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
function Get-Rc1ObservedMarker([string]$line){
 # Only fixed safe category labels can cross Host IPC; no raw log, tool args,
 # account or device tokens are passed from Desktop Commander to RC1 GUI.
 if($line.IndexOf('Desktop Commander Remote is connected',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('Presence tracked (device ',[StringComparison]::OrdinalIgnoreCase) -ge 0){
  return @{State='Ready';Detail='Remote MCP connected (log evidence)';Marker='Remote connected'}
 }
 if($line.IndexOf('Authenticating with Remote MCP server',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('waiting for authentication',[StringComparison]::OrdinalIgnoreCase) -ge 0){
  return @{State='AuthPending';Detail='Remote authentication pending';Marker='Authentication pending'}
 }
 if($line.IndexOf('Device startup failed:',[StringComparison]::OrdinalIgnoreCase) -ge 0){
  return @{State='Fault';Detail='Remote startup failed (log evidence)';Marker='Remote start failed'}
 }
 if($line.IndexOf('Channel error:',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('Channel closed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('Device marked as offline',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('Remote session expired and could not be renewed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('Device registered, but NOT reachable',[StringComparison]::OrdinalIgnoreCase) -ge 0){
  return @{State='Fault';Detail='Remote channel unavailable (log evidence)';Marker='Remote channel unavailable'}
 }
 if($line.IndexOf('Local Desktop Commander MCP went away (',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $line.IndexOf('Could not restart local Desktop Commander MCP:',[StringComparison]::OrdinalIgnoreCase) -ge 0){
  return @{State='Reconnecting';Detail='Local MCP recovery (log evidence)';Marker='Local MCP recovering'}
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
function Initialize-Rc1RemoteObserver([object]$owner){
 $ob=Get-Rc1ObservedRemoteIdentity
 $bootstrap=Get-Rc1ObservedHealthBootstrap $ob.Log
 # Historical messages only establish state. New GUI receives future safe markers.
 $ob.Offset=([IO.FileInfo]$ob.Log).Length
 $ob.DiscardFirst=$false
 $ob.State=$bootstrap.State
 $ob.Detail=$bootstrap.Detail
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
   $ob.Fragment='';$ob.DiscardFirst=$false;$ob.MissingSinceTicks=[long]0
   $ob.State=[string]$history.State;$ob.Detail=[string]$history.Detail
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
 try{
  $stream=New-Object IO.FileStream -ArgumentList @($ob.Log,[IO.FileMode]::Open,[IO.FileAccess]::Read,
    ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  if($stream.Length -lt $ob.Offset){
   $ob.Offset=0;$ob.Fragment='';$ob.DiscardFirst=$false
   $ob.State='Connecting';$ob.Detail='Remote log rotated; awaiting fresh evidence'
  }
  $available=[Math]::Min([long]32768,($stream.Length-$ob.Offset))
  if($available -le 0){
   $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
   return
  }
  [void]$stream.Seek($ob.Offset,[IO.SeekOrigin]::Begin)
  $buffer=New-Object byte[] ([int]$available)
  $n=$stream.Read($buffer,0,$buffer.Length)
  $ob.Offset+=$n
  $chunk=[Text.Encoding]::UTF8.GetString($buffer,0,$n)
  $joined=$ob.Fragment+$chunk
  $last=$joined.LastIndexOf([char]10)
  if($last -lt 0){
   $ob.Fragment=if($joined.Length -le 2048){$joined}else{''}
   return
  }
  $ob.Fragment=$joined.Substring($last+1)
  if($ob.Fragment.Length -gt 2048){$ob.Fragment=''}
  $lines=@($joined.Substring(0,$last).Split([char]10))
  if($ob.DiscardFirst){
   if($lines.Count -gt 0){$lines=@($lines | Select-Object -Skip 1)}
   $ob.DiscardFirst=$false
  }
  if($lines.Count -gt 160){$lines=@($lines | Select-Object -Last 160)}
  $emitted=0
  foreach($raw in $lines){
   $marker=Get-Rc1ObservedMarker ([string]$raw).TrimEnd([char]13)
   if($null -eq $marker){continue}
   if($marker.State){$ob.State=$marker.State;$ob.Detail=$marker.Detail}
   if($emitted -lt 24){$owner.ObservedMarker([string]$marker.Marker);$emitted++}
  }
  $owner.UpdateObservedRemote($true,$ob.State,$ob.Detail)
 }catch{
  $owner.UpdateObservedRemote($true,'Fault','Observer could not read private log; Remote was not controlled')
 }finally{
  if($stream){$stream.Dispose()}
 }
}