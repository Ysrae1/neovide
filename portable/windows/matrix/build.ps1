# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
$sourceDirectory = $PSScriptRoot
$cmake = (Get-Command cmake -ErrorAction Stop).Source
$platform = if ($Architecture -ieq 'arm64') { 'ARM64' } else { 'x64' }
& $cmake -S $sourceDirectory -B $BuildDirectory -G 'Visual Studio 17 2022' -A $platform
if ($LASTEXITCODE -ne 0) { throw "CMatrix configure failed: $LASTEXITCODE" }
& $cmake --build $BuildDirectory --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw "CMatrix build failed: $LASTEXITCODE" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($name in @('cmatrix-gm.exe', 'cmatrix-uni.exe', 'cmatrix-uni-native.exe')) {
    Copy-Item -LiteralPath (Join-Path (Join-Path $BuildDirectory 'Release') $name) -Destination (Join-Path $OutputDirectory $name)
}
& (Join-Path $OutputDirectory 'cmatrix-gm.exe') --help
if ($LASTEXITCODE -ne 0) { throw "CMatrix help check failed: $LASTEXITCODE" }
