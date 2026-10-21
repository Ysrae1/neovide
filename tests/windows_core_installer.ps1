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
$shortcut=Join-Path ([Environment]::GetFolderPath('Programs')) 'Neovide Glow Preview.lnk'
if (Test-Path -LiteralPath $shortcut) { throw ('Pre-existing Start menu shortcut preserved: '+$shortcut) }
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
function Run-Owned([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$Timeout=900,[hashtable]$Environment=@{}) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable;$start.Arguments=(@($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($key in $Environment.Keys) {
        if($null -eq $Environment[$key]){$start.EnvironmentVariables.Remove($key)}
        else{$start.EnvironmentVariables[$key]=[string]$Environment[$key]}
    }
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw ('Unable to start '+$Name) }
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout*1000)) { & (Join-Path $env:WINDIR 'System32\taskkill.exe') /PID $process.Id /T /F | Out-Null;throw ('Timed out: '+$Name) }
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),2000)){throw ('Child output handles did not close: '+$Name)}
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
function Check-CoreConfig([string]$Directory) {
    $scriptFile=Join-Path $WorkRoot 'installed-config-health.lua'
    $lua=@'
vim.defer_fn(function()
  local ok, err = xpcall(function()
    assert(vim.fn.has('win32') == 1, 'Expected native Windows Neovim')
    assert(vim.fn.stdpath('config'):gsub('\\', '/'):lower() == vim.env.GLOW_CORE_EXPECT_CONFIG:gsub('\\', '/'):lower(), 'Config escaped the task-owned profile')
    assert(vim.g.neovide_glow_windows_runtime == vim.fs.normalize(vim.env.NEOVIDE_GLOW_ROOT):gsub('/$', ''), 'Installed core runtime hook did not load')
    assert(vim.fn.exists(':GlowDependencies') == 2, 'Explicit dependency setup command is missing')
    assert(not require('config.media.runtime').ready(), 'Missing optional Python was silently replaced')
    assert(vim.fn.filereadable(vim.fn.stdpath('config') .. '/lua/config/navigation/buffer_close.lua') == 1, 'Verified close guard is missing')
    assert(vim.v.errmsg == '', 'Installed config startup error: ' .. vim.v.errmsg)
    print('PASS installed full core config without optional Python; no kernel started')
  end, debug.traceback)
  if ok then vim.cmd('qa!') else io.stderr:write(err .. '\n');vim.cmd('cquit 1') end
end, 500)
'@
    [IO.File]::WriteAllText($scriptFile,$lua,(New-Object Text.UTF8Encoding($false)))
    $environment=@{NEOVIDE_GLOW_ROOT=$Directory;NEOVIDE_GLOW_INIT=(Join-Path $Directory 'runtime\lua\WindowsInit.lua');NEOVIDE_GLOW_DISTRIBUTION='core';NEOVIDE_GLOW_DEPENDENCY_SETUP=(Join-Path $Directory 'dependencies\Setup-Dependencies.ps1');
        GLOW_CORE_HEALTH_SCRIPT=$scriptFile;GLOW_CORE_EXPECT_CONFIG=(Join-Path $profile 'config\nvim');NVIM_APPNAME='nvim';
        XDG_CONFIG_HOME=(Join-Path $profile 'config');XDG_DATA_HOME=(Join-Path $profile 'data');XDG_STATE_HOME=(Join-Path $profile 'state');XDG_CACHE_HOME=(Join-Path $profile 'cache');
        JUPYTER_DATA_DIR=(Join-Path $profile 'data\jupyter');JUPYTER_CONFIG_DIR=(Join-Path $profile 'config\jupyter');JUPYTER_RUNTIME_DIR=(Join-Path $profile 'state\jupyter');
        GLOW_PYTHON=$null;NEOVIDE_GLOW_PYTHON=$null;GLOW_JUPYTEXT=$null;GLOW_LATEX2TEXT=$null;PYTHONHOME=$null;PYTHONPATH=$null;VIM=$null;VIMRUNTIME=$null;NVIM_RPLUGIN_MANIFEST=$null}
    if((Run-Owned (Join-Path $Directory 'bin\nvim.exe') @('--headless','-i','NONE','-n','-c','lua dofile(vim.env.GLOW_CORE_HEALTH_SCRIPT)') 'installed-full-config' 90 $environment) -ne 0){throw 'Installed full core config failed; see installed-full-config.log'}
    Pass 'installed-full-config-without-optional-python'
}
function Check-Preserved {
    if (-not (Test-Path -LiteralPath $script:sentinel) -or [IO.File]::ReadAllText($script:sentinel) -cne 'preserve core profile') { throw 'Core profile was changed or removed by uninstall.' }
    $after=if (Test-Path -LiteralPath $selection) { (Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash } else { $null }
    if ($after -cne $selectionBefore) { throw 'Silent installer changed the existing dependency selection.' }
    $actual=Read-ProfileSeal
    if ($actual.Count -ne $script:profileSeal.Count) { throw 'Uninstall changed the profile file set.' }
    foreach ($relative in $script:profileSeal.Keys) {
        if (-not $actual.ContainsKey($relative) -or $actual[$relative] -cne $script:profileSeal[$relative]) { throw ('Uninstall changed a profile file: '+$relative) }
    }
    if (Test-Path -LiteralPath $shortcut) { throw 'Uninstall left the task-created Start menu shortcut behind.' }
}
function Read-ProfileSeal {
    # The launcher's versioned profile can have paths longer than the installer.
    $prefix='\\?\'+$profile.TrimEnd('\')+'\'
    $seal=@{}
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        foreach ($file in [IO.Directory]::GetFiles($prefix,'*',[IO.SearchOption]::AllDirectories)) {
            $stream=[IO.File]::OpenRead($file)
            try { $seal[$file.Substring($prefix.Length)]=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
            finally { $stream.Dispose() }
        }
    } finally { $sha.Dispose() }
    return $seal
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
    Check-CoreConfig $default
    $script:sentinel=Join-Path $profile 'core-installer-preserve.txt'
    [IO.File]::WriteAllText($script:sentinel,'preserve core profile')
    $script:profileSeal=Read-ProfileSeal
    [IO.File]::WriteAllText((Join-Path $WorkRoot 'profile-before-uninstall-sha256.json'),($script:profileSeal|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    $receipt['profile_preservation_files']=$script:profileSeal.Count
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
