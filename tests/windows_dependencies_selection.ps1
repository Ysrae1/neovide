#requires -Version 5.1
<# Exercise the real setup phase/catch statements with synthetic providers and
   installer stubs. Runs on PowerShell 5.1/7 without downloads, registry access,
   Python processes, kernels, GUI or writes outside a fresh WorkRoot. #>
param(
    [string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory=$true)][string]$WorkRoot,
    [string]$SetupPath
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh selection-test WorkRoot.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
if(-not $SetupPath){$SetupPath=Join-Path $SourceRoot 'portable/windows/Setup-Dependencies.ps1'}
. (Join-Path $SourceRoot 'portable/windows/Dependency-Helpers.ps1')
$tokens=$null;$parseErrors=$null
$setupAst=[Management.Automation.Language.Parser]::ParseFile($SetupPath,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors|Out-String)}
foreach($name in @('Save-Selection','Save-ToolSelection','Assert-NotebookProbeKnown')){
    $definitions=@($setupAst.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$true))
    # An older source can be supplied to demonstrate the original regression.
    if($definitions.Count -eq 0 -and $name -eq 'Save-ToolSelection'){continue}
    if($definitions.Count -ne 1){throw ('Expected production function '+$name)}
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$setupTries=@($setupAst.FindAll({param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
    $node.CatchClauses.Count -gt 0 -and $node.Extent.Text -match 'Assert-NotebookProbeKnown \$selected'
},$true))
if($setupTries.Count -ne 1){throw 'Expected the production setup phase and catch statements.'}
$phaseSource=$setupTries[0].Extent.Text.Replace('$PSScriptRoot','$fixtureScripts')
$utf8=New-Object Text.UTF8Encoding($false)
function Write-Fixture([string]$Path,[string]$Value){
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllText($Path,$Value,$utf8)
}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Read-Selection([string]$Path){Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
$receipt=[ordered]@{schema_version=1;state='running';powershell=$PSVersionTable.PSVersion.ToString();
    setup_sha256=(Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash.ToLowerInvariant();
    real_installers_started=0;cases=@()}
$cases=@(
    @{name='new-notebook-survives-tex-failure';notebook=$true;latex=$true;texFailure=$true;seed=$false},
    @{name='reused-notebook-survives-base-failure';notebook=$true;reused=$true;baseFailure=$true;seed=$true},
    @{name='notebook-install-failure-preserves-prior-bytes';notebook=$true;notebookFailure=$true;seed=$true;exactOld=$true},
    @{name='notebook-import-failure-preserves-prior-bytes';notebook=$true;probeFailure=$true;seed=$true;exactOld=$true},
    @{name='base-survives-notebook-failure';notebook=$true;notebookFailure=$true;baseTools=$true;latex=$true;seed=$true},
    @{name='tex-survives-acp-failure';latex=$true;acp=$true;acpFailure=$true;seed=$true},
    @{name='tex-failure-keeps-old-provider';latex=$true;texFailure=$true;seed=$true;exactOld=$true},
    @{name='normal-completion';notebook=$true;latex=$true;baseTools=$true;seed=$true},
    @{name='missing-tex-is-not-selected';latex=$true;missingTex=$true;seed=$true;exactOld=$true}
)
try{
    foreach($caseSpec in $cases){
        foreach($flag in @('notebook','latex','texFailure','seed','reused','baseFailure','notebookFailure','exactOld','probeFailure','baseTools','acp','acpFailure','missingTex')){
            if(-not $caseSpec.ContainsKey($flag)){$caseSpec[$flag]=$false}
        }
        & {
            $caseRoot=Join-Path $WorkRoot $caseSpec.name
            $SelectionRoot=Join-Path $caseRoot 'selection';$DependencyRoot=Join-Path $caseRoot 'dependencies'
            $fixtureScripts=Join-Path $caseRoot 'scripts'
            $oldTool=Join-Path $caseRoot 'old-tools';$newTool=Join-Path $caseRoot 'new-tools';$newTex=Join-Path $caseRoot 'new-tex'
            $null=New-Item -ItemType Directory -Path $oldTool,$newTool,$newTex -Force
            $selection=Join-Path $SelectionRoot 'selected.json'
            $oldRecord=@{schema_version=1;python='old-python';jupytext='old-jupytext';latex2text='old-latex2text';
                python_version='3.12.1';tool_paths=@($oldTool);retained_extra=@{value='preserved'}}
            $oldBytes=$null
            if($caseSpec.seed){Write-Fixture $selection ($oldRecord|ConvertTo-Json -Depth 5);$oldBytes=[IO.File]::ReadAllText($selection)}
            Write-Fixture (Join-Path $fixtureScripts 'notebook-requirements.txt') 'synthetic-requirement'
            if(-not $caseSpec.missingTex){Write-Fixture (Join-Path $newTex 'xelatex.exe') 'synthetic-executable'}
            Write-Fixture (Join-Path $fixtureScripts 'Setup-LaTeX.ps1') @'
param($DependencyRoot,$RunRoot,$ToolPaths,$TeXMirror)
if($caseSpec.texFailure){throw 'fixture TeX failed'}
$null=New-Item -ItemType Directory -Path $RunRoot -Force
Write-DependencyJson (Join-Path $RunRoot 'selected.json') @{schema_version=1;status='passed';bin=$newTex}
'@
            $verified=[pscustomobject]@{ready=$true;python=(Join-Path $caseRoot 'verified-python.exe');
                jupytext=(Join-Path $caseRoot 'verified-jupytext.exe');latex2text=(Join-Path $caseRoot 'verified-latex2text.exe');version='3.12.8';platform='win-amd64'}
            $base=[pscustomobject]@{python='fixture-source-python';platform='win-amd64'}
            $selected=if($caseSpec.reused){$verified}else{$null}
            $interpreters=@();$plan=@{};$webview2=@{};$manifest=@{};$mapping=@{search='rg'}
            $assetLock=@{assets=@{rg=@{download_size=1};python=@{}}}
            $roles=@(if($caseSpec.baseTools -or $caseSpec.baseFailure){'search'})
            $tools=@([pscustomobject]@{role='latex';available=$true;path=(Join-Path $newTex 'xelatex.exe')})
            if($roles.Count){$tools+=@([pscustomobject]@{role='search';available=(-not $caseSpec.baseFailure);path=(Join-Path $newTool 'rg.exe')})}
            $InstallNotebook=[bool]$caseSpec.notebook;$SelectPython=$false;$InstallLatex=[bool]$caseSpec.latex
            $InstallACP=[bool]$caseSpec.acp;$NvimDataRoot='fixture-data';$ACPNodePath='fixture-node';$ACPArchitecture='x64'
            $TeXMirror='auto';$ReportPath=$null;$Json=$false;$mutating=$true;$acpReady=$false;$selectionSaved=$false
            $dependencyMutex=$null;$mutexAcquired=$false
            $script:SelectedToolPaths=@(if($caseSpec.seed){$oldTool})
            $script:DependencyRun=$null;$script:DependencyChecks=@();$script:PythonProbeDiagnostics=@();$script:DependencyStatusPath=$null
            function Install-DependencyTool {throw 'fixture base failed'}
            function Install-DependencyPython {throw 'Unexpected Python installer invocation'}
            function Invoke-DependencyProcess {
                param($Executable,$Arguments,$Name,$TimeoutSeconds)
                if($caseSpec.notebookFailure -and $Name -eq 'install-Notebook-packages'){throw 'fixture Notebook failed'}
                if($caseSpec.acpFailure -and $Name -eq 'prepare-ACP-runtime'){throw 'fixture ACP failed'}
            }
            function Probe-Python {param($Executable);if($caseSpec.probeFailure){return $null};return $verified}
            $savedAppData=$env:APPDATA
            $failure=$null
            try{
                $env:APPDATA=$caseRoot
                try{. ([scriptblock]::Create($phaseSource))}catch{$failure=$_}
            }finally{$env:APPDATA=$savedAppData}
            $shouldFail=$caseSpec.name -ne 'normal-completion'
            Require (([bool]$failure) -eq $shouldFail) ('Unexpected phase outcome: '+$caseSpec.name+' '+$failure)
            if($failure){
                $expected=if($caseSpec.baseFailure){'fixture base failed'}elseif($caseSpec.notebookFailure){'fixture Notebook failed'}elseif($caseSpec.probeFailure){'failed import validation'}elseif($caseSpec.acpFailure){'fixture ACP failed'}elseif($caseSpec.missingTex){'Validated LaTeX executable is missing'}else{'fixture TeX failed'}
                Require ($failure.Exception.Message.Contains($expected)) ('Unexpected failure cause: '+$failure.Exception.Message)
            }
            Require (Test-Path -LiteralPath $selection -PathType Leaf) ('Verified selection is absent: '+$caseSpec.name)
            $result=Read-Selection $selection
            $newPython=($caseSpec.notebook -and -not $caseSpec.notebookFailure -and -not $caseSpec.probeFailure)
            Require ($result.python -ceq $(if($newPython){$verified.python}else{$oldRecord.python})) ('Incorrect provider after '+$caseSpec.name)
            if(-not $newPython){Require ($result.retained_extra.value -ceq 'preserved') 'A tool update dropped a retained field.'}
            if($caseSpec.exactOld){Require ([IO.File]::ReadAllText($selection) -ceq $oldBytes) ('Failure rewrote the old selection: '+$caseSpec.name)}
            if($caseSpec.baseTools){Require (@($result.tool_paths) -contains $newTool) 'A validated base path was not persisted.'}
            $texPassed=$caseSpec.latex -and -not $caseSpec.texFailure -and -not $caseSpec.missingTex -and -not $caseSpec.notebookFailure
            Require ((@($result.tool_paths) -contains $newTex) -eq [bool]$texPassed) ('Unverified or missing TeX selection: '+$caseSpec.name)
            if($caseSpec.seed -and $newPython){
                $backups=@(Get-ChildItem -LiteralPath $SelectionRoot -File -Filter 'selected.json.before-*')
                Require (@($backups|Where-Object {[IO.File]::ReadAllText($_.FullName) -ceq $oldBytes}).Count -ge 1) 'Original selection backup was lost.'
            }
            Require (@(Get-ChildItem -LiteralPath $SelectionRoot -File -Filter '*.preparing-*').Count -eq 0) 'Temporary selection file remained.'
            $runReceipt=Read-Selection (Join-Path $script:DependencyRun 'receipt.json')
            Require ($runReceipt.status -ceq $(if($shouldFail){'failed'}else{'passed'})) 'Run receipt misreported the phase result.'
            if($shouldFail -and ($newPython -or $caseSpec.baseTools -or $texPassed)){
                Require ($runReceipt.selection_saved -eq $true) 'Failure receipt hid a committed successful selection.'
            }
            $receipt.cases+=@(@{name=$caseSpec.name;state='passed';expected_failure=[bool]$failure})
            Write-Output ('PASS '+$caseSpec.name)
        }
    }
    $receipt.state='passed'
}catch{$receipt.state='failed';$receipt.error=$_.Exception.Message;throw}
finally{Write-Fixture (Join-Path $WorkRoot 'receipt.json') ($receipt|ConvertTo-Json -Depth 7)}
