# Native Windows installers

The preferred delivery is now a **core installer plus system dependencies**.
The former offline pipeline below remains available explicitly; existing frozen
releases and their assets are unchanged. The new core entry is implemented but
has not yet passed a complete Windows GUI/install acceptance run or produced a
published release. Do not infer a final download size from the previous 825 MB
offline candidate.

## Core installer and reusable dependencies

```powershell
./portable/windows/build-core.ps1 -SourceStage C:\VerifiedOfflineStage `
  -WorkRoot C:\FreshGlowCoreBuild -Version 2026.10.21.1 `
  -StackId glow-windows-core-20261021-preview1
```

A later tested frontend can be supplied independently of the sealed dependency
stage, for example after adding a native PDF backend:

```powershell
./portable/windows/build-core.ps1 -SourceStage C:\VerifiedOfflineStage `
  -WorkRoot C:\FreshGlowCoreBuild -Version 2026.10.21.2 `
  -StackId glow-windows-core-20261021-preview2 `
  -Frontend C:\VerifiedFrontend\neovide.exe -FrontendSha256 <expected-build-sha256> `
  -FrontendSourceState dirty -FrontendSourceCommit <source-base-commit> `
  -FrontendSourceFingerprint <source-tree-sha256>
```

An override requires an explicit expected digest and an x64 PE32+ executable;
its copied bytes are checked again. SHA256, size and source state are recorded
in `bundle.json` and the build report, with optional base commit/source-tree
fingerprint. A dirty or unknown new build does not inherit the old stage's
frozen `neovide_commit` claim. Clean provenance requires a source commit. The
source stage and the original EXE remain unchanged.

This maintainer path reads an existing checksum-sealed dependency stage, verifies
every retained input, and creates a separate output. It compiles only the small
launcher; it does not rebuild or alter the old dependency stage. Current config
defaults are refreshed only if their plugin lock matches the stage's fixed
native modules. A different lock requires a new native build. Core uses a new
stack ID and therefore does not adopt or overwrite existing user profiles.
It also uses a separate installation identity and the default directory
`%LOCALAPPDATA%\Programs\Neovide Glow Core`. An offline installation directory
is rejected rather than deleting its runtimes or silently retaining large old
files/CLI shims. The app name remains Neovide Glow; its parallel preview shortcut
is `Neovide Glow Preview`. The old app can
be removed separately after the core package has passed acceptance.

Core retains native Neovide, Neovim and adjacent DLLs/runtime, fixed plugins and
their native DLLs/parsers, fonts/licenses, config, and Matrix. It excludes the
private Python, Node, Java, bundled Git/CLI tools, Mason package installations
and Codex runtime. It never includes MSVC/Rust or other compiler installations.
Optional functionality is unavailable until its dependencies are configured;
installing core alone does not establish Notebook, LaTeX or all language-server
acceptance.
Core defaults to `frame = "none"`, matching the Windows desktop entry; the
frozen stage's other window/font settings and the user's existing profiles are preserved.
The current reviewed Rust/Skia notice generator adds `licenses/THIRD-PARTY-NOTICES.txt`
and its source index to the sealed core payload, covering frontend dependencies
added after the old offline stage. Notice generation is offline.
Each build writes `core-size-report.json` with actual retained/omitted component
bytes, every plugin's total/native/download-cache bytes, and the 20 largest
files. Required plugin assets are retained until their runtime role is verified;
there is no blanket deletion of vendor or node_modules directories. This report
is the basis for further size changes, not an assumed final EXE size.
`receipt.json` binds the finished EXE, stage seal, launcher and frontend hashes.
It records installation/GUI acceptance as pending. On an isolated native Windows
user task, `tests/windows_core_installer.ps1 -BuildReceipt C:\Build\receipt.json
-WorkRoot C:\FreshCoreAcceptance` verifies the actual EXE at default and
Unicode/space/apostrophe paths, rejects an offline directory before extraction,
checks installed checksums and runtime omissions, and uninstalls while preserving
the versioned profile and the existing dependency selection. This test skips
dependency installation; Notebook, LaTeX and native GUI acceptance are separate.

The normal installer now detects and installs missing dependencies before it
finishes. A feature page selects Notebook/Python and LaTeX; base tools are
required. It first shows the local detection results and approximate download
sizes, reuses compatible existing tools, and displays phase/download progress.
Silent packaging smoke tests skip dependency installation unless explicitly
passed `/INSTALLDEPS=1`.

Base tools are ripgrep, fd, Yazi, fzf, Git (including the MIME helper), and
Evergreen WebView2. Working existing CLI versions are reused at minimum
rg 14, fd 10, Yazi 26.5.6, fzf 0.65 and Git 2.30. A missing or older tool is
preserved; a fixed official release is installed alongside it under the shared
user dependency directory. `system-assets.lock.json` pins official URLs, byte
sizes and SHA256. ZIP entries are checked for traversal/links before extraction.
Downloads resume only inside an owned cache and are hashed before execution;
tampered bytes and unknown existing directories are preserved and rejected.

Notebook first reuses a complete CPython 3.12 x64 environment, checking imports
and both Jupytext/latex2text commands. It detects PATH, standard Python
registrations, common Conda locations, registered Jupyter kernels and the prior selection. Kernel discovery reads only an existing absolute Python executable path; kernel arguments are never executed. If needed it
installs the official PSF-signed, hash-locked CPython 3.12.10 per user without
PATH/association/launcher changes. This is the last traditional Windows installer
for the 3.12 series, not a claim to contain later source-only security patches.
Package installation always uses a separate
owned `notebook-v1` venv, never an existing Anaconda/base environment. An owned
partial venv can be resumed. Python packages are version-pinned; the text
converter additionally uses its existing hash lock. Actual enabled capabilities
still require their own disk space; shrinking the editor installer does not
remove that requirement. See [Python installer options](https://docs.python.org/3.12/using/windows.html#installing-without-ui)
and [venv](https://docs.python.org/3/library/venv.html).

LaTeX first compiles a Chinese fixture with existing XeLaTeX/latexmk/SyncTeX.
If that fails, it preserves that distribution and prepares a separate owned
TinyTeX from its official monthly release digest. TeX repository signatures
remain mandatory, and its own GPG keyring is used. Common Chinese/math packages,
PDF and SyncTeX are checked before selection. TeX installation roots must be
ASCII without spaces, an upstream TeX Live limitation; Chinese document paths
are tested separately. No system/user PATH or file association is rewritten.
See [TinyTeX](https://yihui.org/tinytex/) and [TeX Live's Windows path limits](https://tug.org/texlive/windows.html#nonascii).

WebView2 detection reads Microsoft's documented Evergreen Runtime `pv`
registration, requiring a nonzero valid version. It does not use Edge browser
files as evidence. Missing Runtime uses the fixed official Microsoft
bootstrapper, requiring both the recorded SHA and a valid Microsoft
Authenticode signature. Its normal installation UI remains visible and its
Runtime registration is rechecked; an inaccessible registry is reported unknown
and is not blindly replaced. Existing Evergreen Runtime is shared. See
[Microsoft's deployment contract](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution).

`:GlowDependencies` and a plain script invocation remain read-only detection
entries. Explicit maintainer/repair actions are also available:

```powershell
./Setup-Dependencies.ps1 -InstallBase -InstallNotebook -InstallLatex
./Setup-Dependencies.ps1 -SelectPython -Python C:\ExistingEnv\python.exe
./Setup-Dependencies.ps1 -InstallTool powershell,node,pdf
```

Only additional explicitly requested PowerShell/Node/external PDF packages use
exact allowlisted WinGet IDs. They keep interactive license/elevation prompts;
there is no forced upgrade, automatic agreement acceptance or reboot. An
external PDF reader does not establish embedded PDF acceptance. Failures write
bounded per-phase logs/receipts, preserve owned partial output and stop setup
instead of claiming the feature is installed. Re-running setup resumes it.

Selections are username-local absolute executable/tool-directory paths in
`%LOCALAPPDATA%\NeovideGlow\dependencies\selected.json`, atomically written with
the previous selection backed up. No account tokens or kernels from another
computer are copied. Launching core reads this selection and changes only its
child environment. Removing a selected interpreter disables Notebook without
turning it into an editor launch prerequisite. Uninstalling the editor preserves
system tools, dependency environments and user profiles.
Later setup runs retain still-existing selected tool directories, including a
separate TinyTeX installation, and resume only TeX roots bearing this installer's
ownership marker. The TeX worker validates that marker against its asset lock.

`python3 tests/windows_core_package.py` tests retention/omission, source
immutability/checksums, config-lock compatibility, links/traversal and profile
separation with synthetic files. `tests/windows_launcher_core.cs` exercises the
actual launcher validator. `tests/windows_dependencies_helpers.ps1` checks owned-directory resume, archive containment and cached digest rejection with synthetic local files. Native Windows install/GUI/Notebook/TeX acceptance
is still required before publishing a core package.
`tests/windows_dependencies_process.ps1` checks native command success/failure,
timeout logs and process receipts, and ensures an uncertain existing TeX check
stops before any replacement download. A timeout preserves the current environment;
it is not treated as proof that a new TeX distribution is required.

## Optional full offline package

The legacy release-worker pipeline creates a per-user `Neovide-Glow-…-Setup.exe`.
The installed application uses native Windows Neovide and Neovim. It does not
install WSL, download dependencies, or compile code on the user's computer.
The existing `glow-stack-20261020-gm1` Mac/WSL release remains unchanged.

The package includes its own fixed Neovim, Node, Python/Notebook dependencies,
Java runtime, Git/Yazi/search tools, plugin sources and prebuilt native modules,
56 parser DLLs, 24 language tools, fonts, and the Windows port of Glow Matrix.
AI authentication is performed by the user. A project-specific compiler,
complete TeX distribution, and macOS-only media frameworks are outside the
editor's bundled runtime.

## Build on the release worker

Use the `Windows offline installer` workflow on `glow-preview`, or run this in
a disposable Windows x64 MSVC developer shell with the declared build tools:

```powershell
./portable/windows/build.ps1 -WorkRoot C:\GlowBuild -Version 2026.10.20.1
```

`WorkRoot` must be empty. The worker requires Visual Studio 2022 x64 C++ tools,
LLVM/clang-cl, Rust 1.99.1, Python 3.12+, CMake, Ninja, 7-Zip and Inno Setup 6.3+.
Only the worker needs those tools. Official runtime downloads and SHA256 values
are in `assets.lock.json`; `resolve-assets.py` is a maintainer operation for
deliberately refreshing that separate Windows lock.

Build phases are explicit: frontend, runtimes, native modules, language tools,
relocation, then EXE packaging. Missing required components stop the build.
The worker checks the relocated payload with a PATH containing only packaged
tools and Windows system directories. It also installs/uninstalls the resulting
EXE in its disposable account and verifies that user-profile files survive.

The immutable installed payload lives under `%LOCALAPPDATA%\Programs\Neovide Glow`.
First launch copies static defaults to a separate versioned profile under
`%LOCALAPPDATA%\NeovideGlow\profiles`; later launches preserve user changes.
First-run Notebook registration only writes local metadata and starts no kernel.
The installer checks its complete payload's path limit before writing files.
If a destination is too long, choose a shorter folder; user profiles remain
separate from the application and survive uninstall.

The workflow uploads an unsigned build artifact and evidence; it does not
automatically publish a release or claim real Windows GPU/GUI acceptance.
Actual results and remaining acceptance work are recorded in the repository's
canonical `GLOW.md`.

## Parallels development and graphics acceptance

Windows 11 ARM64 in Parallels can build x64 programs and run the installer and
headless checks through Windows emulation. It is a separate graphics target
from a Windows x64 PC. Windows Neovide uses D3D12 by default, while
[Parallels documents DirectX 11.1 support](https://kb.parallels.com/en/129497).
The packaged Glow launcher selects system OpenGL for its child process only
when both BIOS `SystemManufacturer` and `SystemProductName` explicitly identify
Parallels. Other hardware and unavailable BIOS information retain the normal
default. Any inherited `NEOVIDE_OPENGL` value, including `false` or an empty
value, is preserved; command-line arguments pass through unchanged. No system
environment, registry or driver setting is changed.

The current frontend's transparent pixel-format fallback passed a dedicated
Parallels system-OpenGL test with the actual Parallels graphics modules, native
PNG decoding before and after resize, and process cleanup. The ordinary
launcher also passed these checks without an explicit OpenGL argument or
inherited backend environment value; 14 targeted launcher selection cases
passed on Windows. These checks do not establish complete visual layout, input,
physical GPU compatibility or measured frame rate.

A separate, per-application Mesa llvmpipe setup with `--opengl` passed the real
frontend's image, Notebook-image, Yazi and Matrix functional checks. That
software renderer is a local development aid, outside this offline installer;
it does not establish hardware GPU compatibility or performance. Full visual
layout, manual keyboard/mouse and physical Windows GPU acceptance remain separate
checks.
