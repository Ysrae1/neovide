#requires -Version 5.1
<# The installer passes explicit feature switches; a plain invocation is read-only.
   No credentials, remote telemetry, activation, global PATH edits or WSL changes. #>
[CmdletBinding()]
param(
    [string]$Python,
    [switch]$SelectPython,
    [switch]$InstallNotebook,
    [switch]$InstallBase,
    [switch]$InstallLatex,
    [ValidateSet('powershell','git','search','find','yazi','fzf','node','latex','pdf','webview2')]
    [string[]]$InstallTool = @(),
    [switch]$Json,
    [string]$DependencyRoot = (Join-Path $env:LOCALAPPDATA 'NeovideGlow\dependencies'),
    [string]$SelectionRoot = (Join-Path $env:LOCALAPPDATA 'NeovideGlow\dependencies')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($InstallTool -contains 'latex') {
    $InstallLatex=$true
    $InstallTool=@($InstallTool|Where-Object {$_ -ne 'latex'})
}

function Quote-Argument([string]$Value) {
    $quoted = New-Object Text.StringBuilder
    $null = $quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        $count = $slashes
        if ($character -eq '"') { $count = $slashes * 2 + 1 }
        $null = $quoted.Append('\', $count)
        $null = $quoted.Append($character)
        $slashes = 0
    }
    $null = $quoted.Append('\', $slashes * 2)
    $null = $quoted.Append('"')
    return $quoted.ToString()
}

function Probe-Python([string]$Executable,[ValidateRange(1,120)][int]$TimeoutSeconds=60) {
    if (-not $Executable -or -not [IO.Path]::IsPathRooted($Executable) -or
        -not (Test-Path -LiteralPath $Executable -PathType Leaf) -or
        $Executable -like '*\Microsoft\WindowsApps\*') { return $null }
    $program = @'
import json, pathlib, sys, sysconfig, struct
implementation=sys.implementation.name
version=list(sys.version_info[:3])
platform=sysconfig.get_platform()
bits=8*struct.calcsize('P')
compatible=implementation=='cpython' and version[:2]==[3,12] and platform=='win-amd64' and bits==64
missing=[]
imports_checked=False
if compatible:
    import importlib
    for module in ['pynvim','jupyter_client','ipykernel','jupytext','nbformat','PIL','matplotlib','pylatexenc']:
        print('starting '+module,file=sys.stderr,flush=True)
        try:
            importlib.import_module(module)
            print('imported '+module,file=sys.stderr,flush=True)
        except Exception as error:
            missing.append(module)
            print('failed '+module+': '+type(error).__name__,file=sys.stderr,flush=True)
    imports_checked=True
scripts=pathlib.Path(sysconfig.get_path('scripts'))
print(json.dumps({'python':sys.executable,'implementation':implementation,'version':version,'platform':platform,'bits':bits,'missing':missing,'imports_checked':imports_checked,'jupytext':str(scripts/'jupytext.exe'),'latex2text':str(scripts/'latex2text.exe')}))
'@
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = '-I -B -c ' + (Quote-Argument $program)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['PYTHONNOUSERSITE'] = '1'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $channels=@()
    $diagnostic=[ordered]@{python=$Executable;status='unknown';seconds=0;pid=$null;exit_code=$null;
        timed_out=$false;timeout_seconds=$TimeoutSeconds;imports_checked=$false;output_drain_complete=$false;stdout='';stderr='';
        stdout_truncated=$false;stderr_truncated=$false;error=$null}
    if (-not (Get-Variable PythonProbeDiagnostics -Scope Script -ErrorAction SilentlyContinue)) { $script:PythonProbeDiagnostics=@() }
    try {
        if (-not $process.Start()) { throw 'Python probe could not start.' }
        $diagnostic.pid=$process.Id
        # Poll bounded reads on this runspace. Keep partial output even when a
        # child inherits a pipe; neither output storage nor handle drain is unbounded.
        $channels=@($process.StandardOutput,$process.StandardError)|ForEach-Object {
            $buffer=New-Object char[] 8192
            @{reader=$_;buffer=$buffer;text=(New-Object Text.StringBuilder);
                task=$_.ReadAsync($buffer,0,$buffer.Length);ended=$false;failed=$false;truncated=$false}
        }
        $readOutput={
            foreach ($channel in $channels) {
                for ($round=0; $round -lt 16 -and -not $channel.ended -and $channel.task.IsCompleted; $round++) {
                    try {
                        $count=$channel.task.GetAwaiter().GetResult()
                        if ($count -eq 0) { $channel.ended=$true; continue }
                        $null=$channel.text.Append($channel.buffer,0,$count)
                        if ($channel.text.Length -gt 32KB) {
                            $null=$channel.text.Remove(0,$channel.text.Length-32KB);$channel.truncated=$true
                        }
                        $channel.task=$channel.reader.ReadAsync($channel.buffer,0,$channel.buffer.Length)
                    } catch {
                        $channel.ended=$true;$channel.failed=$true
                        $channel['error']=$_.Exception.Message
                    }
                }
            }
        }
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited) {
            & $readOutput
            if ([DateTime]::UtcNow -ge $deadline) { $diagnostic.timed_out=$true; break }
            $null=$process.WaitForExit(50)
        }
        if ($diagnostic.timed_out -and -not $process.HasExited) {
            # Only this probe's new process tree; do not touch existing kernels.
            $killer=New-Object Diagnostics.Process
            $killer.StartInfo.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe'
            $killer.StartInfo.Arguments='/PID '+$diagnostic.pid+' /T /F'
            $killer.StartInfo.UseShellExecute=$false;$killer.StartInfo.CreateNoWindow=$true
            $killer.StartInfo.RedirectStandardOutput=$true;$killer.StartInfo.RedirectStandardError=$true
            try {
                if (-not $killer.Start()) { throw 'Could not start owned-tree termination.' }
                $killOut=$killer.StandardOutput.ReadToEndAsync();$killErr=$killer.StandardError.ReadToEndAsync()
                if (-not $killer.WaitForExit(2000)) { $killer.Kill();$null=$killer.WaitForExit(1000) }
                if ($killer.HasExited -and $killer.ExitCode -ne 0) { $diagnostic['stop_error']='Owned-tree termination returned '+$killer.ExitCode }
            } catch { $diagnostic['stop_error']=$_.Exception.Message }
            finally { $killer.Dispose() }
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill();$null=$process.WaitForExit(1000) }
                catch { $diagnostic['stop_error']=$_.Exception.Message }
            }
        }
        $drainDeadline=[DateTime]::UtcNow.AddSeconds(2)
        do {
            & $readOutput
            $diagnostic.output_drain_complete=@($channels|Where-Object {-not $_.ended -or $_.failed}).Count -eq 0
            if (@($channels|Where-Object {-not $_.ended}).Count -eq 0 -or [DateTime]::UtcNow -ge $drainDeadline) { break }
            Start-Sleep -Milliseconds 25
        } while ($true)
        $diagnostic.stdout=$channels[0].text.ToString();$diagnostic.stderr=$channels[1].text.ToString()
        $diagnostic.stdout_truncated=$channels[0].truncated;$diagnostic.stderr_truncated=$channels[1].truncated
        $readErrors=@($channels|Where-Object {$_.failed}|ForEach-Object {$_.error})
        if ($readErrors.Count) { $diagnostic['output_error']=$readErrors -join '; ' }
        if ($process.HasExited) { $diagnostic.exit_code=$process.ExitCode }
        if ($diagnostic.timed_out) { throw ('Python probe exceeded its '+$TimeoutSeconds+'-second budget; interpreter availability is unknown.') }
        if (-not $diagnostic.output_drain_complete) { throw 'Python output handles did not drain within 2 seconds; interpreter availability is unknown.' }
        if ($diagnostic.exit_code -ne 0) { throw ('Python probe exited with code '+$diagnostic.exit_code+'.') }
        if ($diagnostic.stdout_truncated) { throw 'Python probe output exceeded 32 KiB; its result could not be verified.' }
        $result=$diagnostic.stdout|ConvertFrom-Json
        # This release's Windows wheels are validated with CPython 3.12.
        $compatible = $result.implementation -eq 'cpython' -and $result.version[0] -eq 3 -and $result.version[1] -eq 12 -and $result.platform -eq 'win-amd64' -and $result.bits -eq 64
        $diagnostic.imports_checked=[bool]$result.imports_checked
        if ($compatible -and -not $diagnostic.imports_checked) { throw 'Compatible Python did not complete its dependency imports; interpreter availability is unknown.' }
        $ready = $compatible -and $diagnostic.imports_checked -and @($result.missing).Count -eq 0 -and
            (Test-Path -LiteralPath $result.jupytext -PathType Leaf) -and
            (Test-Path -LiteralPath $result.latex2text -PathType Leaf)
        $diagnostic.status=if (-not $compatible) {'incompatible'} elseif ($ready) {'ready'} else {'missing'}
        return [pscustomobject]@{ python = $result.python; version = ($result.version -join '.');
            compatible = $compatible; ready = [bool]$ready; missing = @($result.missing); imports_checked = $diagnostic.imports_checked;
            jupytext = $result.jupytext; latex2text = $result.latex2text }
    }
    catch { $diagnostic.error=$_.Exception.Message;return $null }
    finally {
        $diagnostic.seconds=[Math]::Round($watch.Elapsed.TotalSeconds,3)
        $script:PythonProbeDiagnostics+=@([pscustomobject]$diagnostic)
        foreach ($channel in $channels) { try { $channel.reader.Close() } catch {} }
        $process.Dispose()
    }
}

function Assert-NotebookProbeKnown($Selected,[bool]$Requested) {
    if (-not $Requested -or ($Selected -and $Selected.ready)) { return }
    $unknown=@($script:PythonProbeDiagnostics|Where-Object {$_.status -eq 'unknown'})
    if ($unknown.Count) {
        $details=@($unknown|ForEach-Object {$_.python+': '+$_.error}) -join [Environment]::NewLine
        throw ('Existing Python inspection was inconclusive; no dependencies were installed. '+
            'Inspect python_probes in detection JSON or python-probes.json in the setup run before retrying. '+
            [Environment]::NewLine+$details)
    }
}

function Save-Selection($Selected) {
    if (-not $Selected.ready) { throw 'Python did not pass the Notebook import checks; no selection was saved.' }
    # Environment storage can be customized; the stable launcher selection
    # remains at its documented per-user location.
    $selectionRoot = $SelectionRoot
    $null = New-Item -ItemType Directory -Path $selectionRoot -Force
    $receipt = Join-Path $selectionRoot 'selected.json'
    if (Test-Path -LiteralPath $receipt) {
        $backup = $receipt + '.before-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffff')
        Copy-Item -LiteralPath $receipt -Destination $backup
    }
    $contents = @{ schema_version = 1; python = $Selected.python; jupytext = $Selected.jupytext;
        latex2text = $Selected.latex2text; python_version = $Selected.version; tool_paths=@($script:SelectedToolPaths) }
    $temporary = $receipt + '.preparing-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, ($contents | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $receipt) { [IO.File]::Replace($temporary, $receipt, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $receipt) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}


. (Join-Path $PSScriptRoot 'WebView2.ps1')
. (Join-Path $PSScriptRoot 'Dependency-Helpers.ps1')
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dependencies.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$assetLock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'system-assets.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $assetLock.schema_version -ne 1) { throw 'Unsupported dependency manifest.' }
$script:SelectedToolPaths=@(Get-DependencySelectedPaths (Join-Path $SelectionRoot 'selected.json'))
$script:DependencyChecks=@(); $script:DependencyRun=$null; $script:PythonProbeDiagnostics=@()
$dependencyMutex=$null; $mutexAcquired=$false
$mutating=$InstallBase -or $InstallNotebook -or $SelectPython -or $InstallLatex -or $InstallTool.Count -gt 0
$mapping=@{search='rg';find='fd';yazi='yazi';fzf='fzf';git='git'}
$minimumVersions=@{search='14.0';find='10.0';yazi='26.5.6';fzf='0.65.0';git='2.30.0'}
function Find-DependencyCommand([string]$Role,[string]$Name) {
    $command=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (-not $mapping.ContainsKey($Role) -or (Test-DependencyCommand $command.Source $minimumVersions[$Role]))) { return $command.Source }
    foreach ($directory in $script:SelectedToolPaths) {
        $candidate=Join-Path $directory $Name
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            (-not $mapping.ContainsKey($Role) -or (Test-DependencyCommand $candidate $minimumVersions[$Role]))) { return $candidate }
    }
    if ($mapping.ContainsKey($Role)) {
        $asset=$assetLock.assets.($mapping[$Role])
        $payload=Join-Path $DependencyRoot ('programs-v1\'+$mapping[$Role]+'-'+$asset.version+'\payload')
        if (Test-Path -LiteralPath $payload -PathType Container) {
            $found=@(Get-ChildItem -LiteralPath $payload -Recurse -File -Filter $Name)
            if ($Role -eq 'git') { $found=@($found|Where-Object {$_.FullName -like '*\cmd\git.exe'}) }
            if ($found.Count -eq 1) { return $found[0].FullName }
        }
    }
    if ($Role -eq 'latex') {
        foreach ($tiny in @((Join-Path $env:APPDATA 'TinyTeX\bin\windows\xelatex.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\NeovideGlow-TinyTeX\bin\windows\xelatex.exe'))) {
            if (Test-Path -LiteralPath $tiny -PathType Leaf) { return $tiny }
        }
    }
    return $null
}
function Test-DependencyCommand([string]$Executable,[string]$MinimumVersion='0.0') {
    if (-not $Executable) { return $false }
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable; $start.Arguments='--version'; $start.UseShellExecute=$false
    $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$start
    try {
        if (-not $process.Start()) { return $false }
        $out=$process.StandardOutput.ReadToEndAsync(); $err=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) { $process.Kill(); $process.WaitForExit(); return $false }
        $text=$out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { return $false }
        $match=[regex]::Match($text,'(?<![0-9])([0-9]+\.[0-9]+(?:\.[0-9]+)?)')
        if (-not $match.Success) { return $false }
        return ([Version]$match.Groups[1].Value) -ge ([Version]$MinimumVersion)
    } catch { return $false } finally { $process.Dispose() }
}
$webview2=Get-GlowWebView2Runtime
$tools=@($manifest.tools|ForEach-Object {
    if ($_.role -eq 'webview2') {
        [pscustomobject]@{role=$_.role;purpose=$_.purpose;package=$_.package;available=$webview2.available;
            path=$null;version=$webview2.version;status=$webview2.status;detection=$webview2.detection;download_bytes=$assetLock.assets.webview2.download_size}
        return
    }
    $path=Find-DependencyCommand $_.role $_.command
    $available=[bool]$path
    # Only CLI base dependencies have a safe, specified --version contract.
    if ($mapping.ContainsKey($_.role)) { $available=Test-DependencyCommand $path $minimumVersions[$_.role] }
    $bytes=$null
    if ($mapping.ContainsKey($_.role)) { $bytes=$assetLock.assets.($mapping[$_.role]).download_size }
    [pscustomobject]@{role=$_.role;purpose=$_.purpose;package=$_.package;available=[bool]$available;path=$path;download_bytes=$bytes}
})
$candidates=@()
if ($Python) { $candidates+=[IO.Path]::GetFullPath($Python) }
else {
    $selection=Join-Path $SelectionRoot 'selected.json'
    if (Test-Path -LiteralPath $selection -PathType Leaf) {
        try {
            $prior=Get-Content -LiteralPath $selection -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($prior.PSObject.Properties['python']) { $candidates+=$prior.python }
        } catch { Write-Warning 'Previous dependency selection could not be read; existing bytes were preserved.' }
    }
    $candidates+=Join-Path $DependencyRoot 'notebook-v1\Scripts\python.exe'
    $candidates+=Join-Path $env:LOCALAPPDATA 'Programs\NeovideGlow-Python312\python.exe'
    $candidates+=Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
    foreach ($name in @('python.exe','python3.exe')) {
        $candidates+=@(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue|ForEach-Object {$_.Source})
    }
    foreach ($relative in @('anaconda3\python.exe','miniconda3\python.exe','miniforge3\python.exe')) {
        $candidates+=Join-Path $env:USERPROFILE $relative
    }
    $jupyterRoots=@((Join-Path $env:APPDATA 'jupyter'),(Join-Path $env:PROGRAMDATA 'jupyter'))
    if ($env:JUPYTER_DATA_DIR) { $jupyterRoots+=$env:JUPYTER_DATA_DIR }
    if ($env:JUPYTER_PATH) { $jupyterRoots+=@($env:JUPYTER_PATH -split [IO.Path]::PathSeparator) }
    $candidates+=@(Get-JupyterPythonCandidates $jupyterRoots)
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
            $key=$null; $baseKey=$null
            try {
                $baseKey=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                $key=$baseKey.OpenSubKey('Software\Python\PythonCore\3.12\InstallPath')
                if ($key) { $value=$key.GetValue('ExecutablePath',$null); if (-not $value) { $value=Join-Path $key.GetValue('') 'python.exe' }; $candidates+=$value }
            } catch { } finally { if ($key) {$key.Dispose()}; if ($baseKey) {$baseKey.Dispose()} }
        }
    }
}
$interpreters=@($candidates|Select-Object -Unique|ForEach-Object {$probe=Probe-Python $_; if ($probe) {$probe}})
$selected=$interpreters|Where-Object {$_.ready}|Select-Object -First 1
$base=$interpreters|Where-Object {$_.compatible}|Select-Object -First 1
# Always show the detection result before any network request or installation.
$tools|Format-Table role,available,@{Label='Download';Expression={if ($_.available) {'reuse'} elseif ($_.download_bytes) {'{0:N1} MiB' -f ($_.download_bytes/1MB)} else {'provider size'}}},path -AutoSize|Out-Host
$interpreters|Format-Table version,compatible,ready,python -AutoSize|Out-Host
$script:PythonProbeDiagnostics|Where-Object {$_.status -eq 'unknown'}|Format-Table status,seconds,exit_code,timed_out,python,error -AutoSize|Out-Host
if ($InstallBase) { Write-Host 'Base: reuse working tools; download only missing search, find, Yazi, fzf, Git and WebView2.' }
if ($InstallNotebook) {
    if ($selected) { Write-Host ('Notebook: reusing complete environment '+$selected.python) }
    elseif (@($script:PythonProbeDiagnostics|Where-Object {$_.status -eq 'unknown'}).Count) { Write-Host 'Notebook: existing Python inspection is unknown; setup will stop before installing dependencies.' }
    elseif ($base) { Write-Host ('Notebook: reuse CPython '+$base.version+'; download packages into a separate environment (package size is resolved by pip).') }
    else { Write-Host ('Notebook: download official CPython 3.12 x64 ('+[Math]::Round($assetLock.assets.python.download_size/1MB,1)+' MiB), then packages into a separate environment.') }
}
if ($InstallLatex) { Write-Host 'LaTeX: reuse a verified complete TeX installation; otherwise TinyTeX (70.3 MiB) plus signed TeX packages and Git/GnuPG if missing.' }
try {
    if ($mutating) {
        $dependencyMutex=New-Object Threading.Mutex($false,'Local\NeovideGlowDependenciesV1')
        try { $mutexAcquired=$dependencyMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $mutexAcquired=$true }
        if (-not $mutexAcquired) { throw 'Another Glow dependency setup is running. Existing work was preserved; wait for it to finish.' }
        $script:DependencyRun=Join-Path $DependencyRoot ('runs\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffff'))
        $null=New-Item -ItemType Directory -Path $script:DependencyRun -Force
        Write-Host ('Setup log: '+$script:DependencyRun)
        Write-DependencyJson (Join-Path $script:DependencyRun 'python-probes.json') @($script:PythonProbeDiagnostics)
    }
    Assert-NotebookProbeKnown $selected ([bool]($InstallNotebook -or $SelectPython))
    $roles=@($InstallTool)
    if ($InstallBase) { $roles+=@('search','find','yazi','fzf','git','webview2') }
    if ($InstallLatex) { $roles+=@('git') }
    foreach ($role in @($roles|Select-Object -Unique)) {
        $tool=$tools|Where-Object {$_.role -eq $role}|Select-Object -First 1
        if ($tool.available) { Write-Host ('Reusing '+$role); continue }
        if ($mapping.ContainsKey($role)) {
            $assetName=$mapping[$role]; $asset=$assetLock.assets.$assetName
            Write-Host ('Missing '+$role+': official download '+[Math]::Round($asset.download_size/1MB,1)+' MiB; existing versions are preserved.')
            $tool.path=Install-DependencyTool $assetName $asset
            $tool.available=$true
        } elseif ($role -eq 'webview2') {
            Write-Host 'Missing WebView2: official 1.8 MiB bootstrapper; Microsoft supplies the current device runtime download/progress.'
            if ($webview2.status -eq 'unknown') { throw 'WebView2 registration could not be read. Existing runtime state was preserved.' }
            $installer=Get-DependencyAsset $assetLock.assets.webview2
            $signature=Get-AuthenticodeSignature -LiteralPath $installer
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Microsoft Corporation*') { throw 'The locked WebView2 bootstrapper does not have a valid Microsoft signature.' }
            $null=Invoke-DependencyProcess $installer @('/install') 'install-WebView2' 600
            $deadline=[DateTime]::UtcNow.AddSeconds(90)
            do {
                $webview2=Get-GlowWebView2Runtime
                if ($webview2.available) { break }
                Start-Sleep -Seconds 1
            } while ([DateTime]::UtcNow -lt $deadline)
            if (-not $webview2.available) { throw 'WebView2 did not produce a valid Evergreen registration; it was not marked available.' }
            $tool.available=$true; $tool.version=$webview2.version; $tool.status=$webview2.status
        } else {
            $winget=Get-Command winget.exe -CommandType Application -ErrorAction Stop
            # This exact selected package only. Microsoft/App Installer verifies
            # its manifest hash; license/elevation prompts remain interactive.
            & $winget.Source install --id $tool.package --exact --source winget --no-upgrade --interactive
            if ($LASTEXITCODE -ne 0) { throw ('System package installation was not completed: '+$role) }
            $spec=$manifest.tools|Where-Object {$_.role -eq $role}|Select-Object -First 1
            $tool.path=Find-DependencyCommand $role $spec.command; $tool.available=[bool]$tool.path
            if (-not $tool.available) { throw ('New '+$role+' command is not available in this session. Reopen setup to detect it before use.') }
        }
    }
    foreach ($tool in $tools) {
        if ($tool.available -and $tool.path) { $script:SelectedToolPaths+=Split-Path -Parent $tool.path }
    }
    $git=$tools|Where-Object {$_.role -eq 'git' -and $_.available}|Select-Object -First 1
    if ($git) {
        $helpers=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $git.path) '..\usr\bin'))
        if (Test-Path -LiteralPath (Join-Path $helpers 'file.exe')) { $script:SelectedToolPaths+=$helpers }
    }
    if ($InstallNotebook -and -not $selected) {
        if (-not $base) { $base=Install-DependencyPython $assetLock.assets.python }
        $environment=Join-Path $DependencyRoot 'notebook-v1'
        $requirements=Join-Path $PSScriptRoot 'notebook-requirements.txt'
        $requirementsSha=(Get-FileHash -LiteralPath $requirements -Algorithm SHA256).Hash.ToLowerInvariant()
        Initialize-DependencyDirectory $environment ('glow-notebook-v1-'+$requirementsSha)
        $null=Invoke-DependencyProcess $base.python @('-I','-m','venv',$environment) 'prepare-Notebook-environment' 120
        $privatePython=Join-Path $environment 'Scripts\python.exe'
        $null=Invoke-DependencyProcess $privatePython @('-I','-m','pip','--isolated','install','--index-url','https://pypi.org/simple','--disable-pip-version-check','--only-binary=:all:','-r',$requirements) 'install-Notebook-packages' 1200
        $null=Invoke-DependencyProcess $privatePython @('-I','-m','pip','--isolated','install','--index-url','https://pypi.org/simple','--disable-pip-version-check','--require-hashes','-r',(Join-Path $PSScriptRoot 'latex-requirements.lock')) 'install-LaTeX-text-converter' 180
        $selected=Probe-Python $privatePython
        if (-not $selected -or -not $selected.ready) { throw 'Installed Notebook dependencies failed import validation; nothing was selected.' }
        $interpreters+=@($selected)
    }
    if ($InstallLatex) {
        # Keep the process helper's script-scoped run/checks in this setup scope.
        . (Join-Path $PSScriptRoot 'Setup-LaTeX.ps1') -DependencyRoot $DependencyRoot -RunRoot (Join-Path $script:DependencyRun 'tex') -ToolPaths $script:SelectedToolPaths
        if (-not $?) { throw 'LaTeX setup did not pass.' }
        $texBin=Join-Path $env:APPDATA 'TinyTeX\bin\windows'
        $texSelection=Join-Path $script:DependencyRun 'tex\selected.json'
        if (Test-Path -LiteralPath $texSelection) { $texBin=(Get-Content -LiteralPath $texSelection -Raw|ConvertFrom-Json).bin }
        $script:SelectedToolPaths+=$texBin
        $texTool=$tools|Where-Object {$_.role -eq 'latex'}|Select-Object -First 1
        $texTool.path=Join-Path $texBin 'xelatex.exe'; $texTool.available=Test-Path -LiteralPath $texTool.path -PathType Leaf
    }
    $script:SelectedToolPaths=@($script:SelectedToolPaths|Select-Object -Unique)
    if ($SelectPython -or $InstallNotebook) {
        if (-not $selected) { throw 'No compatible complete Notebook environment was found.' }
        Save-Selection $selected
    } elseif ($mutating) {
        $selectionRoot=$SelectionRoot
        $null=New-Item -ItemType Directory -Path $selectionRoot -Force
        $selection=Join-Path $selectionRoot 'selected.json'
        $record=@{schema_version=1;tool_paths=$script:SelectedToolPaths}
        if (Test-Path -LiteralPath $selection) {
            $previous=Get-Content -LiteralPath $selection -Raw -Encoding UTF8|ConvertFrom-Json
            foreach ($property in $previous.PSObject.Properties) { if ($property.Name -notin @('schema_version','tool_paths')) { $record[$property.Name]=$property.Value } }
            Copy-Item -LiteralPath $selection -Destination ($selection+'.before-'+[Guid]::NewGuid().ToString('N'))
        }
        Write-DependencyJson $selection $record
    }
    $report=[pscustomobject]@{schema_version=1;status='passed';tools=$tools;python=$interpreters;python_probes=@($script:PythonProbeDiagnostics);notebook_ready=[bool]$selected;selection_saved=[bool]$mutating;webview2=$webview2;latex_checked=[bool]$InstallLatex;latex_ready=[bool]$InstallLatex;checks=$script:DependencyChecks}
    if ($mutating) {
        Write-DependencyJson (Join-Path $script:DependencyRun 'python-probes.json') @($script:PythonProbeDiagnostics)
        Write-DependencyJson (Join-Path $script:DependencyRun 'receipt.json') $report
    }
    if ($Json) { $report|ConvertTo-Json -Depth 8 }
    else {
        if ($mutating) { Write-Host 'Selected dependencies passed. Reopen Glow to use them.' }
        else { Write-Host 'Detection only. The installer installs missing base tools and selected Notebook / LaTeX features.' }
        Write-Host 'Existing Python/Conda environments are preserved. No global PATH or file associations were rewritten.'
    }
} catch {
    $failure=$_
    $diagnosticWriteErrors=@()
    if ($script:DependencyRun) {
        try { Write-DependencyJson (Join-Path $script:DependencyRun 'python-probes.json') @($script:PythonProbeDiagnostics) }
        catch {
            $diagnosticWriteErrors+=('python-probes.json: '+$_.Exception.Message)
            Write-Warning ('Could not save Python diagnostics: '+$_.Exception.Message+'. Original setup error: '+$failure.Exception.Message) -WarningAction Continue
        }
        try {
            Write-DependencyJson (Join-Path $script:DependencyRun 'receipt.json') @{schema_version=1;status='failed';error=$failure.Exception.Message;
                python_probes=@($script:PythonProbeDiagnostics);checks=$script:DependencyChecks;diagnostic_write_errors=$diagnosticWriteErrors}
        } catch { Write-Warning ('Could not save setup failure receipt: '+$_.Exception.Message+'. Original setup error: '+$failure.Exception.Message) -WarningAction Continue }
    }
    throw $failure
} finally {
    if ($mutexAcquired) { $dependencyMutex.ReleaseMutex() }
    if ($dependencyMutex) { $dependencyMutex.Dispose() }
}
