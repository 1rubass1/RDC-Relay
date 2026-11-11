# Product guard against managed Remote spawning before GUI authenticates.
# Source-only/compile regression; never starts OS Host, GUI, or Remote.
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'
$store=[IO.File]::ReadAllText((Join-Path $source 'RdcOwnerTicketStore.cs'))
$hostScript=[IO.File]::ReadAllText((Join-Path $source 'rc1-tray-host.ps1'))
$runtime=[IO.File]::ReadAllText((Join-Path $source 'RdcOwnerRuntime.cs'))
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($store -match 'mode!="MANAGED_OWNER_RC1"' -and
 $store -match 'RC1_TICKET_PAYLOAD_IDENTITY') 'managed GUI ticket accepted only in original authenticated ticket contract'
Check ($hostScript -notmatch 'TryAutoStartManagedRemote\s*\(') 'product Host has no early managed Remote spawn before GUI'
Check ($hostScript -match '\$owner\.EnableManagedRemote\(\)' -and
 $hostScript -match '\$owner\.OpenGui\(\)') 'full Host arms managed mode then creates GUI'
Check ($runtime -match '!guiAuthenticated\|\|guiState!="CONNECTED"\|\|reopenAfterModeChange') 'managed autostart method refuses unauthenticated GUI'
Check ($runtime -match 'autoStartPending && guiAuthenticated && guiState=="CONNECTED"' -and
 $runtime -match 'guiReadySignal.Set\(\)') 'WinForms timer starts only after authenticated GUI event'
Write-Output ('RC1_MANAGED_STARTUP_CONTRACT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
