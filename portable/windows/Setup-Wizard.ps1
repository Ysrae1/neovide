#requires -Version 5.1
<# Graphical, per-user dependency setup. Detection is read-only; installation
   starts only after the user reviews the detected plan and clicks Install. #>
[CmdletBinding()]
param([switch]$InstallNotebook,[switch]$InstallLatex,
    [ValidateSet('auto','en','zh-CN')][string]$Language='auto',
    [ValidateSet('auto','tuna','ustc','illinois')][string]$TeXMirror='auto')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Setup-Locale.ps1')
$script:SetupLanguage=Resolve-SetupLanguage $Language
$script:texMirrorValues=@('auto','tuna','ustc','illinois')
# PowerShell 5.1 is DPI-unaware. Set the UI thread before any WinForms HWND
# exists so Windows renders text at system DPI instead of stretching a bitmap.
# This deliberately promises system-DPI clarity, not dynamic cross-monitor DPI.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GlowSetupDpi {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
$previousDpiContext=[GlowSetupDpi]::SetThreadDpiAwarenessContext([IntPtr]::new(-2))
if ($previousDpiContext -eq [IntPtr]::Zero) {
    throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
try {
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:worker=$null
$script:plan=$null
$script:blocked=$false
$script:mode=''
$script:exitCode=2 # Deferred/cancelled; never report dependency acceptance.
$script:work=Join-Path ([IO.Path]::GetTempPath()) ('NeovideGlowSetup\'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $script:work -Force
$utf8=[Text.UTF8Encoding]::new($false)

function Quote([string]$Value) {
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Set-Busy([bool]$Busy) {
    $notebook.Enabled=-not $Busy; $latex.Enabled=-not $Busy
    $mirrorOptions.Enabled=(-not $Busy -and $latex.Checked)
    $detect.Enabled=-not $Busy; $install.Enabled=(-not $Busy -and $null -ne $script:plan -and -not $script:blocked)
    $close.Text=if ($Busy) {(Get-SetupText 'Stop setup')} else {(Get-SetupText 'Finish later')}
}
function Start-Setup([bool]$Apply) {
    $script:plan=$null
    $script:exitCode=2
    $script:mode=if ($Apply) {'install'} else {'detect'}
    $script:statusFile=Join-Path $script:work ($script:mode+'-'+[Guid]::NewGuid().ToString('N')+'.json')
    $script:reportFile=$script:statusFile+'.report.json'
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
        (Join-Path $PSScriptRoot 'Setup-Dependencies.ps1'),'-InstallBase','-StatusPath',$script:statusFile,'-ReportPath',$script:reportFile)
    if (-not $Apply) { $arguments+='-PlanOnly' }
    if ($notebook.Checked) { $arguments+='-InstallNotebook' }
    if ($latex.Checked) { $arguments+='-InstallLatex' }
    $arguments+=@('-TeXMirror',$script:texMirrorValues[$mirror.SelectedIndex])
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=Join-Path $PSHOME 'powershell.exe'
    $start.Arguments=(@($arguments|ForEach-Object {Quote $_}) -join ' ')
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $start.WorkingDirectory=$PSScriptRoot
    $script:worker=[Diagnostics.Process]::new(); $script:worker.StartInfo=$start
    try {
        if (-not $script:worker.Start()) { throw (Get-SetupText 'The setup worker could not start.') }
        $script:stdout=$script:worker.StandardOutput.ReadToEndAsync()
        $script:stderr=$script:worker.StandardError.ReadToEndAsync()
        $script:deadline=[DateTime]::UtcNow.AddMinutes($(if ($Apply) {90} else {10}))
        $status.Text=if ($Apply) {(Get-SetupText 'Preparing selected dependencies...')} else {(Get-SetupText 'Checking existing tools. This may take a few minutes...')}
        $progress.Style='Marquee'; Set-Busy $true
    } catch {
        $script:worker.Dispose(); $script:worker=$null
        $status.Text=(Get-SetupText 'Setup could not start. Check the message below and try again.')
        $details.Text=(Get-SetupText 'Technical details:')+"`r`n"+$_.Exception.Message; Set-Busy $false
    }
}
function Stop-Setup {
    if ($null -eq $script:worker -or $script:worker.HasExited) { return }
    # Kill only the new worker tree. Existing editors, kernels and tools are not targets.
    $stop=[Diagnostics.Process]::new()
    $stop.StartInfo.FileName=Join-Path $env:WINDIR 'System32\taskkill.exe'
    $stop.StartInfo.Arguments='/PID '+$script:worker.Id+' /T /F'
    $stop.StartInfo.UseShellExecute=$false; $stop.StartInfo.CreateNoWindow=$true
    $stop.StartInfo.RedirectStandardOutput=$true; $stop.StartInfo.RedirectStandardError=$true
    try {
        $null=$stop.Start(); $a=$stop.StandardOutput.ReadToEndAsync(); $b=$stop.StandardError.ReadToEndAsync()
        if (-not $stop.WaitForExit(5000)) { $stop.Kill(); $null=$stop.WaitForExit(1000) }
        $null=$script:worker.WaitForExit(5000)
    } finally { $stop.Dispose() }
}
function Confirm-SetupStop {
    $dialog=[Windows.Forms.Form]::new(); $dialog.SuspendLayout(); $dialog.Text='Neovide Glow'; $dialog.Icon=$form.Icon
    $dialog.AutoScaleDimensions=[Drawing.SizeF]::new(96,96); $dialog.AutoScaleMode='Dpi'
    $dialog.Font=[Drawing.Font]::new($fontName,10)
    $dialog.ClientSize=[Drawing.Size]::new(480,180); $dialog.StartPosition='CenterParent'
    $dialog.FormBorderStyle='FixedDialog'; $dialog.MinimizeBox=$false; $dialog.MaximizeBox=$false
    $dialog.ShowInTaskbar=$false
    $prompt=[Windows.Forms.Label]::new(); $prompt.Dock='Fill'; $prompt.Padding=[Windows.Forms.Padding]::new(18)
    $prompt.Text=Get-SetupText 'Stop this setup run? Existing environments and partial downloads are preserved. Reopen Setup to continue.'
    $actions=[Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock='Bottom'; $actions.AutoSize=$true
    $actions.FlowDirection='RightToLeft'; $actions.Padding=[Windows.Forms.Padding]::new(12)
    $keep=[Windows.Forms.Button]::new(); $keep.Text=Get-SetupText 'Continue setup'; $keep.AutoSize=$true
    $keep.Name='SetupContinue'; $keep.DialogResult='Cancel'; $keep.MinimumSize=[Drawing.Size]::new(110,34)
    $stop=[Windows.Forms.Button]::new(); $stop.Text=Get-SetupText 'Stop setup'; $stop.AutoSize=$true
    $stop.Name='SetupStopConfirm'; $stop.DialogResult='Yes'; $stop.MinimumSize=[Drawing.Size]::new(110,34)
    $actions.Controls.AddRange([Windows.Forms.Control[]]@($keep,$stop)); $dialog.Controls.Add($prompt); $dialog.Controls.Add($actions)
    $dialog.AcceptButton=$keep; $dialog.CancelButton=$keep
    $dialog.ResumeLayout($true)
    try { return $dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::Yes }
    finally { $dialog.Dispose() }
}
function Show-Plan($Report) {
    $script:plan=$Report.plan
    $script:blocked=@($Report.plan.items|Where-Object {$_.status -eq 'blocked'}).Count -gt 0
    $lines=@((Get-SetupText 'Review what will be reused or downloaded:'),'')
    if ($latex.Checked) { $lines+=((Get-SetupText 'TeX download source: {0}') -f [string]$mirror.SelectedItem); $lines+='' }
    foreach ($item in $Report.plan.items) {
        $line=(Get-SetupRole ([string]$item.role))+': '+(Get-SetupPlanStatus ([string]$item.status))
        if ($item.reuse_path) { $line+=' — '+$item.reuse_path }
        if ($null -ne $item.download_bytes -and $item.download_bytes -gt 0) { $line+=' — '+[Math]::Round($item.download_bytes/1MB,1)+' MiB' }
        if ($item.download_note) { $line+=' ('+(Get-SetupDetail ([string]$item.download_note))+')' }
        $lines+=$line
    }
    $lines+=@('',((Get-SetupText 'Known official downloads: {0} MiB.') -f [Math]::Round($Report.plan.known_download_bytes/1MB,1)))
    foreach ($note in @($Report.plan.dynamic_downloads)) { $lines+=Get-SetupDetail ([string]$note) }
    if ($Report.plan.PSObject.Properties['download_note']) { $lines+=Get-SetupDetail ([string]$Report.plan.download_note) }
    $lines+=@('',(Get-SetupText 'Download size is not installed disk space. Compatible tools are reused; existing environments are preserved.'),
        (Get-SetupText 'Install changes only selected dependencies. Finish later keeps the editor usable; optional features may be unavailable.'))
    $details.Text=$lines -join [Environment]::NewLine
    $status.Text=if ($script:blocked) {(Get-SetupText 'Some checks were inconclusive. Open logs and resolve them before installing.')} else {(Get-SetupText 'Detection complete. Review the plan, then choose Install or Finish later.')}
}

$form=[Windows.Forms.Form]::new(); $form.SuspendLayout(); $form.Text=(Get-SetupText 'Neovide Glow — First steps')
$iconPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'neovide.ico'
if (Test-Path -LiteralPath $iconPath -PathType Leaf) { $form.Icon=[Drawing.Icon]::new($iconPath) }
$form.AutoScaleDimensions=[Drawing.SizeF]::new(96,96); $form.AutoScaleMode='Dpi'
$form.Size=[Drawing.Size]::new(800,650); $form.MinimumSize=[Drawing.Size]::new(650,540)
$form.StartPosition='CenterScreen'
$fontName=if ($script:SetupLanguage -eq 'zh-CN') {'Microsoft YaHei UI'} else {'Segoe UI'}
$form.Font=[Drawing.Font]::new($fontName,10)
$layout=[Windows.Forms.TableLayoutPanel]::new(); $layout.Dock='Fill'; $layout.Padding=[Windows.Forms.Padding]::new(20)
$layout.ColumnCount=1; $layout.RowCount=7
$null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
foreach ($row in 0..3) { $null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('AutoSize')) }
$null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
$null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',24)); $null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('AutoSize'))
$intro=[Windows.Forms.Label]::new(); $intro.Dock='Fill'; $intro.AutoSize=$true; $intro.Margin=[Windows.Forms.Padding]::new(3,3,3,12)
$intro.Text=(Get-SetupText "The editor is installed. Choose the features you need; setup checks this PC before downloading anything.`r`nYour configuration, Python/Conda environments and system PATH are preserved.")
$choices=[Windows.Forms.FlowLayoutPanel]::new(); $choices.Dock='Fill'; $choices.AutoSize=$true; $choices.WrapContents=$true
$notebook=[Windows.Forms.CheckBox]::new(); $notebook.Text=(Get-SetupText 'Notebook / Python'); $notebook.AutoSize=$true; $notebook.Checked=[bool]$InstallNotebook
$latex=[Windows.Forms.CheckBox]::new(); $latex.Text=(Get-SetupText 'LaTeX / Chinese PDF'); $latex.AutoSize=$true; $latex.Checked=[bool]$InstallLatex
$choices.Controls.AddRange([Windows.Forms.Control[]]@($notebook,$latex))
$mirrorOptions=[Windows.Forms.FlowLayoutPanel]::new(); $mirrorOptions.Dock='Fill'; $mirrorOptions.AutoSize=$true
$mirrorOptions.WrapContents=$true; $mirrorOptions.Enabled=$latex.Checked
$mirrorLabel=[Windows.Forms.Label]::new(); $mirrorLabel.Text=Get-SetupText 'TeX download source'; $mirrorLabel.AutoSize=$true
$mirrorLabel.Margin=[Windows.Forms.Padding]::new(3,8,10,3)
$mirror=[Windows.Forms.ComboBox]::new(); $mirror.Name='SetupTeXMirror'; $mirror.AccessibleName=Get-SetupText 'TeX download source'
$mirror.DropDownStyle='DropDownList'; $mirror.Width=210
foreach ($label in @('Automatic','Tsinghua University','USTC','Illinois')) { $null=$mirror.Items.Add((Get-SetupText $label)) }
$mirror.SelectedIndex=[Array]::IndexOf($script:texMirrorValues,$TeXMirror)
$mirrorHint=[Windows.Forms.Label]::new(); $mirrorHint.AutoSize=$true
$mirrorHint.Text=Get-SetupText 'Automatic tries Chinese mirrors first on Chinese Windows and Illinois first on other systems. The source is checked only when installing LaTeX; system settings are unchanged.'
$mirrorHint.Margin=[Windows.Forms.Padding]::new(3,4,3,8)
$mirrorOptions.Controls.AddRange([Windows.Forms.Control[]]@($mirrorLabel,$mirror,$mirrorHint)); $mirrorOptions.SetFlowBreak($mirror,$true)
$status=[Windows.Forms.Label]::new(); $status.Dock='Fill'; $status.AutoSize=$true; $status.Margin=[Windows.Forms.Padding]::new(3,8,3,8)
$details=[Windows.Forms.TextBox]::new(); $details.Dock='Fill'; $details.Multiline=$true; $details.ReadOnly=$true
$details.ScrollBars='Vertical'; $details.WordWrap=$true; $details.AccessibleName=(Get-SetupText 'Detected dependencies and download plan')
$progress=[Windows.Forms.ProgressBar]::new(); $progress.Dock='Fill'
$buttons=[Windows.Forms.FlowLayoutPanel]::new(); $buttons.Dock='Fill'; $buttons.AutoSize=$true; $buttons.WrapContents=$true; $buttons.FlowDirection='RightToLeft'; $buttons.Padding=[Windows.Forms.Padding]::new(0,10,0,0)
$close=[Windows.Forms.Button]::new(); $close.Text=(Get-SetupText 'Finish later'); $close.AutoSize=$true
$install=[Windows.Forms.Button]::new(); $install.Text=(Get-SetupText 'Install selected'); $install.AutoSize=$true; $install.Enabled=$false
$detect=[Windows.Forms.Button]::new(); $detect.Text=(Get-SetupText 'Check again'); $detect.AutoSize=$true
$logs=[Windows.Forms.Button]::new(); $logs.Text=(Get-SetupText 'Open logs'); $logs.AutoSize=$true
foreach ($entry in @(@($close,'SetupClose'),@($install,'SetupInstall'),@($detect,'SetupDetect'),@($logs,'SetupLogs'))) {
    $entry[0].Name=$entry[1]; $entry[0].MinimumSize=[Drawing.Size]::new(98,34)
}
$notebook.Name='SetupNotebook'; $latex.Name='SetupLatex'; $details.Name='SetupDetails'; $status.Name='SetupStatus'
$buttons.Controls.AddRange([Windows.Forms.Control[]]@($close,$install,$detect,$logs))
foreach ($control in @($intro,$choices,$mirrorOptions,$status,$details,$progress,$buttons)) { $layout.Controls.Add($control) }
$form.Controls.Add($layout)
$resizeText={
    $width=[Math]::Max(200,$layout.ClientSize.Width-$layout.Padding.Horizontal-8)
    $intro.MaximumSize=[Drawing.Size]::new($width,0); $status.MaximumSize=[Drawing.Size]::new($width,0)
    $mirrorHint.MaximumSize=[Drawing.Size]::new($width,0)
}
$layout.Add_SizeChanged($resizeText); & $resizeText
$form.ResumeLayout($true)
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=300
$timer.Add_Tick({
    if ($null -eq $script:worker) { return }
    try {
        if (Test-Path -LiteralPath $script:statusFile -PathType Leaf) {
            try {
                $current=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:statusFile,[Text.Encoding]::UTF8))
                $status.Text=(Get-SetupPhase ([string]$current.phase))+': '+(Get-SetupDetail ([string]$current.detail))
                if ($current.run_path) { $script:lastRun=[string]$current.run_path }
                if ($current.total_bytes -gt 0) {
                    $progress.Style='Continuous'; $progress.Value=[Math]::Min(100,[int](100*$current.downloaded_bytes/$current.total_bytes))
                } else { $progress.Style='Marquee' }
            } catch {} # Atomic replacement can briefly hold the file; retry next tick.
        }
        if (-not $script:worker.HasExited -and [DateTime]::UtcNow -ge $script:deadline) {
            Stop-Setup
            throw (Get-SetupText 'This setup run exceeded its time budget. Logs and partial downloads are preserved. Check again to resume.')
        }
        if (-not $script:worker.HasExited) { return }
        $drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($script:stdout,$script:stderr),2000)
        $output=if ($script:stdout.IsCompleted) {$script:stdout.GetAwaiter().GetResult()} else {(Get-SetupText 'Output pipe did not close; use the setup report and phase logs.')}
        $errors=if ($script:stderr.IsCompleted) {$script:stderr.GetAwaiter().GetResult()} else {(Get-SetupText 'Error pipe did not close; use the setup report and phase logs.')}
        [IO.File]::WriteAllText((Join-Path $script:work ($script:mode+'.stdout.log')),$output,$utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($script:mode+'.stderr.log')),$errors,$utf8)
        if ($script:worker.ExitCode -ne 0) { throw $errors.Substring([Math]::Max(0,$errors.Length-3000)) }
        $report=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:reportFile,[Text.Encoding]::UTF8))
        if ($script:mode -eq 'detect') {
            if ($report.status -ne 'planned' -or $report.selection_saved) { throw (Get-SetupText 'Setup did not produce a read-only detection report.') }
            Show-Plan $report
        }
        else {
            $completed=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:statusFile,[Text.Encoding]::UTF8))
            if ($completed.state -ne 'passed' -or $report.status -ne 'passed') { throw (Get-SetupText 'Setup exited without a passed dependency receipt. Open logs before retrying.') }
            $status.Text=(Get-SetupText 'Selected dependencies passed. Reopen Glow to use them.')
            $details.Text=(Get-SetupText "Next: launch Neovide Glow from Start. On first launch, choose your existing compatible Windows configuration or the separate defaults.`r`n`r`nOpen a .ipynb file for Notebook or a .tex file for LaTeX. AI accounts and project compilers are configured separately.`r`n`r`nTo review or repair dependencies later, use the Neovide Glow Setup shortcut.")
            $script:exitCode=0; $close.Text=(Get-SetupText 'Finish')
        }
        $script:worker.Dispose(); $script:worker=$null; $progress.Style='Continuous'; $progress.Value=100
        Set-Busy $false
        if ($script:exitCode -eq 0) { $close.Text=(Get-SetupText 'Finish') }
    } catch {
        if ($script:worker -and -not $script:worker.HasExited) { Stop-Setup }
        if ($script:worker) { $script:worker.Dispose(); $script:worker=$null }
        $script:plan=$null; $script:exitCode=1; Set-Busy $false; $progress.Style='Continuous'; $progress.Value=0
        $status.Text=(Get-SetupText 'Setup did not finish. Your editor and existing environments are preserved.')
        $details.Text=(Get-SetupText 'Technical details:')+"`r`n"+$_.Exception.Message+"`r`n`r`n"+(Get-SetupText 'Open logs for the failed phase. Check again to detect completed work, then Install selected to resume owned partial downloads. You can also finish later and reopen Neovide Glow Setup.')
    }
})
$detect.Add_Click({Start-Setup $false})
$install.Add_Click({Start-Setup $true})
$selectionChanged={
    $script:plan=$null; $script:exitCode=2; $close.Text=Get-SetupText 'Finish later'; $install.Enabled=$false
    $mirrorOptions.Enabled=$latex.Checked
    $status.Text=Get-SetupText 'Selection changed. Choose Check again to refresh the download plan.'
}
foreach ($choice in @($notebook,$latex)) { $choice.Add_CheckedChanged($selectionChanged) }
$mirror.Add_SelectedIndexChanged($selectionChanged)
$logs.Add_Click({
    $directory=if (Get-Variable lastRun -Scope Script -ErrorAction SilentlyContinue) {$script:lastRun} else {$script:work}
    $start=[Diagnostics.ProcessStartInfo]::new(); $start.FileName='explorer.exe'; $start.Arguments=Quote $directory; $start.UseShellExecute=$false
    $p=[Diagnostics.Process]::Start($start); if ($p) { $p.Dispose() }
})
$close.Add_Click({$form.Close()})
$form.Add_FormClosing({
    if ($script:worker -and -not $script:worker.HasExited) {
        if (-not (Confirm-SetupStop)) { $_.Cancel=$true; return }
        Stop-Setup
    }
})
$form.Add_Shown({$timer.Start(); Start-Setup $false})
try { $null=$form.ShowDialog() }
finally { $timer.Stop(); $timer.Dispose(); if ($script:worker) { Stop-Setup; $script:worker.Dispose() }; $form.Dispose() }
} finally {
    $null=[GlowSetupDpi]::SetThreadDpiAwarenessContext($previousDpiContext)
}
exit $script:exitCode
