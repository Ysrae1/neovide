#requires -Version 5.1
# Pure path/parent regression. Production resolver functions run with synthetic
# filesystem/short-name boundaries; the real parent uses a recording child.
# No downloads, installers, registry writes, VM or Windows native calls.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if (Test-Path -LiteralPath $WorkRoot) { throw 'Use a fresh TeX path-test WorkRoot.' }
$null=New-Item -ItemType Directory -Path $WorkRoot
$tokens=$null; $errors=$null
$source=Join-Path $SourceRoot 'portable/windows/tex/Install-TinyTeX.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors|Out-String) }
$preflight=@($ast.EndBlock.Statements|Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -ceq '$ResolveInstallRootOnly' })
if ($preflight.Count -ne 1 -or $preflight[0].Clauses[0].Item2.Statements.Count -ne 1 -or
    $preflight[0].Clauses[0].Item2.Statements[0] -isnot [Management.Automation.Language.ReturnStatementAst] -or
    $preflight[0].Clauses[0].Item2.Statements[0].Pipeline.Extent.Text -cne '$InstallRoot') {
    throw 'Read-only preflight must return the resolved root directly.'
}
$before=@($ast.EndBlock.Statements|Where-Object { $_.Extent.StartOffset -lt $preflight[0].Extent.StartOffset -and $_ -isnot [Management.Automation.Language.FunctionDefinitionAst] })
foreach ($statement in $before) {
    if ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -in @('$ErrorActionPreference','$InstallRoot')) { continue }
    if ($statement -is [Management.Automation.Language.PipelineAst] -and $statement.Extent.Text -match '^Set-StrictMode\b') { continue }
    throw ('Unexpected action before read-only preflight: '+$statement.Extent.Text)
}
$resolvedAssignments=@($before|Where-Object { $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$InstallRoot' })
if ($resolvedAssignments.Count -ne 1 -or $resolvedAssignments[0].Right.Extent.Text -notmatch '^Resolve-TeXInstallRoot\b') { throw 'Preflight must resolve the installation root before returning it.' }
Write-Output 'PASS read-only preflight returns before identity, run-directory, download and install actions'
foreach ($name in @('Test-TeXInstallRoot','Resolve-TeXInstallRoot')) {
    $found=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true))
    if ($found.Count -ne 1) { throw ('Expected production function '+$name) }
    Invoke-Expression $found[0].Extent.Text
}
$script:existing=@(); $script:shortNames=@{}; $script:probes=@(); $script:shortCalls=@()
function Test-Path([string]$LiteralPath,[string]$PathType) {
    if ($PathType -cne 'Container') { throw 'Resolver must query directory existence only.' }
    $script:probes+=$LiteralPath
    return $LiteralPath -in $script:existing
}
function Get-TeXShortPath([string]$Path) {
    $script:shortCalls+=$Path
    if ($script:shortNames.ContainsKey($Path)) { return $script:shortNames[$Path] }
    return $null
}
function Reset-PathCase([string[]]$Existing=@(),[hashtable]$ShortNames=@{}) {
    $script:existing=$Existing; $script:shortNames=$ShortNames
    $script:probes=@(); $script:shortCalls=@()
}
function Assert-Resolved([string]$InputPath,[string]$Expected,[string[]]$Probes=@(),[string[]]$Calls=@()) {
    $actual=@(Resolve-TeXInstallRoot $InputPath)
    if ($actual.Count -ne 1 -or $actual[0] -cne $Expected) { throw ('Wrong resolved root: '+$InputPath+' => '+($actual -join ',')) }
    if (($script:probes -join '|') -cne ($Probes -join '|') -or ($script:shortCalls -join '|') -cne ($Calls -join '|')) {
        throw ('Incorrect filesystem/native call order for '+$InputPath)
    }
}
function Assert-Rejected([string]$InputPath,[switch]$BeforeProbe,[switch]$NeedAliasHelp) {
    $message=$null
    try { $null=Resolve-TeXInstallRoot $InputPath } catch { $message=$_.Exception.Message }
    if (-not $message -or -not $message.Contains($InputPath)) { throw ('Rejected path must identify the actual root: '+$InputPath) }
    if ($BeforeProbe -and ($script:probes.Count -or $script:shortCalls.Count)) { throw ('Unsafe path reached the filesystem/native boundary: '+$InputPath) }
    if ($NeedAliasHelp -and ($message -notmatch '8\.3' -or $message -notmatch '-InstallRoot' -or $message -notmatch 'spaces|non-ASCII')) {
        throw 'Unusable alias must explain the path restriction and explicit recovery option.'
    }
}
$ordinary='C:\Users\Alice\AppData\Roaming\TinyTeX'
Reset-PathCase
Assert-Resolved $ordinary $ordinary
$spaceRoot='C:\Users\Chen Haoyang\AppData\Roaming\TinyTeX'
$spaceParent='C:\Users\Chen Haoyang\AppData\Roaming'
$shortParent='C:\Users\CHENHA~1\AppData\Roaming'
Reset-PathCase @($spaceParent) @{$spaceParent=$shortParent}
Assert-Resolved $spaceRoot ($shortParent+'\TinyTeX') @($spaceRoot,$spaceParent) @($spaceParent)
$chineseRoot='C:\Users\'+[char]0x5f20+[char]0x4e09+'\AppData\Roaming\TinyTeX'
$chineseParent=$chineseRoot.Substring(0,$chineseRoot.LastIndexOf('\'))
Reset-PathCase @($chineseParent) @{$chineseParent='C:\Users\ZHANGS~1\AppData\Roaming'}
Assert-Resolved $chineseRoot 'C:\Users\ZHANGS~1\AppData\Roaming\TinyTeX' @($chineseRoot,$chineseParent) @($chineseParent)
$missingRoot='C:\Users\Chen Haoyang\AppData\Local\Programs\NeovideGlow-TinyTeX'
$missingPrograms='C:\Users\Chen Haoyang\AppData\Local\Programs'
$existingLocal='C:\Users\Chen Haoyang\AppData\Local'
Reset-PathCase @($existingLocal) @{$existingLocal='C:\Users\CHENHA~1\AppData\Local'}
Assert-Resolved $missingRoot 'C:\Users\CHENHA~1\AppData\Local\Programs\NeovideGlow-TinyTeX' @($missingRoot,$missingPrograms,$existingLocal) @($existingLocal)
Reset-PathCase @($spaceRoot) @{$spaceRoot='C:\Users\CHENHA~1\AppData\Roaming\TinyTeX'}
Assert-Resolved $spaceRoot 'C:\Users\CHENHA~1\AppData\Roaming\TinyTeX' @($spaceRoot) @($spaceRoot)
Write-Output 'PASS unchanged safe root, space/Unicode user roots, missing suffixes and existing complete root'
foreach ($alias in @($null,$spaceParent,'C:\Users\STILL SPACE\AppData\Roaming')) {
    Reset-PathCase @($spaceParent) @{$spaceParent=$alias}
    Assert-Rejected $spaceRoot -NeedAliasHelp
    if ($script:shortCalls.Count -ne 1 -or $script:shortCalls[0] -cne $spaceParent) { throw 'Failed alias must be tried exactly once.' }
}
Reset-PathCase @('C:\') @{'C:\'='C:\'}
Assert-Rejected 'C:\Missing Space\TinyTeX' -NeedAliasHelp
$dangerous=@(';','"','%','!','^','&','|','<','>',[string][char]13,[string][char]10)
foreach ($character in $dangerous) {
    $candidate='C:\Users\Bad'+$character+'Name\TinyTeX'
    Reset-PathCase
    if (Test-TeXInstallRoot $candidate) { throw ('Dangerous root accepted: '+$candidate) }
    Assert-Rejected $candidate -BeforeProbe
}
foreach ($candidate in @('\\server\share\TinyTeX','TinyTeX','C:TinyTeX','\TinyTeX')) {
    Reset-PathCase
    Assert-Rejected $candidate -BeforeProbe
}
Write-Output 'PASS unavailable/unusable aliases and unsafe/non-local roots fail without alternate installation'
Remove-Item Function:\Test-Path

# Execute the complete production parent, replacing only its external dependency
# boundaries and TinyTeX child. Record preflight -> download -> install ordering
# and prove that selected.json uses the actual resolved installation root.
$fixture=Join-Path $WorkRoot 'parent-fixture'; $tex=Join-Path $fixture 'tex'
$null=New-Item -ItemType Directory -Path $tex -Force
Copy-Item -LiteralPath (Join-Path $SourceRoot 'portable/windows/Setup-LaTeX.ps1') -Destination (Join-Path $fixture 'Setup-LaTeX.ps1')
$utf8=New-Object Text.UTF8Encoding($false)
$events=Join-Path $WorkRoot 'events.jsonl'; $resolved=Join-Path $WorkRoot 'TEXSHORT'
$archive=Join-Path $WorkRoot 'TinyTeX.exe'
[IO.File]::WriteAllText($archive,'Synthetic local archive; never executed.',$utf8)
foreach ($name in @('asset-lock.json','fixture.tex')) { [IO.File]::WriteAllText((Join-Path $tex $name),'fixture',$utf8) }
[IO.File]::WriteAllText((Join-Path $fixture 'system-assets.lock.json'),'{"assets":{"tinytex":{"filename":"TinyTeX.exe"}}}',$utf8)
$worker=@'
param([string]$AssetDirectory,[string]$InstallRoot,[string]$RunRoot,[switch]$Resume,[switch]$NoUserPath,[switch]$AllowSeparateExistingTools,[string]$TeXMirror,[scriptblock]$ProgressCallback,[switch]$ResolveInstallRootOnly)
$event=@{phase=$(if($ResolveInstallRootOnly){'resolve'}else{'install'});root=$InstallRoot;resume=[bool]$Resume;no_user_path=[bool]$NoUserPath}
[IO.File]::AppendAllText('__EVENTS__',($event|ConvertTo-Json -Compress)+[Environment]::NewLine)
if($ResolveInstallRootOnly){if(Test-Path -LiteralPath '__BLOCK__'){throw 'Synthetic path resolution failed.'};return '__RESOLVED__'}
if($InstallRoot -cne '__RESOLVED__'){throw 'Installer did not receive the resolved root.'}
'@
$blocked=Join-Path $WorkRoot 'block-resolution'
$worker=$worker.Replace('__EVENTS__',$events.Replace("'","''")).Replace('__BLOCK__',$blocked.Replace("'","''")).Replace('__RESOLVED__',$resolved.Replace("'","''"))
[IO.File]::WriteAllText((Join-Path $tex 'Install-TinyTeX.ps1'),$worker,$utf8)
function Get-Command { return $null } # No existing native TeX for this fixture.
function Get-DependencyTeXTarget { [pscustomobject]@{root=$spaceRoot;resume=$true} }
function Get-DependencyAsset {
    [IO.File]::AppendAllText($events,'{"phase":"download"}'+[Environment]::NewLine)
    return $archive
}
function Set-DependencyStatus {}
function New-DependencyPhaseCallback { return {} }
function Write-DependencyJson([string]$Path,$Value) { [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 5),$utf8) }
$oldAppData=$env:APPDATA; $oldLocalAppData=$env:LOCALAPPDATA
try {
    $env:APPDATA=Join-Path $WorkRoot 'User With Space/Roaming'
    $env:LOCALAPPDATA=Join-Path $WorkRoot 'User With Space/Local'
    $run=Join-Path $WorkRoot 'parent-pass'
    & (Join-Path $fixture 'Setup-LaTeX.ps1') -DependencyRoot (Join-Path $WorkRoot 'dependencies') -RunRoot $run
    $records=@(Get-Content -LiteralPath $events|ForEach-Object {$_|ConvertFrom-Json})
    if (($records.phase -join ',') -cne 'resolve,download,install') { throw 'Parent must resolve the target before downloading and installing.' }
    if ($records[0].root -cne $spaceRoot -or $records[2].root -cne $resolved -or -not $records[2].resume -or -not $records[2].no_user_path) { throw 'Parent lost the requested/resolved root or resume/user-PATH policy.' }
    $selection=Get-Content -LiteralPath (Join-Path $run 'selected.json') -Raw|ConvertFrom-Json
    if ($selection.bin -cne (Join-Path $resolved 'bin\windows') -or $selection.reused) { throw 'Persisted selection does not point at the installed resolved root.' }

    # Replace the default-path fixture with the production target selector.
    # Passing one explicit root as both candidates must never select elsewhere.
    $helperAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'portable/windows/Dependency-Helpers.ps1'),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors|Out-String) }
    $targetHelper=@($helperAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-DependencyTeXTarget'},$true))
    if ($targetHelper.Count -ne 1) { throw 'Expected production TeX target selector.' }
    Invoke-Expression $targetHelper[0].Extent.Text
    $explicitFresh=Join-Path $WorkRoot 'Explicit Fresh TinyTeX'
    $explicitOwned=Join-Path $WorkRoot 'Explicit Owned TinyTeX'
    $null=New-Item -ItemType Directory -Path $explicitOwned
    $ownerMarker='.glow-tinytex-v1-owner.json'
    [IO.File]::WriteAllText((Join-Path $explicitOwned $ownerMarker),'{"operation":"glow-system-tinytex-v1","asset_sha256":"fixture-digest"}',$utf8)
    foreach ($case in @(@{root=$explicitFresh;resume=$false;name='explicit-fresh'},@{root=$explicitOwned;resume=$true;name='explicit-owned'})) {
        [IO.File]::WriteAllText($events,'',$utf8)
        $run=Join-Path $WorkRoot $case.name
        & (Join-Path $fixture 'Setup-LaTeX.ps1') -DependencyRoot (Join-Path $WorkRoot 'dependencies') -RunRoot $run -TeXInstallRoot $case.root
        $records=@(Get-Content -LiteralPath $events|ForEach-Object {$_|ConvertFrom-Json})
        if (($records.phase -join ',') -cne 'resolve,download,install') { throw ('Explicit root lost preflight ordering: '+$case.name) }
        if ($records[0].root -cne $case.root -or $records[2].root -cne $resolved -or $records[2].resume -ne $case.resume -or -not $records[2].no_user_path) {
            throw ('Explicit requested/resolved root or resume policy changed: '+$case.name)
        }
        $selection=Get-Content -LiteralPath (Join-Path $run 'selected.json') -Raw|ConvertFrom-Json
        if ($selection.bin -cne (Join-Path $resolved 'bin\windows') -or $selection.reused) { throw ('Explicit selection used the unresolved input: '+$case.name) }
    }
    $explicitUnowned=Join-Path $WorkRoot 'Explicit Existing Unowned TinyTeX'
    $null=New-Item -ItemType Directory -Path $explicitUnowned
    $sentinel=Join-Path $explicitUnowned 'keep.txt'; [IO.File]::WriteAllText($sentinel,'Existing user installation.',$utf8)
    $unownedTarget=Get-DependencyTeXTarget $explicitUnowned $explicitUnowned
    if ($unownedTarget.root -cne $explicitUnowned -or $unownedTarget.resume) { throw 'Explicit unowned directory was redirected or marked resumable.' }
    $ownedTarget=Get-DependencyTeXTarget $explicitOwned $explicitOwned
    if ($ownedTarget.root -cne $explicitOwned -or -not $ownedTarget.resume) { throw 'Explicit owned directory was redirected or lost resume.' }
    $ownerGuard=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text -match '^if \(Test-Path -LiteralPath \$InstallRoot\)' -and $node.Extent.Text -match 'resume requires this setup operation ownership marker'},$true))
    if ($ownerGuard.Count -ne 1) { throw 'Expected the real final-install ownership guard.' }
    foreach ($resume in @($false,$true)) {
        $rejected=$false
        try {
            & {
                param([string]$InstallRoot,[bool]$Resume,[string]$Guard)
                $ownerFile=Join-Path $InstallRoot '.glow-tinytex-v1-owner.json'
                Invoke-Expression $Guard
            } $explicitUnowned $resume $ownerGuard[0].Extent.Text
        } catch { $rejected=$_.Exception.Message -match 'existing TinyTeX installation was preserved' }
        if (-not $rejected) { throw 'Final installer guard accepted an explicit unowned directory.' }
    }
    if ([IO.File]::ReadAllText($sentinel) -cne 'Existing user installation.' -or (Test-Path -LiteralPath (Join-Path $explicitUnowned $ownerMarker))) { throw 'Ownership checks changed the existing directory.' }
    Write-Output 'PASS explicit roots retain input/resolved selection and real ownership/resume protection without fallback'

    [IO.File]::WriteAllText($events,'',$utf8)
    [IO.File]::WriteAllText($blocked,'block',$utf8)
    $failed=$false
    try { & (Join-Path $fixture 'Setup-LaTeX.ps1') -DependencyRoot (Join-Path $WorkRoot 'dependencies') -RunRoot (Join-Path $WorkRoot 'parent-fail') } catch { $failed=$_.Exception.Message -match 'Synthetic path resolution failed' }
    $records=@(Get-Content -LiteralPath $events|ForEach-Object {$_|ConvertFrom-Json})
    if (-not $failed -or $records.Count -ne 1 -or $records[0].phase -cne 'resolve') { throw 'Failed preflight reached download/install or its error was hidden.' }
    if (Test-Path -LiteralPath (Join-Path $WorkRoot 'parent-fail/selected.json')) { throw 'Failed preflight wrote a completed selection.' }

    # Both an explicit occupied folder and an occupied default fallback stop
    # before the path resolver, download, or install child is reached.
    $defaultPrimary=Join-Path $env:APPDATA 'TinyTeX'
    $defaultFallback=Join-Path $env:LOCALAPPDATA 'Programs\NeovideGlow-TinyTeX'
    foreach ($directory in @($defaultPrimary,$defaultFallback)) {
        $null=New-Item -ItemType Directory -Path $directory -Force
        [IO.File]::WriteAllText((Join-Path $directory 'keep.txt'),'Existing user installation.',$utf8)
    }
    foreach ($case in @(@{name='explicit-unowned';parameter=$explicitUnowned;expected=$explicitUnowned},@{name='default-fallback-unowned';parameter='';expected=$defaultFallback})) {
        [IO.File]::WriteAllText($events,'',$utf8)
        $run=Join-Path $WorkRoot $case.name
        $message=$null
        try { & (Join-Path $fixture 'Setup-LaTeX.ps1') -DependencyRoot (Join-Path $WorkRoot 'dependencies') -RunRoot $run -TeXInstallRoot $case.parameter } catch { $message=$_.Exception.Message }
        if (-not $message -or $message -notmatch 'already exists and is not owned by Glow' -or -not $message.Contains($case.expected)) { throw ('Existing folder was not rejected at the selected target: '+$case.name) }
        if ((Get-Item -LiteralPath $events).Length -ne 0 -or (Test-Path -LiteralPath (Join-Path $run 'selected.json'))) { throw ('Occupied folder reached resolution/download/install or selection: '+$case.name) }
    }
    foreach ($directory in @($explicitUnowned,$defaultPrimary,$defaultFallback)) {
        if ([IO.File]::ReadAllText((Join-Path $directory 'keep.txt')) -cne 'Existing user installation.' -or (Test-Path -LiteralPath (Join-Path $directory $ownerMarker))) { throw 'Parent preflight changed an existing unowned directory.' }
    }
    Write-Output 'PASS explicit/default unowned folders stop before resolve/download/install and preserve existing files'
} finally {
    $env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData
    Remove-Item Function:\Get-Command
}
Write-Output 'PASS real parent resolves before download, preserves resume, selects resolved bin and stops on failed preflight'
@{schema_version=1;state='passed';powershell=$PSVersionTable.PSVersion.ToString();checks=@('readonly-preflight','safe-root','space-user','unicode-user','missing-suffixes','existing-root','unavailable-alias','unsafe-root','parent-order','selected-resolved-root','explicit-root-forwarding','explicit-owned-resume','explicit-unowned-preserved','failed-preflight-no-download','unowned-preflight-no-download');windows_native_short_path_tested=$false;real_install=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'receipt.json') -Encoding UTF8
