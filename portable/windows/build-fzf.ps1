#requires -Version 5.1
<# Build the pinned Telescope sorter for the Neovim process architecture. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [string]$CMake = 'cmake.exe'
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($Source)
$buildRoot = [IO.Path]::GetFullPath($BuildDirectory)
if ($buildRoot.StartsWith('\\')) { throw 'MSVC requires a local Windows build directory rather than a UNC path.' }
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'src\fzf.c') -PathType Leaf)) {
    throw 'The Telescope FZF source is missing.'
}
$null = New-Item -ItemType Directory -Path $buildRoot -Force
$cmakePath = (Get-Command $CMake -ErrorAction Stop).Source

function Quote-Argument([string]$Value) {
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-CMake([string[]]$Arguments, [string]$LogName) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $cmakePath
    $start.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Cannot start CMake.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            # Only this helper's build process and its compiler children are owned here.
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            throw ('Telescope FZF build timed out: ' + $LogName)
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $buildRoot ($LogName + '.log')), $log)
        if ($process.ExitCode -ne 0) { throw ('Telescope FZF build failed; see ' + (Join-Path $buildRoot ($LogName + '.log'))) }
    }
    finally { $process.Dispose() }
}

$platform = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
Invoke-CMake @('-S', $sourceRoot, '-B', $buildRoot, '-G', 'Visual Studio 17 2022', '-A', $platform,
    '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded') 'configure'
# Upstream's install target puts the DLL at the location used by its Lua loader;
# the multi-config Release directory alone is insufficient.
Invoke-CMake @('--build', $buildRoot, '--config', 'Release', '--target', 'install', '--parallel', '2') 'build'
$library = Join-Path $buildRoot 'libfzf.dll'
if (-not (Test-Path -LiteralPath $library -PathType Leaf)) { throw 'Telescope FZF did not produce libfzf.dll.' }
$stream = [IO.File]::OpenRead($library)
try {
    $reader = New-Object IO.BinaryReader($stream)
    $stream.Position = 60
    $offset = $reader.ReadInt32()
    $stream.Position = $offset + 4
    $machine = $reader.ReadUInt16()
}
finally { $stream.Dispose() }
$expected = if ($Architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
if ($machine -ne $expected) { throw 'Telescope FZF architecture does not match the requested Neovim architecture.' }
Write-Output $library
