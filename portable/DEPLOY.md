# Neovide Glow 部署说明

这套安装包将 Neovide Glow、Neovim 配置、文件选择器、字母雨和 AI 侧栏放进一个独立环境，方便在新电脑上恢复相近的体验。核心软件与插件采用固定版本，日常启动不会自行更新插件或安装语言工具。发行包另附 `SHA256SUMS.txt`，可用于核对收到的 ZIP 或单文件安装器；依赖下载仍由内部清单逐项校验。现有的 Neovim 配置、终端设置和登录信息不会作为安装源复制。

适用范围是 Apple Silicon Mac，以及 Windows x64 原生 Neovide 加 Ubuntu 24.04 WSL2。Windows ARM64、Intel Mac 和原生 Windows Neovim 后端不在本版范围内。不同系统的字体回退、透明材质、GPU 驱动和窗口装饰仍可能有差别。

## 安装包中的文件

| 文件 | 用途 |
| --- | --- |
| `install.sh` | Mac 和 WSL 的共享入口 |
| `install.ps1` | Windows 构建、字体及 WSL 连接入口 |
| `manifest.json` | 固定版本、源码提交、下载地址及 SHA256 |
| `payload/nvim` | 经整理的 Neovim 配置，保留外观、侧栏与快捷键 |
| `payload/plugins.json` | 插件的精确来源、提交和构建方式 |
| `payload/mason.json` | 语言工具顶层版本及固定 registry |
| `payload/patches` | 必须保留的 LuaSnip 和 Treesitter 兼容修复 |
| `payload/Neovide.dmg` | Mac 的 Glow App、分层图标和拖拽安装界面 |
| `scripts` | 安装和版本维护所需代码 |
| `licenses` | Neovide 与图标来源和授权说明 |

请整体解压，不能只单独复制 `install.sh` 或 `install.ps1`。单文件 Mac 安装器已经将这些内容封装在内部，可以整体移动到另一台 Apple Silicon Mac。首次安装需要访问 GitHub、Node.js、Python 包源和 Rust 包源；没有把他人的登录凭据打进安装包。

`*.sh` 表示所有以 `.sh` 结尾的文件。真正执行的文件名是 `install.sh`，不含星号。Windows 对应的入口是 `install.ps1`。

## Apple Silicon Mac

### 准备

使用普通用户终端。需要 Python 3.12 或更新版本、Git、curl、make、C 编译器和 Rustup；完整语言工具还需要 Go 与 Java。首次安装 Xcode Command Line Tools 时，先完成系统弹出的安装步骤：

```sh
xcode-select --install
```

如果使用 Homebrew，请使用 Apple Silicon 的 `/opt/homebrew` 版本；不要为了这个安装包移除其他项目仍在使用的 Intel Homebrew。缺少前置工具时可通过 Homebrew 安装：

```sh
brew install python git pkgconf ncurses rustup go openjdk@21
```

Java 如未出现在 PATH，可在本次终端设置：

```sh
export JAVA_HOME="$(/opt/homebrew/bin/brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
```

应用本体随 DMG 提供，普通部署不需要完整 Xcode 或 Icon Composer。重新构建原生分层图标才需要相应版本的 Xcode 工具链。

### 安装

在解压后的文件夹中执行：

```sh
bash install.sh --plan
bash install.sh
```

默认环境在：

```text
~/.local/share/neovide-glow/stacks/neovide-glow-20261017/
```

下载会核对清单中的 SHA256。安装器把 Neovim、配置、插件、运行库和缓存放进这个版本目录；失败时保留结果并退出，可以在处理具体错误后重跑同一命令。首次源码构建需要联网和一定磁盘空间；构建耗时取决于网络和电脑，不能把仍在编译误判为无响应。

安装完成后：

1. 打开安装器输出的 DMG 路径。
2. 在 DMG 窗口里将 Neovide 拖到 Applications。若已有同名 App，由你决定是否替换；安装器不会代替你操作。
3. 从版本目录里的 `bin/neovide-glow` 启动这套独立环境。这个入口使用专用的配置及 Neovim 路径。
4. 若希望从 Finder、Dock 直接打开 Neovide 时也使用此环境，再运行 `bash install.sh --activate`。它会先备份已有 Neovide 配置，写入指向此版本的路径；不会覆盖原来的 Neovim 配置。

这个社区构建没有 Apple 公证签名。若 macOS 阻止打开，请核实来源后使用系统的“隐私与安全性”允许打开流程；不要关闭全局 Gatekeeper。动态图标材质需要支持该图标格式的 macOS，较旧系统使用内置 ICNS 回退。

### 验证

```sh
bash install.sh --doctor
~/.local/share/neovide-glow/stacks/neovide-glow-20261017/bin/nvim --version
```

再启动 GUI，确认字体完整、Glow 正常、启动字母雨能结束、首页和侧栏正常。打开一个 Lua 或 Python 文件，确认没有启动报错并检查对应 LSP。详细检查项见后面的验收清单。

## Windows x64 与 WSL2

### 准备 WSL

需要支持 WSL2 的 Windows 10 或 Windows 11，启用硬件虚拟化，并准备足够空间进行 Rust 编译。在管理员 PowerShell 安装 Ubuntu：

```powershell
wsl --install -d Ubuntu-24.04 --no-launch
```

按系统提示重启。首次打开 Ubuntu，创建普通 Linux 用户和密码；不要把 root 作为日常默认用户。

在 Ubuntu 终端安装 Linux 前置依赖：

```sh
sudo apt update
sudo apt install -y python3 python3-venv git curl build-essential pkg-config libncurses-dev libssl-dev libclang-dev unzip xz-utils golang-go openjdk-21-jre-headless
```

WSL 中也需要 Rustup；Windows 的 Rust 不代替 Linux 的 Rust。若尚未安装，可从 [Rust 官方安装入口](https://www.rust-lang.org/tools/install) 下载并按提示安装。共享安装器会使用清单指定的 Rust 工具链，不会更换其他项目的默认工具链。

### 安装 Windows 窗口和后端

回到普通 Windows 用户的 PowerShell，在解压文件夹中执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Plan
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`ExecutionPolicy Bypass` 只作用于这次进程，不修改全局执行策略。请在执行前确认脚本来自你信任的安装包。

入口会通过交互式安装器补齐 Windows 的 Git、CMake、LLVM、Ninja、MSVC C++ 构建工具及 Rustup，然后编译固定提交的原生 Glow 程序；Linux 后端由同包的 `install.sh` 安装。遇到重启或 Ubuntu 首次用户设置时会停下给出说明，完成后重跑。

该 Neovide 提交的 `--wsl` 使用 Windows 的默认 WSL 发行版，没有 `--wsl-distro` 参数。若默认不是 Ubuntu-24.04，脚本会要求你明确决定。允许切换时运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -UseDistroAsDefault
```

这个选项会改变 Windows 的默认 WSL 发行版；如果其他工作依赖现有默认值，先记录原值，并在部署后按需恢复。恢复后，这份启动器会提示重新选择正确发行版，不会连接到错误的 Linux 环境。

字体安装到当前 Windows 用户。GUI、配置和启动器在 `%LOCALAPPDATA%\NeovideGlow` 下的版本目录中；启动 `Neovide Glow.cmd`。不要直接改用其他已安装 Neovide 的快捷方式，否则可能启动到另一套配置。

请把 Linux 项目保存在 WSL 自己的文件系统，例如 `~/projects`。大量文件索引、编译和插件安装放在 `/mnt/c` 下可能较慢。

Windows 使用同一 Glow 源码与静态浅色图标，Apple `.icon/Assets.car` 分层材质不会在 Windows 生效。剪贴板、字体显示、透明窗口和 GPU 动画必须在实际 Windows 机器上验收。

## AI 登录和公式

AI 仍使用 Avante 原侧栏与原快捷键，通过固定版本的 Codex ACP 适配器连接。首次使用时在这套环境中启动登录流程，使用自己的 ChatGPT 账号完成浏览器授权，例如在 Mac 或 WSL 终端运行 `~/.local/share/neovide-glow/stacks/neovide-glow-20261017/bin/codex login`；已有宿主电脑的登录不会自动复制到另一台机器。WSL 后端需要在 WSL 里完成登录，Windows 宿主的登录文件不等于 Linux 后端的登录。

不要把 `auth.json`、密钥、会话和账号目录发到 GitHub 或交给其他用户。部署说明可以交给 Codex，账号登录仍由账号本人完成。

Markdown 和 AI 侧栏中的公式转换使用固定 `pylatexenc`。这与完整 LaTeX 编译是两件功能。写作时需要生成 PDF，请额外安装 TeX Live／MacTeX；Mac 可配 Skim，WSL 需要可用的 PDF 查看器或 Windows 打开桥接。文档模板放在 `config/nvim/templates/template_assignment.tex`，也可通过 `NVIM_LATEX_TEMPLATE` 指定；缺失模板不会阻止启动。

## 常用操作与字母雨

- `空格 t f`：FFF 快速找文件；首页 `f` 找文件，`c` 找配置。
- `空格 t a`：保留 Telescope 的全部文件入口，适合查隐藏文件或通常被忽略的文件。
- 其他原有 leader、Ctrl 快捷键及 AI 侧栏入口保留。Command 快捷键只在 Mac 启用；Windows/WSL 使用普通 leader 和 Ctrl 入口。
- Neovide 全屏启动字母雨与首页动画统一使用 C 原生 `cmatrix-uni`，显式选择混合字符集 `-l m`。全屏动画仍为两秒、20ms 刷新；首页为 50ms 刷新。两处均开启 `-a`，每列随机选择不同下落节奏。终端 Neovim 首页继续使用原 CMatrix。原 Unimatrix 仍安装保留，可用于对照。

Unimatrix 默认字符包含半角片假名、数字和符号；`unimatrix -l k` 可单独查看半角片假名。`ｱ` 是一格宽，`ア` 是两格宽，不能只靠切换等宽字体让全角字占一格。原版 CMatrix 2.0 不能仅靠参数完全复刻这套字符与下落细节，故本包保留两个程序，并另带一个修改版 CMatrix 的独立 `--unimatrix` 模式。修改版将纵向长度区间、生成／擦除交替、白头概率、列间距和异步调度公式与原 Python 版对齐；同步／异步各 50 帧受控事件对照一致。可运行 `cmatrix-uni -o -s 98` 对比；`cmatrix-uni -o -s 98 -l k` 为纯半角片假名。它不是把 Python 放在后台运行，也不声称随机序列或所有 Unimatrix 可选字符集逐项完全相同。

修改版同时修复了原 CMatrix 旧式滚动模式的空字符哨兵问题，避免 Neovim 小高度终端里的 `@` 残留。安装器在写入 tools 成功标记前会实际检查 6 行和 12 行终端中的可见内容。

两者的同名参数含义可能不同：Unimatrix 的 `-o` 隐藏状态栏，CMatrix 的 `-o` 是旧式滚动；不要直接照搬参数。不能仅根据语言是 C 或 Python 就给出可靠的性能倍数；刷新间隔、字符数、终端解析和 GPU 重绘都影响最终开销。本机 M2 Pro 的 3 秒单次后台样本中，C/Python 单核用量分别为 2.32%/4.16%（80×24）和 4.14%/7.13%（160×48）。这不包含 Neovim、Neovide 和 GPU，也不是跨机器保证。

## 冻结范围与维护

| 内容 | 本包的固定方式 |
| --- | --- |
| Neovide Glow | 远程完整源码提交及 Mac DMG 校验值 |
| Neovim、Yazi、Node、Python、搜索工具、字体 | 精确发行版本、下载地址和 SHA256 |
| Neovim 插件 | 完整提交、必要本地补丁、原生库版本 |
| Treesitter | 插件提交和 grammar lock，目标机本地编译 |
| Codex ACP | npm package-lock，使用 `npm ci` |
| 公式转换 | pylatexenc 精确版本及发行文件哈希 |
| Mason 工具 | 固定 registry 和顶层版本；历史 receipt 未完整锁住传递依赖 |
| 系统编译器、Homebrew、apt、WinGet | 系统前置条件，不承诺跨系统逐字节一致 |

Mason 清单共有 22 项工具。Mac ARM 跳过旧版 Hadolint 2.12.0：固定 registry 没有这个平台的发行包，因此本包不提供该可选 Dockerfile 检查器；Linux x64 保留该项。Mac 默认安装其余 21 项，不会为绕过错误偷偷升级版本或加入 Intel 运行库。

应用 Python 使用 3.14.6；旧版 Mason Python 工具使用 3.12.2，以匹配原环境并避开旧工具对新解释器的兼容问题。这是隔离运行库，不会修改系统默认 Python。长期维护仍应定期验证后更新受支持版本，冻结不等于永不维护。

日常不要运行无计划的全量更新。需要新功能时建立新快照：拉取 Glow 分支、合并官方提交、保留图标源和 DMG 流程，在新版本目录更新清单并验证，再切换启动入口。当前已验收的目录保留作回退。原本本机的 `neovide-update` 属于源码维护入口，不会因安装此独立快照被自动替换。

`markdown-preview.nvim` 和 Peek 的浏览器资源、完整 TeX、多媒体预览工具属于可选扩展，不以“核心安装成功”宣称它们都已就绪。Yazi 默认保留内建预览和当前主题；需要视频、PDF、压缩包预览时，另行安装 ffmpeg、poppler、7-Zip 等并验收相关类型。

## 失败处理与回退

校验值不符：停止，不要删掉校验逻辑。先确认官方文件是否发生变化、网络是否返回了错误网页；维护者决定是否生成新快照。下载失败可以在恢复网络后重跑，同版缓存会复用。

源码或受管配置已有修改：保留修改，先备份再决定是否使用新目录安装。不要用 `git reset --hard`、删除配置或重新生成锁来掩盖错误。

语言工具安装失败：保留工具名、精确版本和错误输出；按失败阶段重跑，不要临时改成最新版。Mason 的旧传递依赖可能已不再兼容当前源，这是需要新快照验证的真实限制。

默认独立部署的回退方式是继续使用原 App／原 Neovim 入口。若已运行 `--activate`，把安装器记录的旧 Neovide 配置备份恢复到原路径，或改回原启动器。确认不再需要后，再删除对应版本目录；不要删除整个 `~/.config` 或整个 WSL 发行版。

## 部署验收清单

1. `--doctor` 无必需组件缺失；Neovim 版本与清单一致。
2. GUI 能启动，字体图标正常，侧栏与常用快捷键可用。
3. 启动的 cmatrix-uni 全屏动画正常结束，GUI 首页 cmatrix-uni 正常；没有遗留动画进程。
4. FFF 能搜索并打开文件，隐藏文件需求可通过原全部文件入口完成。
5. Lua／Python 文件打开后没有插件启动错误，所需 LSP 能连接；LaTeX／Markdown 公式能转换。
6. AI 侧栏在本人登录后能回应；不要把未登录当作程序启动故障。
7. Mac DMG 仍有拖拽安装布局与浅色图标；Windows 启动器连接到正确的 WSL 发行版。
8. 原配置仍可使用，备份和回退路径明确。

未具备 Windows 机器时，脚本静态检查不能替代 Windows 编译、WSL、字体、剪贴板和 GPU 的实际验收。测试完成后记录平台、安装阶段、通过项和未通过项；不要只写“全部稳定”。

## 本次安装包的实际验证范围

Mac 已在独立目录完成工具安装、68 个固定插件及其原生库构建、56 个语法解析器和本平台 21 个语言工具安装，整体 Doctor 检查通过。插件源码检查使用本机 Git 对象缓存建立干净提交副本；运行库和工具使用清单里的官方发行文件，未复制原电脑的登录或运行状态。

空主题缓存的终端启动与 Neovide 配置分支检查通过；后者是 headless 源码分支检查，不代表打开了新的 GUI 窗口。CMatrix 旧首页模式在 Neovim 的 6 行和 12 行终端中未留下异常分隔列字符。Lua 首文件自然识别为 Lua 且 LuaLS 成功连接，Python／Ruff 与 Texlab 连接和公式转换通过。新开场动画实际使用 cmatrix-uni 混合字符，约两秒后进程、浮窗和缓冲区清理通过。实际 GUI 的外观和账号登录，仍按目标电脑上的验收清单完成。

Windows 入口经官方 PowerShell 运行时解析，语法错误数为 0；本次没有 Windows 真机，原生 Windows 编译、WSL 连接、字体、剪贴板和 GPU 尚未验收。

## 可以直接交给 Codex 的部署指令

把以下指令连同整个安装包提供给目标电脑上的 Codex。这里只授权部署这份固定快照；修改远程仓库、公开上传配置和更新版本需另行确定范围。

```text
请部署当前文件夹中的 Neovide Glow 固定快照。先完整读取 DEPLOY.md、README.md、manifest.json 和对应平台入口，并确认目标系统是否在支持范围内。

先运行只读计划。使用安装包现有版本、完整提交和 SHA256，不把任何下载改成 latest，不重新解析或覆盖锁文件。使用独立的版本目录，不覆盖我的原 Neovim 配置、shellrc、其他 WSL 发行版或已安装 App，不终止正在运行的编辑器。

如果缺少系统前置依赖，列明具体缺项并完成已授权的可逆准备；系统重启、首次 Linux 用户创建和本人账号登录由我完成。Windows 更换默认 WSL 发行版必须明确说明其全局影响，未经我选择不要修改。不要读取、复制或公开账号认证文件。

执行对应平台安装器。Mac 必须保留生成／打开 DMG 后由用户拖入 Applications 的安装步骤；完成拖拽前不要自行替换 /Applications 中的 App。默认先用独立启动器；只有我选择从 Finder 直接接入时才使用 --activate，并保留旧配置备份。

遇到校验失败、源码已有本地修改、依赖不兼容或安装失败，保留现有成果和具体错误，不取消校验、不强制覆盖、不静默换最新版。修复应针对真实失败，不做无关插件升级。

只做一轮与部署范围相称的验收：doctor、Neovim 版本、GUI 启动、原侧栏／快捷键、字母雨、FFF 打开文件、Lua/Python LSP、公式，以及本人登录后的 AI。Windows 还要检查 WSL 归属、字体、剪贴板和 GPU 动画。没有测试到的项目明确标明，不能把静态检查说成运行验收。

交付可启动入口、安装目录、备份／回退方法、已通过项和剩余阻碍。完成必要检查后停止，不追加新功能、可选美化或重复全量检查。
```

## 官方参考

- [Neovide 安装与构建](https://neovide.dev/installation.html)
- [Neovide 命令行参数](https://neovide.dev/command-line-reference.html)
- [Microsoft WSL 安装](https://learn.microsoft.com/windows/wsl/install)
- [Microsoft WSL 基本命令](https://learn.microsoft.com/windows/wsl/basic-commands)
- [Unimatrix 固定源码](https://github.com/will8211/unimatrix/blob/dff519f972103f91384f360f270614184de8aa92/unimatrix.py)
- [CMatrix 2.0 源码](https://github.com/abishekvashok/cmatrix/tree/v2.0)
- [自定义 Neovide Glow 源码](https://github.com/Ysrae1/neovide/tree/glow-preview)
