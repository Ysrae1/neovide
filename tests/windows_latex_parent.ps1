#requires -Version 5.1
<# Run from the logged-on Windows user, with an existing complete TeX and Git.
   Calls the real TeX-only parent without a redirected PowerShell supervisor.
   An independent watchdog bounds the test, including native grandchildren.
   No downloads, new installations, user selection writes, Python imports or GUI. #>
param(
    [string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory=$true)][string]$WorkRoot,
    [string]$SeedSelection,
    [ValidateRange(45,180)][int]$HardTimeoutSeconds=90
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$current=[Diagnostics.Process]::GetCurrentProcess()
if($identity.IsSystem -or $current.SessionId -eq 0){throw 'The actual logged-on user session is required.'}
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh LaTeX parent WorkRoot; previous evidence is preserved.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
$utf8=New-Object Text.UTF8Encoding($false)
function Save-TestJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),$utf8)}
function Test-Hash([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()};return 'absent'}
$userSelection=Join-Path $env:LOCALAPPDATA 'NeovideGlow\dependencies\selected.json'
$before=Test-Hash $userSelection
$stopFile=Join-Path $WorkRoot 'watchdog-stop'
$timeoutFile=Join-Path $WorkRoot 'watchdog-timeout.json'
# This child has no redirected streams and never wraps the parent invocation.
# On a deadline it records the exact owned tree, then terminates this test tree.
$watchdogProgram=@'
param([int]$OwnerPid,[long]$OwnerStarted,[int]$Seconds,[string]$StopFile,[string]$TimeoutFile)
$ErrorActionPreference='Stop'
$deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
while(-not(Test-Path -LiteralPath $StopFile)){
    $owner=Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue
    if(-not $owner -or $owner.StartTime.ToUniversalTime().Ticks -ne $OwnerStarted){exit 0}
    if([DateTime]::UtcNow -ge $deadline){
        $all=@(Get-CimInstance Win32_Process);$ids=@($OwnerPid)
        do{$count=$ids.Count;$ids+=@($all|Where-Object {$ids -contains $_.ParentProcessId -and $ids -notcontains $_.ProcessId}|ForEach-Object {$_.ProcessId})}while($ids.Count -gt $count)
        $record=@{state='failed';timed_out=$true;owner_pid=$OwnerPid;deadline_seconds=$Seconds;owned_tree=@($all|Where-Object {$ids -contains $_.ProcessId}|Select-Object ProcessId,ParentProcessId,CreationDate,ExecutablePath,CommandLine)}
        [IO.File]::WriteAllText($TimeoutFile,($record|ConvertTo-Json -Depth 7),(New-Object Text.UTF8Encoding($false)))
        & (Join-Path $env:WINDIR 'System32\taskkill.exe') /PID $OwnerPid /T /F | Out-Null
        exit 1
    }
    Start-Sleep -Milliseconds 250
}
'@
$watchdogPath=Join-Path $WorkRoot 'Watch-LaTeXParent.ps1'
[IO.File]::WriteAllText($watchdogPath,$watchdogProgram,$utf8)
$command='& '+"'"+$watchdogPath.Replace("'","''")+"'"+' -OwnerPid '+$current.Id+' -OwnerStarted '+$current.StartTime.ToUniversalTime().Ticks+' -Seconds '+$HardTimeoutSeconds+' -StopFile '+"'"+$stopFile.Replace("'","''")+"'"+' -TimeoutFile '+"'"+$timeoutFile.Replace("'","''")+"'"
$watchdog=New-Object Diagnostics.Process
$watchdog.StartInfo.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$watchdog.StartInfo.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$watchdog.StartInfo.UseShellExecute=$false;$watchdog.StartInfo.CreateNoWindow=$true
$receipt=[ordered]@{schema_version=1;state='started';identity=$identity.Name;session_id=$current.SessionId;started_utc=[DateTime]::UtcNow.ToString('o');hard_timeout_seconds=$HardTimeoutSeconds;user_selection_before=$before;python_imports_repeated=$false;downloads=0;new_installations=0}
$savedPath=$env:PATH
$watchdogStarted=$false
try{
    if(-not $watchdog.Start()){throw 'Could not start the owned deadline watchdog.'}
    $watchdogStarted=$true
    $receipt.watchdog_pid=$watchdog.Id
    $selection=Join-Path $WorkRoot 'selection';$deps=Join-Path $WorkRoot 'dependencies'
    $null=New-Item -ItemType Directory -Path $selection,(Join-Path $deps 'downloads-v1')
    [IO.File]::WriteAllText((Join-Path $deps 'downloads-v1\reuse-only.txt'),'Unowned guard: no download or new installation is allowed.',$utf8)
    $seed=@{schema_version=1;tool_paths=@();python=(Join-Path $WorkRoot 'retained-python.exe');jupytext='retained-jupytext';latex2text='retained-latex2text';qa_retained='preserve value'}
    if($SeedSelection){$prior=Get-Content -LiteralPath $SeedSelection -Raw -Encoding UTF8|ConvertFrom-Json;foreach($property in $prior.PSObject.Properties){$seed[$property.Name]=$property.Value}}
    Save-TestJson (Join-Path $selection 'selected.json') $seed
    $env:PATH=(@($seed.tool_paths) -join ';')+';'+$savedPath
    $sourceHashes=[ordered]@{}
    foreach($name in @('Setup-Dependencies.ps1','Setup-LaTeX.ps1','Dependency-Helpers.ps1','tex\fixture.tex')){$sourceHashes[$name]=Test-Hash (Join-Path $SourceRoot ('portable\windows\'+$name))}
    $receipt.source_sha256=$sourceHashes
    # An explicitly absent interpreter avoids re-running Python inspection.
    $report=& (Join-Path $SourceRoot 'portable\windows\Setup-Dependencies.ps1') -InstallLatex -Python (Join-Path $WorkRoot 'intentionally-absent-python.exe') -Json -DependencyRoot $deps -SelectionRoot $selection|ConvertFrom-Json
    Save-TestJson (Join-Path $WorkRoot 'parent-report.json') $report
    if($report.status -cne 'passed' -or -not $report.latex_checked -or -not $report.latex_ready){throw 'Real TeX parent did not pass.'}
    if(@($report.python_probes).Count){throw 'The TeX-only check repeated Python imports.'}
    $runs=@(Get-ChildItem -LiteralPath (Join-Path $deps 'runs') -Directory)
    if($runs.Count -ne 1){throw 'Expected one parent run.'}
    $tex=Get-Content -LiteralPath (Join-Path $runs[0].FullName 'tex\selected.json') -Raw|ConvertFrom-Json
    if($tex.status -cne 'passed' -or -not $tex.reused){throw 'Existing TeX was not reused.'}
    $checks=@($report.checks)
    if($checks.Count -ne 2){throw 'Expected the Chinese latexmk and SyncTeX checks only.'}
    foreach($check in $checks){if($check.exit_code -ne 0 -or $check.timed_out -or -not $check.output_drain_complete){throw ('Incomplete native child: '+$check.name)}}
    $project=Join-Path $runs[0].FullName 'tex\existing-tex-probe'
    $pdf=Join-Path $project 'fixture.pdf';$synctex=Join-Path $project 'fixture.synctex.gz'
    if((Get-Item -LiteralPath $pdf).Length -le 5 -or (Get-Item -LiteralPath $synctex).Length -le 0){throw 'Missing PDF or SyncTeX.'}
    $stream=[IO.File]::OpenRead($pdf);try{$header=New-Object byte[] 5;$null=$stream.Read($header,0,5)}finally{$stream.Dispose()}
    if([Text.Encoding]::ASCII.GetString($header) -cne '%PDF-'){throw 'Invalid PDF header.'}
    $after=Get-Content -LiteralPath (Join-Path $selection 'selected.json') -Raw|ConvertFrom-Json
    foreach($key in @('python','jupytext','latex2text','qa_retained')){if($after.$key -cne $seed[$key]){throw ('Retained selection changed: '+$key)}}
    foreach($path in @($seed.tool_paths)){if(@($after.tool_paths) -notcontains $path){throw ('Retained tool path lost: '+$path)}}
    if((Test-Hash $userSelection) -cne $before){throw 'Actual user selection changed.'}
    if(@(Get-ChildItem -LiteralPath (Join-Path $deps 'downloads-v1') -Force).Count -ne 1 -or (Test-Path -LiteralPath (Join-Path $deps 'programs-v1')) -or (Test-Path -LiteralPath (Join-Path $deps 'notebook-v1'))){throw 'Reuse-only guard changed or a new environment was created.'}
    $receipt.state='passed';$receipt.process_checks=$checks;$receipt.tex_reused=$true
    $receipt.pdf=@{path=$pdf;bytes=(Get-Item -LiteralPath $pdf).Length;sha256=Test-Hash $pdf}
    $receipt.synctex=@{path=$synctex;bytes=(Get-Item -LiteralPath $synctex).Length;sha256=Test-Hash $synctex}
    $receipt.selection_fields_preserved=$true
}catch{$receipt.state='failed';$receipt.error=$_.Exception.Message;throw}
finally{
    $env:PATH=$savedPath
    [IO.File]::WriteAllText($stopFile,'completed',$utf8)
    if($watchdogStarted -and -not $watchdog.HasExited -and -not $watchdog.WaitForExit(5000)){$watchdog.Kill();$null=$watchdog.WaitForExit(1000)}
    $receipt.watchdog_finished=($watchdogStarted -and $watchdog.HasExited)
    $receipt.user_selection_after=Test-Hash $userSelection
    $receipt.completed_utc=[DateTime]::UtcNow.ToString('o')
    Save-TestJson (Join-Path $WorkRoot 'receipt.json') $receipt
    $watchdog.Dispose()
}
Write-Output 'PASS real logged-on-user TeX parent, Chinese XeLaTeX PDF, SyncTeX, retained selection and no download/install'
