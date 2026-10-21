# Read-only Evergreen detection from Microsoft's documented Runtime client ID.
# https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution
# Edge browser presence/versions are deliberately not probed.
function Read-GlowWebView2RegistryValue {
    param([string]$Hive,[string]$View,[string]$Key)
    $base = $null; $entry = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Enum]::Parse([Microsoft.Win32.RegistryHive],$Hive),
            [Enum]::Parse([Microsoft.Win32.RegistryView],$View))
        $entry = $base.OpenSubKey($Key,$false)
        if (-not $entry) { return [pscustomobject]@{ accessible=$true; value=$null } }
        $value = $entry.GetValue('pv',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -ne $value -and $entry.GetValueKind('pv') -ne [Microsoft.Win32.RegistryValueKind]::String) { $value = $null }
        return [pscustomobject]@{ accessible=$true; value=$value }
    }
    catch { return [pscustomobject]@{ accessible=$false; value=$null } }
    finally { if ($entry) { $entry.Dispose() }; if ($base) { $base.Dispose() } }
}

function Get-GlowWebView2Runtime {
    param([scriptblock]$ReadRegistry)
    if (-not $ReadRegistry) { $ReadRegistry = { param($Hive,$View,$Key) Read-GlowWebView2RegistryValue $Hive $View $Key } }
    $key = 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $registrations = @(); $unreadable = 0
    $locations = @(
        @{hive='LocalMachine';view='Registry32'},
        @{hive='CurrentUser';view='Registry64'},
        @{hive='CurrentUser';view='Registry32'}
    )
    foreach ($location in $locations) {
        $record = & $ReadRegistry $location.hive $location.view $key
        if (-not $record -or -not $record.accessible) { $unreadable++; continue }
        if ($record.value -isnot [string] -or $record.value -notmatch '^\d+\.\d+\.\d+\.\d+$') { continue }
        $version = $null
        if ([Version]::TryParse($record.value,[ref]$version) -and $version -gt [Version]'0.0.0.0') {
            $registrations += [pscustomobject]@{hive=$location.hive;view=$location.view;key=$key;version=$version.ToString()}
        }
    }
    $selected = $registrations | Sort-Object { [Version]$_.version } -Descending | Select-Object -First 1
    $status = if ($selected) { 'installed' } elseif ($unreadable) { 'unknown' } else { 'not_detected' }
    return [pscustomobject]@{available=[bool]$selected;status=$status;version=$(if ($selected) { $selected.version } else { $null });
        detection='official-evergreen-runtime-registry';registrations=$registrations;unreadable_locations=$unreadable}
}
