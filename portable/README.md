# Neovide Glow 便携环境安装包

保留自定义 Glow、浅色原生分层图标、Neovim 外观、快捷键和 Avante Codex 侧栏的可迁移快照。本次 `glow-macos-20261021-preview1` 仅交付 Apple Silicon Mac 预览版。Windows x64 搭配 Ubuntu 24.04 WSL2 的既有源码安装说明仍保留；新版 Windows 原生前端和精简安装器尚待验收，Linux 开发暂缓。

不需要预先安装 Neovim、Yazi 或字母雨程序。安装器会下载并校验清单锁定的 Neovim 与运行库，再安装配置和插件；已有系统 Neovim 也不会被替换。全新电脑仍需先按部署说明准备系统编译工具与启动安装器的 Python；Windows 还需完成 WSL2／Ubuntu 首次设置。

当前源码安装方案已直接附带 FiraCode Nerd Font Mono（Nerd Fonts 3.3.0，六个字重）及 Noto Sans Mono CJK SC（2.004，常规／粗体），来源、SHA256 和许可见 `payload/fonts/`。安装字体不再需要另行下载。Mac 默认 Fira＋系统苹方，Windows／WSL 默认 Fira＋Noto；苹方文件不随包复制。字体仅装入当前用户目录，遇到不同内容的同名文件会停止并保留原文件。Neovide 的默认字体由随包配置指定；终端应用自身的字体仍由终端设置控制。

本版标签为 `glow-macos-20261021-preview1`，独立环境标识为 `neovide-glow-20261021-preview1`。Mac App 固定源码 `955e75faf91a518699abc2cc6ad4ac9c240b5671`，配置固定为 `5687116f97156745fae6c4dcfc084e3cadd853ef`。App 使用通用 Apple Silicon CPU 目标编译，最低构建目标为 macOS 11；较旧 macOS 仍未单独验收。App 采用 ad-hoc hardened runtime 签名，未经 Apple 公证。

本次修复原生菜单中英切换、系统窗口菜单、PDF 重复白色工具栏、输入标题刷新与 Mini.ai 中英文提示。通用构建的中文→英文→中文菜单、真实 PDF 画面、页码与缩放已通过；新电脑联网完整部署仍需按清单验收。旧 `glow-stack-20261020-gm1`、`glow-stack-20261019-gm1`、`glow-stack-20261017-gm2` 的标签、文件及校验值保持原样。

先阅读 [部署说明](DEPLOY.md) 和 [冻结版本记录](CHANGELOG.md)。把整个安装包解压到一处，保留 `install.sh`、`install.ps1`、`scripts`、`payload` 和 `manifest.json` 的相对位置。

```sh
# Apple Silicon Mac：只查看计划
bash install.sh --plan
# 安装独立环境
bash install.sh
```

以下保留既有 Windows／WSL2 源码安装入口，不代表本次 Mac 预览包含已验收的 Windows 安装包：

```powershell
# Windows x64：只查看计划
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Plan
# 完成 WSL 首次设置和 Linux 前置依赖后再安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Mac 仍需要打开生成的 DMG，把 Neovide 拖入 Applications。安装器不会代替你拖入，也不会停止正在运行的编辑器。默认使用独立配置；如需从 Finder 直接打开时也采用此配置，完成拖拽后显式运行 `bash install.sh --activate`。

本快照冻结核心下载的 SHA256、70 个插件提交、56 个 Treesitter grammar 和 24 个 Mason 工具的顶层版本（Mac ARM 安装其中支持本平台的工具）。Mason 历史安装信息不包含完整传递依赖锁，Notebook Python 固定包版本但未固定每个发行文件哈希，因此不承诺这些依赖逐字节复现。完整 TeX、浏览器 Markdown 预览与 Yazi 多媒体预览属于可选扩展。

新版 Windows 原生程序已编译通过，实际界面与精简安装器的安装／卸载验收尚未完成；不要将 Mac 的检查结果理解为 Windows 已通过。Apple 的 Liquid Glass 分层图标只在 macOS 适用，Windows 使用同一设计的静态浅色图标。

远程固定快照：[glow-macos-20261021-preview1](https://github.com/Ysrae1/neovide/releases/tag/glow-macos-20261021-preview1)，[Mac DMG](https://github.com/Ysrae1/neovide/releases/download/glow-macos-20261021-preview1/Neovide-Glow-macOS-arm64.dmg)。仓库源码中的 `portable/` 目录也可直接运行入口；Mac DMG 若未放在本地，会从该固定发行版获取并核对 SHA256。各组件保留各自许可证，CMatrix 与 Unimatrix 衍生部分见 `licenses/CMatrix-Unimatrix-GPL3.txt`。
