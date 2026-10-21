#requires -Version 5.1
<# Native core EXE acceptance. Installs only this new core identity, skips external
   dependency installation, and retains its test profile after both uninstalls.
   Run in an interactive Windows user task after the build has been committed. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuildReceipt,
    [Parameter(Mandatory=$true)][string]$WorkRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw 'A native 64-bit Windows user process is required.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Use a fresh test WorkRoot; previous evidence was preserved.' }
$build=Get-Content -LiteralPath $BuildReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
if ($build.schema_version -ne 1 -or $build.state -cne 'compiled_pending_acceptance' -or $build.frontend.source_state -cne 'clean') { throw 'A clean committed frontend and completed core build receipt are required.' }
$setup=$build.artifact.path;$stage=$build.stage
if ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $build.artifact.sha256 -or
    (Get-Item -LiteralPath $setup).Length -ne $build.artifact.bytes) { throw 'Installer differs from the build receipt.' }
if ((Get-FileHash -LiteralPath (Join-Path $stage 'bundle-sha256.json') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $build.stage_seal_sha256) { throw 'Core stage differs from the build receipt.' }
$bundle=Get-Content -LiteralPath (Join-Path $stage 'bundle.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($bundle.distribution -cne 'core' -or $bundle.stack_id -cne $build.stack_id) { throw 'Core stage identity mismatch.' }
$default=Join-Path $env:LOCALAPPDATA 'Programs\Neovide Glow Core'
$profile=Join-Path $env:LOCALAPPDATA ('NeovideGlow\profiles\'+$build.stack_id)
foreach ($path in @($default,$profile)) { if (Test-Path -LiteralPath $path) { throw ('Pre-existing application/profile preserved: '+$path) } }
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
    $key=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$view)
    try { $entry=$key.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\{2BE1E0A6-180C-4700-8453-FB29359286D9}_is1'); if ($entry) { $entry.Dispose(); throw 'A registered core installation already exists; it was preserved.' } }
    finally { $key.Dispose() }
}
$null=New-Item -ItemType Directory -Path $WorkRoot
$custom=Join-Path $WorkRoot "中文 O'Connor\Glow"
$selection=Join-Path $env:LOCALAPPDATA 'NeovideGlow\dependencies\selected.json'
$selectionBefore=if (Test-Path -LiteralPath $selection) { (Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash } else { $null }
$receipt=[ordered]@{schema_version=1;state='running';setup_sha256=$build.artifact.sha256;stack_id=$build.stack_id;frontend=$build.frontend;checks=@();profile=$profile;native_gui_acceptance='not_performed_by_installer_test';dependencies_installation='skipped';error=$null}
function Save-Receipt { [IO.File]::WriteAllText((Join-Path $WorkRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false))) }
function Run-Owned([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$Timeout=900) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable;$start.Arguments=(@($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw ('Unable to start '+$Name) }
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout*1000)) { & (Join-Path $env:WINDIR 'System32\taskkill.exe') /PID $process.Id /T /F | Out-Null;throw ('Timed out: '+$Name) }
        [IO.File]::WriteAllText((Join-Path $WorkRoot ($Name+'.log')),($stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()),(New-Object Text.UTF8Encoding($false)))
        return $process.ExitCode
    } finally { $process.Dispose() }
}
function Pass([string]$Name) { $receipt.checks+=@{name=$Name;state='passed'};Save-Receipt;Write-Host ('PASS '+$Name) }
function Install-Core([string]$Directory,[string]$Name) {
    $arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/TASKS=',('/DIR='+$Directory),('/LOG='+(Join-Path $WorkRoot ($Name+'-installer.log'))))
    if ((Run-Owned $setup $arguments $Name) -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Directory 'Glow.exe'))) { throw ('Core install failed: '+$Name) }
    if ((Run-Owned (Join-Path $Directory 'Glow.exe') @('--launcher-check') ($Name+'-launcher') 60) -ne 0) { throw ('Core launcher check failed: '+$Name) }
    Pass $Name
}
function Check-Preserved {
    if (-not (Test-Path -LiteralPath $script:sentinel) -or [IO.File]::ReadAllText($script:sentinel) -cne 'preserve core profile') { throw 'Core profile was changed or removed by uninstall.' }
    $after=if (Test-Path -LiteralPath $selection) { (Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash } else { $null }
    if ($after -cne $selectionBefore) { throw 'Silent installer changed the existing dependency selection.' }
}
function Uninstall-Core([string]$Directory,[string]$Name) {
    $uninstaller=Join-Path $Directory 'unins000.exe'
    if ((Run-Owned $uninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG='+(Join-Path $WorkRoot ($Name+'-uninstaller.log')))) $Name) -ne 0) { throw ('Core uninstall failed: '+$Name) }
    if (Test-Path -LiteralPath (Join-Path $Directory 'Glow.exe')) { throw 'Uninstall left application files behind.' }
    Check-Preserved;Pass $Name
}
try {
    Save-Receipt
    # Guard a synthetic offline folder before extraction; sentinel must survive.
    $offline=Join-Path $WorkRoot 'existing-offline';$null=New-Item -ItemType Directory -Path (Join-Path $offline 'runtime\python') -Force
    [IO.File]::WriteAllText((Join-Path $offline 'runtime\python\python.exe'),'offline sentinel')
    if ((Run-Owned $setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR='+$offline),('/LOG='+(Join-Path $WorkRoot 'offline-guard-installer.log'))) 'offline-guard') -eq 0 -or
        (Test-Path -LiteralPath (Join-Path $offline 'Glow.exe')) -or [IO.File]::ReadAllText((Join-Path $offline 'runtime\python\python.exe')) -cne 'offline sentinel') { throw 'Offline folder was accepted or changed.' }
    Pass 'offline-directory-preserved-and-rejected'
    Install-Core $default 'default-install-and-launcher'
    if ((Run-Owned (Join-Path $default 'Glow.exe') @('--initialize-profile') 'initialize-profile' 180) -ne 0) { throw 'Core profile initialization failed.' }
    $script:sentinel=Join-Path $profile 'core-installer-preserve.txt'
    [IO.File]::WriteAllText($script:sentinel,'preserve core profile')
    Pass 'initialize-new-versioned-profile'
    Uninstall-Core $default 'default-uninstall-preserves-profile'
    Install-Core $custom 'unicode-space-apostrophe-install-and-launcher'
    $seal=Get-Content -LiteralPath (Join-Path $custom 'bundle-sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $seal.PSObject.Properties) {
        $file=Join-Path $custom $entry.Name.Replace('/','\')
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.Value) { throw ('Installed payload checksum mismatch: '+$entry.Name) }
    }
    foreach ($omitted in @('runtime\python','runtime\node','runtime\java','tools','profile\data\nvim\mason','profile\data\nvim\codex-acp')) {
        if (Test-Path -LiteralPath (Join-Path $custom $omitted)) { throw ('Core retained an omitted runtime: '+$omitted) }
    }
    Pass 'installed-seal-and-runtime-omissions'
    if ((Run-Owned (Join-Path $custom 'bin\nvim.exe') @('--version') 'native-nvim-version' 60) -ne 0) { throw 'Installed native Neovim did not run.' }
    Pass 'installed-native-neovim'
    Uninstall-Core $custom 'unicode-uninstall-preserves-profile'
    $receipt.state='passed'
} catch { $receipt.state='failed';$receipt.error=$_.Exception.Message;throw }
finally { $receipt.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Receipt }
