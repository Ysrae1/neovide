#requires -Version 5.1
# Pure regression: executes production selection and command argument logic;
# substitutes only the HTTP boundary. No downloads, installers or VM access.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if (Test-Path -LiteralPath $WorkRoot) { throw 'Use a fresh mirror-test WorkRoot.' }
$null=New-Item -ItemType Directory -Path $WorkRoot
$tokens=$null; $errors=$null
$path=Join-Path $SourceRoot 'portable/windows/tex/Install-TinyTeX.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors|Out-String) }
function Get-FunctionAst([string]$Name) {
    $found=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name},$true))
    if ($found.Count -ne 1) { throw ('Expected production function '+$Name) }
    return $found[0]
}
foreach ($name in @('Get-TeXMirrorCandidates','Select-TeXRepository')) { Invoke-Expression (Get-FunctionAst $name).Extent.Text }
$receipt=[ordered]@{}; $script:probes=@(); $script:phases=@(); $script:fail=@()
function Save-Receipt { $receipt|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $WorkRoot 'selection.json') -Encoding UTF8 }
function Progress([string]$Message,[string]$Phase) { $script:phases+=@{message=$Message;phase=$Phase} }
function Test-TeXMirrorMetadata([string]$Repository,[int]$TimeoutSeconds) {
    if ($TimeoutSeconds -ne 15) { throw 'Probe exceeded its 15-second budget.' }
    $script:probes+=$Repository
    if ($Repository -in $script:fail) { throw 'Synthetic unreachable metadata endpoint.' }
}
$tuna='https://mirrors.tuna.tsinghua.edu.cn/CTAN/systems/texlive/tlnet'
$ustc='https://mirrors.ustc.edu.cn/CTAN/systems/texlive/tlnet'
$illinois='https://ctan.math.illinois.edu/systems/texlive/tlnet'
foreach ($culture in @('zh-CN','zh-TW','zh-Hans')) {
    $actual=@(Get-TeXMirrorCandidates -Mirror auto -UICulture $culture).name -join ','
    if ($actual -cne 'tuna,ustc,illinois') { throw ('Incorrect Chinese priority: '+$culture) }
}
if ((@(Get-TeXMirrorCandidates -Mirror auto -UICulture 'en-US').name -join ',') -cne 'illinois,tuna,ustc') { throw 'Incorrect non-Chinese priority.' }
$script:fail=@($tuna); $selected=Select-TeXRepository -Mirror auto -UICulture 'zh-CN'
if ($selected -cne $ustc -or ($script:probes -join ',') -cne ($tuna+','+$ustc) -or $receipt.mirror_probes.Count -ne 2 -or $receipt.selected_repository -cne $ustc) { throw 'Auto did not stop after its first reachable repository.' }
if ($receipt.mirror_probes[0].passed -or -not $receipt.mirror_probes[1].passed -or -not $receipt.mirror_probes[0].error) { throw 'Probe results were not recorded.' }
if (@($script:phases|Where-Object {$_.phase -cne 'select-tex-mirror'}).Count -or $script:phases[-1].message -notmatch 'Selected TeX mirror ustc') { throw 'Mirror progress did not publish the selected source.' }
$saved=Get-Content -LiteralPath (Join-Path $WorkRoot 'selection.json') -Raw|ConvertFrom-Json
if ($saved.selected_repository -cne $ustc -or $saved.mirror_probes.Count -ne 2) { throw 'Receipt was not saved.' }
$receipt=[ordered]@{}; $script:probes=@(); $script:fail=@($ustc)
$failed=$false
try { $null=Select-TeXRepository -Mirror ustc -UICulture 'zh-CN' } catch { $failed=$_.Exception.Message -match 'No reachable TeX mirror' }
if (-not $failed -or $script:probes.Count -ne 1 -or $script:probes[0] -cne $ustc) { throw 'Explicit mirror failure silently fell back.' }
$receipt=[ordered]@{}; $script:probes=@(); $script:fail=@($tuna,$ustc,$illinois)
$failed=$false
try { $null=Select-TeXRepository -Mirror auto -UICulture 'en-US' } catch { $failed=$_.Exception.Message -match 'No reachable TeX mirror' }
if (-not $failed -or ($script:probes -join ',') -cne ($illinois+','+$tuna+','+$ustc)) { throw 'Auto failure did not try exactly three candidates once.' }
Write-Output 'PASS culture priority, bounded auto fallback, explicit failure, persisted probes and selected-source progress'
# Validate real metadata format guard independently of the network boundary.
$metadata=Get-FunctionAst 'Test-TeXMirrorMetadata'
$guard=@($metadata.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text -match '^if \(\$content\.Trim'},$true))
if ($guard.Count -ne 1 -or $metadata.Extent.Text -notmatch 'AllowAutoRedirect = \$false' -or $metadata.Extent.Text -notmatch 'MaxResponseContentBufferSize = 4096') { throw 'Missing bounded HTTPS metadata guard.' }
foreach ($sample in @(@{text=(('a'*128)+'  texlive.tlpdb');valid=$true},@{text=('a'*128);valid=$true},@{text='<html>proxy error</html>';valid=$false},@{text=(('a'*128)+' wrong-file');valid=$false})) {
    $content=$sample.text; $valid=$true
    try { Invoke-Expression $guard[0].Extent.Text } catch { $valid=$false }
    if ($valid -ne $sample.valid) { throw 'Metadata SHA512 format validation failed.' }
}
# Evaluate the real online tlmgr command arguments with a recorder replacing
# process creation. A later step must never select a different repository.
$source=[IO.File]::ReadAllText($path)
$selects=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Select-TeXRepository'},$true))
if ($selects.Count -ne 1 -or $selects[0].Extent.StartOffset -gt $source.IndexOf("-Name 'extract-official-archive'")) { throw 'Repository selection must happen once before extraction.' }
$repository=$ustc; $tlmgr='synthetic-tlmgr'; $tlmgrBatch='synthetic-tlmgr.bat'; $perl='synthetic-perl'; $packages=@('ctex')
$verifiedAssignment=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$verified'},$true))
if ($verifiedAssignment.Count -ne 1) { throw 'Expected one verified argument base.' }
Invoke-Expression $verifiedAssignment[0].Extent.Text
$script:commands=@()
function Invoke-Bounded([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$TimeoutSeconds) { $script:commands+=@{name=$Name;arguments=$Arguments;timeout=$TimeoutSeconds} }
$names=@('tlmgr-self-update','verify-self-update-complete','update-texlive-scripts','install-common-packages')
foreach ($name in $names) {
    $matches=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-Bounded' -and $node.Extent.Text -match ("-Name '"+[regex]::Escape($name)+"'")},$true))
    if ($matches.Count -ne 1) { throw ('Missing online command '+$name) }
    Invoke-Expression $matches[0].Extent.Text
}
foreach ($command in $script:commands) {
    $args=$command.arguments; $index=[Array]::IndexOf($args,'--repository')
    if ($index -lt 0 -or $args[$index+1] -cne $ustc -or '--verify-repo=all' -notin $args) { throw ('Repository/signature binding failed: '+$command.name) }
}
if (($script:commands.timeout -join ',') -cne '420,180,300,600') { throw 'Existing online command deadlines changed.' }
$parent=[IO.File]::ReadAllText((Join-Path $SourceRoot 'portable/windows/Setup-LaTeX.ps1'))
if ($parent -notmatch "\[ValidateSet\('auto','tuna','ustc','illinois'\)\]\[string\]\`$TeXMirror='auto'" -or $parent -notmatch '-TeXMirror \$TeXMirror -ProgressCallback') { throw 'Parent did not validate and forward the mirror alongside progress callback.' }
Write-Output 'PASS SHA512 metadata guard, single pre-install selection, all online operations pinned with signature verification and unchanged deadlines, parent forwarding'
@{schema_version=1;state='passed';powershell=$PSVersionTable.PSVersion.ToString();checks=@('culture-priority','auto-fallback-once','explicit-no-fallback','receipt-and-progress','sha512-metadata-format','repository-binding','unchanged-deadlines','parent-forwarding');real_install=$false;windows_gui_tested=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'receipt.json') -Encoding UTF8
