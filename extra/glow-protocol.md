# Glow 配套配置接口

维护：Codex，2026-10-19。这里记录 GUI 与 Neovim 配置共同使用的长期约定；当前状态和验收记录仍只在 [GLOW.md](../GLOW.md)。

## macOS 原生菜单语言

支持的 macOS GUI 设置 `g:neovide_native_menu_version=1`，提供 `neovide.set_native_menu_language("en" | "zh")`，并触发 `User NeovideNativeMenuReady`。底层通知 `neovide.native_menu.language` 接收一个完整快照 `{version=1, language="en" | "zh"}`；非法版本／语言整包拒绝，保留当前菜单。旧 GUI、Windows 和 Linux 不发送此通知。

本机及 portable 的 `config.platform.native_menu_locale` 监听就绪及 `GlowLanguageChanged`，传递同一 UI 语言。原生端记录各编辑器 route 的选择，只更新活动窗口对应的应用菜单；切换编辑窗口时恢复其语言，后台初始化不覆盖前台。启动期间窗口尚未创建的通知也会保留。

原位修改应用自建菜单、Dock“新建窗口”，以及注册窗口菜单内已确认动作的系统项；不重建菜单，不修改 selector、target、快捷键或 Services／Windows／Help 注册。系统窗口操作以实际 selector 白名单识别，未知动作保留；布局分节另要求已知布局子树／分节头上下文。`menuWillOpen` 只安排一次 common-mode 延后刷新，等 AppKit 完成插入与验证后，在菜单跟踪期间补齐标题。所有全屏操作标题随实际窗口状态更新。应用名、文档名、设备名后缀和系统提供的 Services 子项保留原值；后者仍由 macOS 自身的语言和服务提供方管理。桥接回归见 `tests/navigation/native_menu_locale.lua`，真实菜单与文档保护验收使用独立测试 App。

全屏项由专用 target 转发同一个 `toggleFullScreen:`，验证时保留 NSWindow 的可用性决定，然后回写当前语言标题，防止 AppKit 再次覆盖。仅移除同一窗口菜单内后来追加的重复全屏项，保留自建项及其用户配置快捷键；语言切换不更换该 target。

## 图片传输与编号

`neovide.image.load/show/hide/close` 使用同一个编辑器 route 内的正整数 ID；不同 route 独立。图片、Molten 和嵌入式 Yazi 共用该命名空间，不能各自从 1 开始计数。配套配置的 `config.media.image_transport` 是编号分配及状态分发入口：

| 调用方 | 有效 ID | 状态接收模块 |
| --- | --- | --- |
| 普通图片预览 | 1–999999 | `config.media.image` |
| Molten 图像 | 1000001–1999999 | `config.media.molten_images` |
| 嵌入式 Yazi | 2000001–9007199254740991 | `config.media.yazi` |

1000000 与 2000000 保留不用；上限不超过 Lua 精确整数范围。编号递增、不回绕、不重用，以免尚在队列中的旧回调击中新请求；有限范围耗尽时给出重启会话提示，不能侵入下一调用方的范围。关闭或取消后，各接收模块继续按自身活动请求表拒绝迟到结果。热替换时应保留模块状态，不能单独卸载编号分配模块。

新 GUI 的异步状态回调优先调用 `image_transport.on_status(id, width, height, error)`；旧配置没有此模块时保留历史范围分发。新配置沿用历史范围，因此也能与已有 Glow 图片构建配合使用。`neovide.preview.*` 的音视频、网页与 PDF 编号属于另一套协议，不占图片范围。

`load(id, path, owner)` 的第三个参数可选，值为 `image`、`molten` 或 `yazi`；配套模块经 `image_transport.load` 传入。旧配置省略时按历史 ID 范围推断，旧 GUI 忽略新增参数。全应用总上限保持八槽，Molten 在所有 route 中最多六槽，为普通图片与 Yazi 共同保留两槽；交互预览自身仍共享总上限，不能保证任意数量均成功。`hide` 只隐藏，`close` 才撤销并释放请求。Molten 保留超额输出及暂缓占位，先回收旧候选，再加载当前候选；释放事件安排重试并以 750ms 退避限制频率，不轮询。取消、失败、同 ID 重载及 route 销毁均归还配额。回归见 `tests/media/{image_transport,preview_fairness}.lua`、真实 GUI 入口及图片 Rust 单元测试。

## 高亮语义与插件适配

颜色始终来自 Neovim 主题；Rust 不提供另一份 Ayu 调色板，也不再按 Notebook／Avante 的高亮名称猜渲染行为。配置通过 `neovide.highlight_roles` 发送版本化完整快照：

```lua
neovide.set_highlight_roles({
  MyTypeIcon = { "enlarged_icon" },
  MyKernelTitle = { "notebook_kernel" },
  MyActionTitle = { "notebook_actions" },
  MySolidCap = { "solid_title_cap" },
  MyReference = { "reference_outline" },
  MyCaption = { "centered_caption" },
})
```

原生 RPC 参数为 `{version=1, groups={...}}`，每个编辑器 route 独立。合法空映射清除角色；非法版本、未知角色或冲突快照整包拒绝并保留原映射。声明改变会更新已经缓存的网格／光标样式并重绘。组合高亮保留完整名称列表，由声明匹配；更具体的后项决定顶栏对齐角色。

本机与 portable 的 `config.appearance.render_roles` 集中声明现有主题组。新 GUI 的 `lua/highlight_roles.lua` 为旧配置提供兼容默认声明，并在 VimEnter／ColorScheme 重发；旧 GUI 没有 setter 时，配置仅保存声明，继续使用旧渲染路径。更改主题组名时同步 Lua 声明即可，不需要修改 Rust 组名字符串。

`reference_outline` 将连续引用格合为一个细矩形，不因语法前景或当前行背景分片而产生内部竖线；普通格间隔及 `sp` 颜色变化会开始另一框。描边使用高亮的 `sp`（未设置时回退前景），宽度固定一个物理像素，完整保留在字格内，不继承背景 `blend`。原生端在加载声明脚本时设置 `g:neovide_reference_outline_supported=true`，完成 setter 初始化后触发 `User NeovideHighlightRolesReady`；新配置仅在能力标记存在时发送此角色，避免旧 GUI 因未知角色拒绝整包声明。内置兼容默认映射覆盖 `LspReferenceText/Read/Write`。

`centered_caption` 只将连续声明标题的实际文字墨迹水平居中于原有标题格范围，合并该段的所有字体／高亮 run 后统一平移；字体、字间排布、背景宽度、边框和窗口位置不变。标题行失效重绘时以小型透明 raster 测量实际 hinted alpha 边界（避免保守 glyph bounds 的额外误差），按整数像素移动以保留其抗锯齿，静态行沿用缓存。它修正 CJK fallback 字形 advance 小于两格而造成的右侧额外空白。配置仅在 `g:neovide_centered_caption_supported=true` 时声明，旧 GUI 保留原来的相同左右空格，不发送未知角色。现有声明只覆盖三类 `GlowPicker*Title`、三类 `Telescope*Title` 及 popup 层对这六个名字派生的 chunk-only 组；普通正文、Notebook 与任意同色组均不参与。

终端中的圆角端帽由字符绘制，端帽背景会填满整个矩形字格。`config.appearance.capsules` 在主题兼容层刷新时统一 minimal/round 状态栏左端帽与 Avante 的 `Reversed*Title`：端帽只保留既有前景和样式，外侧背景继承所在栏，与原本正确的右端帽一致。实心主体、文字及调色板不变。Neovide 跳过这项终端修正，继续使用自己的字形与材质处理；媒体和 Notebook 的端帽已使用透明背景，无需另设覆盖。

| 名称或角色 | 配置来源 | GUI 消费者与用途 |
| --- | --- | --- |
| `GlowNotebookLanguage`、`GlowNotebookMarkdown` | `config.media.notebook_edit` | `enlarged_icon`：仅类型图标放大，端帽与正文保持原尺寸 |
| `GlowNotebookKernel{,Cap,Value,ValueCap}` | Notebook 顶栏 | `notebook_kernel`：内核域的小数格对齐 |
| `GlowNotebookCells*`、`Prev`、`Next`、`Menu*` | Notebook 顶栏 | `notebook_actions`：操作域对齐；名称集合在 Lua 显式声明，不将任意前缀自动当作角色 |
| `AvanteReversedTitle`、`Subtitle`、`ThirdTitle`、状态栏 `St_*ModeSep`／`St_*_sep`／`St_sep_r` | `config.appearance.render_roles` 与 `transparency` | `solid_title_cap`：端帽保持实心并位于普通图标下方，外侧沿用玻璃底材 |
| `LspReferenceText`、`LspReferenceRead`、`LspReferenceWrite` | `config.appearance.render_roles` 与 `editor_highlights.references` | `reference_outline`：引用词的单像素外框，颜色由对应高亮 `sp` 控制 |
| 六个 picker 语义标题组及其 popup 派生组 | `config.appearance.render_roles` | `centered_caption`：只移动标题文字，使实际字形左右留白相等 |
| `SnacksPickerInput/List/Preview` 及其 `Border`，`SnacksPickerBox{,Border}` | 固定版本 Snacks 的窗口局部 `winhighlight` | `lua/float_shadow.lua` 从窗口角色识别组合面板；RPC `neovide.window.shadow_exclusions` 传递窗口 ID，Rust 按窗口 ID 处理阴影 |

Snacks 的链接高亮可能只留下 `NormalFloat` 等通用名字，因此其窗口角色仍在 Lua 层读取，Rust 按窗口 ID 处理。不要将这些已有适配扩展为所有同色或任意插件浮窗的隐式规则。角色声明检查见 `tests/media/highlight_roles.lua` 与 Rust `highlight_roles`、样式替换和像素回归。

底部状态栏的 `St_*` 底材沿用 `config.appearance.transparency` 中的 `material_blend`，胶囊主体显式 `blend=0`，避免继承底栏透明度；不改公共 `StatusLineNC`，以免传递到链接它的顶部 Tab 栏。组合高亮回归见 `tests/media/statusline_material.py --config /path/to/nvim`（使用已有 pynvim 环境）。

`g:neovide_bottom_margin_opacity` 是可选的 0～1 不透明度，仅控制全局根网格下方不足一个字格的像素余量；默认未设置或设为 `nil` 时沿用原背景。它使用 Normal 的 RGB，乘全局 `neovide_opacity`，独立于编辑区 `neovide_normal_opacity`；不延展最后一个彩色胶囊，不影响浮窗、分屏或显式 padding。配置将其设为 `(100-material_blend)/100`，旧 GUI 忽略此设置。

Notebook 输入/输出框与图像滚动锚点通过各自的原生协议传递窗口和布局 epoch。主题重载应只改变颜色，不重新编号请求或启动内核。已有验证包括 Rust 组合高亮/样式/像素断言，以及 headless Notebook 高亮、胶囊检查；真实 Snacks 插件链路另见 `tests/media/picker_shadow_scope.py`，需要已安装的固定插件与 Python 依赖。

输出展开提示仅在实际折叠或长行超出可用宽度时显示。支持 `neovide_native_notebook_footer=true` 的前端将胶囊置于底边中心线；`neovide.notebook.frames` 的可选 `footer_gaps` 与顶边 `label_gaps` 使用相同的局部列坐标 `{ col, width }`，最多八项，数值必须有限、非负且不超过 1,000,000，宽度必须为正。底边断口只裁底部描边，保留输入／输出接缝与左右边线；旧前端将提示留在框内安全显示。查看浮窗复用原始 Molten 文本及语义高亮，按源输出框的实际边界定位，仅改变当前查看窗口的滚动方式。
