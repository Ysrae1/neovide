#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DataRoot,
    [Parameter(Mandatory=$true)][string]$NodePath,
    [Parameter(Mandatory=$true)][ValidateSet('x64','arm64')][string]$Architecture,
    [string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Only this frozen runtime is managed. Never start the adapter or inspect login state.
$receipt=[ordered]@{state='failed';architecture=$Architecture;node_version=$null;adapter_version=$null;
    codex_version=$null;native_pe=$null;locksha=$null;exitcode=$null;ownedpid=$null;checks=@()}
$root=[IO.Path]::GetFullPath((Join-Path $DataRoot 'codex-acp'))
$source=Join-Path $PSScriptRoot 'codex-acp'
if (-not (Test-Path -LiteralPath $source -PathType Container)) { $source=Join-Path $PSScriptRoot '..\payload\codex-acp' }
$cache=$null
function Assert-ACPPlainPath([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ('Linked ACP paths are preserved and not managed: '+$Path)
    }
}
function Invoke-ACPNode([string[]]$Arguments,[string]$Name,[int]$Seconds=20) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$NodePath; $start.WorkingDirectory=$root
    $quoted=@($Arguments|ForEach-Object {
        $value=[regex]::Replace($_,'(\\*)"','$1$1\"')
        '"'+[regex]::Replace($value,'(\\+)$','$1$1')+'"'
    })
    $start.Arguments=$quoted -join ' '; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    foreach ($envName in @($start.EnvironmentVariables.Keys)) {
        if ($envName -match '^(NPM_CONFIG_|NODE_OPTIONS$|NODE_PATH$|NPM_TOKEN$|NODE_AUTH_TOKEN$)') { $start.EnvironmentVariables.Remove($envName) }
    }
    $process=New-Object Diagnostics.Process; $process.StartInfo=$start
    $check=[ordered]@{name=$Name;pid=$null;exitcode=$null;timed_out=$false;output=$null}
    $receipt.checks+=@($check)
    try {
        if (-not $process.Start()) { throw ('Could not start '+$Name) }
        $check.pid=$process.Id
        if ($Name -eq 'npm-ci') { $receipt.ownedpid=$process.Id }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Seconds*1000)) {
            $check.timed_out=$true
            # This is exclusively the child started above; do not stop other Node processes.
            & (Join-Path $env:WINDIR 'System32\taskkill.exe') /PID $process.Id /T /F 2>&1 | Out-Null
            $null=$process.WaitForExit(5000)
        }
        $drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),2000)
        if ($process.HasExited) { $check.exitcode=$process.ExitCode }
        if ($Name -eq 'npm-ci') { $receipt.exitcode=$check.exitcode }
        if ($drained) { $check.output=$stdout.Result+$stderr.Result }
        else { $check.output='Output pipes remained open after the bounded drain.' }
        if ($check.timed_out) { throw [TimeoutException]::new(($Name+' exceeded '+$Seconds+' seconds; partial owned runtime preserved.')) }
        if (-not $drained -or $check.exitcode -ne 0) { throw ($Name+' failed; inspect its receipt output.') }
        return $stdout.Result.Trim()
    } finally { $process.Dispose() }
}
function Test-ACPReady {
    try {
        $adapter=Join-Path $root 'node_modules\@agentclientprotocol\codex-acp'
        $codex=Join-Path $root 'node_modules\@openai\codex'
        $native=Join-Path $root ('node_modules\@openai\codex-win32-'+$Architecture)
        $receipt.adapter_version=(Get-Content -LiteralPath (Join-Path $adapter 'package.json') -Raw|ConvertFrom-Json).version
        $receipt.codex_version=(Get-Content -LiteralPath (Join-Path $codex 'package.json') -Raw|ConvertFrom-Json).version
        $nativeVersion=(Get-Content -LiteralPath (Join-Path $native 'package.json') -Raw|ConvertFrom-Json).version
        if ($receipt.adapter_version -cne '2.2.2' -or $receipt.codex_version -cne '0.160.1' -or $nativeVersion -cne ('0.160.1-win32-'+$Architecture)) { return $false }
        $entry=Join-Path $adapter 'dist\index.js'
        if (-not (Test-Path -LiteralPath $entry -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $codex 'bin\codex.js') -PathType Leaf)) { return $false }
        $triple=if ($Architecture -eq 'arm64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
        $exe=Join-Path $native ('vendor\'+$triple+'\bin\codex.exe')
        $reader=New-Object IO.BinaryReader([IO.File]::OpenRead($exe))
        try {
            if ($reader.ReadUInt16() -ne 0x5a4d) { return $false }
            $null=$reader.BaseStream.Seek(60,[IO.SeekOrigin]::Begin); $offset=$reader.ReadInt32()
            if ($offset -lt 0 -or $offset -gt $reader.BaseStream.Length-6) { return $false }
            $null=$reader.BaseStream.Seek($offset,[IO.SeekOrigin]::Begin)
            if ($reader.ReadUInt32() -ne 0x4550) { return $false }
            $machine=$reader.ReadUInt16(); $receipt.native_pe=('0x{0:x4}' -f $machine)
            $expected=if ($Architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
            if ($machine -ne $expected) { return $false }
        } finally { $reader.Dispose() }
        return $true
    } catch { $receipt['readiness_detail']=$_.Exception.Message; return $false }
}
try {
    $NodePath=[IO.Path]::GetFullPath($NodePath)
    if (-not (Test-Path -LiteralPath $NodePath -PathType Leaf)) { throw 'The explicit official Node executable is missing.' }
    foreach ($file in @('package.json','package-lock.json')) {
        $original=Join-Path $source $file; $target=Join-Path $root $file
        $hash=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($file -eq 'package-lock.json') { $receipt.locksha=$hash }
        if (Test-Path -LiteralPath $root) {
            Assert-ACPPlainPath $root; Assert-ACPPlainPath $target
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) {
                throw ('Existing ACP '+$file+' differs from the frozen payload; preserved.')
            }
        }
    }
    if (-not (Test-Path -LiteralPath $root)) {
        $null=New-Item -ItemType Directory -Path $root -Force
        Copy-Item -LiteralPath (Join-Path $source 'package.json'),(Join-Path $source 'package-lock.json') -Destination $root
    }
    $receipt.node_version=Invoke-ACPNode @('--version') 'node-version'
    if ((Invoke-ACPNode @('-p','process.arch') 'node-architecture') -cne $Architecture) { throw 'Node architecture does not match the requested runtime.' }
    if (Test-ACPReady) { $receipt.state='already_ready'; $receipt.exitcode=0 }
    else {
        if (Test-Path -LiteralPath (Join-Path $root '.npmrc')) { throw 'Existing project npm settings are preserved; refuse to read them.' }
        $npm=Join-Path (Split-Path -Parent $NodePath) 'node_modules\npm\bin\npm-cli.js'
        if (-not (Test-Path -LiteralPath $npm -PathType Leaf)) { throw 'Official Node sibling npm-cli.js is missing.' }
        $cacheRoot=Join-Path $root '.cache'; Assert-ACPPlainPath $cacheRoot
        $cache=Join-Path $cacheRoot ('glow-acp-setup-'+[Guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path $cache -Force
        $user=Join-Path $cache 'empty-user.npmrc'; $global=Join-Path $cache 'empty-global.npmrc'
        [IO.File]::WriteAllText($user,''); [IO.File]::WriteAllText($global,'')
        $receipt['cache']=$cache
        $null=Invoke-ACPNode @($npm,'ci','--ignore-scripts','--no-audit','--no-fund','--include=optional','--registry=https://registry.npmjs.org/',('--userconfig='+$user),('--globalconfig='+$global),('--cache='+$cache)) 'npm-ci' 300
        if ((Get-FileHash -LiteralPath (Join-Path $root 'package-lock.json') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $receipt.locksha) { throw 'npm changed the frozen lock; preserved for inspection.' }
        if (-not (Test-ACPReady)) { throw 'Installed ACP did not pass fixed version, native PE, and JS syntax checks.' }
        $null=Invoke-ACPNode @('--check',(Join-Path $root 'node_modules\@agentclientprotocol\codex-acp\dist\index.js')) 'adapter-syntax'
        $receipt.Remove('readiness_detail')
        $receipt.state='installed'; $receipt.exitcode=0
    }
} catch { $receipt['error']=$_.Exception.Message; throw }
finally {
    if ($EvidenceDirectory) {
        $null=New-Item -ItemType Directory -Path $EvidenceDirectory -Force
        $path=Join-Path $EvidenceDirectory 'acp-setup.json'
        $temporary=$path+'.preparing-'+[Guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText($temporary,($receipt|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary,$path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary,$path) }
    }
    [pscustomobject]$receipt
}
