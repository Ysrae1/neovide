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
function Write-DependencyJson([string]$Path,$Value) {
    $temporary=$Path+'.preparing-'+[Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,$null) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
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
function Invoke-DependencyProcess {
    param([string]$Executable,[string[]]$Arguments,[string]$Name,[int]$TimeoutSeconds=1200,[string]$Directory=$script:DependencyRun)
    Write-Host ('Installing / checking: '+$Name)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable; $start.Arguments=(@($Arguments|ForEach-Object { Quote-Argument $_ }) -join ' ')
    $start.UseShellExecute=$false; $start.CreateNoWindow=$false; $start.WorkingDirectory=$Directory
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw ('Cannot start '+$Name) }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.WaitForExit(1000)) {
            Write-Progress -Activity 'Neovide Glow setup' -Status $Name
            if ([DateTime]::UtcNow -ge $deadline) {
                & (Join-Path $env:WINDIR 'System32\taskkill.exe') /PID $process.Id /T /F | Out-Null
                $process.WaitForExit(); throw ('Timed out: '+$Name)
            }
        }
        $output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
        if ($output.Length -gt 2MB) { $output='[final 2 MiB]'+$output.Substring($output.Length-2MB) }
        $log=Join-Path $script:DependencyRun ($Name+'.log')
        [IO.File]::WriteAllText($log,$output,(New-Object Text.UTF8Encoding($false)))
        $script:DependencyChecks+=@{name=$Name;exit_code=$process.ExitCode;log=$log}
        if ($process.ExitCode -notin @(0,3010)) {
            Write-Host $output.Substring([Math]::Max(0,$output.Length-2500))
            throw ($Name+' failed ('+$process.ExitCode+'). Partial owned output and logs were preserved.')
        }
        return $output
    } finally { Write-Progress -Activity 'Neovide Glow setup' -Completed; $process.Dispose() }
}
function Get-DependencyAsset($Asset) {
    if ($Asset.url -notmatch '^https://' -or $Asset.sha256 -notmatch '^[0-9a-f]{64}$' -or
        $Asset.filename -notmatch '^[A-Za-z0-9._+-]+$' -or $Asset.download_size -le 0) { throw 'Invalid locked dependency asset.' }
    $cache=Join-Path $DependencyRoot 'downloads-v1'
    Initialize-DependencyDirectory $cache 'glow-download-cache-v1'
    $destination=Join-Path $cache $Asset.filename
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if ((Get-Item -LiteralPath $destination).Length -eq $Asset.download_size -and
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $Asset.sha256) { return $destination }
        throw ('Cached asset failed verification; preserved: '+$destination)
    }
    $partial=$destination+'.part'
    $offset=0L
    if (Test-Path -LiteralPath $partial -PathType Leaf) { $offset=(Get-Item -LiteralPath $partial).Length }
    if ($offset -gt $Asset.download_size) { throw 'Partial download exceeds the locked size; preserved.' }
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
            try {
                while (($read=$input.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $file.Write($buffer,0,$read); $offset+=$read
                    if ($offset -gt $Asset.download_size) { throw 'Download exceeds the locked size; no asset was executed.' }
                    Write-Progress -Activity ('Downloading '+$Asset.filename) -Status ('{0:N1} / {1:N1} MiB' -f ($offset/1MB),($Asset.download_size/1MB)) -PercentComplete ([Math]::Min(100,[int](100*$offset/$Asset.download_size)))
                }
            } finally { $input.Dispose(); $file.Dispose(); Write-Progress -Activity ('Downloading '+$Asset.filename) -Completed }
        } finally { $response.Dispose() }
    }
    if ((Get-Item -LiteralPath $partial).Length -ne $Asset.download_size -or
        (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Asset.sha256) {
        throw ('Download size/SHA256 mismatch. No asset was executed; bytes preserved: '+$partial)
    }
    [IO.File]::Move($partial,$destination)
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
