#requires -Version 5.1
<# Native UI acceptance using a local synthetic backend. Opens only this test's
   setup window; never downloads software or touches user configuration. #>
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),[Parameter(Mandatory=$true)][string]$WorkRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:process=$null
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh wizard-test WorkRoot.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GlowWizardTestWindow {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
$utf8=[Text.UTF8Encoding]::new($false)
$fixture=Join-Path $WorkRoot 'fixture';$null=New-Item -ItemType Directory -Path $fixture
foreach($file in @('Setup-Wizard.ps1','Setup-Locale.ps1')) { Copy-Item -LiteralPath (Join-Path $SourceRoot ('portable\windows\'+$file)) -Destination $fixture }
$backend=@'
param([switch]$InstallBase,[switch]$InstallNotebook,[switch]$InstallLatex,[switch]$PlanOnly,[switch]$Json,[string]$StatusPath,[string]$ReportPath,[ValidateSet('auto','tuna','ustc','illinois')][string]$TeXMirror='auto')
$u=[Text.UTF8Encoding]::new($false)
$mode=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'mode.txt'))
[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'calls.txt'),("plan=$PlanOnly notebook=$InstallNotebook latex=$InstallLatex mirror=$TeXMirror"+[Environment]::NewLine),$u)
if($PlanOnly){
 $state=if($mode -eq 'blocked'){'blocked'}else{'reuse'}
 @{status='planned';selection_saved=$false;plan=@{items=@(@{role='search';status=$state;reuse_path='C:\fixture\rg.exe';download_bytes=0;download_note='Existing compatible tool will be reused.'});known_download_bytes=0;dynamic_downloads=@('Python package size is resolved by pip.')}}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
 exit 0
}
if($mode -eq 'slow'){
 @{state='running';phase='download';detail='Downloading fixture.zip; retrying the same selection resumes retained partial bytes.';downloaded_bytes=5;total_bytes=10;run_path=$PSScriptRoot}|ConvertTo-Json|Set-Content -LiteralPath $StatusPath -Encoding UTF8
 $deadline=[DateTime]::UtcNow.AddSeconds(25)
 while(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'resume.txt')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
}
$state=if($mode -eq 'failed'){'failed'}else{'passed'}
@{state=$state;phase=$state;detail='fixture phase';downloaded_bytes=10;total_bytes=10;run_path=$PSScriptRoot;error='fixture controlled failure'}|ConvertTo-Json|Set-Content -LiteralPath $StatusPath -Encoding UTF8
if($mode -eq 'failed'){[Console]::Error.WriteLine('fixture controlled failure; retained partial downloads');exit 7}
@{status='passed'}|ConvertTo-Json|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host 'synthetic installation output is deliberately not pure JSON'
exit 0
'@
[IO.File]::WriteAllText((Join-Path $fixture 'Setup-Dependencies.ps1'),$backend,$utf8)
$receipt=[ordered]@{state='running';checks=@();processes=@();downloads=$false;user_configuration_changed=$false}
function Save{[IO.File]::WriteAllText((Join-Path $WorkRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 6),$utf8)}
function Pass([string]$Name){$receipt.checks+=@($Name);Save}
function Quote([string]$Value){'"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}
function Start-Wizard([string]$Mode,[string]$Language='en',[string]$TeXMirror='auto'){
 $script:UiLanguage=$Language
 [IO.File]::WriteAllText((Join-Path $fixture 'mode.txt'),$Mode,$utf8)
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=Join-Path $PSHOME 'powershell.exe'
 $start.Arguments=(@('-STA','-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $fixture 'Setup-Wizard.ps1'),'-InstallNotebook','-Language',$Language,'-TeXMirror',$TeXMirror)|ForEach-Object{Quote $_}) -join ' '
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $script:process=[Diagnostics.Process]::new();$script:process.StartInfo=$start;$null=$script:process.Start()
 $script:stdout=$script:process.StandardOutput.ReadToEndAsync();$script:stderr=$script:process.StandardError.ReadToEndAsync()
 $receipt.processes+=@{pid=$script:process.Id;create_no_window=$true;use_shell_execute=$false};Save
 $script:window=$null
 Wait-For {
  $script:window=[Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty,$script:process.Id))
  $null -ne $script:window
 } 'setup window'
}
function Find-Control([string]$Name){
 $script:window.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,$Name))
}
function Wait-For([scriptblock]$Condition,[string]$Label){
 $deadline=[DateTime]::UtcNow.AddSeconds(30)
 do{
  if($script:process -and $script:process.HasExited){throw ('Wizard exited while waiting for '+$Label+': '+$script:stderr.GetAwaiter().GetResult())}
  if(& $Condition){return};Start-Sleep -Milliseconds 150
 }while([DateTime]::UtcNow -lt $deadline)
 throw ('Timed out waiting for '+$Label)
}
function Invoke-Control($Control){
 $pattern=$null
 if($Control.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)){
  ([Windows.Automation.InvokePattern]$pattern).Invoke();return
 }
 if($Control.Current.ClassName -notlike 'WindowsForms10.BUTTON*' -or $Control.Current.NativeWindowHandle -eq 0){throw 'Control has no supported button action.'}
 $result=[UIntPtr]::Zero
 if([GlowWizardTestWindow]::SendMessageTimeout([IntPtr]$Control.Current.NativeWindowHandle,0xF5,[UIntPtr]::Zero,[IntPtr]::Zero,2,2000,[ref]$result) -eq [IntPtr]::Zero){throw 'Test-owned button did not accept BM_CLICK.'}
}
function Click([string]$Name){
 $control=Find-Control $Name;if(-not $control -or -not $control.Current.IsEnabled){throw ('Control is unavailable: '+$Name)}
 Invoke-Control $control
}
function Install-Label { if($script:UiLanguage -eq 'zh-CN'){'安装所选依赖'}else{'Install selected'} }
function Plan-Ready{Wait-For { $c=Find-Control (Install-Label);$c -and $c.Current.IsEnabled } 'reviewable plan'}
function Get-ElementText($Element){
 # Classic WinForms/MSAA may expose the visible edit content through Name.
 $pattern=$null
 if($Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)){
  $value=([Windows.Automation.ValuePattern]$pattern).Current.Value
  if(-not [string]::IsNullOrWhiteSpace($value)){return $value}
 }
 $pattern=$null
 if($Element.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern,[ref]$pattern)){
  $value=([Windows.Automation.TextPattern]$pattern).DocumentRange.GetText(-1)
  if(-not [string]::IsNullOrWhiteSpace($value)){return $value}
 }
 if($Element.Current.ClassName -like 'WindowsForms10.EDIT*'){return $Element.Current.Name}
}
function Plan-Text {
 $name=if($script:UiLanguage -eq 'zh-CN'){'检测结果与下载计划'}else{'Detected dependencies and download plan'}
 $nodes=$script:window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
 foreach($node in $nodes){
  $info=$node.Current
  if($info.IsOffscreen){continue}
  if($info.Name -ne $name -and $info.ControlType -ne [Windows.Automation.ControlType]::Edit -and
     $info.ControlType -ne [Windows.Automation.ControlType]::Document -and $info.ClassName -notlike 'WindowsForms10.EDIT*'){continue}
  $value=Get-ElementText $node
  if(-not [string]::IsNullOrWhiteSpace($value) -and $value -ne $name){return $value}
 }
 throw 'No visible setup details were exposed by the test window.'
}
function Close-Wizard([int]$Expected){
 $name=if($script:UiLanguage -eq 'zh-CN'){if($Expected -eq 0){'完成'}else{'稍后完成'}}else{if($Expected -eq 0){'Finish'}else{'Finish later'}};Click $name
 if(-not $script:process.WaitForExit(10000)){throw 'Wizard did not close.'}
 if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($script:stdout,$script:stderr),2000)){throw 'Wizard output did not drain.'}
 [IO.File]::WriteAllText((Join-Path $WorkRoot ('wizard-'+$receipt.processes.Count+'.stderr.log')),$script:stderr.GetAwaiter().GetResult(),$utf8)
 if($script:process.ExitCode -ne $Expected){throw ('Wizard exit '+$script:process.ExitCode+'; expected '+$Expected)}
 $script:process.Dispose();$script:process=$null
}
try{
 Save
 . (Join-Path $fixture 'Setup-Locale.ps1')
 if((Resolve-SetupLanguage auto ([Globalization.CultureInfo]::GetCultureInfo('zh-TW'))) -ne 'zh-CN'){throw 'Chinese culture did not select Chinese.'}
 if((Resolve-SetupLanguage auto ([Globalization.CultureInfo]::GetCultureInfo('en-US'))) -ne 'en'){throw 'English culture did not select English.'}
 if((Resolve-SetupLanguage en ([Globalization.CultureInfo]::GetCultureInfo('zh-CN'))) -ne 'en'){throw 'Explicit English override was ignored.'}
 $script:SetupLanguage='zh-CN'
 if((Get-SetupDetail 'TeX fallback: a failed existing-TeX check may require the locked TinyTeX archive (123 bytes).') -notmatch '123 字节'){throw 'Dynamic TeX download note was not translated.'}
 if((Get-SetupDetail 'pdf: package provider determines download size.') -notmatch '下载量由软件包提供方决定'){throw 'Provider download note was not translated.'}
 if((Get-SetupDetail 'Installing / checking: prepare-Notebook-environment') -notmatch '准备 Notebook 环境'){throw 'Worker phase was not translated.'}
 if((Get-SetupDetail 'fixture technical detail') -cne 'fixture technical detail'){throw 'Unknown technical detail was rewritten.'}
 if((Get-SetupPhase 'select-tex-mirror') -ne '连接 TeX 软件源'){throw 'TeX mirror phase was not translated.'}
 Pass 'language selection and dynamic status templates preserve technical values'
 Start-Wizard 'success';Plan-Ready
 $calls=[IO.File]::ReadAllText((Join-Path $fixture 'calls.txt'))
 if($calls -match 'plan=False'){throw 'Detection installed software before confirmation.'}
 Pass 'first page detects without applying changes'
 $choice=Find-Control 'LaTeX / Chinese PDF'
 $toggle=$null
 if($choice.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern,[ref]$toggle)){([Windows.Automation.TogglePattern]$toggle).Toggle()}else{Invoke-Control $choice}
 Wait-For {-not (Find-Control 'Install selected').Current.IsEnabled} 'invalidated stale plan'
 Click 'Check again';Plan-Ready
 Click 'Install selected';Wait-For {$null -ne (Find-Control 'Finish')} 'passed installation next steps'
 Close-Wizard 0;Pass 'selection refresh and explicit install show next steps and return success'
 Start-Wizard 'success';Plan-Ready;Close-Wizard 2;Pass 'finish later returns deferred instead of acceptance'
 Start-Wizard 'failed';Plan-Ready;Click 'Install selected'
 Wait-For {$null -ne (Find-Control 'Setup did not finish. Your editor and existing environments are preserved.')} 'failure recovery'
 if((Find-Control 'Install selected').Current.IsEnabled){throw 'Failed setup offered an obsolete install plan.'}
 [IO.File]::WriteAllText((Join-Path $fixture 'mode.txt'),'success',$utf8)
 Click 'Check again';Plan-Ready;Click 'Install selected';Wait-For {$null -ne (Find-Control 'Finish')} 'recovered setup'
 Close-Wizard 0;Pass 'controlled failure retains logs and requires a fresh plan before retry'
 Start-Wizard 'blocked'
 Wait-For {$null -ne (Find-Control 'Some checks were inconclusive. Open logs and resolve them before installing.')} 'inconclusive detection'
 if((Find-Control 'Install selected').Current.IsEnabled){throw 'An inconclusive detection allowed installation.'}
 Close-Wizard 2;Pass 'inconclusive detection blocks installation without touching the environment'
 Start-Wizard 'success' 'zh-CN' 'ustc';Plan-Ready
 if([IO.File]::ReadAllText((Join-Path $fixture 'calls.txt')) -notmatch 'plan=True notebook=True latex=False mirror=ustc'){throw 'Wizard did not pass the mirror selection during read-only detection.'}
 $plan=Plan-Text
 foreach($text in @('文本搜索 (ripgrep)','复用已有环境','将复用本机已有的兼容工具。','已知官方来源下载量：','Python 软件包的下载量由 pip 确定。','C:\fixture\rg.exe')) {
  if(-not $plan.Contains($text)){throw ('Chinese plan is missing: '+$text)}
 }
 Click '安装所选依赖';Wait-For {$null -ne (Find-Control '完成')} 'Chinese installation next steps'
 if((Plan-Text) -notmatch '下一步：'){throw 'Chinese next steps were not shown.'}
 Close-Wizard 0;Pass 'Chinese controls plan notes and successful next steps are localized'
 Start-Wizard 'failed' 'zh-CN';Plan-Ready;Click '安装所选依赖'
 Wait-For {$null -ne (Find-Control '设置未完成。编辑器和已有环境均已保留。')} 'Chinese failure recovery'
 $failure=Plan-Text
 if(-not $failure.Contains('技术错误信息（保留原文）：') -or -not $failure.Contains('fixture controlled failure')){throw 'Chinese failure lost its localized context or raw error.'}
 Close-Wizard 1;Pass 'Chinese failure retains technical error and recovery guidance'
 Start-Wizard 'blocked' 'zh-CN'
 Wait-For {$null -ne (Find-Control '部分检测未能得出结论。请打开日志，处理后再安装。')} 'Chinese blocked plan'
 if((Find-Control '安装所选依赖').Current.IsEnabled){throw 'Chinese blocked plan allowed installation.'}
 Close-Wizard 2;Pass 'Chinese blocked plan stays deferred'
 Start-Wizard 'slow' 'zh-CN';Plan-Ready;Click '安装所选依赖'
 Wait-For {$null -ne (Find-Control '下载: 正在下载 fixture.zip；使用相同选择重试可继续已保留的部分下载。')} 'Chinese download progress'
 # Native window close is asynchronous; it opens the modal confirmation without blocking this test.
 if(-not [GlowWizardTestWindow]::PostMessage([IntPtr]$script:window.Current.NativeWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)){throw 'Could not open stop confirmation.'}
 $script:stopDialog=$null
 Wait-For {
  $owned=[Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty,$script:process.Id))
  foreach($candidate in $owned){
   $script:stopDialog=$candidate.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,'继续设置'))
   if($script:stopDialog){break}
  }
  $null -ne $script:stopDialog
 } 'localized stop confirmation'
 Invoke-Control $script:stopDialog
 Wait-For {(Find-Control '停止设置').Current.IsEnabled} 'continue after cancelled stop'
 [IO.File]::WriteAllText((Join-Path $fixture 'resume.txt'),'continue',$utf8)
 # Release the synthetic worker after cancelling stop; it also has a bounded fallback.
 Wait-For {$null -ne (Find-Control '完成')} 'continued Chinese setup completion'
 Close-Wizard 0;Pass 'Chinese progress and stop confirmation allow setup to continue'
 $receipt.state='passed'
}catch{$receipt.state='failed';$receipt.error=$_.Exception.Message;$receipt.stack=$_.ScriptStackTrace;throw}
finally{
 if($script:process){if(-not $script:process.HasExited){$script:process.Kill();$null=$script:process.WaitForExit(2000)};$script:process.Dispose()}
 Save
}
