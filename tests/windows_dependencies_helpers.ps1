#requires -Version 5.1
# Local synthetic files only; no package/network/process install or registry writes.
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[string]$WorkRoot=(Join-Path $env:TEMP ('glow-dependency-test-'+[Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $SourceRoot 'portable\windows\Dependency-Helpers.ps1')
if (Test-Path -LiteralPath $WorkRoot) { throw 'Fixture requires fresh WorkRoot.' }
$null=New-Item -ItemType Directory -Path $WorkRoot
$DependencyRoot=Join-Path $WorkRoot 'dependencies'
$owned=Join-Path $WorkRoot 'owned'
Initialize-DependencyDirectory $owned 'fixture-v1'
[IO.File]::WriteAllText((Join-Path $owned 'keep'),'partial output')
Initialize-DependencyDirectory $owned 'fixture-v1'
if ([IO.File]::ReadAllText((Join-Path $owned 'keep')) -cne 'partial output') { throw 'Resume overwrote partial output.' }
$unowned=Join-Path $WorkRoot 'unowned'; $null=New-Item -ItemType Directory -Path $unowned
$rejected=$false; try { Initialize-DependencyDirectory $unowned 'fixture-v1' } catch { $rejected=$true }
if (-not $rejected) { throw 'Unowned directory accepted.' }
Write-Output 'PASS owned partial directory reused and unowned directory preserved'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath=Join-Path $WorkRoot 'tool.zip'
$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
$entry=$zip.CreateEntry('tool/bin/tool.exe');$stream=$entry.Open();$bytes=[Text.Encoding]::ASCII.GetBytes('fixture');$stream.Write($bytes,0,$bytes.Length);$stream.Dispose();$zip.Dispose()
$expand=Join-Path $WorkRoot 'expand';$null=New-Item -ItemType Directory -Path $expand
Expand-DependencyZip $zipPath $expand
if ([IO.File]::ReadAllText((Join-Path $expand 'tool\bin\tool.exe')) -cne 'fixture') { throw 'Zip content missing.' }
$badZip=Join-Path $WorkRoot 'bad.zip';$zip=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create);$null=$zip.CreateEntry('../escaped.txt');$zip.Dispose()
$badOut=Join-Path $WorkRoot 'bad-out';$null=New-Item -ItemType Directory -Path $badOut
$rejected=$false;try { Expand-DependencyZip $badZip $badOut } catch { $rejected=$true }
if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $WorkRoot 'escaped.txt'))) { throw 'Zip traversal was not rejected.' }
Write-Output 'PASS archive extraction and traversal rejection'
$cache=Join-Path $DependencyRoot 'downloads-v1';Initialize-DependencyDirectory $cache 'glow-download-cache-v1'
Copy-Item -LiteralPath $zipPath -Destination (Join-Path $cache 'tool.zip')
$asset=[pscustomobject]@{filename='tool.zip';url='https://example.invalid/never-requested';sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant();download_size=(Get-Item -LiteralPath $zipPath).Length}
$actual=Get-DependencyAsset $asset
if ($actual -cne (Join-Path $cache 'tool.zip')) { throw 'Verified download cache was not reused.' }
[IO.File]::AppendAllText($actual,'tampered')
$rejected=$false;try {$null=Get-DependencyAsset $asset} catch {$rejected=$true}
if (-not $rejected -or -not (Test-Path -LiteralPath $actual)) { throw 'Tampered cache was accepted or removed.' }
Write-Output 'PASS exact cached digest reused and tampered bytes preserved/rejected'
$jupyter=Join-Path $WorkRoot 'jupyter'
$python=Join-Path $WorkRoot 'Existing environment\python.exe'
$null=New-Item -ItemType Directory -Path (Split-Path -Parent $python)
[IO.File]::WriteAllText($python,'not executed')
$specs=@{
    valid=@{argv=@($python,'-m','ipykernel_launcher','-f','{connection_file}')};
    duplicate=@{argv=@($python)};
    relative=@{argv=@('python.exe')};
    shell=@{argv=@((Join-Path $env:WINDIR 'System32\cmd.exe'),'/c','must-not-run')};
    missing=@{argv=@((Join-Path $WorkRoot 'missing\python.exe'))};
    scalar=@{argv=$python}
}
foreach ($name in $specs.Keys) {
    $directory=Join-Path $jupyter ('kernels\'+$name)
    $null=New-Item -ItemType Directory -Path $directory -Force
    Write-DependencyJson (Join-Path $directory 'kernel.json') $specs[$name]
}
$bad=Join-Path $jupyter 'kernels\broken';$null=New-Item -ItemType Directory -Path $bad
[IO.File]::WriteAllText((Join-Path $bad 'kernel.json'),'{')
$found=@(Get-JupyterPythonCandidates @($jupyter,(Join-Path $WorkRoot 'absent')) | Select-Object -Unique)
if ($found.Count -ne 1 -or $found[0] -cne $python) { throw 'Jupyter discovery accepted an unsafe/missing command or lost a valid Python path.' }
if ([IO.File]::ReadAllText($python) -cne 'not executed') { throw 'Discovery modified the existing interpreter.' }
Write-Output 'PASS Jupyter discovery uses existing absolute Python paths without running kernel arguments'
$selection=Join-Path $WorkRoot 'selected.json'
$keep=Split-Path -Parent $python
Write-DependencyJson $selection @{schema_version=1;tool_paths=@($keep,'relative',42,(Join-Path $WorkRoot 'missing-tool-dir'))}
$paths=@(Get-DependencySelectedPaths $selection)
if ($paths.Count -ne 1 -or $paths[0] -cne $keep) { throw 'Prior selected tool paths were lost or invalid paths accepted.' }
$primary=Join-Path $WorkRoot 'primary-tex';$fallback=Join-Path $WorkRoot 'fallback-tex'
$target=Get-DependencyTeXTarget $primary $fallback
if ($target.root -cne $primary -or $target.resume) { throw 'Fresh TeX root selection failed.' }
$null=New-Item -ItemType Directory -Path $primary
$target=Get-DependencyTeXTarget $primary $fallback
if ($target.root -cne $fallback -or $target.resume) { throw 'Unowned TeX root was adopted.' }
$null=New-Item -ItemType Directory -Path $fallback
[IO.File]::WriteAllText((Join-Path $fallback '.glow-tinytex-v1-owner.json'),'{}')
$target=Get-DependencyTeXTarget $primary $fallback
if ($target.root -cne $fallback -or -not $target.resume) { throw 'Owned fallback TeX install could not be resumed.' }
[IO.File]::WriteAllText((Join-Path $primary '.glow-tinytex-v1-owner.json'),'{}')
$target=Get-DependencyTeXTarget $primary $fallback
if ($target.root -cne $primary -or -not $target.resume) { throw 'Owned primary TeX install could not be resumed.' }
Write-Output 'PASS prior valid tool directories retained and owned primary/fallback TeX roots resume'
