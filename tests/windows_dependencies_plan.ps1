#requires -Version 5.1
# Synthetic planning/status regression: no downloads, installers, registry or user config.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $SourceRoot 'portable\windows\Dependency-Helpers.ps1')
# Import the actual feature-to-tool selection without executing discovery/setup.
$tokens=$null;$errors=$null
$setupAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'portable\windows\Setup-Dependencies.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$roleDefinition=@($setupAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-RequestedDependencyRoles'
},$true))
if($roleDefinition.Count -ne 1){throw 'Expected the real dependency-role selection function.'}
. ([scriptblock]::Create($roleDefinition[0].Extent.Text))
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh plan-test WorkRoot.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
$deps=Join-Path $WorkRoot 'never-created-dependencies'
$assets=[pscustomobject]@{}
foreach($name in @('rg','git','webview2','python','tinytex')){
 $assets|Add-Member NoteProperty $name ([pscustomobject]@{filename=($name+'.zip');download_size=100L;sha256=('0'*64)})
}
$tools=@(
 [pscustomobject]@{role='search';available=$false;path=$null},
 [pscustomobject]@{role='git';available=$true;path='C:\existing\git.exe'},
 [pscustomobject]@{role='webview2';available=$false;path=$null;status='not_detected'},
 [pscustomobject]@{role='pdf';available=$false;path=$null},
 [pscustomobject]@{role='latex';available=$true;path='C:\existing\xelatex.exe'})
$plan=New-DependencyPlan -Tools $tools -Assets $assets -Root $deps -Roles @('search','git','webview2','pdf') -Notebook $true -Latex $true -Selected $null -Base $null -UnknownPython $false
if((Test-Path -LiteralPath $deps) -or $plan.known_download_bytes -ne 300 -or @($plan.items).Count -ne 6){throw 'Planning changed disk or lost selected downloads/features.'}
foreach($item in $plan.items){foreach($key in @('role','status','reuse_path','download_bytes','download_note')){if(-not $item.PSObject.Properties[$key]){throw ('Missing fixed plan field: '+$key)}}}
if(@($plan.dynamic_downloads).Count -ne 5){throw 'Provider/runtime/pip/TeX download uncertainty was hidden.'}
Write-Output 'PASS selected plan is read-only, preserves reuse paths and separates known/provider download sizes'
$latexRoles=@(Get-RequestedDependencyRoles -Tools @() -Base $false -Latex $true)
if($latexRoles -notcontains 'git' -or $latexRoles -notcontains 'webview2' -or $latexRoles -contains 'pdf'){throw 'LaTeX-only setup must select Git and embedded WebView2, without requesting an external viewer.'}
$combinedRoles=@(Get-RequestedDependencyRoles -Tools @() -Base $true -Latex $true)
if($combinedRoles -contains 'pdf' -or @($combinedRoles|Where-Object {$_ -eq 'git'}).Count -ne 1 -or @($combinedRoles|Where-Object {$_ -eq 'webview2'}).Count -ne 1){throw 'Base/LaTeX setup duplicated shared dependencies or requested SumatraPDF.'}
$pdfTool=$tools|Where-Object {$_.role -eq 'pdf'}|Select-Object -First 1
foreach($hasPdf in @($false,$true)){
 $pdfTool.available=$hasPdf;$pdfTool.path=if($hasPdf){'C:\existing\SumatraPDF.exe'}else{$null}
 $latexPlan=New-DependencyPlan -Tools $tools -Assets $assets -Root $deps -Roles $latexRoles -Notebook $false -Latex $true -Selected $null -Base $null -UnknownPython $false
 if(@($latexPlan.items|Where-Object {$_.role -eq 'pdf'}).Count -ne 0 -or $latexPlan.known_download_bytes -ne 100 -or @($latexPlan.dynamic_downloads|Where-Object {$_ -like 'pdf:*'}).Count -ne 0){throw 'Automatic LaTeX planning requested SumatraPDF or lost the embedded runtime download.'}
 $explicitRoles=@(Get-RequestedDependencyRoles -Tools @('pdf') -Base $false -Latex $false)
 $explicitPlan=New-DependencyPlan -Tools $tools -Assets $assets -Root $deps -Roles $explicitRoles -Notebook $false -Latex $false -Selected $null -Base $null -UnknownPython $false
 if(@($explicitPlan.items).Count -ne 1 -or $explicitPlan.items[0].role -ne 'pdf'){throw 'Explicit external-viewer selection was lost.'}
 if($hasPdf){
  if($explicitPlan.items[0].status -ne 'reuse' -or $explicitPlan.items[0].reuse_path -cne $pdfTool.path -or @($explicitPlan.dynamic_downloads).Count -ne 0){throw 'An explicitly selected existing SumatraPDF was not reused.'}
 }elseif($explicitPlan.items[0].status -ne 'missing' -or @($explicitPlan.dynamic_downloads).Count -ne 1){throw 'An explicitly selected missing SumatraPDF was not offered through its provider.'}
 if($pdfTool.available -ne $hasPdf -or ($hasPdf -and $pdfTool.path -cne 'C:\existing\SumatraPDF.exe') -or (Test-Path -LiteralPath $deps)){throw 'Read-only planning changed detected tools or created dependencies.'}
}
Write-Output 'PASS LaTeX uses embedded WebView2, omits missing/existing SumatraPDF, and preserves explicit install/reuse'
$blocked=New-DependencyPlan -Tools $tools -Assets $assets -Root $deps -Roles @() -Notebook $true -Latex $false -Selected $null -Base $null -UnknownPython $true
if($blocked.items[0].status -ne 'blocked' -or $blocked.known_download_bytes -ne 0){throw 'Unknown Python inspection was presented as safe to install.'}
Write-Output 'PASS inconclusive Python inspection blocks Notebook replacement'
$DependencyRoot=Join-Path $WorkRoot 'owned-dependencies'
$cache=Join-Path $DependencyRoot 'downloads-v1';Initialize-DependencyDirectory $cache 'glow-download-cache-v1'
$file=Join-Path $cache 'rg.zip';[IO.File]::WriteAllText($file,'verified fixture')
$assets.rg.download_size=(Get-Item -LiteralPath $file).Length
$assets.rg.sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
$cached=New-DependencyPlan -Tools $tools -Assets $assets -Root $DependencyRoot -Roles @('search') -Notebook $false -Latex $false -Selected $null -Base $null -UnknownPython $false
if($cached.known_download_bytes -ne 0 -or $cached.items[0].download_note -notlike '*cached*'){throw 'Verified download cache did not reduce the plan.'}
[IO.File]::AppendAllText($file,'corrupt')
$uncached=New-DependencyPlan -Tools $tools -Assets $assets -Root $DependencyRoot -Roles @('search') -Notebook $false -Latex $false -Selected $null -Base $null -UnknownPython $false
if($uncached.known_download_bytes -ne $assets.rg.download_size -or -not (Test-Path -LiteralPath $file)){throw 'Corrupt cache was trusted or removed during planning.'}
Write-Output 'PASS verified cache reduces known bytes; invalid cache is preserved without being trusted'
$script:DependencyStatusPath=Join-Path $WorkRoot 'status.json';$script:DependencyRun=Join-Path $WorkRoot 'run'
Set-DependencyStatus 'running' 'download' 'fixture progress' 25 100
Set-DependencyStatus 'running' 'download' 'fixture resumed progress' 50 100
Set-DependencyStatus 'failed' 'failed' 'fixture retry' -ErrorMessage 'fixture error'
$status=Get-Content -LiteralPath $script:DependencyStatusPath -Raw -Encoding UTF8|ConvertFrom-Json
$previous=Get-Content -LiteralPath ($script:DependencyStatusPath+'.previous') -Raw -Encoding UTF8|ConvertFrom-Json
if($status.state -ne 'failed' -or $status.error -ne 'fixture error' -or $status.run_path -ne $script:DependencyRun -or $status.downloaded_bytes -ne 0 -or $previous.downloaded_bytes -ne 50 -or $previous.total_bytes -ne 100){throw 'Status replacement lost progress, failure details or the explicit previous-state backup.'}
Write-Output 'PASS fixed status schema and atomic explicit backup retain progress and recovery evidence'
@{schema_version=1;state='passed';checks=@('read-only-plan','dynamic-downloads','latex-embedded-viewer','explicit-pdf-install-reuse','unknown-python-block','verified-cache','status-backup')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'receipt.json') -Encoding UTF8
