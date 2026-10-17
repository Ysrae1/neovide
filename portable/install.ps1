#requires -Version 5.1
<#
.SYNOPSIS
Build the pinned Windows Neovide Glow frontend and install its Unix environment in WSL2.
.DESCRIPTION
Run -Plan or -Doctor first. Both modes are read-only and never start a WSL distro.
Normal execution may install missing build tools through interactive WinGet installers.
WSL installation, a required reboot, and Ubuntu's first-user setup are separate resumable steps.
Existing Neovide installations and processes are never replaced or stopped.

Official references checked for this implementation:
https://neovide.dev/installation.html
https://neovide.dev/command-line-reference.html
https://learn.microsoft.com/windows/wsl/install
https://learn.microsoft.com/windows/wsl/basic-commands

Neovide's pinned source supports --wsl, but NOT --wsl-distro. It launches the default
WSL distribution. Changing that default requires the explicit -UseDistroAsDefault switch.
#>
[CmdletBinding()]
param(
    [string]$Manifest = (Join-Path $PSScriptRoot 'manifest.json'),
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'NeovideGlow'),
    [string]$Distro = 'Ubuntu-24.04',
    [switch]$Plan,
    [switch]$Doctor,
    [switch]$UseDistroAsDefault
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Plan -and $Doctor) { throw 'Choose either -Plan or -Doctor.' }
if ($env:OS -ne 'Windows_NT') { throw 'Run install.ps1 on Windows. Use install.sh on macOS.' }
if ($Distro -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Use a standard WSL distribution name such as Ubuntu-24.04.' }

function Read-RequiredValue([object]$Object, [string]$Path) {
    $value = $Object
    foreach ($key in $Path.Split('.')) {
        if ($null -eq $value -or $null -eq $value.PSObject.Properties[$key]) {
            throw "Missing required manifest field: $Path"
        }
        $value = $value.$key
    }
    if ([string]::IsNullOrWhiteSpace([string]$value)) { throw "Empty manifest field: $Path" }
    return [string]$value
}

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    Write-Host ('=> ' + $Command + ' ' + ($Arguments -join ' '))
    & $Command @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE." }
}

function Get-CommandPath([string]$Name, [string[]]$Candidates = @()) {
    $found = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath;$env:Path"
}

function Get-VsInstallation {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $result = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0) { throw "vswhere failed with exit code $LASTEXITCODE." }
    if ($result) { return ([string]($result | Select-Object -First 1)).Trim() }
    return $null
}

function Get-WslRegistration {
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $root)) { return $null }
    foreach ($key in Get-ChildItem $root) {
        $properties = Get-ItemProperty $key.PSPath
        if ($properties.DistributionName -eq $Distro) { return $properties }
    }
    return $null
}

function Get-DefaultDistro {
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $root)) { return $null }
    $properties = Get-ItemProperty $root
    if ($null -eq $properties.PSObject.Properties['DefaultDistribution']) { return $null }
    $key = Join-Path $root $properties.DefaultDistribution
    if (Test-Path $key) { return (Get-ItemProperty $key).DistributionName }
    return $null
}

function Install-WinGetPackage([string]$Id, [string]$Override) {
    $winget = Get-CommandPath 'winget.exe'
    if (-not $winget) { throw "WinGet is missing. Install Microsoft's App Installer, reopen PowerShell, and rerun. Required package: $Id" }
    $arguments = @('install', '--exact', '--id', $Id, '--source', 'winget', '--interactive')
    if ($Override) { $arguments += @('--override', $Override) }
    # Do not auto-accept package/source agreements; WinGet displays its normal prompts.
    & $winget @arguments | Out-Host
    if ($LASTEXITCODE -in @(3010, 1641, -1978335188)) {
        throw "The $Id installer requires a Windows restart. Restart, then rerun this script."
    }
    if ($LASTEXITCODE -ne 0) { throw "WinGet could not install $Id (exit $LASTEXITCODE). Review the displayed installer error." }
    Refresh-ProcessPath
}

function Ensure-Tool([string]$Name, [string]$Package, [string[]]$Candidates = @()) {
    $tool = Get-CommandPath $Name $Candidates
    if (-not $tool) {
        Install-WinGetPackage $Package ''
        $tool = Get-CommandPath $Name $Candidates
        if (-not $tool) { throw "$Name is still unavailable. Finish its installer, open a new PowerShell, and rerun." }
    }
    $toolDirectory = Split-Path -Parent $tool
    if ($env:Path.Split(';') -notcontains $toolDirectory) { $env:Path = "$toolDirectory;$env:Path" }
    return $tool
}

function Ensure-Wsl {
    $wsl = Get-CommandPath 'wsl.exe'
    $registration = Get-WslRegistration
    if (-not $wsl -or -not $registration) {
        if (-not $wsl) { $wsl = Join-Path $env:WINDIR 'System32\wsl.exe' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "WSL or $Distro is missing. Open administrator PowerShell, run 'wsl --install -d $Distro --no-launch', restart if requested, then launch '$Distro' once to create a Linux user. Rerun this script from your ordinary Windows account."
        }
        if (-not (Test-Path -LiteralPath $wsl)) { throw 'WSL is unavailable on this Windows edition. Windows 10 build 19041+ or Windows 11 is required.' }
        Invoke-Checked $wsl @('--install', '-d', $Distro, '--no-launch')
        throw "WSL installation finished. Restart Windows if requested, launch '$Distro' to create your Linux username/password, then rerun this script."
    }
    if ($registration.Version -ne 2) {
        throw "$Distro is not using WSL2. Back up important distro data, run 'wsl --set-version $Distro 2', and rerun."
    }
    $linuxUserId = & $wsl -d $Distro --exec id -u
    if ($LASTEXITCODE -ne 0) { throw "$Distro could not start. Complete its first-run setup or resolve the displayed WSL error, then rerun." }
    if (([string]$linuxUserId).Trim() -eq '0') {
        throw "$Distro currently starts as root. Complete Ubuntu's normal first-user setup and configure a non-root default user, then rerun."
    }
    if ((Get-DefaultDistro) -ne $Distro) {
        if (-not $UseDistroAsDefault) {
            throw "Neovide --wsl uses the default WSL distro. Current default: $(Get-DefaultDistro). Rerun with -UseDistroAsDefault to explicitly select $Distro, or run 'wsl --set-default $Distro' yourself."
        }
        Invoke-Checked $wsl @('--set-default', $Distro)
    }
    return $wsl
}

function Convert-ToWslPath([string]$Wsl, [string]$WindowsPath) {
    $result = & $Wsl -d $Distro --exec wslpath -a -u $WindowsPath
    if ($LASTEXITCODE -ne 0) { throw "Could not translate Windows path for WSL: $WindowsPath" }
    return ([string]$result).Trim()
}

function Install-UserFonts([string[]]$FontDirectories) {
    Add-Type -AssemblyName System.Drawing
    $fonts = @()
    foreach ($directory in $FontDirectories) {
        if ($directory -and (Test-Path -LiteralPath $directory -PathType Container)) {
            $fonts = @(Get-ChildItem -LiteralPath $directory -Recurse -File | Where-Object { $_.Extension -in @('.ttf', '.otf') })
            if ($fonts.Count -gt 0) { break }
        }
    }
    if ($fonts.Count -eq 0) {
        $collection = New-Object System.Drawing.Text.InstalledFontCollection
        try { $alreadyInstalled = @($collection.Families | Where-Object { $_.Name -eq 'FiraCode Nerd Font Mono' }).Count -gt 0 }
        finally { $collection.Dispose() }
        if (-not $alreadyInstalled) {
            throw 'FiraCode Nerd Font Mono is missing. Install the bundled payload/fonts/*.ttf using Windows Font Settings (Install for this user), or rerun after the shared installer has downloaded the fonts. Linux font installation alone does not install Windows GUI fonts.'
        }
        Write-Host 'FiraCode Nerd Font Mono is already installed in Windows.'
        return
    }
    $userFontDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontRegistry = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $null = New-Item -ItemType Directory -Path $userFontDirectory -Force
    $null = New-Item -Path $fontRegistry -Force
    if (-not ('NeovideGlow.FontApi' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace NeovideGlow {
    public static class FontApi {
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
        public static extern int AddFontResourceEx(string path, uint flags, IntPtr reserved);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam,
            IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    }
}
'@
    }
    foreach ($font in $fonts) {
        $destination = Join-Path $userFontDirectory $font.Name
        if (Test-Path -LiteralPath $destination) {
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $font.FullName -Algorithm SHA256).Hash) {
                throw "A different font already uses $destination. It was preserved; remove or rename it through Windows Font Settings before retrying."
            }
        } else { Copy-Item -LiteralPath $font.FullName -Destination $destination }
        $label = $font.BaseName + $(if ($font.Extension -eq '.otf') { ' (OpenType)' } else { ' (TrueType)' })
        $null = New-ItemProperty -LiteralPath $fontRegistry -Name $label -PropertyType String -Value $destination -Force
        $null = [NeovideGlow.FontApi]::AddFontResourceEx($destination, 0, [IntPtr]::Zero)
    }
    $fontChangeResult = [UIntPtr]::Zero
    $null = [NeovideGlow.FontApi]::SendMessageTimeout([IntPtr]0xffff, 0x001d, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$fontChangeResult)
    Write-Host "Installed/verified $($fonts.Count) font files for the current Windows user. Other users' fonts were not changed."
}

function Write-WindowsConfig([string]$Source, [string]$Destination) {
    $topLevel = $true
    $lines = @('# Versioned Windows configuration; the existing user Neovide configuration is untouched.', 'frame = "full"', 'wsl = true')
    foreach ($line in Get-Content -LiteralPath $Source -Encoding UTF8) {
        if ($line -match '^\s*\[') { $topLevel = $false }
        # The source is the approved shared appearance. Only platform-specific launch keys change.
        if ($topLevel -and $line -match '^\s*(?:neovim-bin|frame|title-hidden|wsl|icon|system-[A-Za-z-]+)\s*=') { continue }
        $lines += $line
    }
    [IO.File]::WriteAllLines($Destination, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
}

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Manifest not found: $Manifest. Keep the complete release bundle together." }
$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$data = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$repo = Read-RequiredValue $data 'neovide.repo'
$commit = Read-RequiredValue $data 'neovide.commit'
$rustVersion = Read-RequiredValue $data 'neovide.rust_toolchain'
$stackId = Read-RequiredValue $data 'stack_id'
if ($repo -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$') { throw 'Neovide source must be an explicit GitHub HTTPS repository.' }
if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'The Neovide commit must be a full 40-character SHA.' }
if ($rustVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'The Rust toolchain must be an exact release version.' }
if ($stackId -notmatch '^[A-Za-z0-9_.-]+$') { throw 'stack_id must contain only letters, numbers, dots, underscores, and hyphens.' }
$target = 'x86_64-pc-windows-msvc'
$toolchain = "$rustVersion-$target"
$shellInstaller = Join-Path $PSScriptRoot 'install.sh'
if (-not (Test-Path -LiteralPath $shellInstaller -PathType Leaf)) { throw "Shared installer missing: $shellInstaller" }
$payload = Join-Path $PSScriptRoot 'payload'
$payloadIcon = Join-Path $payload 'windows-icon.ico'
$payloadConfig = Join-Path $payload 'neovide\config.toml'
foreach ($requiredFile in @($payloadIcon, $payloadConfig)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Required release payload missing: $requiredFile" }
}

$detectedTools = [ordered]@{
    Git = Get-CommandPath 'git.exe' @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'))
    Rustup = Get-CommandPath 'rustup.exe' @((Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'))
    CMake = Get-CommandPath 'cmake.exe' @((Join-Path $env:ProgramFiles 'CMake\bin\cmake.exe'))
    LLVM = Get-CommandPath 'clang.exe' @((Join-Path $env:ProgramFiles 'LLVM\bin\clang.exe'))
    Ninja = Get-CommandPath 'ninja.exe'
    MSVC = Get-VsInstallation
    WSL = Get-CommandPath 'wsl.exe'
    Distro = [bool](Get-WslRegistration)
    DefaultDistro = Get-DefaultDistro
}
Write-Host "Pinned Neovide Glow source: $repo @ $commit"
Write-Host "Rust $rustVersion / $target; Linux environment: $Distro (WSL2)"
Write-Host "Output directory: $InstallRoot"
foreach ($entry in $detectedTools.GetEnumerator()) { Write-Host ('{0,-15} {1}' -f $entry.Key, $entry.Value) }
if ($Plan) {
    Write-Host 'Plan only: install missing Windows build prerequisites through interactive WinGet; ensure WSL2 and a non-root Ubuntu user; run the shared pinned Linux installer; install the downloaded fonts for this Windows user; build the exact Glow commit with cargo --locked plus the approved icon overlay; write a separate runnable directory, configuration and launcher.'
    Write-Host 'No files, packages, default distro, running apps, or settings were changed.'
    return
}
if ($Doctor) {
    $missing = @($detectedTools.GetEnumerator() | Where-Object { -not $_.Value })
    if ($missing.Count -gt 0) { Write-Warning ('Missing prerequisites: ' + (($missing | ForEach-Object { $_.Key }) -join ', ')) }
    if ($detectedTools.DefaultDistro -ne $Distro) { Write-Warning "Neovide --wsl requires $Distro as the default distro for this bundle." }
    Write-Host 'Read-only checks complete. Windows compilation and WSL configuration have not been tested by this mode.'
    return
}
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This Windows build entry currently supports x64 Windows. Windows ARM64 has not been validated.' }

$wsl = Ensure-Wsl
$git = Ensure-Tool 'git.exe' 'Git.Git' @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'))
$null = Ensure-Tool 'cmake.exe' 'Kitware.CMake' @((Join-Path $env:ProgramFiles 'CMake\bin\cmake.exe'))
$clang = Ensure-Tool 'clang.exe' 'LLVM.LLVM' @((Join-Path $env:ProgramFiles 'LLVM\bin\clang.exe'))
$null = Ensure-Tool 'ninja.exe' 'Ninja-build.Ninja'
$vsPath = Get-VsInstallation
if (-not $vsPath) {
    Install-WinGetPackage 'Microsoft.VisualStudio.2022.BuildTools' '--wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    $vsPath = Get-VsInstallation
    if (-not $vsPath) { throw 'MSVC C++ build tools are still unavailable. Complete the Visual Studio installer with Desktop development with C++, then rerun.' }
}
$devShell = Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
Import-Module $devShell
Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
$env:LIBCLANG_PATH = Split-Path -Parent $clang
$rustup = Ensure-Tool 'rustup.exe' 'Rustlang.Rustup' @((Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'))
Invoke-Checked $rustup @('toolchain', 'install', $toolchain, '--profile', 'minimal', '--no-self-update')
Invoke-Checked $rustup @('target', 'add', '--toolchain', $toolchain, $target)
$cargo = Get-CommandPath 'cargo.exe' @((Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'))
if (-not $cargo) { throw 'Rustup is present but cargo.exe is missing. Repair the Rustup installation and rerun.' }

$wslScript = Convert-ToWslPath $wsl (Resolve-Path -LiteralPath $shellInstaller).Path
$wslManifest = Convert-ToWslPath $wsl $manifestPath
Invoke-Checked $wsl @('-d', $Distro, '--exec', 'bash', $wslScript, '--target', 'wsl', '--manifest', $wslManifest)
$linuxHomeOutput = & $wsl -d $Distro --exec printenv HOME
if ($LASTEXITCODE -ne 0) { throw 'Could not read the Linux user home after installing the WSL environment.' }
$linuxHome = ([string]$linuxHomeOutput).Trim()
if ($linuxHome -notmatch '^/[A-Za-z0-9_./-]+$') { throw 'The Linux home path cannot be safely passed to the pinned Neovide WSL command. Use a standard Ubuntu home directory containing letters, digits, underscores, dots, and hyphens.' }
$linuxStack = "$linuxHome/.local/share/neovide-glow/stacks/$stackId"
$linuxNvim = "$linuxStack/bin/nvim"
Invoke-Checked $wsl @('-d', $Distro, '--exec', 'test', '-x', $linuxNvim)
$linuxStackUnc = '\\wsl.localhost\' + $Distro + $linuxStack.Replace('/', '\')
$legacyStackUnc = '\\wsl$\' + $Distro + $linuxStack.Replace('/', '\')
Install-UserFonts @((Join-Path $payload 'fonts'), (Join-Path $linuxStackUnc 'payload\fonts'), (Join-Path $legacyStackUnc 'payload\fonts'))

$buildRoot = Join-Path $InstallRoot ('build-' + $commit.Substring(0, 12))
$sourceRoot = Join-Path $buildRoot 'source'
$managedIcon = Join-Path $sourceRoot 'assets\neovide.ico'
$iconMarker = Join-Path $buildRoot 'managed-icon.sha256'
$freshCheckout = $false
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    $null = New-Item -ItemType Directory -Path $buildRoot -Force
    Invoke-Checked $git @('-c', 'core.longpaths=true', 'clone', '--no-checkout', $repo, $sourceRoot)
    $freshCheckout = $true
}
$existingRepo = & $git -C $sourceRoot remote get-url origin
if ($LASTEXITCODE -ne 0 -or ([string]$existingRepo).Trim().TrimEnd('/') -ne $repo.TrimEnd('/')) { throw "Existing source checkout has a different origin: $sourceRoot" }
if (-not $freshCheckout) {
    $dirty = @(& $git -C $sourceRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the source checkout.' }
    if ($dirty.Count -gt 0) {
        $onlyManagedIcon = $dirty.Count -eq 1 -and $dirty[0] -eq ' M assets/neovide.ico'
        $matchesMarker = $false
        if ($onlyManagedIcon -and (Test-Path -LiteralPath $iconMarker) -and (Test-Path -LiteralPath $managedIcon)) {
            $matchesMarker = (Get-FileHash -LiteralPath $managedIcon -Algorithm SHA256).Hash -eq (Get-Content -LiteralPath $iconMarker -Raw).Trim()
        }
        if (-not $matchesMarker) { throw "Existing build checkout has unexpected local edits; they were preserved: $sourceRoot" }
        Invoke-Checked $git @('-C', $sourceRoot, 'restore', '--worktree', '--', 'assets/neovide.ico')
    }
}
Invoke-Checked $git @('-C', $sourceRoot, '-c', 'core.longpaths=true', 'fetch', 'origin', $commit)
Invoke-Checked $git @('-C', $sourceRoot, '-c', 'core.longpaths=true', 'checkout', '--detach', $commit)
$resolvedCommit = & $git -C $sourceRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or ([string]$resolvedCommit).Trim() -ne $commit) { throw 'Source commit verification failed.' }
# The pinned build.rs embeds exactly this file. Mark the managed overlay for safe reruns.
Copy-Item -LiteralPath $payloadIcon -Destination $managedIcon -Force
$approvedIconHash = (Get-FileHash -LiteralPath $managedIcon -Algorithm SHA256).Hash
Set-Content -LiteralPath $iconMarker -Value $approvedIconHash -Encoding ASCII
$env:CARGO_TARGET_DIR = Join-Path $buildRoot 'target'
Push-Location $sourceRoot
try {
    Invoke-Checked $cargo @("+$toolchain", 'build', '--release', '--locked', '--target', $target)
} finally { Pop-Location }

$builtExe = Join-Path $env:CARGO_TARGET_DIR "$target\release\neovide.exe"
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) { throw "Build completed without expected executable: $builtExe" }
$releaseRoot = Join-Path $InstallRoot ('neovide-' + $commit.Substring(0, 12))
$null = New-Item -ItemType Directory -Path $releaseRoot -Force
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $releaseRoot 'neovide.exe') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'LICENSE') -Destination (Join-Path $releaseRoot 'LICENSE-Neovide.txt') -Force
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $releaseRoot 'manifest.json') -Force
Copy-Item -LiteralPath $payloadIcon -Destination (Join-Path $releaseRoot 'neovide.ico') -Force
Write-WindowsConfig $payloadConfig (Join-Path $releaseRoot 'config.toml')
$powershellLauncher = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$NeovideArguments)
$ErrorActionPreference = 'Stop'
$lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
$defaultId = (Get-ItemProperty $lxss).DefaultDistribution
$defaultName = (Get-ItemProperty (Join-Path $lxss $defaultId)).DistributionName
if ($defaultName -ne '__DISTRO__') { throw 'This stack uses __DISTRO__; Neovide --wsl uses the default distro. Run wsl --set-default __DISTRO__ before launching.' }
$env:NEOVIDE_CONFIG = Join-Path $PSScriptRoot 'config.toml'
& (Join-Path $PSScriptRoot 'neovide.exe') --wsl --neovim-bin '__LINUX_NVIM__' --icon (Join-Path $PSScriptRoot 'neovide.ico') @NeovideArguments
exit $LASTEXITCODE
'@
$powershellLauncher = $powershellLauncher.Replace('__DISTRO__', $Distro.Replace("'", "''")).Replace('__LINUX_NVIM__', $linuxNvim)
[IO.File]::WriteAllText((Join-Path $releaseRoot 'Neovide Glow.ps1'), $powershellLauncher, (New-Object Text.UTF8Encoding($true)))
$launcher = @'
@echo off
setlocal DisableDelayedExpansion
cd /d "%USERPROFILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Neovide Glow.ps1" %*
if errorlevel 1 pause
'@
Set-Content -LiteralPath (Join-Path $releaseRoot 'Neovide Glow.cmd') -Value $launcher -Encoding ASCII
$receipt = [ordered]@{
    stack_id = $stackId
    source_repo = $repo
    source_commit = $commit
    rust_toolchain = $toolchain
    source_overlay = 'assets/neovide.ico'
    icon_sha256 = $approvedIconHash
    wsl_distro = $Distro
    neovim_launcher = $linuxNvim
    windows_status = 'Built locally; GUI/GPU/clipboard/font interaction requires verification on this Windows machine.'
}
$receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $releaseRoot 'build-receipt.json') -Encoding UTF8
Write-Host 'The executable uses the approved static light icon on Windows. Apple .icon/Assets.car layered materials are available only on macOS.'
# A deliberate icon overlay can make Neovide's version string end in -dirty;
# source_commit + icon_sha256 in build-receipt.json identify the exact build inputs.
Invoke-Checked (Join-Path $releaseRoot 'neovide.exe') @('--version')
Write-Host "Ready: $(Join-Path $releaseRoot 'Neovide Glow.cmd')"
Write-Host 'Launch this file to use the pinned native Windows GUI with Neovim inside WSL2. Existing applications and the existing Neovide user configuration were not replaced.'
Write-Host 'Fonts were installed for the current Windows user; if an already-open app still shows its previous font list, close and reopen that app.'
Write-Host 'Glow rendering uses the same pinned source; final appearance, clipboard and GPU behavior still need testing on the Windows machine.'
