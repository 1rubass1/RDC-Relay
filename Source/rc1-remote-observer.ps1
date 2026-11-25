# RDC Relay 1.6.0 RC1: existing Desktop Commander Remote OBSERVER ONLY.
# Never starts, stops, reconnects or changes credentials of an existing session.
# Called only by rc1-tray-host.ps1 -ObserveExisting on its STA UI thread.
function Assert-Rc1ObserverNoReparse([string]$path){
 $cursor=[IO.Path]::GetFullPath($path)
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'RC1_OBSERVER_REPARSE_DENIED'
   }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if(-not $parent -or $parent -ceq $cursor){break}
  $cursor=$parent
 }
}
function Get-Rc1ObservedRemoteIdentity{
 $appdata=[Environment]::GetFolderPath('LocalApplicationData')
 if([string]::IsNullOrWhiteSpace($appdata)){throw 'RC1_OBSERVER_NO_APPDATA'}
 $log=[IO.Path]::GetFullPath((Join-Path $appdata 'RemoteDesktopCommanderLauncher\remote-session.log'))
 Assert-Rc1ObserverNoReparse $log
 if(-not [IO.File]::Exists($log)){throw 'RC1_OBSERVER_LEGACY_LOG_NOT_FOUND'}
 $expectedExe=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\cmd.exe'))
 $redirection='>\s*"'+[regex]::Escape($log)+'"'
 $candidates=@(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction Stop | Where-Object {
  $line=[string]$_.CommandLine
  $line.IndexOf('@wonderwhy-er/desktop-commander@0.2.52',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
  $line.IndexOf(' remote ',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
  [regex]::IsMatch($line,$redirection,[Text.RegularExpressions.RegexOptions]::IgnoreCase) -and
  [string]::Equals([IO.Path]::GetFullPath([string]$_.ExecutablePath),$expectedExe,[StringComparison]::OrdinalIgnoreCase)
 })
 if($candidates.Count -ne 1){throw ('RC1_OBSERVER_AMBIGUOUS_OR_ABSENT_'+$candidates.Count)}
 $record=$candidates[0]
 $proc=Get-Process -Id ([int]$record.ProcessId) -ErrorAction Stop
 if($proc.HasExited){throw 'RC1_OBSERVER_PROCESS_EXITED'}
 $hostSession=[Diagnostics.Process]::GetCurrentProcess().SessionId
 if($proc.SessionId -ne $hostSession){throw 'RC1_OBSERVER_CROSS_SESSION'}
 return @{
  Pid=[int]$record.ProcessId;Born=[long]$proc.StartTime.ToUniversalTime().Ticks;
  Session=[int]$proc.SessionId;Parent=[int]$record.ParentProcessId;
  Log=$log;Exe=$expectedExe;Offset=[long]0;DiscardFirst=$false;
  Fragment='';State='Connecting';Detail='Existing pinned Remote; channel not yet confirmed';
  MissingSinceTicks=[long]0;HandoffComplete=$false
 }
}
function Test-Rc1ObservedRemoteIdentity([hashtable]$ob){
 try{
  $now=Get-Process -Id $ob.Pid -ErrorAction Stop
  if($now.HasExited -or $now.StartTime.ToUniversalTime().Ticks -ne $ob.Born -or
    $now.SessionId -ne $ob.Session){return $false}
  $row=Get-CimInstance Win32_Process -Filter ('ProcessId='+$ob.Pid) -ErrorAction Stop
  if(-not $row -or [int]$row.ParentProcessId -ne $ob.Parent -or
    -not [string]::Equals([IO.Path]::GetFullPath([string]$row.ExecutablePath),$ob.Exe,[StringComparison]::OrdinalIgnoreCase)){
   return $false
  }
  $line=[string]$row.CommandLine
  if($line.IndexOf('@wonderwhy-er/desktop-commander@0.2.52',[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
   $line.IndexOf(' remote ',[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
   -not [regex]::IsMatch($line,'>\s*"'+[regex]::Escape($ob.Log)+'"','IgnoreCase')){return $false}
  Assert-Rc1ObserverNoReparse $ob.Log
  return [IO.File]::Exists($ob.Log)
 }catch{return $false}
}
# Only actual top-level official Remote status lines carry link evidence:
# matching embedded text inside tool output/JSON would invent connectivity.
function Get-Rc1ObservedStatusText([string]$line){
 $status=([string]$line).TrimStart()
 foreach($prefix in @('🔌 ','✅ ','❌ ','⚠️ ','⚠ ','ℹ️ ','🔄 ')){
  if($status.StartsWith($prefix,[StringComparison]::Ordinal)){
   $status=$status.Substring($prefix.Length).TrimStart()
   break
  }
 }
 return $status
}
function Test-Rc1ObservedStatusPrefix([string]$status,[string]$prefix){
 return $status.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)
}
function Get-Rc1ObservedMarker([string]$line){
 # Fixed categories only; never send raw Remote logs, arguments or account data.
 $status=Get-Rc1ObservedStatusText $line
 if((Test-Rc1ObservedStatusPrefix $status 'Channel error:') -or
    (Test-Rc1ObservedStatusPrefix $status 'Channel closed') -or
    (Test-Rc1ObservedStatusPrefix $status 'Device marked as offline') -or
    (Test-Rc1ObservedStatusPrefix $status 'Remote session expired and could not be renewed') -or
    (Test-Rc1ObservedStatusPrefix $status 'Restart the terminal running Desktop Commander to reconnect') -or
    (Test-Rc1ObservedStatusPrefix $status 'This device is now offline for remote calls') -or
    (Test-Rc1ObservedStatusPrefix $status 'Device registered, but NOT reachable') -or
    (Test-Rc1ObservedStatusPrefix $status 'Realtime channel is not open') -or
    (Test-Rc1ObservedStatusPrefix $status 'Channel subscription timed out') -or
    (Test-Rc1ObservedStatusPrefix $status 'Presence track remained unavailable') -or
    (Test-Rc1ObservedStatusPrefix $status 'Presence published but the device row could not be updated')){
  return @{State='Fault';Detail='Remote channel unavailable (log evidence)';Marker='Remote channel unavailable'}
 }
 if((Test-Rc1ObservedStatusPrefix $status 'Local Desktop Commander MCP went away') -or
    (Test-Rc1ObservedStatusPrefix $status 'Could not restart local Desktop Commander MCP:')){
  return @{State='Reconnecting';Detail='Local MCP recovery (log evidence)';Marker='Local MCP recovering'}
 }
 if(Test-Rc1ObservedStatusPrefix $status 'Device startup failed:'){
  return @{State='Fault';Detail='Remote startup failed (log evidence)';Marker='Remote start failed'}
 }
 if((Test-Rc1ObservedStatusPrefix $status 'Authenticating with Remote MCP server') -or
    (Test-Rc1ObservedStatusPrefix $status 'waiting for authentication')){
  return @{State='AuthPending';Detail='Remote authentication pending';Marker='Authentication pending'}
 }
 if((Test-Rc1ObservedStatusPrefix $status 'Desktop Commander Remote is connected') -or
    (Test-Rc1ObservedStatusPrefix $status 'Presence tracked (device ')){
  return @{State='Ready';Detail='Remote MCP connected (log evidence)';Marker='Remote connected'}
 }
 if($line.StartsWith('🔧 Received tool call ',[StringComparison]::Ordinal)){
  return @{State='';Detail='';Marker='Remote tool started'}
 }
 if($line.StartsWith('✅ Tool call ',[StringComparison]::Ordinal) -and
    $line.IndexOf(' completed:',[StringComparison]::Ordinal) -gt 0){
  return @{State='';Detail='';Marker='Remote tool completed'}
 }
 if($line.StartsWith('❌ Tool call ',[StringComparison]::Ordinal) -and
    $line.IndexOf(' failed:',[StringComparison]::Ordinal) -gt 0){
  return @{State='';Detail='';Marker='Remote tool failed'}
 }
 return $null
}
function Get-Rc1ObservedHealthBootstrap([string]$path){
 # Read-only, bounded health reconstruction. Never export log text across IPC.
 # An incomplete read is deliberately NOT reported as confirmed connected.
 Assert-Rc1ObserverNoReparse $path
 $stream=$null
 $reader=$null
 $result=@{State='Connecting';Detail='Existing Remote process observed; channel evidence unconfirmed';Complete=$false;Lines=0}
 try{
  $stream=New-Object IO.FileStream -ArgumentList @($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,
    ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  $start=[Math]::Max([long]0,($stream.Length - [long]8388608))
  [void]$stream.Seek($start,[IO.SeekOrigin]::Begin)
  $reader=New-Object IO.StreamReader -ArgumentList @($stream,[Text.Encoding]::UTF8,$true,8192,$false)
  if($start -gt 0){[void]$reader.ReadLine()}
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not $reader.EndOfStream -and $result.Lines -lt 100000 -and $watch.ElapsedMilliseconds -lt 3000){
   $raw=[string]$reader.ReadLine()
   $result.Lines++
   $marker=Get-Rc1ObservedMarker ($raw.TrimEnd([char]13))
   if($null -ne $marker -and $marker.State){
    $result.State=[string]$marker.State
    $result.Detail=[string]$marker.Detail
   }
  }
  $result.Complete=$reader.EndOfStream
  if(-not $result.Complete){
   $result.State='Connecting'
   $result.Detail='Existing Remote observed; bounded historical scan incomplete'
  }
  return $result
 }catch{
  return @{State='Connecting';Detail='Existing Remote observed; historical log evidence unavailable';Complete=$false;Lines=0}
 }finally{
  if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}
 }
}
# A healthy process and an old log line do not provide fresh connection
# evidence. The two-minute lease applies only to newly observed channel
# or presence status proof, never tool completion or active Remote probing.
function Test-Rc1ObservedReadyEvidenceExpired([long]$nowTicks,[long]$proofTicks){
 return ($proofTicks -le 0 -or $proofTicks -gt $nowTicks -or
  ($nowTicks-$proofTicks) -gt [TimeSpan]::FromMinutes(2).Ticks)
}
function Expire-Rc1ObservedReadyEvidence([hashtable]$ob){
 if($ob.State -cne 'Ready'){return}
 if(Test-Rc1ObservedReadyEvidenceExpired ([DateTime]::UtcNow.Ticks) ([long]$ob.LastReadyProofTicks)){
  $ob.State='Reconnecting'
  $ob.Detail='Remote channel unconfirmed; awaiting new connectivity evidence'
  $ob.LastReadyProofTicks=[long]0
 }
}
# Keep the UTF-8 decoder state across 750ms polls. A Remote tool marker
# starts with multi-byte Unicode; a split byte sequence must not turn into
# replacement glyphs and silently drop its start/completion record.
function Reset-Rc1ObservedUtf8Stream([hashtable]$ob){
 if($ob.Decoder){$ob.Decoder.Reset()}
 $ob.Fragment=''
 $ob.DiscardOversizedLine=$false
 # A new OS launcher or log generation must never replay old complete lines.
 $ob.PendingLines=[string[]]@()
 $ob.PendingLineIndex=0
}
function Read-Rc1ObservedUtf8Lines([hashtable]$ob,[byte[]]$buffer,[int]$count){
 if($null -eq $buffer -or $count -lt 0 -or $count -gt $buffer.Length){
  throw 'RC1_OBSERVER_UTF8_READ_BOUNDS'
 }
 if(-not $ob.Decoder){
  $ob.Decoder=(New-Object Text.UTF8Encoding($false,$false)).GetDecoder()
 }
 if($count -eq 0){return}
 $chars=New-Object char[] ($count+4)
 $actual=$ob.Decoder.GetChars($buffer,0,$count,$chars,0,$false)
 if($actual -eq 0){return}
 $joined=([string]$ob.Fragment)+[string]::new($chars,0,$actual)
 $end=$joined.LastIndexOf([char]10)
 if($end -lt 0){
  # Once an incomplete physical line exceeds its safe bound, discard
  # everything up to the next LF; never parse its suffix as a new event.
  if(-not $ob.DiscardOversizedLine){
   if($joined.Length -le 8192){$ob.Fragment=$joined}
   else{$ob.Fragment='';$ob.DiscardOversizedLine=$true}
  }
  return
 }
 $rows=$joined.Substring(0,$end).Split([char]10)
 $skipFirst=[bool]$ob.DiscardOversizedLine
 $ob.DiscardOversizedLine=$false
 $ob.Fragment=$joined.Substring($end+1)
 if($ob.Fragment.Length -gt 8192){
  $ob.Fragment='';$ob.DiscardOversizedLine=$true
 }
 for($i=0;$i -lt $rows.Length;$i++){
  if(($skipFirst -and $i -eq 0) -or $rows[$i].Length -gt 8192){continue}
  $rows[$i].TrimEnd([char]13)
 }
}
# Every complete line from the last bounded FileStream read remains buffered
# until processed. Consume the current entry BEFORE invoking owner callbacks:
# if a callback throws after applying a side effect, never replay that entry.
# Crucially, later complete lines in the same read survive the exception.
# Private raw log text is kept only in this local observer, never IPC.
function Invoke-Rc1ObservedPendingLines([object]$owner,[hashtable]$ob){
 if($null -eq $ob.PendingLines){return}
 while([int]$ob.PendingLineIndex -lt $ob.PendingLines.Length){
  $raw=[string]$ob.PendingLines[[int]$ob.PendingLineIndex]
  $ob.PendingLineIndex=[int]$ob.PendingLineIndex+1
  $marker=Get-Rc1ObservedMarker ($raw.TrimEnd([char]13))
  if($null -eq $marker){continue}
  if($marker.State){
   $ob.State=$marker.State;$ob.Detail=$marker.Detail
   $ob.LastReadyProofTicks=if($marker.State -ceq 'Ready'){
    [DateTime]::UtcNow.Ticks
   }else{[long]0}
  }
  # Local tool completion precedes transport delivery. Activity only.
  if($marker.Marker -in @('Remote tool started','Remote tool completed','Remote tool failed')){
   $owner.ObservedToolLine($raw.TrimEnd([char]13))
  }else{$owner.ObservedMarker([string]$marker.Marker)}
 }
 $ob.PendingLines=[string[]]@()
 $ob.PendingLineIndex=0
}
function Initialize-Rc1RemoteObserver([object]$owner){
 $ob=Get-Rc1ObservedRemoteIdentity
 $bootstrap=Get-Rc1ObservedHealthBootstrap $ob.Log
 # Historical messages only establish state. New GUI receives future safe markers.
 $ob.Offset=([IO.FileInfo]$ob.Log).Length
 Reset-Rc1ObservedUtf8Stream $ob
 $ob.DiscardFirst=$false
 # Old history is descriptive, not a current link signal.
 $ob.LastReadyProofTicks=[long]0
 $ob.State=if($bootstrap.State -ceq 'Ready'){'Connecting'}else{$bootstrap.State}
 $ob.Detail=if($bootstrap.State -ceq 'Ready'){
  'Historic Remote connection noted; awaiting fresh channel evidence'
 }else{$bootstrap.Detail}
 $owner.EnableObservedRemote($ob.Pid)
 $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
 return $ob
}
function Invoke-Rc1RemoteObserverPoll([object]$owner,[hashtable]$ob){
 if(-not (Test-Rc1ObservedRemoteIdentity $ob)){
  # Passive reacquisition after legacy launcher's own restart. Its fresh
  # PID, birth, session, pinned command and private log must all match.
  # A missing/ambiguous candidate remains Disconnected; never start it.
  try{
   $replacement=Get-Rc1ObservedRemoteIdentity
   if(-not (Test-Rc1ObservedRemoteIdentity $replacement)){throw 'RC1_REACQUIRE_UNVERIFIED'}
   if($replacement.Pid -eq $ob.Pid -and $replacement.Born -eq $ob.Born){
    throw 'RC1_REACQUIRE_NO_NEW_IDENTITY'
   }
   $history=Get-Rc1ObservedHealthBootstrap $replacement.Log
   $owner.RetargetObservedRemote([int]$replacement.Pid)
   foreach($key in @('Pid','Born','Session','Parent','Log','Exe')){$ob[$key]=$replacement[$key]}
   $ob.Offset=([IO.FileInfo]$ob.Log).Length
   Reset-Rc1ObservedUtf8Stream $ob
   $ob.DiscardFirst=$false;$ob.MissingSinceTicks=[long]0
   $ob.LastReadyProofTicks=[long]0
   $ob.State=if($history.State -ceq 'Ready'){'Connecting'}else{[string]$history.State}
   $ob.Detail=if($history.State -ceq 'Ready'){
    'Replaced Remote launcher; awaiting fresh channel evidence'
   }else{[string]$history.Detail}
   $owner.ObservedMarker('Remote launcher replaced')
   $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
  }catch{
   $owner.UpdateObservedRemote($false,'Disconnected',
    'Previous Remote stopped or replaced; waiting for verified safe handoff')
   # Never treat a vanished PID alone as proof of permission to start a
   # second Remote. Both the old shell AND all external Remote launchers
   # must be absent continuously, including a fresh PID after restart.
   if($owner.CanPromoteObservedRemote()){
    $now=[DateTime]::UtcNow.Ticks
    if([long]$ob.MissingSinceTicks -le 0){$ob.MissingSinceTicks=$now}
    elseif($now-[long]$ob.MissingSinceTicks -ge [TimeSpan]::FromSeconds(5).Ticks){
     if($owner.PromoteObservedRemoteToManaged()){$ob.HandoffComplete=$true}
    }
   }else{$ob.MissingSinceTicks=[long]0}
  }
  return
 }
 $stream=$null
 # A temporary sharing failure before Read must retain the decoder,
 # fragment, overflow-discard state AND Offset as one coherent cursor.
 # Only a failure after Read but BEFORE successful line framing makes
 # the current physical line uncertain: drop its suffix through next LF.
 # Once framing commits, a callback failure must preserve every later
 # complete message in PendingLines and the partial UTF-8 line context.
 $readBytesConsumed=$false
 $framingCommitted=$false
 try{
  $stream=New-Object IO.FileStream -ArgumentList @($ob.Log,[IO.FileMode]::Open,[IO.FileAccess]::Read,
    ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($stream.Length -lt $ob.Offset){
   $ob.Offset=0;Reset-Rc1ObservedUtf8Stream $ob;$ob.DiscardFirst=$false
   $ob.LastReadyProofTicks=[long]0
   $ob.State='Connecting';$ob.Detail='Remote log rotated; awaiting fresh evidence'
  }
  # Drain completed lines from the previous read BEFORE consuming new bytes.
  # On a callback exception only its own line is skipped; later complete
  # messages stay queued, in order, even if file EOF has been reached.
  Invoke-Rc1ObservedPendingLines $owner $ob
  $available=[Math]::Min([long]32768,($stream.Length-$ob.Offset))
  if($available -le 0){
   Expire-Rc1ObservedReadyEvidence $ob
   $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
   return
  }
  [void]$stream.Seek($ob.Offset,[IO.SeekOrigin]::Begin)
  $buffer=New-Object byte[] ([int]$available)
  $n=$stream.Read($buffer,0,$buffer.Length)
  if($n -gt 0){$readBytesConsumed=$true}
  $ob.Offset+=$n
  # Decode with the persistent UTF-8 decoder, then store ALL complete
  # physical lines atomically before invoking any potentially failing
  # owner callback. Maximum batch is the bounded 32 KiB file-read window.
  $lines=@(Read-Rc1ObservedUtf8Lines $ob $buffer $n)
  if($ob.DiscardFirst -and $lines.Count -gt 0){
   $lines=@($lines | Select-Object -Skip 1)
   $ob.DiscardFirst=$false
  }
  $ob.PendingLines=[string[]]$lines
  $ob.PendingLineIndex=0
  $framingCommitted=$true
  Invoke-Rc1ObservedPendingLines $owner $ob
  Expire-Rc1ObservedReadyEvidence $ob
  $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
 }catch{
  # Update the internal state as well as the public snapshot. Without this,
  # the next successful empty-file poll revives stale Ready after a lock.
  $ob.State='Fault'
  $ob.Detail='Observer could not read private log; Remote was not controlled'
  $ob.LastReadyProofTicks=[long]0
  if($readBytesConsumed -and -not $framingCommitted){
   # An exception BEFORE the complete lines were safely queued leaves
   # framing uncertain. Retain any prior queued lines but drop the new
   # partial physical line through its next LF; never parse a JSON suffix.
   if($ob.Decoder){$ob.Decoder.Reset()}
   $ob.Fragment=''
   $ob.DiscardOversizedLine=$true
  }
  # After successful framing, an owner callback error must NOT reset the
  # decoder or discard already-decoded later physical lines. The failing
  # line was consumed before its callback; pending lines resume next poll.
  # Before Read, also preserve pending UTF-8, Fragment and file Offset.
  $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
 }finally{
  if($stream){$stream.Dispose()}
 }
}