# One-shot product Source Host/GUI OS smoke. NO real Desktop Commander Remote.
# Requires owner approval. Only exact fresh TEMP/RDC-RC1-OS-<GUID> roots.
# Never force-terminates a process. Unknown identity / survivor -> NOT CLEAN.
param([switch]$Execute,[switch]$InjectStartFailure)
$ErrorActionPreference='Stop'
if(-not $Execute){Write-Output 'NOT CHECKED: OS smoke requires explicit -Execute';exit 42}
$project=Split-Path -Parent $PSScriptRoot
$branch=(git -C $project branch --show-current).Trim()
if($branch -cne 'feature/v1.6-host-gui-owner-pilot'){throw 'OS_REFUSED_WRONG_BRANCH'}
$marker=Get-Content -LiteralPath (Join-Path $project 'Source\rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($marker.candidate -cne '1.6.0 RC1' -or $marker.liveRemoteEnabled -ne $false -or
   $marker.installable -ne $false -or $marker.publishable -ne $false){throw 'OS_REFUSED_CANDIDATE_GATE'}
$names=@('remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerProcess.cs','rc1-candidate.json','RDCRelay.ico',
 'divider-caustic.ps','divider-caustic-detail.ps','divider-particles.ps',
 'divider-particles-core.ps','update-notice.ps1','update.ps1')
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$runId=[Guid]::NewGuid().ToString('N')
$trial=Join-Path $temp ('RDC-RC1-OS-'+$runId)
$src=Join-Path $trial 'Source'
$sentinel=Join-Path $temp ('RDC-RC1-OS-SENTINEL-'+$runId+'.txt')
$sentinelBytes=[Text.Encoding]::UTF8.GetBytes('RDC RC1 disposable outside sentinel '+$runId)
$hashes=@{}
$hostProcess=$null;$firstGui=$null;$secondGui=$null
$outTask=$null;$errTask=$null
$pass=0;$fail=0;$notChecked=0;$safeToClean=$false
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
function PathSafe([string]$path){
 $cursor=[IO.Path]::GetFullPath($path)
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'OS_REPARSE_REFUSED'
   }
  }
  $next=[IO.Path]::GetDirectoryName($cursor)
  if(-not $next -or $next -ceq $cursor){break};$cursor=$next
 }
}
function Verified([Diagnostics.Process]$process,[string]$expectedFile,[int]$expectedParent){
 if(-not $process -or $process.HasExited){return $false}
 try{
  $process.Refresh()
  $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$process.Id) -ErrorAction Stop
  if(-not $cim -or [int]$cim.ParentProcessId -ne $expectedParent){return $false}
  if(-not [String]::Equals([IO.Path]::GetFullPath($process.MainModule.FileName),
   [IO.Path]::GetFullPath($expectedFile),[StringComparison]::OrdinalIgnoreCase)){return $false}
  if($process.StartTime.ToUniversalTime().Ticks -le 0){return $false}
  return $true
 }catch{return $false}
}
function FindOwnGui([Diagnostics.Process]$hostProcess,[int]$excludePid){
 $rows=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$hostProcess.Id) -ErrorAction Stop |
  Where-Object {
   $_.Name -ieq 'powershell.exe' -and $_.CommandLine -and
   $_.CommandLine.IndexOf((Join-Path $src 'remote-window.ps1'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
   $_.CommandLine.IndexOf('-OwnerGui',[StringComparison]::Ordinal) -ge 0 -and
   $_.CommandLine.IndexOf($trial,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
   $_.ProcessId -ne $excludePid
  })
 if($rows.Count -gt 1){throw 'OS_DUPLICATE_GUI_PROCESSES'}
 if($rows.Count -eq 0){return $null}
 $g=[Diagnostics.Process]::GetProcessById([int]$rows[0].ProcessId)
 if(-not (Verified $g $powerShellFile $hostProcess.Id)){throw 'OS_GUI_IDENTITY_UNVERIFIED'}
 return $g
}
function WaitOwnGui([Diagnostics.Process]$hostProcess,[int]$excludePid,[int]$seconds){
 $timer=[Diagnostics.Stopwatch]::StartNew()
 while($timer.Elapsed.TotalSeconds -lt $seconds){
  if($hostProcess.HasExited){throw 'OS_HOST_EXITED_BEFORE_GUI'}
  $g=FindOwnGui $hostProcess $excludePid
  if($g){
   $g.Refresh()
   if($g.MainWindowHandle -ne [IntPtr]::Zero){return $g}
   $g.Dispose()
  }
  Start-Sleep -Milliseconds 250
 }
 throw 'OS_GUI_HWND_TIMEOUT'
}
if([IO.Directory]::Exists($trial) -or [IO.File]::Exists($trial) -or [IO.File]::Exists($sentinel)){
 throw 'OS_GUID_COLLISION'
}
PathSafe $temp
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($userSid,
 [Security.AccessControl.FileSystemRights]::FullControl,
 ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
 [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
 ([Security.Principal.SecurityIdentifier]'S-1-5-2'),
 [Security.AccessControl.FileSystemRights]::Read,[Security.AccessControl.AccessControlType]::Deny))
try{
 [void][IO.Directory]::CreateDirectory($trial,$acl)
 [void][IO.Directory]::CreateDirectory($src)
 PathSafe $trial
 [IO.File]::WriteAllBytes($sentinel,$sentinelBytes)
 foreach($name in $names){
  $from=Join-Path (Join-Path $project 'Source') $name
  $to=Join-Path $src $name
  PathSafe $from
  if(-not [IO.File]::Exists($from)){throw ('OS_SOURCE_MISSING_'+$name)}
  [IO.File]::Copy($from,$to,$false)
  $hashes[$name]=(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash
 }
 $powerShellFile=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if(-not [IO.File]::Exists($powerShellFile)){throw 'OS_SYSTEM_POWERSHELL_MISSING'}
 Add-Type -TypeDefinition @'
 using System;
 using System.Runtime.InteropServices;
 public static class RdcRc1OsMessage {
  [DllImport("user32.dll",SetLastError=true)]
  public static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr wParam,IntPtr lParam);
  [DllImport("user32.dll",SetLastError=true)]
  public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
 }
'@
 $args='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+
  (Join-Path $src 'rc1-tray-host.ps1')+'" -FakeOnly -TrialRoot "'+$trial+
  '" -TrialAutoExitSeconds 35 -TrialReopenOnce'
 if($InjectStartFailure){$args+=' -TrialFailGuiStartOnce'}
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$powerShellFile;$psi.Arguments=$args
 $psi.WorkingDirectory=$src;$psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $hostProcess=[Diagnostics.Process]::Start($psi)
 if(-not $hostProcess){throw 'OS_HOST_START_NULL'}
 $outTask=$hostProcess.StandardOutput.ReadToEndAsync()
 $errTask=$hostProcess.StandardError.ReadToEndAsync()
 Check (Verified $hostProcess $powerShellFile $PID) 'OS Host exact executable and parent'
 if($fail){throw 'OS_HOST_UNVERIFIED'}
 $hostBorn=$hostProcess.StartTime.ToUniversalTime().Ticks
 Write-Output ('OS_HOST_PID='+$hostProcess.Id+' UTC_TICKS='+$hostBorn+' SESSION='+$hostProcess.SessionId)
 $firstGui=WaitOwnGui $hostProcess 0 18
 $firstGuiId=$firstGui.Id
 $firstGuiBorn=$firstGui.StartTime.ToUniversalTime().Ticks
 Check (Verified $firstGui $powerShellFile $hostProcess.Id) 'OS GUI A exact parent and birth'
 Write-Output ('OS_GUI_A_PID='+$firstGuiId+' UTC_TICKS='+$firstGuiBorn+' SESSION='+$firstGui.SessionId)
 # Allow two bounded 150ms GUI polls plus IPC deadlines before OS-01 WM_CLOSE.
 Start-Sleep -Milliseconds 1800
 [uint32]$hwndPid=0
 [void][RdcRc1OsMessage]::GetWindowThreadProcessId($firstGui.MainWindowHandle,[ref]$hwndPid)
 if($hwndPid -ne $firstGui.Id -or
    $firstGui.StartTime.ToUniversalTime().Ticks -ne $firstGuiBorn -or
    $hostProcess.StartTime.ToUniversalTime().Ticks -ne $hostBorn -or
    -not (Verified $firstGui $powerShellFile $hostProcess.Id)){
  throw 'OS_GUI_HWND_OWNER_MISMATCH'
 }
 if(-not [RdcRc1OsMessage]::PostMessage($firstGui.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)){
  throw 'OS_WM_CLOSE_REFUSED'
 }
 Check ($firstGui.WaitForExit(7000)) 'OS-01 native WM_CLOSE exits only GUI A'
 Check (-not $hostProcess.HasExited) 'OS-01 Host survives GUI A close'
 $secondGui=WaitOwnGui $hostProcess $firstGuiId 18
 Check ($secondGui.Id -ne $firstGuiId -and (Verified $secondGui $powerShellFile $hostProcess.Id)) 'OS-02 separate GUI B under original Host'
 Write-Output ('OS_GUI_B_PID='+$secondGui.Id+' UTC_TICKS='+$secondGui.StartTime.ToUniversalTime().Ticks+' SESSION='+$secondGui.SessionId)
 if($InjectStartFailure){Check ($secondGui.Id -gt 0) 'OS-19 injected first Process.Start failure followed by GUI A/B'}
 Check ($hostProcess.WaitForExit(48000)) 'OS bounded cooperative Host exit'
 Check ($secondGui.HasExited) 'OS GUI B exits through Host closeGeneration'
 $safeToClean=($fail -eq 0 -and $hostProcess.HasExited -and $firstGui.HasExited -and $secondGui.HasExited)
}catch{
 $script:fail++
 Write-Output ('FAIL OS_EXCEPTION '+$_.Exception.Message)
}finally{
 # The dedicated trial Host has a 35-second cooperative self-exit.
 # A failed GUI assertion is NOT permission to terminate it forcibly.
 if($hostProcess){
  try{if(-not $hostProcess.HasExited){[void]$hostProcess.WaitForExit(45000)}}catch{}
  try{$hostProcess.Refresh()}catch{}
 }
 if($outTask -and $outTask.IsCompleted){
  $out=[string]$outTask.Result
  if($out.Length>2000){$out=$out.Substring(0,2000)}
  Write-Output ('OS_HOST_STDOUT '+$out)
  Check ($out.Contains('RC1_TRIAL_IPC_SNAPSHOT_GUI_COUNT=2 EVENT_GUI_COUNT=2')) 'OS authenticated IPC snapshots and event polls for GUI A and B'
  if($InjectStartFailure){
   Check ($out.Contains('RC1_TRIAL_F2_FIRST_START_REFUSED_AND_CLEAN')) 'OS-19 failed first Process.Start leaves no blocking ticket'
   Check ($out.Contains('RC1_TRIAL_INJECTED_GUI_START_FAILURE')) 'OS-19 exact injected error observed'
  }
 }else{Check $false 'OS Host stdout evidence available'}
 if($errTask -and $errTask.IsCompleted){
  $err=[string]$errTask.Result
  if($err.Length>2000){$err=$err.Substring(0,2000)}
  if($err){Write-Output ('OS_HOST_STDERR '+$err)}
 }
 $liveHost=($hostProcess -and -not $hostProcess.HasExited)
 $liveA=($firstGui -and -not $firstGui.HasExited)
 $liveB=($secondGui -and -not $secondGui.HasExited)
 if($liveHost -or $liveA -or $liveB){$safeToClean=$false;Write-Output 'NOT CLEAN: test-owned process survivor; NO FORCE KILL'}
 if($fail){$safeToClean=$false}
 if([IO.File]::Exists($sentinel)){
  $current=[IO.File]::ReadAllBytes($sentinel)
  $same=($current.Length -eq $sentinelBytes.Length)
  if($same){for($i=0;$i -lt $current.Length;$i++){if($current[$i] -ne $sentinelBytes[$i]){$same=$false;break}}}
  Check $same 'OS outside sentinel unchanged'
  if(-not $same){$safeToClean=$false}
 }
 if($safeToClean){
  try{
   PathSafe $trial
   $state=Join-Path $trial 'owner-state'
   if([IO.Directory]::Exists($state) -and [IO.Directory]::GetFileSystemEntries($state).Count -ne 0){throw 'OS_STATE_NOT_EMPTY'}
   foreach($name in $names){
    $file=Join-Path $src $name
    PathSafe $file
    if(-not [IO.File]::Exists($file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $hashes[$name]){
     throw ('OS_SOURCE_CHANGED_'+$name)
    }
   }
   if([IO.Directory]::GetFileSystemEntries($src).Count -ne $names.Count){throw 'OS_UNKNOWN_SOURCE_ENTRY'}
   foreach($name in $names){[IO.File]::Delete((Join-Path $src $name))}
   [IO.Directory]::Delete($src,$false)
   if([IO.Directory]::Exists($state)){[IO.Directory]::Delete($state,$false)}
   if([IO.Directory]::GetFileSystemEntries($trial).Count -ne 0){throw 'OS_UNKNOWN_TRIAL_ENTRY'}
   [IO.Directory]::Delete($trial,$false)
   [IO.File]::Delete($sentinel)
   Write-Output 'OS_DISPOSABLE_CLEAN=TRUE'
  }catch{
   $script:fail++;Write-Output ('NOT CLEAN: verified-only fixture cleanup refused '+$_.Exception.Message)
  }
 }else{Write-Output ('NOT CLEAN: preserved exact trial root '+$trial)}
 if($secondGui){$secondGui.Dispose()}
 if($firstGui){$firstGui.Dispose()}
 if($hostProcess){$hostProcess.Dispose()}
}
Write-Output ('RC1_OS_SMOKE_PASS='+$pass+' FAIL='+$fail+' NOT_CHECKED='+$notChecked)
if($fail){exit 1}
exit 0
