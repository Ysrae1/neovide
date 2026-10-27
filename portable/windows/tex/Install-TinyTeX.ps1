#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AssetDirectory = $PSScriptRoot,
    [string]$InstallRoot = (Join-Path $env:APPDATA 'TinyTeX'),
    [string]$RunRoot = (Join-Path $env:LOCALAPPDATA ('NeovideGlow\tex-setup\tinytex-v1-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffff'))),
    [switch]$Resume,
    [switch]$NoUserPath,
    [switch]$AllowSeparateExistingTools,
    [switch]$ResolveInstallRootOnly,
    [ValidateSet('auto','tuna','ustc','illinois')][string]$TeXMirror = 'auto',
    [scriptblock]$ProgressCallback
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Test-TeXInstallRoot([string]$Path) {
    return ($Path -match '^[A-Za-z]:\\[!-~]+$' -and $Path -notmatch '[";%!^&|<>\r\n]')
}
function Get-TeXShortPath([string]$Path) {
    # Read an existing Windows alias; never enable 8.3 naming, create a junction,
    # or move the user's installation into a shared/admin directory.
    if (-not ('GlowTeXNativePath' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
public static class GlowTeXNativePath {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
 public static extern uint GetShortPathNameW(string path, StringBuilder result, uint capacity);
}
'@
    }
    $buffer=New-Object Text.StringBuilder 32768
    $length=[GlowTeXNativePath]::GetShortPathNameW($Path,$buffer,[uint32]$buffer.Capacity)
    if ($length -gt 0 -and $length -lt $buffer.Capacity) { return $buffer.ToString() }
    return $null
}
function Resolve-TeXInstallRoot([string]$Path) {
    if (Test-TeXInstallRoot $Path) { return $Path }
    if ($Path -notmatch '^[A-Za-z]:\\.+' -or $Path -match '[";%!^&|<>\r\n]') {
        throw ('Unsupported TeX installation root: "'+$Path+'". Use -InstallRoot with a writable local ASCII path without spaces or batch metacharacters. No files were written.')
    }
    # The new TinyTeX directory need not exist yet. Resolve only its nearest
    # existing ancestor, then append the unchanged, not-yet-created suffix.
    $ancestor=$Path; $suffix=''
    while (-not (Test-Path -LiteralPath $ancestor -PathType Container)) {
        $separator=$ancestor.LastIndexOf('\')
        if ($separator -lt 3) { break }
        $suffix=$ancestor.Substring($separator)+$suffix
        $ancestor=$ancestor.Substring(0,$separator)
    }
    $short=$null
    try { $short=Get-TeXShortPath $ancestor } catch { $short=$null }
    if ($short) {
        $candidate=$short.TrimEnd('\')+$suffix
        if (Test-TeXInstallRoot $candidate) { return $candidate }
    }
    throw ('TeX installation root contains spaces or non-ASCII characters and Windows has no usable ASCII 8.3 alias: "'+$Path+'". Choose a writable ASCII user-level path without spaces via -InstallRoot. Nothing was installed; no ProgramData/admin fallback was attempted.')
}
$InstallRoot = Resolve-TeXInstallRoot ([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\'))
if ($ResolveInstallRootOnly) { return $InstallRoot }
$RunRoot = [IO.Path]::GetFullPath($RunRoot)
function Assert-TeXUserContext([string]$IdentitySid,[string]$SelectedRoot,[string]$ProfilePath) {
    if ($IdentitySid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        $SelectedRoot -match '(?i)\\Windows\\(?:System32|SysWOW64)\\config\\(?:systemprofile|LocalService|NetworkService)(?:\\|$)' -or
        $ProfilePath -match '(?i)\\Windows\\(?:System32|SysWOW64)\\config\\(?:systemprofile|LocalService|NetworkService)(?:\\|$)') {
        throw 'Run TeX setup as the logged-in user, not SYSTEM or a service identity. No files were written.'
    }
}
function Assert-TeXInfrastructurePlan([string]$Plan) {
    $section=[regex]::Match($Plan,'(?ms)^end-of-header\r?\n(?<updates>.*?)^end-of-updates\r?$')
    if (-not $section.Success -or $section.Groups['updates'].Value.Trim() -ne '' -or
        $Plan -notmatch '(?m)^total-bytes\t0\r?$') {
        throw 'TeX Live infrastructure update is still pending; package installation was not started. See the official self-update log and machine-readable plan.'
    }
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$identitySid=$identity.User.Value
Assert-TeXUserContext $identitySid $InstallRoot $env:USERPROFILE
if (Test-Path -LiteralPath $RunRoot) { throw 'RunRoot must be fresh. Existing logs were preserved.' }
$null = New-Item -ItemType Directory -Path $RunRoot
$logs = Join-Path $RunRoot 'logs'
$null = New-Item -ItemType Directory -Path $logs
$progress = Join-Path $RunRoot 'progress.log'
$receiptPath = Join-Path $RunRoot 'receipt.json'
$utf8 = New-Object Text.UTF8Encoding($false)
$receipt = [ordered]@{schema=1;operation='glow-system-tinytex-v1';status='started';install_root=$InstallRoot;started_utc=[DateTime]::UtcNow.ToString('o');checks=@();user_path_changed=$false;execution_context=@{identity_sid=$identitySid;session_id=[Diagnostics.Process]::GetCurrentProcess().SessionId;is_64_bit_process=[Environment]::Is64BitProcess;service_identity=$false}}
$savedEnvironment = @{}
foreach ($variable in @('PATH','TL_GNUPG','TL_GNUPGHOME')) { $savedEnvironment[$variable] = [Environment]::GetEnvironmentVariable($variable,'Process') }
function Progress([string]$Message,[string]$Phase) {
    $line = [DateTime]::UtcNow.ToString('HH:mm:ss') + ' ' + $Message
    Write-Host $line
    [IO.File]::AppendAllText($progress,$line + [Environment]::NewLine,$utf8)
    if ($Phase -and $ProgressCallback) { & $ProgressCallback $Phase $Message }
}
function Save-Receipt {
    [IO.File]::WriteAllText($receiptPath,($receipt | ConvertTo-Json -Depth 7),$utf8)
}
function Get-TeXMirrorCandidates {
    param([ValidateSet('auto','tuna','ustc','illinois')][string]$Mirror,
        [string]$UICulture = [Globalization.CultureInfo]::CurrentUICulture.Name)
    $repositories = @{
        tuna='https://mirrors.tuna.tsinghua.edu.cn/CTAN/systems/texlive/tlnet'
        ustc='https://mirrors.ustc.edu.cn/CTAN/systems/texlive/tlnet'
        illinois='https://ctan.math.illinois.edu/systems/texlive/tlnet'
    }
    $names = if ($Mirror -ne 'auto') { @($Mirror) }
        elseif ($UICulture -match '^zh(?:-|$)') { @('tuna','ustc','illinois') }
        else { @('illinois','tuna','ustc') }
    foreach ($name in $names) { [pscustomobject]@{name=$name;repository=$repositories[$name]} }
}
function Test-TeXMirrorMetadata {
    param([string]$Repository,[int]$TimeoutSeconds=15)
    # Read-only reachability check, never a substitute for tlmgr signature
    # verification. Buffer and total request time are both bounded; redirects
    # cannot silently change the selected repository or downgrade HTTPS.
    if (([uri]$Repository).Scheme -cne 'https') { throw 'TeX mirror must use HTTPS.' }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object Net.Http.HttpClient($handler)
    $response = $null
    try {
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $client.MaxResponseContentBufferSize = 4096
        $response = $client.GetAsync($Repository+'/tlpkg/texlive.tlpdb.sha512').GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200) { throw ('Metadata returned HTTP '+[int]$response.StatusCode) }
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ($content.Trim() -notmatch '\A[0-9a-fA-F]{128}(?:[ \t]+\*?texlive\.tlpdb)?\z') { throw 'Metadata did not contain a valid TeX Live SHA512 record.' }
    } finally {
        if ($response) { $response.Dispose() }
        $client.Dispose(); $handler.Dispose()
    }
}
function Select-TeXRepository {
    param([ValidateSet('auto','tuna','ustc','illinois')][string]$Mirror,
        [string]$UICulture = [Globalization.CultureInfo]::CurrentUICulture.Name)
    $receipt.tex_mirror = $Mirror
    $receipt.mirror_probes = @()
    foreach ($candidate in @(Get-TeXMirrorCandidates -Mirror $Mirror -UICulture $UICulture)) {
        Progress ('Checking TeX mirror '+$candidate.name+': '+$candidate.repository) 'select-tex-mirror'
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $probe = [ordered]@{name=$candidate.name;repository=$candidate.repository;timeout_seconds=15;passed=$false}
        try {
            Test-TeXMirrorMetadata -Repository $candidate.repository -TimeoutSeconds 15
            $probe.passed = $true
        } catch { $probe.error = $_.Exception.Message }
        $timer.Stop(); $probe.elapsed_ms = $timer.ElapsedMilliseconds
        $receipt.mirror_probes += $probe
        Save-Receipt
        if ($probe.passed) {
            $receipt.selected_mirror = $candidate.name
            $receipt.selected_repository = $candidate.repository
            $receipt.repository = $candidate.repository
            Save-Receipt
            Progress ('Selected TeX mirror '+$candidate.name+': '+$candidate.repository) 'select-tex-mirror'
            return $candidate.repository
        }
    }
    throw ('No reachable TeX mirror for selection "'+$Mirror+'". Each candidate was checked once (15 seconds maximum). See mirror_probes in receipt.json; no TeX installation or repository change was started.')
}
function Quote-Argument([string]$Value) {
    $quoted = New-Object Text.StringBuilder
    $null = $quoted.Append('"'); $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        $count = $slashes
        if ($character -eq '"') { $count = $slashes * 2 + 1 }
        $null = $quoted.Append('\',$count); $null = $quoted.Append($character); $slashes = 0
    }
    $null = $quoted.Append('\',$slashes * 2); $null = $quoted.Append('"')
    return $quoted.ToString()
}
function Invoke-Bounded {
    param([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$TimeoutSeconds=120,[string]$Directory=$RunRoot)
    Progress ('Running ' + $Name) $Name
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.WorkingDirectory = $Directory
    if ([IO.Path]::GetExtension($Executable) -ieq '.bat') {
        # Windows TeX self-update must enter the official tlmgr.bat watchdog.
        # cmd.exe has different escaping from CreateProcess/CRT argument rules.
        # Only literal trusted arguments are accepted by this batch boundary.
        foreach ($literal in @($Executable) + @($Arguments)) {
            if ($literal -match '["%!^&|<>\r\n]') { throw 'Unsafe batch argument; no command was started.' }
        }
        $command = '"' + $Executable + '"'
        foreach ($argument in $Arguments) { $command += ' "' + $argument + '"' }
        $start.FileName = Join-Path $env:WINDIR 'System32\cmd.exe'
        $start.Arguments = '/d /s /c "' + $command + '"'
    }
    else { $start.Arguments = (@($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' ') }
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process; $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw ('Cannot start ' + $Name) }
        $ownedPid = $process.Id; $timedOut = $false; $terminationNotes = @()
        # Read incrementally so a timed-out command retains output even when a
        # descendant keeps a redirected handle open. Poll on this runspace.
        $channels = @($process.StandardOutput,$process.StandardError) | ForEach-Object {
            $buffer = New-Object char[] 8192
            @{reader=$_;buffer=$buffer;text=(New-Object Text.StringBuilder);
                task=$_.ReadAsync($buffer,0,$buffer.Length);ended=$false;failed=$false}
        }
        $readOutput = {
            foreach ($channel in $channels) {
                # Bound each poll as well, so continuous output cannot hide the
                # process deadline; drain more than one buffered block per poll.
                for ($round=0; $round -lt 16 -and -not $channel.ended -and $channel.task.IsCompleted; $round++) {
                    try {
                        $count = $channel.task.GetAwaiter().GetResult()
                        if ($count -eq 0) { $channel.ended = $true; continue }
                        $null = $channel.text.Append($channel.buffer,0,$count)
                        $channel.task = $channel.reader.ReadAsync($channel.buffer,0,$channel.buffer.Length)
                    } catch {
                        $channel.ended = $true; $channel.failed = $true
                        $null = $channel.text.Append([Environment]::NewLine+'[Output read failed: '+$_.Exception.Message+']')
                    }
                }
            }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited) {
            & $readOutput
            if ([DateTime]::UtcNow -ge $deadline) { $timedOut = $true; break }
            $null = $process.WaitForExit(50)
        }
        if ($timedOut -and -not $process.HasExited) {
            # This tree was created by this call; never terminate other TeX/editor jobs.
            $killer = New-Object Diagnostics.Process
            $killer.StartInfo.FileName = Join-Path $env:WINDIR 'System32\taskkill.exe'
            $killer.StartInfo.Arguments = '/PID '+$ownedPid+' /T /F'
            $killer.StartInfo.UseShellExecute = $false; $killer.StartInfo.CreateNoWindow = $true
            $killer.StartInfo.RedirectStandardOutput = $true; $killer.StartInfo.RedirectStandardError = $true
            try {
                if ($killer.Start()) {
                    $killOut = $killer.StandardOutput.ReadToEndAsync(); $killErr = $killer.StandardError.ReadToEndAsync()
                    if (-not $killer.WaitForExit(5000)) {
                        $killer.Kill(); $null = $killer.WaitForExit(1000)
                        $terminationNotes += 'Owned-tree termination command exceeded 5 seconds.'
                    }
                    if ($killOut.IsCompleted -and -not $killOut.IsFaulted -and -not $killOut.IsCanceled) { $terminationNotes += $killOut.GetAwaiter().GetResult() }
                    if ($killErr.IsCompleted -and -not $killErr.IsFaulted -and -not $killErr.IsCanceled) { $terminationNotes += $killErr.GetAwaiter().GetResult() }
                } else { $terminationNotes += 'Owned-tree termination command could not be started.' }
            } catch { $terminationNotes += 'Owned-tree termination error: '+$_.Exception.Message }
            finally { $killer.Dispose() }
            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill(); $null = $process.WaitForExit(1000) }
                catch { $terminationNotes += 'Owned-process termination error: '+$_.Exception.Message }
            }
        }
        $drainDeadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            & $readOutput
            $outputDrainComplete = @($channels | Where-Object {-not $_.ended -or $_.failed}).Count -eq 0
            if ($outputDrainComplete -or [DateTime]::UtcNow -ge $drainDeadline) { break }
            Start-Sleep -Milliseconds 25
        } while ($true)
        $output = $channels[0].text.ToString() + $channels[1].text.ToString()
        if ($output.Length -gt 2 * 1024 * 1024) { $output = '[log truncated to final 2 MiB]' + $output.Substring($output.Length-2*1024*1024) }
        $exitCode = $null
        if ($process.HasExited) { $exitCode = $process.ExitCode }
        $log = Join-Path $logs ($Name + '.log')
        $logOutput = $output
        if ($timedOut -or -not $outputDrainComplete) {
            $logOutput += [Environment]::NewLine+'[Glow command state: pid='+$ownedPid+'; timed_out='+$timedOut+'; output_drain_complete='+$outputDrainComplete+'; exit_code='+$exitCode+']'
            if ($terminationNotes.Count) { $logOutput += [Environment]::NewLine+($terminationNotes -join [Environment]::NewLine) }
        }
        [IO.File]::WriteAllText($log,$logOutput,$utf8)
        $receipt.checks += @{name=$Name;exit_code=$exitCode;log=$log;pid=$ownedPid;
            timed_out=$timedOut;output_drain_complete=$outputDrainComplete}
        Save-Receipt
        if ($timedOut) { throw (New-Object TimeoutException ('Timed out after ' + $TimeoutSeconds + ' seconds: ' + $Name + '. Output and process state saved: ' + $log)) }
        if (-not $outputDrainComplete) { throw ('Output did not drain within 5 seconds: ' + $Name + '. Partial output saved: ' + $log) }
        if ($exitCode -ne 0) {
            if ($output) { Write-Host $output.Substring([Math]::Max(0,$output.Length-3500)) }
            throw ('Command failed (' + $exitCode + '): ' + $Name)
        }
        return $output
    }
    finally { $process.Dispose() }
}
function Find-Application([string]$Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }; return $null
}
function Append-UserPath([string]$Directory) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment',$true)
    if (-not $key) { throw 'Cannot open the current-user environment key.' }
    try {
        $exists = @($key.GetValueNames()) -contains 'Path'
        $before = $key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        if ($exists) { $kind = $key.GetValueKind('Path') }
        if ($kind -notin @([Microsoft.Win32.RegistryValueKind]::String,[Microsoft.Win32.RegistryValueKind]::ExpandString)) { throw 'Unexpected user PATH registry type; preserved.' }
        $current = if ($null -eq $before) { '' } else { [string]$before }
        foreach ($entry in $current.Split(';')) {
            if ([Environment]::ExpandEnvironmentVariables($entry).Trim().Trim('"').TrimEnd('\') -ieq $Directory.TrimEnd('\')) { return }
        }
        $after = $current
        if ($after -and -not $after.EndsWith(';')) { $after += ';' }
        $after += $Directory
        # Store raw PATH only in a private Windows snapshot, never in the shared receipt/logs.
        $snapshotRoot = Join-Path $env:LOCALAPPDATA 'NeovideGlow\settings-snapshots'
        $null = New-Item -ItemType Directory -Path $snapshotRoot -Force
        $snapshot = Join-Path $snapshotRoot ('tinytex-v1-user-path-' + [Guid]::NewGuid().ToString('N') + '.json')
        $record = @{schema=1;existed=$exists;kind=$kind.ToString();before=$before;after=$after;appended=$Directory}
        [IO.File]::WriteAllText($snapshot,($record | ConvertTo-Json),$utf8)
        $unchanged = $key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($unchanged -cne $before) { throw 'User PATH changed during setup; no append was made.' }
        $key.SetValue('Path',$after,$kind)
        $receipt.user_path_changed = $true
        $receipt.user_path_backup = $snapshot
        Progress 'Appended only the current-user TeX binary path; original value saved privately.'
    }
    finally { $key.Dispose() }
    # Notify desktop apps without changing a system environment value.
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class GlowTexEnvironment {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 internal static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,UIntPtr wparam,string value,uint flags,uint timeout,out UIntPtr result);
 public static void Notify(){ UIntPtr result; SendMessageTimeout(new IntPtr(0xffff),0x1a,UIntPtr.Zero,"Environment",2,2000,out result); }
}
'@
    [GlowTexEnvironment]::Notify()
}
try {
    Save-Receipt
    $lock = Get-Content -LiteralPath (Join-Path $AssetDirectory 'asset-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($lock.repository -cne 'rstudio/tinytex-releases' -or $lock.tag -cne 'v2026.10' -or
        $lock.filename -cne 'TinyTeX-1-windows-v2026.10.exe' -or
        $lock.sha256 -cne '36c329c644683d981a668419d13c8804696e2816ae4d287ad755788fee231a31') { throw 'Unexpected TeX asset lock; nothing was installed.' }
    Progress 'Checking official TinyTeX archive size and SHA256.' 'verify-tinytex-archive'
    $archive = Join-Path $AssetDirectory $lock.filename
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Verified official TinyTeX archive is missing.' }
    if ((Get-Item -LiteralPath $archive).Length -ne $lock.size -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $lock.sha256) { throw 'Official TinyTeX archive digest/size mismatch.' }
    $receipt.asset_url=$lock.asset_url; $receipt.asset_sha256=$lock.sha256; $receipt.release=$lock.tag
    $ownerFile = Join-Path $InstallRoot '.glow-tinytex-v1-owner.json'
    if (Test-Path -LiteralPath $InstallRoot) {
        if (-not $Resume -or -not (Test-Path -LiteralPath $ownerFile -PathType Leaf)) { throw 'An existing TinyTeX installation was preserved. Use a new location; resume requires this setup operation ownership marker.' }
        $owner = Get-Content -LiteralPath $ownerFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($owner.operation -cne 'glow-system-tinytex-v1' -or $owner.asset_sha256 -cne $lock.sha256) { throw 'The existing TeX directory does not belong to this setup operation.' }
    }
    foreach ($command in @('xelatex.exe','pdflatex.exe','latexmk.exe','tlmgr.bat')) {
        $existing = Find-Application $command
        if (-not $AllowSeparateExistingTools -and $existing -and -not $existing.StartsWith($InstallRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw ('Existing TeX tool preserved: '+$command+'. No new distribution was installed or selected.') }
    }
    # Select once, before extraction or any change to this distribution. All
    # online tlmgr operations below remain bound to this exact repository.
    $repository = Select-TeXRepository -Mirror $TeXMirror
    if (-not (Test-Path -LiteralPath $InstallRoot)) {
        $extract = Join-Path $RunRoot ('extract-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $extract
        $null = Invoke-Bounded -Executable $archive -Arguments @('-y') -Name 'extract-official-archive' -TimeoutSeconds 180 -Directory $extract
        $unpacked = Join-Path $extract 'TinyTeX'
        foreach ($relative in @('bin\windows\xelatex.exe','bin\windows\latexmk.exe','tlpkg\tlperl\bin\perl.exe','texmf-dist\scripts\texlive\tlmgr.pl','LICENSE.TL')) {
            if (-not (Test-Path -LiteralPath (Join-Path $unpacked $relative) -PathType Leaf)) { throw ('Official archive is missing '+$relative) }
        }
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $InstallRoot) -Force
        Move-Item -LiteralPath $unpacked -Destination $InstallRoot
        [IO.File]::WriteAllText($ownerFile,(@{schema=1;operation='glow-system-tinytex-v1';asset_sha256=$lock.sha256} | ConvertTo-Json),$utf8)
        Progress 'Extracted verified TinyTeX into the new current-user directory.'
    }
    $bin = Join-Path $InstallRoot 'bin\windows'
    $env:PATH = $bin + ';' + $env:PATH
    $gpg = Find-Application 'gpg.exe'
    if (-not $gpg) {
        $git = Find-Application 'git.exe'
        if ($git) {
            $candidate = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $git) '..\usr\bin\gpg.exe'))
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $gpg = $candidate }
        }
    }
    if (-not $gpg) { throw 'A working GnuPG is required to verify CTAN repository signatures. Install Git for Windows/GnuPG or supply it on this process PATH; verification was not weakened.' }
    # TLCrypto::test_one_gpg calls TLUtils::which on Windows. The shipped
    # which() accepts a basename and searches PATH; an absolute TL_GNUPG
    # value is incorrectly concatenated to each PATH directory and never found.
    $env:PATH = $bin + ';' + (Split-Path -Parent $gpg) + ';' + $savedEnvironment['PATH']
    $env:TL_GNUPG = [IO.Path]::GetFileName($gpg)
    $env:TL_GNUPGHOME = Join-Path $InstallRoot 'tlpkg\gpg'
    $perl = Join-Path $InstallRoot 'tlpkg\tlperl\bin\perl.exe'
    $tlmgr = Join-Path $InstallRoot 'texmf-dist\scripts\texlive\tlmgr.pl'
    $null = Invoke-Bounded -Executable $gpg -Arguments @('--homedir',$env:TL_GNUPGHOME,'--version') -Name 'gpg-version' -TimeoutSeconds 30
    $gpgProbe = 'use TeXLive::TLUtils; use TeXLive::TLCrypto; exit(TeXLive::TLCrypto::setup_gpg($ARGV[0]) ? 0 : 2);'
    $null = Invoke-Bounded -Executable $perl -Arguments @('-I',(Join-Path $InstallRoot 'tlpkg'),'-e',$gpgProbe,$InstallRoot) -Name 'tlcrypto-gpg-offline-preflight' -TimeoutSeconds 30
    # Only this new distribution's options are changed. No path action or file association action.
    foreach ($option in @('desktop_integration','fileassocs','multiuser')) {
        $null = Invoke-Bounded -Executable $perl -Arguments @($tlmgr,'option',$option,'0') -Name ('option-'+$option)
    }
    # Keep infrastructure and package metadata on the one selected mirror.
    $verified = @($tlmgr,'--repository',$repository,'--verify-repo=all')
    $tlmgrBatch = Join-Path $bin 'tlmgr.bat'
    if (-not (Test-Path -LiteralPath $tlmgrBatch -PathType Leaf)) { throw 'Official Windows tlmgr watchdog is missing.' }
    # The native tar must see/write the same owned temp tree as PowerShell.
    # A SYSTEM/System32 profile can resolve differently for bundled 32-bit tools;
    # such identities/paths are rejected above, before any filesystem writes.
    $updateTemp=Join-Path $InstallRoot 'temp'
    $null=New-Item -ItemType Directory -Path $updateTemp -Force
    $probeId=[Guid]::NewGuid().ToString('N')
    $probeList=Join-Path $updateTemp ('.glow-tar-probe-'+$probeId+'.txt')
    $probeTar=Join-Path $updateTemp ('.glow-tar-probe-'+$probeId+'.tar')
    try {
        [IO.File]::WriteAllText($probeList,'',$utf8)
        $null=Invoke-Bounded -Executable (Join-Path $InstallRoot 'tlpkg\installer\tar.exe') -Arguments @('-cf',$probeTar,'-T',$probeList) -Name 'native-tar-temp-preflight' -TimeoutSeconds 30
        if (-not (Test-Path -LiteralPath $probeTar -PathType Leaf)) { throw 'Native TeX tar could not create its owned temporary archive.' }
    } finally {
        foreach ($probe in @($probeList,$probeTar)) { if (Test-Path -LiteralPath $probe -PathType Leaf) { Remove-Item -LiteralPath $probe } }
    }
    $null = Invoke-Bounded -Executable $tlmgrBatch -Arguments @('--repository',$repository,'--verify-repo=all','-v','update','--self') -Name 'tlmgr-self-update' -TimeoutSeconds 420
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'temp\updater-w32')) { throw 'TeX Live prepared but did not execute its Windows infrastructure updater.' }
    $updateLog = Join-Path $InstallRoot 'temp\update-self.log'
    if (Test-Path -LiteralPath $updateLog -PathType Leaf) {
        $updateText = [IO.File]::ReadAllText($updateLog)
        if ($updateText.Length -gt 2 * 1024 * 1024) { $updateText = '[log truncated to final 2 MiB]' + $updateText.Substring($updateText.Length - 2 * 1024 * 1024) }
        [IO.File]::WriteAllText((Join-Path $logs 'official-windows-updater.log'),$updateText,$utf8)
    }
    # tlmgr.bat may return 0 even when its Perl preparer failed before an
    # updater was created. Check the documented machine-readable self-update
    # plan instead of treating the batch exit code as completed infrastructure.
    $selfPlan=Invoke-Bounded -Executable $perl -Arguments ($verified+@('--machine-readable','update','--self','--list')) -Name 'verify-self-update-complete' -TimeoutSeconds 180
    Assert-TeXInfrastructurePlan $selfPlan
    $receipt.infrastructure_update_verified=$true
    Save-Receipt
    # texlive.infra updates tlmgr, but fmtutil belongs to texlive-scripts.
    # Since upstream fmtutil r80658 (2026-10-16), tlmgr may combine its
    # --byengine/--byfmt selectors. The monthly archive's old fmtutil rejects
    # that syntax. Update only the owning scripts package from the same signed
    # repository before installing packages that trigger format generation.
    $fmtutil=Join-Path $bin 'fmtutil-sys.exe'
    $receipt.fmtutil_before=(Invoke-Bounded -Executable $fmtutil -Arguments @('--version') -Name 'fmtutil-version-before').Trim()
    $null=Invoke-Bounded -Executable $perl -Arguments ($verified+@('update','texlive-scripts')) -Name 'update-texlive-scripts' -TimeoutSeconds 300
    $receipt.fmtutil_after=(Invoke-Bounded -Executable $fmtutil -Arguments @('--version') -Name 'fmtutil-version-after').Trim()
    $null=Invoke-Bounded -Executable $fmtutil -Arguments @('--dry-run','--byengine','xetex','--byfmt','xelatex') -Name 'verify-combined-format-selectors' -TimeoutSeconds 90
    Save-Receipt
    $packages = @('latexmk','xetex','synctex','xecjk','ctex','fandol','tex-gyre','enumitem','fancyhdr','geometry','amsmath','amsfonts','amscls','hyperref','fontspec','xcolor','graphics','tools','booktabs','caption','float','listings','mathtools','unicode-math','xurl','etoolbox','kvoptions')
    $receipt.requested_packages = $packages
    $null = Invoke-Bounded -Executable $perl -Arguments ($verified+@('install')+$packages) -Name 'install-common-packages' -TimeoutSeconds 600
    # A prior post-install fmtutil failure leaves installed packages intact.
    # Rebuild only missing formats after their scripts are compatible. This
    # does not accept arbitrary tlmgr exit 2 or suppress format-build errors.
    $null=Invoke-Bounded -Executable $fmtutil -Arguments @('--missing') -Name 'complete-missing-formats' -TimeoutSeconds 300
    # Documented TinyTeX relocation action for the XeTeX font configuration only.
    $null = Invoke-Bounded -Executable $perl -Arguments @($tlmgr,'postaction','install','script','xetex') -Name 'xetex-local-font-configuration' -TimeoutSeconds 120
    . (Join-Path $PSScriptRoot 'Fontconfig.ps1')
    $fontconfig=Set-GlowTeXFontDirectories -BinRoot $bin -RunRoot $RunRoot -RefreshCache {
        param($cache)
        $null=Invoke-Bounded -Executable $cache -Arguments @('-f') -Name 'xetex-user-font-cache' -TimeoutSeconds 120
    }
    $receipt.fontconfig=$fontconfig
    $null = Invoke-Bounded -Executable (Join-Path $bin 'xelatex.exe') -Arguments @('--version') -Name 'xelatex-version'
    $null = Invoke-Bounded -Executable (Join-Path $bin 'latexmk.exe') -Arguments @('-v') -Name 'latexmk-version'
    $null = Invoke-Bounded -Executable (Join-Path $bin 'synctex.exe') -Arguments @('help') -Name 'synctex-help'
    foreach ($name in @('latin','中文 环境 O''Connor')) {
        $project = Join-Path $RunRoot $name
        $null = New-Item -ItemType Directory -Path $project
        Copy-Item -LiteralPath (Join-Path $AssetDirectory 'fixture.tex') -Destination (Join-Path $project 'fixture.tex')
        $logName = if ($name -eq 'latin') { 'compile-latin-path' } else { 'compile-unicode-path' }
        $null = Invoke-Bounded -Executable (Join-Path $bin 'latexmk.exe') -Arguments @('-xelatex','-synctex=1','-interaction=nonstopmode','-halt-on-error','-file-line-error','-latexoption=-no-shell-escape','fixture.tex') -Name $logName -TimeoutSeconds 180 -Directory $project
        $pdf = Join-Path $project 'fixture.pdf'; $synctex = Join-Path $project 'fixture.synctex.gz'
        if (-not (Test-Path -LiteralPath $pdf) -or -not (Test-Path -LiteralPath $synctex)) { throw ('PDF/SyncTeX output missing: '+$logName) }
        $stream = [IO.File]::OpenRead($pdf)
        try { $header = New-Object byte[] 5; $null = $stream.Read($header,0,5) } finally { $stream.Dispose() }
        if ([Text.Encoding]::ASCII.GetString($header) -cne '%PDF-' -or (Get-Item -LiteralPath $synctex).Length -eq 0) { throw ('Invalid PDF/SyncTeX output: '+$logName) }
        $receipt.checks += @{name=$logName+'-outputs';pdf=$pdf;pdf_sha256=(Get-FileHash -LiteralPath $pdf -Algorithm SHA256).Hash.ToLowerInvariant();synctex=$synctex;passed=$true}
    }
    $null = Invoke-Bounded -Executable $perl -Arguments @($tlmgr,'list','--only-installed') -Name 'installed-package-versions'
    $receipt.tlpdb_sha256 = (Get-FileHash -LiteralPath (Join-Path $InstallRoot 'tlpkg\texlive.tlpdb') -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $NoUserPath) { Append-UserPath $bin }
    $receipt.status='passed'; $receipt.completed_utc=[DateTime]::UtcNow.ToString('o')
    Progress 'TinyTeX, Chinese XeLaTeX, latexmk, PDF and SyncTeX checks passed.'
    Save-Receipt
}
catch {
    $receipt.status='failed'; $receipt.error=$_.Exception.Message; $receipt.completed_utc=[DateTime]::UtcNow.ToString('o')
    Progress ('Stopped; existing installations and partial owned output preserved. '+$_.Exception.Message)
    Save-Receipt
    throw
}
finally {
    foreach ($variable in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($variable,$savedEnvironment[$variable],'Process') }
}
