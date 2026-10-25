# Neovide Glow Preview

基于 [neovide/neovide](https://github.com/neovide/neovide) 的实验分支 `glow-preview`，加入可调节的柔光效果。保留上游 MIT 许可证。这是第三方分支，尚未合入官方版本；本轮 Mac 预览包采用 ad-hoc 签名，未做 Apple 公证。

## 当前维护状态

### 2026-10-25 v1.0 冻结、结构整理与 GitHub Pages 上线（Codex）

- 按用户授权保存原始完整基线至 `showcase/review/release-20261025/baseline/`，整理提交 `9cb2353`；页面样式/控制脚本拆出，实际显示与离屏测量共用 `story-copy.js`，清除空缓存/只写状态。旧测试页与未使用素材可恢复归档；现有Safari零尺寸fixed/sticky锚点、合成轨道、动画和自然文字排版保留。最终编辑源码 `f1e01a8e`、本地网站标签 `v1.0`。
- 宽屏快捷栏71px过粗已确认是减少动态模式给隐藏测量节点施加0.01ms全属性过渡，读到了旧16px字号及旧宽度；仅关闭测量节点过渡，单行40px、375px宽多行98px。288组DOM写入序列等价；1200/375px四组中英/浅深色组合共96阶段尺寸与文案对照通过，1468媒体引用无缺失，IAB与原生Safari实际滚动检查完成。没有新增手机快速触摸录屏或软件安装验收。
- 新官网 `https://ysrae1.github.io/neovide-glow/` 已built并强制HTTPS；公开官网仓库 `Ysrae1/neovide-glow` 的main与v1.0均为 `6a9faf2084afaeeaf4a45a3f9e6aaacbdd60e133`，1121静态文件与冻结源码逐字节一致。线上代表性8文件字节一致、7个下载链接及官网源码ZIP均HTTP200。用户指定新主入口后取消旧Sites上传流程；原官网第32版改为仅所有者可访问，保留源码/历史版本，可恢复公开。
- 软件发行 `https://github.com/Ysrae1/neovide/releases/tag/v1.0` 已公开，源码归档基点 `34ab3ddd`；Mac 2026.10.21与Windows 2026.10.23.6两架构共14项原件原样保存，另附统一manifest/校验清单，共16资产远端大小及SHA256全部核对。未重编译或替换本机安装，原包内部版本/签名/配置/依赖入口及旧发行保留；冻结清单见 `extra/releases/v1.0.json`，收据见 `target/releases/v1.0/`。
- 验证证据在 `showcase/review/release-20261025/`；自有8771验证服务与临时浏览器页已关闭，既有8767/8770预览保留。软件仓库主页和README已改指新官网与v1.0发行。


### 2026-10-25 当前发布页本地版用户确认收敛（Codex）

- 用户先确认 `track-compositing1` 顶部内容延伸“基本上可以了”，随后明确纵向内部空行指各项文字从多行变少行时的预留；核对期间最终反馈“现在都正常了”“感觉终于完成了”。保留当前版本，不追加布局修改；文字浮现／图片飞入仍保留，动效关闭曾由用户明确确认是自己切换了开关。
- 本次核对未改正式页面代码；375px Notebook标题三行→两行实际高度146.39→97.59px、标题到说明仍16px。临时检查页与8771独立检查服务清理，原8767及手机8770预览保留。此前快速滑动缺绘没有新增专门录屏验收，不扩大用户本次确认范围。仍仅本地未提交／未发布。

### 2026-10-25 图文自然高度修正与 iOS 顶部绘制分层，内容延伸待验（Codex）

- `showcase/dist/assets/story-layout.js` 不再分别取标题、说明、阶段栏等内部项的双语最大高度；保留整块最大外部占位，内部按当前内容自然排版。`workflow-lab.css` 清除内部最小高度、阻止阶段按钮拉伸，并显式隐藏空快捷键行；`workflow-lab.js` 增加内容容器，只在宽屏将当前实际文字整体垂直居中。入口缓存 `natural-copy3`；仅本地未提交／未发布。
- 1440×900 TeX 三阶段及英文阶段实测：图片中心、外部占位中心、实际文字中心均为450px，差值0；标题到说明16px、说明到阶段栏24px，中文阶段栏46.5px、按钮36.5px。402×800仍上图下文，图片顶96px、图片到文字26px，空快捷键行不占位。语法／diff检查通过；截图 `showcase/review/reconstruction-20261025/wide-natural-copy-centered.png`。未把桌面窄屏当作手机动态验收。
- 用户最短触发为**从页顶向下到第一内容块出现**。实际失败位置 y3417：仅隐藏快捷栏仍纯色，导航也隐藏后纹理恢复，仅恢复快捷栏又复现。`ios-check=1` 的对照按钮仅显式本地启用。导航与浮动快捷栏改为0×0 fixed锚点、实际组件作absolute子项，缓存 `edge-anchors1`；用户真实滚动后纯色消失，但确认文字仍被系统栏下沿裁切，不能以纹理恢复宣称解决。证据 `ios27-edge-{failed-before-toggle,legend-hidden,nav-and-legend-hidden,legend-alone-reproduces}.png`、`ios27-edge-anchors-after-native-scroll.png`（同review目录）。
- WebKit官方源码的 `viewportConstrainedSublayers` 对直接合成到根视图的sticky额外建立viewport裁切，与边缘取色是两条路径；官方测试 `compositing/ios/immediate-scrolling-clip-sticky-element-to-viewport.html` 明确覆盖该行为。仅给既有 `.wf-track` 加静态 `translateZ(0)`，使其成为非根合成祖先，原生sticky／几何／阶段不变；CSS缓存 `track-compositing1`，备份 `before/track-compositing/`。源码支持此候选，但不能视为同版运行证明；实际内容进入系统时间后方、回滑稳定与快速缺绘仍待验收。
- 按用户要求重启Device Hub并保留模拟器；用户随后可手动滑动。控制工具拖动曾直接冲到页尾，小幅滚动和诊断点击未可靠改变位置，停止反复工具手势，不当作验收通过。已提供8770手机预览当前候选（HTTP及CSS版本确认）；8767原服务保留，未提交／发布。临时额外浏览器页已关闭，既有用户页面保留；未改系统输入或网络设置。

### 2026-10-25 历史滚动叙事恢复与移动端停驻候选（Codex）

- 实际重读历史对话“发布页交接：图文对齐、间距与滚动阶段”、`showcase/DESIGN.md` §9／§14.1及 `showcase/review/reconstruction-20261025/before/workflow-lab.js/css`，从旧代码恢复文字浮现、前块退出、新下滑门槛和单向完成记忆。文字先以850px完整居中出现、随前块保持间距上移，到屏幕中点后脱钩；浮现完成且前块实际内容完全离屏才记基线，新增下滑才引入图片。原真实文本触边侧对齐、宽度重排及动效时长保留。
- 当前 `workflow-lab.js/css`、`story-layout.js` 改为0×0原生sticky锚点承载可见溢出图文，轨道明确高度，由浏览器连续处理两端边界；不再由JS跨界切换relative／sticky。WebKit官方源码确认边缘扩色判断读取自身border box，但不把main源码当作iOS27.2实机验收。提前一屏sticky候选曾被用户确认跳回消失但顶底遮挡回归，已撤回，禁止继续调guard重复该分支；失败录屏及源码保留。
- 手机只避让顶部导航，顶距safe-top+96px（14+58+24），不计快捷键栏；导航收放不移动图文。≤860px按历史要求强制上图下文，双语／全部阶段预留最大文字高度，沿用同一节点。三份入口缓存 `narrative-anchor2`；修改前备份在 `showcase/review/reconstruction-20261025/before/reading-state-restore/`。
- 已验1000×900完整居中浮现、前块未退出不入图、记录基线后新下滑触发、真实触边侧对齐、阶段及语言位置稳定；402×800终端三阶段图片顶96px／文字顶304.54px保持，宽窄屏无横向溢出／页面错误，减少动态下9块直接可见。Mac Safari实际窄屏跨退出边界后返回，停驻图片与导航保持间距；JS语法和diff检查通过。
- iPhone18Pro／iOS27.2已加载本候选，导航跨区到下载后返回、终端阶段按钮2→3→1实际检查图片／文字位置不变，顶部导航展开仍有留白，顶底纹理正常；证据 `showcase/review/reconstruction-20261025/ios27-narrative-anchor-{intro,download,phase1,phase2,phase3}.png`，宽屏／Safari证据同目录。**快速触摸到底回滑仍未验收**：控制工具可点按但不能可靠驱动拖动，键盘滚动也无效；本轮结果不代表该项通过，不再要求用户反复手测。录屏与键盘捕获关闭，8767原服务及8770手机预览保留；仅本地未提交／未发布。

### 2026-10-25 展示块回滑空档与阶段跳动修正（Codex）

- 用户确认巨大空档出现在跨展示块回滑；原 CSS transform scroll timeline 在 iOS 缺图文，桌面同位置有上一块内容。JS逐帧top候选消除空档但整块跳动；CSS timeline动画top仍跳，均已撤回。后续用户明确为同块各状态切换时整块上下跳；402宽逐阶段实测标题、说明、图片及整体高度不变，不归因为文字换行。
- 最终 `workflow-lab.js/css` 改成进入前relative/top0、停驻段原生sticky、离开后relative/top R；仅跨边界更换定位，不逐帧移动整块，也不让离场的宽sticky祖先跨浏览器边缘。P+R占位、96px间距、阶段与入场历史保留；HTML缓存 `bounded-sticky1`。JS语法、宽窄屏往返与三阶段固定位置、中英／减少动态及控制台检查通过。
- iPhone 18 Pro／iOS27.2本轮手势录屏跨展示块、阶段、页尾回滑及回到首屏；用户明确“切换稳定，纹理正常”。记录 `showcase/review/reconstruction-20261025/ios27-workflow-bounded-sticky.mp4` 和同名前缀contact图；本轮范围通过，不扩大为所有快速缺绘／真正文档首尾覆盖已解决。首个录屏与两候选保留同目录供追溯，不继续该失败分支。
- 录屏及键盘捕获已关闭，临时IAB标签／视口已清理。原8767服务保留；按用户要求另开手机本地预览8770（Codex进程75735，执行会话74114，仅提供showcase/dist），HTTP 200已确认，保留供手机访问。仅本地未提交／未发布，官网仍32版。

### 2026-10-25 页尾回滑顶部遮挡与快捷键漂移收敛（Codex）

- 用户明确触发为“滑到最底部再往回滑，停下仍遮挡”；新录屏最后数秒确认顶部纯色持续、底部已恢复真实内容。402宽几何对照显示原 legend sticky 被 main 尾界推至 top=-69／bottom=19，跨过顶边；footer 位于 main 外。相关 WebKit 固定／sticky 颜色延伸机制支持这条线索，但不把整个浏览器实现认定为已定因。
- `legend-floating.js/css` 最终改为永久双语最大占位，同一组件原位 relative、浮动时原生 fixed，分离可见阈值和 CSS 固定坐标；不在滚动时搬节点。scroll timeline 候选虽恢复顶部纹理却在 Safari 工具栏收放时漂移，已撤回并移除诊断分支。最终用户手动往返明确“没有漂移”，37.77秒模拟器录屏中回滑停止后顶部真实文字／纹理恢复；已设为默认，缓存 `viewport-pin1`。
- 按用户补充，顶部导航回滑展开后停止1000ms自动收小，页首保持展开；hover仅用于精细悬停设备，键盘focus-visible保留展开。浏览器实际回滑从expanded转compact、最终40px且legend间距10px通过；模拟器已加载最新版并显示收小。中英、折叠、减少动态占位检查及JS语法通过。
- 证据在 `showcase/review/reconstruction-20261025/ios27-bottom-reverse{,-scroll-pin,-viewport-pin}.mp4`、`ios27-viewport-pin-motion.png`、`nav-idle-compact.png`；录屏与键盘捕获均已关闭，临时桌面标签／视口已清理，8767原服务保留。仅本地未提交／未发布，官网仍32版；快速滑动缺绘、真正文档首尾纹理覆盖与初始hash时序仍未完成，不能称整体重构验收通过。

### 2026-10-25 本地整体重构与 iOS 复验继续（Codex）

- 用户恢复本地重构／测试后，已新增共享 `viewport-runtime.js`；`workflow-lab`／`story-layout` 改为自然流图文、双语最大占位与独立单向入场历史，移除负 margin／滚动补偿。`legend-floating` 保留同一组件，初始文字、到顶变玻璃；色场改为文档连续镜像纹理，resize 纳入原渲染节拍。官网仍第32版，未发布、未提交；未改源码或 Windows 配置。
- iPhone 18 Pro／iOS 27.2 实测仍有上下纯色区及快速滑动缺绘，用户手动往返录屏已确认，不能称重构验收完成。取消图文原生 sticky 在部分中段有效，现以标准 CSS scroll timeline 保留停驻（支持时）；桌面位置核对通过，手机完整动态仍待验。剩余悬浮全部取消的临时对照仅完成首屏／中段，用户反馈后已恢复正常导航与快捷键，未完成真正页尾对照。WebKit 原生首尾裁切与固定元素纯色延伸是相关机制，尚未与设备构建逐项对应，不能把全部缺口归为浏览器限制。
- 已确认并修复页脚压暗：inline 文字背景的 overlay 混合影响后续普通字；单变量 normal 对照恢复，单纯隔离层只恢复普通字而链接仍暗。最终只将 `.link`／`.wf-source a` 置于 inline-block 绘制路径，保留原色场／颗粒；模拟器中文及390宽英文深浅色清楚，无横向溢出。根静帧、文字混合与取消悬浮实验已移除，未证明根静帧能修快速缺绘。
- 按用户新要求，主页及手册窄屏语言切换用地球，主页下载用圆圈向下箭头，600px 以上保留文字；`locale.js` 仅更新标签，保留 SVG 与可访问名称。320／390／430／600／900宽度及中英切换通过，模拟器已显示。当前图片提前约一屏加载，组件色场提前约两屏更新；这不等于浏览器完成屏外分块绘制。
- 证据统一在 `showcase/review/reconstruction-20261025/`：`ios27-manual-roundtrip.mp4`、`ios27-text-{blend-normal,isolation,block}.png`、`reported-{top,bottom}-extension.png`、`ios27-nav-icons.png`。JS语法检查通过；当前仍欠快速双向缺绘、完整首尾覆盖及初始 hash 锚点时序验收。录屏已停止、模拟器键盘捕获已关闭，原8767服务保留；临时浏览器尺寸已恢复。下一步须先定位实际绘制瓶颈，不继续盲目增加预热距离或背景层。

### 2026-10-25 用户要求暂停，下一聊天整体重构（Codex）

- **当前授权：只记录、不再实施。** 用户要求先暂停，之后到咖啡店新开聊天整体重构；不是继续逐点补丁。官网保持32版，未发布新版本；没有创建新的视口／滚动重构模块。所有子代理已完成或停止；本轮8769手机预览已关闭，原8767／8768服务归属此前任务，保留。
- **用户确认的失败：** iOS Safari快速往返后系统栏下纯色／多处宽黑带与断裂绘制复发；已入场图片回看仍缩小；02/09回看01/09时图文遮挡、图片像未计入队列；英文快捷键裸行穿过图片后方。Mac Safari快速滚动同样有来不及绘制感；用户明确Chrome也有模块遮挡，不能归为Safari专有。单向语义保持：上方离屏的已入场内容回看直接呈现；只有回看继续使其从下方完整离屏才重新武装入场。
- **已审出的结构问题，尚未整体改造：** workflow图片／文字绝对定位、相邻feature负margin拼接；innerHeight变化可让flow/sticky布局切换并重算占位。legend在普通无玻璃inline与fixed之间拆装，measureInline还对活组件拆类测量。色场只覆盖上次JS滚动窗口，异步滚动可露出窗口外；root合成均色又覆全篇veil会二次压暗；renderer的resize直接render绕过30fps（内存桩320ms内20次resize产生20帧）；未统一VV.scroll／scrollend收敛。录屏中具体黑带归因仍需几何＋动态实证，不把假设写成已解决。
- **未验补丁须谨慎接手：** 本轮layout_solver仅改`showcase/dist/assets/workflow-lab.js`，加入flow可见完成记忆、entryProgress高水位及data-entry-*；语法／逻辑检查过，尚未GUI动态验收、未提升HTML缓存版本、未发布。此前underpage/overscan/absolute/移除skip等本地代码及诊断仍保留；不要以已有代码当通过，不要继续叠加同类补丁。下一步应整体设计稳定占位、唯一视口/滚动状态、独立入场历史、全程背景覆盖与原生sticky玻璃控件，并覆盖中英文、深浅色、减少动态效果及Mac Safari/Chrome/iOS实际往返。
- **证据已留在项目内：** `showcase/review/field-performance-20261025/mobile-safari/reported-123728.png`、`reported-123825.png`、`reported-124028.mov`（9.53秒/120fps）、`reported-124556.png`、`reported-124756.png`；`124028-contact.png`与`124028-4p5.png`是已提取预览。原临时上传路径不应作为唯一证据。模拟器为Device Hub里的iPhone18Pro/iOS27.2，原8767页可继续复现；不要把桌面窄屏当真机验收。

### 2026-10-25 页首状态栏颜色衔接，本地手机复验（Codex）

- iOS 27.2 的 y0 单变量对照确认：仅将 html background-color 设洋红，原黑带同步变洋红；对应 WebKit underPageBackgroundColor 只读取根底色、不含背景图片的路径。移除临时洋红实验，保留截图证据 `mobile-safari/ios27-root-magenta.png`。
- 本地从同一 decodedFrame 的 viewport y0（扣除 overscan）取小样，合成当前玻璃 tint，供根纯色回退；非继承变量纳入圆角绘制白名单。减少动态效果下主题切换经下一渲染机会重取根材质，深浅色同步已在模拟器实看；中段 y464 真实文字仍可经过状态栏。新增文档顶部64px衔接层覆盖首屏独立柔光，最终手机视觉衔接仍待用户实看，不称完整纹理铺满。
- 用户改为只要本地手机地址，已停止上线准备；官网仍32版，未保存／部署新版本，托管源码检出未修改。新增本轮局域网预览服务8769（会话13828，仅dist），HTTP200；原8767／8768保留。单向动画完整动态、页尾与快速往返仍未完成验收。

### 2026-10-25 已连接 iOS 模拟器，延伸与磨砂仍在本地验收（Codex）

- 修正先前“Simulator.app 缺失即无法测试”的判断：本机 Xcode 27.1 使用 Device Hub；经内部主程序启动并结束本轮启动的未完成 trampoline 后，CUA 已连接 iPhone 18 Pro / iOS 27.2，实际打开 Safari。模拟器键盘捕获已关闭；用户在模拟器拍的两张截图已保存到该模拟器 Photos。
- 本地新增同一 WebGL 帧的上下扩展域，根背景／文字／阶段 Canvas 共用帧几何，异步解码保留旧几何；GPU 640 边长、30fps 未增加。实际 iOS 已编译并显示 webgl-shared；坐标契约通过。固定背景原路径仍造成顶部实色与磨砂边界，不能宣称已修复。
- 显式本地 `ios-absolute=1` 保留原玻璃参数、改两背景层按文档坐标跟随；iOS 中段 y928 已看到真实图文经过顶部、上下磨砂连续。页首仍黑；放开负 top 后页首仍未通过，页尾及快速往返、单向完整动态复验未完成。当前交给用户查看 `http://127.0.0.1:8767/?lang=zh&ios-check=1&ios-absolute=1&v=skip-removed1`；面板已收起。
- 用户要求移除屏外左上角入口，已删除主页／手册的“跳到正文”链接及相应样式／绘制匹配，语法与入口检查通过；未改 main 语义。官网保持第32版，全部本轮改动与 `ios-*` 诊断未发布；证据在 `showcase/review/field-performance-20261025/mobile-safari/`，原8767／8768服务保留。

### 2026-10-25 第32版手机验收失败，暂停继续宣称已修复（Codex）

- 用户真机明确反馈：Safari上下仍被系统栏遮挡；减少动态效果滚动卡住；正常模式回看仍重播。线上HTML及5资产已核对匹配32版，Cloudflare仅注入验证脚本，无旧文件／包装iframe证据；报告`target/showcase-publication-20261025/mobile32-delivery-check.json`。
- 修正验证边界：此前只有桌面窄屏和状态检查，没有iPhone Safari验收。本机simctl列出iOS27运行时，但Simulator.app缺失、CUA无法打开图形模拟器，未启动或操作iOS设备。不得把运行时列表或桌面Safari当iPhone验证。
- 本地workflow-lab.js／section-reveal.js窄修了阶段回看仍animateText、快速越过early return漏记完成、reduce高度变化自动scrollTo、模式切换未失效布局缓存及普通section无条件rearm。仅语法通过，尚未动态验收，未发布；官网保持32版。
- 系统栏新依据收敛到WebKit固定边缘extension机制，不能继续调viewport-fit／theme-color并声称有效。建议只切换固定背景组件的受控对照，尚未实施或宣称真机通过；当前手机目标未完成。

### 2026-10-25 手机上下延伸、扩大色场预热与单向入场上线供真机查看（Codex）

- 按用户“直接上线，手机看”要求，官网第32版已`succeeded`；源码`c152ddefacd45858e5e8bdf596b30945ed3c8526`，部署`appgdep_6add66a4bfec8191a307bc07104dfac1`。相对31版仅5运行资产及3页viewport／缓存；回执`target/showcase-publication-20261025/mobile-edge-publication.json`。
- 三页viewport加cover；根文档画布用同源实时帧与viewport尺寸、scroll坐标延伸到系统栏后，frame／size／position注册为非继承变量并在圆角observer中视为纯绘制，避免全树／全部圆角重绘。悬浮nav避safe-top，正文不加整页安全区padding；图文高度预算只扣安全top一次。iOS不可靠的background-attachment:fixed未用于根画布方案。
- 色场从屏外60px扩大到上下各两屏，跨越半个预热带时在rAF扫描当前采样范围；保留单WebGL、640边长与同一解码帧。普通区块与story均记忆已完成入场，从上方离开后回看直接呈现；只有回滚使其从下方离开才重置，图片不倒放。
- 基础已验：JS语法、79个本地引用；390×844下cover、根frame非继承、跨±2532px跳转后可见采样与背景同帧、无横向溢出／页面错误；单向状态逻辑边界检查通过。用户要求尽快上线，未追加Safari动态／iPhone真机系统栏验收，不把桌面尺寸模拟称真机通过。依据／备份在`showcase/review/field-performance-20261025/mobile-bottom/`、`mobile-field/`；等待用户手机实看。

### 2026-10-25 Safari S217 快捷键栏收起外伸修复上线（Codex）

- 官网第31版已`succeeded`；源码`9370a00dc1ad0e2cb21a35949e71a55f6bd27be7`，部署`appgdep_6add614714708191b68eab3742cfc459`。相对30版仅`legend-floating.js`、`continuous-corners.js`和3页4处缓存引用；回执`target/showcase-publication-20261025/legend-sync-publication.json`。
- 用户09:20日志S217对应视频4.183333秒：宿主已到右侧圆点位置，旧展开底材仍向右延伸，S218恢复。源码与兼容回放确认绘制层自身子树变化被误当内容变化，重新测量提前取消宽动画；另有ResizeObserver尺寸下一rAF才提交轮廓的滞后。现过滤绘制层变化，浮动栏尺寸在RO同帧绘制；Safari实测原WAAPI宽高关键帧运行而布局直接取最终尺寸，故仅连续角兼容路径按原360ms／原缓动显式插值宽高与morph，原生corner-shape路径保留WAAPI。
- 已验可见Safari756×859深色收起51样本／展开54样本、浅色收起56样本及无诊断正式入口，实际宽度连续变化、RO后右边缘差0–0.015625CSSpx、页面错误0；兼容路径快速反向从当前宽度接续，Chromium原生路径收起121样本宽度单调。初始Safari隐藏导致帧暂停，经用户并排保持可见后完成验收；无新增手机／Windows浏览器验收。
- 录屏邻帧、原始与修复采样、Safari实际截图和来源匹配记录在`showcase/review/field-performance-20261025/legend-s217/`。临时probe与error监听均已从dist入口移除，检查页关闭、用户原有Safari两页保留；8767／8768服务保留。

### 2026-10-25 图文宽高联动与阶段控件修复上线（Codex）

- 用户授权睡后完成测试并直接上线；官网第30版已`succeeded`，源码`cd77ed35fd3a1a697ab29f45f29fbac7ad533167`，部署`appgdep_6add08e46dec81918391e511cac13956`。回执`target/showcase-publication-20261025/height-fit-publication.json`；仅8项运行资产及3页引用相对v29变化，745项原有文件保持原样，无删除。
- 新增`story-layout.js`，按中英文所有场景／阶段测量最长控件行和最高图文组合；先消耗外侧空白，再固定文字字号与列宽缩图，按窗口可用高度计算转竖排时图宽。不同语言可在同宽度采用不同布局；确实过矮时采用可滚动自然流，避免硬裁切。窗口／语言变化保留选中阶段，并在计算各场景高度前统一重置入场基准。
- PDF控件统一为“源码 ↦ PDF / PDF ↦ 源码”（英文Source / PDF）；动态色场恢复。沿用阶段组物理像素对齐及兼容路径三个标签同Canvas字形的边缘／字色修复；连续轮廓保持。S329–335快速切换定位为阶段高度重新测量改变阶段起点，现仅窗口／字体／语言变化更新入场距离，并使用最高阶段固定占位。
- 已验IAB 380–1600宽度、480–1200高度及恢复、同宽930×862中英文切换、正式无检查入口与减少动态效果；Safari实际图文完整，原闪烁边界66连续采样仅一次正常阶段切换、控件y恒492。先前Safari浅深色动态边缘测试及Chromium原生／兼容路径结果沿用；无手机真机或Windows浏览器新增验收。证据在`showcase/review/field-performance-20261025/layout-height-0220/`，旧录屏对应资料在`jitter-0201/`。
- 发布包无布局检查／手动录制入口；临时检查脚本已移至review。本地显式phase-record入口保留，8767预览服务恢复并保留，8768设置服务未改；未暂存或提交其它源码／Windows改动。

### 2026-10-25 已确认闪变／下移修复发布，边缘与同组字色本地修复（Codex）

- 用户确认当前本地正常并授权先发布；官网第29版已 `succeeded`，源码 `2057e4688c82210e2561cf6229154dd8f361ccc4`。冻结5个运行文件，仅同帧发布样本／失选清理与阶段文案先于测量的修复；无薄荷绿、强制不透明或录屏诊断。回执 `target/showcase-publication-20261025/accepted-phase-layout1-publication.json`（target链接实际在neovide构建目录）。
- S526已定位旧文案宽度下先换新标题造成约62.375CSSpx单帧下压；当前593×862同轨迹IAB回放420次布局采样稳定，用户最终确认正常。S116日志明确运行临时 `_s526-before` 旧版；旧入口已停用并跳当前页，记录条／JSON加入实际源码版本。原始证据在showcase/review/field-performance-20261025/{s526,s116}。
- 用户00:24录屏的PDF双向定位组：S105右侧少1录屏像素，S109底侧少1像素，选中字形同时偏移；S105→106两个未选中标签输出强度约减半，CSS色值未变。原日志跟踪错了屏外theme组，不能用于受影响按钮的几何结论。证据集中在`showcase/review/field-performance-20261025/edge-0024/`。
- 本地`phase-labels1`：阶段组按DPR对齐并跟踪剩余位移动画；兼容路径三个标签共用现有Canvas绘字，未选中文字只按字体／大小／颜色变化重画，保留DOM布局与无障碍。原连续曲线、clip、底材及disabled/inert逻辑保留，原生状态／appearance／层级试验均撤回；改动为workflow-lab.js、brand-field.js/css、phase-flat-fill.js及HTML缓存。
- 已验真实Safari27.2（574×838/DPR2）浅深色进入／返回及连续往返各18次实际截图、三个阶段切换，所测缺边与同组字色突变未再出现，3个文字Canvas且绘制失败0。Chromium156强制兼容回放481次几何读数物理像素误差0，另测原生corner路径无错误；几何读数不是Paint帧验收。新改动未发布，官网仍为已确认第29版。
- 临时edge-probe已从运行入口移至上述review目录，自有Safari／IAB检查页已关闭、视口覆盖已恢复；用户页及8767／8768服务保留。

### 2026-10-24 23:44 本地紫色闪变新对话交接（Codex）

- 当前目标：查清并修复状态往返切换、上方文案高度改变引起按钮竖向位移时的异常紫色；最新复现同时涉及Safari与Chrome，不沿用“Safari专属引擎问题”的已确认结论。优先Safari S83/S86及Chrome S399，不再扫描整段找更多例子；用户要求新开本地对话继续。
- 最新5个输入已保存在`showcase/review/field-performance-20261024/manual-2337-2340/`：safari.mov/json、chrome.mov/json、chrome-s399.png，原路径映射见inputs.json。现有本地入口`http://127.0.0.1:8767/?lang=zh&field-solid=mint&stage-opaque=1&v=mint1#feature-theme`，固定#70ffd4 PNG、全程不透明、自动S序号/JSON记录已就绪；服务未停止。
- 本地候选由`brand-field.js/css`和`phase-flat-fill.js`对兼容路径选中按钮预合成色场/颗粒/字形，保留DOM布局与基线探针；默认渐显只乘底材alpha，字形alpha1。HTML及JS缓存mint1/flat3；local诊断文件保留。已做语法、Chrome原生/强制兼容、Safari静态920帧检查；动态录屏有采样开销且无录屏性能复核未完成，不据此宣称最终解决。源码/实验在既有investigation.md和manual-214524/flat-fix目录。
- 上缘缺切子代理只读报告`showcase/review/field-performance-20261024/phase-corner-clip/findings.md`：轮廓拟合约0.05px，缺约1截图像素顶行，具体裁切层未定；未修改轮廓。根代理已停止操作GUI，未对最新两段录屏做新的分析或改动。
- 发布子代理已完成官网v28，status=succeeded，源码`5db6fcb989e3d768048595bfa7525eb216cc1be6`；回执`/Users/ysrae1/Dev/neovide/target/showcase-publication-20261024/phase-flat3-publication.json`。发布源冻结8文件，未带本地mint/录屏诊断；后续调试只改local，不把发布捆进修bug。根仓库已有Windows等脏文件不动，showcase为独立main仓库。

### 2026-10-24 Safari 闪变触发链与颜色标记对照（Codex）

- 只分析用户指定的 S152–154→S157、S188–190→S194：暗帧按钮约RGB(124,63,91)，亮帧约(253,125,166)；同次日志固定PNG、opacity=1、无材质属性切换。S序号是rAF同步回调，不是Paint／录屏帧号，不能以跳号直接认定浏览器丢Paint。
- 实际Safari单变量ABA：父填充仅改为绿色，按钮由粉色突变黄色；目标填充computed背景混合全normal时12秒/690视频帧没有串色，恢复normal,overlay,normal后12秒/689帧中193帧再次变黄。已证实父底材参与overlay路径的最终像素，尚未锁定WebKit内部具体错误步骤；证据及主源链接在既有investigation.md与manual-214524目录。
- 独立伪元素颗粒混合仍串色；同源SVG按DPR2固定360²PNG后也串色，两个保留材质候选均停止并还原。运行源码未因此修改，未发布；故障尚未修复。8767 PID84232继续服务；8768旧进程退出，已由本会话恢复PID55780／session43519，/settings HTTP200，参数文件未改。


### 2026-10-24 用户手动录屏／同钟日志对照（Codex）

- 用户明确滚动症状是突发闪暗／恢复；改由用户手动操作，要求画面与日志按同一时间节点对齐。当前本地 `field-solid=1&stage-opaque=1` 用固定640×332 RGB粉色PNG替代动态色场，阶段底材与图片alpha全程1；几何滚动进度、颗粒、材质和连续轮廓保留。默认／线上路径未切换。
- 新增显式诊断手动控制条，先录屏再点开始；画面自动同步序号Sxxxxxx与毫秒计时，日志按每个同步回调保存同源时间节点及trace-to-video偏移；不要求用户给高频闪变打点，停止后用户点击下载JSON。最长90秒，不自动滚动或截图；后续按用户新授权结合同次录屏与日志分析，不再把正常渐显当作异常证据。
- 展开缺角子代理已以定位HTML盒包住完整SVG，缓存svg-box1；待用户观感确认。8767 PID84232与8768 PID91315均已恢复并验HTTP200，参数文件未改。此前原生Paint时间线与页面日志已保存在既有调查目录；尚未建立闪变因果链，不宣称根因已定位。线上未部署。


### 2026-10-24 Safari 图标裁切修正与阶段按钮 inert 本地候选（Codex）

- 用户反馈 alpha 遮罩候选无改善，已完整撤回；后续明确本地修改／用户反馈，不走线上上传部署，不再截图或图像分析。阶段按钮保留 group.inert 阻止交互，移除每次滚动重复写原生 disabled，增加点击入口的 inert 校验；这是待用户反馈的单变量候选，未确认明暗根因。
- 用户补报右侧圆形说明按钮闪电缺截；源码确认 continuous-corners 的子内容裁切仅用 offsetTop，漏掉 toggle 的 translateY(-50%)。已仅为纯平移2D矩阵补回位移，保留连续圆形与完整原SVG图标；依据 CSSOM View offsetTop 忽略变换的定义。非平移路径未扩展。
- 语法与差异检查通过；本地 index／handbook 缓存已更新。线上未上传／部署，仍沿用此前第27版；实际 Safari 观感由用户验证，8767／8768服务保留。


### 2026-10-24 Safari 阶段按钮本地 alpha 候选（Codex）

- 按用户最新要求停止图像分析，后续直接改本地代码由用户反馈；当前仍未确认根因。仅 `showcase/dist/assets/brand-field.css` 将连续角兼容路径中选中阶段按钮的整组 opacity 改为填充 alpha 遮罩，描边／外阴影单独沿原渐显进度；两 HTML 缓存引用已更新为 `safari-alpha1`。待用户实际滚动反馈，未发布。
- 此前 normal-blend 对照没有消除所见变化；固定帧／同色资源对照未形成足以认定根因的结论，不再扩展该分支。用户明确小字无此明暗故障，撤回把小字色场变化当故障证据的判断。临时 probe 已从 dist 移到既有调查目录 `scroll-blend/`；正式连续曲线、颜色与颗粒保留。
- 线上仍第27版；8767／8768服务保留。无新增常驻诊断进程；不再自动截图／录屏，等待用户给本地候选反馈。

### 2026-10-24 20:20 先发布卡顿修复、保留连续圆角（Codex）

- 按用户最新要求先发布官网第27版，部署已`succeeded`；保留第26版缓存Canvas外阴影性能修复、原连续曲线、材质、颗粒和色场。另补按钮仅更新label及失联paint重建，防止文字更新删除绘制层；没有把普通圆角作为正式降级。
- 源码`17545268acb9e6d1387f500373b131a5158d0149`，部署`appgdep_6adca27276f08191a35c2446adb2b7f6`；唯一发布源不变，回执`target/showcase-publication-20261024/safari-performance2-receipt.json`。相对26版仅两JS与两HTML缓存引用改变；JS语法、差异检查通过，实际Safari英文浅色加载／阶段按钮可见。沿用已完成的性能验收，不冒称新的120Hz、手机或Windows Edge验收。
- 普通圆角临时对照已在Safari加载，用户反馈仍未解决；overlay普通混合候选尚未完成动态验收即按发布优先级停止，不能报告有效或无效。所有临时开关／trace已从运行源码清除，归档在`showcase/review/field-performance-20261024/continuous-corners-diagnostics-before-release.js`，未上线；Safari已切回正式中文页面。
- 浅色阶段按钮“滚动变暗、停下变亮”仍未解决，当前没有已确认引擎根因；后续继续先核对来源与匹配条件，再做单变量验证。没有新后台测试或常驻进程，8767／8768服务保留。

### 2026-10-24 Safari 滚动明暗故障仍未解决（Codex）

- 用户录屏及本机复现确认：浅色外观的阶段按钮，在文字从居中移向左侧时持续滚动变暗、停下变亮；Chrome正常。19:38的测量循环修复不能证明这一动态故障已解决，前条“闪烁修复”仅指当时确认的静止测量循环。
- 正层级候选在实际移动录屏中无效，已撤回；停止沿层级继续试改。已查官方与社区历史，尚无完整匹配报告；条件差异及现有证据见既有`showcase/review/field-performance-20261024/investigation.md`。
- 当时官网为第26版，按钮文字更新保留绘制节点的确定性修复未发布；现已随上条第27版上线。持续滚动明暗变化仍单独待验，诊断代码未发布，不能相互代替验收。
- 已补强并实际重读唯一全局`~/.codex/AGENTS.md`的故障排查前置条件；没有通知或声称其他agent已重载。后续修改先交代来源、匹配与不匹配条件及唯一主要变量，按用户这段实际滚动过程验收。

### 2026-10-24 19:38 Safari 外阴影性能与顶部条闪烁修复上线（Codex）

- 原调色板在真实Safari27.2正常；主站正常PNG路径1.5 rAF／0.7 published fps，单独停用连续角SVG外阴影59.8／30.0。将外阴影改为同一Path2D的缓存Canvas、扣除全部内部，保留SVG描边／clip和原玻璃／色场后58.4／28.5，后续浅色静止样本60.0／30.0。未采用命名canvas／噪声候选；发布`brand-field.js`与第25版逐字节相同。
- 静止bar闪烁已定位到测量恢复宿主时启动box-shadow过渡：36次nav测量对应34次阴影结束事件、无外部属性触发，结束又调度祖先nav。测量期间只抑制绘制过渡并先提交透明宿主，保留height／width／transform原timing；修复后静止仅2次初始化、0次阴影事件，导航缩小与legend开合已实操。标题格状阴影改同sigma drop-shadow，限定对应能力；支持原生corner-shape者不进入圆角兼容脚本。
- 实验和证据在`showcase/review/field-performance-20261024/`；Safari浅深首屏、滚动导航／浮动符号条、文字中部点击“完整手册”进入296项手册已检查，Chrome浅深实际画面正常，IAB390px原生／强制兼容路径无横溢出。四类外阴影内部alpha为0及缓存／离屏恢复离线检查通过。物理iPhone与Windows Edge本轮未复测，不由桌面Safari／IAB结果代替。
- 原官网第26版已`succeeded`，源码`60068c33137ba2275191bdfb31edfe3d54e5c692`，部署`appgdep_6adc98a764c481919b05c1b63beae9ce`；public受众、25版完整手册入口、精简发布资产与既有英文修复保留。唯一源仍`target/showcase-publication-20261024/source-responsive`，回执同级`safari-publication-receipt.json`。仅3个运行资源与两HTML对应cache更新；DESIGN已同步，无全局规则／Rust／Windows安装器改动，8767／8768未重启。

### 2026-10-24 发布页本地交互增量（Codex）

- `showcase` 独立本地 `main`，未提交／未发布，沿用8767服务。详细现行设计为 `showcase/DESIGN.md`；所有未来网页的连续曲率与Safari兼容固定策略已写入唯一全局 `~/.codex/AGENTS.md`，不声称其他agent已重载。当前依赖cache版本`20261024-scroll50`，大量原有未跟踪素材保留。
- 八组只有一份文字构件，前组退出至少1/3才揭示、稳定gap96px；整体24px/700ms与内部8px/55ms错峰。中心固定后与前组脱钩，前组文字图片均完全退出且介绍完整后，下一新下滑才飞图；宽850→350、高度缓存插值保持Y中心。最新按介绍态实际Range最长行触边切侧对齐（替代e=.5，待本轮浏览器增量确认）。阶段底材与选中色块跟随图片同一透明度e，未到位disabled/inert、纯文字；实测e0与e0.403271图/色块一致，progress>=.999才可点。原滚动阶段24vh与空闲2000ms内帧播放保留，无滚轮截获。
- 删除连续视频、范围控件、重复导航；字体固定自托管Inter/FiraCode/Noto。导航58→40全部同比缩小。legend同一div+button原位/浮层淡出140ms再淡入200ms，浮层导航下10px、同宽40高；圆球40×40，左端圆润三角，展开为描边闪电。宽/maxWidth/--legend-morph360ms同一动画，修正closed max-width使收起瞬跳的问题。SVG原生曲线fallback也按同一morph进度绘制；最终Safari形变仍需定向确认。
- `continuous-corners.css/js/fallback.css`统一同源轮廓：原生支持采用校准superellipse1.44×radius1.283，不支持使用SwiftUI每角3cubic路径；不再普通圆弧作为Safari目标。清除inset rims、重复底材与边线；外阴影明确排除SourceAlpha内部。Safari实际新画面已见连续长条、正常文字与矢量图标，但新阶段字段填充曾缺失（深字无底），**仍待兼容层定位，不能称Safari全量通过**。新增仅QA查询`geometry=vector`方便在IAB定向检查，同样不证明Safari像素通过。
- cmatrix卡片改为GoStream原C状态逻辑web移植，GPL3许可随资源，GlowMono字形125字符覆盖；M/W/L替换Apple/Windows SVG与有来源的Tux。仍待最终卡片/平台/手册整合画面确认。dark真实补录按用户要求稍后继续，PDF双向定位真实素材缺口保留。
- 独立色场预览（冻结前记录）`dist/color-field.html` 使用固定 `@kawarp/core1.3.1` MIT 的真实WebGL域扭曲＋128²缓存Kawase模糊；当时以首页4色＋Logo6色为默认，每色一个移动空间源，显示饱和1.12、warp .45，静态细粒磨砂。速度0.25–6倍（当时默认1.5，基础轨道.09 rad/s、warp时钟×2），模糊2–12（默认8）；30fps、输出长边≤960，hidden/reduce静止。当时为用户调试中的候选，未接主站，不宣称Apple私有原生算法；当前确认值见下方冻结增量。
- 调色面板支持新增颜色、参与开关、取色器/HEX、收起；颜色、开关、速度、模糊、暂停与收起状态用同一key自动保存。IAB独立localhost来源已实际验证修改、刷新恢复、新增项自动滚入可见区与总数更新；测试数据不覆盖用户127.0.0.1来源。主站Glow负字距裁切已补足着色空间，IAB实际截图`showcase/review/2026-10-24-scroll/hero-glow-ink.png`；此增量未做Safari实机验收。
- 色场预览cache为`20261024-field9`：六点手柄支持跨行拖动排序，颜色/参与状态绑定并保存。IAB实际将禁用第1色拖至第7后编辑，刷新仍保留顺序、色值、开关与其他参数；无运行错误。用户页面已更新，13色与速度4/模糊9保留，截图`showcase/review/2026-10-24-scroll/color-field-reorder.png`；未声称Safari或触摸真机验收。
- 2026-10-24，Codex：按用户“先固定这套”冻结当前14色顺序与参与状态，仅第3色 `#ffc6c2` 暂停、其余13色启用；速度2.5／模糊8／暂停false／面板收起true。共享默认入口 `showcase/dist/assets/field-preset.js`，预览cache `20261024-field10`，完整色值与来源边界见 `showcase/DESIGN.md` 4.1；Kawarp1.3.1、饱和1.12、warp .45、轨道.09、warp时钟×2及静止噪声保持。按后续要求加入颗粒强度0–0.5（步长.01，当时默认.2）、大小0.5–2倍（步长.05，当时默认1）滑块，实时调节透明度／背景尺寸并保存到同一设置。IAB已验证颗粒透明度／尺寸实时生效、强度0关闭、刷新保留及恢复14色默认；用户预览仍正常播放（time32.69→53.54）。暂停测试页已关闭，截图`showcase/review/2026-10-24-scroll/color-field-grain.png`。当时主站蒙版尚未集成，未新增Safari验收或发布。
- 2026-10-24，Codex：主站本地接入 `field-renderer.js`／`field-preset.js`，每页单个WebGL renderer与时钟，最多30fps渲染、24fps发布解码后的共享帧；14色顺序／第3色禁用、速度2.5／模糊8保持，当时颗粒为.45／1.15。层级按用户最新要求固定为共享动态色场→高不透明黑白玻璃→原有首屏斜光束；光束自身效果保留，底部完整材质含暗角整体alpha渐变到透明以消除硬分界。主题色控件／文字按mask同坐标取底层帧形成视觉挖孔，不称物理DOM减法。可见消费者以CSSOM更新坐标与缩放补偿，避免transform祖先下fixed背景错位，不为每控件另设动画；连续角底材继承同一帧和颗粒。IAB已见主站深／浅色场，暂停后frame748／time140.23保持、恢复后继续流动；快捷键浮窗左三角朝右／右侧空心闪电已由截图确认。Safari工具无可用窗口，本轮未做真实Safari验收；IAB强制vector路径的阶段选中底材已见动态纹理，手册37处搜索匹配与平台选中态也接入同一帧；透明度6.5%→9%的同源同步及刷新保留已确认，未发布，不外推手机真机。
- 2026-10-24，Codex：原调色面板加入玻璃透明度0–100%（步长.5%，当时默认3.5%，越大越透明），独立key `glow-field-glass-v1` 即时保存并同源同步主站；当时两主题veil alpha均.965。预览默认盖玻璃，两个按钮样例直接裁同一WebGL帧并对齐颗粒，深浅切换仅作用当前预览页；`field12`预览／`glass1`共享设置。IAB已确认按钮内色场持续更新、玻璃透明度同源同步与刷新保留、深浅玻璃切换。玻璃表面新增独立静止磨砂纹理（当时默认.115／1倍，normal混合）与24px柔化；当时颗粒控制尚待后续完成。截图`showcase/review/2026-10-24-scroll/glass-frost-preview.png`；仅本地，未发布。

- 2026-10-24，Codex：最新确认默认集中于FIELD_PRESET：色场颗粒.45／1，玻璃透明度20%（veil .8）、颗粒.09／1；玻璃独立保存 `{transparency,grain,grainSize}`，控制与持久化已在前一步IAB检查。主站去除旧vignette不透明尾部，改用256×2048静态五次曲线羽化mask（54%–96%、确定性随机alpha量化），无新增动画循环；Glow字形以同场7／18px模糊恢复发光。Linux按已有SVG alpha取共享色场剪影，功能／章节大标题加入同场；最后功能组至CMATRIX按缓存尾部恢复96px间距，阶段与停驻门槛保持；修复英文四处拆分标题及requirements链接前空格。IAB已见全部8组与章节标题、三平台剪影、同色场Glow发光，英文两处截图中的空格已确认；CMATRIX与最后画面边界实测约96px，未改阶段停驻。Safari未验、未发布；30fps／长边960／128²色源15Hz／PNG桥24Hz仅为代码上限，另有全屏blur成本，没有GPU占用率实测。

- 2026-10-24，Codex：用户确认无遮罩对照：停用Hero额外颗粒与暗角／整体mask，光带overflow可见，IAB首屏底边硬接缝已消失；原beam-fade-mask资产保留但不加载。玻璃颗粒改sRGB中性overlay，并新增独立亮度0–100%默认50%（同源screen颗粒提升），实时保存且不改强度／大小／透明度；IAB亮度50→70→50已验证，后续用户自调透明度12.5%／强度.1／大小1，服务保留现值。
- 2026-10-24，Codex：跨浏览器玻璃本地同步已加入glass-settings与tools/glass-preview-server.py；实际自有服务PID51617（exec session84115）监听127.0.0.1:8768，启动命令 `python3 tools/glass-preview-server.py`，保存review/glass-preview-settings.json；原8767服务未重启。隔离API/SSE/迁移/旧客户端与JS模拟通过；IAB同步到主站及外部Chrome新预览实际读到12.5%/.1/1/.5已确认，Safari未验。静态部署不连接此本地服务。
- 2026-10-24，Codex：用户认可Glow浅色也用原色，去掉字形深色veil，修正伪元素继承已解析veil导致黑雾；标语整行轻投影2px/3px，深色.22浅色.14。功能组h3恢复主题正文色，01/08序号功能名行改共享色场；章节h2维持色场。当前brand CSS shared18、JS shared7、glass5；仅本地，未发布。

### 2026-10-24 19:02 主页完整手册文字入口上线（Codex）

- 原对话按用户澄清仅修改`showcase/dist/index.html`的“打开完整手册”入口：整段原生a链接、明确下划线、44px点击高度及普通正文色，保留语言同步。六处文字命中检查与实际文字中部坐标点击通过，官网已实际跳到手册；未改Safari专项候选或其GUI。
- 第25版已succeeded，源码`5788ddbb27fa6f2a73308b77cbd96f3d930826e8`，部署`appgdep_6adc904acc7c81919d974d00a97a03f0`。唯一发布源仅index有4行增量，后续Safari发布须保留；本地index也已同步。证据`showcase/review/manual-link-20261024/`，根因调查仍由新对话接管。

### 2026-10-24 Safari 专项新对话交接（Codex）

- 用户明确要求另开新对话处理：Chrome正常，iPhone／桌面Safari仍卡，另报告“Neovide Glow”大字阴影有格状纹理；**根因未证实、未解决**。官网仍是下述第24版，修好的字体／四标题／双栏对齐均已发布。原会话停止编辑，原生子代理全部完成；8767、8768及既有本地服务保留，不重启他人进程。
- 本地未发布试验只在`showcase/dist/assets/brand-field.js`及两个HTML的brand cache（`safari-profile4`），当前候选把Kawarp直接画到命名CSS WebGL canvas，原生Safari能力与画面尚未验；不支持则PNG回退。先前命名2D canvas的drawImage实测约679ms，已弃用，勿发布该分支；9项新控制流检查仅在内存VM通过，旧`css-canvas-check.*`是废弃2D候选。
- Safari27.2实际窗口现可用。诊断URL `http://127.0.0.1:8767/?lang=zh&field-debug=1#top`；`field-transport=png`可强制旧桥，`field-test=render/encode/no-glass`可隔离阶段。面板会报告visibility，后台hidden=0fps不得作为性能结论；用CUA切到Safari前台后曾见rAF约4／发布约2fps、PNG20–34ms＋decode4–8ms，2D桥2.3fps。`field-test=render`旧页也曾见4fps，须控好前台/缓存再判断，不能锁定PNG为唯一原因。
- 原生AX／截图在`showcase/review/field-performance-20261024/safari-native-*`；当前Safari停在`v=safari-render&field-debug=1&field-test=render`，可能仍加载旧2D试验，需明确刷新至新候选。CUA初次按规范重载文档；原生Safari可用`cua.getApp('com.apple.Safari')`，需要前台时已验证`super+Tab`可使面板visible，勿靠IAB替代Safari。下一步先核实直连命名WebGL实际支持／同步重绘与帧率；无效即停候选，定向查GPU绘制、全屏blur/grain和标题阴影格纹。用户还反复指出“打开完整手册”六字链接区域，官网AX实点已跳转并载入296项，但尚未做原生Safari文字区域坐标实点。

### 2026-10-24 18:47 Safari 路径窄修与网页样式上线（Codex）

- 官网第24版已succeeded：源码`0b2c537061d0124979697381423e28aa6f28bed6`、部署`appgdep_6adc8ca98e388191ab105e2981567f35`，仍沿用唯一发布源`target/showcase-publication-20261024/source-responsive`与public受众。第23版先发布性能／字体／标题，第24版加入Windows导航与浮动说明条的滚动条宽度定位修复，17／18px及手机布局模拟通过，未冒称Windows真机通过。
- 共享帧改局部inline变量，四个纯绘制变量不触发连续角重建（13项过滤回归）；CPU/GPU渲染前背压保留最新静态修改（生命周期检查通过）；主站色场长边640，独立预览仍960。普通蒙版、原生圆角、颗粒与配色保留。WebKit源码表明原每帧CSSOM写入可能触发全树样式重算，但没有建立与本机二进制的逐版对应。用户仍报告Safari卡、Chrome正常，**性能问题未解决**。
- 现有字体含“变更”，只修`--mono`的无衬线及Windows微软雅黑回退；四个章节大标题恢复深色白／浅色深字，中英实际IAB样式检查通过。完整手册入口已实际点击官网并载入296项；用户仍指出文字点击区域，待Safari实点核查，不假定用户误操作。
- 当前新一步只在本地加入`field-debug=1`的阶段诊断，未发布；实际Safari窗口现已可访问，用户同意直接在Safari检查。IAB前后帧率不稳定，不能写成Safari性能改善。证据集中`showcase/review/field-performance-20261024/`，DESIGN已同步现行640／inline／四标题规则。

### 2026-10-24 18:29 九模块响应式小图版上线与手机性能调查（Codex）

- 按用户明确授权发布至原官网，保留public受众。第22版部署 `appgdep_6adc87b8b044819181bc4dc446ba2ab9` 已 `succeeded`；源码 `340fda7fd36b0fdddffd1e8db539e22899427c25`，唯一发布源在 `target/showcase-publication-20261024/source-responsive`，回执在同级 `publication-receipt.json`。九模块、既有Windows2026.10.23.5双架构下载／指南／校验与中英内容均保留。首个过大源包被HTTP413拒绝、第二个较大传输按新压缩要求停止；均未部署，最终只发布约48.6MB运行文件，未带本地原图、review或内部清单。
- 用户最新要求覆盖此前网页原尺寸无损规则：224张原3024×1840桌面图生成768／1280／1700三档WebP Q90，672个派生图全部尺寸／解码检查，原SHA不变。原桌面图合计356.7MB，1700档18.0MB、三档合计36.0MB；原图留本地。来源和参数在 `showcase/content/native-responsive-assets.json`，四份原manifest及逐像素核验逻辑保持；准备工具生成响应式字段，缺匹配派生图会报错。文字压缩对照及证据在 `showcase/review/responsive-assets-20261024/`。
- `workflow-lab.js` 移除全九组首帧eager与整阶段预载，临近视口才挂src/srcset，逐字阶段最多当前＋后2帧；大图链接1700档，去掉未使用的窗口mask。定向加载检查通过；IAB窄屏实际初始仅1组请求，PDF双向定位第三阶段在英文浅色切换后保留，使用1280图／1700大图且无控制台错误。官网浏览器已见九组、响应式链接与完整双架构下载；后续截图通道失去标签会话，CLI直取返回403，未据此重复改站或冒称iPhone通过。
- 色场CPU按行筛除零贡献源与指数递推，Node中位1.493→0.642ms；1,409,024像素零差。共享帧只向背景与可见样本局部发布，根变量只初始化一次；静止不读几何，滚动／长动画继续对齐。12项合成控制流检查与实际窄屏滚动／主题／语言检查通过，缓存 `20261024-mobile2`；用户仍报告iPhone卡顿，不能将上述桌面结果当手机通过。全部性能证据集中 `showcase/review/field-performance-20261024/`。
- 只读色场调查完成，优先候选为480／640长边输出与渲染前背压，其次验证去PNG桥；GPU源shader暂缓，现有128² CPU并非已证实手机瓶颈。官方资料与边界见该目录 `investigation.md`。候选尚未实施／上线；等待用户对官网小图版的实际手机反馈，不宣称卡顿已解决。DESIGN已同步原图保留／网页派生与可见区发布规则，未改已安装程序或用户配色。

### 2026-10-24 17:57 色场帧率节拍修复（Codex）

- 用户反馈 iPhone Safari 正常模式色场流动帧率低。确认代码有两级独立限频：30fps渲染后再以24fps门槛发布，理想输入也会被减半至15fps；渲染端 `last=now` 另会丢失rAF时间余量。`field-renderer.js` 改为累计deadline与0.5ms容差，长延迟跳过过期工作；`brand-field.js` 移除第二层时间门槛，仅保留PNG编码／解码单项背压。
- 同一IAB 516×778窗口、516×778画布，DOM实际已发布帧计数测得修复前27.157秒355帧（13.07fps），修复后32.214秒951帧（29.52fps）；该数据属于桌面浏览器窄屏，不能替代iPhone真机性能。减少动态后39.823秒保持同一帧，恢复后继续更新，无控制台错误。颜色、速度、模糊、纹理大小、分辨率与共享蒙版／玻璃材质均保持。
- 实际源码VM快检覆盖60／120／30Hz及微小抖动、暂停恢复、10秒卡顿、palette／speed输入与dispose，通过；只证明调度与控制流，不模拟GPU或PNG耗时。证据与截图集中在 `showcase/review/field-performance-20261024/`。主页、手册及色场预览缓存更新为 `20261024-cadence1`，DESIGN同步单节拍约定；仅本地、未提交／发布，iPhone观感待用户复看。

### 2026-10-24 17:42 恢复本地发布页预览（Codex）

- 用户报告主页无法加载；实际8767无监听、连接被拒绝，原服务已停止，停止原因未确认。按既有静态入口恢复仅监听127.0.0.1的独立预览进程PID86921，根目录仍为 `showcase/dist`；8768同步服务PID51617未重启。
- 主页、新脚本、Dark素材目录与PDF桌面图片均返回HTTP200；启动与健康检查在 `showcase/review/local-preview-20261024/`。未改网页内容、提交或发布；用户原错误页需刷新。

### 2026-10-24 17:31 主页新增独立双向定位模块（Codex）

- 按用户明确要求将主页扩为九组：原第4组 `feature-pdf` 保留 PDF 对照／翻页，新增第5组 `feature-pdf-sync` 展示“同窗预览→源码定位 PDF→PDF 返回源码”，后续AI、终端、补全与Git顺延。四份manifest恢复原PDF预览对象，真实双向定位补录独立保存为 `pdf-sync`，不复制／改写图片或来源。
- 新增独立场景与中英文内容，四份素材目录、阶段与主页缓存统一 `20261024-nine1`；`DESIGN.md` 同步九组架构及已闭合素材缺口。四套目录检查、阶段索引／独立素材引用及JS语法通过。
- IAB 1280×720实际确认九组编号01/09–09/09、新模块05/09及三阶段，中英×浅深四组合素材正确、切换保留第三阶段，无横溢出或控制台错误。截图／记录在 `showcase/review/pdf-git-retake-20261024/qa/home-nine-features-{zh.png,qa.json}`。仅本地，未提交／发布，8767／8768服务保留。

### 2026-10-24 17:23 发布页 PDF 双向定位与 Light Git 补录（Codex）

- 仅本地 `showcase`，未提交／发布。中英×浅深四组合的 PDF 各补三帧：同窗预览→源码定位 PDF→PDF 返回源码；保留 Neo-tree、TeX 与原生 PDF 同窗。正向实际执行 `GlowTexForward` 并采到定位高亮；反向使用真实 ⌘＋鼠标左键单击 PDF，原生 SyncTeX 序号增至1、自然返回中文45行／英文44行，未用手工移动光标替代。Light Git 中英各三帧重录，末帧实际选择 `basics/format-after.py` 并显示彩色差异。
- 共18个状态、36张窗口／桌面 lossless WebP，桌面3024×1840、窗口2698×1536；新素材位于四目录的 `retake-20261024/`。原PNG、旧资产与四份清单备份保留在 `showcase/review/pdf-git-retake-20261024/`；四份manifest仅替换目标故事，其他故事逐项保持，来源SHA与原图核对通过。语义验收、矩阵核对及导入回执集中在该目录。
- 现有 PDF 模块更新为三阶段，无新增首页模块；中英文案及键帽与真实操作一致，四份catalogue与阶段cache为 `20261024-pdfsync1`。`workflow-lab.js` cache `20261024-stagekeep1` 修复语言重排导致阶段回退：切换期间保持当前已入场组的阶段／内部帧，重排后校准局部阶段位置，普通滚动继续推进，未入场组不提前解锁。
- 四份素材准备工具 `--check`、JS语法及差异空白检查通过。IAB 1280×720实际验证 PDF 第三阶段中英／浅深切换保持、向上滚动可返回前阶段、八组数量不变、无横溢出及控制台错误；画面与记录在 `qa/pdf-bidirectional-page.png`、`qa/browser-retake-qa.json`。本条闭合16:54所记 PDF 双向定位与旧Light Git末帧缺口，未新增Safari、手机真机或Windows／Linux验收。
- 原系统Light、原Space ID 4、前台应用与桌面图标／小组件设置已恢复；自有采集进程与临时App副本已清理，见 `restore-receipt.json`。原8767／8768服务保留，已安装程序与用户窗口未替换／关闭。

### 2026-10-24 16:54 发布页 Dark 原生素材补齐（Codex）

- 仅本地 `showcase`，未提交／发布。中英各新录七组51帧真实Dark；首组复用原有真实Light→Dark两端并保留原始来源／历史采集身份，各形成8组53帧、合计212张窗口／桌面WebP。两份 `content/native-state-manifest{,-en}-dark.json`、`dist/assets/states{,-en}-dark/` 与Dark catalogue已生成；新原PNG及分组清单在 `showcase/review/dark-capture-20261024/`，旧Light资产、原PNG和配色均保留。
- Desktop 3实际采集，窗口2698×1536、桌面3024×1840，上下各152px。编码逐帧核对直接PNG与lossless WebP的RGBA；两准备工具的 `--theme dark --center-desktop --check` 共106帧桌面原图／裁切核对通过。Notebook只读既有输出、AI只展示已有完整中英答复。采集工具补独立分组／逐组落盘；修正临时LazyGit中文码为 `zh-CN`、将选择键送入真实终端job，最终Dark两端03均选中 `format-after.py`。失败采集保留在review，未导入页面；中文五组清单从已完成编码的原图恢复，记录了恢复说明。
- `workflow-lab.js`／`index.html` 接入语言×主题四份目录及主题事件，cache `20261024-dark1`；保留原scroll56布局与阶段、当前内部帧及旧解码回调失效保护。IAB 1280×720实际检查中英×浅深四组合、快速连续主题／语言切换，文件搜索仍在输入名称／10帧，最终仅一张正确中文Dark显示层，无横溢出或控制台错误。截图与验收在 `showcase/review/dark-capture-20261024/qa/`；JS语法、差异空白检查通过。
- 已恢复原系统Light、Space ID 1、前台应用、桌面图标／小组件设置及采集实例运行语言；自有采集进程与临时App副本已清理，回执 `showcase/review/dark-capture-20261024/restore-receipt.json`。原8767／8768服务继续运行，已安装程序与用户窗口未替换／关闭。
- 边界：PDF仍为真实预览／翻页，未补双向定位；旧Light Git 03仍停总览，本轮未改其原资产，不能将其算作真实文件选择。未新增Safari、手机真机或Windows／Linux验收；本轮没有连续视频或网站样式重做。

### 2026-10-24 16:36 发布页定稿增量与 Dark 素材交接（Codex）

- 仍仅本地 `showcase` main，未提交／发布。按当前预览冻结 FIELD_PRESET `glow-20261024-1616`：14色（第3色暂停），`#70ffd4` 替代旧 `#7affcc`，速度2.5、模糊8、色场颗粒.45/1；玻璃透明度12.5%、颗粒.09/1、亮度.6。共享默认及详情在DESIGN.md，用户仍可继续微调；8768同步服务PID51617/session84115继续供页面使用，不重启8767。
- CMATRIX移除滚动空闲门槛，实际连续滚动时字雨仍更新；Linux改Simple Icons CC0复合路径，眼／嘴／腹部／脚部内部细节保留并透出同一色场。截图在 `showcase/review/2026-10-24-scroll/{cmatrix-while-scrolling,linux-field-details}.png`；旧只含外轮廓的方案已替代。
- `workflow-lab` cache scroll56：窄屏先居中文字、再由完整上图飞入把文字推向下方；长条说明自然换行并随内容增高。触边后真实文本行同时380ms平移，反向中断接续，结束清理包装及位移，终点完全交给原DOM自然侧对齐。IAB实际验证850×778入场中段无图文重叠、宽屏跨阈值倒滚与终点（临时行9→0、最终350px栏／侧对齐）；截图 `text-alignment-final.png`、`narrow-image-entering.png`。JS语法／差异检查通过；本轮未做真实Safari增量验收。
- 中英共168张引用桌面素材仅裁顶部28px，3024×1868→3024×1840，上下各152px；原始PNG保留，manifest记录来源与裁切。逐像素lossless比较、两份catalogue检查及幂等复跑通过，浏览器实际加载新尺寸。新的Dark采集框为 `0,62,1512,920pt`，窗口仍 `81,138,1349,768pt`，窗口图2698×1536。
- 已回顾原聊天“丰富发布页功能展示与快捷键手册”`01a167c6-bb75-7543-8695-46d79c0dbe2f`：用户已明确允许原生AppleScript控制Desktop 3布景／居中／采集；系统级Light/Dark切换，保护现有窗口与Ayu配色。下一聊天只补录中英Dark八组相同阶段，独占GUI、核对新实例，不复用历史PID/window/socket。当前已有theme两端，其他七组尚无Dark；PDF双向定位不冒称已有，AI只展示已有答复、Notebook不启动内核。原PNG在 `~/Desktop/scr_recs/take-20261024/retake-clean/{zh,en}`；工具和计划在showcase/tools，前端尚只有中英Light两catalogue。

- Dark素材任务已新建为“补录 Dark Mode 原生展示素材”，本地线程 `01a16d0e-56ce-78f0-a5ad-6e915706a74e`；当前聊天已释放GUI及素材文件，临时测试tab和 `_layout-review.html` 已清理。新线程接续上述范围与服务保护。

### 2026-10-24 12:42 发布页新对话交接（Codex）

- 用户要求将变慢的对话交接到全新对话；只接续 `showcase/` 发布页，独立 Git `main`，现有大量未跟踪素材均须保留，不提交或发布。旧对话停止编辑，全部子代理已完成。已有本地预览 `http://127.0.0.1:8767/` 根为 `showcase/dist`，保持服务；设计依据 `showcase/DESIGN.md` 第10节，以下增量覆盖其旧验收描述。
- 最新优先修正：图左文右时，文字、阶段按钮、键帽及来源整体右对齐；图右文左时左对齐，不能全部居中。当前 `workflow-lab.css` 末尾全局居中规则尚未按这条修正。相邻内容现在又太近，当前 `margin-top:min(-22svh,calc(450px - 80svh))` 需适度放宽并实测，不回到整屏黑色空档。
- 已写但尚未浏览器验收：`dist/assets/workflow-lab.js` 恢复所有8组随滚动切换阶段，入场50.6vh、每阶段24vh，按阶段数增加sticky距离；按钮滚至同一阶段区间，阶段内输入帧仍连续播放，取消定时跨阶段轮播；修复倒滚时旧解码覆盖新目标、语言/范围切换保留当前帧。JS语法及diff空白检查已过，需实际检验首组浅→深、终端各阶段、倒滚/按钮和间距。
- `dist/index.html` 已删除泛标题“思路不必跟着窗口切换”，保留视图工具条及单次浮现，移除主视觉退出淡隐；工具条新增“演示视图设置”英文ARIA仍需同步。功能序号已显示明确功能名；各组文字浮现与媒体侧飞、透视转正保留，原曲线 E(t)=1−(1−t)^3，禁止缩放和向上退出淡隐。首页六项常用快捷键、完整296项独立handbook、中英/桌面/窗口/关键帧/连续视频保持。
- 以前已验1280/1600宽、390窄屏、浅深主题、视频和减少动态，但本轮增量未验，不沿用旧截图作新通过凭据。资源/阶段事实见 `showcase/content/native-story-phases.json` 与各native-state/video-manifest；PDF仍为旧预览/翻页素材，双向搜索补采集因Desktop3不可达未完成，不虚称已展示。原片在 `~/Desktop/scr_recs/`，按现有recording-profile与DESIGN采集约束，仅Desktop3、不改变用户窗口大小。完成当前布局/滚动修复并给一张新实际预览截图；不重做无关历史工作。

> 2026-10-23，Codex 整合更新。仅本节表示当前状态；下方历史记录保留当时结论。状态依据实际回执，不将源码／协议检查写成实际界面验收。周额度重置后先修复 Fzf 与 TeX 双向搜索；随后按用户“开始做”的新授权补齐 Windows ARM64 插件与 Notebook 依赖。2026-10-21 停止／归档记录仍作历史保留，Linux 原生开发继续暂缓。

- Mac 磁盘 App 当前核对为 `nightly-211+g430c5e3-dirty`，与本轮 generic 候选 App 的 SHA 相同；用户已确认本轮约16:06手动安装，agent未执行安装命令，CLI 仍为旧版。此前菜单及 PDF 界面验收保留历史结论，本轮标题居中仍待用户重开后的 GUI 验收。Windows 配置迁移已完成，Mac80%／Windows60%默认缩放、用户主题与未保存内容保留。
- Windows Telescope、顶部空白拖窗、小窗／边缘缩放及透明圆角修复已分别交付；实时缩放 `1dbe658` 的基础上新增 dashboard 标题上方空白拖窗 `73dcbd1`，已纳入两架构前端。ARM64 动画、缩放／语言继承及桌面无控制台入口已补齐；此前按用户要求跳过 dashboard 多高度 Windows GUI，未将其记作通过，后续 Snap 待验见下节。
- Windows 内嵌 PDF 双向搜索现已实现，功能源码 `fdeece58` 由最新两架构 Snap 修复版继承，三份查看路由配置已部署；此前 ARM64 实际 WebView2 的定位／回源和草稿保护通过，x64 实际加载／关闭通过，实体鼠标尚未验。Sumatra 保留为显式可选回退，详见下节。
- Windows ARM64 原生插件、Notebook 私有环境与 24 项 Mason 工具已补齐并部署；Java 已补到 Mac、Windows ARM64／x64，当前统一清单及两份 Windows 实际 profile 均为57个语法解析库。普通 ARM64 配置实际启动检查通过；部分进程外工具保留 x64 兼容，GUI 图片显示及在线 AI 对话未验。详见下节。
- 10月23日现场反馈的 Snap／最大化重绘已修复并编译、部署 x64／ARM64，等待用户手动验收；Windows 面板材质独立设置，后续用户已改为30并保留，Mac原参数不变，Neo-tree已换方正 Windows 图标。当前 `tool.tex` 已补齐字体发现与宏包并重编，实际 Windows 正逆 SyncTeX CLI 通过，详见下节。
- 既有冻结版 `glow-stack-20261020-gm1` 与 Mac 预览 [`glow-macos-20261021-preview1`](https://github.com/Ysrae1/neovide/releases/tag/glow-macos-20261021-preview1) 保留；官网第21版已接通 x64／ARM64 同版 `2026.10.23.5` 首装／PDF图层修复预览包，两架构各14项安装验收通过。PD ARM64＋OpenGL 的实际示例 Notebook 输出及 PDF 协议检查通过，实体 D3D／PDF 像素效果仍待验证；发布与验收边界见下一节。旧 Candidate5／Core94 不作为新包通过凭据。

### 2026-10-25 Windows .6 双架构推送与发布（Codex）

- 按用户后续授权，将`glow-preview`从`c174ea3`推送至`536817e`，包含既有PDF `q`关闭修复及本轮三笔安装源码提交。新预发布[`glow-windows-core-20261025-preview1`](https://github.com/Ysrae1/neovide/releases/tag/glow-windows-core-20261025-preview1)已公开，标签指向`536817e`；前端实际仍为干净`ac0fe0d`，未重编或重新封包。
- 使用此前已交付的`lzma2/ultra64`两EXE：x64为96,981,675字节，ARM64为95,237,032字节。双安装器、双精确安装源码ZIP、安装说明、来源记录和SHA清单共7项公开资产，远端大小／SHA256全部匹配；本轮无新增功能或安装验收，既有平台限制保留。
- 发布收据与公开资产位于`target/glow-windows-publication-20261025-preview1/`。两份README更新为已发布状态；旧发行、用户安装与配置保留，未修改或部署官网。

### 2026-10-25 Windows 安装源码归属核对与本地提交（Codex）

- 此前未提交的38个Windows文件与`target/glow-windows-publication-20261023-preview4/source-snapshot`逐字节相同，归属此前安装引导与双架构封包任务，复用其实际Windows回执；已分为`2bad49d`（中英文安装／依赖恢复）和`34182fe`（ARM64原生载荷与封包）两笔本地提交。
- 本轮50项隔离Python打包检查、PowerShell7.6.8的29项依赖计划／选择／镜像／进度检查及Core运行时Lua回归通过。既有PS5.1原子JSON8项与选择9场景取最终通过收据；`pretests/receipt.json`为旧失败，JSON重试通过见`receipt-json-retry.json`。
- 窄修`build-core.ps1`超时分支在抛错前有界排空并保存日志，失败时保留超时原因并说明输出未完整保存；新增`tests/windows_core_build.ps1`在本机PowerShell通过。Mac测试使用无操作taskkill替身及自然退出，未新增Windows taskkill／PS5.1实测。两份README更新已发布`.5`与本地`.6`状态，未改冻结包。
- 本轮不启动VM或GUI、不重编／重装、不推送或发布；实体x64／D3D、完整可选依赖联网安装等既有缺口保留。官网文件与共享状态中的官网记录、Mac／Windows用户配置和现有安装均保留。
- 自写文件空白检查通过；第三方`ChineseSimplified.isl`第18行尾空格按固定上游原字节保留，其SHA与验收冻结源一致，不为格式检查改写语言资源。

### 2026-10-24 Windows PDF 焦点内按 q 关闭（Codex）

- 用户反馈 LaTeX／双向定位后按 `q` 不能退出 PDF。此前 Mac 原生层已有 `close_requested`，Windows WebView2 只在原生 accelerator 处理 Esc 返回编辑器，普通字符 `q` 不由该回调报告，查看器页面也没有关闭消息；不是此前图层修复已覆盖的项目。提交 `ac0fe0d` 为查看器加入普通 `q` 请求，经版本／revision 验证后设置 Windows 关闭状态，由已有 Lua 轮询按预览所有者关闭；Esc 语义保持。修饰键、输入法组合、重复键、已处理事件及可编辑控件不触发关闭。
- Rust 桥接3项、JS协议4项、Chromium集成8组、Mac本源／portable的现有预览所有者关闭回归和格式／语法检查通过；源码证据 `target/glow-pdf-q-close-20261024/`。Windows `.5` 基线经原生 focus RPC 确认 PDF DOM 获焦后，CUA 按 q 仍见两窗且源码未录宏；旧版未记录键盘事件，故只作已获焦／未关闭观察，不追认为已证实 WebView 收到该按键。
- ARM64／x64 均已从干净 `ac0fe0d` 构建，并在 PD Windows11＋OpenGL 用各自匹配架构 Neovim 实测：真实 SyncTeX 正向定位后保持源码为 Neovim 当前窗口、直接让原生 PDF 获焦；CUA 实际 `q` 被 WebView 记录为 `isTrusted=true`，随后 PDF target 关闭，只保留源码窗口，模式正常且宏录制／执行为空。两张实时截图与事件／RPC 收据位于 `target/glow-windows-pdf-close-20261024/fixed-{arm64,x64}/`；x64只读源码 fixture `modified=false`、与磁盘逐行一致。未将该只读测试外推为可编辑草稿或实体D3D验收。
- `2026.10.23.6` 两架构本地安装器已导出到 `target/glow-windows-pdf-close-20261024/release-assets/`，沿用 `.5` 冻结安装器与配置，只换前端及版本／来源清单。ARM64为95,237,032字节，完成隔离安装及配置保留检查并清理；x64为139,709,418字节，最终 ProductVersion.Trim／导出SHA通过，按用户要求取消新安装循环。x64首次压缩因用户关闭VM中断，后续误将停机视为故障恢复；改用仅降低压缩等级的 `lzma2/fast`，在停止清理执行前已自行完成导出，内容与同一已验stage一致。最终已正常关闭VM（stopped），自有任务／进程结束，不再继续验证；未发布官网。
- x64初轮archive构建与缓存版本刷新失败证据保留，最终 `build-final/x64` 实际重建；现有build.rs对纯SHA版本回退显示0.16.2，修复commit由新bundle来源与SHA核对，不声称程序版本文字包含commit。未修改既有安装或用户主题。x64安装包SHA256：`f4ce4db394e7ee37496f5d284c08860571ccf14ab2922fb0e236629a5c6cedb4`；ARM64：`46802f909e4d16e71c69ce69883a0543ba3220634728795a648ba667a5cc4df5`。

- 2026-10-24 重新封装（Codex，按用户最新要求）：复用上述已验 ARM64／x64 stage 与干净 `ac0fe0d` 前端，使用原冻结 ISS 的 `lzma2/ultra64` 顺序封装，两份新 EXE 位于 `target/glow-windows-pdf-close-20261024/repack-ultra64-20261024-192016/release-assets/`，此前已交付资产保留。ARM64 为95,237,032字节、封装297.298秒；x64为96,981,675字节、封装322.344秒。
- 本轮只核对冻结 ISS／stage／前端来源、`ProductVersion.Trim()` 与跨系统导出大小／SHA256；均通过，未重编、重跑功能或安装验收、替换用户安装或发布。ARM64 SHA256 仍为 `46802f909e4d16e71c69ce69883a0543ba3220634728795a648ba667a5cc4df5`；新 x64 为 `30fce61e4562b87f3ef9eec48151ec9d52390d6f2eef0b08cca25426463f8d38`，同目录附 `SHA256SUMS.txt`，上级保留来源／封装／导出收据。用户调整压缩要求后已终止本轮 normal 尝试；全部自有封装进程结束，本轮启动的 PD VM 已正常关闭（stopped）。

### 2026-10-24 中文缺字定位与两架构发布版复测（Codex）

- 源示例 PDF 未损坏：与桌面原件 SHA256 相同，9 个字体子集均嵌入；Poppler 正常显示，PDF.js 6.4.299 使用随包 CMaps 时两页共535个汉字，无 CMaps 时为0。FandolSong 中文字体无 ToUnicode，需正确加载字符映射；未新增字体、依赖或修改源 PDF。
- PD 实测官网当前 `2026.10.23.5` 的 ARM64／x64 原发布前端，各自使用匹配架构 Neovim、原内嵌查看器和独立测试配置。两架构的两页中文标题、正文、表格均经实时 CUA 截图确认，9 个字体加载成功，实际 canvas 中文区域存在字形墨迹。测试显式使用 OpenGL，仅证明该环境的发布版 PDF 字形正常，不扩展为完整 D3D12／实体 GPU 验收。
- 缺字仅复现于此前图层测试的最小查看器：新 D3D11 对照两侧均 `topmost=false`，只把 `cMapUrl` 从相对地址改为绝对地址，第1页汉字0→208、标题墨迹0→1569像素；原相对地址产生两次字体 `Failed to fetch`，修正后中文实际可见。正式查看器本来使用 `new URL(..., import.meta.url).href`，本轮不修改产品或重发安装器，旧图层证据保留。
- 输入检查、发布版诊断、四张双架构双页截图及字体路径对照保存在 `target/glow-pdf-cjk-20261024/`；对照实图 `windows/probe/cmap-path-comparison.jpg`，可复用修正源码在 `windows/probe/corrected/`（绝对路径分支已实测，独立修正副本未重复构建）。本轮自有进程归零、三项专用任务注销，PD 保持起始运行状态并恢复原全屏模式；清理回执 `windows/cleanup-receipt.json`。未改用户配置或已安装程序。

### 2026-10-24 PD D3D11 PDF 图层对照（Codex）

- 按用户要求完成独立 ARM64 D3D11 探针：Parallels Display Adapter (WDDM)、硬件 feature level 11.1；沿用 `DCompositionCreateDevice2(NULL)`、STATIC 子 HWND→WebView2 与冻结示例 PDF，左右唯一图层差异为 `CreateTargetForHwnd` 的 true／false。旧设置实际复现整页压暗，false 恢复白纸；与已发布 `.5` 内 `c174ea3` 修复一致，本轮未重编或替换 Glow。
- 大窗→程序控制缩小→恢复大窗三阶段，两侧共6次 PDF ready，resize／present HRESULT 均成功；3张实时 CUA 截图各200×200空白区采样，旧侧RGB恒为(38,39,41)，修复侧(255,255,255)。源码、日志与原始截图：`target/glow-d3d11-layering-20261024/`；最终回执 `final-receipt.json`。
- 本结论限 DirectComposition 子窗口层级与程序控制 resize；不是完整 Glow D3D12、物理鼠标、实体 GPU 或性能验收。最小查看器当时有中文缺字，未计作完整 PDF 字形通过；后续已定位为测试程序字体映射路径问题，见上节。原始示例、用户配置与已安装程序均未改。
- 探针正常退出0，自有进程／WebView2后代为0，专用任务已注销，GUI确认回到原桌面；虚拟机恢复本轮开始前的挂起状态，最终状态见同目录 `vm-final-state.txt`。

### 2026-10-24 x64 合并发布与 ARM64 对齐（Codex）

- x64 `2026.10.23.5` 已先本地交付，再发布 `glow-windows-core-20261023-preview3`及官网第20版；96,974,539字节，SHA256 `7a90fa3ef78db915ab3c248b35b88d84ce40dc139b1151043a8aad1727e43be9`。本版14项实际安装检查通过，10453个profile文件及依赖选择保留，自有进程／临时安装和快捷方式已清理；DPI及3项桌面图标补验明确复用`.4`，未算入本轮14项。
- 5公开资产大小／SHA256匹配，旧资产未覆盖。官网源`b9f7501fb3d950a49b3a777f05a5eaa7dd99e9f1`，部署`succeeded`，线上x64`.5`链接已核对；showcase未改。精确安装源码84文件＋2来源元数据，非完整重建套件。回执`target/glow-windows-publication-20261023-preview4/publication-receipt.json`。
- ARM64 `.5` 已以同一 clean `c174ea3` 前端及冻结安装逻辑完成；95,250,815字节，SHA256 `3bcdf84411d7add5d07bba1aae49f6b4bfec5b04335a5188a0a9b2d3fef40d02`。14项安装检查通过，保留10,350个profile文件；84项ARM原生文件检查、实际原生启动器及14场景后端策略检查通过，17项公共PowerShell回归复用相同冻结输入证据。PD使用ARM64原生＋OpenGL、普通ARM真机默认D3D，显式环境覆盖保留；AnyCPU启动器在较早Windows版本可走托管x64回退，不称所有进程皆原生。
- 两架构已先本地交付，再联合发布 [`glow-windows-core-20261024-preview1`](https://github.com/Ysrae1/neovide/releases/tag/glow-windows-core-20261024-preview1)；x64沿用已公开的原字节，7项公开资产远端大小／SHA256全部匹配。官网第21版源`5e83af113bc04d23415f0538cedf4ee585f225c1`部署`succeeded`，在线双下载入口及截图已核对；旧发行、showcase与用户配置保留。回执`target/glow-windows-aligned-20261024/publication-receipt.json`。
- 示例冻结副本14文件输入SHA保持：实际ARM启动器在PD无显式OpenGL参数时选择`NEOVIDE_OPENGL=1`；WebView2／PDF.js两页ready、翻页、135%缩放、关闭通过。实际Molten运行Notebook两格得到42、全部30行及1051×451 PNG，内核关闭后为空；原项目未修改、未新增依赖。首次两处验收脚本问题已保留证据并定向修正，产品源码未改。回执`target/glow-windows-aligned-20261024/arm64/demo-test/final-receipt.json`；未验像素／实体输入、Windows重编SyncTeX或实体D3D视觉。
- 01:01:52自有构建／测试进程、两安装目录和临时快捷方式清理确认；用户应用及配置保留，VM未擅自挂起。录屏任务明确交还GUI后，按用户要求于01:10完成锁屏，系统`IOConsoleLocked=true`已读回；本聊天未改亮度。桌面接口快捷键／菜单未生效后，沿用用户在录屏对话中直接许可的原生脚本方式成功；回执`target/glow-windows-aligned-20261024/lock-screen-receipt.json`。本阶段结束，无自有后台构建／测试待停。
- 用户追问PD能否验证D3D：本机PD27.0.3，官方支持DirectX11.1；后续可做D3D11＋DirectComposition／WebView2子窗口的topmost前后对照，针对合成层级而非完整Glow D3D12验收。WARP可研究离屏D3D12诊断，但当前源码跳过软件适配器且交换链存在限制；本轮仅确认方案，未改源码或重测失败路径，实体GPU兼容性／性能仍需原生Windows。

### 2026-10-23 首装反馈增量：DPI、图标、PDF 与终端包（Codex）

- x64 `2026.10.23.4` 已本地交付，97.0MB（96,968,540字节），SHA256 `c1d898a5ad075e582358729a2bc1013ab3692f8ec7a6d6138d4f38e221c70ffd`。启动器／安装器嵌入7尺寸ICO，桌面／开始菜单显式图标及Setup窗图标补齐；Windows实际安装13项与桌面补验3项通过，保留10453个profile文件和依赖选择。证据 `target/glow-windows-publication-20261023-preview3/`；尚未公开发布，官网仍为第19版`.3`，计划合并后续修复再更新。
- 依赖向导在创建WinForms窗口前将UI线程设为SystemAware，并补96DPI布局基准。200%缩放实测主窗／停止确认窗192DPI、10pt字体及控件边界通过，既有10场景GUI回归通过；CUA的PD窗口显示旧桌面，未取得有效视觉截图，96／144DPI和跨屏动态适配未验。`target/glow-windows-dpi-20261023/`；不以陈旧截图作通过证据。
- 朋友物理Windows PDF整页变暗：确认D3D `CreateTargetForHwnd(hwnd,true)`与原生子HWND层级约定矛盾，旧PDF测试仅走OpenGL；窄修提交 `c174ea3` 改为false并说明裁孔关系，格式检查通过。默认物理Windows入口使用D3D，用户反馈`NEOVIDE_OPENGL`为空；x64前端已由clean `c174ea3`编译并推送，43,588,096字节，SHA256 `1a89e5096b1e909bc379f3fa8f2fb8cccd5667360f9dc5ec2e127dc31db617b0`，已进入`.5`。PD强制D3D在ResizeBuffers返回`0x887A0005`，CrossOver26.2实际D3DMetal在CreateSwapChainForComposition返回`0x80004001`且未到首帧；均不作为PDF视觉通过。未能执行用户要求的demo_project测试。证据 `target/glow-windows-pdf-layering-20261023/`与`target/glow-crossover-d3d-20261024/`。
- 朋友Notebook已由用户确认：选择`glow-python`后单元格正常输出；系统`python3`无响应不影响该私有环境。另修复Notebook成功后TeX失败漏存选择的独立源码缺口，Windows PS5.1选择保存9场景及原子JSON8场景通过，已进入`.5`，不追认其为朋友现场根因。
- Windows Terminal＋PowerShell独立部署包已交付：`target/glow-terminal-share-20261023/Glow-Terminal-Windows-x64-20261023.zip`，3,073,772字节，SHA256 `90d76092eec083d06c8b095191fd3acdeb596ef8f93728728b3649b6c2c2a4d1`；外观／按键白名单、官方固定Mojada、字体、预览／备份／回滚，12项隔离检查及隐私／ZIP检查通过。实际当前主题未导出，来源已明示，朋友x64渲染未验；未部署到本机或VM。

### 2026-10-23 Windows x64 中文引导与 TeX 镜像修复发布（Codex）

- 按用户顺序先交付本地 x64 EXE，再发布 [`glow-windows-core-20261023-preview2`](https://github.com/Ysrae1/neovide/releases/tag/glow-windows-core-20261023-preview2) 及官网第19版；5项发行资产远端大小／SHA256逐项匹配。x64 `2026.10.23.3` 为96,855,312字节，较旧版增268,275字节（0.28%）；SHA256 `077a8e1f61d927ae9a11526319a772742570a1ac9be05f116b8f968f9ff4965e`。ARM64与旧发行资产保留，不等待其重新构建。
- 包含中英文主流程、TeX自动／清华／中科大／Illinois选择、每候选15秒有界检查及一次安装固定源；不改全局TeX软件源、固定包SHA和签名策略。修复下载满格后的实际阶段进度；LaTeX不再自动安装Sumatra，显式备用查看器保留。前端仍复用冻结`b534ddf`，未重编Rust；Inno语法问题仅合并3处数组续行，复用已通过stage重跑压缩。
- Windows11 ARM64（PD）以x64兼容执行：PS5.1依赖／进度／镜像／进程及中英文GUI、启动器检查通过，清华只读元数据探测通过；实际安装11项通过，涵盖默认／中文特殊路径、完整配置、中文检测与稍后完成、卸载保留。未替换用户安装，未做完整Notebook／TinyTeX安装、物理x64／Windows10或本次前端GUI／剪贴板验收；朋友电脑的超时需更新后实际重试，少量Inno系统提示仍回退英文。
- 构建与公开源码冻结清单、验收和发布回执集中在`target/glow-windows-publication-20261023-preview2/`；`accept-final/receipt.json`和`github-assets-receipt.json`为最终证据。安装器精确源码ZIP包含83源文件且逐项匹配冻结输入，发布标签仅指已有公开基线。官网源`0d6704c73b5c7328a4bb315960469616ac9ea8f6`，部署`succeeded`，线上x64链接／96.9MB与本地深浅色下载区已检查；showcase新设计未部署。自有构建和临时预览均结束，VM原先已运行，未擅自挂起。

### 2026-10-23 Windows Core 预览公开下载（Codex）

- 按用户“保留现在线上版，先接通新安装包”发布 [`glow-windows-core-20261023-preview1`](https://github.com/Ysrae1/neovide/releases/tag/glow-windows-core-20261023-preview1)：x64 `2026.10.23.1` 与 ARM64 `2026.10.23.2` 安装器、两份精确安装器源码、安装说明、来源记录及校验清单，共7项；远端大小／SHA256逐项匹配。原发行资产、GM1草稿及showcase新版草稿保留。
- [官网](https://neovide-glow.windygrass17.chatgpt.site/#download) 第18版部署成功，来源 `b59fcfae9aba2538dd8235b190bb1ec6591c549b`，仅补Windows下载与首次安装步骤；深浅色下载区和公开页面检查通过，未做手机真机验收。独立源码位于 `target/glow-windows-publication-20261023/site`，回执为同目录上级 `publication-receipt.json`、`github-assets-receipt.json`。
- 安装／独立profile／图形引导检测与稍后继续／卸载保留数据在PD Windows11 ARM64完成：x64兼容运行10项、ARM64 11项。Windows10、物理x64、完整外部依赖安装及本次包原生编辑器GUI／剪贴板仍未验；官网新用户实际下载安装尚待用户操作。安装到同一目录可能更新应用文件，演练使用独立目录及默认配置，用户既有配置不清空。

### 2026-10-23 Windows 中英文安装引导源码（Codex）

- 按用户汉化要求，`installer.iss` 加入中英文选择及25组自定义提示，`languages/` 固定与Inno6.3.3标准消息匹配的简体中文资源和MIT许可证；应用目录内保存语言，launcher首次配置与`Setup-Wizard.ps1`沿用，`Setup-Locale.ps1`集中翻译计划、进度和恢复说明。用户配置与系统语言不改，稳定的Setup快捷方式保留。
- `core-package.py`已包含语言模块；18项本地打包检查、编码／消息参数／语言保存顺序及固定资源SHA检查通过。更新了launcher、引导和安装验收入口，覆盖英文安装、中文Unicode目录安装及中文计划／稍后完成；Windows编译、PowerShell执行及GUI验收尚未运行，不能沿用已发布包的通过结论。
- 用户已要求弹出ZHITAI，虚拟机已挂起；本轮未重新挂载／启动。接回后需携带整个`portable/windows/languages/`、新语言模块及更新入口，以新版本重新构建x64／ARM64并验收后发布。官网第18版与公开2026.10.23.1／.2仍为原英文安装器，不替换旧资产。

### 2026-10-23 Windows 首装现场反馈与依赖修正（Codex）

- 用户提供错误并通过 ToDesk 展示实际阶段日志：TinyTeX v2026.10 下载／解压完成，自更新命令后在 `verify-self-update-complete` 的180秒上限停止；该日志仅到 Illinois CTAN 源的 `start load`，保留 `timed_out=True`、`output_drain_complete=True` 和自有进程树终止结果。范围已缩到仓库加载阶段，具体连接／下载原因及替代镜像在该电脑的可达性仍待验证；没有重装、删除环境或改动朋友电脑的安装文件。
- 源码已移除 LaTeX 自动安装 SumatraPDF 的旧关联，改用 Git＋WebView2，显式 `-InstallTool pdf` 保留；TinyTeX 子阶段通过捕获父任务状态路径的回调更新向导，下载满格转为运行中，并加入中文联网更新／检查提示。时限、软件源和签名验证策略未改；`README.md` 补可选查看器及具体失败日志说明。
- 原生 Mac PowerShell 7.6.8 的依赖计划与新增 `windows_tex_progress.ps1` 通过，覆盖显式外部查看器、父 dot-source／子调用作用域、状态路径、进度清零、中文和独立运行无回调；`windows_latex_parent.ps1` 已改为内嵌查看器断言但未运行 Windows 验收。回执 `target/glow-powershell-validation-20261023/plan-test-fresh/receipt.json`、`target/tex-progress-check-20261023-1/receipt.json`。未重新构建／发布，官网公开英文包仍保持原版，朋友的 TinyTeX 超时尚未解决。

### 2026-10-23 配置结构整理与发布准备（Codex）

- 用户确定顺序：保留已保存版本基线 → 配置结构整理 → 发布流程 → 独立对话测试／优化 Windows 安装引导；发布页功能盘点、HTML 动画演示与可查询快捷键手册已在独立聊天并行制作，暂不部署线上。
- 整理前 Mac 配置／源码快照在 `target/glow-freeze-20261023/before-structure/`；Windows 已保存的164文件在该端 `C:\GlowDev\Freeze-20261023-before-structure`，逐文件与ZIP校验通过，未保存缓冲区为0。两端参数独立保留，Windows用户主题未复制回Mac／portable。
- `init.lua` 统一委托 `config.bootstrap.setup()`，原启动先后顺序不变；六项媒体注册统一进入 `config.media.setup()`。10个语言内部实现／词典归入 `config/locale/`，保留 `config.platform.locale` 公共入口、早晚两次setup、公开reload身份和Notebook Python桥接，未进行Notebook内部模块搬迁。
- Mac本源／portable各6项语言定向检查、启动时序检查通过；最终统一隔离回归32/32通过。两端共24项主题／材质／字体等参数文件与整理前SHA相同，Git空白检查通过。语言测试修正原fixture的早期leader假设，基线同样失败的复现与原始数据均保留。证据 `target/glow-config-structure-20261023/`。
- Windows已按自己本源完成17项窄迁移，保留 `NEOVIDE_GLOW_INIT` 前置钩子，只有该端原有的9个语言内部模块归档（不补Mac专用菜单模块）；ARM64／x64各6项定向通过。149旧文件原样保留，8项主题／材质参数SHA不变，未热载用户窗口。新入口在下次启动完整生效；两架构隔离检查保留缺markdown_inline及日志目录提示的边界。最终166文件配置ZIP、SHA清单与两架构前端副本位于Windows本地 `C:\GlowDev\Freeze-20261023-gm1`，收据 `target/glow-freeze-20261023/windows-final.json`；前端仍来自 `b534ddf`，不冒称新源码重编。
- Mac标准暂存流程在隔离源码 `430c5e3d` 上完成generic arm64候选，最低macOS11.0、App／DMG ad-hoc签名、只读挂载与校验通过；DMG SHA `fefcb99277f68c4b83c5a71b7873601fc9a882f8cc55a979c97dcb6b6da52d27`。构建只改脚本副本CPU选项，未运行安装或用户Sketch同步；期间安装App文件改变，实际检查排除符号／硬链接后，用户明确确认自己手动安装，来源已闭合，CLI不变。旧候选、构建与核验回执在 `target/glow-release-20261023/mac-build/`。
- 冻结标签 `glow-stack-20261023-gm1` 已推送：源码／portable `6cc4d40`，Mac配置 `a5ec5994`；Mac App实际编译源码为 `430c5e3d`。同名[发行草稿](https://github.com/Ysrae1/neovide/releases/tag/untagged-17b1845f3b1fa2763c88)已建立并完成9项资产上传（最终校验见 `target/glow-release-20261023/receipt.json`）；241项包内文件与单文件载荷逐项校验、Mac／WSL安装计划、4项字体保护检查通过，不执行联网安装。旧标签及公开发行资产保留，未公开发布未经新引导验收的Windows安装包。
- 独立聊天已启动：[Windows安装流程引导](codex://threads/01a167d4-31a6-7d20-bc27-38162a31a134)接续安装步骤、依赖检测／复用、首次使用和错误恢复，负责Windows安装器与对应测试；[发布页功能展示与快捷键手册](codex://threads/01a167c6-bb75-7543-8695-46d79c0dbe2f)负责showcase，先详尽盘点主功能，再制作HTML动画、平台可查快捷键与场景介绍，暂不部署。两个聊天不操作当前冻结标签／发行资产或用户已有主题；本主聊天完成后无自有构建／runner／挂载残留。

### 2026-10-23 Windows 树焦点主题刷新、Neo-tree 提示字色接口（Codex）

- 用户最终确认的症状为 Neo-tree 持焦点时整窗深浅双向切换均停住，点击顶部 Tab 空白后才更新。实际保留现场：Windows 应用／系统值为 Light，Neovim 内部 `background=light`、`ayu_light`、全局 Normal 为 `#F3F3F3`，正常模式且未阻塞；两次真实截图仍为 Dark。一次纯 `redraw!` 后截图立即变 Light，未发送点击、切换焦点或改配色。已确认最终画面刷新缺失，尚未细分原先是 Neovim 未 flush 还是前端未呈现；不将同类 PowerToys 通知报告当成本机原因。实际 PowerToys 为0.102.2933.0。
- 在 `appearance/base46.lua` 完成主题／材质重放和树 redraw 后，仅 Windows Neovide 主动执行一次 `redraw!`；Mac／Linux／普通终端沿用 `redrawstatus!`，无新轮询或渲染参数修改。本源／portable 各8场真实 Neo-tree／multigrid 检查通过，平台差异为本机模拟，深浅主题的 flush／grid_line、树焦点、窗口／光标／未保存内容均保留；新测试 `tests/media/windows_theme_redraw.py`。首轮测试消息区等待回车，改测试 UI 为 ext_messages 后自然完成，非产品初始化修改。Windows 单文件旧SHA／目标buffer守卫、原字节备份／非空swap原子部署，两架构原生语法检查通过；新会话自动生效，尚未把用户实际重新切换的验收记作通过。
- 按用户要求，两端统一提示字色入口为各自 `~/.config/nvim/lua/config/appearance/tree_message.lua` 的 `config.light`／`config.dark`；默认 `false` 完整继承原色，可填十六进制或主题色槽，保存后 `:lua require('config.appearance.tree_message').reload()`。作用于 `NeoTreeMessage`（隐藏项目、空目录等提示），仅改前景，保留背景／斜体／透明度；false 或重载可恢复继承。`ui.lua` 接入，README补入口；两端配置仍独立，所有主题文件未修改。
- 本源／portable 及 Windows 原生 ARM64／x64 的真实冻结 Neo-tree 定向检查通过，覆盖实际隐藏项目提示高亮组、默认继承、Light／Dark／色槽、重复应用、恢复及无关组不变；新增 `tests/config/tree_message.lua`。Windows仅新增接口、原UI按唯一调用点插入一行、README按旧SHA更新，保留其他本源内容与原字节备份；两原生测试有隔离日志目录不可用警告，不影响行为断言。所有自有进程退出，未热载／重启用户窗口、改 PowerToys 设置或启动构建／发布。
- 现场与刷新部署证据 `target/glow-windows-theme-focus-20261023/{diagnosis.json,stalled-before.png,stalled-after-read.png,stalled-after-redraw.png,redraw-deployment.json}`；颜色入口检查 `target/glow-neotree-message-20261023/`，Windows守卫与原生收据 `target/glow-neotree-message-windows-20261023/{deployment.json,arm64.json,x64.json}`。刷新修复与接口均下次新会话完整加载；当前卡住画面已由前述单次纯重绘恢复。

### 2026-10-23 Mac 全屏 CMatrix 开屏去阴影（Codex）

- 用户观察到开屏全屏字母雨下方残留浮窗阴影；原因是 `matrix_intro` 覆盖窗口尚未进入阴影排除快照。现 Mac 平台按既有 `glow_popup_profile=matrix_intro` 身份排除真实窗口 ID，intro 创建并标记后同步发布 RPC 再 redraw，避免等待 WinNew 的延迟首帧；关闭沿用同一控制器的完整快照清理。仅调整本源及 portable 的 `appearance/intro.lua`、`appearance/float_shadows.lua` 与 `platform/neovide.lua`，普通浮窗阴影保留，未改字体、颜色、动画或 Windows 实际配置。
- 新增 `tests/navigation/matrix_shadow.py`：本源／portable 各6场本机真实 embedded Neovim／CMatrix 启动通过，覆盖首个 `win_float_pos` 前已排除 ID、VimEnter／UIEnter、新旧前端脚本接管、焦点／材质及窗口／buffer／job 清理；Windows／Linux 仅为平台策略模拟。两份配置各12场既有 Notebook／Picker／Snacks／WhichKey 阴影协议回归通过。首轮采集将 MessagePack 窗口 ExtType 当整数，保留失败证据后只修测试解码；不冒称原生 GUI／GPU 像素验收。
- 全部自有检查进程已退出，无后台等待。下次 Mac 新会话生效；未替换 App、热载或重启用户窗口。原字节备份与通过回执为 `target/glow-macos-matrix-shadow-20261023/{before,protocol-local.json,protocol-portable.json,notebook-local.json,notebook-portable.json,manifest.json}`。

### 2026-10-23 配置独立维护、主题路径统一（Codex）

- 按用户最新要求，统一相对入口、分开维护整个配置：Mac 与 Windows 各以自己系统的 `~/.config/nvim` 为本源，公共功能逐文件核对后同步，Windows 参数／配色不被 Mac 或 portable 整份覆盖。项目 AGENTS 与两份 README 已更新；不新建仓库、不搬回 Windows 配色，也未复制或改写两端主题文件。
- Windows `windows_themes` 改读标准 `config.appearance.themes.*`，主题目录为当前 `stdpath(config)/lua/config/appearance/themes`；现有 x64／ARM64 home 桥接均指向 `C:\Users\ysrae1\.config\nvim`。不再优先读取 AppData 旧副本；`reload()` 与主题顶部的旧单主题命令现在读取同一文件。AppData 原文件原样保留，相关原字节另备份在 Windows `C:\GlowDev\ConfigThemeEntry20261023`。未迁移的新 stack 仍默认自己的 profile，采用它时须显式沿用既有 home 入口；安装／启动代码核对未发现覆盖已有用户配置的路径，无据不改安装器。
- 本机本源→portable 定向检查、Windows 原生 x64／ARM64 的隔离用例及实际完整主题／Base46 选中行解析均通过。Windows 已保存的 Light `folder_bg=#92929B`、Dark `#47525C` 和两主题 blend15 被正确读取；两份 `.config` 主题的未保存缓冲区保留。Windows 仅 helper／README 两文件发生本轮部署变更，其余配置与旧 AppData 文件 SHA 保持，Mac 两主题 SHA 保持；未关闭、热载或重启用户窗口。现有窗口若手动应用，先保存主题，再执行 `:lua package.loaded['config.platform.windows_themes']=nil; require('config.platform.windows_themes').reload()`；新会话直接使用新入口。
- 两文件按旧 SHA／目标 buffer modified 守卫、原字节备份及实际非空 swap 备份原子更新；首轮预检因 PowerShell 默认编码误读中文 UTF-8 收据而零写入停止，明确指定 UTF-8 后完成，原失败回执保留。自有进程均退出，没有后台监控或新发布。证据 `target/glow-windows-config-theme-entry-20261023/{deployment.json,theme-differences.json,arm64-actual.json,x64-actual.json}`；源／portable回执与 Mac 主题哈希见 `target/glow-theme-config-entry-20261023/`，新回归沿用 `tests/config/windows_themes.lua`。

### 2026-10-23 Neo-tree 路径输入、C/C++ 能力核对与 x64 Java（Codex）

- 按用户要求新增 Neo-tree 文件树 `g/`（先 g 再 /）：在树面板内弹出路径输入框，目录切换树根，文件定位并选中；支持 `~`、相对／绝对路径及 Windows 盘符／UNC。取消、空值或无效路径不改变树，保留草稿；`?` 帮助和中英提示同步。手动跳转后在树中浏览保留该根，返回编辑文件后恢复已有自动跟随。修改 `navigation/neo_tree_path.lua`、`navigation/project_root.lua`、插件键位及 UI 词典四文件，本机验证后逐字节同步 portable，再按旧 SHA／目标 buffer modified 守卫、原字节备份与非空备份路径原子部署 Windows 共用 home 配置；下次启动生效，未热载或重启现窗。
- 新增 `tests/navigation/neo_tree_path.lua`，Mac 本源／portable 及 Windows 原生 ARM64／x64 均通过实际冻结 Neo-tree／Nui 定向检查：左右侧树内输入框、18／28／40列、目录／隐藏文件选中、取消／非法／空输入、词典帮助、手动根与自动跟随恢复、未保存草稿。Windows 用户私有主题字节不变，全部自有检查进程已退出；此为 headless 实际窗口与导航检查，用户 GUI 观感待自行验收。Windows 部署／检查证据 `target/glow-neotree-path-deployment-20261023/{manifest.json,deployment.json,buffer-guard.json}`。
- C/C++ 能力只读核对：Mac 普通 zsh 可用 Apple Clang21、CMake4.3.4、Ninja1.13.2及Make3.81；现有 CMake extra 在项目有 `CMakeLists.txt` 时提供 `:CMakeGenerate`／`:CMakeBuild`／`:CMakeRun`，单文件可从 Ctrl-T 终端手动编译。Windows 普通 PowerShell／CMD、非交互 zsh -f 及当前 ARM64 Neovim 进程内均无 clang／cl／cmake／ninja／make 命令入口；桌面“Glow 开发环境”可用 MSVC19.44.35229（ARM64宿主、x64目标）、Clang21.1.8、CMake4.4.4、Ninja1.13.2和NMake。clangd／clang-format 为语言服务／格式工具，不负责生成程序；未发现通用编译运行当前 C/C++ 文件快捷键。未安装或改工具链／PATH，未编译或执行用户项目。普通环境／专用入口证据 `target/glow-cpp-capability-20261023/windows-audit/{tools-ordinary.json,tools-developer.json,followup.json}`；当前编辑器只读实查见前项 `runner-preflight/guard.json`，早期审计 pipe 查询超时不作为通过证据。
- Windows x64 Java 原缺 parser 已补齐，复用固定 grammar `a7db5227ec40fcfe94489559d8c9bc7c8181e25a`／ABI14，MSVC HostARM64→x64 编译 PE8664（514560字节，SHA `536d9e08124756e9b0aeaf0ccf4f1a759533f2c4d53dc8e5511f277cccd566e4`），部署到实际 `pd-hardware-opengl-a96bece797dd-7d61575a` profile。实际 x64 Neovim0.12.3 的 Java 文件类型、无错误语法树、自动高亮及 Light／Dark 解析通过（82 capture／21类）；原56个 parser 和164个配置／私有主题文件哈希保持。首轮守卫撞到本轮另一个临时查询进程而零部署停止，保留失败回执后只续守卫／部署／profile验收，未重复构建。未安装JDK／jdtls、未运行Java、未重做Mac／ARM64或操作用户窗口；全部自有进程已退出。`target/glow-java-x64-20261023/{attempt1-result.json,result.json,acceptance.json}`。

### 2026-10-23 标题居中、Avante 材质与阶段结束（Codex）

- Picker 标题实际网格已左右各一空格，约5px差来自字体可见墨迹边界。`b534ddf29e76b0acf74f7e3f421b873cd13c8f23` 新增显式 `centered_caption` 角色及前端能力声明，只平移文字墨迹，不改背景、网格、字体或配色。覆盖 Snacks／Telescope 六类标题组及其派生 caption，包含文件、Buffer 列表、结果区及预览；Avante／Notebook 胶囊沿用各自布局。30项真实字体 CPU raster 检查覆盖五类文字、三档缩放与浅深主题，左右间距差均≤1px，缓存与既有渲染回归通过；不等同于两平台 GPU 界面验收。`target/glow-picker-caption-spacing-20261023/source.json`。
- Windows 同源 ARM64／x64 release 均完成，继承 Snap 及系统外框修复；最终分别41,434,624／43,587,584字节，SHA `d70e0070a900b41c8eefb4665dda8bbcb1481cbc10ef6a1d7ac172acc5ca28de`／`36c72826f3de3d70ebe25cd46841143b02639b7b9ea4053f2b9c12836b250f12`。PE架构／GUI子系统、源包及远端哈希核验后，三入口守卫备份原子切换，下次启动生效；自有构建进程全部结束，未重启用户窗口。`target/glow-windows-caption-centering-20261023/receipt.json`。Mac 用同commit隔离干净检出经 `neovide-update --no-fetch --stage-only` 构建，App／CLI arm64与严格签名验证通过，资产已还原；App SHA `293116f25f2ebfdc2437720ed4faf776af54adff3547ce10c6029223ef90e82a`，已安装App观察状态见上文，CLI未替换。候选及构建证据在 `target/glow-picker-caption-spacing-20261023/mac-build/`。
- Avante 全区统一归 `popup_materials.config.avante={mode="editor"}`，正文、选区区、输入区、边框、间隙及胶囊外侧沿用编辑区材质，语义实心标题／按钮保留；清除旧 transparency.lua 中第二套 Avante 材质来源。复用窗口变回普通 split 时只恢复本模块拥有的 namespace。Mac／portable 的真实窗口及 UI 协议检查、Windows ARM64 原生六窗口和复用边界通过，三文件守卫备份部署；Windows 用户 material_blend=30及私有调色板保留。最终证据 `target/glow-avante-editor-material-20261023/{ui-protocol.json,reuse-deployment.json,windows-reuse-headless.json}`；用户 GUI 外观待验。
- Mac 编辑区透明度独立移至 `config/platform/macos_appearance.lua` 的 Light／Dark `normal_opacity`，保存后 `:lua require('config.platform.macos_appearance').reload()`；主题事件自动选对应值。`GlowGlass opacity` 临时值即时更新 Avante，`GlowGlass reset` 恢复当前主题默认。仅Mac GUI启用，本机／portable的主题事件、真实Avante窗口、重载及既有Glass检查通过；未改Windows独立值。用户工作中继续修改Mac参数／配色，收尾保留最新本机Light .95／Dark .85，portable保留代理最后同步的 .90／.85，此为参数差异，不回写用户颜色。
- Java 高亮缺口是 Mac／Windows ARM64 均漏装 parser，已有 Ayu 映射无需修改；仅补固定 grammar `a7db5227ec40fcfe94489559d8c9bc7c8181e25a`／ABI14，原56项保持。实际 Java 文件类型、无错误语法树、自动高亮及两主题解析检查通过（82 capture／21类）；本机 ensure_installed 与 portable统一清单补Java，共57项。未安装JDK／jdtls、未操作现窗，Windows x64及Linux原生未验。`target/glow-java-highlighting-20261023/{acceptance.json,windows/result.json}`。
- 本阶段所有已分派子任务已完成，无自有后台工作或继续监控；未发布版本。用户自行验收重开后的标题留白、Windows外框／Snap材质及Notebook／Avante外观。按用户要求，以本文件作为新对话最小交接，后续承接“当前C/C++编译能力及入口”核对；用户随后指定Windows x64 Java parser也放到新工作补齐，不恢复无关历史任务。已只读发现本机 clang／clang++、CMake／Ninja／make 可用，配置有 clangd／clang-format，尚未确认编辑器编译动作；Windows已有开发工具部署记录，普通终端可用性留新对话实查。

### 2026-10-23 Windows 原生外框、Mac 输出去阴影与 Buffer 标题（Codex）

- 用户追加 Windows 主窗口系统圆角、细描边和阴影。固定源码 `5681beecf656432f7a50a536aabd7e5303e3b240` 仅改三份 Windows 窗口相关 Rust：默认显式请求 DWM Round（用户显式圆角设置仍有效），frameless 顶层启用 Winit 原生 shadow 路径并使用系统默认描边色，进入全屏关闭其1px非客户顶边、退出恢复。保留渲染 alpha／RGB／主题，未引入 DwmExtendFrameIntoClientArea；核对自有 resize hook不处理WM_NCCALCSIZE、八向命中仍以系统外框及DPI为准。Mac 四项 resize release检查、格式检查通过。
- 同一 commit 的 ARM64／x64 release 均通过，41,415,680／43,565,056字节，SHA分别 `4e5bfb2ff8cf1afd361a6ee5c50e221147539b16fdd2cea0ae2704afa1bba84b`／`9d7cb8c401437b7d790a0a2a1db80530ff8eb8addaa93662cbddb6540396d1a6`；PE架构／GUI子系统2及三入口旧SHA、原字节备份／原子切换均核验，下次启动生效。前两次源包选择遗漏derive／桥接Lua使Cargo预检101，失败证据保留；改为完整固定commit git archive后两架构成功，没有改产品源码或依赖来绕过预检。全部构建与部署隐藏启动、自有进程均结束。`target/glow-windows-native-frame-20261023/receipt.json`。未实际GUI验收；[微软说明](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-rounded-corners)表明圆角是系统提示、最大化／Snap及虚拟或远程环境受系统策略限制，不能将API请求写成三项像素均通过。
- 用户要求仅 Mac Notebook 展开输出框去阴影。新增 `config.appearance.float_shadows` 单一完整排除快照控制器，平台入口只为Mac启用真实 `molten_output` window ID；保留Snacks子层／WhichKey footer规则、其他浮窗和picker外层阴影。原生Lua优先委托、旧配置保留fallback；旧App由同名augroup接管及单次真实UIEnter兼容，不替换Mac App、不全局关闭shadow、不伪装Snacks角色。重复接管清缓存，修正已有server被旧脚本写回后的快照去重缺口。源／portable各12场真实RPC／UIEnter检查及无配置fallback picker回归通过，包含新旧脚本、两种启动顺序、已有输出、三平台策略、Tab／关闭清理和frame／capsule／材质保留。`target/glow-macos-notebook-shadow-20261023/protocol-{local,portable}.json`；尚非GPU像素验收，下次Mac会话生效。用户若需当前会话手动应用可用 `:lua require("config.appearance.float_shadows").setup({ notebook_output = true })`，本轮未向现窗发送。
- 用户指定 `空格 b e` 顶栏标题为 `Buffer Explorer`／`Buffer 浏览器`。确认真实冻结快捷键打开Neo-tree buffers源，现 `tree_title.lua` 按 `neo_tree_source` 选Buffer标题，仅修词典该中文项，其他树源仍为文件浏览器；之前方正Windows图标保留。源／portable／实际Windows原生Neovim各检查快捷键→真实树源、中英切换、492种宽度、源往返、未保存内容保护通过。两文件守卫备份部署，旧探针语法及绕过既有UNC适配的两次失败收据保留；最后只续验而未重复部署。`target/glow-buffer-explorer-title-20261023/{source.json,windows-headless.json}`。用户随后另报picker红色标题内左右留白不等，作为独立事项继续，不能将该标题命名检查当作留白已修。
- 上述三项及下方Notebook胶囊均已完成可独立交付；当时未发布新版本、未关闭／重启用户窗口、未替换Mac安装。随后完成的picker标题留白及构建状态见上节，当前无后台等待。

### 2026-10-23 Notebook 展开输出的右下角收起胶囊（Codex）

- 按用户要求，Mac／Windows 的 `空格 j o` 展开输出框在右下角固定显示 `󰕎 q / Esc` 胶囊；长短输出均显示，正文横纵滚动不移动提示。复用主题已有 `GlowNotebookExpand*` 普通字号／透明端帽，底边预留一行、原生 frame 只在胶囊处断开下边线；极小视口隐藏提示并保留至少一正文行，原 q／Esc 收起动作始终可用。旧前端安全保留框内提示，无需改 Rust 或替换 Mac 已安装 App。
- 仅修改 `notebook_output.lua`、`notebook_ui.lua` 与浮窗 caption 的四个 Notebook 语义组保留规则，先本机再同步 portable；用户颜色、Windows 独立主题与材质值均不变。两份配置的实时／保存输出滚动回归及各14项附 UI 协议检查通过：浅深主题、实际 footer glyph 列／gap 对齐、固定底行、滚动位置、缩窗、短输出、q／Esc 清理、旧前端回退以及实际 popup caption 材质。未启动内核、AI 或用户 GUI；协议不等于 GPU 像素验收。
- Windows 三文件按旧 SHA 与用户目标 buffer modified 元数据守卫，原字节备份后原子部署；实际原生 Neovim0.12.6 语法和 `output_scroll.lua` 通过，自有进程全部退出。首轮 File.Replace 空备份路径导致零替换失败，保留收据后使用实际非空备份路径修正；完整检查、部署及必要重试均通过 GUI 子系统 launcher／CreateNoWindow 隐藏启动，未热载或重启现窗。下次加载配置生效，真实外观由用户验收。
- 按用户追加要求，原上箭头改为展开图标U+F054F对应的[双向内收图标U+F054E](https://pictogrammers.com/library/mdi/icon/unfold-less-horizontal/)，无横杠；源／portable各两主题实际linegrid、宽度与gap增量检查通过，现有及随包六款Mono字体映射／双轮廓通过，两者均1列、胶囊仍12列。旧测试字体同时缺展开／收起两字形，记录为既有边界而未改字体。Windows仅helper此一行守卫备份部署，原生语法／字形宽度／gap检查通过，自有进程退出。增量证据为同目录 `protocol-icon-{local,portable}.json`、`icon-fonts.json`、`deployment-icon.json`、`windows-headless-icon.json`。
- 证据 `target/glow-notebook-output-hint-20261023/{protocol-local.json,protocol-portable.json,deployment.json,windows-headless.json}`；新增独立 `tests/notebook/output_hint.py`，README 与验证说明同步。该项已完成，不等待后续独立 Windows 原生外框构建。

### 2026-10-23 Windows 主题独立、Avante 材质与终端反馈（Codex）

- 按用户要求，将 Windows 完整 Light/Dark 调色板及高亮参数与 Mac 独立。新增 `config.platform.windows_themes`，Windows 优先读取 `%LOCALAPPDATA%\NeovideGlow\appearance\themes\ayu_{light,dark}_customed.lua`，缺少私有文件的新安装使用共享默认；Mac/Linux 继续原主题加载路径。`chadrc` 与嵌入 Yazi 后备配色共用此入口，私有文件不进入 portable／配置同步树，也不回写 Mac。共享源与 portable 的隔离检查已通过，Mac 两份原主题文件 SHA 不变；Windows 原保存值已逐字节迁入私有目录，两份原源文件保持不变，当前 ayu_light 选择保留。helper 先安装，再按 SHA 守卫原子更新 chadrc／Yazi／README并保留备份；实际 ARM64 隔离检查完整调色板深度相等、私有文件优先、重载路由及语法均通过，不启动插件／GUI。下次载入生效；以后编辑私有文件后执行 `:lua require("config.platform.windows_themes").reload()`。说明与重载入口同步 README，项目 AGENTS 记录平台边界。`target/glow-platform-themes-20261023/{deployment.json,windows-headless.json}`。
- Windows Avante 分隔格及胶囊外侧材质原先仅在 Mac Liquid Glass 条件下匹配，现仅放开这两处 Windows 路径；未改 RGB 或原生绘制。用户最新 `windows.material_blend=30`、原格式及其他参数保留，守卫备份后部署。源／portable／实际 Windows ARM64 共六组深浅平台检查通过，Mac/Linux 前后快照一致；真实边框及圆角观感尚待用户验收。证据 `target/glow-windows-avante-material-20261023/{source.json,deployment.json,windows-headless.json}`。
- Windows 内嵌 zsh 的 gitstatus 错误已按实际继承环境复现：Neovim 传入 Windows 格式 `XDG_CACHE_HOME`，gitstatus 将其缓存路径判为非 POSIX 绝对路径。仅 workstation-config 的 `shell/zsh-port/windows.zsh` 转换 `GITSTATUS_CACHE_DIR`，保留 XDG 原值、用户 p10k 及 Mac 路径；Windows 已备份部署。实际用户环境下的自建 Neovim 虚拟 UI，经相同 PowerShell→zsh 链验证 daemon state2、查询 ok-sync、测试分支及未跟踪文件；七份既有 shell／入口文件 SHA 不变，自有仓库／进程已清理。现有终端未重启，用户执行 `exit` 后 Ctrl-T 重开验收。`target/glow-windows-zsh-gitstatus-20261023/receipt.json`。
- WhichKey 初次只读查询确认用户窗口正在录制 `q` 寄存器；冻结插件录制期间会移除自动提示触发，附 UI 协议已复现。用户反馈按 `q` 无反应后补查 Avante 默认 buffer-local `q` 关闭侧栏映射；独立同语义映射场景证明其可能拦截结束录制，条件命令 `:if reg_recording() !=# '' | execute 'normal! q' | endif` 能安全绕过，重复执行不启动新录制。后续只读现窗已无录制、Avante 已关闭、普通代码缓冲区 Space 触发存在且树含35个子项；未向现窗输入或修改配置，告知用户 Esc 后直接 Space 验收，不再重复按 q。无法追溯最初触发录制的按键；用户随后手动确认代码区 Esc→Space 能正常弹出菜单，本项已闭合。证据 `target/glow-windows-whichkey-20261023/{live-readonly-q-followup.json,live-readonly-tree-followup.json,avante-q-stop-ui.json}`。

- 用户后续观察打开文件时有终端短暂闪现。本轮最后检查确实以未隐藏的 PowerShell／原生 headless Neovim 控制台方式运行，可能与该次闪现相关；没有视觉记录，不能认定具体来源。全部自有检查已返回、无后台进程；收到反馈后停止新增 Windows 调用。Avante 外观与新终端由用户验收，未重启／热载用户窗口、未替换 Mac 已安装产物、未构建／发布或新增 standby。

### 2026-10-23 现场反馈：Snap 重绘、Windows 材质及 TeX 项目迁移（Codex）

- 用户报告 Neo-tree 展开时贴顶最大化、左右贴边半屏及后续缩放会空白、需点击才恢复，并观察到背景材质变化。`7da35f706fc27227e80ec3af5c4595cc3cfd3660` 修复 Windows 原生 paint 在 Snap 不发送 `WM_SIZING` 时绕过完整准备的问题：先处理缓冲批次、布局和动画再呈现，尺寸变化期间继续失效重绘，退出原生循环补一次 paint，纯移动不持续刷新。没有通过修改 RGB／opacity 掩盖画面缺失；材质观感与空白是否全部解决仍待用户实际验证。
- 同一提交的 ARM64／x64 release 均 exit0，匹配各自 Skia；41,413,120／43,561,472 字节，SHA 分别 `cf592322c66d78569144f935eccd236c6473fce41a000818845087c9db905f3c`／`d393cdcadcef462ab4115ee4c25e484b47d314b5b49e5b32af370790acbc1ff3`。Mac release 原有四项 resize 几何检查通过。桌面 `Glow ARM64`／`nvidec-arm64` 及原 x64 桌面／`nvidec` 已守卫备份、并排切至下次启动，未关闭或重启用户窗口。两次自建 GUI 均未达到 readiness，不能宣称复现／像素验收通过；自有进程已按 PID＋创建时间清理，按用户“弄好交给我测试”停止追加 GUI。证据 `target/glow-windows-snap-redraw-20261023/{receipt.json,deployment/deployment.json}`。
- Windows `transparency.lua` 用户实际已改为40，却被 `apply()` 的80及浅色平台15覆盖。现集中为该文件 `M.config.windows.material_blend=40`，深浅面板统一；原 Windows `normal_opacity` 深.85／浅.98、`popup_blend` 深100／浅15也在同一 Windows 表，保留原语义。Mac/Linux 的 `M.config.material_blend=80` 不读取 Windows 表，独立选中行／RGB／字体不变。Windows 原格式化差异保留，单文件 SHA 守卫备份部署；本源／portable 定向检查、10个实际状态栏合成场景及实际 Windows ARM64 headless 通过，含编辑53后主题刷新及重载。首次迁移随新前端重开；以后修改保存后执行 `:lua package.loaded['config.appearance.transparency']=nil; require('config.appearance.transparency').setup()`。证据 `target/glow-windows-snap-synctex-20261023/material/`。
- Neo-tree 标题 Windows 图标从斜透视 U+F17A 换成方正四格 U+F0372；实际安装字体与随包 FiraCode Nerd Font Mono 字节一致，已核对字形。本源／Windows各75个标题宽度场景通过，Mac/Linux图标、字号、颜色及布局不变，未热载用户窗口。`target/glow-windows-feedback-20261023/tree-icon/`。
- 当前 Windows `Desktop/tex.tool/tool.tex` 的旧 PDF／SyncTeX／recorder 仍记录 Mac `/Users/...`，实际四种源路径查询均 code0、stdout `No tag`，空 stderr 又吞掉诊断。仅 Windows 修正错误显示，并新增构建缓存迁移模块：真实 VimTeX 初始化发现 `.fls` 的绝对 PWD 与当前根不同，给该 compiler 首次实际编译加自有 `-g`，成功后恢复增量；不自动编译、不删产物，手动原有 `-g` 保留。Mac不导入该模块／注册新事件／改编译参数，诊断也保留原分支。真实冻结 VimTeX 的本源／portable四次定向检查通过，包含 Mac 旧根项目行为不变；四份配置已守卫备份部署 Windows。证据 `target/glow-{synctex-diagnostics,latex-cache-migration}-20261023/`、`target/glow-windows-synctex-feedback-20261023/config-deployment.json`。
- 强制编译另暴露 XeLaTeX 找不到已安装的用户级 FiraCode Nerd Font Mono，随后缺 `tgschola.sty`。新增 Windows TeX fontconfig 局部扩展，包含用户字体目录和实际 TeX 字体目录，保留原 `fonts.conf`；明确选择 TeX 时的复用／安装入口均接入。实际 TeX 父入口的字体 cache、中文 XeLaTeX、SyncTeX三检查通过，用户全局依赖选择 SHA 不变，Core八项检查通过。补齐 `tex-gyre` 后当前文档以 XeLaTeX 成功生成新 PDF 和 `Input:1:C:/Users/.../tool.tex`，原源码 SHA `56e95971723a8aad0e14f8bb8fa2f87d3171acacb49ff78e73fdf81d27fce12d` 不变，原产物备份在 `C:\GlowDev\GraphicsQA\TexFeedback20261023Rebuild\before`。第74／20行真实正向与逆向 CLI 均通过；首次 Python 验收保留 CR 导致逆向参数失败，修正为 splitlines 后只重验查询，未重复编译。`tex-gyre` 来自官方 CTAN HTTPS；tlmgr 输出有 `not verified: pubkey missing` 及 cmd 启动告警，未将此安装记作 PGP 校验通过。此前编译失败、工具探针与安装失败收据原样保留，最终可用状态以 `target/glow-windows-synctex-feedback-20261023/project-verified.json` 为准。
- 本轮窗口 GUI、材质实际观感及鼠标双向定位由用户验收；已给出保存重开 `Glow ARM64` 后测试贴顶／左右半屏／连续缩放、深浅面板、`:VimtexView` 与 PDF Ctrl＋单击的入口。未替换 Mac 已安装产物、未改既有 `chadrc.lua`、未发布新版本；后台构建及自建测试已结束，不新增 standby／自动唤醒。

### 2026-10-23 Windows ARM64 插件与 Notebook 依赖补齐（Codex）

- 按用户新授权完成此前“仍待单独适配”的依赖项。证据统一位于 `target/glow-windows-arm64-dependencies-20261023/`。Avante 冻结源码 `7a9fbbd` 的四个原生模块、FFF v0.11.0、LuaSnip jsregexp 已按 ARM64 准备并守卫部署；实际 ARM64 Neovim 加载、分词／模板／repo-map／HTML 转换、模糊查找及正则捕获通过，既有 x64 原生库保持。既有 Fzf ARM64 修复复用。56 个冻结语法解析库均实际加载／解析通过，其中 10 个使用非空语法样例，其余仅验证 ABI 与空输入树；Python 使用冻结提交，未混入 x64 DLL。`native-plugins/{receipt.json,parsers/deployed.json}`、`luasnip/{deployment.json,deployed-probe.json}`。
- Notebook 使用独立、不继承全局包的 ARM64 Python 3.14.8 venv，按原锁安装 53 个包并生成真实 Molten rplugin manifest；未重建或覆盖用户科学环境。真实内核返回 42、预期 ValueError、执行计数及异步编辑响应通过；PNG 经内核→Molten→ipynb 导出后尺寸／像素一致，中文空格路径 Jupytext 往返保留结果、错误和图片。私有 Jupyter 路径只在选择私有 host 时启用，显式用户设置保留。实际依赖父入口已选择新 provider，原先无 selected.json；没有虚构旧选择备份。`notebook/{setup-report.json,live-report.json,jupytext-report.json,runtime-deployment.json}`、`shared/notebook-selection.json`。
- ARM64 profile 已准备冻结的 24 项 Mason 工具；23 项 CLI、9 项 LSP initialize/shutdown、实际 Neovim 的 24 项命令解析及 3 项 LSP 初始化通过。Node、Java、Texlab、Neocmakelsp、Ruff 为 ARM64，其他部分进程外工具及其私有 Python 继续兼容 x64；不宣称全软件原生化。未改全局 PATH 或旧 x64 profile。覆盖范围记为 `mason/receipt.json` 的 `passed_scoped`；未做完整项目诊断／调试，Go SDK 不在 PATH，未验证 Go 项目构建。
- 另补齐 Avante 原缺失的 ACP adapter 2.2.2 与 Codex 0.160.1 ARM64，使用既有私有 ARM64 Node；保留冻结 npm 锁和 Mac 路由。实际入口环境下路径、语法及版本检查通过，未 initialize、读取认证或发送聊天请求。新增 `Setup-ACP.ps1`，安装父入口已实际返回 ready，复用分支未运行 npm 或修改现有模块。`native-plugins/acp/receipt.json`、`shared/acp-parent.json`。
- 公共配置先本源验证、再同步 portable、按 SHA 备份部署 Windows；新增可复用 Notebook／Mason／ACP 准备入口，Avante／LuaSnip 构建明确目标架构，Core 素材包含新入口和 ACP 锁。本源＋portable 共 30 项隔离检查、Windows PythonProbe 9 组及 Core 打包 8 项检查通过；普通 ARM64 home 配置实际启动、Python provider RPC、原生库、Mason 路径、Python 解析及 Avante 路径均通过，见 `shared/profile-health.json`。本次未构建新的完整 ARM64 离线安装包；`build-bundle.py` 主类仍为 x64，不能据单项架构支持宣称完整 ARM64 安装器已验。
- GUI 图片像素、实体交互及在线 AI 对话未验；必要检查已结束，不继续 standby。早期探针／构建失败及定向修正证据保留，没有追认失败断言；各模块自有进程已退出。未关闭／重启用户应用，未替换 Mac 已安装产物，未改字体、缩放、主题色或既有 `chadrc.lua`，未发布新版本；下次启动使用部署结果。

### 2026-10-23 保留 Windows 内嵌 PDF，实现双向搜索（Codex）

- 按用户选择扩展 WebView2 后端，采用离线 PDF.js 6.4.299 与版本化坐标桥；新前端明确声明 SyncTeX 能力，`VimtexView`／`GlowTexForward` 优先内嵌，PDF 正文 Ctrl＋单击逆向回源，显式 `g:glow_tex_viewer='sumatra'` 仍可选择外部回退。本源配置先验证再同步 portable，三份文件按旧 SHA 守卫部署，字体、缩放、主题色不变。
- 源码最终 `fdeece58f8c14f33a0f08203e89646e018e53e08`，匹配架构 Skia 的 x64／ARM64 release 均 exit0、输出关闭、自有构建进程退出；EXE 分别 43,559,424／41,411,072 字节，SHA256 及 PE 见 `target/glow-windows-embedded-synctex-20261023/build/{x64,arm64}/receipt.json`。旧 `4433823` 构建保留于 `attempt-4433823`，因真实定位缺陷不用于部署。
- 真实 ARM64 首轮发现 SyncTeX `v` 为包围框底边、`H` 向上延伸，查看器原来向下延伸使第3行误回第5行；已修正方向、小标记中心与定位上下文。真实 XeLaTeX 浏览器回环在 135%／50% 均回第3行；Windows ARM64 新版 135% 实际 WebView2 DOM→host→Lua→SyncTeX 也回第3行，目标标记与上下文已查看，nohidden 拒绝覆盖及 hidden 草稿保留通过。x64 新版 ready／两页／显式关闭通过。原首轮稳定正向定位证据复用，新版 ARM64 仅续必要失败断点；不是实体鼠标验收。
- 本源＋portable 28 项隔离回归、2 项 Rust 协议测试、4 项 Node／7 组浏览器检查通过，官方资源 286 项哈希核对通过。ARM64 续验附加 Network 统计断言把初载误当重载，原失败收据保留并按实际观察记为 `passed_scoped`；该轮未执行显式 RPC 关闭，只确认正常 quit 与9个自有进程退出，未冒称全套通过。实际范围绑定 `integration/{arm64-01,arm64-02,x64-02}`、`viewer/tex-roundtrip` 及 `deployment/deployment-authority.json`。特殊后处理裁切 PDF 的 MediaBox 坐标仍需额外元数据，普通 XeLaTeX 输出已覆盖；Mac 未重做原生 PDF GUI、Linux 未验。
- 已并排部署并切换 x64 桌面／`nvidec` 与 ARM64 原入口；原程序、入口字节、三份配置和新增 PDF.js 许可均保留，`deployment/deployment.json` 为 `deployed_next_launch`。首次入口替换因 PowerShell 5.1 将空备份参数绑定成非法路径，在零文件更改时失败；改为真实同卷备份路径后切换成功，原失败收据保留。未关闭／重启用户应用、未替换 Mac 已安装产物、未重封或发布包；所有本轮自有进程已结束，不再 standby／新设唤醒。

### 2026-10-23 周用量重置后的两项修复（Codex，首轮记录）

- 定时检查实际读取 Codex 七天窗口（10080 分钟）由 100% 降为 0%，重置时间也已更新，符合用户“重置才开始”的条件；随后暂停一次性检查 `glow`，未恢复无关历史任务。依据 `target/glow-windows-two-fixes-20261023/quota-gate.json`。
- ARM64 Fzf 的直接原因是数据准备时过滤原生二进制，实际缺少 `build/libfzf.dll`。已按 Neovim 架构编译并守卫部署 ARM64 DLL（114688 字节，PE 0xaa64，SHA256 `4b77ba529e57d45c41a47d9f9a711858eab206c21f2c99fbf1c239e7118bcc12`，仅 KERNEL32.dll），保留原 x64 DLL及配置备份。修正插件依赖结构、分架构 CMake/install 构建与明确警告／Lua 排序回退，portable 构建器仅调整 Fzf 分支。Mac 本源／portable、Windows ARM64 候选／部署、现有 x64 与缺库回退六项实际加载／排序通过；见 `target/glow-windows-fzf-fix-20261023/receipt.json`。
- Windows 当前 WebView2 内嵌 PDF 明确不支持坐标 SyncTeX；本轮通过官方原生 ARM64 SumatraPDF 3.6.1 恢复双向搜索，保留内嵌普通预览和系统 PDF 关联。`VimtexView`／`GlowTexForward` 发起正向搜索，Sumatra 正文双击为逆向入口；每个 Neovim server 使用独立查看器 profile，逆向最小客户端通过结构化 RPC 回到发起实例，保留未保存草稿。另修复 Windows 盘符／UNC 绝对路径与 XeLaTeX/SyncTeX 的系统 ANSI 中文文件名解码；Mac 保留既有原生／Skim 路由。查看器下载哈希及签名通过，六个运行配置文件含词典均按旧 SHA 守卫、原字节备份部署，普通 ARM64／打包 x64 环境均能自动发现原生 ARM64 查看器，下次启动生效；见 `target/glow-windows-tex-search-fix-20261023/{deployment.json,sumatra-rpc-receipt.json,arm64-viewer-detection.json,x64-viewer-detection.json}`。
- 验证：真实 XeLaTeX／SyncTeX 中文、空格、单引号及独立输出目录往返通过；实际逆向 RPC、两实例隔离、未保存草稿保护通过。Windows TeX 真实父入口 7.13 秒通过，复用 TeX／Sumatra、两子进程 exit0 且输出关闭，零下载／新增安装／Python 导入，用户选择保留；首次验收脚本 ANSI 读取 UTF-8 JSON 的误判已定向修正，失败证据保留。安装流程同时检测／补齐双向查看器，并按 OS 架构复用；本源＋portable 共 28 项隔离 headless 回归及改动格式检查通过。收据 `target/glow-windows-two-fixes-20261023/{latex-parent-passed.json,headless.log}`。
- GUI 边界：自建隔离 Neovide／Neovim／Sumatra 在真实登录 session1 成功启动且收到正确参数；CUA 返回旧画面，原生自有窗口尺寸也不可用，因此未发送 SendInput、未验证实际定位高亮／正文双击。两项鼠标体验留待用户在场；不能将 RPC 通过写成 GUI 通过，Windows 内嵌双向搜索也未实现。测试窗口按精确 PID／创建时间／路径清理，最终自有进程均已退出；未关闭用户窗口、未替换 Mac 已安装产物、未构建／发布新包，既有 `chadrc.lua` 改动保留。各自证据中的 `gui-cleanup.json`／`final-process-check.json` 为清理依据；本轮结束，无 standby 或继续唤醒。

### 2026-10-22 16:21 用户反馈待办：仅记录，暂不处理（Codex，历史记录）

- 用户明确要求“现在先不工作，先记录一下”；本次只保存反馈与截图，后续排查／修复等待用户明确恢复。
- Windows ARM64：dashboard 启动时 lazy.nvim 报 `Failed to run config for telescope-fzf-native.nvim`，`fzf` 扩展加载失败；截图指向 nvim-arm64 数据目录内的 `telescope-fzf-native.nvim/build/libfzf.dll`，提示“找不到指定的模块”。具体原因未排查。
- LaTeX：用户反馈编译后，源文件与 PDF 之间无法双向搜索（正向／逆向搜索）。本次未复现或检查阅读器／SyncTeX 链路；此前编译通过不代表双向搜索通过。
- 截图（16:21:14）：`target/glow-windows-user-feedback-20261022-1621/screenshot.png`。未启动代理、Windows 操作、构建或测试，未修改程序及运行配置。

### 2026-10-22 ARM64 继承、动画、无控制台入口与 dashboard 拖窗（Codex）

- 用户最终明确 dashboard 不显示 tab 栏，NEOVIM 大字上方整片空白可拖；当前源码 `73dcbd176f7ff769a04ca9ee3c31077129a0b94d`／配置 `3d55c9faebd7f705962778c628457ec4493c045e` 按实际 Snacks Header extmark 与窗口 screenpos 每次点击计算范围，resize 后随标题更新；标题／正文／浮窗／已有自定义鼠标映射保留。普通编辑页面仍仅 buffer 标签右侧、右侧组件左侧填充区可拖。保留 v1 首行协议，新增 v2 dashboard 明确表面与真实 root 行列、同次按下／物理行／时效校验；旧前端安全回退首行。曾强显 tab 栏的方案已撤回。Mac release 定向 7/7、fmt、local／portable 各9场景通过；早先隐藏栏首行 Windows GUI 通过仅属旧范围，新版多高度 Windows GUI 按用户“不用检查了”跳过，未冒记通过。`target/glow-windows-dashboard-drag-20261022/expanded/`。
- 同一冻结源码的 x64／ARM64 两个 release 均 cargo exit0、输出关闭、自有进程退出。x64 36,213,248 字节、SHA256 `cd324f69a5544dea8b8b58f42f64fdb030321cefdca5fc762996f0dfb1a1cebc`；ARM64 34,073,088 字节、SHA256 `cf142827c040017b79b5bb894c9a6fea84557ea65b179082cc3d3a04a58eb1b1`；复用各自已核对的缓存与 Skia，不升级依赖／工具链。`target/glow-windows-dashboard-region-20261022/build/{x64,arm64}/receipt.json`。
- Windows 单文件配置已原 SHA 守卫／原字节备份部署。x64 桌面及 nvidec 指针切至 `DashboardRegion20261022X64/HardwareOpenGLApp`，保留原 runtime／profile 与 shell 其余内容；ARM64 将新前端并排放为原入口目录的 `neovide-dashboard-region.exe`，只更新 PS 的 frontend 选择行，既有 native GUI launcher／图标／Matrix／XDG 均保留。两端下一次启动生效，未关闭／重启已有用户窗口，未自动打开新版。构建与明确跳过验收授权绑定在 `target/glow-windows-dashboard-region-20261022/deployment/{deployment-authority.json,deployment.json}`；回滚字节保留。未发布新包，Mac 已安装 App 未替换；所有本轮自有工作已结束，无 standby／自动唤醒。
- 原 ARM64 启动错误确认包含缺失 `cmatrix-gm`；三个真实前端当时均可见，version 与脚本语法正常，未据此声称复现硬崩溃。已用项目改过的 Glow Gomatrix 同源编译原生 ARM64，PE 0xaa64、仅 KERNEL32.dll、SHA `cf19d7c6fe28f6b1e153c9abfde59d50676ee7a1a042958790d30ad2c40120cf`；intro／PowerShell dashboard 两个实际 ARM64 Neovim ConPTY 动画 exit0并输出 Unicode 雨。桌面无参数保留动画，带文件／目录或显式 skip 时直入编辑；仅新子进程加入单工具目录。源码 `52600ca` 补 Matrix 双架构构建参数，`ff156d38`／`d723003` 在依赖缺失或明确 skip 时安全跳过。`target/glow-windows-arm64-startup-fix-20261022/result.json` 绑定有效结果及早期探针失败；未把失败探针写成产品失败／GUI通过。
- 继承核对已补 ARM 缺失的 Windows 0.6 缩放、zh_CN.UTF-8 语言偏好及前端同一图标；三个旧 ARM 用户窗口曾仅热设缩放，字体名／h16不变，退出前均为0.6。zsh 首选原已相同，字体／主题／快捷键／材质共用 home 配置，位置尺寸共用系统保存文件；公共 Zoom 默认、RGB、Mac 缩放未改。ARM 原生 Fzf／Avante、Mason／rplugin／Notebook 等依赖仍未完整准备，不把 x64 DLL 复制过去或声明两版插件完全等价；本轮科学环境迁移不自动等同 Notebook provider 配置完成。`inheritance-audit.json`／`scale-alignment.json` 保存范围。
- 桌面图标先出现再消失的本机原因是旧 PowerShell 控制台先显示约970ms，再隐藏，之后前端显示；原主窗口观测内未 hide/show 循环。`06f5842` 新增极小原生 ARM64 GUI launcher，以 CREATE_NO_WINDOW 调用同目录 PS；7个参数／中文工作目录／无 console 检查通过，新私有配置对照0个控制台窗口事件、主窗口仅一次 SHOW。桌面 lnk 已备份切换，保留图标与起始目录；前端后续更新不改变该 launcher。`target/glow-windows-native-launcher-20261022/result.json`。未录任务栏像素视频，不宣称启动性能提高；旧对照曾用正常配置自建窗，清理前未查 modified，这一限制留在收据，新对照已改私有配置。

### 2026-10-22 Windows 软件 ARM64 替换与科学环境重建（Codex）

- 用户明确授权替换及重建环境后，由原生子代理并行完成 Teams、foobar2000、Git 和 Conda；root 负责 7-Zip／ImageMagick 及唯一全局 PATH 整合。Teams 已为 26260.1717.5229.7049 ARM64、注册状态 Ok；foobar2000 2.26.1 ARM64EC 已安装并新增独立桌面入口。foobar 旧 v1 私有配置仅在同用户 Windows 本地原字节复制，未解析／导出；正式 v1→v2 导入要等首次用户启动，旧 Store 版保留回退。未启动播放或用户 GUI，`target/glow-windows-arm64-gui-apps-20261022/receipt.json`。
- Git 保持 2.55.0.windows.5，同版官方 ARM64 安装 exit0，cmd 入口及 clangarm64 核心均 PE 0xaa64；独立空仓库 init/add/write-tree/status 通过，1717 个用户 shell／插件文件 SHA、安装选项／组件保全通过，系统 gitconfig 只由官方安装器调整内置路径，原字节备份保留。zsh 5.9／MSYS 仍是官方 x64 设计，Glow 双入口、y/tree/btop 函数及 frame none 保持；非 Git PATH 段及 ExpandString 类型保持。`target/glow-windows-git-arm64-migrate-20261022/{receipt.json,verification.json,path-after-git.json}`。
- 7-Zip 26.05 ARM64、ImageMagick 7.1.2-34 Q16-HDRI ARM64 均已安装 exit0，官方发布 SHA 校验通过（ImageMagick 签名有效，7-Zip 官方包未签名）。ARM64 归档／解包中文空格文件哈希一致，ImageMagick 格式枚举、中文 PNG、无损 WebP 及尺寸检查通过；旧 x64 ImageMagick 已由精确官方卸载器 exit0 移除。安装器及回滚字节保留，`target/glow-windows-native-apps-20261022/receipt.json`。
- 新 Miniconda ARM64 26.9.3 位于 Windows 用户的 miniconda3-arm64，science 环境为 Python 3.14.8；248 个包中 239 个 win-arm64、9 个 noarch，无 win-64。11 个主要模块真实导入、7 项小计算／绘图及 Python／NumPy／SciPy／Pandas／pyzmq PE 检查通过，旧 Anaconda 2026.07-1 精确卸载 exit0、旧 Python／登记／根残余清零，新两份 Python 保留；未改共享配置或 Glow 私有 Python。Spyder／Navigator 等旧完整发行版 GUI 未重建。`target/glow-windows-conda-arm64-migrate-20261022/{verification.json,path-boundary.json,uninstall-receipt.json}`。
- root 等各官方 PATH 写入事务结束后再统一切换：旧 Anaconda 段清除，ImageMagick 指向新根；用户 PATH 按 science 根／Library/bin／Scripts、Miniconda Scripts／condabin 排序，Python／Jupyter 优先 science，Git zsh 裸 conda 也可找到原生入口。Machine／User 原注册类型及其余段保留、原字节备份，实际登录用户已广播环境变化；六个默认命令及 zsh conda 解析检查通过。已知 VS Code 用户设置及所查 shell/profile 入口没有显式旧 Anaconda 引用，未改写它们。新开终端生效；PATH 不等于激活环境，包管理用 `conda install -n science ...` 或先激活。软件事务自有进程均已退出，无重启／常驻任务；不将本节安装／CLI 检查写成 GUI／性能验收。

### 2026-10-22 首次终端选择、Windows 命令与软件架构审计（Codex）

- 按用户明确要求，交给三个独立子代理完成交互终端、命令工具和软件架构审计；三项均已结束，未启动用户 GUI、真实交互 shell、性能测试或常驻任务。
- local 配置 `3e1a91027151046097a5b96d451300388378a627`、portable `cf829e6decaadcf7be3e28ea568e72a7224bcd3f` 新增中央交互 shell 首选：首次手动打开终端选择本机实际可用 shell，取消不启动，选择保存在 `stdpath(state)/preferences/terminal-shell.json`；`:GlowTerminalShell` 可更改，已存在的终端进程继续 toggle。Ctrl+T／Ctrl+/／Ctrl+_ 及 leader ft/fT 统一使用该选择，Windows 非交互 PowerShell 与 flags 保留。Windows x64／ARM64 两份现有 state 已预设 zsh，五文件按旧 SHA 守卫及原字节备份部署，下次启动生效；`target/glow-terminal-shell-choice-20261022/{receipt.json,deployment.json}`。local／portable 隔离选择、取消、持久化、失效重选及路由检查通过，Windows 原生 headless 只查候选与转义，未启动 shell；Linux 真实终端未验。既有 chadrc 改动未触碰。
- Mac 的 tree／btop 是 Homebrew 独立安装的软件，zsh 不包含它们。Windows 旧 Chocolatey tree 1.5.2.2 实际可运行但中文乱码，现已并排补 MSYS2 tree 2.3.2；btop 命令使用同作者普通 btop4win 1.0.5，不安装 LHM／管理员驱动。两者目前均为 x64；版本／帮助及 tree 中文空格／层级／JSON 检查通过，btop 未做交互界面验收，普通版不含 GPU／CPU 温度监测。新 `tools.zsh` 只对无自定义 alias/function 的 tree 精准路由，原程序、PATH、四份启动／主题文件及 x64／ARM64 Glow 入口保留；重开 Git zsh 或 source windows.zsh 生效。`target/glow-windows-shell-tools-20261022/receipt.json` 保存官方来源、包 SHA 和原字节备份。
- 软件架构只读审计覆盖 134 条登记、172 个 MSIX、54 个明确 EXE，未递归扫描磁盘或替换软件。优先可换 ARM64：7-Zip、Teams、Git 核心；ImageMagick 可保留 Q16-HDRI 规格迁移，foobar2000 可选 ARM64EC 但需核对旧 x86 插件。完整 Anaconda 暂无 ARM64，Miniconda ARM64 属于环境迁移。VS Code／系统 nvim／Terminal／Edge 等已是 ARM64；SDK 证实 Word／Excel／Apple Music 为 ARM64EC，不误列普通 x64。Git 的 MSYS／Bash／zsh 仍为 x64；WezTerm、iTunes、爱思、TinyTeX、构建工具和各架构运行库不因本审计删除。完整版本、架构、官方来源、建议及覆盖限制见 `target/glow-windows-software-arch-20261022/audit.md`，原始证据由 receipt 绑定。

### 2026-10-22 Windows 实时缩放、终端入口与双架构（Codex）

- 用户截图中的右侧／下方空白在隔离原生输入中复现：旧 Capsule110 连续六次拉宽时，Neovim 始终停留在 70 列，松手后才更新。`1dbe6589de1296269d82518090718e02c116c7c0` 在 Windows 原生 sizing 期间由 `RedrawRequested` 准备网格、处理异步绘制并呈现，不再等待被系统缩放循环阻塞的 `AboutToWait`；普通移动和 Mac／Linux 沿用原调度，无新增 timer。
- x64／ARM64 release 均以同一源码编译完成、cargo exit0。x64 EXE 36,210,688 字节，SHA256 `63f1c0da363626467e1409f7813faed50192ba6e2bbf1ce75e299547c4f23a24`；`target/glow-windows-live-resize113-20261022/build/receipt.json`。ARM64 EXE 34,071,552 字节，PE 0xaa64，SHA256 `163b5ca8d5157612e85d332e2d35fa3101d0b3511b62951a9479236172a16bc2`；独立缓存及匹配的官方 Skia 0.153.3，新增 Rust ARM64 标准库、既有工具不升级，`target/glow-windows-arm64-20261022/build/receipt.json`。编译进程均已退出；后续单独授权已配置 ARM64 入口，仍未启动程序，见下条。
- 用户睡前明确要求两架构编译完即结束、不再验证；未将本轮写为 GUI 验收通过。早期 112 候选新增 `GetWindowSubclass` 导入，因缺少 Comctl32 v6 manifest 在启动前退出（0xC0000139）；已撤掉该导入，改为 UI 线程内按 HWND 追踪／销毁清理。113 的隔离探针在 fresh 工作目录前置检查即退出，尚未启动前端或发送输入；按用户要求不再重试。原失败材料及 `acceptance-deferred.json` 保留，旧 shared Mac 38 项结果只复用于未变的共享路径。
- 按用户跳过验收要求，将 x64 修复版并排放入 `C:\\GlowDev\\GraphicsQA\\LiveResize113Hardware20261022`，桌面和终端设备指针均改为下次启动使用，旧入口／原字节备份保留；未启动、重启或关闭用户编辑器，未改窗口保存尺寸／配置／主题。`target/glow-windows-live-resize113-20261022/{deployment-authority.json,deployment.json}` 明确记录 GUI／launcher 检查跳过，不沿用旧版通过状态。
- 用户继续授权独立 ARM64 入口后，已将同 SHA 前端放入 `C:\\GlowDev\\GraphicsQA\\LiveResize113ARM64`，新增桌面 `Glow ARM64` 及 Git zsh 命令 `nvidec-arm64`。使用系统 ARM64 Neovim、`--opengl --frame none`、同一份 home 配置与既有独立 nvim-arm64 数据；新进程清除继承的旧 x64 runtime 指向，不加载其 WindowsInit／原生模块。默认 `nvidec`／旧桌面仍为 x64，四份 shell 启动／主题文件不变，重开 zsh 后新增命令生效；仅创建入口未启动程序，`target/glow-windows-arm64-entry-20261022/deployment.json`。
- Windows `nvidec` 默认传 `--opengl --frame none`，直接调用包内 `Glow.exe`，修正旧硬件包装器固定工作目录导致的路径问题；重开 Git zsh 后 `nvidec .` 生效。独立配置仓库提交 `6897e3412a6521eaeea91e5a9405f3224c29b8a2`，只改三份 shell/zsh-port 源文件；用户收敛前已完成原生 stub 的 cwd／中文空格参数／退出码检查，四份 shell 启动／主题文件未改。证据 `target/glow-windows-nvidec-entry-20261022/receipt.json`；随后只换设备指针到 113，未再次启动检查。
- 系统独立 Neovim 0.12.6 ARM64 已通过官方 MSI 安装至 `C:\\Program Files\\Neovim`，machine PATH 仅追加其 bin；旧 PATH 及旧 AppData init 原字节均备份。`%LOCALAPPDATA%\\nvim\\init.lua` 桥接到 `C:\\Users\\ysrae1\\.config\\nvim`，仅进程内调整 XDG，data／state／cache 使用独立 nvim-arm64 树，不改 Glow profile 或旧插件数据。用户收敛前的一次实际配置 headless 检查已结束，中文路径／70 个插件 Lua／架构及 config 路径正确；未复制 x64 原生模块，FFF／Avante 等 ARM64 native 功能不作通过声明。证据 `target/glow-windows-system-nvim-20261022/{installation.json,config-deployment.json,actual-config-candidate2.json}`；重开终端可用 `nvim`。
- 按用户给出的 Zsh-art/logo 替换 Windows Terminal 的 zsh profile 图标：固定官方提交 `17617f2f6c70c65943a48745c91d997e7561f19d` 的原始 256×256 PNG，未改颜色／比例；图标 SHA256 `3406c2e69b6bed1252c519f950d314ff445b1ddb87317dc5d9fbdc9bea2d1427`。只改 GUID `{2ece5bfe-50ed-5f3a-ab87-5cd4baafed2b}` 的 icon，JSON 格式与其余字段保持，原字节备份及 CC BY-SA 4.0 归属／许可保留；未重启或打开终端，`target/glow-windows-zsh-icon-20261022/receipt.json`。
- 后续 Windows 发布须同时提供 x64、ARM64；本轮仅两架构前端编译，不重封旧 Core 安装器、不发布新资产，Mac 已安装 App 不变。各平台性能优化明确留待下一阶段，NeoTree 分段计时探针只准备未运行；不调材质／刷新率。本轮编译、部署及配置事务均已结束，无自有后台工作、standby 或自动唤醒。

### 2026-10-22 Windows 小窗与无边框缩放修复（用户验收反馈，Codex）

- 用户继续指出透明底栏的胶囊圆角消失；前项只验 blend／linegrid，漏验端帽像素。`2f6710c8e5314ff9141abf40a1502794769ada34` 修正已有 `solid_title_cap` 的原生语义：三端均让显式端帽前景保持主体不透明度，端帽外侧背景继续沿原 blend，不再仅限 Mac Liquid Glass。4 项 release 定向像素／层序测试通过，含浅深底色、blend80／15、global opacity1／.8、角色有无、两端主体一致及抗锯齿；Windows x64 release exit0，EXE SHA256 `f177dfea8c0515d0b82581c1d0055b4ba3e921760c75161d7668778a7e27fe13`。独立 Windows 硬件 OpenGL 的深浅截图已实际查看，固定 NvChad 底栏与角色胶囊均恢复圆角、未标记对照保留普通路径，测试自有进程清零；证据 `target/glow-windows-capsule-fix-20261022/{mac-unit.json,build/receipt.json,native-acceptance.json,gui1/}`。用户保存关闭后，桌面入口并排切至 `Capsule110Hardware20261022` 并打开新版，launcher exit0、实际 SHA／四边命中正确，保存尺寸 2083×1338 保留；实际用户窗口底栏截图 `actual-user-footer.png` 已确认圆角恢复及下方余量透明。只改前端，当前用户配置／主题未再改写，Mac 已安装 App 未替换，未重做无关媒体／实体输入，未重封旧 Core 资产，无常驻监控。
- 用户随后确认缩放／拖窗可用，并要求底部 NORMAL 状态栏背景与其下方区域透明度同 NeoTree。配置 `transparency.lua` 只将 Windows 底栏的显式 blend 改为当前面板材质，并启用既有 `bottom_margin_opacity`；保留 RGB、文字与胶囊主体。local 验证后同步 portable，再以旧 SHA 守卫／原始字节备份部署 Windows 单文件；无需重编 EXE。`tests/media/windows_statusline_material.py` 的真实 NvChad linegrid local／portable 各 5 场景通过，Windows 深浅各 82 格底材与 NeoTree 相同、38 格胶囊保持实心，Mac／terminal 策略不变；既有 Windows material 切主题／用户覆盖检查通过。实际当前用户窗口已通过 RPC 刷新，NeoTree／底栏 blend 均 80、底部余量 alpha 0.20，cmdheight0，内容／modified／光标／当前窗口／字体缩放与主题色前后相同，未发合成输入或重启；`target/glow-windows-footer-material-20261022/{deployment.json,live-acceptance.json}`。画面观感继续由用户确认，未以参数检查宣称像素一致。
- 实际旧窗口为 500×500／192 DPI，启动参数 `--frame none`，已有 `WS_THICKFRAME`，用户持久化尺寸原为 null。`0093eceafefa4efbea3130ee691d79b7e39db01a` 将缺少保存尺寸时的 fallback 改为 100×50 网格，由真实字体／DPI 换算；显式 size／grid／maximized 和保存像素尺寸仍保留。Windows 无边框窗口增加八方向原生 `WM_NCHITTEST`，只覆盖系统 DPI 缩放边带，内部仍交给原 Winit；最大化、全屏／禁止缩放和已有鼠标 capture 不覆盖。
- Mac 实际 release 定向测试 34＋4 项通过，含默认尺寸／显式覆盖及八方向几何，格式检查通过；Windows x64 release exit0／输出关闭，EXE 36,205,568 字节，SHA256 `bb0bc93c9f16ed7014adb64ca056c6391d65c58f081896829cd0dd6025c1e15a`。证据根 `target/glow-windows-window-fix-20261022/`，`mac-unit.json`、`build/receipt.json`。Mac 已安装 App 未替换，Linux 原生 GUI 未测。
- 登录用户独立新 profile 实测：无显式 size／grid 的默认窗口 1576×1600、100×50／192 DPI；八方向系统缩放光标、右边＋80／下边＋60 像素原生缩放、顶部空白区＋60×30 拖窗、标签切换和编辑点击通过。最大化首次探针对包含不可见边框的 outer 直接查询而失败，原材料保留；只补可点击 client／monitor workarea 交集的八方向及 restore 通过。两次均只操作隔离自建窗口，自有 PID／按住状态清零；统一 `resize/native-acceptance.json` 明确绑定两个原始收据，不追认首次错误断言。
- 用户保存并关闭旧窗口后，其退出实际写回 500×500；已保存原始字节备份，只清除此已报告的小尺寸记录，位置保留，`size-migration.json`。桌面原入口并排切至 `C:\GlowDev\GraphicsQA\WindowFix108Hardware20261022`，旧程序／快捷方式备份保留，launcher 检查 exit0；`deployment.json`。已通过该入口为用户打开新版，实际用户 profile 的可见窗口为 1576×1600，四边命中正确、EXE SHA 相同，仅作只读查询，留给用户验收；`actual-user-startup.json`。未向用户窗口发送鼠标／键盘输入。
- 实体鼠标、首帧与新 EXE 的 PDF 像素不作通过声明；PDF 源码未变。现有未发布 Core preview1 包仍含旧 96 前端，后续封包必须采用新版本号及本修复，不覆盖旧冻结资产；终端硬编码 PdfNav92 入口也未在本次桌面修复中改写。构建／隔离测试均已结束，无 standby 或自动唤醒，只有已打开供用户验收的正常编辑器继续运行。

### 2026-10-22 Windows 恢复与收敛（Codex）

本节证据根：`target/glow-windows-20261022/`。该恢复阶段未修改产品源码；已保存原失败与中间状态，由下列最终收据限定通过范围。

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
