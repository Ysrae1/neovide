#requires -Version 5.1
# UI-only localization. Backend report keys, paths and technical errors stay intact.
function Resolve-SetupLanguage {
    param([ValidateSet('auto','en','zh-CN')][string]$Language='auto',
        [Globalization.CultureInfo]$Culture=[Globalization.CultureInfo]::CurrentUICulture)
    if ($Language -ne 'auto') { return $Language }
    if ($Culture.TwoLetterISOLanguageName -eq 'zh') { return 'zh-CN' }
    return 'en'
}
$script:SetupChinese=@{
    'Connecting to TeX source: {0}'='正在连接 TeX 软件源：{0}'
    'Selected TeX source: {0}'='已选择 TeX 软件源：{0}'
    'TeX download source'='TeX 软件源'
    'TeX download source: {0}'='TeX 软件源：{0}'
    'Automatic'='自动'
    'Tsinghua University'='清华大学'
    'USTC'='中国科大'
    'Illinois'='Illinois'
    'Automatic tries Chinese mirrors first on Chinese Windows and Illinois first on other systems. The source is checked only when installing LaTeX; system settings are unchanged.'='自动模式在中文 Windows 上优先尝试国内镜像，其余系统优先尝试 Illinois。仅安装 LaTeX 时检查软件源，不改动系统设置。'

    'Stop setup'='停止设置'
    'Finish later'='稍后完成'
    'Finish'='完成'
    'Install selected'='安装所选依赖'
    'Check again'='重新检查'
    'Open logs'='打开日志'
    'Neovide Glow — First steps'='Neovide Glow — 首次设置'
    'Notebook / Python'='Notebook / Python'
    'LaTeX / Chinese PDF'='LaTeX / 中文 PDF'
    'Detected dependencies and download plan'='检测结果与下载计划'
    "The editor is installed. Choose the features you need; setup checks this PC before downloading anything.`r`nYour configuration, Python/Conda environments and system PATH are preserved."="编辑器已安装。请选择需要的功能；向导会先检查本机，再下载缺少的依赖。`r`n现有配置、Python/Conda 环境和系统 PATH 均会保留。"
    'Preparing selected dependencies...'='正在准备所选依赖……'
    'Checking existing tools. This may take a few minutes...'='正在检查本机已有工具，可能需要几分钟……'
    'The setup worker could not start.'='无法启动设置进程。'
    'Setup could not start. Check the message below and try again.'='无法启动设置。请查看下方错误信息后重试。'
    'Review what will be reused or downloaded:'='请确认将复用或下载的依赖：'
    'Known official downloads: {0} MiB.'='已知官方来源下载量：{0} MiB。'
    'Download size is not installed disk space. Compatible tools are reused; existing environments are preserved.'='下载量不代表安装后的磁盘占用。向导会复用兼容工具，并保留已有环境。'
    'Install changes only selected dependencies. Finish later keeps the editor usable; optional features may be unavailable.'='安装仅处理所选依赖。选择“稍后完成”后仍可使用编辑器，部分可选功能可能暂不可用。'
    'Some checks were inconclusive. Open logs and resolve them before installing.'='部分检测未能得出结论。请打开日志，处理后再安装。'
    'Detection complete. Review the plan, then choose Install or Finish later.'='检测完成。请确认下载计划，然后选择“安装所选依赖”或“稍后完成”。'
    'This setup run exceeded its time budget. Logs and partial downloads are preserved. Check again to resume.'='本次设置已超时。日志和已下载的部分文件均已保留，请重新检查后继续。'
    'Output pipe did not close; use the setup report and phase logs.'='输出通道未关闭，请查看设置报告与阶段日志。'
    'Error pipe did not close; use the setup report and phase logs.'='错误输出通道未关闭，请查看设置报告与阶段日志。'
    'Setup did not produce a read-only detection report.'='设置进程未生成有效的只读检测报告。'
    'Setup exited without a passed dependency receipt. Open logs before retrying.'='设置进程已退出，但未生成依赖通过记录。请打开日志后再重试。'
    'Selected dependencies passed. Reopen Glow to use them.'='所选依赖已通过检查。重新打开 Glow 即可使用。'
    "Next: launch Neovide Glow from Start. On first launch, choose your existing compatible Windows configuration or the separate defaults.`r`n`r`nOpen a .ipynb file for Notebook or a .tex file for LaTeX. AI accounts and project compilers are configured separately.`r`n`r`nTo review or repair dependencies later, use the Neovide Glow Setup shortcut."="下一步：从开始菜单启动 Neovide Glow。首次启动时，可选择已有的兼容 Windows 配置，或使用独立的默认配置。`r`n`r`n打开 .ipynb 文件可使用 Notebook，打开 .tex 文件可使用 LaTeX。AI 账户和项目编译器需另外配置。`r`n`r`n以后可通过开始菜单中的 Setup 快捷方式检查或修复依赖。"
    'Setup did not finish. Your editor and existing environments are preserved.'='设置未完成。编辑器和已有环境均已保留。'
    'Technical details:'='技术错误信息（保留原文）：'
    'Open logs for the failed phase. Check again to detect completed work, then Install selected to resume owned partial downloads. You can also finish later and reopen Neovide Glow Setup.'='请打开日志查看失败阶段。选择“重新检查”以识别已完成的步骤，再选择“安装所选依赖”可继续使用向导保留的下载。也可稍后通过开始菜单中的 Setup 快捷方式重新打开设置。'
    'Selection changed. Choose Check again to refresh the download plan.'='所选功能已改变。请选择“重新检查”以更新下载计划。'
    'Stop this setup run? Existing environments and partial downloads are preserved. Reopen Setup to continue.'='停止本次设置？已有环境和已下载的部分文件均会保留，可重新打开设置继续。'
    'Continue setup'='继续设置'
    'Existing compatible tool will be reused.'='将复用本机已有的兼容工具。'
    'Locked x64-compatible tool download; existing tools are preserved.'='下载固定版本的 x64 兼容工具；已有工具会保留。'
    'Verified cached download will be reused.'='将复用已校验的下载缓存。'
    'Microsoft bootstrapper; the device runtime is an additional provider download.'='先下载 Microsoft 安装引导程序；适用于本机的运行时由 Microsoft 另外下载。'
    'Runtime registration is unreadable; setup stops without installing a replacement.'='无法读取运行时注册信息；向导将停止，不会安装替代版本。'
    'Selected package provider determines the download size and may ask for installation approval.'='下载量由所选软件包提供方决定，安装时可能需要您确认。'
    'Complete existing Notebook environment will be reused.'='将复用本机已有的完整 Notebook 环境。'
    'An existing Python inspection is inconclusive; setup stops before downloading packages.'='已有 Python 环境的检测未能得出结论；向导会在下载软件包前停止。'
    'Packages go into a separate Glow environment; existing Python/Conda packages are preserved.'='软件包将安装到独立的 Glow 环境，已有 Python/Conda 软件包会保留。'
    'Packages go into a separate Glow environment; existing Python/Conda packages are preserved. The locked CPython 3.12 x64 installer is used when no compatible Python is found.'='软件包将安装到独立的 Glow 环境，已有 Python/Conda 软件包会保留。未找到兼容 Python 时，将使用固定版本的 CPython 3.12 x64 安装程序。'
    'Existing TeX is reused after Chinese XeLaTeX / latexmk / SyncTeX checks; a failed check can require separate TinyTeX.'='已有 TeX 通过中文 XeLaTeX、latexmk 和 SyncTeX 检查后会被复用；检查失败时可能需要安装独立的 TinyTeX。'
    'Install a separate owned TinyTeX; existing TeX directories are preserved.'='安装由 Glow 管理的独立 TinyTeX；已有 TeX 目录会保留。'
    'Known bytes exclude provider downloads and partial-file resume savings. Verified cached archives count as zero. Shared CLI fallbacks are locked x64 binaries, including on ARM64 Windows.'='已知下载量不含提供方的额外下载，也未扣除断点续传已完成的部分；已校验的缓存计为零。共用命令行备用工具采用固定的 x64 版本，ARM64 Windows 也使用这些兼容版本。'
    'WebView2 runtime: Microsoft determines device-specific download size.'='WebView2 运行时：适用于本机的下载量由 Microsoft 决定。'
    'Notebook wheels and text converter: pip resolves the package download size for the selected Python architecture.'='Notebook 软件包与文本转换器：pip 根据所选 Python 架构确定下载量。'
    'TeX packages: additional selected packages are downloaded by TeX Live; size is determined by its repository.'='TeX 软件包：所选的额外软件包由 TeX Live 下载，下载量取决于其软件源。'
    'Checking existing tools and Notebook environments; no downloads have started.'='正在检查已有工具和 Notebook 环境，尚未开始下载。'
    'Selected dependencies passed. Open Glow from its shortcut to use them.'='所选依赖已通过检查。请从快捷方式启动 Glow 使用。'
    'Setup stopped. Logs and owned partial downloads are preserved. Retry the same feature selection to continue; move aside a reported corrupt cache file before retrying.'='设置已停止。日志和向导管理的未完成下载均已保留。保留原来的功能选择可继续；若日志报告缓存损坏，请先移走该损坏文件再重试。'
    'Python package size is resolved by pip.'='Python 软件包的下载量由 pip 确定。'
    'Preparing verified TinyTeX for installation.'='正在准备已校验的 TinyTeX 安装文件。'
    'Checking official TinyTeX archive size and SHA256.'='正在检查 TinyTeX 官方安装文件的大小与 SHA256。'
}
function Get-SetupText([string]$Text) {
    if ($script:SetupLanguage -eq 'zh-CN' -and $script:SetupChinese.ContainsKey($Text)) { return $script:SetupChinese[$Text] }
    return $Text
}
function Get-SetupRole([string]$Role) {
    if ($script:SetupLanguage -ne 'zh-CN') { return $Role }
    $names=@{search='文本搜索 (ripgrep)';find='文件搜索 (fd)';yazi='文件管理器 (Yazi)';fzf='交互筛选 (fzf)';git='版本管理 (Git)';webview2='网页与 PDF 运行时 (WebView2)';notebook='Notebook / Python';latex='LaTeX / 中文 PDF';pdf='可选外部 PDF 阅读器 (SumatraPDF)';powershell='交互终端 (PowerShell)';node='JavaScript 运行时 (Node.js)';rg='ripgrep';python='Python'}
    if ($names.ContainsKey($Role)) { return $names[$Role] }
    return $Role
}
function Get-SetupPlanStatus([string]$Status) {
    if ($script:SetupLanguage -ne 'zh-CN') { return $Status }
    $names=@{reuse='复用已有环境';missing='需要安装';blocked='需先处理检测问题';check='需要验证'}
    if ($names.ContainsKey($Status)) { return $names[$Status] }
    return $Status
}
function Get-SetupPhase([string]$Phase) {
    if ($script:SetupLanguage -ne 'zh-CN') { return $Phase }
    $names=@{'select-tex-mirror'='连接 TeX 软件源';detection='检测';preparation='准备';download='下载';complete='完成';passed='通过';failed='失败';'extract-Git'='解压 Git';'install-CPython312'='安装 CPython 3.12';'prepare-Notebook-environment'='准备 Notebook 环境';'install-Notebook-packages'='安装 Notebook 软件包';'install-LaTeX-text-converter'='安装 LaTeX 文本转换器';'prepare-ACP-runtime'='准备 ACP 运行时';'refresh-TeX-font-cache'='更新 TeX 字体缓存';'probe-existing-LaTeX'='验证已有 LaTeX';'probe-existing-SyncTeX'='验证已有 SyncTeX'}
    $texNames=@{
        'prepare-tinytex'='准备 TinyTeX 安装';'verify-tinytex-archive'='校验 TinyTeX 安装文件';'extract-official-archive'='解压 TinyTeX'
        'gpg-version'='检查签名验证工具';'tlcrypto-gpg-offline-preflight'='检查 TeX 签名验证环境'
        'option-desktop_integration'='配置 TeX 桌面集成';'option-fileassocs'='配置 TeX 文件关联';'option-multiuser'='配置 TeX 用户范围'
        'native-tar-temp-preflight'='检查 TeX 临时目录';'tlmgr-self-update'='联网更新 TeX 管理器并验证签名'
        'verify-self-update-complete'='联网检查 TeX 管理器更新是否完成';'fmtutil-version-before'='检查 TeX 格式工具版本'
        'update-texlive-scripts'='联网更新 TeX 脚本并验证签名';'fmtutil-version-after'='检查更新后的 TeX 格式工具'
        'verify-combined-format-selectors'='检查 TeX 格式生成参数';'install-common-packages'='联网安装 LaTeX 软件包并验证签名'
        'complete-missing-formats'='生成 TeX 格式文件';'xetex-local-font-configuration'='配置 XeTeX 字体';'xetex-user-font-cache'='更新 XeTeX 字体缓存'
        'xelatex-version'='检查 XeLaTeX';'latexmk-version'='检查 latexmk';'synctex-help'='检查 SyncTeX'
        'compile-latin-path'='验证中文 PDF 与 SyncTeX';'compile-unicode-path'='验证中文路径下的 PDF 与 SyncTeX';'installed-package-versions'='记录已安装的 TeX 软件包'
    }
    if ($texNames.ContainsKey($Phase)) { return $texNames[$Phase] }
    if ($names.ContainsKey($Phase)) { return $names[$Phase] }
    if ($Phase -match '^install-(.+)$') { return '安装 '+(Get-SetupRole $Matches[1]) }
    if ($Phase -match '^check-(.+)$') { return '检查 '+(Get-SetupRole $Matches[1]) }
    return $Phase
}
function Get-SetupDetail([string]$Detail) {
    if ($Detail -match '^(Checking|Selected) TeX mirror (auto|tuna|ustc|illinois): .+$') {
        $action=$Matches[1]; $mirrorName=@{auto='Automatic';tuna='Tsinghua University';ustc='USTC';illinois='Illinois'}[$Matches[2]]
        $template=if ($action -eq 'Checking') {'Connecting to TeX source: {0}'} else {'Selected TeX source: {0}'}
        return (Get-SetupText $template) -f (Get-SetupText $mirrorName)
    }
    if ($script:SetupLanguage -ne 'zh-CN') { return $Detail }
    if ($script:SetupChinese.ContainsKey($Detail)) { return $script:SetupChinese[$Detail] }
    if ($Detail -match '^(.+): package provider determines download size\.$') { return (Get-SetupRole $Matches[1])+'：下载量由软件包提供方决定。' }
    if ($Detail -match '^TeX fallback: a failed existing-TeX check may require the locked TinyTeX archive \(([0-9]+) bytes\)\.$') { return 'TeX 备用方案：若已有 TeX 检查失败，可能需要下载固定版本的 TinyTeX 压缩包（'+$Matches[1]+' 字节）。' }
    if ($Detail -match '^Running (.+)$') { return '正在执行：'+(Get-SetupPhase $Matches[1]) }
    if ($Detail -match '^Installing / checking: (.+)$') { return '正在安装或检查：'+(Get-SetupPhase $Matches[1]) }
    if ($Detail -match '^Setup log: (.+)$') { return '设置日志：'+$Matches[1] }
    if ($Detail -match '^Reusing verified download: (.+)$') { return '复用已校验的下载：'+$Matches[1] }
    if ($Detail -match '^Downloading (.+); retrying the same selection resumes retained partial bytes\.$') { return '正在下载 '+$Matches[1]+'；使用相同选择重试可继续已保留的部分下载。' }
    if ($Detail -match '^Downloading (.+)$') { return '正在下载 '+$Matches[1] }
    if ($Detail -match '^Verified (.+)$') { return '已校验 '+$Matches[1] }
    return $Detail # Unknown third-party details and filenames must remain diagnosable.
}
