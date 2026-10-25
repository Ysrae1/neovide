#requires -Version 5.1
<# Maintainer entry. Existing sealed offline builds are read-only inputs. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceStage,
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$')][string]$StackId,
    [string]$Python = 'python.exe',
    [string]$ISCC,
    [string]$Frontend,
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$FrontendSha256,
    [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$FrontendSourceCommit,
    [ValidateSet('clean','dirty','unknown')][string]$FrontendSourceState = 'unknown',
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$FrontendSourceFingerprint,
    [string]$ParserSupplement,
    [ValidateSet('x64','arm64')][string]$Architecture = 'x64'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the core installer on Windows.' }
$Architecture = $Architecture.ToLowerInvariant()
$arm64Stack = $StackId -match '(?:^|[-_.])arm64(?:$|[-_.])'
if ($Architecture -eq 'arm64' -and -not $arm64Stack) { throw 'An ARM64 StackId must contain an arm64 segment so its native plugin profile cannot be shared with x64.' }
if ($Architecture -eq 'x64' -and $arm64Stack) { throw 'An x64 build cannot use an ARM64 StackId. Existing profiles were preserved.' }
if ($Frontend -and -not $FrontendSha256) { throw 'An explicit Frontend requires its expected build SHA256.' }
if (-not $Frontend -and ($FrontendSha256 -or $FrontendSourceCommit -or $FrontendSourceFingerprint -or $PSBoundParameters.ContainsKey('FrontendSourceState'))) {
    throw 'Frontend provenance options require an explicit Frontend artifact.'
}
if (Test-Path -LiteralPath $WorkRoot) { throw 'Use a fresh WorkRoot. Existing files were preserved.' }
$work = [IO.Path]::GetFullPath($WorkRoot)
$null = New-Item -ItemType Directory -Path $work
$stage = Join-Path $work 'stage'
$output = Join-Path $work 'output'
$null = New-Item -ItemType Directory -Path $output
function Quote-CoreArgument([string]$Value) {
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Invoke-CoreBuild([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$Timeout=900) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable; $start.Arguments=(@($Arguments|ForEach-Object {Quote-CoreArgument $_}) -join ' ')
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true; $start.WorkingDirectory=$work
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw ('Unable to start '+$Name) }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout*1000)) {
            # Only this worker's new process tree, never another build/editor.
            $stop=[Diagnostics.Process]::new()
            $stop.StartInfo.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe'
            $stop.StartInfo.Arguments='/PID '+$process.Id+' /T /F'
            $stop.StartInfo.UseShellExecute=$false; $stop.StartInfo.CreateNoWindow=$true
            $stop.StartInfo.RedirectStandardOutput=$true; $stop.StartInfo.RedirectStandardError=$true
            try { $null=$stop.Start();$a=$stop.StandardOutput.ReadToEndAsync();$b=$stop.StandardError.ReadToEndAsync();if(-not $stop.WaitForExit(5000)){$stop.Kill();$null=$stop.WaitForExit(1000)} }
            finally { $stop.Dispose() }
            $null=$process.WaitForExit(5000)
            throw ('Build phase timed out: '+$Name+'. Partial output is preserved in '+$work)
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),2000)) { throw ('Build output did not drain: '+$Name) }
        [IO.File]::WriteAllText((Join-Path $work ($Name+'.log')),($stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()),[Text.UTF8Encoding]::new($false))
        if ($process.ExitCode -ne 0) { throw ('Build phase failed: '+$Name+'. See '+(Join-Path $work ($Name+'.log'))) }
    } finally { $process.Dispose() }
}
$launcher = Join-Path $work 'Glow.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$launcherIcon = Join-Path $SourceStage 'neovide.ico'
if (-not (Test-Path -LiteralPath $launcherIcon -PathType Leaf)) { throw 'The core launcher requires the packaged Neovide Glow icon.' }
$launcherPlatform = 'x64'
$launcherArguments = @('/nologo','/codepage:65001','/target:winexe','/r:System.Windows.Forms.dll','/r:System.Runtime.Serialization.dll',('/win32icon:'+$launcherIcon))
if ($Architecture -eq 'arm64') {
    # AnyCPU alone defaults to x64 emulation on ARM64. The application manifest
    # opts supported Windows versions into native ARM64; earlier systems retain
    # the managed launcher's x64 fallback. Frontend/native payload checks remain
    # strictly ARM64 regardless of this small helper's runtime architecture.
    $launcherPlatform = 'anycpu'
    $launcherManifest = Join-Path $PSScriptRoot 'launcher\GlowLauncher.manifest'
    if (-not (Test-Path -LiteralPath $launcherManifest -PathType Leaf)) { throw 'The ARM64 managed launcher requires its supported-architectures manifest.' }
    $launcherArguments += ('/win32manifest:'+$launcherManifest)
}
$launcherArguments += @(('/platform:'+$launcherPlatform),('/out:'+$launcher),(Join-Path $PSScriptRoot 'launcher\GlowLauncher.cs'))
Invoke-CoreBuild $compiler $launcherArguments 'launcher' 120
$arguments = @('-I','-B','-X','utf8',(Join-Path $PSScriptRoot 'core-package.py'),'--source',$SourceStage,'--destination',$stage,
    '--launcher',$launcher,'--stack-id',$StackId,'--architecture',$Architecture,'--report',(Join-Path $work 'core-size-report.json'))
if ($Frontend) {
    $arguments += @('--frontend',$Frontend,'--frontend-sha256',$FrontendSha256,'--frontend-source-state',$FrontendSourceState)
    if ($FrontendSourceCommit) { $arguments += @('--frontend-source-commit',$FrontendSourceCommit) }
    if ($FrontendSourceFingerprint) { $arguments += @('--frontend-source-fingerprint',$FrontendSourceFingerprint) }
}
if ($ParserSupplement) { $arguments += @('--parser-supplement',$ParserSupplement) }
Invoke-CoreBuild $Python $arguments 'payload' 900
Invoke-CoreBuild $Python @('-I','-B','-X','utf8',(Join-Path $PSScriptRoot 'verify-native.py'),'--stage',$stage,'--architecture',$Architecture,'--report',(Join-Path $work 'native-package.json')) 'native-package' 120
Invoke-CoreBuild (Join-Path $stage 'Glow.exe') @('--launcher-check') 'launcher-check' 60
if (-not $ISCC) { $ISCC = (Get-Command ISCC.exe -ErrorAction Stop).Source }
Invoke-CoreBuild $ISCC @(('/DStageDir='+$stage),('/DOutputDir='+$output),('/DAppVersion='+$Version),('/DTargetArchitecture='+$Architecture),'/DDistribution=core',(Join-Path $PSScriptRoot 'installer.iss')) 'installer' 1200
$artifact = Join-Path $output ('Neovide-Glow-' + $Version + '-Windows-' + $Architecture + '-Core-Setup.exe')
if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw 'Compiler succeeded without the expected core installer.' }
$sizeReport = Get-Content -LiteralPath (Join-Path $work 'core-size-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$receipt = [ordered]@{
    schema_version = 1; state = 'compiled_pending_acceptance'; stack_id = $StackId; architecture = $Architecture
    source_stage = [IO.Path]::GetFullPath($SourceStage)
    source_seal_sha256 = (Get-FileHash -LiteralPath (Join-Path $SourceStage 'bundle-sha256.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    stage = $stage; stage_seal_sha256 = (Get-FileHash -LiteralPath (Join-Path $stage 'bundle-sha256.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    frontend = $sizeReport.frontend
    launcher_sha256 = (Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash.ToLowerInvariant()
    launcher_icon_sha256 = (Get-FileHash -LiteralPath $launcherIcon -Algorithm SHA256).Hash.ToLowerInvariant()
    launcher_platform = $launcherPlatform
    launcher_manifest_sha256 = $null
    launcher_native_arm64_requirement = $null
    launcher_check_exit_code = 0
    native_package_report_sha256 = (Get-FileHash -LiteralPath (Join-Path $work 'native-package.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    artifact = @{path=$artifact; bytes=(Get-Item -LiteralPath $artifact).Length; sha256=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()}
    source_bytes = $sizeReport.source_bytes; core_bytes = $sizeReport.core_bytes
    native_gui_acceptance = 'not_performed_by_packager'; install_acceptance = 'pending'
    completed_utc = [DateTime]::UtcNow.ToString('o')
}
if ($Architecture -eq 'arm64') {
    $receipt.launcher_manifest_sha256 = (Get-FileHash -LiteralPath $launcherManifest -Algorithm SHA256).Hash.ToLowerInvariant()
    $receipt.launcher_native_arm64_requirement = 'Windows 11 24H2+ with .NET Framework 4.8.1'
    $receipt.launcher_runtime_policy = 'native ARM64 where supported by supportedArchitectures; managed x64 fallback on earlier Windows'
}
[IO.File]::WriteAllText((Join-Path $work 'receipt.json'), ($receipt | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
Write-Host ('Core package created in ' + $output + '. GUI/optional dependency acceptance is still required before release.')
