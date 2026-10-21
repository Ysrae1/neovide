#requires -Version 5.1
<# Native process-boundary regression. Only test-owned PowerShell children and
   synthetic files; no installers, network requests, user config or GUI. #>
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh process-test WorkRoot'}
$null=New-Item -ItemType Directory -Path $WorkRoot
. (Join-Path $SourceRoot 'portable\windows\Dependency-Helpers.ps1')
$script:DependencyRun=$WorkRoot;$script:DependencyChecks=@()
# Import trusted definitions without executing either installer body.
function Import-Definition([string]$Path,[string]$Name) {
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors|Out-String)}
 $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name},$true)
 if(-not $definition){throw ('Missing definition: '+$Name)}
 return $definition.Extent.Text
}
. ([scriptblock]::Create((Import-Definition (Join-Path $SourceRoot 'portable\windows\Setup-Dependencies.ps1') 'Quote-Argument')))
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Child-Arguments([string]$Program) {
 return @('-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Program)))
}
$output=Invoke-DependencyProcess $ps (Child-Arguments '[Console]::Out.WriteLine("child success");exit 0') 'success' 30
if($output -notlike '*child success*' -or $script:DependencyChecks[-1].exit_code -ne 0){throw 'Successful child changed behavior'}
$failed=$false
try{$null=Invoke-DependencyProcess $ps (Child-Arguments '[Console]::Out.WriteLine("child failure evidence");exit 7') 'failure' 30}catch{$failed=$true}
if(-not $failed -or $script:DependencyChecks[-1].exit_code -ne 7 -or [IO.File]::ReadAllText((Join-Path $WorkRoot 'failure.log')) -notlike '*child failure evidence*'){throw 'Failed child lost its exit code or log'}
$timedOut=$false
try{$null=Invoke-DependencyProcess $ps (Child-Arguments '[Console]::Out.WriteLine("before timeout");[Console]::Out.Flush();Start-Sleep -Seconds 60') 'timeout' 8}catch{$timedOut=$_.Exception.GetBaseException() -is [TimeoutException]}
$check=$script:DependencyChecks[-1]
if(-not $timedOut -or -not $check.timed_out -or -not $check.pid -or [IO.File]::ReadAllText($check.log) -notlike '*before timeout*'){throw 'Timeout lost its type, process identity or partial output'}
Write-Output 'PASS dependency process success, exit failure and timeout diagnostics'

$logs=Join-Path $WorkRoot 'tex-logs';$null=New-Item -ItemType Directory -Path $logs
$utf8=New-Object Text.UTF8Encoding($false);$RunRoot=$WorkRoot;$receipt=@{checks=@()}
function Progress([string]$Message){}
function Save-Receipt{[IO.File]::WriteAllText((Join-Path $WorkRoot 'tex-receipt.json'),($receipt|ConvertTo-Json -Depth 6),$utf8)}
. ([scriptblock]::Create((Import-Definition (Join-Path $SourceRoot 'portable\windows\tex\Install-TinyTeX.ps1') 'Invoke-Bounded')))
$output=Invoke-Bounded $ps (Child-Arguments '[Console]::Out.WriteLine("tex success");exit 0') 'tex-success' 30
if($output -notlike '*tex success*' -or $receipt.checks[-1].exit_code -ne 0){throw 'TeX success changed behavior'}
$timedOut=$false
try{$null=Invoke-Bounded $ps (Child-Arguments '[Console]::Out.WriteLine("tex timeout evidence");[Console]::Out.Flush();Start-Sleep -Seconds 60') 'tex-timeout' 8}catch{$timedOut=$_.Exception.GetBaseException() -is [TimeoutException]}
$check=$receipt.checks[-1]
if(-not $timedOut -or -not $check.timed_out -or -not $check.pid -or [IO.File]::ReadAllText($check.log) -notlike '*tex timeout evidence*'){throw 'TeX timeout lost its diagnostics'}
Write-Output 'PASS TeX process success and bounded timeout retain output and receipt'

$fake=Join-Path $WorkRoot 'synthetic-tex-bin';$null=New-Item -ItemType Directory -Path $fake
foreach($name in @('xelatex.exe','latexmk.exe','synctex.exe')){[IO.File]::WriteAllText((Join-Path $fake $name),'not executed')}
$global:GlowDependencyTestDownloads=0
function Get-DependencyAsset($Asset){$global:GlowDependencyTestDownloads++;throw 'Unexpected fallback download'}
function Invoke-DependencyProcess{throw [TimeoutException]::new('Controlled uncertain existing-TeX validation')}
$savedPath=$env:PATH;$env:PATH=$fake+';'+$savedPath
$stopped=$false
try{
 try{& (Join-Path $SourceRoot 'portable\windows\Setup-LaTeX.ps1') -DependencyRoot (Join-Path $WorkRoot 'unused-dependencies') -RunRoot (Join-Path $WorkRoot 'tex-timeout-no-fallback')}
 catch{$stopped=$_.Exception.Message -like '*Existing TeX validation did not finish*'}
}finally{$env:PATH=$savedPath}
if(-not $stopped -or $global:GlowDependencyTestDownloads -ne 0){throw 'Uncertain existing TeX validation triggered a replacement/download'}
Write-Output 'PASS existing TeX timeout preserves the environment without fallback installation'
@{schema_version=1;state='passed';checks=@('process-success','process-exit-failure-log','process-timeout-log','tex-process-success','tex-process-timeout-log','existing-tex-timeout-no-fallback')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $WorkRoot 'receipt.json') -Encoding UTF8
