# Native Windows installers

## 安装与第一次使用

1. 在 Windows「设置 → 系统 → 系统信息」查看系统类型。x64 电脑选 x64；ARM64 电脑选 ARM64 安装包。当前公开预览的两架构安装、引导和卸载检查均在 Parallels 的 Windows 11 ARM64 中完成；x64 使用兼容运行，物理 x64 电脑仍待验收。编辑器渲染、剪贴板及完整可选依赖安装属于另行验收范围。ARM64 前端快照不是完整安装包，不要只复制 EXE。
2. 安装器包含编辑器、Neovim、固定插件、字体和 Matrix。安装到自己的账户即可；现有离线版使用独立目录，不覆盖它。不要把版本号或旧包大小当作本次下载量，实际 EXE 大小以该包收据为准。
3. 选择 Notebook / Python、LaTeX / Chinese PDF 后，图形引导先检查已有工具，展示复用位置、已知下载量及仍需由 pip、TeX 或 WebView2 决定的下载量。点击 **Install selected** 才开始安装。基础功能包含搜索、文件管理、Git 和内嵌 PDF 运行时；项目编译器、语言服务、AI 登录另行配置。
4. 从开始菜单启动 **Neovide Glow Preview**。若标准 `%USERPROFILE%\.config\nvim` 已有带前置运行时钩子的 Glow 配置，首次启动会明确询问采用它或独立默认配置；采用只读取原文件，保留 Windows 配色和参数。普通 Neovim 配置不会被自动改写。没有兼容配置时使用独立默认配置，并显示实际路径。运行数据、插件和缓存保留在该版本自己的 profile。
5. 打开普通文件开始编辑；依赖完成后再打开 `.ipynb` 或 `.tex`。选择 **Finish later** 后，仍可从开始菜单 **Neovide Glow Preview Setup** 或编辑器 `:GlowDependencies` 继续检查、安装或修复。依赖改变后重新打开 Glow 才使用新的选择。

**下载量与磁盘占用：** 安装器文件、缺失依赖下载、安装后的运行环境是三种不同大小。已校验的下载缓存从计划中扣除；Python 包、TeX 宏包和 WebView2 Runtime 大小不能预先准确相加。基础下载锁目前采用 x64 工具；缺少可复用 Python 时使用 CPython 3.12 x64，ARM64 本机已有的完整 CPython 3.14 环境可复用。引导不会把这些工具标成全原生 ARM64。

**出错后继续：** 先在引导中点击 **Open logs** 查看失败阶段，再用 **Check again** 检查已完成的工作，确认计划后点击 **Install selected**。安装中断保留属于本安装器的 `.part` 下载和环境；有效缓存经 SHA256 核验后复用。提示缓存损坏时，把错误中明确指出的那个文件移到别处，再重试；不要删除整个用户数据目录。探测超时或状态未知时先检查日志，不把未知环境判成缺失并覆盖。也可先退出，稍后从 Setup 快捷方式继续。

**升级和卸载：** 新 stack 的默认配置不会覆盖旧配置；每次采用外部配置都需要首次明确选择。选择保存在该 profile 的 `.glow-config.json`，后续若原配置消失或前置钩子不再兼容，会显示错误并保留文件。需要重新选择时，先关闭自己要调整的 Glow 会话，把该选择文件另存后移走，下次启动重新选择。卸载只移除应用和自己的快捷方式，保留用户配置、profile、共享字体、Python / TeX 环境和依赖选择。

## 中英文引导

双架构 `2026.10.23.5` 已联合发布，均包含简体中文与英文引导，并在 Parallels 的 Windows 11 ARM64 中各完成14项安装／引导检查；x64 使用兼容运行，ARM64 使用匹配架构载荷。物理 x64 和完整可选依赖联网安装仍待验证，不同架构的验收不能混用。

`2026.10.23.6` 两架构安装器已在本地交付，补上 PDF 获得焦点后按 `q` 关闭的处理，沿用 `.5` 冻结安装逻辑与配置。两架构真实按键已在 PD＋OpenGL 验证；ARM64 完成隔离安装及配置保留检查，x64 按用户要求取消新安装循环。后续最高压缩重封仅核对来源、版本与导出完整性，没有新增功能／安装验收，也尚未发布。

`2026.10.23.4` 安装器源码补齐启动器、安装程序、桌面／开始菜单快捷方式和初始设置窗口的 Glow 图标。依赖引导在创建窗口前启用系统 DPI 感知，使用 96 DPI 布局基准，避免高缩放下被 Windows 以位图拉伸；这不代表跨不同缩放显示器移动时的动态 DPI 适配。192 DPI（200%）的主窗口及停止确认窗口已检查字体尺寸和控件边界，96／144 DPI 与跨显示器移动未实测。实际发布版本以发行页为准。

`2026.10.23.5` 采用 `c174ea3` 前端修正 Windows D3D 与原生 PDF 子窗口的层级，避免编辑器背景盖暗页面；依赖安装每完成一个已验证阶段就保存选择，后续 TeX 等步骤失败不再丢失已成功的 Notebook／Python 选择。安装依赖后需重新打开 Glow，使新选择在下次启动生效。系统 PowerShell 的 `python3` 命令与 Glow 所选的私有 Python 是独立入口，Notebook 可直接选择 `glow-python`。实际发布资产以发行页为准。

安装器根据 Windows 显示语言选择默认语言，也可在开始安装时选择 **简体中文** 或 **English**。所选语言只记录在该应用目录的 `glow-ui-language.txt`；后续依赖引导与首次启动提示沿用它，不改系统语言或 Neovim 用户配置。没有语言记录时，中文 Windows 使用简体中文，其余系统使用英文。

中文流程依次为：选择安装目录 → 选择功能 → 检查已有工具及下载计划 → **安装所选依赖** 或 **稍后完成** → 首次启动选择已有配置或独立默认配置。保留稳定的开始菜单 **Setup** 入口；中文错误说明提示恢复步骤，工具原始日志、路径和技术错误保留原文，便于排查。

x64 `2026.10.23.3` 同时修正 LaTeX 的查看器依赖：默认使用内嵌 WebView2，不再随 LaTeX 自动安装 SumatraPDF；后者仅在明确选择 `-InstallTool pdf` 时作为可选外部查看器安装。已有 SumatraPDF 不会被删除。此前英文安装器仍有旧的自动选择逻辑。

TinyTeX 下载完成后，x64 `2026.10.23.3` 引导会继续显示解压、联网更新、联网检查和中文编译等实际阶段；下载进度满格只表示该文件传输完成，不再一直占用后续安装的状态显示。

LaTeX 的“TeX 下载源”可选自动、清华大学、中国科大或 Illinois。自动模式在中文 Windows 优先尝试国内镜像；安装前对每个候选进行最多15秒的元数据连接检查，选定后本次安装始终使用同一个源。手动选择只检查该源，失败后可回到引导另选。只读检测阶段不联网测试镜像，也不修改系统网络设置、已有 TeX 的全局软件源或签名验证规则。命令行入口可用 `-TeXMirror auto|tuna|ustc|illinois`。

**TinyTeX 自更新检查超时：** `verify-self-update-complete` 会联网读取 TeX 仓库的更新清单，当前时限为180秒；到时停止不代表下载的安装包损坏。`progress.log` 仅记录阶段，具体输出在本次运行目录的 `tex\install\logs\verify-self-update-complete.log`，命令状态在 `tex\install\receipt.json`。先查看对应阶段日志，不需要重装整个 Glow 或删除 TinyTeX；保留带拥有标记的目录，后续设置可以复用缓存并续接该目录，但仍须通过完整安装与编译检查。

## 安装流程与维护边界

| 阶段 | 实际入口与行为 | 失败／恢复边界 |
| --- | --- | --- |
| 架构与封包 | `build-core.ps1 -Architecture x64\|arm64` / `core-package.py --architecture` 贯通目标检查；保留 Neovim、相邻 DLL 和原生插件 | 默认 x64；ARM64 须使用独立密封的匹配 Neovim、CRT DLL、插件和解析库；不能替换一个 EXE 后沿用 x64 包结论 |
| 安装目录 | `installer.iss` 检查路径长度、已有离线版身份 | 写入前拒绝冲突，保留已有程序与配置 |
| 功能与本机计划 | `Glow.exe --setup` → `Setup-Wizard.ps1` → `Setup-Dependencies.ps1 -PlanOnly -Json` | 检测不写依赖目录／选择；变更功能后须重新检查计划 |
| 下载与补齐 | 用户点击安装后才传入明确功能开关；图形进度来自状态文件 | 分阶段日志、SHA 校验、拥有标记、续传；未知环境与非自有目录保护 |
| 第一次启动 | launcher 选择兼容 Windows 配置或私有默认，保留 `NEOVIDE_GLOW_INIT` | 不覆盖任何已有配置；取消可下次再选，丢失配置明确报错 |
| 后续修复 | 开始菜单 Setup 或 `:GlowDependencies` 再次打开图形引导 | 不必重新安装编辑器，完成后重开 Glow |
| 卸载 | Inno 仅撤销应用文件、应用快捷方式 | profile／用户配置／依赖环境／选择／共享字体保留 |

The preferred delivery is now a **core installer plus system dependencies**.
The former offline pipeline below remains available explicitly; existing frozen
releases and their assets are unchanged. Bilingual x64 and ARM64
`2026.10.23.5` installers are published as
[`glow-windows-core-20261024-preview1`](https://github.com/Ysrae1/neovide/releases/tag/glow-windows-core-20261024-preview1).
Each passed 14 actual installation/onboarding checks on Windows 11 ARM64 under
Parallels; x64 used emulation. Both local `.6` installers retain that frozen
installation logic and update the frontend to `ac0fe0d` for focused-PDF `q`
closing. Their later maximum-compression repack checked provenance, version and
export integrity only, without repeating functional or installation acceptance.
The `.6` installers have not been published.

Do not infer download sizes from older candidates. Physical x64 hardware,
complete optional dependency downloads, clipboard behavior and external Copilot
runtime execution remain separate acceptance work. The frozen
`glow-stack-20261023-gm1` Windows directory is a configuration/frontend snapshot,
not an independently installable distribution: its receipt explicitly records
`frontend_dependencies_copied=false`.

## Core installer and reusable dependencies

```powershell
./portable/windows/build-core.ps1 -SourceStage C:\VerifiedOfflineStage `
  -WorkRoot C:\FreshGlowCoreBuild -Version 2026.10.21.1 `
  -StackId glow-windows-core-20261021-preview1
```

A separately prepared, sealed ARM64 dependency stage can use the same core entry:

```powershell
./portable/windows/build-core.ps1 -SourceStage C:\VerifiedArm64Stage `
  -WorkRoot C:\FreshGlowArm64Build -Version 2026.10.23.2 `
  -StackId glow-windows-core-arm64-20261023-preview1 -Architecture arm64
```

This maintainer interface requires independently verified inputs; the accepted
candidate does not validate arbitrary stages. The legacy offline stage producer
still defaults to x64. An ARM64 stage must declare
`architecture: "arm64"` (or `"aarch64"`) in its checksum-sealed `bundle.json`;
missing architecture is accepted only as legacy x64. Both executables, native
plugins/parsers and app-local CRT must pass the ARM64 gate. Changing metadata or
replacing only the frontend does not convert an x64 stage. CRT copied from a
test computer's System32 is diagnostic input, not a redistribution source.
ARM64 uses a separate application identity, `Neovide Glow Core ARM64` directory,
`Neovide Glow Preview ARM64` shortcuts, and a stack ID containing a separate
`arm64` component. A custom directory belonging to the other architecture is
rejected before extraction. Existing x64 names and identity are preserved.

The ARM64 launcher is IL-only AnyCPU with an embedded architecture manifest.
The ARM64 installer requires Windows 11 22H2 (build 22621) or later, where .NET
Framework 4.8.1 is included; the x64 installer's existing minimum is unchanged.
Native ARM64 launcher execution requires Windows 11 24H2+ and .NET Framework
4.8.1; earlier Windows 11 versions can use x64 emulation for this helper. This
does not change the native ARM64 frontend/plugin requirement. See Microsoft's
[architecture manifest contract](https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests#supportedarchitectures).
The bundled Framework baseline follows Microsoft's
[Windows installation/version table](https://learn.microsoft.com/en-us/dotnet/framework/install/on-windows-10).
The AnyCPU launcher compiled on Windows with its architecture manifest present;
five launcher fixture checks passed. A same-manifest AnyCPU fixture reported
native ARM64 execution on the test VM; Inno compilation and the 11 installer
checks also passed. This does not establish native editor GUI acceptance.

`prepare-native-stage.py --source <sealed-base> --destination <fresh-stage>
--inputs <explicit-inputs.json> --report <fresh-report.json>` prepares that input.
The inputs pin the base seal, target architecture, separate stack ID and every
overlay file's source, SHA256 and origin label. `replace_prefixes` explicitly
removes obsolete platform trees or development fixtures. `sealed_external_files`
can preserve hash-bound Copilot Node modules and helper executables for its
separate Node process; they are not Neovim ABI acceptance. All editor DLLs,
parsers, Matrix and target overlays remain architecture checked. Only a passing
stage receives a new seal; the base and failed attempts are preserved.

The tested ARM64 input uses matching files from the official VC Redist tree.
Its x64-only `vcruntime140_1.dll` and upstream x64 `win32yank.exe` are omitted;
no ARM64 input imports the former. The core retains ARM64 `tee.exe` and `xxd.exe`.
Clipboard interaction remains a GUI acceptance item.

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

An override requires an explicit expected digest and a PE32+ executable matching
the selected architecture;
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
`build-core.ps1` runs `verify-native.py --architecture <selected target>` before packaging:
both main executables and declared native DLLs/parsers must match the target,
and normal/delayed MSVC CRT imports must resolve to matching app-local DLLs.
The native validator handles x64 and ARM64 independently; having an ARM64 build
entry does not establish that a complete ARM64 source stage or installer exists.
Verified parser additions absent from an older stage can be supplied with
`-ParserSupplement C:\Build\parser-supplement.json`. The manifest has
`schema_version=1`, the matching `plugin_lock_sha256`, and a `files` array of
`path`, absolute `source` and `sha256` entries. Only parser `.so` files under
`profile/data/nvim/lazy/nvim-treesitter/parser` are accepted; they enter the new
seal and native architecture check. Existing source stages are never changed.
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
Add `-CheckOnboarding` to verify the installed `Glow.exe --setup` window with
real local detection, visible download-plan text and the deferred exit code;
this still performs no dependency installation. `tests/windows_setup_wizard.ps1`
uses a local synthetic backend to exercise feature changes, confirmation,
deferral, failure/retry and inconclusive detection through the actual GUI.
`tests/windows_dependencies_plan.ps1` checks plan/cache/status behavior without
network access; `tests/windows_launcher_config.cs` checks first-start config
choices and preservation using fixture files.

The normal installer opens graphical dependency setup after copying the editor.
A feature page selects Notebook/Python and LaTeX; base tools are included in
the plan. It first shows local detection and known/variable download sizes;
the user confirms installation or finishes later. Compatible tools are reused
and phase/download progress stays in the setup window. Deferring does not mark
optional dependencies as accepted.
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

`:GlowDependencies` opens the graphical setup window, whose first phase is
read-only detection. A plain `Setup-Dependencies.ps1` invocation remains
read-only; `-PlanOnly -InstallBase -InstallNotebook -InstallLatex -Json` returns
a structured plan without creating dependency/selection roots. `-ReportPath`
can save an explicit UTF-8 report in a caller-owned directory; the GUI consumes
this atomic report instead of waiting indefinitely for inherited output handles.
Explicit maintainer/repair actions are also available:

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
57 parser DLLs (including Java), 24 language tools, fonts, and the Windows port of Glow Matrix.
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
