# P1 reviewer repro: fail-closed readiness with link faults and stale evidence.
# Compiles production sources, probes fake markers; never connects to Remote.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs') |
 ForEach-Object {Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll',
 'System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
. (Join-Path $src 'rc1-remote-observer.ps1')
$pass=0;$fail=0
function Check([bool]$yes,[string]$label){
 if($yes){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$method=([RdcOwnerRuntime]).GetMethod('SafeRemoteMarker',
 [Reflection.BindingFlags]'Static,NonPublic')
Check ($null -ne $method) 'production managed link classifier exists'
$faults=@(
 'Channel closed',
 'Remote session expired and could not be renewed',
 'Device registered, but NOT reachable',
 'Realtime channel is not open',
 'Channel subscription timed out',
 'Presence track remained unavailable',
 'Presence published but the device row could not be updated',
 'Restart the terminal running Desktop Commander to reconnect',
 'This device is now offline for remote calls',
 'Could not restart local Desktop Commander MCP: fake',
 'Device marked as offline'
)
foreach($line in $faults){
 $argsForParser=[object[]]@($line,'')
 $category=[string]$method.Invoke($null,$argsForParser)
 $next=[string]$argsForParser[1]
 Check (($next -ceq 'Fault' -or $next -ceq 'Reconnecting') -and
   $category -in @('Remote channel unavailable','Local MCP recovering','Remote session expired')) ('managed fail closed '+$line)
 $observer=Get-Rc1ObservedMarker $line
 Check ($null -ne $observer -and $observer.State -in @('Fault','Reconnecting') -and
   -not ($observer.Marker -match 'fake')) ('observer fail closed '+$line)
}
foreach($line in @(
 'Desktop Commander Remote is connected',
 'Presence tracked (device fixture online)'
)){
 $argsForParser=[object[]]@($line,'')
 Check ([string]$method.Invoke($null,$argsForParser) -ceq 'Remote connected' -and
  [string]$argsForParser[1] -ceq 'Ready') ('managed genuine ready evidence '+$line)
}
foreach($line in @(
 '{"message":"Presence tracked (device fixture online)"}',
 'tool output: Presence tracked (device fixture online)',
 'PRIVATE Channel closed inside tool output'
)){
 $argsForParser=[object[]]@($line,'')
 $category=[string]$method.Invoke($null,$argsForParser)
 Check ($category -ceq '' -and [string]$argsForParser[1] -ceq '') ('untrusted text cannot change managed link '+$line)
}
$lease=([RdcOwnerRuntime]).GetMethod('ManagedReadyEvidenceExpired',
 [Reflection.BindingFlags]'Static,NonPublic')
Check ($null -ne $lease) 'owned readiness proof has bounded lease'
if($lease){
 $now=[DateTime]::UtcNow
 Check (-not [bool]$lease.Invoke($null,[object[]]@($now,$now.AddSeconds(-15)))) 'recent owned proof retained'
 Check ([bool]$lease.Invoke($null,[object[]]@($now,$now.AddMinutes(-10)))) 'idle stale owned proof expires'
 Check ([bool]$lease.Invoke($null,[object[]]@($now,[DateTime]::MinValue))) 'missing owned proof cannot remain ready'
}
$observedLease=Get-Command Test-Rc1ObservedReadyEvidenceExpired -ErrorAction SilentlyContinue
Check ($null -ne $observedLease) 'observed readiness proof has bounded lease'
if($observedLease){
 $now=[DateTime]::UtcNow.Ticks
 Check (-not (Test-Rc1ObservedReadyEvidenceExpired $now ($now-[TimeSpan]::FromSeconds(15).Ticks))) 'recent observed proof retained'
 Check (Test-Rc1ObservedReadyEvidenceExpired $now ($now-[TimeSpan]::FromMinutes(10).Ticks)) 'silent observed link expires'
 Check (Test-Rc1ObservedReadyEvidenceExpired $now ([long]0)) 'historic observer startup cannot claim fresh ready'
}
# Real supervisor store transitions: no network or process creation.
$store=New-Object RdcOwnerRemoteState
$store.EnableManaged()
$store.ManagedStatus(33333,$true,'Ready','fake link proof')
$store.AddSyntheticLogLine('Remote tool started')
Check (($store.Snapshot()).state -ceq 'Ready' -and
 ($store.Snapshot()).toolActivity -ceq 'working') 'managed fake live tool in ready state'
$store.ManagedStatus(33333,$true,'Fault','Channel closed (safe category)')
$closed=$store.Snapshot()
Check ($closed.state -ceq 'Fault' -and $closed.transportReady -ceq 'not_connected' -and
 $closed.toolActivity -ceq 'idle' -and -not $closed.toolFault) 'managed disconnect revokes ready and stale tool activity'
$store.ManagedStatus(33333,$true,'Reconnecting','no proof')
Check (($store.Snapshot()).state -ceq 'Reconnecting' -and
 ($store.Snapshot()).transportReady -ceq 'not_connected') 'owned still-running process cannot imply ready'
$store.ManagedStatus(33333,$true,'Ready','new confirmed marker')
Check (($store.Snapshot()).transportReady -ceq 'MANAGED_READY') 'new proof can restore managed Ready'
$observedStore=New-Object RdcOwnerRemoteState
$observedStore.AttachObservedReadOnly(44444)
$observedStore.UpdateObservedReadOnly($true,'Ready','fake observed proof')
$observedStore.AddObservedMarker('Remote tool started')
$observedStore.UpdateObservedReadOnly($true,'Reconnecting','stale observed link')
Check (($observedStore.Snapshot()).state -ceq 'Reconnecting' -and
 ($observedStore.Snapshot()).toolActivity -ceq 'idle' -and
 -not ($observedStore.Snapshot()).canStop) 'adopted stale ready and work disappear, ownership never granted'

# Historical bootstrap may describe a former connection but must not itself
# grant current readiness to an observed launcher.
$historic=Join-Path ([IO.Path]::GetTempPath()) ('rc1-P1-history-'+[Guid]::NewGuid().ToString('N')+'.log')
try{
 [IO.File]::WriteAllText($historic,("Desktop Commander Remote is connected"+[Environment]::NewLine),[Text.Encoding]::UTF8)
 $script:fixtureHistoricalLog=$historic
 Set-Item Function:\Get-Rc1ObservedRemoteIdentity {return @{Pid=55555;Born=123;Session=1;Parent=0;Log=$script:fixtureHistoricalLog;Exe='fixture'}}
 $sink=[pscustomobject]@{Attached=0;LastState='';Markers=0}
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name EnableObservedRemote -Value {
  param([int]$processId) $this.Attached=$processId
 }
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name UpdateObservedRemote -Value {
  param([bool]$alive,[string]$state,[string]$detail) $this.LastState=$state
 }
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedMarker -Value {
  param([string]$marker) $this.Markers++
 }
 $bootstrap=Initialize-Rc1RemoteObserver $sink
 Check ($bootstrap.State -ceq 'Connecting' -and [long]$bootstrap.LastReadyProofTicks -eq 0 -and
  $sink.LastState -ceq 'Connecting' -and $sink.Attached -eq 55555) 'historic observer Ready not carried into live GUI'
 $bootstrap.State='Ready';$bootstrap.LastReadyProofTicks=[DateTime]::UtcNow.AddMinutes(-5).Ticks
 Expire-Rc1ObservedReadyEvidence $bootstrap
 Check ($bootstrap.State -ceq 'Reconnecting' -and
  $bootstrap.Detail -match 'unconfirmed' -and
  [long]$bootstrap.LastReadyProofTicks -eq 0) 'observed silent link falls back without Remote IO'
}finally{
 if([IO.File]::Exists($historic)){[IO.File]::Delete($historic)}
}
# Actual observed poll on a disposable logfile: stale -> recovering,
# new real marker -> Ready, channel failure -> Fault. OS identity is mocked
# solely in this test process; the installed Remote is not discovered.
$pollLog=Join-Path ([IO.Path]::GetTempPath()) ('rc1-P1-poll-'+[Guid]::NewGuid().ToString('N')+'.log')
try{
 [IO.File]::WriteAllText($pollLog,'old ignored log line'+[Environment]::NewLine,[Text.Encoding]::UTF8)
 Set-Item Function:\Test-Rc1ObservedRemoteIdentity {param($record) return $true}
 $record=@{Pid=55555;Born=123;Session=1;Parent=0;Log=$pollLog;Exe='fixture';
  Offset=([IO.FileInfo]$pollLog).Length;Fragment='';DiscardFirst=$false;
  State='Ready';Detail='old proof';LastReadyProofTicks=[DateTime]::UtcNow.AddMinutes(-10).Ticks}
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Reconnecting' -and $sink.LastState -ceq 'Reconnecting') 'silent observed log poll revokes stale Ready'
 [IO.File]::AppendAllText($pollLog,'Desktop Commander Remote is connected'+[Environment]::NewLine,[Text.Encoding]::UTF8)
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Ready' -and $sink.LastState -ceq 'Ready' -and
  [long]$record.LastReadyProofTicks -gt [DateTime]::UtcNow.AddMinutes(-1).Ticks) 'fresh observed status reestablishes Ready'
 [IO.File]::AppendAllText($pollLog,'Channel closed'+[Environment]::NewLine,[Text.Encoding]::UTF8)
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Fault' -and $sink.LastState -ceq 'Fault' -and
  [long]$record.LastReadyProofTicks -eq 0 -and $sink.Markers -eq 2) 'observed channel closure immediately revokes ready'
}finally{
 if([IO.File]::Exists($pollLog)){[IO.File]::Delete($pollLog)}
}
$runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
$observerSource=[IO.File]::ReadAllText((Join-Path $src 'rc1-remote-observer.ps1'),[Text.Encoding]::UTF8)
Check ($runtime.Contains('ExpireManagedReadyEvidence();') -and
 $runtime.Contains('managedReadyEvidenceUtc=next=="Ready"?DateTime.UtcNow:DateTime.MinValue;') -and
 $runtime.Contains('remoteSupervisor.ManagedStatus(managedProcess.Pid,true,managedState,managedDetail)')) 'Host checks stale readiness during normal refresh and publishes change'
Check ($observerSource.Contains('Test-Rc1ObservedReadyEvidenceExpired') -and
 $observerSource.Contains('$ob.State=') -and
 $observerSource.Contains('LastReadyProofTicks')) 'observer evaluates silent state without new log lines'
Write-Output ('RC1_READY_LOSS_FAIL_CLOSED_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
