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
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$FrontendSourceFingerprint
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the core installer on Windows.' }
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
$launcher = Join-Path $work 'Glow.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /codepage:65001 /target:winexe /platform:x64 /r:System.Windows.Forms.dll /r:System.Runtime.Serialization.dll ('/out:' + $launcher) (Join-Path $PSScriptRoot 'launcher\GlowLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Unable to compile the core-aware launcher.' }
$arguments = @((Join-Path $PSScriptRoot 'core-package.py'),'--source',$SourceStage,'--destination',$stage,
    '--launcher',$launcher,'--stack-id',$StackId,'--report',(Join-Path $work 'core-size-report.json'))
if ($Frontend) {
    $arguments += @('--frontend',$Frontend,'--frontend-sha256',$FrontendSha256,'--frontend-source-state',$FrontendSourceState)
    if ($FrontendSourceCommit) { $arguments += @('--frontend-source-commit',$FrontendSourceCommit) }
    if ($FrontendSourceFingerprint) { $arguments += @('--frontend-source-fingerprint',$FrontendSourceFingerprint) }
}
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Core payload construction failed.' }
& (Join-Path $stage 'Glow.exe') --launcher-check
if ($LASTEXITCODE -ne 0) { throw 'The core payload failed launcher input validation.' }
if (-not $ISCC) { $ISCC = (Get-Command ISCC.exe -ErrorAction Stop).Source }
& $ISCC ('/DStageDir=' + $stage) ('/DOutputDir=' + $output) ('/DAppVersion=' + $Version) /DDistribution=core (Join-Path $PSScriptRoot 'installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Core installer packaging failed.' }
Write-Host ('Core package created in ' + $output + '. GUI/optional dependency acceptance is still required before release.')
