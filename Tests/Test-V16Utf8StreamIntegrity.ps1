# G133 / P2 UTF-8 split regression. Uses only an isolated read-only log fixture.
# No installed launcher, real Remote, network, credentials or GUI are touched.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs') |
 ForEach-Object {Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @(
 'System.Core.dll','System.Web.Extensions.dll','System.Security.dll',
 'System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
. (Join-Path $src 'rc1-remote-observer.ps1')
$pass=0;$fail=0
function Check([bool]$value,[string]$label) {
 if($value){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$utf8=New-Object Text.UTF8Encoding($false,$false)
$wrench=[char]::ConvertFromUtf32(0x1F527)
$doneIcon=[string][char]0x2705
$start=$wrench+' Received tool call abc: read_file {"path":"C:\fixture\notes.txt"}'
$complete=$doneIcon+' Tool call abc completed:'
$sourceBytes=$utf8.GetBytes(($start+"`r`n"+$complete+"`r`n"))
$probeStart=Get-Rc1ObservedMarker $start
Check ($null -ne $probeStart -and $probeStart.Marker -ceq 'Remote tool started') 'actual Windows PowerShell observer parses Unicode marker literals'
$sourceType='RdcOwnerUtf8LogBuffer' -as [type]
Check ($null -ne $sourceType) 'production owned log decoder exists'
if($sourceType){
 foreach($slice in @(1,2,3,4,5,7,11,32768)){
  $decoder=[Activator]::CreateInstance($sourceType)
  $lines=New-Object 'System.Collections.Generic.List[string]'
  for($off=0;$off -lt $sourceBytes.Length;$off+=$slice){
   $count=[Math]::Min($slice,$sourceBytes.Length-$off)
   $out=[string[]]$decoder.Feed($sourceBytes,$off,$count)
   foreach($line in $out){$lines.Add($line)}
  }
  Check ($lines.Count -eq 2 -and $lines[0] -ceq $start -and
   $lines[1] -ceq $complete -and -not (($lines -join '').Contains([char]0xfffd))) ('owned byte splits '+$slice+' preserve tool start/completion')
 }
 # A dropped oversized partial line must not be reparsed from its suffix.
 $decoder=[Activator]::CreateInstance($sourceType)
 [void]$decoder.Feed($utf8.GetBytes('X'*9000),0,9000)
 $payload=$utf8.GetBytes(($start+"`n"+$start+"`n"))
 $recovered=[string[]]$decoder.Feed($payload,0,$payload.Length)
 Check ($recovered.Count -eq 1 -and $recovered[0] -ceq $start) 'owned oversize line ignored to newline, later good event preserved'
 # Place the first byte of the four-byte icon at the 32768-byte read
 # boundary of the actual Host FileStream polling window.
 $decoder=[Activator]::CreateInstance($sourceType)
 $boundary=$utf8.GetBytes((('x'+"`n")*16383)+"`n"+$start+"`n"+$complete+"`n")
 $first=[string[]]$decoder.Feed($boundary,0,32768)
 $second=[string[]]$decoder.Feed($boundary,32768,$boundary.Length-32768)
 Check ($first.Count -eq 16384 -and $second.Count -eq 2 -and
  $second[0] -ceq $start -and $second[1] -ceq $complete) 'exact owned 32KiB read-boundary does not split Unicode tool markers'
 $decoder.Reset()
 $half=$utf8.GetBytes($start)
 [void]$decoder.Feed($half,0,2)
 $reset=[string[]]$decoder.Feed($sourceBytes,0,$sourceBytes.Length)
 $decoder.Reset()
 $reset=[string[]]$decoder.Feed($sourceBytes,0,$sourceBytes.Length)
 Check ($reset.Count -eq 2 -and $reset[0] -ceq $start) 'owned reset discards incomplete old UTF-8 sequence'
 $journal=New-Object RdcOwnerToolJournal
 $supervisor=New-Object RdcOwnerRemoteState
 $supervisor.EnableManaged()
 $supervisor.ManagedStatus(9012,$true,'Ready','fixture only')
 $classifier=([RdcOwnerRuntime]).GetMethod('SafeRemoteMarker',
  [Reflection.BindingFlags]'Static,NonPublic')
 foreach($line in $reset){
  $argsForMarker=[object[]]@([string]$line,'')
  $marker=[string]$classifier.Invoke($null,$argsForMarker)
  if($marker -ne ''){
   $safe=$journal.Format($line,$marker)
   if($safe -ne ''){$supervisor.AddSyntheticLogLine($safe)}
  }
 }
 Check (($supervisor.Snapshot()).toolActivity -ceq 'hold' -and
  -not ($supervisor.Snapshot()).toolFault) 'owned sanitized start/completion pair clears active state to hold'
}
$oldIdentity=Get-Command Test-Rc1ObservedRemoteIdentity
Set-Item Function:\Test-Rc1ObservedRemoteIdentity {param([hashtable]$record) return $true}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-UTF8-P2-'+[Guid]::NewGuid().ToString('N')+'.log')
try{
 $state=New-Object RdcOwnerRemoteState
 $state.AttachObservedReadOnly(9021)
 $sink=[pscustomobject]@{
  Store=$state;Received=(New-Object 'System.Collections.Generic.List[string]');
  LastState=''
 }
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name UpdateObservedRemote -Value {
  param([bool]$alive,[string]$status,[string]$detail)
  $this.LastState=$status
  $this.Store.UpdateObservedReadOnly($alive,$status,$detail)
 }
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedToolLine -Value {
  param([string]$line)
  $this.Received.Add($line)
  if($line.StartsWith([char]::ConvertFromUtf32(0x1F527),[StringComparison]::Ordinal)){
   $this.Store.AddObservedMarker('Remote tool started')
  }elseif($line.StartsWith([string][char]0x2705,[StringComparison]::Ordinal)){
   $this.Store.AddObservedMarker('Remote tool completed')
  }else{
   $this.Store.AddObservedMarker('Remote tool failed')
  }
 }
 Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedMarker -Value {
  param([string]$safeMarker) $this.Store.AddObservedMarker($safeMarker)
 }
 $record=@{
  Pid=9021;Born=[long]1;Session=1;Parent=2;Log=$fixture;Exe='fixture';
  Offset=[long]0;Fragment='';DiscardFirst=$false;
  State='Ready';Detail='fresh fixture';LastReadyProofTicks=[DateTime]::UtcNow.Ticks
 }
 [IO.File]::WriteAllBytes($fixture,(New-Object byte[] 0))
 # Call the real observer polling path after each single byte append.
 for($i=0;$i -lt $sourceBytes.Length;$i++){
  $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
  try{$s.Write($sourceBytes,$i,1)}finally{$s.Dispose()}
  Invoke-Rc1RemoteObserverPoll $sink $record
 }
 $directBuffer=@{Fragment='';DiscardOversizedLine=$false}
 $directLines=@(Read-Rc1ObservedUtf8Lines $directBuffer $sourceBytes $sourceBytes.Length)
 $directByte=@{Fragment='';DiscardOversizedLine=$false}
 $directByteLines=New-Object 'System.Collections.Generic.List[string]'
 for($di=0;$di -lt $sourceBytes.Length;$di++){
  $one=New-Object byte[] 1;$one[0]=$sourceBytes[$di]
  foreach($line in @(Read-Rc1ObservedUtf8Lines $directByte $one 1)){$directByteLines.Add([string]$line)}
 }
 Check ($directByteLines.Count -eq 2 -and $directLines.Count -eq 2 -and
   $directByteLines[0] -ceq $start -and $directLines[1] -ceq $complete) 'PowerShell UTF-8 decoder returns identical lines for full and one-byte feeds'
 Check ($sink.Received.Count -eq 2 -and
  $sink.Received[0] -ceq $start -and $sink.Received[1] -ceq $complete) 'actual observed poll never loses split UTF-8 tool markers'
 Check (($sink.Store.Snapshot()).toolActivity -ceq 'hold' -and
  -not ($sink.Store.Snapshot()).toolFault -and $sink.LastState -ceq 'Ready') 'observed split completion clears active activity without fake disconnect'
 Check (-not (($sink.Received -join '').Contains([char]0xfffd))) 'observer has no replacement characters at UTF-8 chunk boundaries'
 # A completed tool call is not a channel heartbeat: the upstream result
 # upload follows the local completion log and may fail. Expire the old
 # link lease even when a new completed line is successfully decoded.
 $record.LastReadyProofTicks=[DateTime]::UtcNow.AddMinutes(-10).Ticks
 $freshCompletion=$utf8.GetBytes($complete+"`n")
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($freshCompletion,0,$freshCompletion.Length)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Reconnecting' -and
  [long]$record.LastReadyProofTicks -eq 0) 'completed observed call cannot renew expired Ready channel lease'
 # Only an explicit fresh connection line restores Ready.
 $online=$utf8.GetBytes("Desktop Commander Remote is connected`n")
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($online,0,$online.Length)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Ready' -and
  [long]$record.LastReadyProofTicks -gt [DateTime]::UtcNow.AddSeconds(-10).Ticks) 'fresh observer channel marker reestablishes Ready'
 $owned=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
 Check ($owned.Contains('managedLogStream.Feed(buffer,0,read)') -and
  $owned.Contains('managedLogStream.Reset()') -and
  $owned.Contains('managedReadyEvidenceUtc=next=="Ready"?DateTime.UtcNow:DateTime.MinValue;') -and
  -not $owned.Contains('ToolCompletionConfirmsReady')) 'managed decoder remains intact without tool-derived Ready proof'
 # Simulate a fragment exceeding 2048 without LF, followed by a fake tool
 # marker INSIDE that same physical line. It must never count as a tool call.
 $before=$sink.Received.Count
 $longBytes=$utf8.GetBytes('X'*9000)
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($longBytes,0,$longBytes.Length)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 $fakeByte=$utf8.GetBytes($start+"`n")
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($fakeByte,0,$fakeByte.Length)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($sink.Received.Count -eq $before) 'oversize partial observed line never becomes fake tool start'
 $goodByte=$utf8.GetBytes($start+"`n"+$complete+"`n")
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($goodByte,0,$goodByte.Length)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($sink.Received.Count -eq ($before+2) -and
   $sink.Received[$before] -ceq $start -and
   $sink.Received[$before+1] -ceq $complete) 'valid events after oversized line are not discarded'
 # Reset when the log rotates: any pending half codepoint must be discarded.
 $partial=$utf8.GetBytes($start)
 [IO.File]::WriteAllBytes($fixture,(New-Object byte[] 0))
 Invoke-Rc1RemoteObserverPoll $sink $record
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($partial,0,2)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 [IO.File]::WriteAllBytes($fixture,(New-Object byte[] 0))
 Invoke-Rc1RemoteObserverPoll $sink $record
 $s=[IO.File]::Open($fixture,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$s.Write($goodByte,0,$goodByte.Length)}finally{$s.Dispose()}
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($sink.Received.Count -eq ($before+4) -and
  $sink.Received[$before+2] -ceq $start) 'observed rotation resets partial UTF-8 and resumes only new events'
}catch{
 $fail++;Write-Output ('FAIL UTF8 fixture exception '+$_.Exception.Message)
}finally{
 if([IO.File]::Exists($fixture)){[IO.File]::Delete($fixture)}
 Set-Item Function:\Test-Rc1ObservedRemoteIdentity $oldIdentity.ScriptBlock
}
Write-Output ('RC1_UTF8_STREAM_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
