#requires -Version 5.1
<# Build-worker only. Installed users run the resulting offline installer. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version = '2026.10.20.1',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$')][string]$StackId = 'glow-windows-native-20261020-preview1',
    [switch]$InstallerSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
    throw 'Build this package in an x64 Windows developer shell.'
}
if ($InstallerSmokeTest -and $env:GITHUB_ACTIONS -ne 'true') {
    throw 'The automatic installation/uninstallation smoke test is restricted to the disposable GitHub Actions worker.'
}
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$work = [IO.Path]::GetFullPath($WorkRoot)
if (Test-Path -LiteralPath $work) {
    if (@(Get-ChildItem -LiteralPath $work -Force).Count -ne 0) {
        throw 'WorkRoot must be a fresh empty directory. Existing files were preserved.'
    }
}
$null = New-Item -ItemType Directory -Path $work -Force
$logs = Join-Path $work 'logs'
$output = Join-Path $work 'output'
$null = New-Item -ItemType Directory -Path $logs, $output -Force
$transcribing = $false
$savedEnvironment = @{}
foreach ($name in @('PATH', 'RUSTFLAGS', 'CARGO_TARGET_DIR', 'LLVM_HOME', 'LIBCLANG_PATH')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Invoke-Checked {
    param([string]$File, [string[]]$Arguments = @(), [string]$Directory)
    $previous = Get-Location
    try {
        if ($Directory) { Set-Location -LiteralPath $Directory }
        $global:LASTEXITCODE = 0
        & $File @Arguments
        if ($LASTEXITCODE -ne 0) { throw ('Build command failed (' + $LASTEXITCODE + '): ' + [IO.Path]::GetFileName($File)) }
    }
    finally { Set-Location -LiteralPath $previous.Path }
}

function Quote-WindowsArgument {
    param([AllowEmptyString()][string]$Value)
    $quoted = New-Object Text.StringBuilder
    $null = $quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        $count = $slashes
        if ($character -eq '"') { $count = $slashes * 2 + 1 }
        $null = $quoted.Append('\', $count)
        $null = $quoted.Append($character)
        $slashes = 0
    }
    $null = $quoted.Append('\', $slashes * 2)
    $null = $quoted.Append('"')
    return $quoted.ToString()
}

function Invoke-Bounded {
    param(
        [string]$File, [string[]]$Arguments = @(), [hashtable]$Environment = @{},
        [string]$Directory, [int]$TimeoutSeconds = 120, [string]$LogName = 'check',
        [int[]]$AcceptedExitCodes = @(0)
    )
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $File
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $work
    if ($Directory) { $start.WorkingDirectory = $Directory }
    $start.Arguments = (@($Arguments | ForEach-Object { Quote-WindowsArgument $_ }) -join ' ')
    if ([IO.Path]::GetExtension($File) -in @('.cmd', '.bat')) {
        # ProcessStartInfo cannot execute batch files directly with
        # UseShellExecute=false. Only release-worker-owned tool paths enter here.
        $start.FileName = $env:COMSPEC
        $start.Arguments = '/d /s /c "' + (Quote-WindowsArgument $File) + ' ' + $start.Arguments + '"'
    }
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { $start.EnvironmentVariables.Remove($name) }
        else { $start.EnvironmentVariables[$name] = [string]$Environment[$name] }
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw ('Cannot start ' + [IO.Path]::GetFileName($File)) }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            if ($PSVersionTable.PSVersion.Major -ge 7) { $process.Kill($true) }
            else { $process.Kill() }
            $process.WaitForExit()
            throw ('Check timed out: ' + $LogName)
        }
        $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $logs ($LogName + '.log')), $text, (New-Object Text.UTF8Encoding($false)))
        if ($text) { Write-Host $text.TrimEnd() }
        if ($AcceptedExitCodes -notcontains $process.ExitCode) { throw ('Check failed (' + $process.ExitCode + '): ' + $LogName) }
    }
    finally { $process.Dispose() }
}

function Copy-CrtRuntime {
    param([string]$Destination)
    if (-not $env:VCToolsRedistDir) { throw 'The x64 MSVC developer environment did not expose VCToolsRedistDir.' }
    $redist = Join-Path $env:VCToolsRedistDir 'x64'
    $directory = @(Get-ChildItem -LiteralPath $redist -Directory -Filter 'Microsoft.VC*.CRT' | Sort-Object FullName -Descending)
    if ($directory.Count -eq 0) { throw 'The Visual C++ x64 release redistributable DLLs are missing.' }
    $copied = @()
    foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'msvcp140_atomic_wait.dll', 'msvcp140_codecvt_ids.dll', 'concrt140.dll')) {
        $source = Join-Path $directory[0].FullName $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $Destination $name)
            $copied += $name
        }
    }
    if ($copied -notcontains 'vcruntime140.dll' -or $copied -notcontains 'msvcp140.dll') {
        throw 'The required Microsoft release CRT DLLs could not be collected.'
    }
    return $copied
}

function New-PackagedEnvironment {
    param([string]$Application, [string]$Profile)
    $bundle = Get-Content -LiteralPath (Join-Path $Application 'bundle.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $paths = @((Join-Path $Application 'bin'), (Join-Path $Profile 'data\nvim-data\mason\bin'))
    foreach ($relative in @($bundle.tool_paths)) { $paths += Join-Path $Application $relative }
    $paths += @((Join-Path $env:WINDIR 'System32'), $env:WINDIR, (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0'))
    $environment = @{
        PATH = ($paths -join ';'); NVIM_APPNAME = 'nvim'; PYTHONNOUSERSITE = '1'; PYTHONUTF8 = '1';
        XDG_CONFIG_HOME = (Join-Path $Profile 'config'); XDG_DATA_HOME = (Join-Path $Profile 'data');
        XDG_STATE_HOME = (Join-Path $Profile 'state'); XDG_CACHE_HOME = (Join-Path $Profile 'cache');
        NEOVIDE_GLOW_ROOT = $Application; NEOVIDE_GLOW_INIT = (Join-Path $Application 'runtime\lua\WindowsInit.lua');
        GLOW_PYTHON = (Join-Path $Application 'runtime\python\python.exe');
        JAVA_HOME = (Join-Path $Application 'runtime\java');
        YAZI_FILE_ONE = 'file.exe';
        NEOVIDE_GLOW_PYTHON = (Join-Path $Application 'runtime\python\python.exe');
        NEOVIDE_CONFIG = (Join-Path $Application 'config\neovide.toml');
        GLOW_LATEX2TEXT = (Join-Path $Application 'bin\latex2text.exe');
        JUPYTER_DATA_DIR = (Join-Path $Profile 'data\jupyter'); JUPYTER_CONFIG_DIR = (Join-Path $Profile 'config\jupyter');
        JUPYTER_RUNTIME_DIR = (Join-Path $Profile 'state\jupyter'); MPLCONFIGDIR = (Join-Path $Profile 'cache\matplotlib');
        NVIM_RPLUGIN_MANIFEST = (Join-Path $Profile 'data\nvim-data\rplugin.vim');
        NEOVIDE_BUNDLE_PLATFORM = 'windows-x64'; NEOVIDE_BUNDLE_PAYLOAD = (Join-Path $repoRoot 'portable\payload');
        NVIM_BUNDLE_PHASE = 'health'
    }
    foreach ($name in @('PYTHONHOME', 'PYTHONPATH', 'VIRTUAL_ENV', 'CONDA_PREFIX', 'VIM', 'VIMRUNTIME', 'NVIM', 'NVIM_LISTEN_ADDRESS', 'LLVM_HOME', 'LIBCLANG_PATH', 'CARGO_TARGET_DIR', 'VSINSTALLDIR', 'VCINSTALLDIR', 'VCToolsInstallDir')) {
        $environment[$name] = $null
    }
    return $environment
}

try {
    Start-Transcript -LiteralPath (Join-Path $logs 'build-transcript.log') | Out-Null
    $transcribing = $true
    foreach ($command in @('git', 'python', 'cargo', 'rustup', 'cl', 'cmake', 'ninja', '7z')) {
        $null = Get-Command $command -ErrorAction Stop
    }
    $builderPython = (Get-Command python -ErrorAction Stop).Source
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The Windows .NET Framework x64 C# compiler is unavailable.' }
    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($iscc) { $isccPath = $iscc.Source }
    else { $isccPath = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }
    if (-not (Test-Path -LiteralPath $isccPath -PathType Leaf)) { throw 'The release worker must have Inno Setup 6.3 or later installed.' }

    $manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'portable\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $lockPath = Join-Path $PSScriptRoot 'assets.lock.json'
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sourceCommit = [string]$manifest.neovide.commit
    if ($sourceCommit -cnotmatch '^[0-9a-f]{40}$' -or $sourceCommit -cne [string]$lock.neovide_commit) {
        throw 'The frozen source commit and Windows asset lock disagree.'
    }
    $toolchain = [string]$lock.rust_toolchain
    if ($toolchain -cne '1.99.1' -or $toolchain -cne [string]$manifest.neovide.rust_toolchain) {
        throw 'This Windows release requires the agreed Rust 1.99.1 toolchain.'
    }
    Invoke-Checked rustup @('run', $toolchain, 'rustc', '--version')
    $llvmCandidates = @($env:LLVM_HOME, $env:LLVM_PATH, (Join-Path $env:ProgramFiles 'LLVM'))
    $clang = Get-Command clang.exe -ErrorAction SilentlyContinue
    if ($clang) { $llvmCandidates += Split-Path -Parent (Split-Path -Parent $clang.Source) }
    $llvm = @($llvmCandidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'bin\libclang.dll') -PathType Leaf) })
    if ($llvm.Count -eq 0) { throw 'The release worker must provide x64 LLVM with libclang.dll.' }
    $env:LLVM_HOME = [string]$llvm[0]
    $env:LIBCLANG_PATH = Join-Path $env:LLVM_HOME 'bin'
    $env:PATH = $env:LIBCLANG_PATH + ';' + $env:PATH

    $stage = Join-Path $work 'stage'
    $bin = Join-Path $stage 'bin'
    $icon = Join-Path $repoRoot 'portable\payload\windows-icon.ico'
    $builder = Join-Path $PSScriptRoot 'build-bundle.py'
    $checkpointTool = Join-Path $PSScriptRoot 'payload-checkpoint.py'
    $checkpointArguments = @()
    $reusedDependencies = $false
    $rustEvidence = 'current_run'
    if ($env:GLOW_PAYLOAD_CACHE -or $env:GLOW_PAYLOAD_KEY) {
        if (-not $env:GLOW_PAYLOAD_CACHE -or -not $env:GLOW_PAYLOAD_KEY) {
            throw 'Dependency checkpoint directory and key must be provided together.'
        }
        $checkpointArguments = @('--cache', $env:GLOW_PAYLOAD_CACHE, '--stage', $stage,
            '--records', (Join-Path $work 'records'), '--key', $env:GLOW_PAYLOAD_KEY, '--asset-lock', $lockPath)
        if (Test-Path -LiteralPath $env:GLOW_PAYLOAD_CACHE) {
            Invoke-Checked $builderPython (@($checkpointTool, 'restore') + $checkpointArguments)
            Copy-Item -LiteralPath (Join-Path $env:GLOW_PAYLOAD_CACHE 'checkpoint.json') -Destination (Join-Path $logs 'dependency-checkpoint.json')
            $reusedDependencies = $true
            $rustEvidence = 'verified_dependency_checkpoint_see_dependency-checkpoint.json'
            Write-Host 'Verified and restored the frozen native dependencies; refreshing current configuration and launchers.'
        }
    }
    if ($reusedDependencies) {
        $frontend = Join-Path $bin 'neovide.exe'
        $common = @($builder, '--work', $work, '--frontend', $frontend, '--stack-id', $StackId)
        Invoke-Checked $builderPython ($common + @('--phase', 'refresh'))
    }
    else {
        $frontendSource = Join-Path $work 'frontend-source'
        Invoke-Checked git @('clone', '--no-hardlinks', '--no-checkout', $repoRoot, $frontendSource)
        Invoke-Checked git @('-C', $frontendSource, 'checkout', '--detach', $sourceCommit)
        $actualCommit = (& git -C $frontendSource rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $actualCommit -cne $sourceCommit) { throw 'The isolated frontend checkout has the wrong revision.' }
        Copy-Item -LiteralPath $icon -Destination (Join-Path $frontendSource 'assets\neovide.ico')
        $frontendTarget = Join-Path $work 'frontend-target'
        if ($env:GLOW_FRONTEND_TARGET) {
            $frontendTarget = [IO.Path]::GetFullPath($env:GLOW_FRONTEND_TARGET)
        }
        $env:CARGO_TARGET_DIR = $frontendTarget
        # Match the existing upstream Windows release build. Native Lua modules keep
        # their own build settings and use the collected release CRT when required.
        $env:RUSTFLAGS = '-Ctarget-feature=+crt-static'
        Invoke-Checked cargo @(('+' + $toolchain), 'build', '--release', '--locked', '--target', 'x86_64-pc-windows-msvc') $frontendSource
        $frontend = Join-Path $frontendTarget 'x86_64-pc-windows-msvc\release\neovide.exe'
        if (-not (Test-Path -LiteralPath $frontend -PathType Leaf)) { throw 'The native frontend was not built.' }
        $common = @($builder, '--work', $work, '--frontend', $frontend, '--stack-id', $StackId)
        Invoke-Checked $builderPython ($common + @('--phase', 'prepare'))
        # The settings integration test starts a real Neovim process. Use the exact
        # locked native binary that will ship, rather than the worker's global PATH.
        $env:PATH = $bin + ';' + $env:PATH
        Invoke-Checked cargo @(('+' + $toolchain), 'test', '--release', '--locked', '--target', 'x86_64-pc-windows-msvc') $frontendSource
        [Environment]::SetEnvironmentVariable('CARGO_TARGET_DIR', $savedEnvironment['CARGO_TARGET_DIR'], 'Process')
        [Environment]::SetEnvironmentVariable('RUSTFLAGS', $savedEnvironment['RUSTFLAGS'], 'Process')
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $work 'launchers') -Force
    $applicationManifest = Join-Path $work 'launchers\application.manifest'
    @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="NeovideGlow.NativeLauncher" processorArchitecture="amd64" type="win32" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false" /></requestedPrivileges></security></trustInfo>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware></windowsSettings></application>
</assembly>
'@ | Set-Content -LiteralPath $applicationManifest -Encoding UTF8
    $launcherArgs = @('/nologo', '/codepage:65001', '/optimize+', '/platform:x64', '/r:System.Runtime.Serialization.dll', ('/win32manifest:' + $applicationManifest))
    Invoke-Checked $compiler ($launcherArgs + @('/target:winexe', '/r:System.Windows.Forms.dll', ('/win32icon:' + $icon), ('/out:' + (Join-Path $stage 'Glow.exe')), (Join-Path $PSScriptRoot 'launcher\GlowLauncher.cs')))
    $launcherPaths = Join-Path $work 'launchers\WindowsLauncherPaths.exe'
    Invoke-Checked $compiler ($launcherArgs + @('/target:exe', '/main:WindowsLauncherPaths', '/r:System.Windows.Forms.dll', ('/out:' + $launcherPaths), (Join-Path $PSScriptRoot 'launcher\GlowLauncher.cs'), (Join-Path $repoRoot 'tests\windows_launcher_paths.cs')))
    Invoke-Bounded $launcherPaths @((Join-Path $work 'qa\launcher-paths')) @{} $work 120 'launcher-path-regression'
    $tool = Join-Path $work 'launchers\GlowTool.exe'
    Invoke-Checked $compiler ($launcherArgs + @('/target:exe', ('/out:' + $tool), (Join-Path $PSScriptRoot 'launcher\GlowTool.cs')))
    $runtimeConfig = '<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup><runtime><AppContextSwitchOverrides value="Switch.System.IO.UseLegacyPathHandling=false;Switch.System.IO.BlockLongPaths=false" /></runtime></configuration>'
    [IO.File]::WriteAllText((Join-Path $stage 'Glow.exe.config'), $runtimeConfig)
    foreach ($alias in @('python', 'python3', 'jupytext', 'latex2text', 'codex', 'codex-acp')) {
        Copy-Item -LiteralPath $tool -Destination (Join-Path $bin ($alias + '.exe'))
        [IO.File]::WriteAllText((Join-Path $bin ($alias + '.exe.config')), $runtimeConfig)
    }
    $crt = @(Copy-CrtRuntime $bin)
    if ($reusedDependencies) {
        # The restored Mason shims and native modules are already relocatable.
        # Recompile the current launchers, then seal the refreshed template;
        # every functional check below still runs against the new copy.
        Invoke-Checked $builderPython ($common + @('--phase', 'reseal'))
    }
    else {
        Invoke-Checked powershell.exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'matrix\build.ps1'), '-BuildDirectory', (Join-Path $work 'matrix-build'), '-OutputDirectory', $bin)
        Invoke-Checked $builderPython ($common + @('--phase', 'native'))
        Invoke-Checked $builderPython ($common + @('--phase', 'languages'))
        Invoke-Checked $builderPython ($common + @('--phase', 'assemble'))
        if ($checkpointArguments.Count -gt 0) {
            Invoke-Checked $builderPython (@($checkpointTool, 'save') + $checkpointArguments)
            Copy-Item -LiteralPath (Join-Path $env:GLOW_PAYLOAD_CACHE 'checkpoint.json') -Destination (Join-Path $logs 'dependency-checkpoint.json')
        }
    }

    # Copy before QA: builder paths, global Python/Node and compiler PATH entries
    # cannot accidentally make the relocated offline application appear healthy.
    $qaRoot = Join-Path $work "qa\Relocated 中文 O'Connor"
    $relocated = Join-Path $qaRoot 'Neovide Glow'
    $null = New-Item -ItemType Directory -Path $qaRoot -Force
    Copy-Item -LiteralPath $stage -Destination $relocated -Recurse
    $profile = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('NeovideGlow\profiles\' + $StackId)
    if (Test-Path -LiteralPath $profile) { throw 'Relocation QA requires a fresh disposable Windows account/profile. The existing profile was preserved.' }
    Invoke-Bounded (Join-Path $relocated 'Glow.exe') @('--launcher-check') @{} $qaRoot 60 'relocated-launcher-check'
    Invoke-Bounded (Join-Path $relocated 'Glow.exe') @('--initialize-profile') @{} $qaRoot 300 'relocated-profile-init'
    $qaEnvironment = New-PackagedEnvironment $relocated $profile
    $python = Join-Path $relocated 'runtime\python\python.exe'
    Invoke-Bounded $python @('-c', 'import pynvim,jupyter_client,jupytext,nbformat,PIL,matplotlib,pylatexenc,zmq,numpy;print("Relocated packaged Python imports passed")') $qaEnvironment $qaRoot 120 'relocated-python-imports'
    Invoke-Bounded (Join-Path $relocated 'bin\python3.exe') @('-c', 'import sys;print(sys.executable)') $qaEnvironment $qaRoot 60 'relocated-python-shim'
    Invoke-Bounded (Join-Path $relocated 'bin\jupytext.exe') @('--version') $qaEnvironment $qaRoot 60 'relocated-jupytext-shim'
    Invoke-Bounded (Join-Path $relocated 'bin\codex.exe') @('--version') $qaEnvironment $qaRoot 60 'relocated-codex-shim'
    foreach ($toolName in @('black', 'ruff', 'pyright', 'clangd', 'stylua', 'gofumpt')) {
        Invoke-Bounded (Join-Path $profile ('data\nvim-data\mason\bin\' + $toolName + '.cmd')) @('--version') $qaEnvironment $qaRoot 60 ('relocated-' + $toolName)
    }
    Invoke-Bounded (Join-Path $relocated 'bin\nvim.exe') @('--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE', '-l', (Join-Path $PSScriptRoot 'bootstrap.lua')) $qaEnvironment $qaRoot 180 'relocated-native-health'
    Invoke-Bounded $builderPython @((Join-Path $repoRoot 'tests\validate.py'), 'headless', '--config', (Join-Path $relocated 'profile\config\nvim'), '--nvim', (Join-Path $relocated 'bin\nvim.exe')) $qaEnvironment $qaRoot 600 'isolated-config-checks'
    $qaEnvironment['GLOW_TEST_DATA'] = Join-Path $profile 'data\nvim-data'
    # These independent checks must all report before packaging is blocked, so
    # a preview failure does not hide a separate Python/Notebook regression.
    $functionalFailures = New-Object 'Collections.Generic.List[string]'
    try { Invoke-Bounded $python @((Join-Path $repoRoot 'tests\media\yazi_native.py')) $qaEnvironment $qaRoot 180 'relocated-yazi-native-preview' }
    catch { $functionalFailures.Add('relocated-yazi-native-preview'); Write-Warning $_ }

    $qaScript = Join-Path $qaRoot 'profile-health.lua'
    @'
local function finish()
  local ok, err = xpcall(function()
    assert(vim.fn.has("win32") == 1, "Expected native Windows Neovim")
    local root = vim.fs.normalize(assert(vim.env.NEOVIDE_GLOW_ROOT)):gsub("/$", "")
    assert(vim.g.neovide_glow_windows_runtime == root, "The native runtime hook did not initialize")
    local runtime = require("config.media.runtime")
    assert(runtime.ready(), "The packaged Notebook runtime is not ready")
    assert(vim.fs.normalize(vim.g.python3_host_prog) == vim.fs.normalize(runtime.python()), "Wrong Python provider")
    local manifest = vim.fn.stdpath("data") .. "/rplugin.vim"
    assert(vim.wait(30000, function()
      return vim.fn.filereadable(manifest) == 1 and vim.fn.exists(":MoltenInit") == 2
    end, 100), "The relocated Notebook remote-plugin registration failed")
    local kernelspec = runtime.directory() .. "/share/jupyter/kernels/" .. runtime.default_kernel .. "/kernel.json"
    local kernel = vim.json.decode(table.concat(vim.fn.readfile(kernelspec), "\n"))
    assert(vim.fs.normalize(kernel.argv[1]) == vim.fs.normalize(runtime.python()), "Kernel metadata retained a builder path")
    assert(vim.fn.py3eval("40 + 2") == 42, "The packaged Python provider did not respond")
    print("Relocated full config, Python host and Notebook metadata passed; no kernel was started")
  end, debug.traceback)
  if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") else vim.cmd("qa!") end
end
vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function() vim.defer_fn(finish, 100) end })
'@ | Set-Content -LiteralPath $qaScript -Encoding UTF8
    $qaEnvironment['GLOW_NATIVE_QA_SCRIPT'] = $qaScript
    try { Invoke-Bounded (Join-Path $relocated 'bin\nvim.exe') @('--headless', '-i', 'NONE', '-c', 'lua dofile(vim.env.GLOW_NATIVE_QA_SCRIPT)') $qaEnvironment $qaRoot 120 'relocated-full-profile' }
    catch { $functionalFailures.Add('relocated-full-profile'); Write-Warning $_ }
    $kernelSpec = Join-Path $profile 'data\nvim-data\glow-notebook-venv\share\jupyter\kernels\glow-python\kernel.json'
    try { Invoke-Bounded $python @((Join-Path $repoRoot 'tests\windows_notebook_kernel.py'), '--kernelspec', $kernelSpec, '--expected-python', $python, '--timeout', '60') $qaEnvironment $qaRoot 90 'relocated-notebook-kernel' }
    catch { $functionalFailures.Add('relocated-notebook-kernel'); Write-Warning $_ }
    if ($functionalFailures.Count -gt 0) {
        $functionalFailures.ToArray() | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'functional-failures.json') -Encoding UTF8
        throw ('Functional checks failed; the installer was not packaged: ' + ($functionalFailures -join ', '))
    }

    Invoke-Checked $isccPath @(('/DStageDir=' + $stage), ('/DOutputDir=' + $output), ('/DAppVersion=' + $Version), (Join-Path $PSScriptRoot 'installer.iss'))
    $installer = Join-Path $output ('Neovide-Glow-' + $Version + '-Windows-x64-Setup.exe')
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'ISCC did not create the offline installer.' }
    $installerSmoke = 'not_requested'
    if ($InstallerSmokeTest) {
        # Keep the successful installation below Inno 6's complete-payload path
        # limit; Unicode/space/apostrophe handling is independent of root length.
        $installerQaRoot = Join-Path ([IO.Path]::GetPathRoot($work)) ('GlowInstallerQA-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        if (Test-Path -LiteralPath $installerQaRoot) { throw 'The installer QA path already exists and was preserved.' }
        $installed = Join-Path $installerQaRoot "Installed 中文 O'Connor\Glow"
        $overlongInstalled = Join-Path $installerQaRoot ('Too-long-' + ('x' * 120))
        $overlongLog = Join-Path $logs 'installer-overlong-path.log'
        Invoke-Bounded $installer @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR=' + $overlongInstalled), ('/LOG=' + $overlongLog)) @{} $work 60 'installer-overlong-path' @(1, 7)
        if ((Test-Path -LiteralPath $overlongInstalled) -or
            -not [IO.File]::ReadAllText($overlongLog).Contains('Glow path preflight: rejected before installation')) {
            throw 'The installer did not safely refuse the overlong destination before writing its payload.'
        }
        $fixture = Join-Path $profile 'config\nvim\ci-preserved-user-file.txt'
        [IO.File]::WriteAllText($fixture, 'This user-profile fixture must survive uninstall.')
        $fixtureHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
        Invoke-Bounded $installer @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR=' + $installed), ('/LOG=' + (Join-Path $logs 'installer.log'))) @{} $work 300 'installer-smoke'
        Invoke-Bounded (Join-Path $installed 'Glow.exe') @('--launcher-check') @{} $work 60 'installed-launcher-check'
        Invoke-Bounded (Join-Path $installed 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG=' + (Join-Path $logs 'uninstaller.log'))) @{} $work 180 'uninstaller-smoke'
        if (-not (Test-Path -LiteralPath $fixture -PathType Leaf) -or (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -cne $fixtureHash) {
            throw 'The user-profile preservation check failed after uninstall.'
        }
        if (Test-Path -LiteralPath (Join-Path $installed 'Glow.exe')) { throw 'The uninstaller retained the installed application executable.' }
        if (Test-Path -LiteralPath $installerQaRoot) { Remove-Item -LiteralPath $installerQaRoot -Recurse -Force }
        $installerSmoke = 'passed_user_profile_preserved'
    }
    $checksum = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    ($checksum + '  ' + [IO.Path]::GetFileName($installer)) | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
    $receipt = [ordered]@{
        schema_version = 1; stack_id = $StackId; installer_version = $Version;
        neovide_commit = $sourceCommit; rust_toolchain = $toolchain;
        windows_asset_lock_sha256 = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant();
        approved_icon_sha256 = (Get-FileHash -LiteralPath $icon -Algorithm SHA256).Hash.ToLowerInvariant();
        frontend_sha256 = (Get-FileHash -LiteralPath $frontend -Algorithm SHA256).Hash.ToLowerInvariant();
        installer_sha256 = $checksum; crt_files = $crt;
        windows_rust_unit_tests = 'passed_release_locked_x86_64_pc_windows_msvc';
        windows_rust_unit_tests_evidence = $rustEvidence; dependency_checkpoint_reused = $reusedDependencies;
        relocation = 'passed_spaces_unicode_apostrophe_packaged_path_only'; native_health = 'passed';
        isolated_config = 'passed'; python_host_and_notebook_metadata = 'passed';
        notebook_kernel_execution = 'passed_bundled_python_42_kernel_stopped';
        installer_smoke = $installerSmoke; real_windows_gui_acceptance = 'pending';
        signed = $false; published = $false
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'build-receipt.json') -Encoding UTF8
    Copy-Item -LiteralPath $lockPath -Destination (Join-Path $output 'assets.lock.json')
    Copy-Item -LiteralPath (Join-Path $work 'records') -Destination (Join-Path $output 'records') -Recurse
    Write-Host ('Built and checked offline installer: ' + $installer)
    Write-Host 'The artifact is unsigned and unpublished; real GPU/GUI acceptance remains separate.'
}
finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    if ($transcribing) { Stop-Transcript | Out-Null }
}
