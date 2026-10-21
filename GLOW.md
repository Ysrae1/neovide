# Neovide Glow Preview

基于 [neovide/neovide](https://github.com/neovide/neovide) 的实验分支 `glow-preview`，加入可调节的柔光效果。保留上游 MIT 许可证。这是第三方分支，尚未合入官方版本；本轮 Mac 预览包采用 ad-hoc 签名，未做 Apple 公证。

## 当前维护状态

> 2026-10-22，Codex 整合更新。仅本节表示当前状态；下方历史记录保留当时结论。状态依据实际回执，不将源码／协议检查写成实际界面验收。用户本轮明确恢复 Windows 未闭合范围；2026-10-21 停止／归档记录仍作历史保留，Linux 原生开发继续暂缓。

- 已安装Mac为 `nightly-139+g955e75f`，Mac菜单及PDF真实界面验收、runtime签名／安装已完成。Windows配置迁移已完成，Mac80%／Windows60%默认缩放、用户主题与未保存内容保留；后续Windows增量按下表分别交付。
- Windows Telescope 已独立通过并部署；拖窗 `f5e1e78` 本轮完成 Windows 构建、原生合成鼠标端到端验收及下次桌面启动部署。实体硬件输入与首帧仍未验，安装器及其他本轮增量见下节；既有独立交付结论保留。
- 既有冻结版 `glow-stack-20261020-gm1` 保留；Mac 预览 [`glow-macos-20261021-preview1`](https://github.com/Ysrae1/neovide/releases/tag/glow-macos-20261021-preview1)／网站第17版不变。新 Windows 精简包本轮完成构建及基础安装／卸载验收，公开下载入口仍未开放；TeX 真实登录用户父入口已在后续授权下通过，实体输入与首帧仍未验。旧 Candidate5／Core94 不作为新包通过凭据。

### 2026-10-22 Windows 恢复与收敛（Codex）

本节证据根：`target/glow-windows-20261022/`。本轮未修改产品源码；已保存原失败与中间状态，由下列最终收据限定通过范围。

- 用户再次明确拖窗范围：顶部 tab 栏中，所有可见 buffer 标签右侧至最右侧组件组左侧之间的空白；标签、标签内部空格与右侧组件不拖窗。真实 Neovim local／portable 各 4 场景、共 840 格点击路由通过，含标签溢出、当前标签及右组件宽度变化；`target/glow-windows-20261022/drag/precise-gap-routing.json`。本轮未改产品源码，不重做已通过的媒体／Telescope 专项。
- `f5e1e78ff64637b2f11be5a169a029dce7a5f107` 的 Windows x64 release 构建完成，实际 EXE SHA256 `4bc2e4205c1eafb002788b409deb9ff2cfda41c0ab5393a6d3c7891530675066`。先在登录用户自建标准窗口校准 192 DPI／按住／移动／松开，再由真实 tabline callback 发 column 81 请求：根网格 press → 4ms 接受 → native move loop，窗口实际移动 80×40；随后标签切换与编辑区点击通过。自有进程及按住状态已清理，用户配置未被测试修改。收据 `drag/{build/receipt.json,input-calibration.json,acceptance.json}`；这是原生合成输入，不冒称实体鼠标或像素首帧通过。
- 拖窗已向现有 Windows 桌面入口作并排部署：`C:\GlowDev\GraphicsQA\Drag96Hardware20261022`，原 PdfNav92 程序与快捷方式备份保留，launcher 检查 exit0；只新增 `window_drag.lua` 和 chadrc 一行 setup，既有 Telescope 三模块、主题和其他内容保留，未热载／重启编辑器。`drag/{deployment.json,config-deployment.json}` 均为 `deployed_next_launch`；终端里既有硬编码 PdfNav92 入口未在本步改写。
- 原生合成输入专项已通过：选择／删除／撤销／重做、注释往返、插入／Ctrl+S 磁盘保存；WebView2 child 获焦后第一下 Escape 回编辑器并保留 PDF，第二下关闭预览；单次 Alt 拖选真实调用 press／drag／release，并保留第二行 bytes 0–4 选区。统一收据 `acceptance/native-input-acceptance.json` 绑定同一 96 EXE、三份独立执行与 10 个已验配置 SHA。实体硬件与首帧未验；首次孤立 pipe 断开原因未追定，不用后续通过追认其原因。
- 验收探针修正：单窗口关闭预览按现行设计 `enew()`，要求恢复原 buffer 的断言不成立；RPC ready 不等于可见大 HWND ready；校准普通点击紧接 Alt 按下会被识别成双击，必须分开手势；原生 termcode 诊断含非 UTF-8 字节，JSON 应转义导出。上述问题均在辅助层修正，未据此改产品、强制插件状态或重跑已通过的键盘／PDF；最后真实单次 Alt 手势与原始失败材料均保留。
- 新包 `glow-windows-core-20261022-preview1`：94,629,776 字节，SHA256 `94dc384afa102666064f5616551b781d148b019a660c5dc80ff024df95ae1b50`；复用并核对 12,606 个 stage 文件，只换准确绑定的 96 前端，媒体四新 SHA、Telescope／语言共 10 文件及后续安装器修复均实装核对。登录用户／session1 的默认与中文／空格／撇号路径、启动、完整配置、清单／运行时剔除及卸载共 10 项 passed，逐文件保留 10,439 个验收 profile 文件；`installer/{stage-resume-receipt.json,build-receipt.json,install-progress.json,final-receipt.json}`。已导出同 SHA 至 `installer/artifacts/Neovide-Glow-2026.10.22.1-Windows-x64-Core-Setup.exe`，`export-receipt.json` passed。可选依赖安装在基础包验收中跳过，不能据此宣称 TeX 流程通过；未发布或替换旧发行包。
- TeX 仍未闭合：SYSTEM 下父入口成功不代表登录用户通过。实际登录用户的同参数中文 fixture 窄编译 5.38 秒 exit0／drained，并生成 PDF／SyncTeX；真实 TeX-only 父入口却在原生 Perl 启动后、XeLaTeX 启动前停滞。一次 fresh 父入口 80 秒有界停止；仅换字节流输出 reader 的隔离实验 45 秒仍失败，未将该候选合入产品。stdin 假设也缺依据，成功窄编译同样继承 stdin。`tex-diagnostic/receipt.json` 与 `copy-reader-receipt.json` 保留断点／失败，任务和已知自有进程已清理，用户选择与 QA science 字段保留，零下载／新装。下一动作是比较真实父入口与单独编译的调用上下文，不重复 Python／完整安装或增加超时。
- 策略变化：先校准控制面和实际登录身份；复用原证据，只补真实断点；TeX 正确性与封包并行。CUA 输入返回 `noWindowsAvailable` 后停止重试，用户明确允许隔离窗口 SendInput 后才继续。封包辅助层的 stderr、换行、UTF-8 和收尾变量问题按实际阶段恢复，未反复重编／压缩或安装。用户要求无需其协助的部分结束后暂停，不设 standby、自动唤醒或常驻监控。
- 本轮已停止：GUI／编译／安装验收自有进程已结束，本轮创建的无触发器任务已移除（`installer/cleanup.json`、`tex-diagnostic/*cleanup.json`）；保留实际包、失败材料与回滚入口，不强停历史身份不明进程。后续需本人在场的是实体键鼠体验与明确首帧场景；TeX 父入口另属未闭合的调用上下文问题，未写成“只等用户操作”或整体完成。

### 2026-10-22 TeX、VS Code 与 Windows 软件维护（新增授权，Codex）

- 用户恢复 TeX 修复后，新增唯一验收入口 `tests/windows_latex_parent.ps1`，直接调用未修改的产品 `Setup-Dependencies.ps1 -InstallLatex`；实际登录用户 session1、含中文／空格／单引号的路径、原 180 秒编译期限，整体验收 12.52 秒。两原生子进程 exit0 且输出完整关闭，中文 PDF 43,900 字节、SyncTeX 3,787 字节，分别确认正文中文及源路径映射；用户选择与既有科学字段保留，零下载／新装／Python 导入。证据 `target/glow-windows-20261022/tex-fix-20261022/{receipt.json,final-evidence/receipt.json,final-products.json,cleanup.json}`；自有 PID 已退出、未建计划任务，无需重封精简包。
- 精确捕获的父入口环境、原 `Invoke-DependencyProcess`、前置检测、transcript 与 progress 均分别通过。旧嵌套并重定向输出的 PowerShell 监督包装仍是失败／通过间的执行边界，内部停滞机理未确认；没有为旧验收包装猜测性修改产品。上节 `tex-diagnostic` 的失败保留历史含义，不再代表当前真实父入口未通过。
- Mac VS Code 共同设置由 8 项扩为 21 项，Windows 加两项 XeLaTeX 工具／配方共 23 项；实际补齐 9 个设置，8 条快捷键及 16 个 LaTeX 片段已一致。Mac 专用路径、终端环境及 Windows 的外观共享范围保留本机语义；Mac 配置无改动。源仓库 `~/Dev/workstation-config` 提交 `86dba49`，仅含两份本轮源配置；未提交其既有其他改动。Windows 两次本机事务均保存原始备份，三项同步审计通过，证据 `target/glow-vscode-sync-20261022/{config-receipt.json,settings-cleanup-receipt.json}`。
- 按用户要求对照 Mac，Windows 扩展 54→41，卸载 13 项并清理其 17 个闲置设置键；卸载时 41 个保留项版本不变、依赖齐全，Mac 独有项未新增。官方 CLI 卸载与最终元数据通过，精确旧版本和恢复命令见 `target/glow-vscode-extensions-audit-20261022/uninstall-result.json`。用户随后保存退出 VS Code；官方 ARM64 包 SHA 与 Microsoft 签名核对后，1.142.0→1.143.0 安装 exit0，三配置 SHA 前后一致，未强停或自动重开编辑器。证据 `target/glow-vscode-sync-20261022/update-receipt.json`。
- 用户随后授权原软件清单全部更新及移除 Classic Teams。15 条候选最终为 13 项实际更新、Oh My Posh 命令已为 31.9.1 而保留旧 MSI 登记、Classic 用户客户端与 Machine-Wide Installer 均精准卸载；新版 Teams 保留。实际版本：7-Zip 26.04、Git 2.55.0.5、Inno Setup 6.7.3、iTunes 12.13.11.1、Apple Mobile Device Support 20.0.0.35、VC++ 三架构 14.51.36247.0、Teams 26198.304.4946.9672、Outlook 1.2026.812.100、Terminal 1.25.2733.0、Windows App Runtime 1.6.9。证据 `target/glow-windows-software-update-20261022/update-results.{json,csv}` 及 `target/glow-windows-appx-update-20261022/appx-results.json`；自有安装进程无残留，VC++ ARM64 exit3010 需之后重启，未自动重启 Windows。
- 用户明确弃用旧 Anaconda 环境后，两套已确认旧根卸载均 exit0，唯一新版 JustMe 安装 2026.07-1 exit0。实际用户默认 Python 3.14.6、conda 26.5.3，原用户入口路径沿用、旧 ProgramData 根不存在，Glow 独立 Python SHA 保留；`final-current-user-check.json` passed。官方安装期间的包事务及新根 ACL 遍历有实际 CPU／元数据进度，不因父日志空白而重复安装。Git／Anaconda／运行库变动后再跑一次同一 TeX-only 入口：两子进程 exit0／drained，PDF 43,900 字节、SyncTeX 3,796 字节，watchdog 退出、选择字段保留、零下载／新装；`target/glow-windows-20261022/tex-fix-20261022/after-software-evidence/receipt.json` passed。
- 保留扩展的版本查询随后由实际 Windows 短脚本成功完成：官方 Marketplace HTTP200、41项均可判定。两项兼容 ARM64／Code 1.143.0 的稳定更新已由官方 CLI 安装 exit0：Continue 0.8.68→2.0.0、Markdown All in One 3.6.2→3.6.3；总数仍 41、其余 39 项版本／渠道不变，C/C++ 1.35.4 最新预发布保留（稳定版 1.34.4 不作升级）。三份配置 SHA 未变，未读取 Continue 的配置／密钥，未启动用户窗口，CLI 均退出；`target/glow-vscode-extensions-audit-20261022/{gallery-41-update-audit.json,stable-update-receipt.json}`。本轮软件／TeX维护结束，不设自动唤醒或 standby；原 Neovide 实体输入与首帧验收仍等用户在场。

### Windows Git zsh选择性迁移（新增授权，2026-10-21 Codex）

- 按用户要求以Windows Git zsh为目标；独立仓库 `/Users/ysrae1/Dev/workstation-config` 提交 `fcb8dfda150a9e02399be33ec396241e05f8eba7`，实现见 `shell/zsh-port/`。保留现有Git别名，补历史自动建议、命令高亮、Yazi的`y`和跳过Matrix的`nvidec`；只加入已存在的用户命令目录，Mac专用路径／Homebrew／Logic Pro／构建更新脚本／凭据及Conda绝对路径不迁移。
- 实际部署至Windows `~/.config/glow-shell/`、`~/.local/share/glow-shell/`，通过已有Oh My Zsh自定义入口新增 `~/.oh-my-zsh/custom/glow-shell-port.zsh`；不写`.zshrc`／`.p10k.zsh`／`.bashrc`／`.bash_profile`，部署前后四文件SHA相同，不覆盖另一会话的主题改动，不改PowerShell。输入插件在完整启动配置之后的首次提示符前加载一次。
- 实际Git/MSYS zsh5.9定向验证passed：正常用户启动、Git别名、两插件一次加载、中文空格路径与参数、Yazi失败状态／临时文件清理、nvidec父环境保持；函数检查使用隔离stub，未启动真实Yazi／Neovide GUI，不宣称实体输入／像素验收。初次QA把同目录的/tmp与/c/Users/.../Temp别名误判不同，改为比较cygpath原生路径后通过，生产函数无需修改。
- 现有终端未热重载；下次打开Git终端自动生效。`nvidec`沿用已验收PdfNav92启动器，不换装未验收拖窗。收据 `target/glow-zsh-port-20261021/receipt.json`；禁用本次新增的Oh My Zsh入口即可回滚。此前归档的开发任务不恢复。

### Ubuntu 与 Windows 终端增量（2026-10-22，Codex）

- 按用户继续要求补齐此前漏掉的Ubuntu操作层：独立配置仓库提交 `8a0a7141dd0506bbf0be98ec20d1f77e239e0c17`，新增 `shell/zsh-port/ubuntu.zsh`；加载官方OMZ快照的目录／目录栈／Git行为及锁定的两个输入插件。实际Ubuntu zsh5.8.1定向验证通过：`..`、`./SCDAA`、Git与目录栈别名、插件一次加载及p10k保留；`.zshrc`仅前置入口，原内容逐字节保留并备份，p10k配置／入口／全部非Git主题文件校验一致。新开Ubuntu终端生效；不改目录权限，不恢复Linux原生GUI开发。证据 `target/glow-zsh-port-20261021/ubuntu-receipt.json`。
- 本次QA初始重定向输入在提示符等待，35秒宿主超时；通过精确ZDOTDIR身份核对停止自有QA shell及daemon。随后确认SHIN_STDIN不能运行时修改、source测试文件会改变输入语义，改用启动时`-isc`和eval断言后通过；生产配置未因探针误判反复改动，不宣称实体按键验收。
- Windows Terminal原“Git Bash”入口更名为`zsh`，图标换为自带通用终端图像；仅改name／icon，备份和冲突检查完成，截图已看到Git图标消失。现有shell仍可动态显示目录标题，不更改启动命令、权限或主题。证据 `target/glow-terminal-label-20261022/receipt.json`。
- 按用户新增要求为CMD配置现有PowerShell同款Oh My Posh主题：用户级官方Clink ARM64 1.9.34，复用原主题，PowerShell profile／主题保持；CMD AutoRun及初始化CLI检查通过。当前已打开的管理员CMD PID16348经身份核对后，仅一次官方CLI外部注入失败，未提权或重启；CUA读取截图可用，但当前VM输入目标失败，未能从旧窗口内部激活，故不作当前CMD渲染通过结论。新开CMD将走已配置的AutoRun，或在旧CMD自身执行收据内currentSessionCommand。证据 `target/glow-cmd-theme-20261022/{receipt.json,inject-existing-receipt.json}`；回滚入口已保存。本次不重跑Windows开发／发行验收或唤醒归档聊天。

### 2026-10-21 重启前交接（Codex）

- 用户22:05:50要求两个Windows任务无论进展如何，最迟22:10:50停止、总结并交付；随后因Codex图形界面明显迟缓要求立即保存结束。本轮停止新增开发／构建／测试；重启后先读本节及下列收据，不自动恢复或唤醒任务，继续开发需用户明确恢复。Linux仍暂缓。
- 已交付：Mac预览 `glow-macos-20261021-preview1`／网站第17版不变；媒体顶栏源码 `e8c893b`、配置 `fbe22c3e` 及Mac／Windows回执见下表。Telescope源码 `1e04c0d`／配置 `8ea752d0` 已于21:55:30部署Windows，冷暖预览通过、下次正常启动生效；现有用户编辑器未重启／热重载。
- 拖窗：最终窄修 `f5e1e78`，`target/glow-parallels-20261021-qa/drag96-mac-unit3/{receipt.json,run.log}` 5项定向Rust检查全通过；Windows新构建尚无已完成产物，真实拖窗／标签点击／编辑验收未通过，不部署未验收拖窗，不把源码通过当实机通过。续接只核对该候选和所有权后决定一次必要构建／实机验证，不重跑Telescope。
- 安装器：`2198bd7488fbc924ff0daf122d2d34beea475ce3`；已实际读取 `target/glow-parallels-20261021-qa/core108-probe/receipt.json`（8边界passed）及 `core108-readonly/receipt.json`（真实只读检测passed）。自动识别science完整环境，8真实导入及CLI通过，探针17.281秒／预算60秒；不兼容Anaconda2.784秒跳过重包导入，总检测57.246秒，无安装、用户及QA选择文件不变、未建dependencyRoot。worker于22:04:53 exit0，探针子进程exit0／drained；测试孤儿已清理，外层supervisor `output_drain_complete=false`如实保留。既有94.6MB／Core94基础包安装卸载9项通过，但旧EXE未含2198；Core106仅准备／未构建，不能当新包。TeX `40b7a3c` 修复独立待验收，Core105停在旧Python前置，不是TeX修复实测失败。
- 停止／资源状态：两位负责人已交停止总结；安装器已确认停止并处于idle，无新增Windows调用。前端于22:08:38执行结束 `Glow-Drag96` 计划任务，命令自然exit0且系统确认终止；随后严格PID身份核对发现known root identity changed，已保留未知身份进程，不能声称全部后代逐一清零。前端确认无新增工作／自有GUI，GUI6未启动，不再继续；源码、归档及失败proof保留，未验收程序未替换Windows入口。保留用户窗口、主题、文件及他人进程。整合者只保存本交接，不启动新检查、打包、定时器或监控。

### 本轮交付证据明细（归档后保留）

本轮子任务均已结束；下表保留证据及未闭合项，不表示仍有后台开发或排队任务。归档工作记录和详细反思见后文。

| 状态 | 交付／唯一负责人 | 当前证据与下一项必要验收 |
| --- | --- | --- |
| 已交付；负责人本轮已结束 | Mac App 更新、PDF 白栏：[Mac 前端更新与 PDF 白栏修复交付](codex://threads/01a15e0d-c1a7-7753-9d75-7777301cfa21) | `mac-delivery83-3724db9/receipt.json`／`gui-checks.json`／`pdf-top-edge.png`：首次交付App与CLI为 `nightly-118+g3724db9`，签名／架构／hash一致；后续已由mac88升级为 `nightly-139+g955e75f`，以原生菜单行及mac-delivery88回执为当前安装结论；实际PDF无重复toolbar，胶囊、翻页／缩放通过。旧版在该stage的 `previous-install`，恢复入口已就绪。许可补齐单独提交 `14c3cf0`，477包／14Skia检查通过；未改用户主题与80%缩放。 |
| 已修复并热应用；本轮已结束 | 标签关闭取消处理：[Mac 前端更新与 PDF 白栏修复交付](codex://threads/01a15e0d-c1a7-7753-9d75-7777301cfa21) | 最初TbKillBuf→confirm bd97→E516→E5108源于预览标签自动关闭后重复删除。`config/navigation/buffer_close.lua`及base46 setup已修复，local／portable各14项回归通过并热应用；8个buffer内容／修改状态／光标／布局保持，取消关闭保留未保存内容。最终答复定位：轮次01a15e4c-828a-7f31-94fb-7d03ee540013，消息msg_0e29ec9eb2cf912a016ad8a90ce2cc81938fed3d10b79efd3c。未重编Rust或替换已发布Mac包；不再列修复中。 |
| 媒体顶栏Mac／Windows验收已接收；最终包SHA待核对 | 全媒体顶栏生命周期（提交 `glow-media-winbar-final-v4-20261021`） | 2026-10-21 Codex实际读取 `codex-note-glow-media-winbar-20261021` v4及三份收据；源码 `e8c893b`（含064c55a）、配置 `fbe22c3e`（含4d87551a）。Notebook／图片／PDF／网页及Book／音视频共用窗口owner和原始局部值，拒绝迟到写入／关闭及跨媒体旧栏复活。Mac local／portable各52＋Notebook各8、六类真实GUI通过，用户编辑器已热更，7buffers／2wins内容／输出／session／布局／光标保留。Windows固定fixture旧22/50→50/50，四文件备份部署、SHA与Mac／portable一致，下次启动生效；`gui-acceptance.json=passed_for_media_winbar_lifecycle`确认Notebook／图片／PDF转普通文件顶栏像素及原栏恢复，保存输出42保持、无kernel；owned进程已清理、supervisor exit0、UI回交frontend。此媒体专项的Windows PDF自然ready已到，未另证明该场景页面内容像素、物理输入及首帧时序；原生PDF翻页／缩放的独立通过范围见pdfnav92回执；Telescope后续已独立验收并部署（见下行），不阻塞本媒体结论。证据 `target/glow-media-winbar-qa/receipt.json`、`target/glow-media-winbar-windows-qa/{receipt.json,gui-acceptance.json,gui3-output/}`；四新SHA以首份收据production_sha256为准，core94仅证明旧Notebook修复，最终包仍须core独立核对，不作已封包结论。已读回执 `codex-ack-glow-media-winbar-final-v4-20261021`。 |
| 本轮停止；5项宿主检查通过，Windows实机未验收 | Windows 蓝框、原生 PDF、无系统标题栏及顶部拖窗：[Windows 蓝框与原生 PDF 构建交付](codex://threads/01a15e0d-c5ad-7b91-8d59-a48eb54f56c7) | 最终窄修 `f5e1e78`，`drag96-mac-unit3/receipt.json` 5项全通过；新Windows构建／真实拖窗无通过回执，不能部署或记为已完成。旧95候选真实拖窗失败保留。用户22:05:50要求最迟22:10:50停止并交付，前端已结束Glow-Drag96计划任务，后代逐一清零未确认；版本、证据及停止状态见本页重启交接。原始蓝框／PDF交付已由pdfnav92两份回执通过并部署，Telescope也已独立交付，均不重验；新增拖窗继续列未完成。 |
| 已部署；下一次正常启动生效 | Windows Telescope预览超时：[Windows 蓝框与原生 PDF 构建交付](codex://threads/01a15e0d-c5ad-7b91-8d59-a48eb54f56c7) | 源码 `1e04c0d`、配置 `8ea752d0`；`telescope95-acceptance.json=passed`：真实Windows Neovim0.12.3冷／暖中文文件预览内容及像素通过，保留250ms超时策略。`telescope95-config-deployment.json=deployed_next_launch`：21:55:30已向用户配置部署popups／transparency／popup_text三文件，逐文件旧／新SHA核对且备份至 `C:\GlowDev\ConfigQA\Telescope95_1`；主题及其他文件保留，未重启或热重载现有编辑器。此回执不包含新拖窗验收；复用既有检查，不重复部署或整套重跑。两份证据均在 `target/glow-parallels-20261021-qa/`。 |
| 本轮停止；Python探针已验证，TeX及新包待完成 | 精简安装器、缺失依赖检测：[Windows 精简安装包与依赖检测交付](codex://threads/01a15e0d-d247-7c73-bcb6-a2d5cbbacd0a) | `2198bd7`：Core108 8边界及一次真实只读生产检测passed，现有science环境8包／CLI可用，用户选择不变、无安装。`core108-probe/receipt.json`／`core108-readonly/receipt.json`已读；完整时间、进程排空限制与停止状态见本页重启交接。94.6MB／Core94基础包安装卸载9项通过保留，但未含2198新修；TeX `40b7a3c` 待验收，新包尚未重打，不当作完整依赖／最终发行通过。按用户要求停止新增工作，不等待拖窗。 |
| 代码／实际数据验收与部署完成；物理键／像素未验收 | Lua 中英文菜单、标题／浮窗材质首帧、快捷键及终端样式：[中英文菜单与跨平台界面修复验收](codex://threads/01a15e0d-df72-7160-9316-fd825b365156) | `40e4a29`／`7eb12cd`（配置 `584ee281`／`5687116f`）补输入标题刷新及12组Mini.ai中英／内外语义；local＋portable窄回归通过。`language-ui84/receipt.json`：实际Windows隔离实例的NeoTree、VimTeX22n＋1x、真实LuaLS同浮窗/raw不变、Notebook两输出无内核、Snacks／Telescope／Scratch深浅标题／配色／留白数据通过；3文件按旧hash备份部署用户配置，未热改／重启用户窗口，下次启动加载。自有进程已结束；当时物理键、实际像素及首帧因 `noWindowsAvailable` 未验收，现已交唯一Windows GUI负责人随新EXE闭合，尚不算完整GUI验收。 |
| 已交付；负责人本轮已结束 | 三端环境同步、PowerShell profile优化：[开发环境同步工作流与 PowerShell 启动提速](codex://threads/01a15e0f-47aa-7d71-818f-b0f160ee299f) | 独立仓库 `~/Dev/workstation-config` 提交 `074b9a7`／`31f2292`，14项测试、Mac三个受管配置一致；`workstation-sync89-receipt.json` 六步全exit0，Windows三项／WSL一项一致、独立Python＋11包exact-match，未重装。`workstation-profile87-applied.json`／`88-normal-startup.json` 已去重复OMP初始化，主体6625→1762 ms，主题／提示符／按键hash相同、posh-git保留；普通新进程总8.103秒含会话启动，不能称总启动1.76秒。原profile字节备份保留；终端视觉由UI任务接续。 |
| 已验收并安装；原负责人已结束 | Mac 原生菜单中英切换：[Mac 原生菜单接入中英文切换](codex://threads/01a15e0f-4c6e-75b2-9edb-c9f521ec1b58) | `mac-menu87-955e75f/receipt.json`：实际NSMenu中英往返、Dock、动作／target／快捷键、未保存内容／tick／光标／布局／撤销通过，CUA真实展开系统窗口操作已中文且全屏项唯一。整合者 `mac-delivery88-955e75f/receipt.json` 完成hardened runtime重签与App／CLI安装，旧mac83在该stage的previous-install，恢复入口已备；用户主题与80%缩放hash不变。OS提供方Services仍沿系统语言，全屏进出动画及多编辑器焦点往返未单独验收；旧84／86／85候选不可安装。 |
| 用户明确暂缓；负责人本轮已结束 | Linux 入口、原生媒体及平台差异：[Linux 端兼容与三平台差异闭合](codex://threads/01a15e0f-5123-7692-b3f5-09de30021a20) | 用户2026-10-21决定“linux开发先暂缓”。保留入口 `360a2e0` 及X11后端 `57a341f`；11项入口／12项helper检查、宿主Rust替身接口检查通过，不是完整Linux编译／桌面GUI／解码验收。自有宿主任务均结束；Mac发布时GitHub临时tag误触发的Linux构建39593705298已取消（非验收通过），临时tag已移除，未恢复Linux开发。仅来宾 `*linux-native-20261021*run-entry-check.ps1*` 是否残留未知，两次有界调用超时后已停；恢复只核对此入口，不动其他进程。Wayland／ARM64清单缺口保留，容量恢复不自动唤醒Linux。 |
| 容量恢复与PowerToys安装／界面核验均已完成 | 实际磁盘容量、PowerToys：[排查 Windows C 盘占满与 PowerToys 安装失败](codex://threads/01a15e09-9198-74c3-91b3-97c47d63f6ca) | 2026-10-21 19:28:45迁移完成后的宿主真可用404,418,498,560字节；Windows C盘可用404,421,296,128字节（约376.7 GiB）、Healthy，已远超3 GiB构建门槛。容量负责人已各唤醒一次Windows前端／精简包，整合者不重复唤醒；PowerToys 0.101.2362.0 ARM64 Per User于19:46:29实际安装成功（官方签名缓存包，Bundle／MSI exit0）；19:51 EXE版本／HKCU卸载登记一致，主进程／Settings运行，19:50 CUA实际确认中文欢迎界面。`powertoys-retry1-verification.json` passed=true／own_task_removed=true；旧包装器提前结束receipt不作结果，未重复安装。该任务guest／GUI均已释放，按前端队列先core88再pdfnav92；用户Neovide／配置及Photos保留，Linux暂停。 |
| Mac已公开发布；Windows发布等两项验收 | 唯一状态整合、新版本发布与网站入口：[全部剩余开发事项整合与最终交付](codex://threads/01a15e10-07ad-77f3-b12c-1f312d3b2b1d) | `mac-public89-955e75f/receipt.json`：generic／arm64／minOS11、runtime签名／477＋14许可，无observer。GUI已由容量任务回交；`gui91/acceptance.json`及checks确认真实中英文菜单、PDF实际页面／无重复白栏／彩色胶囊、翻页缩放fit、未保存内容保持，消息空，自有进程已退出。DMG只读挂载核验通过，17,929,958B；单文件37,720,054B／ZIP37,827,820B各222文件SHA核对通过。新source tag固定c5d1f2b、config tag固定5687116f，7发行资产远端大小／digest一致；SH／ZIP／DMG／部署说明公开HTTP200。`target/releases/glow-macos-20261021-preview1/publication-state.json`记录发行419485657及收据；网站第17版／910ed570已部署成功，实际线上下载区及Windows禁用下载确认。旧tag／包保留；整体Windows交付尚未完成。 |

共享资源：本轮按用户要求停止新增工作，为Codex重启保存交接；Windows前端已结束Glow-Drag96计划任务并停止，后代逐一清零未确认；安装器已结束探针验证并停止，无新增安装／guest调用。最终进程状态以本页重启交接及负责人停止回执为准；用户／他人进程保留。Mac公开发布已完成，Telescope已独立部署，Linux继续暂缓；不自动恢复任务、启动LinuxCI或设常驻轮询。

### 本轮子任务验收、工作记录与归档

> 2026-10-21，Codex；按用户重启后的要求，只读核对已有最终答复及收据，不恢复开发、不重跑测试。下表覆盖9个项目子任务及2个本轮调度规则对话；归档保留聊天全文、源码、产物和证据，不等于所有功能通过。原始发起对话与当前整合对话继续保留。

归档操作状态：11个对话已实际归档；逐项接口均返回archived=true，并已在归档列表中核对11/11。原对话全文可从下表链接或归档列表恢复查阅；本次只归档对话，不删除源码／产物／测试证据，不恢复未闭合开发。证据简写 `Q/` 指 `/Users/ysrae1/Dev/neovide/target/glow-parallels-20261021-qa/`；媒体专项位于同级 `glow-media-winbar-qa/`、`glow-media-winbar-windows-qa/`。

| 子任务对话 | 本轮验收结论 | 简要工作记录、证据与保留事项 |
| --- | --- | --- |
| [Mac子任务：前端更新与 PDF 白栏修复交付](codex://threads/01a15e0d-c1a7-7753-9d75-7777301cfa21) | 已交付 | PDF白栏／翻页／缩放通过，首次安装mac83后由原生菜单整合升级mac88；取消关闭标签已修复并热应用，local／portable各14项通过，8个buffer内容／修改状态／光标／布局保留，源消息 `msg_0e29ec9eb2cf912a016ad8a90ce2cc81938fed3d10b79efd3c`（轮次01a15e4c-828a-7f31-94fb-7d03ee540013）。后续全媒体顶栏 `e8c893b`／`fbe22c3e` 的52＋8回归及六类Mac GUI通过；note v4已有整合已读回执。发布包仍为原冻结版本，不冒称新修全部重新封包。 |
| [Windows子任务：蓝框与原生 PDF 构建交付](codex://threads/01a15e0d-c5ad-7b91-8d59-a48eb54f56c7) | 基础前端与Telescope已交付；新增拖窗未闭合 | `d8cbda3` 的实际蓝框／无系统标题栏／PDF页1→2／125%缩放／fit通过，`Q/pdfnav92-native-acceptance.json`及`pdfnav92-deployment.json`确认20:05桌面入口下次启动生效。Telescope `1e04c0d`／`8ea752d0` 冷暖预览通过、21:55:30配置部署。拖窗 `f5e1e78` 只有5项Mac逻辑检查通过，Windows实机未通过、未部署；停止与详细历史见下节。 |
| [Windows子任务：Notebook 顶栏串到普通文件查验](codex://threads/01a15e5b-3624-7ec2-9f0c-fd7030c53f96) | 本专项通过；最终包收录待整合 | 固定fixture旧22/50→50/50，Notebook／图片／PDF回普通文件实际顶栏恢复，保存输出42及内容保留，无kernel；`glow-media-winbar-windows-qa/gui-acceptance.json=passed_for_media_winbar_lifecycle`。四文件备份部署、下次启动生效；最终包四新SHA仍须打包方核对，不能以core94旧Notebook修复代替。 |
| [Windows子任务：精简安装包与依赖检测交付](codex://threads/01a15e0d-d247-7c73-bcb6-a2d5cbbacd0a) | 基础安装／卸载与Python检测通过；TeX及新包未闭合 | Core94 EXE 94,620,158字节，9项安装／卸载通过并保留10,437配置文件。`2198bd7` 的Core108八边界及一次真实只读检测通过，已有science环境8包／CLI识别、无安装、选择未改。旧EXE未含后续修复，TeX完整父入口未验收，外层日志排空未确认；见详细历史。 |
| [跨平台子任务：照片图库迁移与磁盘空间恢复](codex://threads/01a15e09-9198-74c3-91b3-97c47d63f6ca) | 已交付 | 迁移完成时Windows C盘可用404,421,296,128字节（约376.7 GiB）；PowerToys 0.101.2362.0 ARM64当前用户版安装日志、EXE／登记版本及中文欢迎界面通过，`Q/powertoys-retry1-verification.json` passed、own_task_removed；用户图库及其他程序保留，无待续安装。 |
| [跨平台子任务：中英文菜单与界面修复验收](codex://threads/01a15e0d-df72-7160-9316-fd825b365156) | 代码／原生数据及部署通过；实机输入／首帧仍有缺口 | `40e4a29`／`7eb12cd`，配置`584ee281`／`5687116f`；实际LuaLS、12组Mini.ai、NeoTree、VimTeX、Notebook两输出及浮窗数据通过，3文件备份部署，`Q/language-ui84/receipt.json`。后续`popup93-pixel-findings.json`补Snacks／Scratch浅深色画面，Telescope由95独立通过；物理键／鼠标、PDF Escape焦点、原生首帧时序不能据截图补判通过。 |
| [Linux子任务：兼容性与三平台差异闭合](codex://threads/01a15e0f-5123-7692-b3f5-09de30021a20) | 用户暂缓；保留部分成果 | `360a2e0`入口及`57a341f` X11原生后端保留，11＋12项Python检查通过；宿主替身检查不等于完整Linux构建／原生GUI。当前仅WSL1无图形服务，完整桌面、解码、Wayland／ARM64等未验；来宾遗留入口是否存在未确认，不自动恢复。 |
| [Mac子任务：原生菜单中英文切换](codex://threads/01a15e0f-4c6e-75b2-9edb-c9f521ec1b58) | 已交付 | `955e75f`；真实系统菜单／Dock／动作／快捷键中英往返及未保存内容保护通过，`Q/mac-menu87-955e75f/receipt.json`。整合者后续完成runtime重签和App＋CLI安装，`Q/mac-delivery88-955e75f/receipt.json=installed_and_verified`；Services沿系统语言，全屏动画／多编辑器焦点未单独验收。 |
| [跨平台子任务：开发环境同步与 PowerShell 启动提速](codex://threads/01a15e0f-47aa-7d71-818f-b0f160ee299f) | 同步与启动修复已交付；终端视觉属界面续接 | 独立仓库`/Users/ysrae1/Dev/workstation-config`的`074b9a7`／`31f2292`，14测试、Windows／WSL六步审计及Python＋11包版本匹配；`Q/workstation-sync89-receipt.json`六步exit0、0设置写入／0安装。去重复OMP初始化，profile主体6.625→1.762秒，普通新进程总8.103秒，两种口径保留；原profile备份、主题／按键及Git补全保留。 |
| [完善并行任务调度准则](codex://threads/01a15e08-319b-7382-81d2-bd2d512a9d63) | 已交付并并入统一规则 | 全局`/Users/ysrae1/.codex/AGENTS.md`新增整体依赖、快速独立交付、并发排队、职责、资源冲突及真实状态六项规则，已含作者／日期记录；后续系统整理合并，旧行号不再作为当前定位。 |
| [全局 AGENTS.md 系统整理与子代理调度优化](codex://threads/01a15eb4-50d9-7440-9514-c052f799854e) | 已交付 | 全局正文36,431→28,156字节的系统整理完成；保留偏好、作者、隐私边界，补上下文健康及迁移建议；备份与差异在`/Users/ysrae1/Documents/Codex/2026-10-21/global-agents-system-review/outputs/`。本整合对话随后按用户要求追加超时砍支，现文件30,836字节；未建立后台强制计时器，Claude入口实际导入本轮未验证。 |

### 未闭合工作历史与流程反思（保留材料）

> 实际整理者：Codex，2026-10-21。用户明确要求在简要交接之外保留较详细的历史用于自我审查。以下仅来自已保存对话／收据；时间为北京时间，不构造完整并发利用率，不把图形界面迟缓或长上下文直接归为根因。原始工具日志仍在原位置，不复制全部日志。

#### Windows前端：初始交付、新增范围与拖窗未闭合

来源对话：01a15e0d-c5ad-7b91-8d59-a48eb54f56c7；初始PDF轮次01a15e39-51b4-7391-b8d0-8199351a99db；新增需求消息01a15e6d-8b33-78d1-9e1e-97454b0502bd；后续执行轮次01a15e6d-89c7-70e3-9127-ae0e4f47339b。

| 阶段／时间 | 实际动作、结果和证据 |
| --- | --- |
| 18:42开始，19:09仍等待 | 初始目标是构建`3724db9`并验收引用蓝框、无系统标题栏和原生PDF。起初容量不足，未解包／构建，属真实外部依赖。19:29容量恢复后继续，不能将此等待计为已运行的构建。 |
| 容量恢复后的PDF构建与修复 | 首次构建约4分40秒；QA曾错选13×13的Winit辅助窗，校正后蓝框和隐藏标题栏实际像素通过。PDF真实画面却仍第一页，虽然协议已回报第二页；提交`d8cbda3`修正原生加载／导航事件后再构建约7分11秒。此处包含真实产品缺陷及一次辅助窗识别问题，不能混为同类失败。 |
| 20:05–20:16，原范围阶段交付 | `pdfnav92-native-acceptance.json`20:05:19 passed，页1→2、125%缩放／fit、协议生命周期及引用框像素通过；20:05:59 `pdfnav92-deployment.json`确认桌面入口下次启动生效，未重启用户编辑器。20:16:31 `popup93-pixel-findings.json`补Snacks／Scratch浅深色画面，但Telescope超时、物理输入和首帧仍缺。 |
| 20:26:39，用户新增范围 | 明确要求继续修Telescope，并新增顶部Tab空白拖窗。此后耗时并非原PDF目标持续未交付；应当为新增拖窗单列交付及检查点。 |
| 20:26–21:25，性能诊断与拖窗构建 | 诊断捕捉事件循环3–12秒停顿；普通浮窗事件触发每次2–4秒的全局外观刷新，短文件回调后还排队约2.2秒。修普通事件刷新及Base46重复主题查找，最终源码`1e04c0d`、配置`8ea752d0`。初版拖窗`351feee`／`5ce01630`等待安装器资源后构建约17分58秒，三项测试通过；包装脚本读未关闭日志失败后只补导出，未重编／重测，见`drag95-finalized-1/receipt.json`。 |
| 21:25–21:53，GUI1–5反复 | 曾遇前台焦点保护、DPI坐标、预览器未就绪、等待移动标志才移动、请求前已松手等QA问题；去日志延迟并换C盘本地程序后，GUI5仍`moved=false`／`native_move_loop_observed=false`／`nativeGUIAccepted=false`。该次左键确实持续按下、窗口未移动，见`drag95-gui5/state.json`；因此不能继续仅用“没按住／共享路径慢”解释。该隔离实例21:52:59退出并核对自身PID清零。 |
| 21:46–21:55，Telescope独立交付 | `telescope95-acceptance.json`21:46:30确认中文文件冷暖预览内容与像素通过、250ms策略不改；冷态回调107.5ms＋排队47.8ms，暖态229.4ms＋3.9ms。21:55:30 `telescope95-config-deployment.json`三个模块备份部署，下次启动生效。此通过范围不扩为任意负载保证。 |
| 21:55–22:05，最后逻辑修复 | 根网格／顶部边界修正中出现5项检查4通过1失败；最终`f5e1e78`在`drag96-mac-unit3/receipt.json`5项逻辑检查全通过，但不是Windows原生GUI验收。`drag96-dispatch.json`22:05:34才实际派发新构建，不可把“已准备”说成构建已完成。 |
| 停止与期限 | 用户22:05:50要求最迟22:10:50停止、总结并交付；22:08:38系统确认终止`Glow-Drag96`。随后后代PID身份改变，未强杀未知进程，不能声称整树清零。该轮实际结束22:11:23，超过总结交付期限约33秒；只能确认构建任务提前终止，不能宣称五分钟内全部收尾达成。GUI6未启动，拖窗未部署。最终消息`msg_01bd7b7e632c376c016ad8c80564408197a44a60f9a8b03996`。 |

**流程反思与改进（据上述事实提出）：** 原PDF与Telescope应在各自验收后及时结项，新增拖窗单独计时；真实HWND／焦点／DPI／按住→移动→松开及窗口位移观测应先做一次最小校准，QA入口失败与产品失败分别记录，同路径两次无新证据就停止改脚本；GUI、guest短调用、共享Cargo缓存及性能计时的所有权分别协调，不能把短冲突扩大为整项互等。停止预算应提前留出必要清理与最终答复时间，不能等到最后才汇总；此次最终答复超过用户期限是实际收尾不足。

**最小续接接口（未执行）：** 用户明确恢复后，先核对`Glow-Drag96`自有后代身份及是否有`f5e1e78`有效Windows构建回执；缺失才决定续建一次。保持已部署PDF／Telescope，随后只做一次空白区按住移动的真实验收，定位请求接收→根网格判定→Windows移动调用→窗口坐标的唯一断点；失败即交断点，不扩成主题／媒体／安装器全套回归。

#### Windows安装器：基础包完成，依赖复用／TeX与新包未闭合

来源对话：01a15e0d-d247-7c73-bcb6-a2d5cbbacd0a；前置轮次01a15e0d-d603-7390-9bbd-8e9a28ba3e51；关键收据均在`Q/`。收据证明的行为与尚未证明的原因分别保留。

| 阶段／时间 | 实际动作、结果和证据 |
| --- | --- |
| 18:42–18:51 | `dc9be70`／`19a53e7`修标准Jupyter环境发现、选定工具路径保留及测试编码。当时约1.3 GiB剩余空间及可验收前端是真实封包前提。 |
| 20:29:54构建；20:42:50安装验收 | Core94 EXE 94,620,158字节，SHA256 `aba9728986ea6ec119e0d6d017048c44711cf7ff2d7384cce92c63790ad734c0`；默认／中文空格撇号路径、启动、封印、运行时剔除及卸载共9项通过，保留10,437配置文件，见`core94-build/receipt.json`及`core94-installer-acceptance/receipt.json`。基础安装测试跳过可选依赖，不证明完整TeX／科学环境安装。 |
| 20:44:59–20:46:26，依赖复用被挡 | Core94前置检测未找到完整Python，保护条件停止，0下载、用户选择未改；后续确认注册和解释器存在，单次导入曾13.3秒成功。原始漏检原因未证实，不能追认为超时、环境损坏或编译负载。 |
| 21:15:58，未知状态保护 | `28a5cab`记录失败原因／耗时／unknown，阻止未知探针结果触发新装，8项原生探针回归通过。保护行为有效，不代表漏检根因已解决。 |
| 21:38:46，原子写入缺陷 | `419e7a2`修PowerShell把备份参数`$null`转空字符串导致原子替换失败、掩盖原TeX异常；8项原子写入回归通过。这是实际安装器脚本问题。 |
| 21:44:43，TeX调用作用域 | `40b7a3c`修子脚本改变日志目录变量作用域，导致TeX进程尚未启动就失败。完整父入口尚未通过；不能归咎TinyTeX环境，也不能用单独TeX脚本曾成功代替集成验收。 |
| 21:46:15–21:47:43，Core105 | `core105-dependencies/receipt.json`显示真实Python探针触发20秒上限，记录unknown并停止，0下载、选择未改，检查列表为空，尚未走到TeX；不是该TeX修复的实测失败。 |
| 21:52:49–21:53:09，Core107 | 拆模块只读诊断8包全部导入，累计10.031秒／整进程15.140秒，exit0、输出排空；确认环境可用，但不撤销Core105已发生超时，也不追认Core94原因。 |
| 21:58:17提交；22:03:48–22:04:47验证 | `2198bd7`先读metadata跳过不兼容环境重包导入，兼容环境仍实导8包，默认60秒有界预算、逐模块进度。`core108-probe/receipt.json`8边界passed；`core108-readonly/receipt.json`一次生产只读检测自动识别science，探针17.281秒／总57.246秒，不兼容Anaconda2.784秒且imports_checked=false。无安装、用户／QA选择未改、未建依赖目录，无并行compiler。 |
| 22:04:53退出；22:07:48停止交付 | worker与探针子进程exit0，测试孤儿已清理；`core108-probe-supervisor.result.json`外层`output_drain_complete=false`保留。无新增Windows调用、无重打包；Core94旧EXE未含后续原子写入、作用域及探针修复，Core106仅准备／未构建。TeX和最终新包继续待办。 |

**流程反思与改进（据上述事实提出）：** 短只读Python正确性诊断曾等待前端长构建，后来已确认可并行采集并记录负载；只有真正要求空载的性能计时应独占，不应扩大为全部检测的前置。诊断辅助脚本括号错误、过期压缩器路径造成额外往返；首次执行前应核对语法和现存路径，真实父入口验证作用域与写入生命周期。每次失败先保存原异常／阶段／耗时，下一次压缩到最小失败路径，避免TeX入口失败又重复扫描Python；独立基础包先交，最终包绑定准确源码／配置清单。早期容量不足、新前端封包依赖及实际guest短入口冲突不能一概称人为等待，尚无证据证明负载导致Core94漏检或Core105超时。

**最小续接接口（未执行）：** 用户明确恢复后，从`2198bd7`的已保存输入，针对真实父入口定向验证现有TeX复用及选定路径保留；通过后再决定打包含后续修复及媒体四SHA的新包，并只对新包做必要安装／卸载和清单核验。Core94保持原封印，旧测试不作新包通过凭据；无需先等待新增拖窗才能验证TeX正确性。

#### 界面语言／快捷键：已部署数据，物理输入与首帧未闭合

- **已做阶段：** `40e4a29`／`7eb12cd`及配置`584ee281`／`5687116f`完成输入标题刷新、12组Mini.ai语义；local／portable回归后，`language-ui84/receipt.json`真实Windows数据验证LuaLS同一浮窗、NeoTree55行、VimTeX22n＋1x、Notebook两输出无内核及浅深浮窗标题／配色／留白，3文件备份部署。自有进程按PID身份清理，用户窗口未重启。
- **受阻及补验历史：** CUA明确报`noWindowsAvailable`，新绑定及显示方式转换后仍不能可靠操作来宾窗口；没有盲发物理输入。数据首flush不是原生首帧。后续前端`popup93-pixel-findings.json`补Snacks／Scratch静态画面，Telescope95补冷暖预览；这两次后续通过只关闭各自缺口，不能补判物理键、PDF Escape焦点或合成器首帧时序。最后轮次明确仍待验，无运行工作。
- **流程反思：** 将代码回归、原生数据、静态像素、物理输入和首帧时序分别列验收项；控制面故障已有重复证据后停止反复切窗口，先交已通过数据，不让截图或状态查询代替输入／时序证据。后续若仅需要静态材质验收，不增加高成本首帧承诺。
- **最小续接接口：** 用户恢复且已有可靠的来宾控制后，针对现有配置只补物理键／鼠标和明确要求的首帧场景；复用上述静态画面和数据，不重跑语言／媒体全套。终端视觉从workstation任务移交的部分在同一界面范围核对，不另重装环境。

#### Linux：用户暂缓后的保留与反思

- **已做阶段：** 保留`360a2e0`入口和`57a341f` X11原生预览后端；11项入口＋12项helper检查通过，宿主Rust替身接口仅证明对应接口。完整Linux编译、真实X11桌面／解码、Wayland及ARM64支持未验收。
- **停止经过与资源：** 当前实际只有无显示服务的WSL1，无法满足原生GUI验收；用户明确“linux开发先暂缓”，已停止新增开发／CI。自有宿主任务结束；两次有界来宾入口调用超时后未继续追查，`*linux-native-20261021*run-entry-check.ps1*`是否仍存在未确认。Mac发布误触发的GitHub Linux run39593705298已取消，非Linux通过，也非恢复开发。
- **流程反思：** 平台原生GUI前提应先核对；WSL命令行、宿主替身和X11目标源码分别记证据边界。缺少必要环境时及时交阶段成果与明确缺口，不能继续堆测试替身并扩大为平台支持承诺。
- **最小续接接口：** 只有用户明确恢复并提供真实Linux图形环境后，再先核对遗留入口归属、工具链／后端能力和准确源码版本，随后选择一次必要构建与GUI验收；不自动启动CI，不影响用户或其他任务进程。

#### 整合者自身的记录与调度反思

- 总记录曾保留旧PDF“待构建”和标签关闭“修复中”，未及时反映20:05 PDF交付及Mac取消关闭修复；本次只读核对补正。通过项应在自然交付阶段批量登记，未读结论明确标待整合，不能让旧状态持续代表当前事实。
- “两个任务进行了约三小时”跨越容量等待、原目标交付、用户新增范围、真实产品问题和QA返工；本次已分段保留时间和证据。既不能用编译概括全部耗时，也不能据此认定上下文是根因或生成未经测量的并行率。
- 已按用户要求把阶段预算、约5分钟无信息／两次同路径不推进的决策、停低收益分支和独立成果先交写入全局AGENTS；这是提示词约束，非后台强制计时器。此轮归档不重新开发，未闭合目标在用户明确恢复后才接续；应用图形界面迟缓的根因本轮未诊断。

### 已交付，复用既有证据

| 已交付范围 | 证据／边界 |
| --- | --- |
| Windows 用户目录配置、swap／undo、60%默认缩放 | `migration79.json`：149文件、旧目标备份、主题／打开文档／撤销及运行数据保留；状态栏 `statuslinehot78` 已热应用，标题栏另见剩余表。 |
| Windows 编辑键、UNC／URI、PS5／Matrix兼容、浅色文字与阴影 | 既有真实回归及部署记录保留；多光标完整加载和全面新窗口一致性由 Lua／Windows负责人闭合。 |
| Mac Matrix 材质、编辑区布局排除侧栏、GitHub可配置入口、缩放／重新缩进 | 已部署及定向界面／RPC验证；Mac `hot75` 语言和标题已应用，原生菜单另列。 |
| Windows TeX／科学Python／Jupyter／VS Code14项扩展；WSL独立Python | `tex28e-receipt.json`、`python58-windows.json`、`vscode45.json`／`extensions54.json`、`python52`；不重装既有通过环境，不将WSL命令行结果写成Linux原生GUI验收。 |

## 历史维护记录

以下为接手前的阶段快照，保留失败与当时运行状态；其中“当前／待办”不覆盖上方当前表。

### 2026-10-21 接手前构建与迁移快照

- 2026-10-21，Codex：源码已提交 `3724db9a6887e8bb9143be368c1f4897df66343d`，配置已提交 `d41a02f67a76a6fdb0eff4072ba2a53bde91d2bb`；本机当前浅色选择独立保留，未推送或改冻结发行包。Mac 已从该源码提交编译成功（`mac78-3724db9/receipt.json`），尚未安装。
- Windows 配置迁移 `migration79.json` 已通过原生回归并切换实际运行窗口到用户目录 `.config/nvim`；149 个文件复制，旧目标完整备份，打开的主题/配置内容、撤销目录、插件数据和 60% 缩放均保留。
- Windows 提交后构建 Commit82 只在宿主完成源码归档/脚本准备；因 C 盘剩余约 1.39 GiB 尚未启动。容量排查已按用户要求转独立对话，本任务不并行清理或继续写入。

### 2026-10-21 下午需求进度（Codex，历史快照）

“已完成”表示相应改动已经实际部署并完成注明的验证；代码已通过测试但未应用到当前窗口的，单独列出。

| 状态 | 下午提出的事项 | 已有结果／还差什么 |
| --- | --- | --- |
| 已完成 | Windows 配置可编辑、保存时 swap／undo 报错 | 原配置目录可写；短 swap／undo 路径已部署，真实 Windows 重开后撤销通过，用户主题内容保留。 |
| 已完成 | Windows 当前缩放作为默认 | 实际保存 60%，没有改变当前比例。 |
| 已完成 | Windows 复制／剪切／粘贴／保存等编辑键 | 已部署并热应用；Ctrl+C/X 选区操作、Ctrl+V、Ctrl+S、终端 Ctrl+Shift+V 已核对。多光标新增鼠标映射完整加载需下一次正常启动。 |
| 已完成 | Windows UNC 共享路径、NeoTree／LSP URI 报错 | 修复已部署，真实 Windows UNC 路径与 URI 检查通过。 |
| 已完成 | Windows 浅色可读性、浮窗阴影 | Windows 专属透明度与阴影配置已部署，实际查看 Yazi 清晰文字；用户后来调整的 Ayu 色值保留。 |
| 已热应用 | Windows 底部状态栏空白材质 | statuslinehot78 已应用；Normal／St_EmptySpace／St_NormalModeSep 同背景 724500、blend=0，胶囊原实色保留。 |
| 下次启动生效 | 隐藏 Windows 系统标题栏 | frame78 已为现有桌面入口设置 `--frame none`；保留 Glow 标签栏，当前窗口未重启。 |
| 已完成 | PowerShell 兼容、Matrix 脚本报错 | PS5 不再无条件读取 PS7 属性；修复已部署。 |
| 已完成 | Mac Matrix 与编辑区材质一致 | 开屏／Dashboard 配置已同步；开屏首帧网格及 Dashboard 实际界面检查通过。 |
| 已完成 | GitHub 入口可由用户配置 | 已有用户名、gh 登录／当前账户及清除配置入口，已部署；不绑定发布者账户。 |
| 已完成 | 移动／重排编辑窗口排除侧栏 | 已修复并验证布局及快捷键入口，排除 NeoTree、AI 侧栏和浮窗。 |
| 已完成 | Windows 开发依赖 | 用户级 TeX、中文 XeLaTeX＋SyncTeX、独立 Python 科学环境、Jupyter 内核、VS Code 及14项扩展已实际验证。 |
| 已完成 | WSL Python 环境 | python52 已完成；独立 Python 3.12.8、11项固定依赖与 Jupyter 内核已验证，未替换系统 Python。 |
| 部分完成 | 跨平台环境配置工作流 | Mac 盘点与 Windows／WSL 配置应用已有结果；长期三端更新、冲突处理和完整 Linux GUI 验收尚未闭合。 |
| 部分完成 | Toggle Language 全界面中英切换 | Mac hot75 已成功并保留文档及视图；Windows locale75 已部署38文件至2个 profile，旧 pipe 热应用失败，新窗口尚未全面验证。 |
| Mac 已应用 | NeoTree 帮助漏项 | 四来源182条实际帮助项测试通过，包含滚动方向、文件剪贴板、自动宽度；Mac hot75 已应用，Windows 重开后待核对。 |
| Mac 已应用 | 操作等待／Visual 等 WhichKey 菜单 | 172项来源词条及真实菜单中英往返通过，Mac hot75 已应用；Windows 新窗口尚未全面验证。 |
| Mac 已应用 | LaTeX 菜单说明 | 真实 .tex 中22项 normal／1项 visual 映射不变；LaTeX／LaTeX功能及功能说明已在 Mac 热应用，Windows 待核对。 |
| 部分应用 | 选择器标题、预览文件名及中英文留白 | Mac 当前 Snacks 标题已热应用；真实 Snacks／Telescope、深浅主题及 grep 留白测试通过，Windows 重开后待全面验证。 |
| 部分完成 | 诊断及 Notebook 状态汉化 | 精确诊断及生成状态适配已部署，保留原始诊断与输出；Mac locale 热应用成功，旧 Python host 的部分折叠文字仍需下一次正常启动，Windows 新窗口待验证。 |
| 已完成 | Mac 缩放与重新缩进入口 | Command+=/+ 放大、Command+- 缩小、移除旧 Command+9；leader c=重新缩进，hot75 已应用；默认缩放80%已实际保存并由 RPC 确认。 |
| 已完成 | Windows 配置迁到 ~/.config/nvim | 已迁移并热切到用户目录 `.config/nvim`；原生回归通过，用户主题、打开文档及运行数据保留。 |
| 进行中 | Windows 选中词蓝框 | ext_hlstate 源码修正已进入 build76 并编译成功；该构建仅作测试，须先提交源码／配置后重构建，再做实际蓝框验收。 |
| 未完成 | Windows 原生 PDF 最终验收 | 新 EXE 已编译、协议／WebView2就绪通过，实际页面像素与完整交互验收仍缺。 |
| 未完成 | 小体积安装包、缺失依赖检测安装及发布 | 检测／安装流程已有真实检查；新核心安装包尚未生成和公开发布。 |
| 未完成 | 所有浮窗首帧／材质问题全面闭合 | 已有部分修复及定向检查；不能据此宣称所有插件浮窗均已验收。 |
| 部分完成 | Mac 原生菜单、原生 PDF 白栏 | 原生菜单尚未完整接入 Toggle Language；PDF 重复原生工具栏已在源码隐藏，测试通过但未安装。 |
| 未完成 | Mac／Windows／Linux 全面对齐 | Windows 集成及 Linux 实机 GUI 验收仍有缺口。 |

当时优先顺序：完成 Windows 配置迁移 → 提交源码与配置 → 重新构建并验收蓝框／原生 PDF。迁移和提交现已完成，后续依赖见当前表。用户主题、公开冻结包及正在编辑的文件保留。

- 2026-10-21，Codex：Mac `hot75` 已应用 locale、WhichKey、VimTeX 23项映射说明、缩放／重新缩进、NeoTree 帮助及当前 Snacks 标题，文档与视图保留；默认缩放80%已保存并由实际 RPC 确认。
- Windows `locale75` 已部署38文件至2个 profile；旧 pipe 热应用失败，新用户窗口（Neovim PID 6812）重启后尚未全面验证。`statuslinehot78` 的同色底材及胶囊保留已通过实际应用检查，`frame78` 仅为桌面入口设置下次启动无系统标题栏。
- `build76` 编译成功（产物 SHA256 前缀 `93c4b8`），但用户新增规则要求所有编译前先提交源码和配置，因此该产物仅作测试，待提交后重新构建；Mac PDF 白栏修复亦未安装，不作为已交付界面。
- WSL `python52` 已完成；Windows `migration79` 仍在执行，待主任务补最终回执。公开安装包和用户主题均未替换。


- 2026-10-21 16:35，Codex：本机及 portable 已补产品语言层，含真实 leader／Ctrl-W proxy、buffer-local LSP／语法导航、Dashboard、NeoTree、Notebook／图片／PDF 胶囊与状态栏；28 项隔离检查×2配置及14项语言专项通过。当前 Mac 已热应用词典／菜单／状态栏／文件浏览器标题，既有媒体胶囊的安全热更新仍在进行；原生应用菜单与原生 PDF 工具栏尚未接入语言切换，不声称全界面完结。
- Windows 两个实际 profile 已备份部署 `locale62-deployed.json`（31文件×2，init 仅补 setup 调用，保留用户编辑）、`config43-deployed.json`（短 swap 路径解决配置编辑 E303）、`config46-deployed.json`（PS5 Shell 兼容及 picker 首帧材质）；80% 用户缩放已保存。编辑区移动／交换／重排／均分／关闭其余窗口排除侧栏及浮窗，本机真实布局和快捷键入口测试通过。当前新 Windows 诊断入口为 `\\.\pipe\glow-config64`；旧 config24 已由用户关闭。
- Windows 用户级 TeX／中文及单引号路径 XeLaTeX+SyncTeX 已通过 `tex28e-receipt.json`；独立 Python3.12.10 科学环境及 Jupyter 内核由 `python58-windows.json`确认完成，VS Code 升级与14项扩展补齐见 `vscode45.json`／`extensions54.json`。WSL 的 Python 私有环境仍未完成，离线材料已官方校验；`python51-wsl-51.json`在安全解包链接时失败，正定向修复，原证据保留。
- 原生 Windows PDF 新 EXE 已完整构建，`pdf26-gui-2.state.json`协议／WebView2就绪／开关与遮挡检查通过，实际像素验收仍待补；核心安装器基础依赖的真实检测／安装见 `core49/receipt.json`，新小包尚未生成／发布。Scratch 标题图标与页脚底材的同类修复正在进行；保留冻结标签、旧安装包及用户文件，所有 QA 位置在 `target/glow-parallels-20261021-qa/`。

- 2026-10-21，Codex：按用户继续要求补 Windows 兼容性：UNC Neo-tree 根目录、标准 file URI、Ctrl+=/+/−/0 缩放、PowerShell 终端、可配置 GitHub 入口及 Matrix 提前覆盖／编辑区材质。各定向检查通过，UNC 两项另在真实 Windows 路径通过（`windows-unc-tests-20.json`）；19文件×2个实际profile已备份部署，保留既有init hook和浅色选择（`config23-deployed.json`）。
- Windows 浅色单独降低透明度；纠正 Neovide 先发布g默认1/10导致初始化遗漏后，实机RPC确认Normal不透明度0.98、阴影高度6、圆角0.48、messages空（`config25-live.json`）。嵌入Yazi私有主题跟随编辑器，浅色文件名使用原Ayu深色；CUA已实际见清晰文字与加实面板。独立Yazi配置及AyuRGB未改。Mac两处Matrix配置已同步并通过multigrid检查；已新开本机Dashboard实际确认Matrix背景与编辑区一致；开屏以首帧multigrid检查为证，未捕获动画截图。PD全屏已恢复。
- 当前可见开发会话为`\\.\pipe\glow-config24`，应用由本任务新启动，未重启已有编辑器；阶段进度窗口已实际显示并在该阶段结束后关闭。Windows/WSL环境只读盘点已完成，配置workflow源在`~/Dev/workstation-config`；Windows及WSL配置已实际应用，各自audit均unchanged；系统TeX与依赖安装继续进行。
- Windows WebView2 PDF后端及小核心安装路径已落源码，未发布。Mac主工程离线check与Windows后端独立目标check通过；原生Windows完整链接/GUI及新核心包验收尚待进行。新源码快照`pdf26-source/`和6项native manifest用于独立构建，不改旧Stage/C5/冻结标签。原生PDF不声称坐标SyncTeX支持。

- 2026-10-21，Codex：按用户决定停止输入法排查，临时桥接任务已中断，未部署或启用同步服务；保留用户有效映射。后续当前任务为恢复 Windows Glow 普通启动。
- 启动故障已恢复：同硬件入口／profile在保存网格20×9时持续占用CPU且无首屏，仅关闭启动消息捕获无效；只加110×34网格约4.08秒出窗且开场动画正常（`glow-startup-probe-10/`、`-13/`）。仅修复用户本地`neovide-settings.json`中的网格和像素尺寸，原文精确备份`neovide-window-before-14.json`；未改源码、安装包、输入设置。正式已安装普通Launcher不加OpenGL／grid／capture／intro覆盖，约4.08秒出窗（`glow-startup-probe-15/`），该自有验证进程已清理；当前硬件窗口保留给用户，CUA已见用户打开Notebook。小网格卡死的更深层原因尚未确认，不将恢复尺寸视为源码缺陷已修复。
- `glow-startup-cleanup-16/`已逐一确认原三组启动进程的PID亲缘、exe、空文件参数及没有有效可见客户区，只结束这三组持续占用CPU的卡死树；保留用户当前窗口。Candidate5先前Yazi健康失败与当前普通启动故障分开，尚未重新发布。Windows配置目前没有界面缩放快捷键（仅Mac分支定义），临时可设置`vim.g.neovide_scale_factor`，本次未新增绑定。
- 2026-10-21，Codex：完整候选4已在PD本地编译并通过安装／卸载七阶段及最终六项运行环境检查（`candidate-installer-3/`，续用`-2`前三个已通过阶段；仅QA sentinel作用域修复）。两次卸载均保留配置，任务自有sentinel已清理；825,413,515字节，SHA256 `fc74b4eac13bd28ba39631b32113d36a5f2b9867a07c22128f27867af7604ed4`，已导出并核对草稿远端digest，仍未公开。用户反馈PD软件绘制帧率低，先处理硬件OpenGL再确定发布内容。
- 系统WGL独立探针`opengl-probe-result-1`在x64/ARM64均取得Parallels/Metal硬件OpenGL4.3及Core3.3；不要求WGL透明格式可选5项，要求透明时API失败且error0。Windows-only回退`f4e035b178c42007e44cab412fedfe670491e64d`已推送及同步PD；本机renderer检查96通过、1项Metal默认忽略。`opengl-frontend-1`在1065.708秒因`+crt-static`请求未发布的Skia静态包404，源码回退又遇symlink1314而失败；无新EXE，Stage/C4未改。`opengl-frontend-3`曾以0x40010004中断，原因未确定；`-4`正常返回101，确证强制下载模式在registry crate无.git时跳过预编译，转源码而遇symlink1314。`opengl-frontend-5`改用registry VCS元数据／本地官方归档并显式`skia-safe/no-compile`，recipe v3，Windows单次按需任务实际472.067秒通过：AMD64、35,875,840字节、SHA256 `a96bece797dddc7533c0929654d42610ebcd0635360a58f88db1a770d38fe3b7`。`vc-runtime-1.json`的包内VC普通／延迟导入及递归符号89/89通过，不代表干净机运行验收。原缓存、各轮失败回执保留。`hardware-gui-3/gui/state.json`实际26.984秒通过并清理全部自有后代：真实系统OpenGL／Parallels驱动、包内VC运行库、原生PNG加载／关闭、同一窗口resize及再次解码均通过；`opengl-renderer-tests-2`在164.858秒完成96通过、0失败。GUI1/2失败证据保留，GUI3以真实UI/HWND判定就绪并增加RPC诊断；尚无人工视觉／帧率验收，不推断GUI2超时根因。Candidate5第一次prepare因唯一未封印运行缓存`runtime/python/Lib/encodings/__pycache__/gbk.cpython-312.pyc`被严格file-set检查拦截（缺失0、未创建候选目录）；缓存保留，仅精确排除并记录SHA，封印内文件逐项复制验SHA门槛保留。普通入口默认D3D12会在PD失败，已在Launcher `51de98eea4a66f5abf7af40f6b0dd1cfcc20d208`补仅Parallels子进程默认OpenGL，保留显式值与普通Windows默认；`launcher-pd-build-1`在PD真实编译114,688字节／SHA `afbce652ce262a162e665f29d5ee981c915aebe5cb00df0dd543d0578225472e`且14项定向检查通过。`hardware-default-launcher-gui-1`无显式OpenGL参数／父环境值，10.047秒通过全部原硬件GUI门槛并清理；C5第二次prepare在长临时路径创建目录时报206，失败临时目录保留；第三次显式长路径复制在545.960秒因`runtime/python/Lib/__pycache__/copyreg.cpython-312.pyc`与原seal不同而停止，原Stage与部分候选`.C5-8eef11a3eca7`均保留；详见`baseline-hash-mismatch-1.json`。该缓存修改时间20:13早于C4编译20:44，不依赖C4恢复缓存，也未运行恢复安装。新C5改用包内Python3.12.2在无旧缓存的独立候选中，以`-I -S -B`从逐项验证原seal的.py源码显式重建PEP3147 checked-hash缓存；其他文件SHA门槛保留。版本化worker与打包来源`fe0e8270b16cb477280e2674b27d7afbf2ea83c4`已推送；C5第四轮`candidate5-compile-4`在508.983秒完成全部非缓存复制验SHA及3914项源码绑定checked-hash缓存重建，包内Python3.12.2实际运行通过。新封印63870项／SHA `f40139c3063a970fa1ce63ba425e1e8bf2db29f2b1de8ba8312d767058dbfae0`，仅新增gbk缓存及3份来源记录；Stage-Candidate-5为独立副本。`candidate5-compile-4`已完成压缩1747.599秒，最终候选5为825,632,023字节／SHA256 `840db51b9ba82ecf183c6a3583b8b6d4bf5cfb634358e3e869a6b0c76ad58e2c`，未签名。`Glow-Candidate5Install-20261021-1`已启动本次7阶段／6项健康及11项关键payload检查，按用户预设用量停工条件，已停止新增模型工作及宿主观察器。`candidate-installer-5/receipt.json`停工时过长目录拒绝、默认安装／launcher-check／卸载共4阶段已通过，含中文／空格／单引号路径安装正运行；已启动的一次性有界本地套件继续自行完成健康检查与卸载收尾，不会自动导出或发布。恢复先读本次receipt、`installed-health/receipt.json`及`root-run-candidate5-install-1.result.json`，检查任务实际状态，不重启已存在的运行。全部通过后才运行已准备的`root-register-candidate5-export-task-1.ps1`、`root-verify-candidate5-host-export.py`单次宿主SHA校验、`root-finalize-candidate5-public-receipt.py`（compile4、installer5、export-host、launcher-pd-build-1、ordinary GUI1及compile4/canonical-python-caches.json）、`root-publish-candidate5.py`，最后部署并核对Sites已保存第16版。旧C4草稿EXE与线上第15版仍未替换；若本地套件失败，先处理其明确错误，不继承旧验收。有限时防休眠保留到自身超时，不自动续期。新C5显式绑定新Launcher来源／测试／普通入口GUI，不复用候选4安装结论。
- 2026-10-21，Codex只读接手检查发现候选5本地安装套件已结束：6个安装／入口阶段通过，安装后健康／来源绑定检查失败，按脚本保留该安装，未继续卸载、导出或发布；证据`candidate-installer-5/receipt.json`及`root-run-candidate5-install-1.result.json`。后续恢复发布工作先处理该明确失败，不沿用候选4结论。
- 两轮Windows更新已重启完成，用户已登录；`windows-update-after-2.json`实际26H2／26300.9711，WU与CBS均无待重启。全屏Scale view mode已核对为Auto；一次实际窗口→全屏切换读到3024×1680→3024×1898／120Hz，active与registry相同，证据`display-layout-window-auto-1`／`display-layout-fullscreen-auto-1`，未强写显示模式。`Show-Frontend-BuildLog.ps1`已指向已通过的`opengl-frontend-5`。GUI3诊断后已恢复全屏Auto，`display-layout-restored-fullscreen-1`再次读到当前与默认均3024×1898／120Hz；全屏CUA画面曾停在旧帧，退出全屏后刷新，不作产品根因结论。窗口模式来宾坐标输入仍报noWindowsAvailable，输入法及完整手动视觉验收留待可操作时验证，用户睡觉期间不提问。
- 输入法目标为Mac控制Ctrl+Space最近两项、Fn轮换中英希腊，PD保持双向同步；2026-10-21用户先恢复本项排障，发布任务仍暂停。Keyboard optimization=off、内置Switch Language与Mac快捷键／输入源保留，三项task-created Windows legacy值已精确撤回；正式希腊已追加且保留中英原属性与默认源（`greek-input-registration-verified-1.json`）。用户已将Send macOS system shortcuts从Auto改为Never，CUA画面确认；实按快捷键已有反应，但Mac选拼音时Windows仅在ENG／Greek间切换，4秒用户录屏同样显示该现象。用户另确认Windows可手动选微软拼音，不能把问题归为未安装中文；`input-current-status-3.json`确认用户级拼音启用、ChsIME／ctfmon运行、三语及四布局均存在、Tools与PD均27.0.3、KeyboardLayoutSync Enabled=1。用户随后明确确认Windows可手动切拼音，但快捷键仍陷于ENG／EL；按用户明确授权添加PD输入监控后未改善。已通过PD官方CLI重装Tools，界面明确显示成功，并完成Windows重启；用户重测仍失败，不能将重装成功视为修复。已找到PD27同类Mac→Windows同步失败用户报告，未找到本案已确认修复；新版／旧版拼音差异仅为假设，未启用兼容模式或删除任何键盘。用户继续要求解决；最新明确现象为Ctrl+Space时Mac3项／Windows2项，Ctrl+Option+Space时Mac2项／Windows3项（不是两边选中语言相反）。独立记事本正文仍复现，排除仅设置页焦点；未改拼音内部热键。用户随后明确反馈Ctrl+Space→Win+Ctrl+Space无效；自行改为Ctrl+Option+Space→Win+Space后Windows可三语轮换，但Mac不跟随，CUA设置截图确认当前保留该用户映射（Windows.dat从31增至32项；不能仅按Qt二进制modifier值猜标签）。原31项备份`input-keymap-before-7.dat`保留。Windows本身三语切换有效，双向同步仍未修复；同版本论坛有同步失效报告但无本案中文专属已核实修复，不将报告当成本机根因。Mac快捷键与输入源均未改；不覆盖用户有效映射，不重复权限／重装／重启路径。CUA能读原生设置，但坐标输入仍报noWindowsAvailable；如无新证据，不再让用户重复同一测试。
- Notebook整链 `windows-notebook-gui-8` 已通过62.344秒：真实修改41+1得到42、Matplotlib原生PNG、保存源码／计数／输出、关闭内核、同进程重开恢复且marker仍1／磁盘不变；自有GUI与内核均退出。修复覆盖Windows Jupytext双引号、远程桥路径、私有连接目录及sidecar斜杠身份；后者真实Windows旧失败／新通过，输出匹配保护未改。配置 `df6d66f5` 已推送；Stage与仅未改动的QA profile按SHA原子更新，第16版发布页仍仅保存。
- 2026-10-21，用户授权睡觉期间由Codex接管PD继续环境与安装包验证；周额度剩余≤5%时停止新增工作，保存当前成果、活动任务及恢复步骤，等待用户合适时恢复。额度由主任务在阶段节点统一检查，不自动唤醒。
- PD 的 Windows 11 ARM64 开发环境已部署至 `C:\GlowDev\Toolchain`：MSVC 14.44／SDK 26100、Rust 1.99.1 x64、LLVM 21.1.8 x64、Python 3.12.10、CMake／Ninja／Inno 6.7.1／Neovim均通过实际烟测（含 C、Rust、C# 编译运行与 x64 libclang 加载）；桌面入口“Glow 开发环境”使用私有工具路径，原 Anaconda／全局 PATH 保留。源码 `C:\GlowDev\neovide-glow` 已按公开 bundle 更新至 `f4e035b`，21个纯换行差异已按原Git字节规范化，未复制Mac认证。
- 当前PD命令由Codex主任务独占；13个空闲历史终端宿主已按PID和创建时间核对后清理，开发终端已实际显示文字。后台任务使用 `C:\GlowDev\Run-GlowTask.exe`，日志／回执在 `target/glow-parallels-20261021-qa/`；系统既有更新和待重启状态未改，不自动重启。
- PD 的原包短中文目录安装通过；63,866文件／2,965,344,774字节逐文件SHA一致后完整恢复至 `C:\GlowDev\PackageQA\Stage`。随后仅按原SHA核对并原子替换启动器、`lazy.lua`、`image.lua`，各有增量回执并同步manifest。真实Windows路径夹具四项通过；完整版根目录上限68字符，本机默认51字符。候选3在 `C:\GlowDev\PackageQA\Candidate-3` 本地压缩中，回执 `root-compile-candidate-3`／`root-compile-status.json`；候选1/2均因发现真实缺陷主动停止，不能当作构建器异常。
- PD 实际复测修复：启动器显式IO长路径在系统开关仍为0时通过9项回归（两项链接因无权限跳过）；`installed-health-2` 的初始化／7个原生DLL／内核42与关闭／Yazi生命周期通过。完整配置另暴露字节码缓存273字符路径，配置仅对Windows关闭该磁盘缓存，本机验证后同步portable；`full-profile-cache-fix-receipt.json` 已原断言通过Python host／Molten注册。只更新刚创建且SHA未变的QA profile，其他用户配置不覆盖。
- `image.close()` 已修复把Noice浮窗计入普通窗而报E444，新增真实浮窗定向回归；本机／portable共28项检查通过，配置 `665a31f1`／源码 `e50455a` 均已推送且跳过云CI。正式Launcher的GUI3及无配置最小对照均在D3D12 ResizeBuffers报0x887A0005，系统OpenGL也建窗失败；宿主PD27.0.3、虚拟显卡驱动状态OK，[官方支持范围](https://kb.parallels.com/en/129497)到DirectX11.1，不能单独归责驱动。
- 独立Mesa26.2.4 llvmpipe软件OpenGL的 `windows-gui-5` 真实前端功能检查全部通过：中文／空格／apostrophe PNG、损坏恢复、8/6图片配额、Molten Tab释放／恢复、Yazi原生解码／geometry／退出、ConPTY字母雨动画／resize／q零退出；两Mesa模块已在真实前端核对加载路径，全部自有GUI已退出。完整视觉／手动键鼠与硬件GPU未通过；只看到系统提示层后方部分实际图像，未处理账户登录。
- PD桌面“Glow（PD 软件兼容）”入口已创建并实际 `--help` exit0，回执 `software-gl-entry-help-receipt.json`；依赖 `C:\GlowDev\GraphicsQA\MesaApp` 到Stage的本地链接，须保留Stage，未替换系统DLL或产品默认后端。Windows PowerShell5.1中文文件解码问题已明确UTF8 BOM，构建脚本／完整安装QA的中文路径AST实测通过；C#编译显式UTF8。第16版仍待完整候选安装器验收后发布。
- [39464264245](https://github.com/Ysrae1/neovide/actions/runs/39464264245) 已通过功能验收并生成完整EXE（Inno压缩970秒），实际安装检查exit5，尚不能发布；原因已定位为262字符目标路径使Inno MoveFile报code3。839MB artifact已完整下载／解包至 `target/glow-windows-native-assets/worker-39464264245`，EXE825,409,484字节；原ZIP保留 `target/glow-windows-native-assets/artifact-39464264245.zip`。后续优先PD本地验证短目录安装及路径检查修复，不再启动新的云端构建。
- 发布页第16版仅保存未部署：源码 `d56237c81e1d7100b04718ef4994dbfb5dc5468a`，Windows入口已准备指向计划中的原生预览包；源码包 `target/glow-site-windows-native-20261021-qa/site-artifact.tar.gz`。须等EXE安装验收并实际发布后才能部署；当前线上仍第15版字体修复。
- [39462457618](https://github.com/Ysrae1/neovide/actions/runs/39462457618) 已实际复用完整依赖缓存，5分钟完成本轮流程；原生 Windows Yazi 完整生命周期、完整配置／Python host／Molten 注册和真实 Notebook 内核42均通过，最终 Inno6.7.1 编译被常量名称及 Win32 类型别名拦截。安装脚本已统一自定义名称／32位 Setup ABI 类型；官方6.7.1在隔离瓶的完整夹具编译 exit0，记录 `target/glow-inno-671-qa/`，待云端产品包编译及安装卸载检查。
- Windows 运行 [39458079662](https://github.com/Ysrae1/neovide/actions/runs/39458079662) 仍在 Yazi 验收失败，但63,866文件的完整组装 checkpoint 已保存（压缩约1.16GB）。诊断和隔离 Windows 程序复现确证：Yazi Lua `os.getenv` 将 `YAZI_FILE_ONE` 中的中文读成 `??`；改用 ASCII `file.exe` 并从包内 Unicode PATH 查找后，真实 bridge 的 clear／preview 恢复。启动器与 QA 环境已按此修正，待原生 Windows 缓存运行确认。
- 同步 UTF-8 overlay 读写（配置 `5ffd624f`），并让 Yazi／完整 profile／实际 Notebook 内核三项独立检查汇总结果后再决定能否打包；原断言保留。隔离 C# 编译、PowerShell 解析与本机 Yazi 生命周期通过，复现证据 `target/glow-windows-native-assets/yazi-mime-probe/result-relocated-bridge-path.txt`；未把 Wine 结果当作实机验收。
- 2026-10-21，Codex：Windows 运行 [39453410597](https://github.com/Ysrae1/neovide/actions/runs/39453410597) 已通过 Rust 269 项、搬迁启动／profile 初始化、Python 与6个 Mason 命令、7个原生 DLL 加载及14项隔离配置检查；Yazi 能打开但原生图片预览自定义事件未返回，Notebook 内核／安装卸载验收尚未跑到，EXE 未生成。
- 增加 Yazi 私有测试日志与实际 file.exe MIME 诊断，生命周期断言保持；增加已封装依赖 checkpoint，保存阶段在完整编译／组装后，恢复逐文件验 SHA，刷新当前配置／运行时／启动器并重跑功能验收。checkpoint 合成10项、配置刷新／重复封印及凭据保护、Windows PowerShell 解析检查通过；待下一次 Windows 运行验证，尚无已保存完整依赖缓存。
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
