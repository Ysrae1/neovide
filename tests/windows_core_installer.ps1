#requires -Version 5.1
<# Native core EXE acceptance. Installs only this new core identity, skips external
   dependency installation, and retains its test profile after both uninstalls.
   Run in an interactive Windows user task after the build has been committed. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuildReceipt,
    [Parameter(Mandatory=$true)][string]$WorkRoot,
    [switch]$CheckOnboarding
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
$architecture='x64'
if ($build.PSObject.Properties['architecture']) { $architecture=[string]$build.architecture }
if ($architecture -cnotin @('x64','arm64')) { throw 'Unsupported core build architecture.' }
$bundleArchitecture='x64' # Existing accepted x64 receipts omitted this field.
if ($bundle.PSObject.Properties['architecture']) {
    switch -CaseSensitive ([string]$bundle.architecture) {
        'x64' { $bundleArchitecture='x64' }
        'x86_64' { $bundleArchitecture='x64' }
        'arm64' { $bundleArchitecture='arm64' }
        'aarch64' { $bundleArchitecture='arm64' }
        default { throw 'Unsupported core bundle architecture.' }
    }
}
if ($architecture -cne $bundleArchitecture) { throw 'Build receipt and core bundle architectures differ.' }
$directoryName='Neovide Glow Core';$shortcutName='Neovide Glow Preview';$productId='2BE1E0A6-180C-4700-8453-FB29359286D9'
if ($architecture -ceq 'arm64') {
    $directoryName='Neovide Glow Core ARM64';$shortcutName='Neovide Glow Preview ARM64';$productId='9AC25A16-EF9A-41BE-96EF-6AB247FDBE23'
}
$default=Join-Path $env:LOCALAPPDATA ('Programs\'+$directoryName)
$profile=Join-Path $env:LOCALAPPDATA ('NeovideGlow\profiles\'+$build.stack_id)
foreach ($path in @($default,$profile)) { if (Test-Path -LiteralPath $path) { throw ('Pre-existing application/profile preserved: '+$path) } }
$shortcut=Join-Path ([Environment]::GetFolderPath('Programs')) ($shortcutName+'.lnk')
if (Test-Path -LiteralPath $shortcut) { throw ('Pre-existing Start menu shortcut preserved: '+$shortcut) }
$setupShortcut=Join-Path ([Environment]::GetFolderPath('Programs')) ($shortcutName+' Setup.lnk')
if (Test-Path -LiteralPath $setupShortcut) { throw ('Pre-existing Setup shortcut preserved: '+$setupShortcut) }
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
    $key=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$view)
    try { $entry=$key.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\{'+$productId+'}_is1'); if ($entry) { $entry.Dispose(); throw 'A registered core installation already exists; it was preserved.' } }
    finally { $key.Dispose() }
}
$null=New-Item -ItemType Directory -Path $WorkRoot
$custom=Join-Path $WorkRoot "中文 O'Connor\Glow"
$selection=Join-Path $env:LOCALAPPDATA 'NeovideGlow\dependencies\selected.json'
$selectionBefore=if (Test-Path -LiteralPath $selection) { (Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash } else { $null }
$receipt=[ordered]@{schema_version=1;state='running';architecture=$architecture;process_architecture=$env:PROCESSOR_ARCHITECTURE;setup_sha256=$build.artifact.sha256;stack_id=$build.stack_id;frontend=$build.frontend;checks=@();profile=$profile;native_gui_acceptance='not_performed_by_installer_test';dependencies_installation='skipped';error=$null}
function Save-Receipt { [IO.File]::WriteAllText((Join-Path $WorkRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false))) }
function Run-Owned([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$Timeout=900,[hashtable]$Environment=@{},[string]$CompletionReceipt='') {
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
        if (-not $process.WaitForExit($Timeout*1000)) {
            $stop=[Diagnostics.Process]::new();$stop.StartInfo.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe'
            $stop.StartInfo.Arguments='/PID '+$process.Id+' /T /F';$stop.StartInfo.UseShellExecute=$false;$stop.StartInfo.CreateNoWindow=$true
            $stop.StartInfo.RedirectStandardOutput=$true;$stop.StartInfo.RedirectStandardError=$true
            try{$null=$stop.Start();$a=$stop.StandardOutput.ReadToEndAsync();$b=$stop.StandardError.ReadToEndAsync();if(-not $stop.WaitForExit(5000)){$stop.Kill();$null=$stop.WaitForExit(1000)}}finally{$stop.Dispose()}
            $null=$process.WaitForExit(5000);throw ('Timed out: '+$Name)
        }
        $drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),2000)
        if(-not $drained){
            if(-not $CompletionReceipt -or $process.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $CompletionReceipt)){throw ('Child output handles did not close: '+$Name)}
            $completed=Get-Content -LiteralPath $CompletionReceipt -Raw -Encoding UTF8|ConvertFrom-Json
            if($completed.state -cne 'passed'){throw ('Child completion receipt did not pass: '+$Name)}
            $receipt['output_drain_note']='The installed GUI checks passed in their explicit result receipt; inherited diagnostic handles did not close within 2 seconds.'
        }
        $output=''
        foreach($channel in @($stdout,$stderr)){
            if($channel.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$output+=$channel.GetAwaiter().GetResult()}
            else{$output+='[Diagnostic handle did not close; see the explicit GUI result receipt.]'}
        }
        [IO.File]::WriteAllText((Join-Path $WorkRoot ($Name+'.log')),$output,(New-Object Text.UTF8Encoding($false)))
        return $process.ExitCode
    } finally { $process.Dispose() }
}
function Pass([string]$Name) { $receipt.checks+=@{name=$Name;state='passed'};Save-Receipt;Write-Host ('PASS '+$Name) }
function Check-CoreIcons([string]$Directory,[string]$Name) {
    $icon=Join-Path $Directory 'neovide.ico'
    $sourceIcon=Join-Path $stage 'neovide.ico'
    if (-not (Test-Path -LiteralPath $icon -PathType Leaf) -or
        (Get-FileHash -LiteralPath $icon -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $sourceIcon -Algorithm SHA256).Hash) { throw 'The installed icon differs from the sealed stage.' }
    $expected=[GlowCoreIconEvidence]::IcoSignature($icon)
    $shell=New-Object -ComObject WScript.Shell
    try {
        foreach ($link in @($shortcut,$setupShortcut)) {
            $entry=$shell.CreateShortcut($link)
            try {
                $location=[string]$entry.IconLocation
                if ($location -notmatch '^(.*),\s*(-?\d+)$') { throw ('Shortcut icon location is invalid: '+$link) }
                $target=$Matches[1].Trim('"');$index=[int]$Matches[2]
                if ([IO.Path]::GetFullPath($target) -ine [IO.Path]::GetFullPath($icon) -or $index -ne 0) { throw ('Shortcut does not use the installed Neovide Glow icon: '+$link) }
                $receipt.icon_shortcuts+=@{path=$link;icon_location=$location;icon_sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
            } finally { $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($entry) }
        }
    } finally { $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    foreach ($exe in @((Join-Path $Directory 'Glow.exe'),$setup)) {
        $groups=@([GlowCoreIconEvidence]::ExecutableSignatures($exe))
        if ($expected -cnotin $groups) { throw ('Executable icon resources differ from the packaged icon: '+$exe) }
        $receipt.icon_executables+=@{path=$exe;matching_icon_group=$true;icon_images=$expected.Split(',').Count}
    }
    Pass ($Name+'-icon-resources-and-shortcuts')
}
function Install-Core([string]$Directory,[string]$Name,[string]$Language='english') {
    $arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/TASKS=',('/LANG='+$Language),('/DIR='+$Directory),('/LOG='+(Join-Path $WorkRoot ($Name+'-installer.log'))))
    if ((Run-Owned $setup $arguments $Name) -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Directory 'Glow.exe'))) { throw ('Core install failed: '+$Name) }
    if ((Run-Owned (Join-Path $Directory 'Glow.exe') @('--launcher-check') ($Name+'-launcher') 60) -ne 0) { throw ('Core launcher check failed: '+$Name) }
    if (-not (Test-Path -LiteralPath $setupShortcut)) { throw 'The installed Setup recovery shortcut is missing.' }
    $expectedLanguage=if($Language -eq 'chinesesimplified'){'zh-CN'}else{'en'}
    if ([IO.File]::ReadAllText((Join-Path $Directory 'glow-ui-language.txt'),[Text.Encoding]::UTF8).Trim() -cne $expectedLanguage) { throw 'The installer did not preserve its selected UI language.' }
    Check-CoreIcons $Directory $Name
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
    if (Test-Path -LiteralPath $setupShortcut) { throw 'Uninstall left the task-created Setup shortcut behind.' }
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
    if (Test-Path -LiteralPath (Join-Path $Directory 'glow-ui-language.txt')) { throw 'Uninstall left its application-local UI language file behind.' }
    Check-Preserved;Pass $Name
}
try {
    Save-Receipt
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
public static class GlowCoreIconEvidence {
    delegate bool ResourceName(IntPtr module, IntPtr type, IntPtr name, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string file, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool EnumResourceNames(IntPtr module, IntPtr type, ResourceName callback, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr module, IntPtr resource);
    static string Hash(byte[] data) { using (var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant(); }
    static string Signature(List<string> hashes) { hashes.Sort(StringComparer.Ordinal); return String.Join(",",hashes.ToArray()); }
    static byte[] Read(IntPtr module, IntPtr name, int type) {
        IntPtr resource=FindResource(module,name,(IntPtr)type);
        if(resource==IntPtr.Zero) throw new InvalidDataException("Missing icon resource");
        uint length=SizeofResource(module,resource);
        if(length==0 || length>16777216) throw new InvalidDataException("Invalid icon resource size");
        var bytes=new byte[(int)length];
        Marshal.Copy(LockResource(LoadResource(module,resource)),bytes,0,bytes.Length); return bytes;
    }
    public static string IcoSignature(string path) {
        byte[] bytes=File.ReadAllBytes(path);
        if(bytes.Length<6 || BitConverter.ToUInt16(bytes,0)!=0 || BitConverter.ToUInt16(bytes,2)!=1) throw new InvalidDataException("Invalid ICO header");
        int count=BitConverter.ToUInt16(bytes,4);
        if(count==0 || 6+16*count>bytes.Length) throw new InvalidDataException("Invalid ICO directory");
        var hashes=new List<string>();
        for(int i=0;i<count;i++) {
            uint size=BitConverter.ToUInt32(bytes,6+i*16+8), offset=BitConverter.ToUInt32(bytes,6+i*16+12);
            if(size==0 || (ulong)offset+size>(ulong)bytes.Length) throw new InvalidDataException("Invalid ICO image bounds");
            byte[] image=new byte[(int)size]; Array.Copy(bytes,(long)offset,image,0,(long)size); hashes.Add(Hash(image));
        }
        return Signature(hashes);
    }
    public static string[] ExecutableSignatures(string path) {
        IntPtr module=LoadLibraryEx(path,IntPtr.Zero,0x22);
        if(module==IntPtr.Zero) throw new InvalidDataException("Cannot read executable icon resources");
        var signatures=new List<string>();
        try {
            ResourceName callback=delegate(IntPtr handle,IntPtr type,IntPtr name,IntPtr unused) {
                byte[] group=Read(handle,name,14);
                if(group.Length<6) throw new InvalidDataException("Invalid icon group");
                int count=BitConverter.ToUInt16(group,4);
                if(count==0 || 6+14*count>group.Length) throw new InvalidDataException("Invalid icon group directory");
                var hashes=new List<string>();
                for(int i=0;i<count;i++) hashes.Add(Hash(Read(handle,(IntPtr)BitConverter.ToUInt16(group,6+i*14+12),3)));
                signatures.Add(Signature(hashes)); return true;
            };
            if(!EnumResourceNames(module,(IntPtr)14,callback,IntPtr.Zero)) throw new InvalidDataException("Executable has no icon group");
            GC.KeepAlive(callback); return signatures.ToArray();
        } finally { FreeLibrary(module); }
    }
}
'@
    $receipt.icon_shortcuts=@();$receipt.icon_executables=@()
    # Guard a synthetic offline folder before extraction; sentinel must survive.
    $offline=Join-Path $WorkRoot 'existing-offline';$null=New-Item -ItemType Directory -Path (Join-Path $offline 'runtime\python') -Force
    [IO.File]::WriteAllText((Join-Path $offline 'runtime\python\python.exe'),'offline sentinel')
    if ((Run-Owned $setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR='+$offline),('/LOG='+(Join-Path $WorkRoot 'offline-guard-installer.log'))) 'offline-guard') -eq 0 -or
        (Test-Path -LiteralPath (Join-Path $offline 'Glow.exe')) -or [IO.File]::ReadAllText((Join-Path $offline 'runtime\python\python.exe')) -cne 'offline sentinel') { throw 'Offline folder was accepted or changed.' }
    Pass 'offline-directory-preserved-and-rejected'
    if ($build.PSObject.Properties['architecture']) {
        # A custom /DIR must not let the other architecture take over a core
        # installation, even though the two defaults have separate identities.
        $other=Join-Path $WorkRoot 'other-architecture-core'
        $null=New-Item -ItemType Directory -Path $other
        $opposite=if ($architecture -ceq 'arm64') { 'x64' } else { 'arm64' }
        $otherLauncher=Join-Path $other 'Glow.exe';$otherBundle=Join-Path $other 'bundle.json'
        [IO.File]::WriteAllText($otherLauncher,'other architecture sentinel')
        [IO.File]::WriteAllText($otherBundle,(@{distribution='core';architecture=$opposite}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        $otherSeal=(Get-FileHash -LiteralPath $otherBundle -Algorithm SHA256).Hash
        if ((Run-Owned $setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR='+$other),('/LOG='+(Join-Path $WorkRoot 'architecture-guard-installer.log'))) 'architecture-guard') -eq 0 -or
            [IO.File]::ReadAllText($otherLauncher) -cne 'other architecture sentinel' -or
            (Get-FileHash -LiteralPath $otherBundle -Algorithm SHA256).Hash -cne $otherSeal -or
            (Test-Path -LiteralPath (Join-Path $other 'unins000.exe'))) { throw 'The other architecture core folder was accepted or changed.' }
        Pass 'other-architecture-core-preserved-and-rejected'
    }
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
    Install-Core $custom 'unicode-space-apostrophe-install-and-launcher' 'chinesesimplified'
    $afterInstall=Read-ProfileSeal
    if ($afterInstall.Count -ne $script:profileSeal.Count) { throw 'Reinstallation changed the existing profile file set.' }
    foreach ($relative in $script:profileSeal.Keys) {
        if (-not $afterInstall.ContainsKey($relative) -or $afterInstall[$relative] -cne $script:profileSeal[$relative]) { throw ('Reinstallation changed an existing profile file: '+$relative) }
    }
    Pass 'reinstall-preserves-existing-profile'
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
    if ($CheckOnboarding) {
        if ((Run-Owned (Join-Path $PSHOME 'powershell.exe') @('-STA','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'windows_setup_entry.ps1'),'-ApplicationRoot',$custom,'-WorkRoot',(Join-Path $WorkRoot 'onboarding'),'-ExpectedLanguage','zh-CN') 'installed-graphical-setup' 240 @{} (Join-Path $WorkRoot 'onboarding\receipt.json')) -ne 0) { throw 'Installed graphical setup did not pass detection/defer acceptance.' }
        Pass 'installed-graphical-plan-and-deferred-recovery'
    }
    Uninstall-Core $custom 'unicode-uninstall-preserves-profile'
    $receipt.state='passed'
} catch { $receipt.state='failed';$receipt.error=$_.Exception.Message;throw }
finally { $receipt.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Receipt }
