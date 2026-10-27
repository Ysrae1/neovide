#requires -Version 5.1
# Pure source/argument regression plus an owned local PowerShell child. Does not
# run pip, download packages, change user configuration, or access a Windows VM.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh Notebook mirror-test WorkRoot.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
function Read-Ast([string]$Relative){
    $tokens=$null;$errors=$null
    $value=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot $Relative),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
    return $value
}
$helper=Read-Ast 'portable/windows/Dependency-Helpers.ps1'
$backend=Read-Ast 'portable/windows/Setup-Dependencies.ps1'
function Import-Helper([string]$Name){
    $found=@($helper.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name},$true))
    if($found.Count -ne 1){throw ('Expected production helper '+$Name)}
    return $found[0].Extent.Text
}
foreach($name in @('Get-NotebookIndexUrl','Get-NotebookPipArguments','ConvertTo-DependencyArgumentString','Invoke-DependencyProcess')){
    Invoke-Expression (Import-Helper $name)
}
$expected=@{pypi='https://pypi.org/simple';tuna='https://pypi.tuna.tsinghua.edu.cn/simple';ustc='https://mirrors.ustc.edu.cn/pypi/simple'}
if((Get-NotebookIndexUrl) -cne $expected.pypi){throw 'Default Notebook source must remain the official PyPI.'}
$requirements="C:\User With Space\O'Connor\notebook-requirements.txt"
$logPath='C:\User With Space\logs\notebook-pip.log'
foreach($mirror in @('pypi','tuna','ustc')){
    if((Get-NotebookIndexUrl $mirror) -cne $expected[$mirror]){throw ('Unexpected source URL: '+$mirror)}
    foreach($hashes in @($false,$true)){
        $arguments=@(Get-NotebookPipArguments -Mirror $mirror -Requirements $requirements -LogPath $logPath -RequireHashes:$hashes)
        $index=[Array]::IndexOf($arguments,'--index-url')
        if(@($arguments|Where-Object {$_ -ceq '--index-url'}).Count -ne 1 -or $index -lt 0 -or $arguments[$index+1] -cne $expected[$mirror]){throw 'Pip did not use exactly one selected index.'}
        if(($arguments[0..4] -join ',') -cne '-I,-m,pip,--isolated,install'){throw 'Python/pip isolation or install operation changed.'}
        if(@($arguments|Where-Object {$_ -match '^--(?:extra-index-url|trusted-host|no-check-certificate|upgrade|pre)(?:=|$)' -or $_ -match '^http://'}).Count){throw 'Pip source selection weakened TLS, merged indexes or changed version policy.'}
        if($arguments[[Array]::IndexOf($arguments,'-r')+1] -cne $requirements -or $arguments[[Array]::IndexOf($arguments,'--log')+1] -cne $logPath){throw 'Requirements/log paths lost exact argument boundaries.'}
        if($hashes -and ('--require-hashes' -notin $arguments -or '--only-binary=:all:' -in $arguments)){throw 'Text-converter hash policy changed.'}
        if(-not $hashes -and ('--only-binary=:all:' -notin $arguments -or '--require-hashes' -in $arguments)){throw 'Notebook wheel policy changed.'}
    }
}
$invalid=$false;try{$null=Get-NotebookIndexUrl 'http://untrusted.invalid'}catch{$invalid=$true}
if(-not $invalid){throw 'Unlisted source was accepted.'}
Write-Output 'PASS three explicit HTTPS sources, unchanged default, isolated pip, exact requirements/log paths and existing wheel/hash policies'

# Real process creation proves that the override is child-local, including when
# an inherited value already exists. Windows pip compares os.devnull ('nul')
# case-sensitively; uppercase NUL does not disable its config-file loader.
# No actual pip or network process is used.
$script:DependencyRun=Join-Path $WorkRoot 'process';$null=New-Item -ItemType Directory -Path $script:DependencyRun
$script:DependencyChecks=@()
function Set-DependencyStatus {}
$child=Join-Path $WorkRoot 'Read-ChildEnvironment.ps1'
$childResult=Join-Path $WorkRoot 'child-environment.txt'
[IO.File]::WriteAllText($child,'param([string]$OutputPath) [IO.File]::WriteAllText($OutputPath,[string]$env:PIP_CONFIG_FILE); [Console]::WriteLine("child completed")')
$shell=Join-Path $PSHOME 'powershell.exe'
if(-not (Test-Path -LiteralPath $shell -PathType Leaf)){$shell=Join-Path $PSHOME 'pwsh'}
$before=[Environment]::GetEnvironmentVariable('PIP_CONFIG_FILE','Process')
try{
    [Environment]::SetEnvironmentVariable('PIP_CONFIG_FILE','glow-test-parent-value','Process')
    $null=Invoke-DependencyProcess -Executable $shell -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$child,'-OutputPath',$childResult) -Name 'child-environment' -TimeoutSeconds 15 -EnvironmentOverrides @{PIP_CONFIG_FILE='nul'}
    if([IO.File]::ReadAllText($childResult) -cne 'nul'){throw 'Pip configuration isolation did not reach the child.'}
    if([Environment]::GetEnvironmentVariable('PIP_CONFIG_FILE','Process') -cne 'glow-test-parent-value'){throw 'Child override changed the parent process environment.'}
    if($script:DependencyChecks.Count -ne 1 -or $script:DependencyChecks[0].exit_code -ne 0 -or -not $script:DependencyChecks[0].output_drain_complete){throw 'Owned child execution did not complete cleanly.'}
}finally{[Environment]::SetEnvironmentVariable('PIP_CONFIG_FILE',$before,'Process')}
Write-Output 'PASS real owned child receives config isolation while inherited parent environment is preserved'

# Execute the production call expressions with only native process creation
# replaced. This verifies both package stages consume the same selected source.
$script:commands=@()
function Invoke-DependencyProcess([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$TimeoutSeconds,[hashtable]$EnvironmentOverrides){
    $script:commands+=@{executable=$Executable;arguments=$Arguments;name=$Name;timeout=$TimeoutSeconds;environment=$EnvironmentOverrides}
}
$privatePython='C:\fixture\Scripts\python.exe';$NotebookMirror='ustc'
$fixtureScriptRoot=Join-Path $SourceRoot 'portable/windows'
foreach($name in @('install-Notebook-packages','install-LaTeX-text-converter')){
    $call=@($backend.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-DependencyProcess' -and $node.Extent.Text -match ("'"+[regex]::Escape($name)+"'")},$true))
    if($call.Count -ne 1){throw ('Expected one package stage '+$name)}
    # AST-created scriptblocks have no source-file PSScriptRoot; supply only
    # that lexical file location while preserving the production call itself.
    Invoke-Expression $call[0].Extent.Text.Replace('$PSScriptRoot','$fixtureScriptRoot')
}
foreach($command in $script:commands){
    $arguments=$command.arguments;$index=[Array]::IndexOf($arguments,'--index-url')
    if($command.executable -cne $privatePython -or $index -lt 0 -or $arguments[$index+1] -cne $expected.ustc -or $command.environment.PIP_CONFIG_FILE -cne 'nul'){throw ('Package stage lost reviewed source/isolation: '+$command.name)}
}
if(($script:commands.timeout -join ',') -cne '1200,180'){throw 'Package stage deadlines changed.'}
if('--only-binary=:all:' -notin $script:commands[0].arguments -or '--require-hashes' -notin $script:commands[1].arguments){throw 'Production stages changed wheel/hash protection.'}
$sourceAssignment=@($backend.FindAll({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$notebookSource'},$true))
if($sourceAssignment.Count -ne 1){throw 'Expected one selected-source record.'}
Invoke-Expression $sourceAssignment[0].Extent.Text
if($notebookSource.name -cne 'ustc' -or $notebookSource.index_url -cne $expected.ustc){throw 'Source record differs from actual pip selection.'}
$plan=[pscustomobject]@{}
$planSource=@($backend.FindAll({param($node) $node -is [Management.Automation.Language.PipelineAst] -and $node.Extent.Text -match '^\$plan\|Add-Member -NotePropertyName notebook_source\b'},$true))
if($planSource.Count -ne 1){throw 'Selected source missing from the reviewable plan.'}
Invoke-Expression $planSource[0].Extent.Text
if($plan.notebook_source.index_url -cne $expected.ustc){throw 'Plan displays a different package source.'}
$reportSources=@($backend.FindAll({param($node)
    if($node -isnot [Management.Automation.Language.HashtableAst]){return $false}
    $pairs=@($node.KeyValuePairs|Where-Object {$_.Item1.Extent.Text -ceq 'notebook_source'})
    return ($pairs.Count -eq 1 -and $pairs[0].Item2.Extent.Text -ceq '$notebookSource')
},$true))
if($reportSources.Count -ne 3){throw 'Planned, successful and failed receipts must retain the actual source.'}
Write-Output 'PASS both production package calls preserve source, fixed time budgets and config isolation; plan and all receipts retain source'
@{schema_version=1;state='passed';powershell=$PSVersionTable.PSVersion.ToString();checks=@('three-sources','official-default','single-index-tls','argument-boundaries','wheel-hash-policies','child-environment-isolation','both-production-stages','unchanged-deadlines','plan-receipt-source');downloads=$false;pip_executed=$false;windows_gui_tested=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'receipt.json') -Encoding UTF8
