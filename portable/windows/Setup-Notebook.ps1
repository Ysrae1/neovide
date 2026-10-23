# Explicit private Notebook setup. The supplied Python itself is never changed.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$DataRoot,
    [Parameter(Mandatory=$true)][string]$ConfigRoot,
    [Parameter(Mandatory=$true)][string]$Nvim,
    [Parameter(Mandatory=$true)][string]$ReportPath,
    [string]$RequirementsPath,
    [string]$LatexRequirementsPath,
    [switch]$Install
)
$ErrorActionPreference = 'Stop'
if (-not $RequirementsPath) {
    $RequirementsPath = Join-Path $PSScriptRoot 'notebook-requirements.txt'
    if (-not (Test-Path -LiteralPath $RequirementsPath -PathType Leaf)) { $RequirementsPath = Join-Path $PSScriptRoot '..\payload\nvim\lua\config\media\runtime\requirements.txt' }
}
if (-not $LatexRequirementsPath) {
    $LatexRequirementsPath = Join-Path $PSScriptRoot 'latex-requirements.lock'
    if (-not (Test-Path -LiteralPath $LatexRequirementsPath -PathType Leaf)) { $LatexRequirementsPath = Join-Path $PSScriptRoot '..\payload\requirements-latex.lock' }
}
$arguments = @((Join-Path $PSScriptRoot 'setup-notebook.py'), '--data-root', $DataRoot,
    '--config-root', $ConfigRoot, '--nvim', $Nvim, '--requirements', $RequirementsPath,
    '--latex-requirements', $LatexRequirementsPath, '--report', $ReportPath)
if ($Install) { $arguments += '--install' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw "Notebook setup failed; see $ReportPath" }
