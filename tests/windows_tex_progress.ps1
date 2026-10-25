#requires -Version 5.1
# Pure progress/scope regression. No downloads, installers, registry or GUI.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh TeX progress-test WorkRoot.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
$utf8=New-Object Text.UTF8Encoding($true)
function Read-TrustedAst([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot $Relative),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
    return $ast
}
$texAst=Read-TrustedAst 'portable/windows/tex/Install-TinyTeX.ps1'
$progress=@($texAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Progress'},$true))
$bounded=@($texAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Bounded'},$true))
if($progress.Count -ne 1 -or $bounded.Count -ne 1){throw 'Expected real TinyTeX progress and process functions.'}
# Use the actual first Invoke-Bounded statement, which must publish the phase
# before starting a process. Execute no native child, installer or download.
$phaseStatement=$bounded[0].Body.EndBlock.Statements[0].Extent.Text
if($phaseStatement -notmatch '^Progress .*\$Name.*\$Name$'){throw 'Invoke-Bounded does not publish the phase before starting work.'}
$parentAst=Read-TrustedAst 'portable/windows/Setup-LaTeX.ps1'
$invoke=@($parentAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.Extent.Text -match '^& .*Install-TinyTeX\.ps1'},$true))
if($invoke.Count -ne 1 -or $invoke[0].Extent.Text -notmatch '-ProgressCallback \(New-DependencyPhaseCallback\)'){throw 'Real LaTeX parent does not wire the progress callback.'}
$childPath=Join-Path $WorkRoot 'Synthetic-TinyTeX.ps1'
$child=@'
param([string]$RunRoot,[scriptblock]$ProgressCallback)
Set-StrictMode -Version Latest
# Deliberately conflicting child values expose script-scope leakage.
$script:DependencyRun=$RunRoot
$script:DependencyStatusPath=Join-Path $RunRoot 'wrong-child-status.json'
$null=New-Item -ItemType Directory -Path $RunRoot
$progress=Join-Path $RunRoot 'progress.log'
$utf8=New-Object Text.UTF8Encoding($false)
__PROGRESS_FUNCTION__
foreach($Name in @('extract-official-archive','tlmgr-self-update','verify-self-update-complete','install-common-packages','compile-unicode-path')){
    __PHASE_STATEMENT__
    if($ProgressCallback){Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $RunRoot) 'status.json') -Destination (Join-Path $RunRoot ($Name+'.json'))}
}
'@
$child=$child.Replace('__PROGRESS_FUNCTION__',$progress[0].Extent.Text).Replace('__PHASE_STATEMENT__',$phaseStatement)
[IO.File]::WriteAllText($childPath,$child,$utf8)
$latexPath=Join-Path $WorkRoot 'Synthetic-LaTeX.ps1'
[IO.File]::WriteAllText($latexPath,@'
param([string]$ChildPath,[string]$RunRoot)
& $ChildPath -RunRoot $RunRoot -ProgressCallback (New-DependencyPhaseCallback)
'@,$utf8)
$setupPath=Join-Path $WorkRoot 'Synthetic-Setup.ps1'
[IO.File]::WriteAllText($setupPath,@'
param([string]$SourceRoot,[string]$WorkRoot,[string]$LatexPath,[string]$ChildPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $SourceRoot 'portable/windows/Dependency-Helpers.ps1')
$script:DependencyStatusPath=Join-Path $WorkRoot 'status.json'
$script:DependencyRun=Join-Path $WorkRoot 'parent-run'
Set-DependencyStatus 'running' 'download' 'Verified TinyTeX.exe' 100 100
Copy-Item -LiteralPath $script:DependencyStatusPath -Destination (Join-Path $WorkRoot 'download-complete.json')
. $LatexPath -ChildPath $ChildPath -RunRoot (Join-Path $WorkRoot 'child-run')
if($script:DependencyRun -cne (Join-Path $WorkRoot 'parent-run') -or $script:DependencyStatusPath -cne (Join-Path $WorkRoot 'status.json')){throw 'Child changed the parent context.'}
Set-DependencyStatus 'running' 'after-tex' 'Parent continued'
'@,$utf8)
& $setupPath -SourceRoot $SourceRoot -WorkRoot $WorkRoot -LatexPath $latexPath -ChildPath $childPath
$baseline=Get-Content -LiteralPath (Join-Path $WorkRoot 'download-complete.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($baseline.downloaded_bytes -ne 100 -or $baseline.total_bytes -ne 100){throw 'Missing full-download baseline.'}
foreach($phase in @('extract-official-archive','tlmgr-self-update','verify-self-update-complete','install-common-packages','compile-unicode-path')){
    $state=Get-Content -LiteralPath (Join-Path $WorkRoot ('child-run/'+$phase+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
    if($state.state -cne 'running' -or $state.phase -cne $phase -or $state.detail -cne ('Running '+$phase) -or $state.downloaded_bytes -ne 0 -or $state.total_bytes -ne 0 -or $state.run_path -cne (Join-Path $WorkRoot 'parent-run')){throw ('Incorrect phase/status/progress/parent path: '+$phase)}
}
if(Test-Path -LiteralPath (Join-Path $WorkRoot 'child-run/wrong-child-status.json')){throw 'Callback wrote to child status path.'}
$final=Get-Content -LiteralPath (Join-Path $WorkRoot 'status.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($final.phase -cne 'after-tex' -or $final.run_path -cne (Join-Path $WorkRoot 'parent-run')){throw 'Parent did not retain status context after child.'}
Write-Output 'PASS actual helper callback across parent dot-source and child invocation; full download becomes running phase with zero bytes and parent run path'
& $childPath -RunRoot (Join-Path $WorkRoot 'standalone-child')
$standalone=Get-Content -LiteralPath (Join-Path $WorkRoot 'standalone-child/progress.log') -Raw -Encoding UTF8
if($standalone -notmatch 'Running verify-self-update-complete' -or (Test-Path -LiteralPath (Join-Path $WorkRoot 'standalone-child/wrong-child-status.json'))){throw 'Standalone progress logging or optional callback failed.'}
Write-Output 'PASS standalone TinyTeX progress remains usable without a callback and keeps original technical log'
. (Join-Path $SourceRoot 'portable/windows/Setup-Locale.ps1')
$script:SetupLanguage='zh-CN'
foreach($phase in @('tlmgr-self-update','verify-self-update-complete')){
    if((Get-SetupPhase $phase) -notmatch '联网' -or (Get-SetupDetail ('Running '+$phase)) -notmatch '联网'){throw ('Missing explicit Chinese online stage: '+$phase)}
}
if((Get-SetupPhase 'verify-tinytex-archive') -cne '校验 TinyTeX 安装文件' -or (Get-SetupPhase 'extract-official-archive') -cne '解压 TinyTeX'){throw 'Archive phases were not localized.'}
if((Get-SetupRole 'pdf') -notmatch '可选外部'){throw 'Optional external viewer role is ambiguous.'}
$script:SetupLanguage='en'
if((Get-SetupDetail 'Running tlmgr-self-update') -cne 'Running tlmgr-self-update'){throw 'English technical detail changed.'}
Write-Output 'PASS Chinese TinyTeX stages identify online updates/checks while technical English stays intact'
@{schema_version=1;state='passed';powershell=$PSVersionTable.PSVersion.ToString();checks=@('real-helper-parent-child-scope','stale-full-download-cleared','parent-run-path','standalone-child','chinese-online-stages');windows_gui_tested=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'receipt.json') -Encoding UTF8
