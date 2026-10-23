#requires -Version 5.1
# Installer entrypoint; the configuration owns the implementation used by Lazy.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$BuildDirectory
)
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '..\payload\nvim\lua\config\platform\avante_build.ps1'
& $helper -Source $Source -Architecture $Architecture -BuildDirectory $BuildDirectory
