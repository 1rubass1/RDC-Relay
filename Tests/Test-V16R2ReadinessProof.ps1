# R2-002-F1/F2 exact production managed/observed log sequencing.
# Runs a short-lived inert owned Job and strictly disposable fake logs only.
# NO real Remote, GUI, authentication, network, installer or installed files.
# -PackagedRuntimeDll optionally exercises the exact private build DLL and its
# matching packaged observer source, without launching the packaged EXEs.
param([string]$PackagedRuntimeDll='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$src=Join-Path $repo 'Source'
if($PackagedRuntimeDll){
 $packaged=[IO.Path]::GetFullPath($PackagedRuntimeDll)
 $dist=[IO.Path]::GetFullPath((Join-Path $repo 'dist')).TrimEnd([char]92)
 if(-not $packaged.StartsWith($dist+[IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($packaged) -cne 'RdcOwnerRuntime.dll' -or
    [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($packaged)) -cne 'package'){
  throw 'R2_PACKAGED_DLL_SCOPE_REFUSED'
 }
 if(-not [IO.File]::Exists($packaged) -or
    ([IO.File]::GetAttributes($packaged) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'R2_PACKAGED_DLL_MISSING_OR_LINKED'
 }
 $src=Join-Path ([IO.Path]::GetDirectoryName($packaged)) 'Source'
 if(-not [IO.File]::Exists((Join-Path $src 'rc1-remote-observer.ps1'))){
  throw 'R2_PACKAGED_OBSERVER_ABSENT'
 }
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
 [void][Reflection.Assembly]::LoadFrom($packaged)
}else{
 $parts=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
  'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs') |
  ForEach-Object{Join-Path $src $_}
 Add-Type -Path $parts -ReferencedAssemblies @(
  'System.Core.dll','System.Web.Extensions.dll','System.Security.dll',
  'System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
}
. (Join-Path $src 'rc1-remote-observer.ps1')
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$utf8=New-Object Text.UTF8Encoding($false)
$completed=[string][char]0x2705+' Tool call read_file completed: ok'
$failed=[char]::ConvertFromUtf32(0x274C)+' Tool call read_file failed: result upload failed'
$started=[char]::ConvertFromUtf32(0x1F527)+' Received tool call case-1: read_file {}'
$root=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)) ('RDC-RC1-R2-READINESS-'+[Guid]::NewGuid().ToString('N'))
$dummy=Join-Path $root 'npx.cmd'
$jobLog=Join-Path $root 'job.log'
$managedLog=Join-Path $root 'managed.log'
$observedLog=Join-Path $root 'observed.log'
$job=$null;$ownerReady=$false
$instanceFlags=[Reflection.BindingFlags]'Instance,NonPublic'
$refresh=([RdcOwnerRuntime]).GetMethod('RefreshManagedRemote',$instanceFlags)
function SetPrivate([object]$target,[string]$field,[object]$value){
 $slot=$target.GetType().GetField($field,$script:instanceFlags)
 if(-not $slot){throw ('MISSING_PRIVATE_FIELD '+$field)}
 $slot.SetValue($target,$value)
}
function GetPrivate([object]$target,[string]$field){
 return $target.GetType().GetField($field,$script:instanceFlags).GetValue($target)
}
function NewManagedReader([string]$initial,[datetime]$proof){
 $runtime=[Runtime.Serialization.FormatterServices]::GetUninitializedObject([RdcOwnerRuntime])
 $state=New-Object RdcOwnerRemoteState
 $state.EnableManaged()
 $state.ManagedStatus($script:job.Pid,$true,$initial,'R2 synthetic private link proof')
 SetPrivate $runtime 'managedMode' $true
 SetPrivate $runtime 'managedProcess' $script:job
 SetPrivate $runtime 'managedState' $initial
 SetPrivate $runtime 'managedLogPath' $script:managedLog
 SetPrivate $runtime 'managedLogStream' (New-Object RdcOwnerUtf8LogBuffer)
 SetPrivate $runtime 'managedReadyEvidenceUtc' $proof
 SetPrivate $runtime 'managedLogOffset' ([long]0)
 SetPrivate $runtime 'managedStartupComplete' $true
 SetPrivate $runtime 'managedBannerScanned' 100
 SetPrivate $runtime 'remoteSupervisor' $state
 SetPrivate $runtime 'toolJournal' (New-Object RdcOwnerToolJournal)
 SetPrivate $runtime 'events' (New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[string,object]]')
 SetPrivate $runtime 'managedBannerArt' (New-Object 'System.Collections.Generic.List[string]')
 SetPrivate $runtime 'managedStartupHeader' (New-Object 'System.Collections.Generic.List[string]')
 return [pscustomobject]@{Runtime=$runtime;State=$state}
}
function OwnedCase([string]$name,[string]$lines,[string]$initial,[datetime]$proof,
                   [string]$expectedState,[int]$expectedCount){
 [IO.File]::WriteAllText($script:managedLog,$lines,$script:utf8)
 $test=NewManagedReader $initial $proof
 for($i=0;$i -lt 2;$i++){
  [void]$script:refresh.Invoke($test.Runtime,@())
 }
 $snapshot=$test.State.Snapshot()
 Check ($snapshot.state -ceq $expectedState -and $snapshot.tail.Count -eq $expectedCount) ('managed '+$name+' expected '+$expectedState+' got '+$snapshot.state+' events='+$snapshot.tail.Count)
 return $test
}
$allowedFiles=@('npx.cmd','job.log','managed.log','observed.log')
try{
 [void][IO.Directory]::CreateDirectory($root)
 # Local dummy npx.cmd: its contents ignore all npm/Remote arguments.
 # Its only child is a sleeping local PowerShell process in a scoped Job.
 [IO.File]::WriteAllText($dummy,'@echo off'+"`r`n"+
  '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 90"'+"`r`n",
  [Text.Encoding]::ASCII)
 [IO.File]::WriteAllText($observedLog,'',$utf8)
 $job=New-Object RdcOwnerManagedProcess
 $job.Start($dummy,'--yes @wonderwhy-er/desktop-commander@latest remote',$root,$jobLog)
 if(-not $job.Running){throw 'FAKE_ONLY_JOB_FAILED'}
 $ownerReady=$true
 $now=[DateTime]::UtcNow
 $reader=OwnedCase 'closed then local completion' ("Channel closed`n"+$completed+"`n") 'Ready' $now 'Fault' 2
 Check ((GetPrivate $reader.Runtime 'managedReadyEvidenceUtc') -eq [DateTime]::MinValue) 'managed disconnect revokes link proof despite completion'
 $null=OwnedCase 'expired session then local completion' ("Remote session expired and could not be renewed.`n"+$completed+"`n") 'Ready' $now 'Fault' 2
 $null=OwnedCase 'closed then completion then failed upload' ("Channel closed`n"+$completed+"`n"+$failed+"`n") 'Ready' $now 'Fault' 3
 $null=OwnedCase 'completion before close control' ($completed+"`nChannel closed`n") 'Ready' $now 'Fault' 2
 $null=OwnedCase 'connecting then completion does not prove readiness' ($completed+"`n") 'Connecting' ([DateTime]::MinValue) 'Connecting' 1
 $old=$now.AddMinutes(-10)
 $reader=OwnedCase 'expired Ready lease then completion still unconfirmed' ($completed+"`n") 'Ready' $old 'Reconnecting' 1
 Check ((GetPrivate $reader.Runtime 'managedReadyEvidenceUtc') -eq [DateTime]::MinValue) 'managed stale completion never renews expired lease'
 $reader=OwnedCase 'active Ready tool completion does not renew proof' ($completed+"`n") 'Ready' $now 'Ready' 1
 Check ((GetPrivate $reader.Runtime 'managedReadyEvidenceUtc').Ticks -eq $now.Ticks) 'managed completion does not extend still-valid ready lease'
 $reader=OwnedCase 'new connection after loss legitimately restores Ready' ("Channel closed`n"+$completed+"`nDesktop Commander Remote is connected`n") 'Ready' $now 'Ready' 3
 Check ((GetPrivate $reader.Runtime 'managedReadyEvidenceUtc') -gt [DateTime]::UtcNow.AddSeconds(-20)) 'managed new channel evidence renews proof'
 # Replay the observed 0.3.4 console framing through actual managed UTF-8 parsing.
 $stamp='[23:27:08] '
 $ready=[char]0x2705+' Device ready:'
 $null=OwnedCase 'timestamped authorization pending' ($stamp+"Waiting for authorization"+[Environment]::NewLine) 'Connecting' ([DateTime]::MinValue) 'AuthPending' 1
 $null=OwnedCase 'timestamped ready' ($stamp+$ready+[Environment]::NewLine) 'AuthPending' ([DateTime]::MinValue) 'Ready' 1
 $null=OwnedCase 'timestamped ready then channel closed' ($stamp+$ready+[Environment]::NewLine+$stamp+'Channel closed'+[Environment]::NewLine) 'Connecting' ([DateTime]::MinValue) 'Fault' 2
 $null=OwnedCase 'timestamped tool completion never restores ready' ($stamp+$completed+[Environment]::NewLine) 'Connecting' ([DateTime]::MinValue) 'Connecting' 1
 # Observe the actual PowerShell file-poll path. The only stub replaces
 # the OS identity detector; the mounted user Remote is never queried.
 Set-Item Function:\Test-Rc1ObservedRemoteIdentity {param([hashtable]$record) return $true}
 $sink=[pscustomobject]@{State='';Detail='';ToolLines=(New-Object 'System.Collections.Generic.List[string]')}
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name UpdateObservedRemote -Value {
  param([bool]$alive,[string]$state,[string]$detail)
  $this.State=$state;$this.Detail=$detail
 }
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedMarker -Value {param([string]$marker)}
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedToolLine -Value {
  param([string]$line) $this.ToolLines.Add($line)
 }
 $ob=@{Pid=77777;Born=[long]1;Session=1;Parent=0;Log=$observedLog;Exe='R2 fixture';
   Offset=[long]0;Fragment='';DiscardFirst=$false;LastReadyProofTicks=[DateTime]::UtcNow.Ticks;
   State='Ready';Detail='R2 synthetic confirmed state'}
 $locked=[IO.File]::Open($observedLog,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{
  Invoke-Rc1RemoteObserverPoll $sink $ob
  Check ($sink.State -ceq 'Fault' -and $ob.State -ceq 'Fault' -and
   [long]$ob.LastReadyProofTicks -eq 0) 'observer read error revokes internal and public Ready and proof'
 }finally{$locked.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $ob
 Check ($sink.State -ceq 'Fault' -and $ob.State -ceq 'Fault') 'observer empty successful poll cannot resurrect Ready'
 [IO.File]::AppendAllText($observedLog,$completed+"`n",$utf8)
 Invoke-Rc1RemoteObserverPoll $sink $ob
 Check ($sink.State -ceq 'Fault' -and $ob.State -ceq 'Fault' -and
  $sink.ToolLines.Count -eq 1) 'observer completed after read failure stays Fault, tool logged'
 [IO.File]::AppendAllText($observedLog,"Remote session expired and could not be renewed.`n"+$completed+"`n",$utf8)
 Invoke-Rc1RemoteObserverPoll $sink $ob
 Check ($sink.State -ceq 'Fault' -and $ob.State -ceq 'Fault') 'observer expired session then completion stays Fault'
 [IO.File]::AppendAllText($observedLog,"Desktop Commander Remote is connected`n",$utf8)
 Invoke-Rc1RemoteObserverPoll $sink $ob
 Check ($sink.State -ceq 'Ready' -and $ob.State -ceq 'Ready' -and
  [long]$ob.LastReadyProofTicks -gt [DateTime]::UtcNow.AddSeconds(-20).Ticks) 'observer only new channel evidence restores Ready'
 [IO.File]::AppendAllText($observedLog,"Channel closed`n"+$completed+"`n"+$failed+"`n",$utf8)
 Invoke-Rc1RemoteObserverPoll $sink $ob
 Check ($sink.State -ceq 'Fault' -and $ob.State -ceq 'Fault' -and
  [long]$ob.LastReadyProofTicks -eq 0) 'observer closed then completed then failed upload stays Fault'
 [IO.File]::AppendAllText($observedLog,"Desktop Commander Remote is connected`n",$utf8)
 Invoke-Rc1RemoteObserverPoll $sink $ob
 $proofTicks=[long]$ob.LastReadyProofTicks
 [IO.File]::AppendAllText($observedLog,$started+"`n"+$completed+"`n",$utf8)
 Invoke-Rc1RemoteObserverPoll $sink $ob
 Check ($sink.State -ceq 'Ready' -and [long]$ob.LastReadyProofTicks -eq $proofTicks) 'observer connected tool run does not refresh transport lease'
 # End-to-end classification is not a precondition for activity observation.
 Check ($sink.ToolLines.Count -ge 5) 'observer retains separate tool start/completion/failure journal'
}catch{
 $fail++;Write-Output ('FAIL R2 fixture exception '+$_.Exception.Message)
}finally{
 if($job){
  $stopped=$job.StopOwnedOnly(10000)
  Check ($stopped -and -not $job.Running) 'fake-only owned Job stopped without touching other processes'
  $job.Dispose()
 }
 if([IO.Directory]::Exists($root)){
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  try{
   if([IO.Path]::GetDirectoryName($root) -cne $temp -or
      [IO.Path]::GetFileName($root) -cnotmatch '^RDC-RC1-R2-READINESS-[a-f0-9]{32}$'){
    throw 'R2_TEST_CLEANUP_SCOPE_REFUSED'
   }
   $entries=@([IO.Directory]::GetFileSystemEntries($root))
   foreach($entry in $entries){
    $attr=[IO.File]::GetAttributes($entry)
    if(([IO.Path]::GetFileName($entry) -cnotin $allowedFiles) -or
       ($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       ($attr -band [IO.FileAttributes]::Directory) -ne 0){
     throw ('R2_TEST_CLEANUP_UNTRUSTED_MEMBER '+$entry)
    }
   }
   if($job -and $job.Running){throw 'R2_TEST_STILL_RUNNING_REFUSED'}
   foreach($entry in $entries){[IO.File]::Delete($entry)}
   [IO.Directory]::Delete($root,$false)
   Check (-not [IO.Directory]::Exists($root)) 'exact test fixture removed with no survivors'
  }catch{$fail++;Write-Output ('FAIL R2 cleanup '+$_.Exception.Message)}
 }
}
Write-Output ('RC1_R2_READINESS_PROOF_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
