# Native Windows launcher and offline installer contract

`distribution: "core"` in `bundle.json` selects the new small-package contract
described in [../README.md](../README.md). Omitted distribution or `"offline"`
retains the complete frozen offline contract below. Unknown modes are rejected.
Core still verifies every declared native component and fixed plugin payload;
it does not require private Python/Node runtimes. Its launcher reads only the
explicit per-user `NeovideGlow/dependencies/selected.json` selection for Python,
Jupytext and latex2text, and otherwise starts with Notebook unavailable. A
missing, stale or malformed optional selection does not block the editor.
`runtime/lua/WindowsInit.lua` registers `:GlowDependencies` for the explicit
graphical dependency setup; normal launch never installs anything. The
core package intentionally omits the Python/Codex CLI shims below, so they do
not shadow existing system tools with missing bundled runtimes.

The launcher includes Chinese/English first-start messages and dependency setup.
Inno writes `glow-ui-language.txt` in the application directory with `en` or
`zh-CN`; the launcher reads that optional choice and passes it to the wizard.
Without a valid choice, the Windows UI culture selects Chinese for `zh` and
English otherwise. This does not change Windows or Neovim language settings.
Native message-box button captions remain controlled by Windows. Both published
`2026.10.23.5` installers include this bilingual guide and passed 14 actual
installation/onboarding checks per architecture on Windows 11 ARM64 under
Parallels, with x64 running through emulation. The local `.6` installers reuse
that frozen setup logic; their later compression-only repack adds no functional
or installation acceptance. See `../README.md` and `GLOW.md` for the current
delivery state and remaining platform limits.

These files are build inputs. Neither compiling the launcher nor installing an
EXE alone proves that the complete Windows application has passed acceptance.
The Windows staging pipeline must provide and verify every runtime component
before compiling `installer.iss`; installation and first launch never fetch or
compile dependencies.

The stable, per-user installation directory is
`%LOCALAPPDATA%\Programs\Neovide Glow`. Its prepared stage contains:

```text
Glow.exe
bundle.json
neovide.ico                         optional launcher window icon
bin/neovide.exe
bin/nvim.exe                       with its adjacent upstream DLLs
share/nvim/runtime/                complete upstream Neovim runtime
lib/nvim/                          upstream support files, when supplied
config/neovide.toml
runtime/lua/WindowsInit.lua
runtime/python/python.exe
runtime/python/Lib/site-packages/  preinstalled Windows Python packages
runtime/python/Scripts/            relocatable entry points, if needed
runtime/node/node.exe
tools/<tool>/                      prebuilt Windows tools and support files
fonts/*.ttf, *.otf                 reviewed bundled fonts and their licenses
profile/config/nvim/
profile/config/yazi/
profile/data/nvim/                 pinned plugins and native outputs
```

`bundle.json` uses `schema_version: 1`, a unique release `stack_id`, a nonempty
`native_required` array of relative file paths, and an optional `tool_paths`
array of relative directories. The native list must cover all promised native
modules and parsers; the launcher checks existence, while the staging pipeline
is responsible for architecture, checksums, loadability and full coverage.
Explicit `tool_paths` avoids relying on directory discovery. Without it, the
launcher includes `tools`, each direct child and any child's `bin` directory.

Compile with the existing Windows .NET Framework compiler, using
`/target:winexe /platform:x64 /r:System.Windows.Forms.dll
/r:System.Runtime.Serialization.dll`; the release worker may also supply
`/win32icon:...`. This uses the .NET Framework included in Windows 11, without a
separate .NET SDK installation on the user's computer.

For the core ARM64 entry, `build-core.ps1 -Architecture arm64` instead compiles
IL-only `/platform:anycpu` and embeds `GlowLauncher.manifest`. Windows 11 24H2+
with .NET Framework 4.8.1 can run this helper natively on ARM64; older Windows 11
may run the helper through x64 emulation. The ARM64 installer sets a Windows 11
22H2 minimum, whose built-in Framework is 4.8.1. AnyCPU alone does not promise native
execution. The frontend, Neovim and in-process native modules must still pass
their ARM64 PE checks. The x64 compilation path above is unchanged. This new
launcher compiled on Windows with its architecture manifest present and five
launcher fixture checks passed. A same-manifest AnyCPU fixture reported native
ARM64 execution on the test VM. The ARM64 candidate compiled and passed 11
actual installer/onboarding/uninstall checks; editor rendering, clipboard
interaction and optional dependency installation remain separate acceptance.
See the official [supportedArchitectures contract](https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests#supportedarchitectures).

On first launch, static config and data are copied atomically into
`%LOCALAPPDATA%\NeovideGlow\profiles\<stack_id>`. The source data directory
`nvim` becomes `nvim-data`, as required by native Windows Neovim's standard
paths. Further launches preserve that profile. Installed originals remain
separate from writable config, plugin copies, state and cache. New releases
which change the snapshot need a new `stack_id`. Unrecognized existing profile
directories, source-control state, links and common credential files are not
adopted or overwritten.

The child process receives isolated `XDG_*`, `NVIM_APPNAME=nvim`,
`NEOVIDE_CONFIG`, `NEOVIDE_GLOW_ROOT`, `NEOVIDE_GLOW_INIT` and `GLOW_PYTHON`.
`PATH` prepends packaged tools and the profile's Mason directory, without
changing the Windows user's environment. Python user packages and inherited
`PYTHONHOME`/`PYTHONPATH` are excluded from this child. Jupyter directories and
Matplotlib cache are within the writable profile. The seeded `init.lua` must
load `NEOVIDE_GLOW_INIT` before plugin setup. That runtime hook owns relocation
of Python hosts, kernel metadata and remote-plugin registration; it must not
download, compile, install packages, execute a notebook or start a kernel.

`Glow.exe --launcher-check` only validates installed inputs and returns an exit
code. `Glow.exe --initialize-profile` additionally prepares a fresh profile
without opening Neovide. Normal arguments are forwarded with Windows argv
quoting, and the child exit status is returned. These two launcher-only options
must each be used alone.

Compile the installer with Inno Setup 6.3 or later, passing `StageDir`,
`OutputDir` and `AppVersion` defines. The installer targets Windows 11 x64,
requests no elevation, creates shortcuts and optionally launches the app after
installation. Fonts are registered only for the current user; different
existing files or registry entries are preserved. Shared user fonts and all
profiles are retained on uninstall. No system PATH, file associations, WSL,
compiler, package manager or credentials are installed.

`GlowTool.cs` is compiled once as a console executable and copied into `bin`
under the names `python.exe`, `python3.exe`, `jupytext.exe`, `latex2text.exe`,
`codex.exe` and `codex-acp.exe`. It uses the same argument quoting, returns the
real exit status and retains terminal standard handles and the current working
directory. Python entry points use the packaged interpreter; Jupytext and
latex2text invoke `runtime/tool.py --entry <name>`. Codex entry points read
`runtime/tool-commands.json`, whose root object maps a name to
`{"runtime":"node","script":"<relative packaged JavaScript entry>"}`.
All script paths must resolve inside the installation, and every child uses
only process-local environment changes.

Core installers detect/reuse/install selected dependencies before finishing. The
core launcher consumes `selected.json` tool directories for its child PATH,
independently of whether optional Notebook Python is selected. Existing user
PATH and Conda remain unchanged. A missing selected tool directory is ignored;
setup/repair rechecks actual availability. Details and acceptance limits are in
`../README.md`.
