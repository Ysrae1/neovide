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
