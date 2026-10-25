#requires -Version 5.1
<# Actual installed GUI entry, detection/defer only. No dependency downloads or
   profile initialization. Run from a logged-on user via a hidden worker. #>
param([Parameter(Mandatory=$true)][string]$ApplicationRoot,[Parameter(Mandatory=$true)][string]$WorkRoot,
 [ValidateSet('en','zh-CN')][string]$ExpectedLanguage='en')
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if(Test-Path -LiteralPath $WorkRoot){throw 'Use a fresh setup-entry WorkRoot.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
$u=[Text.UTF8Encoding]::new($false);$p=$null;$child=$null
$selection=Join-Path $env:LOCALAPPDATA 'NeovideGlow\dependencies\selected.json'
$before=if(Test-Path -LiteralPath $selection){(Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash}else{$null}
$r=[ordered]@{state='running';changes_requested=$false;download_started=$false;expected_language=$ExpectedLanguage}
$installLabel='Install selected';$deferLabel='Finish later';$planLabel='Detected dependencies and download plan'
$downloadLabel='Known official downloads:';$searchLabel='search:'
if($ExpectedLanguage -eq 'zh-CN'){
 $installLabel='安装所选依赖';$deferLabel='稍后完成';$planLabel='检测结果与下载计划'
 $downloadLabel='已知官方来源下载量：';$searchLabel='文本搜索 (ripgrep)'
}
$window=$null
function Get-ElementText($Element){
 # Classic WinForms/MSAA can expose the entire visible edit text as Name,
 # with no Value/Text patterns. Read only the candidate control in our window.
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
function Invoke-Finish($Element){
 if($null -eq $Element){throw 'Finish later control is missing.'}
 $pattern=$null
 if($Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)){
  ([Windows.Automation.InvokePattern]$pattern).Invoke();return 'UI Automation Invoke'
 }
 if($Element.Current.ClassName -notlike 'WindowsForms10.BUTTON*' -or $Element.Current.NativeWindowHandle -eq 0){throw 'Finish later has no supported native button action.'}
 if(-not ('GlowSetupNativeButton' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GlowSetupNativeButton {
 [DllImport("user32.dll", SetLastError=true)]
 public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
 }
 $result=[UIntPtr]::Zero
 if([GlowSetupNativeButton]::SendMessageTimeout([IntPtr]$Element.Current.NativeWindowHandle,0xF5,[UIntPtr]::Zero,[IntPtr]::Zero,2,2000,[ref]$result) -eq [IntPtr]::Zero){throw 'The test-owned Finish later button did not accept BM_CLICK.'}
 return 'Native WinForms BM_CLICK'
}
function Save-ControlTree($Window){
 $nodes=$Window.FindAll([Windows.Automation.TreeScope]::Subtree,[Windows.Automation.Condition]::TrueCondition)
 $rows=foreach($node in $nodes){
  try{
   [ordered]@{name=$node.Current.Name;type=$node.Current.ControlType.ProgrammaticName;class=$node.Current.ClassName;
    automation_id=$node.Current.AutomationId;offscreen=$node.Current.IsOffscreen;
    patterns=@($node.GetSupportedPatterns()|ForEach-Object{$_.ProgrammaticName})}
  }catch{[ordered]@{error=$_.Exception.Message}}
 }
 [IO.File]::WriteAllText((Join-Path $WorkRoot 'control-tree.json'),(ConvertTo-Json -InputObject @($rows) -Depth 5),$u)
}
try{
 $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=Join-Path $ApplicationRoot 'Glow.exe';$start.Arguments='--setup'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $p=[Diagnostics.Process]::new();$p.StartInfo=$start;$null=$p.Start();$a=$p.StandardOutput.ReadToEndAsync();$b=$p.StandardError.ReadToEndAsync();$r.launcher_pid=$p.Id
 $deadline=[DateTime]::UtcNow.AddSeconds(180);$window=$null;$ready=$false
 do{
  if($p.HasExited){throw ('Installed setup exited before detection: '+$p.ExitCode)}
  if(-not $child){$child=Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$p.Id)|Where-Object{$_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Setup-Wizard.ps1*'}|Select-Object -First 1}
  if($child -and -not $window){$window=[Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty,[int]$child.ProcessId))}
  if($window){
   $install=$window.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,$installLabel))
   $ready=$install -and $install.Current.IsEnabled
  }
  if(-not $ready){Start-Sleep -Milliseconds 200}
 }while(-not $ready -and [DateTime]::UtcNow -lt $deadline)
 if(-not $ready){throw 'Installed setup did not produce a reviewable plan within 180 seconds.'}
 $text=$null
 $nodes=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
 foreach($node in $nodes){
  $info=$node.Current
  if($info.IsOffscreen){continue}
  if($info.Name -ne $planLabel -and
     $info.ControlType -ne [Windows.Automation.ControlType]::Edit -and
     $info.ControlType -ne [Windows.Automation.ControlType]::Document -and
     $info.ClassName -notlike 'WindowsForms10.EDIT*'){continue}
  foreach($value in @(Get-ElementText $node)){
   if($value.Contains($downloadLabel) -and $value.Contains($searchLabel)){
    $text=$value;$r.plan_control_type=$info.ControlType.ProgrammaticName;$r.plan_control_class=$info.ClassName;break
   }
  }
  if($null -ne $text){break}
 }
 if($null -eq $text){throw 'The real GUI did not display dependency and download details in a visible text control.'}
 [IO.File]::WriteAllText((Join-Path $WorkRoot 'visible-plan.txt'),$text,$u)
 $finish=$window.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,$deferLabel))
 $r.defer_control_action=Invoke-Finish $finish
 if(-not $p.WaitForExit(15000) -or $p.ExitCode -ne 2){throw 'Deferring installed setup did not return code 2.'}
 $r.launcher_exit_code=$p.ExitCode
 $r.output_drain_complete=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($a,$b),2000)
 # An inherited diagnostic handle is not the GUI result: the window's actual
 # plan text, successful deferred exit, and unchanged selection are asserted.
 $diagnostic=if($b.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion){$b.GetAwaiter().GetResult()}else{'[Diagnostic output handle did not close within 2 seconds. See the visible plan and result receipt.]'}
 [IO.File]::WriteAllText((Join-Path $WorkRoot 'launcher.stderr.log'),$diagnostic,$u)
 $after=if(Test-Path -LiteralPath $selection){(Get-FileHash -LiteralPath $selection -Algorithm SHA256).Hash}else{$null}
 if($after -cne $before){throw 'Read-only GUI detection changed the existing selection.'}
 $r.worker_pid=$child.ProcessId;$r.launcher_exit_code=$p.ExitCode;$r.selection_preserved=$true;$r.state='passed'
}catch{
 $failure=$_;$r.state='failed';$r.error=$failure.Exception.Message
 $r.stack=$failure.ScriptStackTrace;$r.position=$failure.InvocationInfo.PositionMessage
 if($window){try{Save-ControlTree $window;$r.control_tree='control-tree.json'}catch{$r.control_tree_error=$_.Exception.Message}}
 throw $failure
}
finally{
 if($p -and -not $p.HasExited){
  if($child){$owned=Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue;if($owned){$owned.Kill();$null=$owned.WaitForExit(3000);$owned.Dispose()}}
  $p.Kill();$null=$p.WaitForExit(3000)
 }
 if($p){$p.Dispose()}
 [IO.File]::WriteAllText((Join-Path $WorkRoot 'receipt.json'),($r|ConvertTo-Json -Depth 5),$u)
}
