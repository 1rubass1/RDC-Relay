# Host-only fixed Remote tool markers -> authenticated snapshot -> GUI animation.
# Synthetic probes only. No Remote, GUI, IPC or installed app is launched.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerRuntime.cs')|ForEach-Object{Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
$pass=0;$fail=0
function Check([bool]$condition,[string]$name){
 if($condition){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$parser=([RdcOwnerRuntime]).GetMethod('SafeRemoteMarker',[Reflection.BindingFlags]'Static,NonPublic')
Check ($null -ne $parser) 'Pinned owned Remote marker classifier exists'
if($parser){
 foreach($probe in @(
  @{Raw='🔧 Received tool call abc: read_file {"path":"PRIVATE"}';Expected='Remote tool started: read_file'},
  @{Raw='🔧 Received tool call abc: unknown_tool {"token":"PRIVATE"}';Expected='Remote tool started'},
  @{Raw='✅ Tool call abc completed: PRIVATE OUTPUT';Expected='Remote tool completed'},
  @{Raw='❌ Tool call abc failed: PRIVATE ERROR';Expected='Remote tool failed'},
  @{Raw='{"text":"🔧 Received tool call abc: PRIVATE"}';Expected=''},
  @{Raw='ordinary output with Tool call abc completed:';Expected=''},
  @{Raw='tool result PRIVATE';Expected=''}
 )){
  $argsForParser=[object[]]@([string]$probe.Raw,'')
  $category=[string]$parser.Invoke($null,$argsForParser)
  Check ($category -ceq $probe.Expected -and $category -notmatch 'PRIVATE|abc|token') ('owned fixed marker '+$(if($probe.Expected){$probe.Expected}else{'refused'}))
 }
}
$s=New-Object RdcOwnerRemoteState
$s.EnableManaged()
$s.ManagedStatus(98765,$true,'Ready','fixture only')
$s.AddSyntheticLogLine('Remote tool started')
$a=$s.Snapshot()
Check ($a.toolActivity -ceq 'working' -and -not $a.toolFault) 'owned tool start requests activity'
$s.AddSyntheticLogLine('Remote tool completed')
$a=$s.Snapshot()
Check ($a.toolActivity -ceq 'hold' -and -not $a.toolFault) 'completed call retains classic activity hold'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
([RdcOwnerRemoteState]).GetField('activityHoldUntilUtc',$flags).SetValue($s,[DateTime]::UtcNow.AddSeconds(-2))
Check (($s.Snapshot()).toolActivity -ceq 'idle') 'hold expiration returns shader to idle without state revision'
$s.AddSyntheticLogLine('Remote tool started')
$s.AddSyntheticLogLine('Remote tool failed')
$a=$s.Snapshot()
Check ($a.toolActivity -ceq 'idle' -and $a.toolFault) 'failure ends activity and sets fault'
$s.AddSyntheticLogLine('Remote tool started')
$s.AddSyntheticLogLine('Remote tool completed')
Check (-not ($s.Snapshot()).toolFault) 'successful tool clears previous failure'
$s.AddSyntheticLogLine('Remote tool started')
([RdcOwnerRemoteState]).GetField('lastToolMarkerUtc',$flags).SetValue($s,[DateTime]::UtcNow.AddSeconds(-61))
Check (($s.Snapshot()).toolActivity -ceq 'idle') 'interrupted 60s activity retires safely'
$s.ManagedStatus(0,$false,'Disconnected','fixture disconnected')
Check (($s.Snapshot()).toolActivity -ceq 'idle') 'owned disconnect clears activity'
$o=New-Object RdcOwnerRemoteState
$o.AttachObservedReadOnly(24680)
$o.AddObservedMarker('Remote tool started')
Check (($o.Snapshot()).toolActivity -ceq 'working' -and -not ($o.Snapshot()).canStop) 'adopted read-only tool activity'
$o.AddObservedMarker('Remote tool completed')
Check (($o.Snapshot()).toolActivity -ceq 'hold') 'adopted tool completion holds indicator'
$o.RetargetObservedReadOnly(24681)
Check (($o.Snapshot()).toolActivity -ceq 'idle' -and -not ($o.Snapshot()).canStop) 'adopted PID transition resets activity and preserves denied stop'
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
Check ($gui.Contains('Set-DividerWorkState ($toolActivity -ne ' + "'idle')") -and
 $gui.Contains('Set-DividerFaultState ($toolFault -or $remoteFault)') -and
 $gui.Contains('Start-DividerRecoveryFlash')) 'GUI consumes authenticated activity, fault and recovery'
Check ($gui.Contains("$" + "script:ownerLastRemoteLinkState -in @('Fault','Reconnecting','AuthPending','Connecting')") -and
 $gui.Contains("$" + "remoteLinkState -ceq 'Ready'")) 'GUI flashes on channel reconnection without tool call'
Check ($gui.Contains('Set-DividerWorkState $false')) 'GUI fail-close IPC loses animation'
$recovery=([RdcOwnerRuntime]).GetMethod('ToolCompletionConfirmsReady',[Reflection.BindingFlags]'Static,NonPublic')
Check ($null -ne $recovery) 'Host recovery proof helper exists'
if($recovery){
 Check ([bool]$recovery.Invoke($null,[object[]]@('Remote tool completed','Reconnecting'))) 'completed remote call restores reconnecting state'
 Check (-not [bool]$recovery.Invoke($null,[object[]]@('Remote tool started','Reconnecting'))) 'started call alone cannot restore state'
 Check (-not [bool]$recovery.Invoke($null,[object[]]@('Remote tool completed','Disconnected'))) 'disconnected state not revived by stale log'
}
Write-Output ('RC1_LIVE_ACTIVITY_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
