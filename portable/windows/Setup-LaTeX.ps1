#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DependencyRoot,
    [Parameter(Mandatory=$true)][string]$RunRoot,[string[]]$ToolPaths=@())
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Entered only after an explicit LaTeX feature selection. Never upgrade an
# existing TeX installation; prove it works or create an independent owned one.
if (Test-Path -LiteralPath $RunRoot) { throw 'A fresh LaTeX run directory is required; previous logs were preserved.' }
$null=New-Item -ItemType Directory -Path $RunRoot
$savedPath=$env:PATH
try {
    $env:PATH=($ToolPaths -join ';')+';'+$savedPath
    $existing=Get-Command xelatex.exe -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    $reused=$false; $bin=$null
    if ($existing) {
        $bin=Split-Path -Parent $existing.Source
        $latexmk=Join-Path $bin 'latexmk.exe'; $synctex=Join-Path $bin 'synctex.exe'
        if ((Test-Path -LiteralPath $latexmk) -and (Test-Path -LiteralPath $synctex)) {
            $project=Join-Path $RunRoot 'existing-tex-probe'
            $null=New-Item -ItemType Directory -Path $project
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tex\fixture.tex') -Destination (Join-Path $project 'fixture.tex')
            try {
                $null=Invoke-DependencyProcess -Executable $latexmk -Arguments @('-xelatex','-synctex=1','-interaction=nonstopmode','-halt-on-error','-file-line-error','-latexoption=-no-shell-escape','fixture.tex') -Name 'probe-existing-LaTeX' -TimeoutSeconds 180 -Directory $project
                if (-not (Test-Path -LiteralPath (Join-Path $project 'fixture.pdf')) -or -not (Test-Path -LiteralPath (Join-Path $project 'fixture.synctex.gz'))) { throw 'Existing TeX did not create PDF and SyncTeX.' }
                $null=Invoke-DependencyProcess $synctex @('help') 'probe-existing-SyncTeX' 20
                $reused=$true; Write-Host 'Reusing existing TeX after Chinese XeLaTeX / latexmk / SyncTeX checks.'
            } catch { Write-Warning 'Existing TeX did not pass the selected feature checks. It is preserved; setup will use a separate owned TinyTeX.' }
        }
    }
    if (-not $reused) {
        $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'system-assets.lock.json') -Raw -Encoding UTF8|ConvertFrom-Json
        $archive=Get-DependencyAsset $lock.assets.tinytex
        # TeX installer needs only the hash lock, fixture, and verified archive.
        $assets=Join-Path $RunRoot 'assets'; $null=New-Item -ItemType Directory -Path $assets
        foreach ($name in @('asset-lock.json','fixture.tex')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('tex\'+$name)) -Destination (Join-Path $assets $name) }
        # Hard link avoids a second download/cache copy; Copy-Item is a bounded
        # fallback for cross-volume filesystems.
        $target=Join-Path $assets $lock.assets.tinytex.filename
        try { $null=New-Item -ItemType HardLink -Path $target -Target $archive -ErrorAction Stop }
        catch { Copy-Item -LiteralPath $archive -Destination $target }
        $install=Join-Path $env:APPDATA 'TinyTeX'
        $owner=Join-Path $install '.glow-system-tinytex-v1-owner.json'
        if ((Test-Path -LiteralPath $install) -and -not (Test-Path -LiteralPath $owner)) {
            $install=Join-Path $env:LOCALAPPDATA 'Programs\NeovideGlow-TinyTeX'
            $owner=Join-Path $install '.glow-system-tinytex-v1-owner.json'
        }
        $resume=Test-Path -LiteralPath $owner -PathType Leaf
        & (Join-Path $PSScriptRoot 'tex\Install-TinyTeX.ps1') -AssetDirectory $assets -InstallRoot $install -RunRoot (Join-Path $RunRoot 'install') -Resume:$resume -NoUserPath -AllowSeparateExistingTools
        if (-not $?) { throw 'TinyTeX installation did not pass its compile checks.' }
        $bin=Join-Path $install 'bin\windows'
    }
    Write-DependencyJson (Join-Path $RunRoot 'selected.json') @{schema_version=1;status='passed';reused=$reused;bin=$bin}
} finally { $env:PATH=$savedPath }
