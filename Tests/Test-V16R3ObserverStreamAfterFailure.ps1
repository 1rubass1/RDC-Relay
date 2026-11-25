# R2-003-F1: exercise production observer poll on partial lines across
# FileShare.None failures and consumed-byte failures, without real Remote.
# -PackagedObserverPath verifies the exact private RC1 package independently.
param([string]$PackagedObserverPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$observerPath=Join-Path $repo 'Source\rc1-remote-observer.ps1'
if($PackagedObserverPath){
 $candidate=[IO.Path]::GetFullPath($PackagedObserverPath)
 $dist=[IO.Path]::GetFullPath((Join-Path $repo 'dist')).TrimEnd([char]92)
 if(-not $candidate.StartsWith($dist+[IO.Path]::DirectorySeparatorChar,
     [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($candidate) -cne 'rc1-remote-observer.ps1' -or
    [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($candidate)) -cne 'Source' -or
    [IO.Path]::GetFileName([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($candidate))) -cne 'package'){
   throw 'R3_PACKAGED_OBSERVER_SCOPE_REFUSED'
 }
 if(-not [IO.File]::Exists($candidate) -or
    ([IO.File]::GetAttributes($candidate) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw 'R3_PACKAGED_OBSERVER_MISSING_OR_LINKED'
 }
 $observerPath=$candidate
}
. $observerPath
Set-Item Function:\Test-Rc1ObservedRemoteIdentity {param([hashtable]$record) return $true}
$utf8=New-Object Text.UTF8Encoding($false)
$log=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)) ('RDC-RC1-R3-PARTIAL-'+[Guid]::NewGuid().ToString('N')+'.log')
$pass=0;$fail=0
function Check([bool]$v,[string]$label){
 if($v){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function NewRecord([string]$state){
 return @{Pid=7771;Born=[long]1;Session=1;Parent=0;Exe='R3 test fixture';
  Log=$script:log;Offset=[long]0;Fragment='';DiscardFirst=$false;
  DiscardOversizedLine=$false;State=$state;Detail='unconfirmed';
  LastReadyProofTicks=[long]0}
}
$sink=[pscustomobject]@{
 State='Fault';Markers=(New-Object 'System.Collections.Generic.List[string]');
 ToolLines=(New-Object 'System.Collections.Generic.List[string]');Faults=0;
 FailNextMarker=$false}
Add-Member -InputObject $sink -MemberType ScriptMethod -Name UpdateObservedRemote -Value {
 param([bool]$alive,[string]$state,[string]$detail)
 $this.State=$state
 if($state -ceq 'Fault'){$this.Faults++}
}
Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedMarker -Value {
 param([string]$marker)
 if($this.FailNextMarker){$this.FailNextMarker=$false;throw 'R3_INJECTED_CALLBACK_FAILURE'}
 $this.Markers.Add($marker)
}
Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedToolLine -Value {
 param([string]$line) $this.ToolLines.Add($line)
}
function SetInput([byte[]]$bytes){
 [IO.File]::WriteAllBytes($script:log,$bytes)
 $script:sink.State='Fault';$script:sink.Markers.Clear();$script:sink.ToolLines.Clear()
}
function AppendInput([byte[]]$bytes){
 $stream=[IO.File]::Open($script:log,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
}
function PollWithLock([hashtable]$record){
 $lock=[IO.File]::Open($script:log,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{Invoke-Rc1RemoteObserverPoll $script:sink $record}finally{$lock.Dispose()}
}
try{
 # The exact proof from Reviewer 2, including the actual Windows sharing violation.
 $prefix='{"message":"'
 $suffix='Desktop Commander Remote is connected"}'+"`n"
 SetInput ($utf8.GetBytes($prefix))
 $record=NewRecord 'Fault'
 Invoke-Rc1RemoteObserverPoll $sink $record
 $before=[string]$record.Fragment
 $offset=[long]$record.Offset
 Check ($before -ceq $prefix -and $offset -eq $utf8.GetByteCount($prefix)) 'fragment and offset saved after partial JSON prefix'
 PollWithLock $record
 Check ($sink.State -ceq 'Fault' -and $record.State -ceq 'Fault' -and
  [long]$record.LastReadyProofTicks -eq 0 -and
  [long]$record.Offset -eq $offset) 'sharing violation latches Fault and keeps file cursor'
 Check ([string]$record.Fragment -ceq $prefix) 'failed open retains buffered JSON prefix'
 AppendInput ($utf8.GetBytes($suffix))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Fault' -and $sink.State -ceq 'Fault' -and
  $sink.Markers.Count -eq 0 -and [long]$record.LastReadyProofTicks -eq 0) 'JSON suffix cannot become top-level Ready after read error'
 AppendInput ($utf8.GetBytes("Desktop Commander Remote is connected`n"))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Ready' -and $sink.State -ceq 'Ready' -and
  $sink.Markers.Count -eq 1 -and
  [long]$record.LastReadyProofTicks -gt [DateTime]::UtcNow.AddSeconds(-15).Ticks) 'complete fresh channel marker after JSON restores Ready'

 # R2-002-F2 must remain closed with no buffered content.
 SetInput (New-Object byte[] 0)
 $record=NewRecord 'Ready'
 $record.LastReadyProofTicks=[DateTime]::UtcNow.Ticks
 PollWithLock $record
 Check ($record.State -ceq 'Fault' -and $sink.State -ceq 'Fault' -and
  [long]$record.LastReadyProofTicks -eq 0) 'locked empty log invalidates old Ready evidence'
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Fault' -and $sink.State -ceq 'Fault') 'empty unlocked poll still Fault'
 AppendInput ($utf8.GetBytes("Desktop Commander Remote is connected`n"))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Ready' -and $sink.State -ceq 'Ready') 'read access restored plus genuinely new Ready may recover'

 # The decoder may hold incomplete 4-byte Unicode, not just a text Fragment.
 $start=[char]::ConvertFromUtf32(0x1F527)+' Received tool call r3: read_file {}'
 $startBytes=$utf8.GetBytes($start+"`n")
 SetInput ([byte[]]$startBytes[0..1])
 $record=NewRecord 'Fault'
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($sink.ToolLines.Count -eq 0) 'partial 4-byte tool prefix waits for remaining UTF8 bytes'
 PollWithLock $record
 AppendInput ([byte[]]$startBytes[2..($startBytes.Length-1)])
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($sink.ToolLines.Count -eq 1 -and
  $sink.ToolLines[0] -ceq $start -and
  $record.State -ceq 'Fault') 'split UTF8 marker survives read error but never establishes Ready'
 Check (-not (($sink.ToolLines -join '').Contains([char]0xfffd))) 'no replacement Unicode after partial UTF8 plus IOException'

 # Existing oversized-physical-line suppression must remain in force across
 # a lock even when the newline arrives in a later polling cycle.
 SetInput ($utf8.GetBytes('X'*9000))
 $record=NewRecord 'Fault'
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ([bool]$record.DiscardOversizedLine) 'oversized physical line is in drop-until-LF state'
 PollWithLock $record
 AppendInput ($utf8.GetBytes("Desktop Commander Remote is connected`n"))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Fault' -and $sink.Markers.Count -eq 0) 'oversized line suffix never becomes a channel status'
 AppendInput ($utf8.GetBytes("Desktop Commander Remote is connected`n"))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Ready' -and $sink.Markers.Count -eq 1) 'valid marker after oversized line recovers'

 # An exception AFTER bytes have been consumed (e.g. failed sanitized owner
 # callback) is different from FileShare.None: cursor and decoder may be
 # incoherent. Drop only the remainder of that physical line.
 SetInput ($utf8.GetBytes("Channel closed`n"+$prefix))
 $record=NewRecord 'Ready'
 $record.LastReadyProofTicks=[DateTime]::UtcNow.Ticks
 $sink.FailNextMarker=$true
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Fault' -and $sink.State -ceq 'Fault' -and
  [long]$record.Offset -eq $utf8.GetByteCount("Channel closed`n"+$prefix)) 'consumed-byte callback fault invalidates transport readiness'
 Check (-not [bool]$record.DiscardOversizedLine -and
  [string]$record.Fragment -ceq $prefix -and
  ($null -eq $record.PendingLines -or ($record.PendingLines.Count-[int]$record.PendingLineIndex) -eq 0)) 'framed complete-line callback failure retains partial JSON physical line'
 AppendInput ($utf8.GetBytes($suffix))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Fault' -and $sink.Markers.Count -eq 0) 'consumed-byte failure cannot turn JSON remainder into Ready'
 AppendInput ($utf8.GetBytes("Desktop Commander Remote is connected`n"))
 Invoke-Rc1RemoteObserverPoll $sink $record
 Check ($record.State -ceq 'Ready' -and $sink.Markers.Count -eq 1) 'subsequent complete top-level status recovers after guarded skip'
}catch{
 $fail++
 Write-Output ('FAIL R3_SEQUENCE_EXCEPTION '+$_.Exception.Message)
}finally{
 if([IO.File]::Exists($log)){
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  if([IO.Path]::GetDirectoryName($log) -cne $temp -or
     [IO.Path]::GetFileName($log) -cnotmatch '^RDC-RC1-R3-PARTIAL-[a-f0-9]{32}\.log$' -or
     ([IO.File]::GetAttributes($log) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   $fail++;Write-Output 'FAIL R3_CLEANUP_REFUSED'
  }else{
   [IO.File]::Delete($log)
   Check (-not [IO.File]::Exists($log)) 'R3 disposable log removed without touching user Remote'
  }
 }
}
Write-Output ('RC1_R3_PARTIAL_STREAM_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
