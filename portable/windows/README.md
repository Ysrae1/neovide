# Native Windows offline installer

This release-worker pipeline creates a per-user `Neovide-Glow-…-Setup.exe`.
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

The workflow uploads an unsigned build artifact and evidence; it does not
automatically publish a release or claim real Windows GPU/GUI acceptance.
Actual results and remaining acceptance work are recorded in the repository's
canonical `GLOW.md`.
