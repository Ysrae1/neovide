#requires -Version 5.1
# Sourced by Setup-Dependencies.ps1. No top-level writes, downloads, or installs.
function Get-DependencySelectedPaths([string]$Selection) {
    if (-not (Test-Path -LiteralPath $Selection -PathType Leaf)) { return }
    try {
        $record=Get-Content -LiteralPath $Selection -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($record.schema_version -ne 1 -or -not $record.PSObject.Properties['tool_paths'] -or $record.tool_paths -isnot [Array]) { return }
        foreach ($path in $record.tool_paths) {
            if ($path -is [string] -and [IO.Path]::IsPathRooted($path) -and (Test-Path -LiteralPath $path -PathType Container)) {
                [IO.Path]::GetFullPath($path)
            }
        }
    } catch { return } # Malformed selections cannot become executable search paths.
}
function Get-DependencyTeXTarget([string]$Primary,[string]$Fallback) {
    # This marker is written and validated by tex/Install-TinyTeX.ps1.
    $root=$Primary
    $marker='.glow-tinytex-v1-owner.json'
    if ((Test-Path -LiteralPath $root) -and -not (Test-Path -LiteralPath (Join-Path $root $marker) -PathType Leaf)) { $root=$Fallback }
    [pscustomobject]@{root=$root;resume=(Test-Path -LiteralPath (Join-Path $root $marker) -PathType Leaf)}
}
function Get-JupyterPythonCandidates([string[]]$DataRoots) {
    # Read the standard kernelspec locations, never execute a kernel's argv.
    # https://jupyter-client.readthedocs.io/en/stable/kernels.html#kernel-specs
    foreach ($root in @($DataRoots | Where-Object { $_ } | Select-Object -Unique)) {
        $kernels=Join-Path $root 'kernels'
        if (-not (Test-Path -LiteralPath $kernels -PathType Container)) { continue }
        foreach ($directory in @(Get-ChildItem -LiteralPath $kernels -Directory -ErrorAction SilentlyContinue)) {
            $file=Join-Path $directory.FullName 'kernel.json'
            try {
                if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -gt 1MB) { continue }
                $spec=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $spec.PSObject.Properties['argv'] -or $spec.argv -isnot [Array] -or $spec.argv.Count -eq 0) { continue }
                $executable=$spec.argv[0]
                if ($executable -is [string] -and [IO.Path]::IsPathRooted($executable) -and
                    [IO.Path]::GetFileName($executable) -match '^python(?:[0-9.]*)?\.exe$' -and
                    (Test-Path -LiteralPath $executable -PathType Leaf)) { $executable }
            } catch { continue } # A broken/unreadable kernelspec is not a Python installation.
        }
    }
}
function Write-DependencyJson([string]$Path,$Value,[string]$BackupPath) {
    $temporary=$Path+'.preparing-'+[Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
        # Always use a real same-volume backup path on Windows PowerShell 5.1.
        if (Test-Path -LiteralPath $Path) {
            if (-not $BackupPath) { $BackupPath=$Path+'.before-'+[Guid]::NewGuid().ToString('N') }
            [IO.File]::Replace($temporary,$Path,$BackupPath)
        }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Set-DependencyStatus {
    param([string]$State,[string]$Phase,[string]$Detail,[long]$DownloadedBytes=0,[long]$TotalBytes=0,[string]$ErrorMessage,
        [string]$StatusPath,[string]$RunPath)
    if (-not $PSBoundParameters.ContainsKey('StatusPath')) {
        $setting=Get-Variable -Name DependencyStatusPath -Scope Script -ErrorAction SilentlyContinue
        if ($setting) { $StatusPath=$setting.Value }
    }
    if (-not $StatusPath) { return }
    if (-not $PSBoundParameters.ContainsKey('RunPath')) {
        $run=Get-Variable -Name DependencyRun -Scope Script -ErrorAction SilentlyContinue
        if ($run) { $RunPath=$run.Value }
    }
    $record=@{schema_version=1;state=$State;phase=$Phase;detail=$Detail;
        downloaded_bytes=$DownloadedBytes;total_bytes=$TotalBytes;updated_utc=[DateTime]::UtcNow.ToString('o');run_path=$null;error=$ErrorMessage}
    $record.run_path=$RunPath
    Write-DependencyJson $StatusPath $record ($StatusPath+'.previous')
}
function New-DependencyPhaseCallback {
    # A separately invoked child has its own script scope. Capture the parent's
    # status destination, run identity and helpers before crossing that boundary.
    $setting=Get-Variable -Name DependencyStatusPath -Scope Script -ErrorAction SilentlyContinue
    $statusPath=if ($setting) { $setting.Value } else { $null }
    $run=Get-Variable -Name DependencyRun -Scope Script -ErrorAction SilentlyContinue
    $runPath=if ($run) { $run.Value } else { $null }
    $setStatus=${function:Set-DependencyStatus}
    $writeJson=${function:Write-DependencyJson}
    return {
        param([string]$Phase,[string]$Detail)
        function Write-DependencyJson { param($Path,$Value,$BackupPath); & $writeJson $Path $Value $BackupPath }
        & $setStatus -State 'running' -Phase $Phase -Detail $Detail -StatusPath $statusPath -RunPath $runPath
    }.GetNewClosure()
}
function Get-DependencyDownloadBytes($Asset,[string]$Root) {
    $cache=Join-Path $Root 'downloads-v1'
    $marker=Join-Path $cache '.glow-dependency-owner.json'
    $file=Join-Path $cache $Asset.filename
    if ((Test-Path -LiteralPath $marker -PathType Leaf) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
        try {
            $owner=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
            if ($owner.schema_version -eq 1 -and $owner.owner -ceq 'glow-download-cache-v1' -and
                (Get-Item -LiteralPath $file).Length -eq $Asset.download_size -and
                (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Asset.sha256) { return 0L }
        } catch {} # The install path will explain invalid/locked cache bytes.
    }
    return [long]$Asset.download_size
}
function New-DependencyPlan {
    param($Tools,$Assets,[string]$Root,[string[]]$Roles,[bool]$Notebook,[bool]$Latex,$Selected,$Base,[bool]$UnknownPython)
    $mapping=@{search='rg';find='fd';yazi='yazi';fzf='fzf';git='git';webview2='webview2'}
    $items=@(); $dynamic=@(); $known=0L
    foreach ($role in @($Roles|Select-Object -Unique)) {
        $tool=$Tools|Where-Object {$_.role -eq $role}|Select-Object -First 1
        if (-not $tool) { continue }
        $bytes=0L; $note='Existing compatible tool will be reused.'; $status='reuse'
        if (-not $tool.available) {
            $status='missing'
            if ($mapping.ContainsKey($role)) {
                $asset=$Assets.($mapping[$role]); $bytes=Get-DependencyDownloadBytes $asset $Root
                $note=if ($bytes) {'Locked x64-compatible tool download; existing tools are preserved.'} else {'Verified cached download will be reused.'}
                if ($role -eq 'webview2') {
                    $note='Microsoft bootstrapper; the device runtime is an additional provider download.'
                    $dynamic+=@('WebView2 runtime: Microsoft determines device-specific download size.')
                    if ($tool.status -eq 'unknown') { $status='blocked'; $note='Runtime registration is unreadable; setup stops without installing a replacement.' }
                }
            } else {
                $bytes=$null; $note='Selected package provider determines the download size and may ask for installation approval.'
                $dynamic+=@($role+': package provider determines download size.')
            }
        }
        if ($null -ne $bytes) { $known+=$bytes }
        $items+=@([pscustomobject]@{role=$role;status=$status;reuse_path=$tool.path;download_bytes=$bytes;download_note=$note})
    }
    if ($Notebook) {
        $bytes=0L; $status='reuse'; $path=$null
        if ($Selected) { $path=$Selected.python; $note='Complete existing Notebook environment will be reused.' }
        elseif ($UnknownPython) { $status='blocked'; $note='An existing Python inspection is inconclusive; setup stops before downloading packages.' }
        else {
            $status='missing'; $note='Packages go into a separate Glow environment; existing Python/Conda packages are preserved.'
            if ($Base) { $path=$Base.python }
            else { $bytes=Get-DependencyDownloadBytes $Assets.python $Root; $note+=' The locked CPython 3.12 x64 installer is used when no compatible Python is found.' }
            $dynamic+=@('Notebook wheels and text converter: pip resolves the package download size for the selected Python architecture.')
        }
        $known+=$bytes
        $items+=@([pscustomobject]@{role='notebook';status=$status;reuse_path=$path;download_bytes=$bytes;download_note=$note})
    }
    if ($Latex) {
        $tex=$Tools|Where-Object {$_.role -eq 'latex'}|Select-Object -First 1
        $bytes=0L; $status='check'; $note='Existing TeX is reused after Chinese XeLaTeX / latexmk / SyncTeX checks; a failed check can require separate TinyTeX.'
        if (-not $tex.available) { $status='missing'; $bytes=Get-DependencyDownloadBytes $Assets.tinytex $Root; $note='Install a separate owned TinyTeX; existing TeX directories are preserved.' }
        else { $dynamic+=@('TeX fallback: a failed existing-TeX check may require the locked TinyTeX archive ('+$Assets.tinytex.download_size+' bytes).') }
        $dynamic+=@('TeX packages: additional selected packages are downloaded by TeX Live; size is determined by its repository.')
        $known+=$bytes
        $items+=@([pscustomobject]@{role='latex';status=$status;reuse_path=$tex.path;download_bytes=$bytes;download_note=$note})
    }
    [pscustomobject]@{items=@($items);known_download_bytes=$known;dynamic_downloads=@($dynamic);
        features=@{base=(@($Roles) -contains 'search');notebook=$Notebook;latex=$Latex};
        download_note='Known bytes exclude provider downloads and partial-file resume savings. Verified cached archives count as zero. Shared CLI fallbacks are locked x64 binaries, including on ARM64 Windows.'}
}
function Initialize-DependencyDirectory([string]$Path,[string]$Owner) {
    $marker=Join-Path $Path '.glow-dependency-owner.json'
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked dependency directories are not accepted.' }
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw ('Existing unowned dependency directory preserved: '+$Path) }
        $record=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($record.schema_version -ne 1 -or $record.owner -cne $Owner) { throw ('Dependency directory ownership mismatch: '+$Path) }
    } else {
        $null=New-Item -ItemType Directory -Path $Path -Force
        Write-DependencyJson $marker @{schema_version=1;owner=$Owner}
    }
}
function ConvertTo-DependencyArgumentString([string[]]$Arguments) {
    (@($Arguments|ForEach-Object {
        # CommandLineToArgvW quoting, including a trailing backslash in a path.
        $value=[string]$_
        '"'+[regex]::Replace([regex]::Replace($value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
    }) -join ' ')
}
function Invoke-DependencyProcess {
    param([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$TimeoutSeconds=1200,[string]$Directory=$script:DependencyRun)
    Write-Host ('Installing / checking: '+$Name)
    Set-DependencyStatus 'running' $Name ('Installing / checking: '+$Name)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable; $start.Arguments=ConvertTo-DependencyArgumentString $Arguments
    # Console output is relayed through setup; GUI installers retain their UI.
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WorkingDirectory=$Directory
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$start
    $stdout=$null; $stderr=$null
    $log=Join-Path $script:DependencyRun ($Name+'.log')
    $check=@{name=$Name;pid=$null;exit_code=$null;timed_out=$false;output_drain_complete=$false;log=$log}
    $script:DependencyChecks+=@($check)
    try {
        if (-not $process.Start()) { throw ('Cannot start '+$Name) }
        $check.pid=$process.Id
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.WaitForExit(1000)) {
            Write-Progress -Activity 'Neovide Glow setup' -Status $Name
            if ([DateTime]::UtcNow -ge $deadline) {
                $check.timed_out=$true
                $killer=New-Object Diagnostics.Process
                $killer.StartInfo.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe'
                $killer.StartInfo.Arguments='/PID '+$process.Id+' /T /F'
                $killer.StartInfo.UseShellExecute=$false; $killer.StartInfo.CreateNoWindow=$true
                $killer.StartInfo.RedirectStandardOutput=$true; $killer.StartInfo.RedirectStandardError=$true
                try {
                    if (-not $killer.Start()) { throw 'Could not start owned-tree termination.' }
                    $killOut=$killer.StandardOutput.ReadToEndAsync(); $killErr=$killer.StandardError.ReadToEndAsync()
                    if (-not $killer.WaitForExit(5000)) { $killer.Kill(); $null=$killer.WaitForExit(1000) }
                    if ($killer.HasExited -and $killer.ExitCode -ne 0) { $check['stop_error']='Owned-tree termination returned '+$killer.ExitCode }
                } catch { $check['stop_error']=$_.Exception.Message }
                finally { $killer.Dispose() }
                $null=$process.WaitForExit(5000)
                break
            }
        }
        try { $check.output_drain_complete=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),2000) }
        catch { $check['output_error']=$_.Exception.Message }
        $output=''
        foreach ($stream in @($stdout,$stderr)) {
            if ($stream.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion) { $output+=$stream.GetAwaiter().GetResult() }
            else { $output+='[Output pipe did not close within the drain deadline.]' }
        }
        if ($output.Length -gt 2MB) { $output='[final 2 MiB]'+$output.Substring($output.Length-2MB) }
        [IO.File]::WriteAllText($log,$output,(New-Object Text.UTF8Encoding($false)))
        if ($process.HasExited) { $check.exit_code=$process.ExitCode }
        if ($check.timed_out) { throw [TimeoutException]::new(('Timed out: '+$Name+'. Logs and partial owned output preserved: '+$log)) }
        if (-not $check.output_drain_complete) { throw [TimeoutException]::new(('Output handles did not close: '+$Name+'. Inspect the recorded PID/log before retrying: '+$log)) }
        if ($process.ExitCode -notin @(0,3010)) {
            Write-Host $output.Substring([Math]::Max(0,$output.Length-2500))
            throw ($Name+' failed ('+$process.ExitCode+'). Partial owned output and logs were preserved.')
        }
        return $output
    } finally {
        Write-Progress -Activity 'Neovide Glow setup' -Completed
        if ($stdout) { try { $process.StandardOutput.Close() } catch {} }
        if ($stderr) { try { $process.StandardError.Close() } catch {} }
        $process.Dispose()
    }
}
function Get-DependencyAsset($Asset) {
    if ($Asset.url -notmatch '^https://' -or $Asset.sha256 -notmatch '^[0-9a-f]{64}$' -or
        $Asset.filename -notmatch '^[A-Za-z0-9._+-]+$' -or $Asset.download_size -le 0) { throw 'Invalid locked dependency asset.' }
    $cache=Join-Path $DependencyRoot 'downloads-v1'
    Initialize-DependencyDirectory $cache 'glow-download-cache-v1'
    $destination=Join-Path $cache $Asset.filename
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if ((Get-Item -LiteralPath $destination).Length -eq $Asset.download_size -and
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Asset.sha256) {
            Set-DependencyStatus 'running' 'download' ('Reusing verified download: '+$Asset.filename) $Asset.download_size $Asset.download_size
            return $destination
        }
        throw ('Cached asset failed verification; preserved: '+$destination+'. Move this file aside, then retry the same feature selection to download a verified copy.')
    }
    $partial=$destination+'.part'
    $offset=0L
    if (Test-Path -LiteralPath $partial -PathType Leaf) { $offset=(Get-Item -LiteralPath $partial).Length }
    if ($offset -gt $Asset.download_size) { throw ('Partial download exceeds the locked size; preserved: '+$partial+'. Move this file aside, then retry the same feature selection.') }
    Set-DependencyStatus 'running' 'download' ('Downloading '+$Asset.filename+'; retrying the same selection resumes retained partial bytes.') $offset $Asset.download_size
    if ($offset -lt $Asset.download_size) {
        [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $request=[Net.HttpWebRequest]::Create($Asset.url); $request.Timeout=60000; $request.ReadWriteTimeout=60000
        $request.UserAgent='NeovideGlow-DependencySetup/1'
        if ($offset) { $request.AddRange($offset) }
        $response=$request.GetResponse()
        try {
            if ($response.ResponseUri.Scheme -cne 'https') { throw 'Dependency download redirected away from HTTPS; no asset was executed.' }
            if ($offset -and $response.StatusCode -eq [Net.HttpStatusCode]::PartialContent) {
                if ($response.Headers['Content-Range'] -notlike ('bytes '+$offset+'-*')) { throw 'Unexpected resume range; partial download preserved.' }
                $mode=[IO.FileMode]::Append
            } else { $offset=0L; $mode=[IO.FileMode]::Create }
            $file=New-Object IO.FileStream($partial,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $input=$response.GetResponseStream(); $buffer=New-Object byte[] 131072
            $nextStatus=[DateTime]::UtcNow
            try {
                while (($read=$input.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $file.Write($buffer,0,$read); $offset+=$read
                    if ($offset -gt $Asset.download_size) { throw 'Download exceeds the locked size; no asset was executed.' }
                    Write-Progress -Activity ('Downloading '+$Asset.filename) -Status ('{0:N1} / {1:N1} MiB' -f ($offset/1MB),($Asset.download_size/1MB)) -PercentComplete ([Math]::Min(100,[int](100*$offset/$Asset.download_size)))
                    if ([DateTime]::UtcNow -ge $nextStatus) {
                        Set-DependencyStatus 'running' 'download' ('Downloading '+$Asset.filename) $offset $Asset.download_size
                        $nextStatus=[DateTime]::UtcNow.AddMilliseconds(500)
                    }
                }
            } finally { $input.Dispose(); $file.Dispose(); Write-Progress -Activity ('Downloading '+$Asset.filename) -Completed }
        } finally { $response.Dispose() }
    }
    if ((Get-Item -LiteralPath $partial).Length -ne $Asset.download_size -or
        (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Asset.sha256) {
        throw ('Download size/SHA256 mismatch. No asset was executed; bytes preserved: '+$partial+'. Move this file aside, then retry the same feature selection.')
    }
    [IO.File]::Move($partial,$destination)
    Set-DependencyStatus 'running' 'download' ('Verified '+$Asset.filename) $Asset.download_size $Asset.download_size
    return $destination
}
function Expand-DependencyZip([string]$Archive,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $prefix=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'; $total=0L
        foreach ($entry in $zip.Entries) {
            $name=$entry.FullName.Replace('/','\')
            $unixType=($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($name -match '(^[\\/]|:|(^|[\\/])\.\.([\\/]|$))' -or $unixType -eq 0xA000) { throw 'Unsafe zip entry; archive was not extracted.' }
            $target=[IO.Path]::GetFullPath((Join-Path $Destination $name))
            if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Zip path escapes the selected dependency directory.' }
            $total+=$entry.Length
            if ($total -gt 512MB) { throw 'Dependency archive exceeds extraction budget.' }
        }
        foreach ($entry in $zip.Entries) {
            $target=Join-Path $Destination ($entry.FullName.Replace('/','\'))
            if ($entry.FullName.EndsWith('/')) { $null=New-Item -ItemType Directory -Path $target -Force; continue }
            $null=New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
            $input=$entry.Open(); $output=[IO.File]::Open($target,[IO.FileMode]::CreateNew)
            try { $input.CopyTo($output) } finally { $input.Dispose(); $output.Dispose() }
        }
    } finally { $zip.Dispose() }
}
function Install-DependencyTool([string]$Name,$Asset) {
    $root=Join-Path $DependencyRoot ('programs-v1\'+$Name+'-'+$Asset.version)
    Initialize-DependencyDirectory $root ('glow-tool-'+$Name+'-'+$Asset.sha256)
    $payload=Join-Path $root 'payload'
    if (-not (Test-Path -LiteralPath $payload)) {
        $archive=Get-DependencyAsset $Asset
        $extract=Join-Path $root ('extract-'+[Guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path $extract
        if ($Asset.format -eq 'zip') { Expand-DependencyZip $archive $extract }
        elseif ($Name -eq 'git' -and $Asset.format -eq '7zip') {
            $null=Invoke-DependencyProcess $archive @('-y',('-o'+$extract)) 'extract-Git' 240
        } else { throw 'Unsupported dependency archive format.' }
        Move-Item -LiteralPath $extract -Destination $payload
    }
    $binaries=@(Get-ChildItem -LiteralPath $payload -Recurse -File -Filter $Asset.binary)
    if ($Name -eq 'git') { $binaries=@($binaries|Where-Object {$_.FullName -like '*\cmd\git.exe'}) }
    if ($binaries.Count -ne 1) { throw ('Expected one dependency executable: '+$Name) }
    $binary=$binaries[0].FullName
    $null=Invoke-DependencyProcess $binary @('--version') ('check-'+$Name) 20
    return $binary
}
function Install-DependencyPython($Asset) {
    $root=Join-Path $env:LOCALAPPDATA 'Programs\NeovideGlow-Python312'
    Initialize-DependencyDirectory $root ('glow-cpython-'+$Asset.sha256)
    $python=Join-Path $root 'python.exe'
    $probe=Probe-Python $python
    if ($probe -and $probe.compatible) { return $probe }
    $installer=Get-DependencyAsset $Asset
    $signature=Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Python Software Foundation*') { throw 'The locked Python installer does not have a valid Python Software Foundation signature.' }
    # Standard per-user CPython installation, independent of Glow/Conda. No PATH,
    # associations, launcher, test suite, or system install.
    $null=Invoke-DependencyProcess $installer @('/passive','InstallAllUsers=0',('TargetDir='+$root),
        'PrependPath=0','AppendPath=0','Include_launcher=0','InstallLauncherAllUsers=0','Include_test=0',
        'Include_doc=0','Include_tcltk=0','AssociateFiles=0','Shortcuts=0','Include_pip=1',
        '/log',(Join-Path $script:DependencyRun 'python-installer.log')) 'install-CPython312' 600
    $probe=Probe-Python $python
    if (-not $probe -or -not $probe.compatible) { throw 'Installed Python did not pass the x64 CPython 3.12 probe.' }
    return $probe
}
