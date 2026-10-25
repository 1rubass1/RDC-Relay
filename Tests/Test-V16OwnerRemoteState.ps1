# Product Host state and fake TextReader tests, no OS process spawn.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Add-Type -Path @((Join-Path $root 'Source\RdcOwnerProcess.cs'),(Join-Path $root 'Source\RdcOwnerRemoteState.cs')) -ReferencedAssemblies @('System.Core.dll','System.dll')
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){if($ok){$script:pass++;Write-Output ('PASS '+$name)}else{$script:fail++;Write-Output ('FAIL '+$name)}}
try{
 $s=New-Object RdcOwnerRemoteState
 $a=$s.Snapshot()
 Check ($a.fake -and -not $a.isActualRemote -and $a.ownership -eq 'Unknown') 'default Unknown fake-only'
 Check ($a.canStop -eq $false -and $a.canReconnect -eq $false -and $a.canStart -eq $false -and $a.canUpdate -eq $false) 'mutating controls denied'
 $sameId=$s.SessionId
 $s.AcceptFakeObservation('Connecting','Fake startup')
 Check (($s.Snapshot()).state -eq 'Connecting') 'fake connecting tracked'
 $s.AcceptFakeObservation('AuthPending','Fake authorization')
 Check (($s.Snapshot()).authState -eq 'FAKE_AUTH') 'fake auth state tracked'
 $s.AcceptFakeObservation('Ready','Fake ready; never real connected')
 Check (($s.Snapshot()).transportReady -eq 'FAKE_READY' -and -not ($s.Snapshot()).isActualRemote) 'ready never interpreted as actual Remote'
 $threw=$false;try{$s.AcceptFakeObservation('OWNED_AND_KILL','bad')}catch{$threw=$true}
 Check $threw 'unknown state rejects'
 $lines=New-Object IO.StringReader -ArgumentList ([string]::Join([Environment]::NewLine,@('alpha','beta','gamma')))
 $count=$s.PumpReader($lines,2)
 Check ($count -eq 2 -and ($s.Snapshot()).logCursor -eq 2) 'bounded fake reader cursor'
 Check ($s.PumpReader($lines,2) -eq 1 -and ($s.Snapshot()).logCursor -eq 3) 'incremental fake reader no replay'
 $items=@(($s.Snapshot()).tail)
 Check ($items.Count -eq 3 -and $items[0].Contains('alpha') -and $items[2].Contains('gamma')) 'log tail retains order'
 for($i=0;$i -lt 100;$i++){$s.AddSyntheticLogLine(('line-{0:d3}' -f $i))}
 Check (@(($s.Snapshot()).tail).Count -eq 64) 'bounded log tail'
 $oldEpoch=[long]($s.Snapshot()).logStreamEpoch
 $s.ResetFakeLogStream()
 Check (($s.Snapshot()).logStreamEpoch -eq ($oldEpoch+1) -and ($s.Snapshot()).logCursor -eq 0) 'fake log rotation cursor'
 Check ($s.SessionId -ceq $sameId) 'session unchanged through log rotation'
 $s.ClassifyReadOnly([RdcRelay.Owner.Ownership]::Adopted,$null,$null)
 Check (($s.Snapshot()).ownership -eq 'Adopted' -and -not $s.CanStop()) 'Adopted read only'
 $s.ClassifyReadOnly([RdcRelay.Owner.Ownership]::Owned,$null,$null)
 Check (($s.Snapshot()).ownership -eq 'Unknown' -and -not $s.CanStop()) 'unverified Owned becomes Unknown'
 $e=New-Object RdcRelay.Owner.ProcessEvidence -ArgumentList @(11,4444444,2,10,'C:\fixture\tool.exe','C:\fixture',[Guid]::NewGuid().ToString('N'),[RdcRelay.Owner.Ownership]::Owned)
 $s.ClassifyReadOnly([RdcRelay.Owner.Ownership]::Owned,$e,$e)
 Check (($s.Snapshot()).ownership -eq 'Owned' -and -not $s.CanStop()) 'synthetic Owned still refuses stop'
 $threw=$false;try{$s.RequireSafeStop()}catch{$threw=($_.Exception.Message -match 'RC1_STOP_BLOCKED')}
 Check $threw 'full Remote stop fail closed'
 $s.AcceptFakeObservation('Fault','synthetic failure')
 Check (($s.Snapshot()).state -eq 'Fault' -and -not $s.CanStop()) 'fault status-only'
 $s.AcceptFakeObservation('Reconnecting','synthetic telemetry')
 Check (($s.Snapshot()).state -eq 'Reconnecting' -and -not $s.CanStop()) 'reconnect telemetry not process operation'
 $observed=New-Object RdcOwnerRemoteState
 $observed.AddSyntheticLogLine('fake banner must disappear')
 $before=[long]($observed.Snapshot()).logStreamEpoch
 $observed.AttachObservedReadOnly(23)
 $snapshot=$observed.Snapshot()
 Check ($snapshot.ownership -eq 'Adopted' -and $snapshot.isActualRemote -and
   $snapshot.processPid -eq 23 -and -not $snapshot.canStop) 'observed attach never grants Remote control'
 Check ($snapshot.logStreamEpoch -gt $before -and @($snapshot.tail).Count -eq 0) 'actual attach drops fake startup line'
 $observed.UpdateObservedReadOnly($true,'Ready','Observed health evidence only')
 $observed.AddObservedMarker('Remote connected')
 Check (($observed.Snapshot()).transportReady -eq 'OBSERVED_READY' -and
   ($observed.Snapshot()).logCursor -eq 1) 'real read-only health and sanitized journal'
 $oldEpoch=[long]($observed.Snapshot()).logStreamEpoch
 $observed.RetargetObservedReadOnly(45)
 $snapshot=$observed.Snapshot()
 Check ($snapshot.processPid -eq 45 -and $snapshot.ownership -eq 'Adopted' -and
   $snapshot.logStreamEpoch -eq ($oldEpoch+1) -and $snapshot.logCursor -eq 0 -and
   @($snapshot.tail).Count -eq 0) 'replacement launcher rotates journal and stays Adopted'
 $observed.AddObservedMarker('Remote launcher replaced')
 Check (($observed.Snapshot()).canStop -eq $false -and
   ($observed.Snapshot()).canReconnect -eq $false) 'reacquired launcher cannot be stopped or reconnected'
}catch{$fail++;Write-Output ('FAIL exception '+$_.Exception.Message)}
Write-Output ('RC1_OWNER_REMOTE_STATE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
