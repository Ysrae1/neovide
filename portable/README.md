# Neovide Glow 稳定环境安装包

保留自定义 Glow、浅色原生分层图标、Neovim 外观、快捷键和 Avante Codex 侧栏的可迁移快照。支持 Apple Silicon Mac，以及 Windows x64 原生 Neovide 搭配 Ubuntu 24.04 WSL2。

不需要预先安装 Neovim、Yazi 或字母雨程序。安装器会下载并校验清单锁定的 Neovim 与运行库，再安装配置和插件；已有系统 Neovim 也不会被替换。全新电脑仍需先按部署说明准备系统编译工具与启动安装器的 Python；Windows 还需完成 WSL2／Ubuntu 首次设置。

当前源码安装方案已直接附带 FiraCode Nerd Font Mono（Nerd Fonts 3.3.0，六个字重）及 Noto Sans Mono CJK SC（2.004，常规／粗体），来源、SHA256 和许可见 `payload/fonts/`。安装字体不再需要另行下载。Mac 默认 Fira＋系统苹方，Windows／WSL 默认 Fira＋Noto；苹方文件不随包复制。字体仅装入当前用户目录，遇到不同内容的同名文件会停止并保留原文件。Neovide 的默认字体由随包配置指定；终端应用自身的字体仍由终端设置控制。

此改动属于下一版源码方案；已发布的 `glow-stack-20261017-gm2` 文件及校验值保持原样。Windows 字体安装与界面仍待 Windows 实机验收。

先阅读 [部署说明](DEPLOY.md) 和 [冻结版本记录](CHANGELOG.md)。把整个安装包解压到一处，保留 `install.sh`、`install.ps1`、`scripts`、`payload` 和 `manifest.json` 的相对位置。

```sh
# Apple Silicon Mac：只查看计划
bash install.sh --plan
# 安装独立环境
bash install.sh
```

```powershell
# Windows x64：只查看计划
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Plan
# 完成 WSL 首次设置和 Linux 前置依赖后再安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Mac 仍需要打开生成的 DMG，把 Neovide 拖入 Applications。安装器不会代替你拖入，也不会停止正在运行的编辑器。默认使用独立配置；如需从 Finder 直接打开时也采用此配置，完成拖拽后显式运行 `bash install.sh --activate`。

本快照冻结核心下载的 SHA256、68 个插件提交、56 个 Treesitter grammar 和 22 个 Mason 工具的顶层版本（Mac ARM 安装其中支持本平台的 21 项）。Mason 历史安装信息不包含完整传递依赖锁，因此不能保证所有语言工具在任意未来时间均逐字节相同。完整 TeX、浏览器 Markdown 预览与 Yazi 多媒体预览属于可选扩展。

Windows 入口和平台适配已经编写，但必须在 Windows 机器上完成编译和交互验收；不要将 Mac 的检查结果理解为 Windows 已通过。Apple 的 Liquid Glass 分层图标只在 macOS 适用，Windows 使用同一设计的静态浅色图标。

远程固定快照：[glow-stack-20261017-gm2](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261017-gm2)。仓库源码中的 `portable/` 目录也可直接运行入口；Mac DMG 若未放在本地，会从该固定发行版获取并核对 SHA256。各组件保留各自许可证，CMatrix 与 Unimatrix 衍生部分见 `licenses/CMatrix-Unimatrix-GPL3.txt`。
