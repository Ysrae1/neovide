# Neovide Glow Preview

基于 [neovide/neovide](https://github.com/neovide/neovide) 的实验分支 `glow-preview`，加入可调节的柔光效果。保留上游 MIT 许可证。这是第三方分支，尚未合入官方版本；此仓库没有提供经过签名、公证的安装包。

## 当前维护状态

- 2026-10-20，Codex：按用户选择准备原生 Windows 离线安装 EXE，新增 `portable/windows/` 与独立 Windows 构建工作流；旧 Mac／WSL 冻结包不改写。原生配置路径、Yazi 私有覆盖层、Notebook 可迁移运行时、GUI／CLI 启动器及字母雨移植已实现，构建与迁移集成仍进行中；尚无完成构建的安装 EXE，不把本机隔离检查视为 Windows 实机通过。本机／portable 共 28 项既有隔离检查已通过。
- 原生安装器源码 `2458c68` 与工作流修正 `5bd3a59` 已推送，配置适配 `4e14d093` 已推送 `my-config`。Windows 云端运行 [39439856567](https://github.com/Ysrae1/neovide/actions/runs/39439856567) 已完成原生 release 编译；Rust 测试 268 通过、1 项因测试 PATH 尚未准备 Neovim 而失败，安装 EXE 尚未生成。日志 `target/glow-windows-native-assets/first-worker-failed.log`；前一工作流 `runner.temp` 解析错误已修正。
- 实际 Windows 增量：`39443697531` 暴露 Git 换行转换导致字体许可哈希变化；`b15b944` 保留 payload 原始字节并固定 UTF-8，模拟 autocrlf 检出校验已通过。随后 [39446855475](https://github.com/Ysrae1/neovide/actions/runs/39446855475) 的原生 Rust 269 项全部通过，工具／Python／启动器与 Matrix 编译完成；Avante 编译误选 Portable Git 的 POSIX `link.exe` 失败，Codex 正将该目录移出编译 PATH 后重跑。日志 `target/glow-windows-native-assets/third-worker-failed.log`。
- [39448509793](https://github.com/Ysrae1/neovide/actions/runs/39448509793) 已完成全部原生插件、56 个 parser、24 个 Mason 包与31条可迁移命令的生成；首次 profile 初始化被冻结 `nvim-dap-python/spec/.env` 测试样例误拦。该路径已用固定提交的 Git 树确认，未读取内容；构建仅省略插件测试目录中的凭据类样例，保留其他凭据拦截，启动错误新增包内相对路径。定向复制检查与 C# 编译／路径诊断检查通过，Codex 正重跑余下验收。
- 已包含 `c60d4e4` 的插件缓存复制修正和 `19228a4` 的搬迁 Notebook 实际执行检查；新增内核检查仅在本机隔离环境通过，Windows 尚未跑到该项。离线安装 EXE 仍未生成；编译缓存和主程序已在 Actions 保留，不重复启动并行构建。
- 发布页字体修复已上线第 15 版，源码 `a5efa3ca339fbfa8836003fee4a8b8ad5a539925`；自托管 Inter 4.1／Fira Code 6.2 并补齐 Windows 字体回退。线上字体加载、桌面深浅色与 375px 无横向溢出已检查，Windows 真机字体仍待下次连接；证据 `target/glow-site-fonts-20261020-qa/`。此次未修改共同规则。

- 2026-10-20，Codex：Windows 11 x64 冻结版已在实机完成安装与原生 release 构建（最后增量 54.58 秒），源码 `b8b92bcc8f1e7b974e353e21f34f546dcf66bcac`，版本 `nightly-90+gb8b92bc-dirty` 为批准的图标覆盖。测试根 `D:\GlowTest-20261020-182319`；现有启动入口 `App\neovide-b8b92bcc8f1e\Neovide Glow.cmd`／`.ps1`。用户反馈首次 GUI 已打开且显示正常；尚不能据此宣布完整 Windows 验收通过。
- WSL 3.0.3／Ubuntu 24.04 的 WSL2、默认发行版及非 root 检查通过，隔离 stack 为 Linux 用户目录下 `.local/share/neovide-glow/stacks/neovide-glow-20261020-gm1`。工具、插件、Notebook 包与注册、CMatrix headless、56 个冻结 parser 安装及 Mason 阶段完成。Windows BuildTools 17.14.42、Git、CMake、LLVM、Ninja、Rustup 1.29.1／Rust 1.99.1 均就绪；Cargo、Rustup、BuildTools 与输出在测试根，Ubuntu 整体在 D 盘。
- 本次安装兼容处理：PS5.1 显式传 `-Manifest`／`-InstallRoot`；交互式 VS 安装去掉 `--norestart`；非交互 WSL 会话引入 Rustup 环境，结束恢复会话变量；JSONC 改用 Git 拉同一冻结 revision；Go 模块下载超时以本次进程下载源替代。下载缓存经 Mac 官方文件校验、微信传送后预填，既有应用／冻结发行未改动。初次失败日志保留，不运行旧 `Glow-Prepare.cmd`。
- Skia 0.153.3 官方预编译包已在目标机使用成功：`Glow-Skia-Windows-0.153.3.tar.gz`，25,098,632 字节，官方 API SHA256 `fff3732ad7c9b9935f9cf3d91cd00c2a704e7e3356365c5472c3bc08fe8e6561`；后续 Cargo 使用本地 `file://D:/GlowTest-20261020-182319/Glow-Skia-Windows-0.153.3.tar.gz`，不要加第三个斜杠或 FORCE 下载变量。构建源码和 target 在 `App\build-b8b92bcc8f1e`，保留以续测。
- 本地辅助文件统一在 `target/glow-windows-20261020-qa/`。用户要求双击 EXE 入口，已准备 `Install-Glow-Exe.ps1`（PS 解析与内嵌 C# 编译检查通过，真实生成尚待 Windows 执行）；它旁置原生 `Neovide Glow.exe` 并尝试创建桌面快捷方式，不覆盖主程序。`Run-Windows-Checks.ps1` 准备 Windows release Rust 测试与两份配置共 28 项隔离 Lua 检查，使用真实 vendor Neovim ELF；实机测试尚未运行。两脚本打包为 `Glow-Windows-Tools.zip`，待用户传入；真实 GPU、剪贴板、快捷键、LSP、Notebook 执行／图片与 AI 登录等仍待逐项验收。
- 2026-10-20，Codex：用户反馈嵌入式 Yazi 仍调用 Chafa 并失败；朋友已断开远程，按用户要求停止当天调试。只读排查确认 `image_transport.lua` 将 Linux 图片路径原样传给 Windows 解码器，缺少 WSL 路径转换；Chafa 的直接原因尚待检查目标机原生能力变量及私有 Yazi 覆盖层。此次未改程序／配置／冻结包；下次连接先取这两项实际状态，再修复并验证图片预览。

- 2026-10-20，Codex：发布页下载入口、版本号、首屏日期与部署说明共 14 处引用更新为 `glow-stack-20261020-gm1`；`showcase/main` 提交 `30750352b6acc01f8ca16c082b3708e8e7c5abbe`，Sites 第 14 版部署成功，保留公开访问。实际线上页面已确认新标签与 Mac／Windows ZIP 链接，Windows 仍标记待真机验收；凭据不落盘，部署与截图在 `target/glow-site-20261020-qa/`。

- 2026-10-20，Codex：冻结包 `glow-stack-20261020-gm1` 已在本机 CrossOver 26.2.0 独立测试容器中运行官方 Windows x64 PowerShell 7.4.21；发行文件 SHA256 与微软校验清单一致。`install.ps1 -Plan`／`-Doctor` 均正常退出，正确报告缺失工具与 WSL／Ubuntu，记录 `target/glow-crossover-20261020-qa/`。
- 本次只验收安装入口与只读诊断；容器不具备 WSL2／MSVC，未执行完整安装、编译或 Glow GUI，不作为 Windows 部署通过。测试命令已退出，独立容器留存；用户既有 CrossOver 容器及冻结发行未改动。
- 后续完整验收仍需支持 WSL2 的 Windows x64 环境；[Parallels 官方限制](https://kb.parallels.com/en/129497) 当前同样列明 Apple Silicon 上 Windows Arm 虚拟机不支持 WSL2，不能直接替代该验收环境。

- 2026-10-20，Codex：冻结快照 `glow-stack-20261020-gm1`，源码与配置同名标签／新预发布；原生 DMG 源码 `b8b92bcc8f1e7b974e353e21f34f546dcf66bcac`，配置 `22d4852d5f176237b0f76aff14d1519c43879da6`。当前保存的逐类 editor 材质及文字配置已纳入并同步 portable；旧 gm1／gm2／配色标签与发行包保留。
- 发布资产与核验：`target/releases/glow-stack-20261020-gm1/`；复用用户本次 update 生成的同源码 DMG，SHA256 `e269431fd8b7aa49aa2056767eedf1606efe78b42637a8dda8596690f6ac1975`，实际挂载／arm64／签名／二进制／图标许可通过；ZIP 与单文件安装器各 192 个文件及内嵌校验一致，Mac／WSL 安装计划通过，不安装依赖或启动内核。
- 本次配置快照两仓库共 28 项隔离检查通过，沿用同一原生源码的 292 项 Rust／clippy／构建及实际 GUI 结果，不重复编译；Windows／旧 macOS／新机联网全安装与既有依赖锁限制保留。新预发布入口 https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261020-gm1 ，本轮不替换本机安装。

- 2026-10-20，Codex：接续用户 `neovide-update` 停下的合并，整合官方 `86227b8`（macOS 分屏原生滚动条）；8 个冲突文件与自动合并的 `Window::position_tiled` 接口已处理，保留 Glow／Notebook／Liquid Glass 与刚修复的浮窗材质，文字网格尺寸仍仅由 grid_resize 更新。滚动条默认关闭，用户配置仓库未改。
- 本次合并验证：Apple Silicon release Rust 292 通过、1 个 Metal 测试照常忽略；格式、release all-targets clippy、独立 release 构建通过。新 GUI 启动／Noice 材质实看正常；临时启用原生滚动条，实际拖动右侧仅滚动右分屏（topline 71），左分屏保持 1，随后恢复关闭。日志与窗口快照 `target/glow-upstream-20261020-qa/`。
- 合并按本轮授权在本地提交，不替换已安装 App／CLI，不推送或改冻结发行；自有 QA 进程已停止。完成后可由用户重新运行 `neovide-update` 继续原有更新安装流程；跨平台及旧 macOS 未新增实机验收。

- 2026-10-20，Codex：浮窗材质已在独立开发 GUI 修复并实看。根因是 `FloatingLayer` 把浮窗 alpha 再叠到编辑区（85% 变 97.75%），而旧子窗 blend=100 清空了 Noice 父底材；现整层按绝对 alpha 替换，Lua 各窗保留自身 policy，WhichKey footer 只保留外层阴影。配置处理逻辑已同步 portable，两边原有用户材质值与 Ayu 色值未改。
- 验证：本机／portable 共 28 项隔离检查、两配置真实 Noice／WhichKey／Snacks multigrid 与单外阴影回归、4 项 Rust 浮层像素测试、格式、release all-targets clippy 及独立 release 构建通过。新 GUI 浅深色实看 Noice 外框／留白／输入区一致、WhichKey 独立 opaque／custom／editor 切换及无页脚第二阴影；记录 `target/glow-material-20261020-qa/`。
- Notebook 原有点击修复已补真实鼠标＋键盘整链验收：初始 Cell 2，分别点击 Out[1] 的正文、图片及留白后按空格 j o，均展开 Out[1]；q 关闭正常。本轮无需再改 Notebook 实现；`target/glow-click-20261020-qa/*-click-expanded.json` 保留窗口／键事件。首次工具残留 Command 导致的非普通点击已排除。
- 限制／续作：材质修复需要新构建；本轮按用户要求本地提交，配套配置 `6f2ed5ae`，源码／portable／回归与本记录在本次源码提交中。未替换 `/Applications` 或已安装 CLI，未推送或改冻结发行。透明浮窗现在显示共同窗口底层材质，不再叠加被遮盖编辑区的背景；Windows／Linux 与旧 macOS 未实机验收。自有 QA 已停止后可直接打开 `target/glow-material-20261020-qa/Material QA.app` 试用。

- 2026-10-20，Codex：修复 Notebook 合成 `BufReadPost` 被内建 `.ipynb → json` 检测覆盖的问题；事件结束及窗口重入后重新校验已转换的 percent 源码并恢复 Python。本机与 portable 的 `notebook_edit.lua`／`runtime/init.lua` 已同步。
- 新 `tests/notebook/filetype.lua` 在真实文件类型检测开启时覆盖首次／重复加载、读入／窗口重入、源码及输出保留、原始 JSON 和普通 Python 隔离；两配置单项通过并纳入默认入口。当前用户窗口已恢复 Python parser／高亮，源码 changedtick、未保存状态、Molten 输出及内核保持，热补丁未重载会话。

- Codex，本次原生点击修复：Neovide 原生输出拖选此前消费了鼠标事件，旧 Neovim API 点击检查绕过此层；现于未拖动的释放后串行转发一对点击，拖选复制保持独立。完整输出框命中与文字复制区域分开，覆盖图片、空白和边框，保留浮窗遮挡。
- 已通过 7 项相关 Rust release 回归、release all-targets clippy 与 release 构建；独立新 GUI 的真实鼠标点击已确认 Cell 2 切至 Out[1] 所属源码格。后续 GUI 按键未打开展开窗，整条操作尚未验收；按用户要求停止新增验证并提交，不作完整通过声明。自有 `target/glow-output-click-qa/start.py` 预览已发出 stop 清理。
- 配置增量已提交 `133d6ea6`，配套输出功能的源码提交为用户创建的 `1ec0754`；本次 Rust 修复与本记录同次本地提交。保留用户 `chadrc.lua`／`popup_text.lua` 手调，未推送或替换已安装 Neovide。

- Notebook 输出新增原位向下展开、横纵滚动、同语义高亮与复制；点击内联输出选中所属格，n/i/Visual 均可接 `空格 jo`，`q/Esc`、框外点击／滚动收起。仅折叠／实际长行裁切时显示底边胶囊，普通字号展开图标与边框共用 RGB；新 `footer_gaps` 能力嵌入底边，旧前端安全回退。
- `appearance/popup_materials.lua` 逐类独立设置 opaque/editor/custom、blend 与可选背景，默认只有 Notebook 输出继承主编辑区；reload 同时更新旧会话的弹窗策略，不重载用户文字配置。修复浮窗 namespace 将全局 St_*／StatusLine／WinBar／TabLine 材质实心化，底栏原 blend 保留。
- 本轮两配置 26 项隔离检查、footer／真实 multigrid+winbar 鼠标 n/i/Visual、滚动／复制／关闭／重载定向检查通过；真实独立 Matplotlib 检查覆盖三次 MoltenTick、短窗图片适配及释放，测试内核已清理。Rust 27 项 Notebook 定向测试、格式、release all-targets clippy 与 release 构建通过。
- 独立新构建 GUI 实际查看浅深配色、底边端点及原位文字／蓝边；其真实 grid 2 输入验证插入／Visual 点击后分别展开 Out[8]/Out[7]、框外滚动收起、Normal 同色材质及底栏 blend=80，记录在 `target/glow-output-scroll-qa/`。预览由该目录 `start.py` 持有（状态见 state.json）；关闭预览或创建 stop 文件会清理自己的 GUI/Neovim，临时编辑副本已保留。
- 上述输出／材质功能已整理为用户源码提交 `1ec0754` 与配置提交 `133d6ea6`；未推送或替换安装，用户 `chadrc.lua`／`popup_text.lua` 手调保持。实际字体、图标及已发布冻结产物不变；本轮不修改共同规则，不唤醒 Claude。

- 本机工具 arm64 迁移：Rustup 1.29.0、Go 1.26.3 原生入口及 28 个 Mason 包完成；Hadolint 因旧版无原生资产从 2.12.0 升至 2.13.1，其余顶层版本保留。cbfmt 0.2.0 通过 Mason Cargo 源原生编译；LTeX 16 使用无内嵌 JDK 的原版包与现有原生 Corretto 11。
- 回滚、官方来源校验、逐包架构／版本与命令记录保存在 `~/.local/state/neovide-glow/settings-snapshots/arm64-migration-20261019/`；主要命令及 LuaLS／Texlab／Ruff 的实际 LSP 初始化、关闭已验证。debugpy 官方 universal 包保留供 Intel 目标使用的 attach_x86_64.dylib，正常运行及扩展均原生；它不是额外可执行入口。
- 未替换已安装 Neovide、推送或改写冻结发行；保留用户当前 `chadrc.lua`／`popup_text.lua` 的未提交手调。cbfmt、LTeX 若未来由旧注册表重新安装，需要继续采用本次原生来源选择，不能回退到旧 Intel 发布包。
- 冻结发布后的本地增量：`appearance/popup_text.lua` 集中 Light/Dark 的弹窗正文、路径前缀、说明、计数及通知文字，覆盖 Snacks／Lazy／Mason／FFF／WhichKey／Telescope／Noice；材质刷新修复已物化别名沿用旧主题前景。通知内 Comment／NonText 仅在独立 namespace 改色，代码注释不变。
- 两配置 24 项隔离检查及四组真实插件浅深往返／自定义文字／通知与预览隔离回归通过；当前 Light 窗口已热应用并实际查看 Recent 与 Messages，源缓冲区改动状态和内容版本未变。沿用冻结发行，增量仅本地提交，未推送或替换程序。
- Ghostty 本机光标 shader 增加失焦清除拖尾，配置验证通过；界面工具禁止操作 Ghostty，实际长文本刷新后的残影验证按用户决定留待下次 update，不能计为 GUI 已通过。修改保留本机 shader，不纳入 Neovim／Neovide 仓库。
- 冻结发布 `glow-stack-20261019-gm1`：配置 `0ff8d9cd`，原生二进制源码 `bf17179`；源码／portable 使用本次发布准备提交，两个仓库同名标签。保留旧 gm2 与配色标签，不替换本机安装。发布入口 https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261019-gm1 。
- 修复 Base46 编译先于 background 切换导致 Lazy／LSP inlay／补全按旧模式计算；兼容层重算并回写三份缓存。LazyButton 跟随主题正文色，另刷新 FFF 三个复制前景及 Noice 进度复制色。两配置 × 两前端的浅深往返／延迟加载／旧缓存注入／namespace 检查通过；当前窗口已热应用，LazyButton 前景等于当前 Normal。
- portable 同步用户最终显示值，固定 70 个插件；安装器补 Notebook 独立 Python 3.12.2、prefix 内核与远程命令，五项隔离保护回归及真实临时 XDG 注册通过，未启动内核。24 项配置检查通过。DMG 实际挂载／签名／二进制／Assets.car／许可检查通过，SHA256 `d19a4b36c57711bcd8274493a2204484739a64b132a6979ed3b517678c5fc75f`；沿用已完成的 Rust 284 项／clippy／构建与浅深 GUI，不重复全量检查。
- 发布产物与检查日志在 `target/releases/glow-stack-20261019-gm1/`；Windows／新机联网完整安装／旧 macOS 未新增验收，Notebook Python 固定版本但无发行文件哈希，dispatch 原文缺口保留。


- 本轮按用户要求整理为本地提交；配置仓库 `982df08a` 包含弹窗实心／去遮罩、引用细框配置、Cursor 绑定、Notebook 当前行及本轮 Neo-tree／多光标调整，保留用户当前手调值。配套源码与 portable 在本次源码提交中；沿用已完成的配置、浅深 GUI、284 项 Rust／clippy／构建结果，未推送或替换安装。

- Notebook 清空 Molten 默认的 `MoltenCell → CursorLine` 整格高亮，仅保留真实光标行；两配置的 `notebook_highlights.lua` 与既有回归已更新。主题重载及实际 Molten 选区／附加 UI 的浅深四组检查通过；当前会话热加载，内容、输出 extmarks、边框和内核均保留。
- 工具弹窗按类别统一实心：新 `appearance/popups.lua` 对浮窗正文／边框及透明语义背景设 blend=0／winblend=0，用现有 darker_black 避免 Normal 同色触发窗口透明；稀疏 namespace 保留原样式与映射并复用。Lazy／Mason／Snacks 取消 backdrop，通知／Noice／WhichKey 取消额外混合；主编辑区、侧栏、Dashboard 保留。两配置及独立浅深 GUI 已检查，当前会话已刷新策略。
- `references.outline` 开关与 `references.style.sp` 调整引用词的 1 物理像素细框；新增显式角色与能力／就绪握手，旧 GUI 安全保留底色。跨语法与 CursorLine 片段合并一框；Rust 284 通过／1 个 Metal 忽略，格式、release all-targets clippy 和 release 构建通过。22 项既有配置检查、新弹窗两配置回归、更新后角色声明两配置回归通过。
- 光标规则已存在但 guicursor 未绑定，导致 Cursor 改色无效；已绑定编辑模式到 Cursor/lCursor，保持形状与 TermCursor。两配置 UI 事件检查通过，当前会话已应用；用户随后手调的 pmenu_bg 配色保留并同步该 Cursor 映射。独立预览 `target/glow-popup-outline-qa/Popup Outline Preview.app` 已实看浅深弹窗、通知和细框，自有 GUI／Neovim 已清理；本轮已整理为本地提交，未推送或替换安装。
- 修复浅色 Neo-tree 渐隐再次加黑：按名称读取 Normal 会经过当前窗口的 winhighlight，得到缺前景的 NeoTreeNormal 并误回退黑色；无显式 fg 时改用全局 Normal 原始 ID 读取。两配置同步并热加载；24 组真实窗口重映射／浅深主题／路径与文件名检查通过，原有渐隐算法和样式保留。
- 多光标显式禁用插件默认 Ctrl+n 选点，统一用 Leader+m 添加，保留 Ctrl+p 撤销；两份配置与 README 已同步。实际插件默认合并／生成 heads 检查通过，当前无活动编辑层时已更新会话，现有选区数量不变。
- 两主题 `polish_hl["neo-tree"].NeoTreeCursorLine` 集中设置选中行 `bg`／独立 `blend`，透明处理尊重主题值，缺省才回退 `material_blend`；初值沿用本机 80／portable 40，保留用户浅色 `bg=ui.black`。八组主题／前端检查覆盖 0、23、100、重复刷新、RGB、缺省和终端；当前会话及主题缓存已更新。
- `editor_highlights.lua` 新增独立 `multicursor` 段，共用 style、主／其他选区覆盖及 Neovide blend 均附注释；原 `visual.multicursor_bold` 合入共用样式，默认配色和加粗保持原状。已同步 portable 并热应用当前会话；八组前端／主题检查通过，保留用户其他手调及两配置原有差异。
- 两主题新增可手调的 `base_30.mid_fg`：当前 base04／base05 的 RGB 中间值，Dark `#7E7F7D`、Light `#979A9C`，暂未绑定高亮。本机、portable 与当前会话色表已同步，两配置 × 两主题的实际 Base46 读取验证通过。
- Neo-tree 右侧状态列增加 `container.right_padding=1`，避免斜体 Git 图标在侧栏边界被裁切；保持图标、颜色与斜体。已同步本机及 portable，当前会话热应用后实际 GUI 确认右边完整，两份 Lua 语法检查通过；未重编或替换程序。
- 底部材质试用已按用户要求整理为本地提交，配套配置为 `6b257072`：仅底栏 `St_*` 底材及端帽外侧沿用 `material_blend`，胶囊主体显式 `blend=0`；公共 StatusLineNC／顶部 Tab 栏保持原状。新增可撤销的 `neovide_bottom_margin_opacity` 处理底部不足一格余量；实心端帽移到普通图标下方，其他框线次序不变，接口见 `extra/glow-protocol.md`。
- 已通过 4 项底部余量／设置测试、2 项图标层序像素回归、2 项既有端帽测试、两配置的组合高亮与角色声明检查、release 构建、格式和 release all-targets clippy；独立开发 App 已实际查看浅深主题。预览在 `target/glow-bottom-glass-qa/Bottom Glass Preview.app`，自有 GUI／Neovim 由同目录 `start.py` 持有；创建 `stop` 文件或关闭预览可清理。未替换安装或推送。
- 用户当前已安装窗口仅热加载底栏配套配置；底部余量与端帽层序需新构建，当前可在独立预览查看。`St_gitIcons` 前景改为跟随 NeoTreeFileName（为空则跟随 Normal），保留加粗／材质；本机、portable 与当前会话已同步。用户手调的编辑区高亮、material_blend／格式及 platform/neovide 设置保留，未纳入提交；快照 `bottom-glass-20261019T153908`。
- 用户确认当前边缘变黑问题已解决，本轮不再改渐隐。Neo-tree 标题在侧栏后显式设置 tabline 截断点，避免拖宽时从左侧吃掉苹果标；真实当前会话已热加载，完整 NvChad 标签栏求值与截图确认苹果恢复。宽度／平台／前端定向检查通过；隔离新增 Tab 补验停住并已清理，不计通过。
- 两个主题的普通 `Comment`／Treesitter `@comment` 统一为现有 `light_grey`（Dark `#54575D`、Light `#A0A0A0`），保留 TODO／warning／note／danger 强调色与色板。真实 Base46 编译映射检查通过，当前会话已应用并更新主题缓存；标题及两主题同步 portable，用户其他手调文件未纳入提交。
- Neo-tree 浅色边缘渐隐改为向现有 `light_grey` 弱化前景收敛，避免透明玻璃侧栏上的末尾字变白发亮；深色算法不变。仅同步 `config/navigation/neo_tree.lua`，保留用户当前主题、光标行和材质透明度的未提交调整。
- 本机隔离 GUI 已查看浅深主题；21 组深色结果与旧版完全一致，链接解析／样式与无额外背景／目标色缓存更新检查通过，记录在 `target/glow-neotree-fade-qa/checks.json`。自有测试窗口已退出；无需重编 Neovide，当前会话重新加载模块或重开后生效。
- 本地增量已整理为提交，包含 Claude 既有署名改动；图标／高亮控制上一轮提交为源码 `7b61b59`、配置 `647b829f`，本次仅增量提交 Neo-tree 渐隐修复，用户其他未提交调整保留。未推送、替换已安装程序、改写冻结标签或 gm2 发行包；原有九处 portable 适配差异保留。
- 图标：修复 macOS 启动时静态 ICNS 覆盖原生分层图标；保留显式自定义图标和独立 CLI 回退。静态资源改由同一原生编译／系统渲染路径生成，按用户认可设置 `staticBrightnessGain=1.025`；未改原始材质。模板／自定义源的 PNG、ICO、SVG、ICNS、Sketch 和 TIFF 已同步。
- 已通过新增 NSBundle 定向测试、release 构建与 all-targets clippy；隔离真实 App 验证旧版启动覆盖 1 次、新版 0 次、自定义覆盖仍有效。实际 Finder 测试盘 `target/glow-icon-qa/Neovide-Icon-Preview.dmg` 已打开供用户查看，当前挂载 `/Volumes/Neovide Glow Icon Preview`；其他自有 GUI 均已退出。用户决定跳过上下静态／原生图标描边逐像素一致性的比较，不再扩展该点。
- 编辑区三类高亮集中在本机及 portable 的 `lua/config/appearance/editor_highlights.lua`，保留原默认效果并附中文调节说明；八组前端／主题默认比对及参数重载检查通过。颜色／样式可调用模块 `reload()`；行为参数完整生效需新会话。
- 本轮补显式高亮角色 RPC、全应用总八槽／Molten 六槽预留、网页固定读取范围与信息入口、Rust／Skia 许可收集打包；接口见 [glow-protocol.md](extra/glow-protocol.md)。字体方案见下一节。
- Notebook 修复隐藏即关闭内核造成的输出丢失，并新增无内核显示保存输出、输出未保存保护、重复源码单元格导出位置校验。当前用户窗口只热移除了旧的破坏性 `BufHidden` 回调；完整新 Python 功能需新 Neovim 会话，未重启用户编辑器。快照 `notebook-history-20261019T135006`、`saved-outputs-20261019T135327`。
- 按用户要求将光标行背景提升至现有 `one_bg`（Dark `#1C1F25`、Light `#EBEBEB`），在透明处理后的覆盖层设置；不改色板或 Neovide 透明度。已同步 portable，两个配置 × 深浅主题 × 两种前端共八组实际高亮检查通过；本次未新增 GUI 像素验收。快照 `cursorline-contrast-20261019T140649`。
- 验证：22 项隔离 headless、Rust release 276 通过／1 个 Metal 默认忽略、release all-targets clippy `-D warnings`、真实 WebKit 边界、真实内核保存／切换／错误／dirty／重复源码及 E325 恢复均通过；独立 GUI 实测混合配额和无内核文本／错误／PNG 恢复。开发 App、实际 DMG 内容／签名验证和记录在 `target/glow-closure-qa/`，本轮自有 GUI／内核已清理。
- 更新准备：构建工具、图标／Sketch 源的只读预检、离线许可索引及字体检查通过；`neovide-sync-source --no-fetch` 已实际通过，当前 origin／upstream 提交均已包含在本地。配置的 Python 缓存仅加入本地忽略，保留原文件。`neovide-update` 默认更新命令行程序并生成 DMG，应用本体需手动拖入替换；本轮未执行该命令。
- 剩余：`dispatch 0.2.0` 上游缺许可／版权原文，严格完整许可检查拒绝；Windows/Linux、旧 macOS、未推送代码的远端 CI、终端实机截图与正式发行签名／公证未新增验收。CI 已加入三平台配置、字体与许可检查；Ghostty 截图沿用工具安全限制。发布页第 13 版与旧回执保留，本轮不重复部署或唤醒 Claude。

### 字体安装方案与 Claude 建议核对（2026-10-19，Codex）

用户选择 Mac 保留系统苹方，Windows／Linux 中文使用 Noto。源码安装资源已附带 FiraCode Nerd Font Mono 3.3.0 六个字重，以及 Noto Sans Mono CJK SC 2.004 常规／粗体；固定来源、校验值和原始许可在 `portable/payload/fonts/`。Mac 安装 Fira 并调用系统 PingFang SC；Windows／WSL 安装 Fira＋Noto。Lua 配置已先在本机验证再同步 portable；改前快照为 `fonts-20261019T134245`。未安装本机字体或替换 Neovide；已发布 gm2 和清单中的固定二进制来源未改，字体方案属于下一版源码增量。

已验证：四项隔离字体检查（平台选择、临时用户目录安装／重复运行、同名冲突、损坏资源拒绝）；两份 Lua 配置的 Mac／其他平台默认选择及 TOML；CoreText 从八个实际字体文件直接加载，英文／中文字形均存在。Windows PowerShell 与字体 API、Linux 字体发现尚未实机验收。

本地验证包在 `target/glow-font-package-qa/draft/`；ZIP 和单文件安装器内的八个字体、24 份许可／说明及清单均与源文件一致。文件名沿用冻结清单，仅用于打包验证；不是新的正式发行或 gm2 替换包。

Claude 建议的当前边界：

| 状态 | 实际结果与剩余工作 |
| --- | --- |
| 已闭合 | 系统字体测试依赖、clippy、FIFO、图片编号、统一入口、署名缺口 1–4、发布页，以及公开合并热点说明。 |
| 已闭合 | 图片总八槽／Molten 六槽；交互图片和 Yazi 共留两槽，暂缓输出可见、释放触发有界重试；混合模块已实际 GUI 验收。 |
| 已闭合 | 版本化 Lua RPC 角色声明；Rust 保留组合高亮名并按每个 route 的声明解释，支持改名／重载／已有网格重绘。 |
| 已闭合 | 本地 HTML 固定初始目录读取范围、目录外／符号链接导航判断及 `GlowPreviewInfo`；保留同目录 CSS／JS，并明确页面脚本和目录读取能力。 |
| 收集机制闭合 | 447 个锁定 Rust 包、Skia 本体及 13 个原生依赖的来源索引与原文随 App/DMG 携带；实际 DMG 已挂载验证。完整原文仍缺 dispatch 0.2.0，不能宣称许可全部闭合。 |
| 待外部验收 | Windows/Linux、旧 macOS、当前未推送代码的远端 CI；正式安装界面外观、签名／公证与受工具限制的终端截图仍有边界。 |

Glass 全局状态继续作为既有设计保留。DMG 为独立开发验收包，使用 ad-hoc 签名和 `--skip-jenkins`，未修改已安装 App，也未验收 Finder 安装界面的布局。

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
| `neovide_bloom` | `true` | 布尔值 | 柔光开关，配套配置快捷键 `<leader>uB`（Space → u → Shift+B）；`<leader>uG` 保留 Git Signs |
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

合并时重点核对 `src/renderer/rendered_window.rs` 中对上游 #3572 底部填充的有意回退，以及 `Window::position`；不要直接用上游版本覆盖已有底部布局与原生预览定位。

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

2026-10-18 记录。第一阶段及后续音视频、macOS WebView、Notebook 保存输出查看与 Jupyter Book 构建首版已实现；后续补充原生 Notebook 编辑执行与 macOS PDFKit 预览。以下计划保留开发阶段的先后关系，当前交付和实际验收以对应章节为准。

- **第一阶段：图片原生预览。** 评估移植 [fredizzimo 的 img-support 分支 / PR #3039](https://github.com/neovide/neovide/pull/3039)及其[配套 Snacks 分支](https://github.com/fredizzimo/snacks.nvim/tree/neovide-image)，接入 Neo-tree 的图片预览入口，支持适应窗口、缩放和关闭。参考代码仍为实验实现，需要适配当前 Neovide 和 Neovim，补齐异步加载、错误处理与资源释放。
- **第二阶段：音频播放。** 在图片预览稳定后评估内嵌播放控制，包括播放、暂停、进度和音量，以及关闭面板后的停止行为。
- **第三阶段：视频播放。** 单独评估解码、画面输出、音画同步和拖动进度的实现方式与维护成本，再确定范围。
- **独立方向：内嵌 WebView 预览。** 评估使用 [Wry](https://github.com/tauri-apps/wry)，先在 macOS 上复用系统 WebKit，将网页嵌入 Neovide 右侧分屏。初步范围包括本地 HTML／CSS／JavaScript 保存后自动刷新、URL 页面查看，以及分屏尺寸、缩放、Tab 切换、焦点、输入法和快捷键的协调；按需创建预览，关闭时释放资源。参考[上游议题 #2427](https://github.com/neovide/neovide/issues/2427)，当前尚未找到可直接复用的 Neovide 实现。HTML 的源码与页面双向定位另行评估，不默认视为已有能力。
- **独立方向：Jupyter Notebook 渲染。** 首版支持打开 `.ipynb`，按单元格展示代码、Markdown 和已保存输出，包括表格、公式、图片及 HTML 输出；接入 Matplotlib 等绘图库的 PNG／SVG 已保存图表。后续已补充 Molten＋Jupytext 的原生 Python 编辑、内核执行和输出保存；后续增加了 Skia 原生输入／输出圆角描边，交互图表仍不纳入当前交付。
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

读取、格式识别、完整 RGBA 解码与 Skia raster 创建均在后台完成，编辑器通过异步 RPC 收到结果。全应用最多两个并发解码，并共享八个活动预览槽位（涵盖所有编辑器窗口和原生 Tab，加载中及仅隐藏的请求也占槽；同 ID 重载复用槽位）；单文件上限 64 MiB，源像素和 RGBA 缓冲分别上限 128 MiB（不是进程总内存上限）。Unix 非阻塞打开后检查文件类型，拒绝 FIFO 及其符号链接，保留正常图片符号链接。关闭、换图或离开 Neovim 标签页会撤销请求并移除图像引用，迟到结果不重新显示；正在进行的有界解码会结束后丢弃结果，不能声称可在解码器内部立即中断。返回标签页时保留缩放和平移并重新加载。

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
| Notebook 单文件 | 原生 Python 单元格编辑执行，以及独立的静态保存输出预览 | Molten＋Jupytext 真实内核计算、错误和保存已检查；静态 WebView 的公式、表格、HTML、PNG/SVG、Matplotlib 已保存输出保留 |
| macOS PDF | PDFKit 文档面板、翻页、缩放、适应、连续滚动与文本选择 | 原生 PDF 实际 GUI 翻页、缩放，以及 Neovim 浮窗覆盖与点击已检查 |
| Jupyter Book | 项目构建入口、构建日志、站点预览与刷新 | 独立异步构建；Jupyter Book 1.0.4.post1 的成功、失败与产物刷新已检查；MyST 工具链未实测 |

阶段边界：Notebook 的历史首版只查看已有内容与保存输出；当前新增的原生编辑入口支持 Python 内核执行、结果更新及保存回 `.ipynb`，静态预览入口继续保留。当前单元格使用 Neovim 文本缓冲区，输入／输出圆角框由 Skia 绘制；交互图表和 HTML 源码/页面双向定位仍需另行设计。Jupyter Book 继续提供独立项目构建流程。


### macOS 后续阶段首版：播放、网页与文档预览

新功能通过系统 AVFoundation/AVKit、WebKit 和 PDFKit 嵌入现有 winit 窗口；无需第二套窗口事件循环。已评估 Wry：其 macOS 后端也使用 WebKit，当前直接桥接已有 NSView 可减少依赖与焦点层级。此部分最低构建目标为 macOS 11，实际验收仅限本机 Apple Silicon/Metal；Windows/Linux 继续保留图片能力，不提供音视频/WebView/PDF 原生后端。

主配置与 `portable/payload/nvim` 同步后可用：

| 入口 | 用途 |
| --- | --- |
| `:GlowMedia /path/file.wav`、`:GlowMedia /path/file.mp4` | 在右侧面板预览音频或视频 |
| `:GlowWeb /path/index.html`、`:GlowWeb https://example.com` | 本地网页或 URL 页面 |
| `:GlowNotebook /path/file.ipynb` | 原生 Python 单元格编辑、运行及保存输出 |
| `:GlowNotebookPreview /path/file.ipynb` | 静态查看 Markdown、公式及已保存富输出 |
| `:GlowPDF /path/file.pdf` | macOS PDFKit 原生 PDF 预览 |
| `:GlowBook /path/project` | 查找项目配置并异步构建 HTML 站点 |
| `:GlowBookLog`、`:GlowBookCancel` | 查看构建日志、取消本模块启动的构建 |
| `:GlowPreviewFocus`、`:GlowPreviewClose` | 进入原生面板、关闭当前 Tab 的预览 |

Neo-tree 的 Enter、双击、分屏和新 Tab 入口继续保留图片预览，并支持上述音视频扩展名、HTML、PDF 与 `.ipynb`；Notebook 默认进入原生编辑。音频入口包含 MP3/M4A/AAC/WAV/AIFF/CAF/FLAC；视频入口包含 MP4/M4V/MOV/MPG/MPEG。实际编码是否可播放由系统解码器决定，文件后缀不构成兼容性保证。

图片预览顶栏使用 VIEW、ZOOM、PAN、CLOSE 胶囊，PDF 顶栏使用 PDF 状态、PAGE、ZOOM、FOCUS、CLOSE 胶囊，仅显示状态和快捷键；文件名沿用底部状态栏。胶囊使用主题配色并适配窄窗口。

Dashboard 最近文件、文件搜索、普通 `:edit` 和缓冲区选择入口也会自动打开图片、PDF、音视频预览，沿用调用方选择的窗口、分屏或标签页。二进制文件通过专门读取事件建立受保护的预览描述，不作为文本加载；已切换到别的文件时，排队中的旧预览不会抢回窗口。HTML 保留源码编辑，Notebook 保留 Jupytext 转换，插件浮窗与特殊缓冲区不参与自动路由。

Neovide 内的 `:Yazi` 也支持右侧原生图像预览。同步目录预览沿用 Yazi 原入口，避免重复同步等待；图片等预览器的运行环境统一接管 `ya.image_show()`，通过 DDS 将源文件、生成的图片缓存和预留绘制区域发送给 Neovim，复用异步图片解码与浮窗图像绘制。因此图片、PDF 页面、SVG、视频缩略图、字体样张、AVIF/HEIC 等原本经过该接口和 chafa 的路径共用同一显示方式；自定义插件调用该接口生成的缩略图也会进入此路径。现有预览器的转换、预加载、缓存、原命令参数和 seek 保留，实际可转换格式取决于相应工具和编解码器。

JPEG XL 使用专用预览器补齐当前 ImageMagick 构建缺少的 JXL 解码能力：`jxlinfo` 检查源文件，`djxl` 后台解码为 PNG，ImageMagick 仅缩放 PNG，再通过同一原生显示接口预览。匹配 `image/jxl` 及大小写混合的 `.jxl` 后缀；缓存按源文件与预览尺寸建立，源文件不被改写。需要 JPEG XL 工具包中的 `djxl`、`jxlinfo` 和已有的 `magick`；本机已有 JPEG XL 0.11.2，无需新增安装。此入口提供 8-bit 静态预览，设置输入、像素、进程内存与转换时间上限，失败时在预览栏反馈。

每次嵌入会话使用私有配置覆盖层，保留有效选项、预览规则顺序、主题、按键、插件和初始化配置，不改写独立终端 Yazi 的配置；退出后清理临时覆盖层。覆盖层使用现有 Python 3.11+ 的标准 TOML 库生成，默认预览规则数据对应 Yazi 26.5.6，原预览器实现仍从 Yazi 动态加载。源文件和缓存路径分别校验，翻页或快速切换后的迟到结果不重新显示。非图片、离开窗口、内部对话框和关闭会隐藏或释放图片。绘制区域优先使用终端真实单元格度量；嵌入 PTY 未提供像素度量时，使用 8×16 参考尺寸预留区域并将同一区域返回预览器、交给 Neovide 裁切绘制，使图片下方文字保持可见；这不构成像素边界完全一致的保证。过时自定义插件自身的 API 或外部命令错误不属于 chafa 显示接口问题。

音视频面板有原生播放/暂停、进度与音量控件。编辑器焦点下 Space 播放/暂停，`h/l` 跳转五秒，`+/-` 调音量，`0` 回到开头，`r` 重新加载，`q`/Esc 关闭。初始暂停；离开 Neovim Tab 即停止并销毁原生播放器，返回时按最近异步反馈的位置重新载入并保持暂停。位置反馈每 500 ms 更新，离开时可能有最多约一个反馈周期的进度差。关闭和编辑器 route 销毁会解除观察器、取消加载、移除子视图并释放播放器。

网页按需创建，右侧分屏尺寸与编辑器字号/缩放变化同步。编辑器焦点下 `i`/Enter 进入网页，`+/-` 调整网页缩放，`0` 复位，`r` 刷新；网页中普通 Tab 保持表单导航，Cmd+Esc 返回编辑器，Ctrl+Tab/Ctrl+Shift+Tab 切换 Neovim Tab。Cmd+A/C/X/V/Z 与 Cmd+Shift+Z 在网页焦点下交给系统编辑动作。Neovim 中保存本地 HTML、CSS、JS/MJS 时，同一目录树中的活动页面刷新；解析真实路径，避免 `/tmp` 与 `/private/tmp` 等别名漏掉保存事件。此首版不监视其他程序的磁盘写入，也不实现源码/页面双向定位。WebKit 使用临时数据存储，关闭释放视图与本模块监听，不保留登录会话。

本地 HTML 的脚本可执行，并可读取该文件实际所在文件夹及其子目录，以加载同目录 CSS／JS／图片；这不是不可信网页的沙箱。读取根目录在创建预览时固定，导航不能将其扩大，路径别名／符号链接按真实目标判断；直接打开的 HTTP(S) 预览没有本地文件夹授权。在预览中按 `g?` 或执行 `:GlowPreviewInfo` 可查看实际来源与读取范围。打开目录外的另一文件需要单独创建预览。请只打开可信的本地网页。

原生网页、音视频和 PDF 面板按所有 Neovim 浮窗的实际区域裁切，并将这些区域的鼠标事件交还编辑器；补全、选择器、菜单等浮窗可以覆盖原生面板并接收点击。该规则按浮窗几何统一处理，不依赖特定插件名称。

PDF 使用系统 PDFKit，提供页码、上一页/下一页、缩放与适应按钮、连续纵向滚动及文本选择。编辑器焦点下 `]p`/`[p` 或 PageDown/PageUp 翻页，`+`/`=`、`-` 缩放，`0` 适应当前面板，`i`/Enter 进入 PDF 焦点，`q`/Esc 关闭；PDF 焦点下可选择文字并用 Cmd+C 复制，正文获得焦点时 `q`/Esc 也直接关闭所属 PDF 面板，页码输入框仍保留正常输入；Cmd+Esc 返回编辑器。Tab 生命周期与其他原生面板一致，关闭释放文档与视图。

原生 PDF 与 TeX 使用真实 SyncTeX 双向定位。TeX 缓冲区中 `:GlowTexForward` 或已有 VimTeX 查看快捷键 `<localleader>lv` 会打开／复用同一 PDF 面板，定位并短暂标记当前源码位置；在 PDF 正文中 `Cmd+单击` 返回对应源文件与行。支持已有 `.synctex` 和 `.synctex.gz`，不自动编译用户文档；VimTeX 编译配置已带 `-synctex=1`。缺少 PDF、映射或命令时显示明确反馈。新构建默认走原生面板，设置 `vim.g.glow_tex_viewer = "skim"` 可继续使用原 Skim 流程；其他 Neovide 构建保留 Skim。跳转查询和 PDF 状态传递均异步，Tab 离开或预览关闭后忽略过期结果。

Notebook 静态入口 `:GlowNotebookPreview` 异步读取上限 32 MiB、4000 单元格，支持 nbformat 4。随配置携带 markdown-it 14.1.0、KaTeX 0.16.22 及字体，可离线查看公式、Markdown 表格、代码、文本/错误、静态 HTML、PNG/SVG 和 Matplotlib 已保存输出。HTML 输出在脚本停用的子框架内显示；此入口仅查看保存内容。保存 `.ipynb` 重新渲染，关闭删除临时 HTML；异步准备完成时不抢走其他 Tab，回到原 Tab 后才首次打开面板。

### Liquid Glass 与透明度接口

macOS 26 及以后使用系统 `NSGlassEffectView`，作为整个 winit／Metal 编辑视图后方的原生材质；早期系统回退 `NSVisualEffectView`。编辑区域和 Neovim 浮窗共用这一窗口基底，内部字体、主题、胶囊和边框继续使用现有 Neovide 风格。PDF／媒体容器不另叠一层玻璃，PDF 页面、网页正文和媒体像素保留自身背景；编辑器切换面板沿用其原生材质。Neovim 浮窗仍由 Skia 绘制，不承诺每个浮窗具有独立的系统折射效果。玻璃层不接收点击，原有编辑器、浮窗和预览焦点层级保留。普通窗口右侧不足一字符的像素余量沿用相邻背景的颜色和 alpha 直接替换绘制，避免半透明背景重复叠加成实心竖带。Notebook 边框外的保留列始终使用普通透明背景，当前行和选区不会延伸到框外。

| 调整 | 命令 |
| --- | --- |
| 开启／关闭／切换材质 | `:GlowGlass on`／`off`／`toggle` |
| 背景不透明度（0 透明，1 不透明） | `:GlowGlass opacity 0.85` |
| 浮窗附加模糊（0～100） | `:GlowGlass blur 24` |
| 恢复配置默认／查看状态 | `:GlowGlass reset`／`status` |

透明度和模糊省略数字时会弹出输入框。透明度命令只淡化普通背景，文字与选中高亮保持清楚；底层仍可独立设置 `g:neovide_opacity`、`g:neovide_normal_opacity`、`g:neovide_floating_blur_amount_x/y`，材质由 `g:neovide_liquid_glass` 开关。新构建配套配置默认开启，普通编辑背景不透明度为 `.78`，Neo-tree 背景以及编辑区／Neo-tree 当前行背景为 `.60`；工具弹窗、菜单、补全、选择器使用不透明的主题底色并取消 backdrop；Avante 侧栏及其内部边框继续使用独立材质；Dashboard 终端动画面板在 Liquid Glass 开启时也使用该透明度，原有主题颜色不变。文字、Visual 选区、实心选中项和胶囊保留原有不透明度，浮窗模糊为 `24/24`；普通浮窗保留阴影，搜索器内部组合面板避免重复叠加子窗口阴影。空闲命令行不预留底部整行，输入命令时按需显示。所有这些 Glass 配套调整仅在 `vim.g.neovide` 前端启用，终端 Neovim 不修改高亮、透明度或字体。Neovide 普通分屏不绘制可见分隔线，分隔格仍保留原位置和鼠标调整大小区域；普通编辑窗口右侧的分隔格沿用该编辑器的 Normal 底色与背景透明度，右侧为 PDF 等不透明内容时不再引入第三种底材；紧邻 Avante 玻璃侧栏的空隙与它的内部间隔延续 Avante 自身材质，Neo-tree 自身分隔格仍沿用侧栏材质。侧栏顶栏按显示列截断和补齐，窄于标题时分隔边界仍与侧栏右缘对齐。显式高亮 `blend` 优先于 Normal 同色背景的默认透明度，避免当前行因颜色相同而退回实心。Apple 未公开玻璃模糊半径参数，`blur` 真实调整的是 Neovide 浮窗的附加模糊，系统玻璃由 macOS 管理。[Apple NSGlassEffectView 文档](https://developer.apple.com/documentation/appkit/nsglasseffectview)。

### 原生 Notebook 编辑与执行

`:GlowNotebook` 在真正的 Neovim Python 缓冲区中编辑 `.ipynb`，沿用现有字体、主题、光标、补全与快捷键。Jupytext 使用 `# %%` 和 `# %% [markdown]` 表示代码及 Markdown 单元格，Molten 负责连接 Jupyter 内核、异步执行和显示输出。没有输出时，单元格由 Skia 使用主题 `base0D` 绘制完整圆角框；有输出时，上方输入段保持冰蓝色，下方输出段使用主题 `vibrant_green`，两段在直角接榫处共用一条绿色横线；横线位于独立虚拟空行中央，与末行代码和首行输出留出间距，外侧顶部和底部保留圆角，当前单元格描边加重。输入留白使用本模块的虚拟行，Molten 输出由其自身独占写入，保留真实源码和输出内容；框线跟随正文的同一滚动动画，并按分屏和浮窗层级裁切。顶部序列化元数据默认隐藏，可用 `:GlowNotebookMetadata` 显示。单元格顶边最右侧固定放置仅含 Markdown／语言图标的实心胶囊，图标单独放大至 1.2 倍；代码格的分段运行胶囊放在它左侧，左段显示空心播放图标，右段显示无括号的 Shift／Return 图标，真实运行时播放图标切为实心。四个运行／按键图标选自本机 FiraCode Nerd Font 中与胶囊端帽中线一致的同一套字形，避免字体回退造成垂直偏位。胶囊的外侧半圆直接衔接内容，不另加左右空格；胶囊之间由同色顶边线连接，输入框线与实心胶囊共用同一个强调色，右侧保留一格空隙；正文网格独立收窄两列，让长中文、代码和输出在框内实际换行，分栏宿主宽度与相邻窗口不变，离开 Notebook 后恢复完整正文宽度；普通描边至少与 UI 字符线同为 2 像素，当前单元格略加重。顶栏仅保留 KERNEL、CELLS、MENU 三域，每个胶囊内统一强调色，深浅主题使用对应底色；实心区域文字与底部模式图标使用同一前景色规则。未选择内核时以放大镜提示 ` ␣jk`，停止和启动中状态分别用 `■`、`◌` 表示并保留内核名称；功能入口显示 `␣j`，CELLS 域使用主题 `base0B`，上下格用 `↑ [c` 和 `↓ ]c`。状态栏左侧保留一格留白。Markdown 单元格使用原生 Neovim 高亮与 conceal 显示标题、粗斜体、列表、链接、行内和围栏代码；Insert／Visual 模式仅显露当前单元格的 Markdown 标记，外层 Jupytext 注释前缀始终隐藏；行首退格和行尾删除按可见文本合并行，保持存储前缀正确。退出后恢复渲染，Shift+Enter 可提交 Markdown 渲染而不启动内核。渲染变化会重新测量边框，普通 Python 文件不受影响。字体缺少真正斜体时，仅对字形合成倾斜；真实斜体和普通文本保持原样，字符网格与背景不倾斜。Neovim conceal 仍按隐藏源码计算部分换行，长链接末尾可能提前折行；当前保留原地编辑，不启用独立显示层。公式、复杂 HTML 和完整表格排版仍通过 `:GlowNotebookPreview` 查看。

依赖固定为 Molten [`bedea63819c618e007e7c40059fc6e72d598c8df`](https://github.com/benlubas/molten-nvim/commit/bedea63819c618e007e7c40059fc6e72d598c8df) 和 Jupytext.nvim [`c8baf3ad344c59b3abd461ecc17fc16ec44d0f7b`](https://github.com/GCBallesteros/jupytext.nvim/commit/c8baf3ad344c59b3abd461ecc17fc16ec44d0f7b)。配套 `config/media/runtime/install.sh` 安装固定 Python 依赖至 Neovim 数据目录下的 `glow-notebook-venv`，并注册独立的 `glow-python` 内核；本机路径为 `~/.local/share/nvim/glow-notebook-venv`。既有全局/Conda 环境及 `python3` 内核不被覆盖；显式配置的 Python provider 保持优先。配置只新增这两项插件固定版本，保留原插件锁的其他条目。

打开文件或内核选择器不启动内核；确认选择或首次运行时启动，并异步等待 `MoltenKernelReady` 后导入保存输出、执行请求；等待期间仍可编辑，若代码已改变会要求重新运行。打开文件本身不执行代码。`:w` 将代码写回原 `.ipynb`，并保存已产生的新输出；转换使用私有缓存，不覆盖或删除同名 `.py` 文件。输出保存需要已有 Python Treesitter 解析器。内联文本输出可直接用鼠标拖选，松开即复制到系统剪贴板并保留选区，也可用 `⌘C`／原生 Copy／`Ctrl+Shift+C` 再次复制；选择范围限制在同一个输出框内，不包含行号和框外空白。拖选期间真实输出内容、滚动或布局变化会取消该次选择，避免复制错位内容；相同内容的后台刷新保留选择。行内图片根据真实字体单元格像素占位，默认保持原始分辨率，只有空间不足时缩小；图片与边框共享同次布局和滚动锚点。切换文件、隐藏缓冲区或离开 Neovim Tab 均保留内核、变量和未保存输出；真正删除／卸载 Notebook 缓冲区时才进入 Molten 的内核释放流程。

`<leader>j` 是 Notebook 快捷键分组，保留普通 Neovim 的 `a/b/m/y/dd` 行为。无参数 `:GlowNotebookKernel` 与 `<leader>jk` 打开真实 Python 内核选择器，显示环境名称和解释器路径；包括已安装 ipykernel 的 Conda 环境。取消不启动内核。切换本入口拥有的内核会暂存并恢复完成输出，不自动保存源文件；手动或共享内核不自动替换。已有 `<localleader>n` 快捷键继续可用。

| 操作 | 快捷键 | 命令 |
| --- | --- | --- |
| 选择内核 | `<leader>jk` | `:GlowNotebookKernel` |
| 运行当前单元格 | `<leader>jr`、Shift+Enter | `:GlowNotebookRun` |
| 运行全部代码 | `<leader>jA` | `:GlowNotebookRunAll` |
| 查看输出浮窗 | `<leader>jo` | `:GlowNotebookOutput` |
| 中断／重启内核 | `<leader>ji`／`<leader>j00` | `:GlowNotebookInterrupt`／`:GlowNotebookRestart` |
| 上方／下方新增代码格 | `<leader>ja`／`<leader>jb` | 下方也可 `:GlowNotebookAddCode` |
| 下方新增 Markdown 格 | `<leader>jM` | `:GlowNotebookAddMarkdown` |
| 当前格转 Markdown／代码 | `<leader>jm`／`<leader>jy` | `:GlowNotebookMarkdown`／`:GlowNotebookCode` |
| 删除当前格及其输出 | `<leader>jdd` | `:GlowNotebookDeleteCell` |
| 上一个／下一个单元格 | `[c`／`]c` | — |
| 保存代码及完成输出 | `:w` | — |

非空单元格的 `# %%` 标记行仅在界面隐藏，文件中的分格标记仍保留；单元格跳转定位正文首行，空单元格保留可编辑行。删除源码可用普通 `u` 撤销，已删除的运行输出不随源码撤销恢复。
文本结果和错误在代码下方以原生虚拟文字显示；Molten 标注排队、运行、完成或失败状态。`Out[n]` 编号使用主题强调色，完成状态为绿色，失败状态和错误正文为红色，运行中使用警示色，普通结果保持正文色，切换主题后同步。适配固定版 Molten 的单次输出写入，在其原请求中生成不同高亮片段，不轮询或二次改写现有输出标记；原始文字、输出高度和内核生命周期不变。Python 适配需要新编辑器会话；上游输出方法版本不匹配时明确报错并保留原输出。PNG/Matplotlib 静态图表直接显示在绿色行内输出区，保留 `:GlowNotebookOutput` 浮窗查看；有界解码和独立虚拟留白不改写 Molten 文本输出，图片与边框使用同一个原生滚动锚点，并裁切到所属窗口、避开上层浮窗。旧构建不具备图像锚点能力时继续使用输出浮窗。该适配不替换其他插件的 `image.nvim` 实现，也不承诺交互图表、网页控件或任意 Jupyter 富输出均可原生显示。保存的文本、结果、错误和 PNG 在打开文件时即由同一 Molten 排版链显示，保留原 Out[n] 和 traceback；不会启动内核或执行代码，连接真实内核并成功导入后由其接管，避免重复。当前编辑执行流程以 Python 验收，其他语言内核未验收。

### Jupyter Book 与首版验收记录

2026-10-19，Codex：运行、流式更新或清除输出会将 Notebook 标为未保存，不往源码插入额外文本。`:w` 保存源码与输出，成功后清除标记；导出失败会保留未保存状态并阻止 `:wq` 退出。保存的结果、错误、PNG 与 execution_count 在关闭后重开时直接显示；强制放弃未保存内容仍遵循 Neovim 的 `!` 语义。静态输出绑定原源码位置，编辑后隐藏已过时的展示，避免把旧输出挂到新单元格；重复源码通过明确位置校验导出，不串用其他格结果。该 Python 适配需新编辑器会话，现有用户 host 未热重载。

本轮真实回归：`tab_history.py` 比较切换前后的原始输出／完整 traceback／计数与变量；`saved_outputs.py` 验证不执行源码的四类输出显示、图像字节、重开／插入／编辑与真实内核接管；`output_dirty.py` 验证流式更新／隐藏／单删／全删／重复源码、保存失败与正常写入；既有 `persistence.py`、`kernel_preserve_outputs.py`、`load_swap.py` 均通过。独立 GUI 已查看无内核的 Out[7/8/9]、错误及 PNG，文件未改、测试代码未运行。

Jupyter Book 使用选定环境中的真实命令，并按该项目配置构建；与单文件 Notebook 查看分别实现。传统 `_config.yml` 使用 `jupyter-book build`，`myst.yml` 使用 `jupyter book build --html`。找不到命令时给出反馈，不自动修改用户 Python 环境；也可通过 `require("config.media.book").open(path, { builder = { ... } })` 传入环境启动命令的参数数组。重建成功才刷新已有站点，失败保留原站点并显示日志；首版通过再次执行入口重建，不承诺自动监视整个项目。取消只向本模块启动的构建进程发送 SIGTERM，不保证终止项目自行派生的长期进程。现代 MyST 参数与常见产物路径已接入，但未进行真实 MyST 工具链验收。

2026-10-18 播放、网页与静态文档首版验收（历史记录）：

- Rust release 构建、协议边界检查、分屏生命周期测试及 Notebook/Book 的 38 项针对性断言通过；插件锁不变。音频 AppKit 检查覆盖异步准备、播放时钟、暂停、跳转、音量、错误、加载中关闭与释放。WebKit 检查覆盖 CSS/JS、子框架输出、错误、焦点、缩放、坐标及释放。
- H.264/AAC 原生视频测试在跳转前后采样 85 帧，解码帧时间戳与同一 AVPlayer 时钟最大偏差约 11 ms；4.25 s 跳转、音视频轨启用、首帧和关闭释放通过。播放检查静音进行，不能作为外部扬声器/显示延迟或主观口型同步的测量。
- 独立开发应用实际 GUI 检查了原生音视频画面与控件、缺失文件反馈、Tab 离开/返回、网页 HTML/CSS/JS 保存刷新、分屏尺寸/缩放、按钮、中文粘贴、系统输入法键入并提交“你好”、页面焦点下 Ctrl+Tab 和 Cmd+Esc。Notebook 公式、Markdown/HTML 表格、真实 Matplotlib PNG/SVG 已在 WKWebView 中查看；没有重复此前图片/柔光全量验收。
- 在隔离环境中使用官方 Jupyter Book 1.0.4.post1 实际构建、修改内容后重建刷新、非法目录配置失败；构建站点另在开发应用中打开。用户既有 Python 环境未升级。未据此宣称现代 MyST、Windows/Linux 或所有媒体编解码器已验收。

开发应用继续使用 `target/Neovide Glow Images.app`；没有覆盖 `/Applications/Neovide.app`、gm2 发行包、冻结标签或图标资源。源码和配套配置均应保留；原生预览 RPC 是 `neovide.preview.open/show/action/close` 通知，状态通过异步 Lua 回调送达，没有新增同步 Neovim 查询。

2026-10-18 原生 Notebook 与 PDF 增量验收：

- Apple Silicon release 构建及图片相关 9 项 release 测试通过，包含输出浮窗图像独立绘制和柔光排除；PDFKit 与统一原生浮层检查覆盖加载、翻页、缩放、关闭竞态、裁切合成及点击穿透。
- 真实隔离 `glow-python` 内核自动检查通过：异步运行得到 `42`、显示 `ValueError`、保存新输出及执行计数回 `.ipynb`、关闭后内核释放。运行期间编辑器仍响应；Jupytext 检查覆盖特殊字符路径、私有缓存、同名 Python 文件保护、保存输出保留及磁盘内容重新加载。图表生成与原生图片加载通知已检查。
- 独立开发应用中的 PDFKit 实际 GUI 检查通过：文档显示、翻页、缩放，以及覆盖 PDF 的 Neovim 浮窗显示和点击。其他原生面板继续使用统一的浮窗裁切与鼠标穿透实现。
- 独立开发应用中实际查看了完整的 Matplotlib 原生输出浮窗图像，保存后重新打开可恢复图像。静态 Notebook 的 WKWebView 上方，右侧菜单和跨越右侧面板的悬浮终端均完整覆盖；实际点击右侧终端区域可将焦点从源码窗口切换到终端，关闭两个浮窗后网页完整恢复。
- GUI 验收限本机 macOS/Metal。Windows/Linux、其他 Notebook 内核及交互图表未验收；本轮没有重复已通过的图片、柔光和音视频全量检查。

Dashboard 通用入口增量检查：实际从 Dashboard 最近文件及 Find File 搜索选择 PDF 后均显示原生文档。针对性检查覆盖 `:edit`、`bufadd`/`:buffer`、大小写扩展名、空格与特殊字符路径、原始文件写保护、标签页、过期排队请求，以及 HTML/Notebook 源码读取保留。

Yazi 增量检查：在现有 Yazi 26.5.6 和固定 yazi.nvim 下，真实事件检查通过预览区域、特殊字符文件名、切换图片、非图片清理、内部重命名对话框隐藏/恢复、关闭释放与私有配置清理。独立 Neovide 测试窗口实际显示两张图片，并检查切换、重命名对话框、非图片文本及退出恢复；Apple Silicon release 构建通过。本机与 portable 配置已同步，未更改插件锁或独立终端 Yazi 配置。

Yazi 公共图片接口增量检查：真实 Yazi 后台预览通过 PNG、PDF、SVG、视频、字体、AVIF，以及带参数、自行缓存且提前保存函数别名的自定义插件；检查 PDF 原 seek 切换页面缓存、源文件与缓存分离、实际元信息文字位于图像预留区域下方。独立 Neovide GUI 实际查看了 PDF 页面及翻页、SVG、视频静态缩略图、字体样张、AVIF，切回文本及退出没有残留图片。本轮只修改 Lua/Python 配置，不重复 Rust 全量构建或此前图像测试；视频 seek 保留上游的整秒取整与关键帧选择行为。

JPEG XL 增量检查：使用 JPEG XL 0.11.2 真实生成 JXL，RGBA 无损逐像素往返通过；真实 Yazi 检查通过 MIME、混合大小写和特殊字符路径、受限尺寸 PNG 缓存、缓存复用、损坏文件反馈、切换释放与退出清理。独立 Neovide GUI 中实际显示了 1024×1024 RGB+Alpha JPEG XL 文件。本机与 portable 配置同步，不替换全局 ImageMagick 或安装新依赖。

2026-10-18 Notebook 卡片、内核与 SyncTeX 增量检查：

- 真实 Python 内核选择／取消、Conda base 解释器、切换保留完成输出、单元格增删转换、源码撤销及保存重开通过组合检查。普通 `a/b/m/y/dd` 保留；实际 Snacks 选择器和逐键导航／运行通过，缺少说明的旧 Python 映射补充了可读描述。
- Notebook 原生框协议边界、透明圆角绘制和浮窗裁切测试通过；真实 Neovim UI 几何检查覆盖虚拟留白、输出及源码不变、元数据隐藏／显示、编辑和 Tab 生命周期。独立 GUI 实际查看暖色输入、冷色文本／错误输出、Conda base 返回 42、浅深背景和长输出滚动。
- 真实 TeX 编译样例的 SyncTeX／VimTeX 正反向链路通过，覆盖 included 源文件、独立 build 目录和空格／单引号路径。原生 PDFKit 检查覆盖加载前排队定位、短暂标记、裁切／旋转坐标往返、实际 PDFKit 子视图的 Cmd 点击分发及关闭。
- Liquid Glass 定向检查覆盖实际系统原生类、Metal 下方层级、焦点与点击穿透、尺寸变化、开关恢复、后建预览容器，以及旧材质 fallback 的构造。旧 macOS 未实机验收；系统玻璃模糊半径未提供可调承诺。

合并版实际 GUI 已检查 TeX 正向打开 PDF、Cmd 点击由 PDF 返回 included 源文件第 3 行；Liquid Glass 开／关、背景不透明度 0.3、浮窗模糊 12 及恢复默认的接口已操作，PDF 页保留可读背景，状态栏两格左留白可见。

Notebook 滚动与闪烁增量修复：框线采用实际窗口的同一滚动计数和弹簧像素变换，覆盖正向、反向和动画中途反转。录屏中的周期跳动源于两个定时器交替重写 Molten 虚拟输出，导致行高在原值和额外两行间切换；UI 现只读 Molten marks，等高内容更新及 mark ID 重建不再重置框线布局。真实 Molten NEW／RUNNING 各连续渲染 6 次保持行高、mark 内容和布局 epoch 不变，实际新增输出行才更新布局。合并运行状态检查覆盖排队、运行、完成、错误及打印伪状态文字；独立 GUI 检查了深浅主题胶囊、隐藏标记后的代码首行、返回 42、翻页滚动与 Matplotlib 浮窗边框。本轮未重复其他媒体与 PDF 全量检查。

顶边胶囊增量检查：类型胶囊仅保留图标，运行胶囊左侧实心播放符号、右侧为主题底色快捷键；两个独立顶边断口之间保留连接线，边框与胶囊共用 RGB。Rust 定向像素检查通过 2px 实色描边、双断口连线和底边完整；真实 GUI 已检查浅深主题的顶边嵌入效果。相同元数据行数的缓冲区整段重载会重新定位隐藏标记，针对性回归通过。

界面图标字形检查：Mason 的待安装／未安装符号、Neo-tree 删除图标、which-key 分隔符改为当前 FiraCode Nerd Font 直接覆盖且轮廓中线一致的 Material Design 字形。运行控件也使用同套空心／实心播放、Shift、Return 图标，去掉快捷键括号；类型胶囊固定在最右侧，Python／Markdown 图标仅在该高亮区域内放大 20%，运行图标、端帽和源码字号不变。实心胶囊的文字／图标前景色复用底部状态栏图标的主题规则，深色为深色字形、浅色为浅色字形。

2026-10-19，Codex，发布页部署（`claude-note-005`）：

- `showcase/main` 提交 `61f9c70`，仅纳入新版 `dist/index.html` 及两张 `window-*.webp`；原型和致谢草稿留本地，以 `.git/info/exclude` 排除。
- 沿用 Sites 发布流程完成第 13 版，部署返回 `succeeded`；线上地址为 https://neovide-glow.windygrass17.chatgpt.site 。实际浏览器已确认新版页面、全部页面图片加载及深色首屏。
- 源码默认深色，保留手动主题选择；本轮未重复 Claude 的响应式检查或追加 Safari／真机验收。命令行直接核对内容的请求返回 403，改用实际浏览器确认。
