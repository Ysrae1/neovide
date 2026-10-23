# 冻结版本记录

## 2026-10-23 · glow-stack-20261023-gm1（发布候选）

保存当前源码、独立 Mac 配置及 portable 默认配置；Windows 用户配置在该系统单独保存，不将用户主题装入发行包。旧标签及既有下载保留。

- 启动顺序集中在 `config/bootstrap.lua`，媒体注册集中在 `config/media/init.lua`；10 个语言内部模块归入 `config/locale/`，公共语言入口和主题／材质重载路径保持稳定。
- 包含 Neo-tree `g/` 路径输入、主题色槽提示文字、Windows 树焦点主题重绘、Mac 开屏和 Notebook 输出去阴影，以及本轮标题、材质、原生插件和 PDF／SyncTeX 修复。
- Mac 发布候选和 Windows x64／ARM64 原生前端分别记录来源和校验。Windows 安装引导将另开对话测试与完善；不将此前基础安装／命令行检查写成新安装器完整验收。
- 当前处于发布准备阶段；实际资产、构建及验证结果以发行页与 `GLOW.md` 为准。

## 2026-10-21 · glow-macos-20261021-preview1

本次独立发布 Apple Silicon Mac 预览，环境标识为 `neovide-glow-20261021-preview1`。保留 `glow-stack-20261020-gm1` 及更早标签、发行文件和校验值。

- Mac App 固定源码 `955e75faf91a518699abc2cc6ad4ac9c240b5671`，配置固定为 `5687116f97156745fae6c4dcfc084e3cadd853ef`；下载地址及 SHA256 见 `manifest.json`。
- 使用通用 Apple Silicon CPU 目标编译 arm64 App，最低构建目标 macOS 11；采用 ad-hoc hardened runtime 签名，未经 Apple 公证。
- 修复原生菜单中英切换与系统窗口菜单，保留动作、快捷键及未保存内容；PDF 移除重复白色工具栏，保留彩色胶囊、翻页与缩放；同步输入标题刷新及 Mini.ai 中英文／内外语义修复。
- 通用发行构建已完成中文→英文→中文菜单往返、真实 PDF 画面、页码、翻页与缩放检查。系统提供方的 Services 子项仍随系统语言；旧 macOS、新电脑联网完整部署、全屏动画及多编辑器焦点往返未单独验收。
- Windows 新原生程序已编译通过，前端实际界面及精简安装器仍待验收；保留 legacy WSL2 安装说明，不将其列为本次交付。Linux 开发按用户决定暂缓。

## 2026-10-20 · glow-stack-20261020-gm1

源码与当前保存的个人配置使用同名冻结标签；保留 2026-10-19 gm1、gm2、配色标签及既有下载。本版继续作为预发布。

- 修复 Noice 外框／留白与内容区材质不一致、WhichKey 设置不生效及页脚重复阴影；各类浮窗独立选择 opaque／editor／custom，保留当前 editor 偏好和 Ayu 颜色。
- Notebook 输出原位展开、横纵滚动、复制与关闭；真实点击 Out[1] 的正文、图片或留白后可从 Cell 2 正确切换并用空格 j o 展开 Out[1]。转换后的 .ipynb 读入与窗口重入保持 Python。
- 合入官方 86227b8 的 macOS 分屏原生滚动条，默认关闭；保留 Glow、Liquid Glass、媒体预览及 Notebook 网格尺寸约定。
- Mac DMG 原生源码 `b8b92bcc8f1e7b974e353e21f34f546dcf66bcac`，配置提交 `22d4852d5f176237b0f76aff14d1519c43879da6`；固定插件与第三方依赖沿用上一版，准确校验见 manifest.json。
- Apple Silicon Rust 292 通过、1 项 Metal 测试按原设置忽略，格式／release clippy／构建及两配置共 28 项隔离检查通过；深浅 GUI、输出点击展开、分屏滚动条实际拖动已验收。Windows、旧 macOS、新机联网完整安装仍未实机验收；App 未公证，既有依赖锁与许可证索引限制保留。

## 2026-10-19 · glow-stack-20261019-gm1

本机配置与 Neovide／portable 使用同名冻结标签。旧 gm2、配色标签及下载完整保留；本版继续作为预发布。

- 原生 Liquid Glass、音视频／网页／PDF 与 SyncTeX、Notebook 保存输出和切 Tab 保留；本地 Notebook 输出与错误不因关闭重开而消失。
- 工具弹窗统一实心并移除 backdrop；同名引用增加可调细框，Cursor 显式绑定主题颜色。Neo-tree 渐隐／裁切、多光标和主题切换读取同步修复，保留用户当前 Ayu 配色与材质设置。
- 统一原生分层图标与启动行为，安装盘保留已确认的 Sketch 背景。随包 FiraCode Nerd Font Mono 与 Noto；Mac 中文调用系统苹方。
- 安装器固定 70 个插件并准备隔离 Notebook Python、内核声明和远程命令；不复制用户登录、会话或运行数据。Mac DMG 固定原生源码 `bf17179d226df65f0b5ddb3d94093f743fc6fbac`，准确下载校验与配置提交见 manifest.json。
- 已完成本机浅深 GUI、Rust 284 项／clippy／构建、隔离配置和新安装流程针对检查。Windows／旧 macOS／新机联网整套安装未验收；Mac App 未公证。Mason 传递依赖与 Notebook Python 发行文件哈希不完整锁定，第三方许可索引保留 dispatch 0.2.0 上游原文缺口。

## 2026-10-18 · ayu-colors-20261018-v1

冻结当前 Ayu Light／Dark 自定义配色、Base46 插件映射与编辑配置。两个主题文件统一命名为 `ayu_light_customed.lua`、`ayu_dark_customed.lua`，保留相同字段结构，加载入口与重载命令同步更新。

- 保存 Neo-tree Git 状态色、未保存标记、Dashboard、状态栏、复制提示、浅色行号与缩进点，以及选区加粗设置。
- 保存按用途分组的配置目录、自动浅深切换与开关同步、项目根目录跟随，以及已完成的语言环境和 Skim 修复。
- 保存多光标的移动／确认分离、`Ctrl+p` 选点撤销、Extend 大小写转换与重叠选区修复。
- 本版使用源码／配置标签，不覆盖原 `glow-stack-20261017-gm2` 发行包及下载校验值；平台适用范围与原安装说明中的限制保留。

主配置与便携副本使用同一标签，回滚入口见 `payload/nvim/README.md`。

## 2026-10-17 · glow-stack-20261017-gm2

最终总安装包快照：[glow-stack-20261017-gm2](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261017-gm2)。在 gm1 的基础上，将首页 Find File 与 Config 改为 Telescope，与 Find Text 和 Recent Files 统一。`空格 t f` 的 FFF 入口继续保留；其他版本、字母雨、图标、两秒开场和透明度设置沿用 gm1。

配置 README、部署说明、清单目录和安装包同步更新。首页两项 action 已验证会调用 Telescope，并分别以当前工作目录、配置目录为搜索根目录。cmatrix-gm 仍固定在 `f48f363c4dcbdd37d842b17e82711f869d759950`。gm1 与更早的标签和发行文件保留。

## 2026-10-17 · glow-stack-20261017-gm1

这是一份冻结快照。Apple Silicon Mac 的当前配置与字母雨行为已验收；Windows x64 + WSL2 的入口保留，仍待 Windows 真机验收。旧标签 `glow-stack-20261017` 保留，不覆盖其文件或提交。

### 固定来源

| 组件 | 固定来源 |
| --- | --- |
| 总安装包 | [glow-stack-20261017-gm1](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261017-gm1) |
| Neovide Glow / 图标 / DMG | `6c152c4d4761b5eda75f67dbd82beaa3a0afb59f`；保持原生浅色分层图标与手动拖入 Applications 的流程 |
| cmatrix-gm | [cmatrix-gm-20261017](https://github.com/Ysrae1/cmatrix-gm/tree/cmatrix-gm-20261017)，提交 `f48f363c4dcbdd37d842b17e82711f869d759950` |
| Neovim | `0.12.3`，下载地址和 SHA256 见 `manifest.json` |
| 配置、插件及其他工具 | 当前包内 `payload/` 和 `manifest.json`；延续已有插件提交与依赖版本，不跟随上游最新版本 |

CMatrix 安装仍采用固定官方 2.0 源码与本包补丁，补丁 SHA256 和对应分支提交一起记录在清单中。发行页提供完整对应源码；各下载包的最终校验值见 `SHA256SUMS.txt`。

### 本版行为

- 普通 `cmatrix-gm`：125 字符混合集，每条雨串独立速度；默认长度参数 13～21 格、4 格亮度渐隐。保留 `cmatrix-uni` 与原 CMatrix 入口。
- Neovide 两秒开场：`--intro` 在显示前快速生成中间帧，随后固定 2.5 倍速匀速下落，不播放高速铺开或减速过程；到时清理进程、浮窗和缓冲区。
- 六行首页：`--length 9:13` 单独加长虚拟雨串，保留白／银亮头和渐隐；显式长度可以超过可见区域并正常清尾。
- 修正顶部固定衰减带：渐隐从屏幕外的虚拟尾部随亮头移动。
- 修正主题黄绿串色：清尾和默认绘制属性也使用固定绿色，避免继承主题 ANSI 绿。
- 修正横向圆点堆积与字符偏移：两种半角浊音符采用独立单格载体；125 个字符仍全部参与抽样。
- 透明度保持原设置，尾部采用亮度渐隐。保留原外观、快捷键、FFF 和 Avante Codex 侧栏；账号在目标电脑本地登录，不随安装包分发。
- 不需要预装 Neovim；安装器下载、校验并调用隔离目录中的固定版本。系统编译工具、引导 Python 与 WSL 初次设置仍按部署说明完成。

### 验证与限制

已完成当前生产版本的实际 Neovim 终端检查：主题黄绿色更新为零；1172 次组合符更新中，每格最多保留一个符号；亮头、渐隐、擦除和两秒退出正常。另验证了六行长串、顶部渐隐回归、干净 C 源码构建，以及 PATH 中不存在系统 `nvim` 时的独立 Neovim 下载安装和无界面启动。

本记录不把终端检查等同于所有电脑上的 GUI 验收。Windows 真机、不同显示器和 GPU 仍须按部署清单确认。Mason 只冻结顶层工具版本，历史传递依赖未完全冻结；完整 TeX 与多媒体预览属于可选组件。Mac App 未做 Apple 公证。

后续更新另建版本标签和安装包；不要移动此标签或原地替换清单中的固定源码。
