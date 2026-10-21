#requires -Version 5.1
# Test the actual detector through its registry reader boundary. No registry writes/installers.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\portable\windows\WebView2.ps1')
$script:reads=@()
$absent = {
 param($Hive,$View,$Key)
 $script:reads += @{hive=$Hive;view=$View;key=$Key}
 [pscustomobject]@{accessible=$true;value=$null}
}
$result=Get-GlowWebView2Runtime -ReadRegistry $absent
if ($result.available -or $result.status -ne 'not_detected' -or $script:reads.Count -ne 3) { throw 'Absent runtime detection failed.' }
foreach ($read in $script:reads) {
 if ($read.key -cne 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') { throw 'Detector probed a browser or arbitrary registry path.' }
}
Write-Output 'PASS absent Runtime probes only the documented Evergreen client ID'

foreach ($invalid in @('', '0.0.0.0', 'Edge Stable', '123.4', '123.4.5.6-beta')) {
 $value=$invalid
 $reader={param($Hive,$View,$Key) [pscustomobject]@{accessible=$true;value=$value}}.GetNewClosure()
 $result=Get-GlowWebView2Runtime -ReadRegistry $reader
 if ($result.available) { throw ('Invalid/zero Runtime version accepted: '+$invalid) }
}
Write-Output 'PASS empty, zero, malformed and browser labels do not imply Runtime availability'

$machine={param($Hive,$View,$Key) [pscustomobject]@{accessible=$true;value=$(if ($Hive -eq 'LocalMachine') {'142.0.3595.90'} else {$null})}}
$result=Get-GlowWebView2Runtime -ReadRegistry $machine
if (-not $result.available -or $result.version -ne '142.0.3595.90' -or $result.registrations[0].view -ne 'Registry32') { throw 'Per-machine Runtime not reused.' }
Write-Output 'PASS per-machine Runtime uses the official WOW6432 registry view'

$user={param($Hive,$View,$Key) [pscustomobject]@{accessible=$true;value=$(if ($Hive -eq 'CurrentUser') {'142.0.3595.99'} else {$null})}}
$result=Get-GlowWebView2Runtime -ReadRegistry $user
if (-not $result.available -or $result.version -ne '142.0.3595.99') { throw 'Per-user Runtime not reused.' }
Write-Output 'PASS per-user Runtime registration is reused'

$denied={param($Hive,$View,$Key) [pscustomobject]@{accessible=$false;value=$null}}
$result=Get-GlowWebView2Runtime -ReadRegistry $denied
if ($result.available -or $result.status -ne 'unknown' -or $result.unreadable_locations -ne 3) { throw 'Unreadable keys incorrectly declared absent/available.' }
Write-Output 'PASS inaccessible registration is reported unknown without installation'
