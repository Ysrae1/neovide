# Linux 原生 Glow 入口

`portable/scripts/linux-native.py` 为 Linux x86_64／ARM64 准备独立的 Glow GUI 核心，要求 Python 3.10+、Neovim 0.12+ 和可用的 X11／Wayland、OpenGL 驱动。完整 profile 安装另需 Python 3.12+。它不覆盖系统或 `~/.cargo/bin` 中已有的 Neovide，也不修改现有 Neovim 配置。

## 系统准备

Ubuntu／Debian 的构建依赖依据 [Neovide 官方安装说明](https://neovide.dev/installation.html#linux-source)，以下使用通用编译工具，适合 x86_64／ARM64；x86_64 的上游完整列表另含 `gcc-multilib g++-multilib`。

```sh
sudo apt update
sudo apt install python3 python3-venv curl gnupg ca-certificates git \
  build-essential clang ninja-build cmake libssl-dev pkg-config \
  libfreetype6-dev libasound2-dev libexpat1-dev libxcb-composite0-dev \
  libbz2-dev libsndio-dev freeglut3-dev libxmu-dev libxi-dev \
  libfontconfig1-dev libxcursor-dev libxkbcommon-x11-dev
```

通过 [Rustup](https://rustup.rs/) 准备 `rustup`／`cargo`；构建入口使用 `portable/manifest.json` 固定的 Rust 工具链及 `--locked`，不切换系统默认工具链。完整配置安装另需 `libncurses-dev libclang-dev golang-go openjdk-21-jre-headless unzip xz-utils`，以 `portable/install.sh --plan` 的实际结果为准。安装入口不会自动执行 apt。

## 配置与构建

在仓库根目录执行。x86_64 可先安装清单锁定的完整隔离配置；这一步会下载运行库、插件并构建本地依赖：

```sh
glow_profile_root="$HOME/.local/share/neovide-glow/profiles/linux-x86_64"
bash portable/install.sh --plan --root "$glow_profile_root"
bash portable/install.sh --root "$glow_profile_root"
```

ARM64 的原生 GUI 核心可使用已有 Neovim 0.12+；当前冻结的完整依赖清单没有 Linux ARM64 下载项，不能运行上述完整配置安装来补齐 ARM 依赖。使用已准备的兼容配置或传入 `--nvim /absolute/path/to/nvim`。

```sh
glow_native_root="$HOME/.local/share/neovide-glow/native/linux"
python3 portable/scripts/linux-native.py plan --source . --root "$glow_native_root" --profile-root "$glow_profile_root"
python3 portable/scripts/linux-native.py doctor --source . --root "$glow_native_root" --profile-root "$glow_profile_root"
python3 portable/scripts/linux-native.py build --source . --revision HEAD --root "$glow_native_root"
python3 portable/scripts/linux-native.py install --source . --root "$glow_native_root" --profile-root "$glow_profile_root"
"$glow_native_root/bin/neovide-glow"
```

`build` 只归档选定 Git 提交，不带入未提交修改；构建前先提交需要编译的变更。源码位于 `ROOT/source/SHA`，Cargo 输出位于独立的 `ROOT/build/SHA`，不会占用仓库共享的 `target/`。

| 命令 | 作用 |
| --- | --- |
| `plan` | 只读显示选定提交、路径和构建计划。 |
| `doctor` | 检查本机依赖与运行条件；不安装系统包。 |
| `build` | 从提交归档构建固定 Rust 工具链的 Linux 核心。 |
| `install` | 从本任务构建或显式提供的 Linux ELF 准备独立启动器、Linux 配置和回执。 |
| `package` | 输出核心归档；完整 Neovim 配置与依赖留在外部 profile。 |

公共参数：`--source` 指 Git 仓库，`--revision` 默认为 `HEAD`，`--root` 指独立核心目录；`--profile-root` 可选，连接已有 Linux profile 的配置／数据／状态／缓存；`--nvim` 可显式选择兼容 Neovim。安装器生成自己的配置，使用 Linux 可用的窗口 frame 与 Noto 字体回退。

## 预编译核心与打包

已有同架构的 Linux ELF 时，可跳过本地构建；明确核对它来自预期的 Glow 提交：

```sh
python3 portable/scripts/linux-native.py install --source . --root "$glow_native_root" --binary /absolute/path/to/neovide --nvim /absolute/path/to/nvim
python3 portable/scripts/linux-native.py package --source . --root "$glow_native_root" --output /absolute/path/to/glow-linux-core.tar.gz
```

核心包包含二进制、配置、启动器、许可证和回执；它不附带 Neovim、完整插件或 Python 环境。目标机仍需兼容的 Neovim、profile 和系统图形库；不能将该核心包称作全离线环境。

## 平台差异与验收边界

Linux 使用共用的柔光、图片和 Notebook 渲染路径。X11 预览后端通过独立 GTK3 子进程嵌入 WebKitGTK（Web／音视频）及 Poppler／Cairo（PDF、页码、缩放和坐标同步）；不在编辑器事件循环内运行第二套 GTK 循环。子进程只属于当前预览，关闭预览或路由即回收。依赖缺失时不宣告相应预览能力，直接调用仍返回错误。

Ubuntu／Debian 的预览运行依赖可在核对后安装：

```sh
sudo apt install python3-gi python3-cairo python3-gi-cairo gir1.2-gtk-3.0 \
  gir1.2-webkit2-4.1 gir1.2-poppler-0.18 \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
/usr/bin/python3 -I -B src/native_preview/linux_helper.py --probe
```

默认使用系统 `/usr/bin/python3` 的 GI 绑定，避免与 Notebook 虚拟环境冲突；可显式设置 `NEOVIDE_LINUX_PREVIEW_PYTHON`。探测只报告绑定可用性，不证明实际解码或 GUI 已通过。媒体格式仍取决于目标发行版的 GStreamer 解码器。

Gtk.Plug 的嵌入接口限 X11；原生 Wayland 不宣告该能力。Wayland 桌面上可仅对本次启动选择 Xwayland：`env -u WAYLAND_DISPLAY -u WAYLAND_SOCKET "$glow_native_root/bin/neovide-glow"`，前提是已有可用的 `DISPLAY`。macOS 系统玻璃与分层图标也不适用于 Linux。平台接口依据 [GTK XEmbed 文档](https://docs.gtk.org/gtk3/class.Plug.html)。

目前尚未完成 Linux 原生 GUI 验收。定向测试覆盖启动和打包契约、后端协议、坐标与遮挡转换；独立手动工作流 `Linux native preview checks` 用于真实 Linux 编译及隔离 X11 集成检查。安装、构建、Xvfb、headless 或 WSL 命令行检查均不证明真实桌面的字体发现、剪贴板、GPU、窗口焦点与材质效果通过；应在目标 Linux 桌面运行生成的启动器逐项检查。

WSLg 可用于单独记录的 WSL GUI 检查，不能代替原生 Linux 桌面验收。[微软说明](https://learn.microsoft.com/windows/wsl/tutorials/gui-apps)要求 WSL2、兼容 Windows 版本与 GPU 驱动；WSL1 不支持这条 GUI 路径。没有可用显示会话时只做计划、检查、构建或打包，不声称 GUI 已验证。
