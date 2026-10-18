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

2026-10-18 记录。第一阶段已实现，当前验证结果与使用方式见下文；其余阶段尚未实现。

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
| 音频 | 面板内播放/暂停、进度、音量 | 图片阶段完成后选定后端；打开/暂停/跳转/关闭停止，失败反馈与后台解码；尚未实现 |
| 视频 | 带播放控制的原生视频面板 | 在音频时钟与资源生命周期基础上评估解码/画面输出；验收音画同步、跳转、Tab 与关闭；尚未实现 |
| macOS WebView | 系统 WebKit/Wry 右侧分屏，本地站点/URL 预览 | 单独接入窗口与焦点生命周期；验收 HTML/CSS/JS 保存刷新、尺寸/缩放、Tab、输入法、快捷键与关闭释放；尚未实现 |
| Notebook 单文件 | `.ipynb` 单元格、Markdown、已保存输出查看 | 依赖图片与 WebView；分别验收公式、表格、HTML、PNG/SVG 和 Matplotlib 静态输出；尚未实现 |
| Jupyter Book | 项目构建入口、构建日志、站点预览与刷新 | 依赖 WebView，与 Notebook 单文件单独实现；验收构建成功/失败、产物刷新和关闭；尚未实现 |

实施判断：Notebook 的首版只查看已有内容和已保存输出。内核执行、执行后的实时更新、交互图表，以及 HTML 源码/页面双向定位均需另外设计协议、进程管理与映射，当前不纳入已交付能力。Jupyter Book 不通过把 `.ipynb` 当网页打开来替代项目构建。
