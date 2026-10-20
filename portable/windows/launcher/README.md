# Native Windows launcher and offline installer contract

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
