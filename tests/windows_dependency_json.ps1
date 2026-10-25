#requires -Version 5.1
<# Native Windows PowerShell 5.1 atomic-JSON regression. Uses only synthetic
   files in a fresh WorkRoot; no installers, executables, downloads or GUI.
   Runs directly against the supplied source tree. #>
param(
    [string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory=$true)][string]$WorkRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw 'This regression requires native Windows PowerShell 5.1 (Desktop).'
}
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
if (Test-Path -LiteralPath $WorkRoot) { throw 'Use a fresh atomic-JSON WorkRoot.' }
$null=New-Item -ItemType Directory -Path $WorkRoot
$utf8=New-Object Text.UTF8Encoding($false)
$receipt=@{
    schema_version=1;state='running';checks=@();failures=@();sources=@();
    powershell=$PSVersionTable.PSVersion.ToString();edition=$PSVersionTable.PSEdition;
    prior_native_reproduction='core103-ownership-and-replace.json'
}
function Save-Receipt {
    [IO.File]::WriteAllText((Join-Path $WorkRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 12),$utf8)
}
function Require([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Pass([string]$Name) {
    $receipt.checks+=@($Name)
    Save-Receipt
    Write-Output ('PASS '+$Name)
}
function Read-SourceAst([string]$Path) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors|Out-String) }
    $receipt.sources+=@(@{path=$Path;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()})
    return $ast
}
function Find-Definition($Ast,[string]$Name) {
    $definitions=@($Ast.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name -and
        $node.Parent -eq $Ast.EndBlock
    },$true))
    Require ($definitions.Count -eq 1) ('Expected one trusted definition: '+$Name)
    return $definitions[0]
}
function Assert-NoDestinationDelete($Definition) {
    # The locked-file check below verifies preservation on a real failed write.
    # Also reject a delete-then-move implementation, whose unlocked success
    # could otherwise conceal the interval in which the destination is absent.
    $memberDeletes=@($Definition.Body.FindAll({param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Member.Extent.Text -match '^(Delete|DeleteFile)$'
    },$true))
    Require ($memberDeletes.Count -eq 0) ($Definition.Name+' must not delete its destination before replacing it.')
    $deletes=@($Definition.Body.FindAll({param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -in @('Remove-Item','ri','rm','rmdir','del','erase','rd')
    },$true))
    foreach ($delete in $deletes) {
        $elements=$delete.CommandElements
        $temporaryOnly=$elements.Count -eq 3 -and
            $elements[1] -is [Management.Automation.Language.CommandParameterAst] -and
            $elements[1].ParameterName -eq 'LiteralPath' -and
            $elements[2] -is [Management.Automation.Language.VariableExpressionAst] -and
            $elements[2].VariablePath.UserPath -eq 'temporary'
        Require $temporaryOnly ($Definition.Name+' may remove only its own temporary JSON file.')
    }
}
function Read-Json([string]$Path) {
    Require (Test-Path -LiteralPath $Path -PathType Leaf) ('Expected JSON file: '+$Path)
    $bytes=[IO.File]::ReadAllBytes($Path)
    Require (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'JSON unexpectedly contains a UTF-8 BOM.'
    return ([IO.File]::ReadAllText($Path,(New-Object Text.UTF8Encoding($false,$true)))|ConvertFrom-Json)
}
function Assert-SameBytes([string]$Path,[byte[]]$Expected,[string]$Message) {
    Require (Test-Path -LiteralPath $Path -PathType Leaf) ($Message+' Destination was removed.')
    Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -ceq [Convert]::ToBase64String($Expected)) $Message
}
function Assert-NoPreparing([string]$Path) {
    $prefix=[IO.Path]::GetFileName($Path)+'.preparing-'
    $remaining=@(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -File|Where-Object {
        $_.Name.StartsWith($prefix,[StringComparison]::Ordinal)
    })
    Require ($remaining.Count -eq 0) ('Temporary JSON file was not cleaned up: '+$Path)
}
function Get-SelectionBackups([string]$Path) {
    $prefix=[IO.Path]::GetFileName($Path)+'.before-'
    Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -File|Where-Object {
        $_.Name.StartsWith($prefix,[StringComparison]::Ordinal)
    }
}
function Assert-Selection($Value,$Expected,[string[]]$Paths) {
    $expectedKeys=@('schema_version','python','jupytext','latex2text','python_version','tool_paths')|Sort-Object
    $actualKeys=@($Value.PSObject.Properties|ForEach-Object {$_.Name})|Sort-Object
    Require (($actualKeys -join '|') -ceq ($expectedKeys -join '|')) 'Selection schema fields changed.'
    Require ($Value.schema_version -eq 1 -and $Value.python -ceq $Expected.python -and
        $Value.jupytext -ceq $Expected.jupytext -and $Value.latex2text -ceq $Expected.latex2text -and
        $Value.python_version -ceq $Expected.version) 'Selection lost its synthetic environment fields.'
    Require ($Value.tool_paths -is [Array] -and @($Value.tool_paths).Count -eq $Paths.Count) 'Selection tool_paths is not the expected array.'
    for ($index=0; $index -lt $Paths.Count; $index++) {
        Require ($Value.tool_paths[$index] -ceq $Paths[$index]) 'Selection changed a tool path or its order.'
    }
}

try {
    Save-Receipt
    $helperAst=Read-SourceAst (Join-Path $SourceRoot 'portable\windows\Dependency-Helpers.ps1')
    $setupAst=Read-SourceAst (Join-Path $SourceRoot 'portable\windows\Setup-Dependencies.ps1')
    $writerDefinition=Find-Definition $helperAst 'Write-DependencyJson'
    $selectionDefinition=Find-Definition $setupAst 'Save-Selection'
    foreach ($definition in @($writerDefinition,$selectionDefinition)) {
        Assert-NoDestinationDelete $definition
        # Import definitions only. Never dot-source setup's discovery/install path.
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    Pass 'real JSON writers load without executing setup and never pre-delete destinations'

    # Keep the source ASCII for Windows PowerShell 5.1's BOM-less script reader.
    # Each real writer receives paths containing Chinese, spaces and an apostrophe.
    $specialName='JSON space '+[char]0x4E2D+[char]0x6587+[char]0x27
    $caseRoot=Join-Path $WorkRoot $specialName
    $null=New-Item -ItemType Directory -Path $caseRoot
    $toolOne=Join-Path $caseRoot 'tools one'
    $toolTwo=Join-Path $caseRoot 'tools two'
    $null=New-Item -ItemType Directory -Path $toolOne
    $null=New-Item -ItemType Directory -Path $toolTwo
    $receipt['synthetic_path']=$caseRoot

    $jsonPath=Join-Path $caseRoot 'dependency receipt.json'
    $initial=@{schema_version=1;revision='created';tool_paths=@($toolOne);nested=@{label=$specialName;enabled=$false}}
    Write-DependencyJson $jsonPath $initial
    $created=Read-Json $jsonPath
    Require ($created.schema_version -eq 1 -and $created.revision -ceq 'created' -and
        $created.tool_paths -is [Array] -and @($created.tool_paths).Count -eq 1 -and
        $created.tool_paths[0] -ceq $toolOne -and $created.nested.label -ceq $specialName -and
        $created.nested.enabled -eq $false) 'Write-DependencyJson creation changed schema or content.'
    Assert-NoPreparing $jsonPath
    Pass 'Write-DependencyJson creates UTF-8 JSON in the combined special-character path'

    $updated=@{schema_version=1;revision='updated';tool_paths=@($toolTwo,$toolOne);nested=@{label=$specialName;enabled=$true}}
    $createdJsonBytes=[IO.File]::ReadAllBytes($jsonPath)
    Write-DependencyJson $jsonPath $updated
    $changed=Read-Json $jsonPath
    Require ($changed.schema_version -eq 1 -and $changed.revision -ceq 'updated' -and
        $changed.tool_paths -is [Array] -and @($changed.tool_paths).Count -eq 2 -and
        $changed.tool_paths[0] -ceq $toolTwo -and $changed.tool_paths[1] -ceq $toolOne -and
        $changed.nested.label -ceq $specialName -and $changed.nested.enabled -eq $true) 'Write-DependencyJson replacement changed schema or content.'
    Assert-NoPreparing $jsonPath
    $jsonBackups=@(Get-SelectionBackups $jsonPath)
    Require ($jsonBackups.Count -eq 1) 'JSON replacement did not create an explicit previous-file backup.'
    Assert-SameBytes $jsonBackups[0].FullName $createdJsonBytes 'JSON replacement backup differs from its prior bytes.'
    Pass 'Write-DependencyJson replaces existing JSON and cleans its temporary file'

    $oldBytes=[IO.File]::ReadAllBytes($jsonPath)
    $lockedError=$null
    $hold=[IO.File]::Open($jsonPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        try { Write-DependencyJson $jsonPath @{schema_version=1;revision='must-not-replace'} }
        catch { $lockedError=$_ }
        Require ([bool]$lockedError) 'Write-DependencyJson unexpectedly replaced a target that denies delete/write sharing.'
        Assert-SameBytes $jsonPath $oldBytes 'Write-DependencyJson changed old bytes after a locked-target failure.'
        Assert-NoPreparing $jsonPath
    } finally { $hold.Dispose() }
    Assert-SameBytes $jsonPath $oldBytes 'Write-DependencyJson lost the locked target after handle release.'
    $receipt.failures+=@(@{case='Write-DependencyJson locked target';error=$lockedError.Exception.Message;old_bytes_preserved=$true;temporary_cleaned=$true})
    Pass 'Write-DependencyJson locked-target failure preserves exact old bytes and cleans temporary JSON'

    $SelectionRoot=Join-Path $caseRoot 'selection space'
    $script:SelectedToolPaths=@($toolOne)
    $selected=[pscustomobject]@{ready=$true;python=(Join-Path $toolOne 'python.exe');
        jupytext=(Join-Path $toolOne 'jupytext.exe');latex2text=(Join-Path $toolOne 'latex2text.exe');version='3.12.8'}
    Save-Selection $selected
    $selectionPath=Join-Path $SelectionRoot 'selected.json'
    Assert-Selection (Read-Json $selectionPath) $selected $script:SelectedToolPaths
    Require (@(Get-SelectionBackups $selectionPath).Count -eq 0) 'A new selection unexpectedly created a backup.'
    Assert-NoPreparing $selectionPath
    Pass 'Save-Selection creates its full schema with synthetic Python and existing tool directories'

    $createdBytes=[IO.File]::ReadAllBytes($selectionPath)
    $script:SelectedToolPaths=@($toolTwo,$toolOne)
    $nextSelected=[pscustomobject]@{ready=$true;python=(Join-Path $toolTwo 'python.exe');
        jupytext=(Join-Path $toolTwo 'jupytext.exe');latex2text=(Join-Path $toolTwo 'latex2text.exe');version='3.12.9'}
    Save-Selection $nextSelected
    Assert-Selection (Read-Json $selectionPath) $nextSelected $script:SelectedToolPaths
    $backups=@(Get-SelectionBackups $selectionPath)
    Require ($backups.Count -eq 1) 'Selection update did not retain exactly one prior-selection backup.'
    Assert-SameBytes $backups[0].FullName $createdBytes 'Selection update backup differs from the original selection.'
    Assert-NoPreparing $selectionPath
    Pass 'Save-Selection replaces existing JSON and retains the exact previous selection backup'

    $oldSelectionBytes=[IO.File]::ReadAllBytes($selectionPath)
    $backupNames=@($backups|ForEach-Object {$_.FullName})
    $lockedSelectionError=$null
    $hold=[IO.File]::Open($selectionPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        try { Save-Selection $selected }
        catch { $lockedSelectionError=$_ }
        Require ([bool]$lockedSelectionError) 'Save-Selection unexpectedly replaced a target that denies delete/write sharing.'
        Assert-SameBytes $selectionPath $oldSelectionBytes 'Save-Selection changed old bytes after a locked-target failure.'
        Assert-NoPreparing $selectionPath
        $afterBackups=@(Get-SelectionBackups $selectionPath)
        $newBackups=@($afterBackups|Where-Object {$_.FullName -notin $backupNames})
        Require ($afterBackups.Count -eq 2 -and $newBackups.Count -eq 1) 'Locked selection failed before preserving its existing-selection backup.'
        Assert-SameBytes $newBackups[0].FullName $oldSelectionBytes 'Locked selection backup differs from the retained selection.'
        Assert-SameBytes $backups[0].FullName $createdBytes 'Locked selection damaged the earlier backup.'
    } finally { $hold.Dispose() }
    Assert-SameBytes $selectionPath $oldSelectionBytes 'Save-Selection lost the locked target after handle release.'
    $receipt.failures+=@(@{case='Save-Selection locked target';error=$lockedSelectionError.Exception.Message;old_bytes_preserved=$true;temporary_cleaned=$true;prior_backups_preserved=$true})
    Pass 'Save-Selection locked-target failure preserves exact old bytes, backups and temporary cleanup'

    # Exercise only the production outer catch body. Its diagnostic writes are
    # forced to fail so a filesystem error cannot hide the original setup error.
    $setupCatches=@($setupAst.FindAll({param($node)
        $node -is [Management.Automation.Language.TryStatementAst] -and
        $node.CatchClauses.Count -gt 0 -and
        $node.CatchClauses[0].Body.Extent.Text -match 'python-probes\.json' -and
        $node.CatchClauses[0].Body.Extent.Text -match 'receipt\.json'
    },$true))
    Require ($setupCatches.Count -eq 1) 'Expected one setup diagnostic catch body.'
    $body=$setupCatches[0].CatchClauses[0].Body.Extent.Text
    $catchScript=[scriptblock]::Create($body.Substring(1,$body.Length-2))
    $script:DependencyRun=Join-Path $caseRoot 'synthetic diagnostic run'
    $script:PythonProbeDiagnostics=@()
    $script:DependencyChecks=@()
    $script:SyntheticDiagnosticWrites=@()
    $selectionSaved=$false
    # Deliberately replace the real writer only after all real-writer cases.
    function Write-DependencyJson([string]$Path,$Value) {
        $script:SyntheticDiagnosticWrites+=@($Path)
        throw 'diagnostic write sentinel'
    }
    $originalFailure=$null
    try {
        try { throw 'original TeX failure sentinel' }
        catch { . $catchScript }
    } catch { $originalFailure=$_ }
    Require ([bool]$originalFailure -and $originalFailure.Exception.Message -ceq 'original TeX failure sentinel') 'A diagnostic JSON failure hid the original setup exception.'
    Require ($script:SyntheticDiagnosticWrites.Count -eq 2 -and
        $script:SyntheticDiagnosticWrites[0] -ceq (Join-Path $script:DependencyRun 'python-probes.json') -and
        $script:SyntheticDiagnosticWrites[1] -ceq (Join-Path $script:DependencyRun 'receipt.json')) 'The setup catch did not independently attempt both diagnostic JSON writes.'
    $receipt['setup_catch']=@{original_error=$originalFailure.Exception.Message;attempted_paths=@($script:SyntheticDiagnosticWrites);diagnostic_error='diagnostic write sentinel'}
    Pass 'setup catch attempts both diagnostic writes and preserves the original TeX exception'
    $receipt.state='passed'
} catch {
    $receipt.state='failed'
    $receipt['error']=$_.Exception.Message
    throw
} finally { Save-Receipt }
