# Glow 维护验证

统一入口为 `python3 tests/validate.py`，可以从任意目录调用脚本。默认只运行 13 个 headless Lua 检查；需要已安装的 Python 3 和 Neovim 0.12+。它不安装依赖、不联网、不打开 GUI、不启动 Notebook 内核。Book 生命周期使用仓库内的假 builder，通过当前 Python 解释器启动。

```sh
# 默认检查 portable；两份配置均验证时显式选择，配置只读，不同步或覆盖文件。
python3 tests/validate.py
python3 tests/validate.py --config local --config portable
python3 tests/validate.py --config /path/to/nvim --nvim /path/to/nvim-binary

# Rust 使用已有工具链与依赖缓存，不安装程序；Cargo 使用 --locked --offline。
python3 tests/validate.py rust --target aarch64-apple-darwin
python3 tests/validate.py rust --rust-filter image_preview \
  --rust-filter notebook_icon_highlights_enlarge_only_type_foreground_by_twenty_percent
python3 tests/validate.py all --config local --config portable --clippy
```

每个 Lua 检查都有独立配置、数据、状态和缓存临时目录；`-u NONE`、`--noplugin`、`-i NONE` 禁用用户初始化、插件和 ShaDa。runtimepath 只保留指定配置与 Neovim 自带运行库，因此 portable 缺文件不会回落到本机配置而假通过。`--config local` 使用 XDG 配置路径（Windows 为 LOCALAPPDATA），也可直接传入配置根目录。单项检查失败立即退出非零；默认每项限时 60 秒，可用 `--timeout` 调整。

Rust 套件先检查格式，再运行 release 测试；`--rust-filter` 可重复，适合只验证本次改动。运行前确认共享 `target/` 没有其他构建。首次构建需要预备依赖和 Skia 缓存，Cargo 离线模式不代替第三方构建脚本的联网隔离。`--clippy` 仅使用已安装的组件。Notebook 图标像素回归在 macOS 上使用仓库内嵌 FiraCode Nerd Font，不要求系统另装字体；Unix FIFO 回归使用系统的 `mkfifo` 工具。

默认套件中的 `popup_materials.lua` 使用真实隔离浮窗检查浅深底色、逐类 editor/custom/opaque 切换、当前行／选区、namespace 样式及重复重载、明确遮罩移除，并保护主编辑区、底栏／WinBar／TabLine、Dashboard 和终端前端。

`notebook/output_scroll.lua` 检查实时与保存输出一次聚焦、原地展开、横纵滚动、语义高亮、选择复制及关闭返回，保护源码和原始内联输出。`tests/media/notebook_footer.py` 需要现有 pynvim，以隔离附加 UI 检查溢出提示的条件、端点及布局生命周期；它不证明 Neovide 像素效果。

## 需要显式准备的检查

胶囊检查覆盖状态栏模式／信息块、Avante 三类标题、媒体控件及 Notebook 顶栏／类型／运行胶囊的浅深主题。`capsule_backgrounds.lua` 检查终端端帽背景、主体颜色保留及 Neovide 隔离；既有 `image_title.lua` 和 `title_capsules.lua` 检查其余端帽、分段、宽度和主题重载。终端修正只去掉端帽的矩形背景，继承所在栏的底材，不改变主题调色板。

真实 GUI 图片检查：用已有 Notebook venv Python 运行 `tests/media/gui_maintenance.py --binary /path/to/development/neovide --work-dir /tmp/a-fresh-glow-check --keep-open`。需要现有的 pynvim、Pillow、Yazi 及固定插件；仅启动独立 Neovim 和指定开发 GUI，实际异步回调驱动断言，观察器保留原始处理。`state.json` 保存结果，创建 `stop` 文件可结束持有窗口。界面截图和按键操作另行检查，不能把 RPC 成功等同于像素验收。

本机已安装现有 stable 工具链匹配的 clippy，未升级 Rust 或依赖；2026-10-19 已通过 `cargo clippy --release --all-targets --locked --offline --target aarch64-apple-darwin -- -D warnings`。

随包字体与安装保护使用 `python3 tests/portable_fonts.py`：校验真实字体／许可哈希与平台选择，在临时用户目录安装并检查重复运行、同名冲突及损坏资源拒绝。它不安装本机字体，不调用 Windows 字体 API。打包脚本也会在生成文件前校验 `payload/fonts/fonts.json`；Windows 安装部分仍需 PowerShell 和真实 Windows 验收。

| 范围 | 入口和前提 |
| --- | --- |
| Metal 柔光像素 | 真实 macOS GPU；`cargo test --release --locked --offline renderer::bloom_tests -- --include-ignored`。默认 Rust 套件不执行此忽略项。 |
| 真正的 Jupyter Book 构建 | `tests/media/book_integration.lua`；先准备隔离 builder，以 `GLOW_BOOK_BUILDER_JSON` 传入参数数组，再用 `nvim --headless -u NONE -l tests/media/book_integration.lua`。可用 `GLOW_TEST_CONFIG` 选配置。它实际构建并保留输出，不属于默认套件。 |
| Notebook 执行及保存 | `tests/notebook/*.py`、`tests/notebook_runtime.py`；需要对应固定插件、Python provider、pynvim 和可用 Jupyter 内核，按文件头准备。 |
| 原生媒体、PDF、玻璃和 GUI | `tests/media/*.m`、`tests/native_*.m` 及其余 Python UI 脚本；按文件头使用开发 App、真实 macOS 框架或 Neovim UI。不要替换已安装 App。 |

`tests/notebook/hot_load_guard.lua` 是已有会话的热修补工具，会替换函数并保留会话状态，没有断言，故不作为测试执行。默认 headless 检查只验证 Lua 协议、状态与生命周期；不能据此宣称 GUI、真实内核、Windows/Linux 或真机交互已验收。

## CI 范围

`Build and Test` 的自动触发条件为 PR 和 `main` 推送，另已有 `workflow_dispatch`，可选择远端分支手动运行；直接推送 `glow-preview` 不会自动构建。现有流程含 Windows/macOS/Linux × stable/nightly 的 Rust 测试与独立 clippy job，`Lint App` 可复用流程本身只做 rustfmt。已增加三平台 configuration job，使用 Python 3.12／Neovim 0.12.3 执行 portable headless、随包字体与锁定依赖许可检查；当前未推送代码尚未在远端运行。

2026-10-19 对个人 fork `Ysrae1/neovide` 的 GitHub Actions API 只读查询返回 `total_count=0`；表示当前可见保留记录中无运行，不能推断历史上从未运行。上述平台矩阵是流程能力，未作为当前未推送代码的通过证据。

网页读取边界使用 `tests/media/web-smoke.m`（按文件头编译）：真实 WebKit 验证同目录 CSS／JS、目录外导航拒绝、符号链接路径判断和可查询的 read_root。不会打开用户会话。Notebook 切换历史使用现有 venv Python 运行 `tests/notebook/tab_history.py`：真实内核、两个临时 Notebook，逐项比较切换前后原始结果／完整 traceback／execution_count，并验证变量保留与关闭释放。可用 `GLOW_TEST_CONFIG` 选本机配置。

Notebook 无内核恢复和保存保护分别使用现有 venv Python 运行 `tests/notebook/saved_outputs.py`、`tests/notebook/output_dirty.py`，可用 `GLOW_TEST_CONFIG` 选择配置。前者不运行测试文件源码，另会显式启动隔离内核验证接管；后者实际执行临时流式结果／错误并写回临时文件，验证 dirty、失败退出保护、重复源码和清除输出。均只操作自有临时 Notebook／内核。已配置的 Python provider 必须在新 Neovim 会话加载更新。

冻结安装的 Notebook 准备检查：`python3 tests/portable_notebook_runtime.py` 使用临时目录和假安装命令验证新建、重复运行、中断恢复及已有环境保护，不安装依赖或启动内核。`tests/media/theme_refresh.lua` 需要现有 Base46／FFF／Noice／Lazy／Mason／WhichKey 及其依赖源码，用隔离缓存验证模式相关颜色、缓存修复、延迟加载、集中弹窗调色和通知／代码预览 namespace 隔离；按文件头运行，不属于无依赖默认套件。
