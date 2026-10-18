# Neovide Glow Preview

基于 [neovide/neovide](https://github.com/neovide/neovide) 的实验分支 `glow-preview`，加入可调节的柔光效果。保留上游 MIT 许可证。这是第三方分支，尚未合入官方版本；此仓库没有提供经过签名、公证的安装包。

## 配置

此分支默认开启柔光。在 Neovim 配置中可以实时调整：

```lua
if vim.g.neovide then
  vim.g.neovide_bloom = true
  vim.g.neovide_bloom_strength = 0.20
  vim.g.neovide_bloom_radius = 8.0
  vim.g.neovide_bloom_brightness = 1.10
  vim.g.neovide_bloom_saturation = 0.15
end
```

| 参数 | 默认值 | 范围 | 作用 |
| --- | --- | --- | --- |
| `neovide_bloom` | `true` | 布尔值 | 柔光开关 |
| `neovide_bloom_strength` | `0.20` | 0–1 | 线性光能的强度 |
| `neovide_bloom_radius` | `8.0` | 0–32 | 柔光范围，按帧缓冲像素计算；对应高斯模糊的约 3σ |
| `neovide_bloom_brightness` | `1.10` | 0–8 | 柔光层的亮度，独立于范围 |
| `neovide_bloom_saturation` | `0.15` | 0–3 | 彩色柔光的饱和度增强；0 关闭增强，白光保持中性 |

数值会限制在上述范围；强度、范围或亮度为 0 时跳过柔光处理。使用原版 Neovide 时这些新增变量不会提供柔光功能。

柔光从明亮且不同于默认背景色的内容中提取，采用 Skia 原生滤镜，在宽、高各一半的分辨率上模糊，再用 Screen 混合叠加。原始文字与光标保持原分辨率，不经过模糊；叠加的光仍会影响最终感知的亮度和颜色。此实现没有 GPU 到 CPU 的帧回读，不支持直接加载 Ghostty 的 GLSL shader。

## 获取与编译

```sh
git clone --branch glow-preview https://github.com/Ysrae1/neovide.git neovide-glow
cd neovide-glow
git remote add upstream https://github.com/neovide/neovide.git
cargo build --release --locked
./target/release/neovide
```

Rust、Neovim 和系统编译依赖请按仓库现有的[安装说明](website/docs/installation.md)准备。Apple Silicon 也可显式使用原生目标：

```sh
rustup run stable-aarch64-apple-darwin cargo build --release --locked --target aarch64-apple-darwin
./target/aarch64-apple-darwin/release/neovide
```

## 合并官方新功能

`origin` 指向个人 fork，`upstream` 指向官方。`main` 可保持官方历史，日常使用和柔光改动留在 `glow-preview`。下面的操作只更新源码，不替换当前运行的应用：

```sh
git switch glow-preview
git status --short
# 若有未提交改动，先提交或暂存；保持工作区干净后继续。
git fetch upstream --tags
git merge upstream/main
```

合并没有冲突时，官方新功能与柔光提交都会保留。若渲染接口变化导致冲突，先逐项解决并提交合并；需要撤销本次合并时使用 `git merge --abort`。不需要重置分支或强制推送。

完成合并后检查并编译：

```sh
cargo fmt --all -- --check
cargo test --release --locked renderer::bloom_tests
cargo build --release --locked
# 运行编译结果，确认文字、柔光开关和光标动画，再推送。
git push origin glow-preview
```

如果只希望跟随稳定版本，可在 fetch 后把 `upstream/main` 换成已确认的官方版本标签。官方发布不会自动改写此分支；每次合并仍需检查兼容性。建议先验证新构建，再替换已安装的应用，并保留上一版以便恢复。

## 验证与限制

- 本版在 macOS Apple Silicon 上完成 release 编译、CPU 图像断言、Metal 渲染检查，以及实际窗口中的开关验证。
- 默认测试检查原始内容不被压暗、透明像素与独立暗色填充、柔光确实产生以及关闭时跳过处理。测试图形不依赖系统字体。
- Metal 测试需真实 macOS GPU，默认忽略；可用 `cargo test --release --locked renderer::bloom_tests -- --include-ignored` 手动运行。
- Windows、Linux 和其他 GPU 后端尚未验证。实现使用跨平台 Skia 滤镜，但不能据此保证所有后端效果一致。
- 柔光仍有额外渲染开销。降低处理分辨率能减小部分工作量，实际成本随窗口尺寸、GPU、动画频率而变化；本分支没有可用于宣称帧率提升或 GPU 节省比例的正式基准测试。

## 媒体预览开发计划

2026-10-18 记录。第一阶段及后续音视频、macOS WebView、Notebook 保存输出查看与 Jupyter Book 构建首版已实现；实际验收与平台边界见下文。

- **第一阶段：图片原生预览。** 评估移植 [fredizzimo 的 img-support 分支 / PR #3039](https://github.com/neovide/neovide/pull/3039)及其[配套 Snacks 分支](https://github.com/fredizzimo/snacks.nvim/tree/neovide-image)，接入 Neo-tree 的图片预览入口，支持适应窗口、缩放和关闭。参考代码仍为实验实现，需要适配当前 Neovide 和 Neovim，补齐异步加载、错误处理与资源释放。
- **第二阶段：音频播放。** 在图片预览稳定后评估内嵌播放控制，包括播放、暂停、进度和音量，以及关闭面板后的停止行为。
- **第三阶段：视频播放。** 单独评估解码、画面输出、音画同步和拖动进度的实现方式与维护成本，再确定范围。
- **独立方向：内嵌 WebView 预览。** 评估使用 [Wry](https://github.com/tauri-apps/wry)，先在 macOS 上复用系统 WebKit，将网页嵌入 Neovide 右侧分屏。初步范围包括本地 HTML／CSS／JavaScript 保存后自动刷新、URL 页面查看，以及分屏尺寸、缩放、Tab 切换、焦点、输入法和快捷键的协调；按需创建预览，关闭时释放资源。参考[上游议题 #2427](https://github.com/neovide/neovide/issues/2427)，当前尚未找到可直接复用的 Neovide 实现。HTML 的源码与页面双向定位另行评估，不默认视为已有能力。
- **独立方向：Jupyter Notebook 渲染。** 支持打开 `.ipynb`，按单元格展示代码、Markdown 和已保存输出，包括表格、公式、图片及 HTML 输出；接入 Matplotlib 等绘图库的 PNG／SVG 图表输出，评估复用图片与 WebView 预览能力。先实现已有内容与静态图表的查看，内核连接、单元格执行后的输出实时更新及交互式图表缩放另行评估。
- **独立方向：Jupyter Book 预览。** 支持文档项目的构建入口和站点预览，评估在内嵌 WebView 中显示页面并随构建结果刷新；与 `.ipynb` 单文件的单元格渲染分别实现和验收。
- **必要验收：** 保留现有柔光及底部渲染修复；图片预览覆盖浅深主题、缩放、裁切和 Tab 切换，加载失败不阻塞编辑器，关闭后释放资源。音视频阶段另补对应播放验收。

### 第一阶段交付：原生图片预览

保留冻结标签 `ayu-colors-20261018-v1`，开发在其后新增提交；不替换 gm2 发行包。Neovide 构建与主配置、`portable/payload/nvim` 中的配套配置一起使用。

在 Neo-tree 中对图片按 Enter、双击、分屏打开或 `t` 新建标签页，会进入原生预览。也可用 `:GlowImage /absolute/path/image.png` 打开。支持 PNG、JPEG、GIF 首帧、WebP、BMP、TIFF、ICO；本阶段不支持 SVG 和动态图播放。

| 操作 | 按键 |
| --- | --- |
| 适应窗口并居中 | `0` / `f` |
| 放大、缩小 | `+` / `=`、`-` |
| 平移，查看放大后的裁切区域 | `h` / `j` / `k` / `l` |
| 下一个、上一个 Neovim 标签页 | Tab / Shift-Tab |
| 加载失败后重试 | `r` |
| 关闭预览 | `q` / Esc |

读取、格式识别、完整 RGBA 解码与 Skia raster 创建均在后台完成，编辑器通过异步 RPC 收到结果。全应用最多两个并发解码，每个编辑器会话最多八个活动预览；单文件上限 64 MiB，源像素和 RGBA 缓冲分别上限 128 MiB（不是进程总内存上限）。关闭、换图或离开 Neovim 标签页会撤销请求并移除图像引用，迟到结果不重新显示；正在进行的有界解码会结束后丢弃结果，不能声称可在解码器内部立即中断。返回标签页时保留缩放和平移并重新加载。

已评估固定上游参考 [img-support `5c05d87`](https://github.com/fredizzimo/neovide/commit/5c05d87d666fed917fd088e0644456c598d5dcfd) 与 [Snacks `a1862c6`](https://github.com/fredizzimo/snacks.nvim/commit/a1862c6b488ece4bc03a68b01efff11ced020953)。复用了 RPC 传输、网格到像素换算及 Skia 线性采样/严格裁切的实现思路；没有整体合并旧实验分支。旧实现同步加载、缺少删除处理，`vim.img` 路径还依赖实验 Neovim API；直接换用旧 Snacks 会倒退当前插件。当前适配保留 Neovim 0.12.3、Snacks `fe7cfe9` 和 Neo-tree `f3df514`，插件锁文件不变。

源码中的原生 RPC 为 `neovide.image.load/show/hide/close`，按 route 隔离编辑器窗口；配套 Lua 模块 `config.media.image` 负责预览窗口与加载反馈。图片跳过柔光叠色，编辑器文字和浮窗保留现有柔光；透明像素显示编辑器背景，没有建立照片校色保证。

2026-10-18 验收记录：

- **源码与自动检查：** 图片相关 8 项 release 测试通过，覆盖七种格式、alpha/GIF 首帧、损坏/缺失文件、大小限制、参数边界、适应比例、缩放裁切、释放引用及拒绝迟到结果；原有柔光与底部渲染相关 3 项检查通过。完整 Neovim 0.12.3 配置下的真实 Neo-tree 事件/按键与窗口生命周期检查通过，插件锁未更新。
- **构建：** macOS Apple Silicon 的 `cargo build --release --locked --target aarch64-apple-darwin` 通过。可运行二进制在 `target/aarch64-apple-darwin/release/neovide`；本机独立开发应用在 `target/Neovide Glow Images.app`，不覆盖 `/Applications/Neovide.app` 或 gm2 发行包。
- **实际 GUI：** 在独立开发应用中查看了浅/深 Ayu 主题、透明图片适应、Neo-tree Enter 打开、缩放与分屏裁切、Neovim Tab 离开/返回、关闭及损坏图片反馈。修正了固定 Neovim 版本的 winbar 高度差异，图片不覆盖状态栏。24MP 图片仍在加载时，编辑器能继续处理请求并关闭预览；迟到结果不复活窗口。图片跳过柔光叠色的路径另有像素断言。
- **范围限制：** GUI 验证限本机 macOS/Metal；未验收 Windows/Linux、原生 macOS 系统 Tab、动画播放或照片校色。静态 GIF 首帧和本地栅格图片不能代表后续音视频、WebView 或 Notebook 能力。

### 后续阶段的交付与验收边界

| 阶段 | 交付物 | 必要验收与依赖 |
| --- | --- | --- |
| 音频 | 面板内播放/暂停、进度、音量 | macOS AVPlayer 异步准备；播放/暂停/跳转/音量、失败、Tab 与关闭释放已检查 |
| 视频 | 带播放控制的原生视频面板 | macOS AVPlayerView 原生画面；共享时钟、跳转、Tab 与关闭已检查，外部音画延迟未测 |
| macOS WebView | 系统 WebKit/Wry 右侧分屏，本地站点/URL 预览 | 直接使用系统 WKWebView；本地保存刷新、URL、尺寸/缩放、Tab、中文输入与关闭已检查 |
| Notebook 单文件 | `.ipynb` 单元格、Markdown、已保存输出查看 | macOS WebView 查看 nbformat 4；公式、表格、HTML、PNG/SVG、Matplotlib 已保存静态输出已检查 |
| Jupyter Book | 项目构建入口、构建日志、站点预览与刷新 | 独立异步构建；Jupyter Book 1.0.4.post1 的成功、失败与产物刷新已检查；MyST 工具链未实测 |

实施判断：Notebook 的首版只查看已有内容和已保存输出。内核执行、执行后的实时更新、交互图表，以及 HTML 源码/页面双向定位均需另外设计协议、进程管理与映射，当前不纳入已交付能力。Jupyter Book 不通过把 `.ipynb` 当网页打开来替代项目构建。


### macOS 后续阶段首版：播放、网页与文档预览

新功能通过系统 AVFoundation/AVKit 和 WebKit 嵌入现有 winit 窗口；无需第二套窗口事件循环。已评估 Wry：其 macOS 后端也使用 WebKit，当前直接桥接已有 NSView 可减少依赖与焦点层级。此部分最低构建目标为 macOS 11，实际验收仅限本机 Apple Silicon/Metal；Windows/Linux 继续保留图片能力，不提供音视频/WebView 原生后端。

主配置与 `portable/payload/nvim` 同步后可用：

| 入口 | 用途 |
| --- | --- |
| `:GlowMedia /path/file.wav`、`:GlowMedia /path/file.mp4` | 在右侧面板预览音频或视频 |
| `:GlowWeb /path/index.html`、`:GlowWeb https://example.com` | 本地网页或 URL 页面 |
| `:GlowNotebook /path/file.ipynb` | 单元格与已保存静态输出 |
| `:GlowBook /path/project` | 查找项目配置并异步构建 HTML 站点 |
| `:GlowBookLog`、`:GlowBookCancel` | 查看构建日志、取消本模块启动的构建 |
| `:GlowPreviewFocus`、`:GlowPreviewClose` | 进入原生面板、关闭当前 Tab 的预览 |

Neo-tree 的 Enter、双击、分屏和新 Tab 入口继续保留图片预览，并支持上述音视频扩展名、HTML 与 `.ipynb`。音频入口包含 MP3/M4A/AAC/WAV/AIFF/CAF/FLAC；视频入口包含 MP4/M4V/MOV/MPG/MPEG。实际编码是否可播放由系统解码器决定，文件后缀不构成兼容性保证。

音视频面板有原生播放/暂停、进度与音量控件。编辑器焦点下 Space 播放/暂停，`h/l` 跳转五秒，`+/-` 调音量，`0` 回到开头，`r` 重新加载，`q`/Esc 关闭。初始暂停；离开 Neovim Tab 即停止并销毁原生播放器，返回时按最近异步反馈的位置重新载入并保持暂停。位置反馈每 500 ms 更新，离开时可能有最多约一个反馈周期的进度差。关闭和编辑器 route 销毁会解除观察器、取消加载、移除子视图并释放播放器。

网页按需创建，右侧分屏尺寸与编辑器字号/缩放变化同步。编辑器焦点下 `i`/Enter 进入网页，`+/-` 调整网页缩放，`0` 复位，`r` 刷新；网页中普通 Tab 保持表单导航，Cmd+Esc 返回编辑器，Ctrl+Tab/Ctrl+Shift+Tab 切换 Neovim Tab。Cmd+A/C/X/V/Z 与 Cmd+Shift+Z 在网页焦点下交给系统编辑动作。Neovim 中保存本地 HTML、CSS、JS/MJS 时，同一目录树中的活动页面刷新；解析真实路径，避免 `/tmp` 与 `/private/tmp` 等别名漏掉保存事件。此首版不监视其他程序的磁盘写入，也不实现源码/页面双向定位。WebKit 使用临时数据存储，关闭释放视图与本模块监听，不保留登录会话。

Notebook 异步读取上限 32 MiB、4000 单元格，支持 nbformat 4。随配置携带 markdown-it 14.1.0、KaTeX 0.16.22 及字体，可离线查看公式、Markdown 表格、代码、文本/错误、静态 HTML、PNG/SVG 和 Matplotlib 已保存输出。HTML 输出在脚本停用的子框架内显示；不连接内核、不执行单元格、不提供交互图表。保存 `.ipynb` 重新渲染，关闭删除临时 HTML；异步准备完成时不抢走其他 Tab，回到原 Tab 后才首次打开面板。

Jupyter Book 使用选定环境中的真实命令，并按该项目配置构建；与单文件 Notebook 查看分别实现。传统 `_config.yml` 使用 `jupyter-book build`，`myst.yml` 使用 `jupyter book build --html`。找不到命令时给出反馈，不自动修改用户 Python 环境；也可通过 `require("config.media.book").open(path, { builder = { ... } })` 传入环境启动命令的参数数组。重建成功才刷新已有站点，失败保留原站点并显示日志；首版通过再次执行入口重建，不承诺自动监视整个项目。取消只向本模块启动的构建进程发送 SIGTERM，不保证终止项目自行派生的长期进程。现代 MyST 参数与常见产物路径已接入，但未进行真实 MyST 工具链验收。

2026-10-18 验收：

- Rust release 构建、协议边界检查、分屏生命周期测试及 Notebook/Book 的 38 项针对性断言通过；插件锁不变。音频 AppKit 检查覆盖异步准备、播放时钟、暂停、跳转、音量、错误、加载中关闭与释放。WebKit 检查覆盖 CSS/JS、子框架输出、错误、焦点、缩放、坐标及释放。
- H.264/AAC 原生视频测试在跳转前后采样 85 帧，解码帧时间戳与同一 AVPlayer 时钟最大偏差约 11 ms；4.25 s 跳转、音视频轨启用、首帧和关闭释放通过。播放检查静音进行，不能作为外部扬声器/显示延迟或主观口型同步的测量。
- 独立开发应用实际 GUI 检查了原生音视频画面与控件、缺失文件反馈、Tab 离开/返回、网页 HTML/CSS/JS 保存刷新、分屏尺寸/缩放、按钮、中文粘贴、系统输入法键入并提交“你好”、页面焦点下 Ctrl+Tab 和 Cmd+Esc。Notebook 公式、Markdown/HTML 表格、真实 Matplotlib PNG/SVG 已在 WKWebView 中查看；没有重复此前图片/柔光全量验收。
- 在隔离环境中使用官方 Jupyter Book 1.0.4.post1 实际构建、修改内容后重建刷新、非法目录配置失败；构建站点另在开发应用中打开。用户既有 Python 环境未升级。未据此宣称现代 MyST、Windows/Linux 或所有媒体编解码器已验收。

开发应用继续使用 `target/Neovide Glow Images.app`；没有覆盖 `/Applications/Neovide.app`、gm2 发行包、冻结标签或图标资源。源码和配套配置均应保留；原生预览 RPC 是 `neovide.preview.open/show/action/close` 通知，状态通过异步 Lua 回调送达，没有新增同步 Neovim 查询。
