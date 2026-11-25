# R2-003 follow-up: a failed callback must not discard complete
# status/tool lines already decoded from a bounded Observer file-read batch.
# Actual FileStream, UTF-8 parser and production poll; fake PID only.
param([string]$PackagedObserverPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'Source\rc1-remote-observer.ps1'
if($PackagedObserverPath){
 $candidate=[IO.Path]::GetFullPath($PackagedObserverPath)
 $dist=[IO.Path]::GetFullPath((Join-Path $repo 'dist')).TrimEnd([char]92)
 if(-not $candidate.StartsWith($dist+[IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($candidate) -cne 'rc1-remote-observer.ps1' -or
    [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($candidate)) -cne 'Source' -or
    [IO.Path]::GetFileName([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($candidate))) -cne 'package'){
  throw 'R3_BATCH_PACKAGED_OBSERVER_SCOPE_REFUSED'
 }
 if(-not [IO.File]::Exists($candidate) -or
    ([IO.File]::GetAttributes($candidate) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'R3_BATCH_PACKAGED_OBSERVER_REFUSED'
 }
 $source=$candidate
}
. $source
Set-Item Function:\Test-Rc1ObservedRemoteIdentity {param([hashtable]$record) return $true}
$utf8=New-Object Text.UTF8Encoding($false)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$log=Join-Path $temp ('RDC-RC1-R3-BUFFERED-'+[Guid]::NewGuid().ToString('N')+'.log')
$pass=0;$fail=0
function Check([bool]$yes,[string]$label){
 if($yes){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$sink=[pscustomobject]@{
 LastState='';LastDetail='';
 Markers=(New-Object 'System.Collections.Generic.List[string]');
 Tools=(New-Object 'System.Collections.Generic.List[string]');
 ThrowNextMarker=$false;ThrowNextTool=$false
}
Add-Member -InputObject $sink -MemberType ScriptMethod -Name UpdateObservedRemote -Value {
 param([bool]$alive,[string]$state,[string]$detail)
 $this.LastState=$state;$this.LastDetail=$detail
}
Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedMarker -Value {
 param([string]$marker)
 if($this.ThrowNextMarker){$this.ThrowNextMarker=$false;throw 'R3_FAKE_OWNER_CALLBACK_FAULT'}
 $this.Markers.Add($marker)
}
Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedToolLine -Value {
 param([string]$line)
 if($this.ThrowNextTool){$this.ThrowNextTool=$false;throw 'R3_FAKE_TOOL_CALLBACK_FAULT'}
 $this.Tools.Add($line)
}
function ResetFixture([string]$contents,[string]$state='Ready'){
 [IO.File]::WriteAllText($script:log,$contents,$script:utf8)
 $script:sink.Markers.Clear();$script:sink.Tools.Clear()
 $script:sink.ThrowNextMarker=$false;$script:sink.ThrowNextTool=$false
 $script:sink.LastState=''
 return @{Pid=7321;Born=[long]1;Session=1;Parent=2;Log=$script:log;Exe='R3 fake';
  Offset=[long]0;Fragment='';DiscardFirst=$false;State=$state;Detail='fixture';
  LastReadyProofTicks=$(if($state -ceq 'Ready'){[DateTime]::UtcNow.Ticks}else{[long]0})}
}
function Poll([hashtable]$rec){Invoke-Rc1RemoteObserverPoll $script:sink $rec}
function Append([string]$text){[IO.File]::AppendAllText($script:log,$text,$script:utf8)}
function LockPoll([hashtable]$rec){
 $handle=[IO.File]::Open($script:log,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{Poll $rec}finally{$handle.Dispose()}
}
$ready="Desktop Commander Remote is connected`n"
$closed="Channel closed`n"
$start=[char]::ConvertFromUtf32(0x1F527)+' Received tool call r3: read_file {}'
$completed=[string][char]0x2705+' Tool call r3 completed: ok'
$prefix='{"message":"'
$suffix='Desktop Commander Remote is connected"}'+"`n"
try{
 # Batch contains TWO COMPLETE physical lines when the owner callback fails.
 # Exactly the first following Ready must restore the channel on next poll.
 $rec=ResetFixture ($closed+$ready)
 $sink.ThrowNextMarker=$true
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and $sink.LastState -ceq 'Fault' -and
  [long]$rec.Offset -eq $utf8.GetByteCount($closed+$ready)) 'callback error after completed line latches Fault, offset is after full batch'
 Check ($null -ne $rec.PendingLines -and
  ($rec.PendingLines.Count-[int]$rec.PendingLineIndex) -eq 1) 'already-decoded first following Ready remains pending'
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.LastState -ceq 'Ready' -and
  $sink.Markers.Count -eq 1 -and [long]$rec.LastReadyProofTicks -gt 0) 'first following complete Ready accepted without a second marker'
 Poll $rec
 Check ($sink.Markers.Count -eq 1) 'queued Ready is delivered exactly once'

 # If the private log is temporarily locked while a completed status is
 # already pending, it must remain queued until the next successful poll.
 $rec=ResetFixture ($closed+$ready)
 $sink.ThrowNextMarker=$true
 Poll $rec
 LockPoll $rec
 Check ($rec.State -ceq 'Fault' -and $sink.Markers.Count -eq 0) 'file sharing failure cannot use pending status during failed read'
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Markers.Count -eq 1) 'pending Ready survives transient lock and is used immediately on unlock'

 # Several independent complete messages follow the failing callback in
 # the SAME file read. No byte loss, no duplicated tool lines, stable order.
 $rec=ResetFixture ($closed+$start+"`n"+$completed+"`n"+$ready)
 $sink.ThrowNextMarker=$true
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and $sink.Tools.Count -eq 0) 'callback error stops publishing batch and fails closed'
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Markers.Count -eq 1 -and
  $sink.Tools.Count -eq 2 -and $sink.Tools[0] -ceq $start -and
  $sink.Tools[1] -ceq $completed) 'completed tool and first Ready in same consumed batch are preserved in order'
 Poll $rec
 Check ($sink.Tools.Count -eq 2 -and $sink.Markers.Count -eq 1) 'no completed event or Ready duplicate on later polls'

 # One full line fails, followed by an incomplete JSON physical line.
 # The offset and buffered prefix must remain coherent after callback fault.
 $rec=ResetFixture ($closed+$prefix)
 $sink.ThrowNextMarker=$true
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and
  [string]$rec.Fragment -ceq $prefix) 'post-callback failure preserves already-decoded incomplete JSON prefix'
 Append $suffix
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and $sink.Markers.Count -eq 0) 'JSON suffix after completed-line callback error cannot establish false Ready'
 Append $ready
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Markers.Count -eq 1) 'first real complete Ready after JSON suffix is accepted'

 # The decoder may hold two of the four bytes of an emoji after reading
 # a failed completed status. It must not be reset or turn into U+FFFD.
 $bytes=$utf8.GetBytes($start+"`n")
 $prefixBytes=$utf8.GetBytes($closed)
 $combo=New-Object byte[] ($prefixBytes.Length+2)
 [Array]::Copy($prefixBytes,0,$combo,0,$prefixBytes.Length)
 [Array]::Copy($bytes,0,$combo,$prefixBytes.Length,2)
 $rec=ResetFixture '' 'Ready'
 [IO.File]::WriteAllBytes($log,$combo)
 $sink.ThrowNextMarker=$true
 Poll $rec
 Check ($rec.State -ceq 'Fault') 'callback failure with pending two UTF-8 bytes revokes transport readiness'
 $rest=New-Object byte[] ($bytes.Length-2)
 [Array]::Copy($bytes,2,$rest,0,$rest.Length)
 $f=[IO.File]::Open($log,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$f.Write($rest,0,$rest.Length)}finally{$f.Dispose()}
 Poll $rec
 Check ($sink.Tools.Count -eq 1 -and $sink.Tools[0] -ceq $start -and
  -not (($sink.Tools -join '').Contains([char]0xfffd))) 'pending four-byte marker survives callback error and finishes without loss'

 # A preceding tool line must not be duplicated when the SECOND decoded
 # line fails. Its immediately following Ready is the only recovery proof.
 $rec=ResetFixture ($start+"`n"+$closed+$ready)
 $sink.ThrowNextMarker=$true
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and $sink.Tools.Count -eq 1 -and
  $sink.Markers.Count -eq 0) 'earlier processed tool event survives later callback fault once'
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Tools.Count -eq 1 -and
  $sink.Markers.Count -eq 1) 'first following Ready processed without replay of earlier tool'

 # If a TOOL callback fails, the failing entry may be ambiguous (it could
 # have been partially delivered). Skip only that entry; preserve later
 # completed tool events and the next valid channel confirmation.
 $rec=ResetFixture ($start+"`n"+$completed+"`n"+$ready)
 $sink.ThrowNextTool=$true
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and $sink.Tools.Count -eq 0 -and
  $sink.Markers.Count -eq 0) 'tool callback fault latches transport Fault without losing queued later lines'
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Tools.Count -eq 1 -and
  $sink.Tools[0] -ceq $completed -and $sink.Markers.Count -eq 1) 'after failed tool callback the next completed tool and first Ready are preserved'

 # An exception in the decoder occurs BEFORE decoded lines are committed,
 # unlike a callback exception. Its cursor has consumed bytes but no valid
 # physical line frame exists: skip the rest through LF and accept the FIRST
 # proper channel-status line that follows.
 $rec=ResetFixture $prefix 'Fault'
 $broken=[pscustomobject]@{}
 Add-Member -InputObject $broken -MemberType ScriptMethod -Name GetChars -Value {
  param($bytes,$offset,$count,$chars,$charOffset,$flush)
  throw 'R3_FAKE_DECODER_FAILURE_AFTER_FILE_READ'
 }
 Add-Member -InputObject $broken -MemberType ScriptMethod -Name Reset -Value {}
 $rec.Decoder=$broken
 Poll $rec
 Check ($rec.State -ceq 'Fault' -and
  [bool]$rec.DiscardOversizedLine -and [string]$rec.Fragment -ceq '') 'decode failure before framing discards unknown partial physical line'
 $rec.Decoder=(New-Object Text.UTF8Encoding($false,$false)).GetDecoder()
 Append ($suffix+$ready)
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Markers.Count -eq 1) 'unframed-byte suffix skipped and first next top-level Ready accepted'

 # A queued Ready from a previously consumed file must not survive a real
 # file truncation/rotation: old history is never used as current proof.
 $rec=ResetFixture ($closed+$ready)
 $sink.ThrowNextMarker=$true
 Poll $rec
 [IO.File]::WriteAllBytes($log,(New-Object byte[] 0))
 Poll $rec
 Check ($rec.State -cne 'Ready' -and $sink.Markers.Count -eq 0) 'rotation discards buffered Ready from old log generation'
 Append $ready
 Poll $rec
 Check ($rec.State -ceq 'Ready' -and $sink.Markers.Count -eq 1) 'only new Ready marker after log rotation is accepted'
}catch{
 $fail++
 Write-Output ('FAIL R3_BUFFERED_TEST_EXCEPTION '+$_.Exception.Message)
}finally{
 if([IO.File]::Exists($log)){
  if([IO.Path]::GetDirectoryName($log) -cne $temp -or
     [IO.Path]::GetFileName($log) -cnotmatch '^RDC-RC1-R3-BUFFERED-[0-9a-f]{32}\.log$' -or
     ([IO.File]::GetAttributes($log) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   $fail++;Write-Output 'FAIL R3_BUFFERED_CLEANUP_SCOPE_REFUSED'
  }else{
   [IO.File]::Delete($log)
   Check (-not [IO.File]::Exists($log)) 'scoped buffered-log fixture deleted without touching actual Remote'
  }
 }
}
Write-Output ('RC1_R3_BUFFERED_LINES_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
