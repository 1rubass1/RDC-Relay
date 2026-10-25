# One-shot product Source Host/GUI OS smoke. NO real Desktop Commander Remote.
# Requires owner approval. Only exact fresh TEMP/RDC-RC1-OS-<GUID> roots.
# Never force-terminates a process. Unknown identity / survivor -> NOT CLEAN.
param([switch]$Execute,[switch]$InjectStartFailure,[switch]$InjectConstructorFailure,
 [switch]$ProbeDuplicateHost,[ValidateRange(1,10)][int]$Cycles=1)
$ErrorActionPreference='Stop'
if(-not $Execute){Write-Output 'NOT CHECKED: OS smoke requires explicit -Execute';exit 42}
. (Join-Path $PSScriptRoot 'Rc1OsFixtureProof.ps1')
$project=Split-Path -Parent $PSScriptRoot
$branch=(git -C $project branch --show-current).Trim()
if($branch -cne 'feature/v1.6-host-gui-owner-pilot'){throw 'OS_REFUSED_WRONG_BRANCH'}
$marker=Get-Content -LiteralPath (Join-Path $project 'Source\rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($marker.candidate -cne '1.6.0 RC1' -or $marker.liveRemoteEnabled -ne $false -or
   $marker.installable -ne $false -or $marker.publishable -ne $false){throw 'OS_REFUSED_CANDIDATE_GATE'}
$names=@($Rc1OsNames)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$runId=[Guid]::NewGuid().ToString('N')
$trial=Join-Path $temp ('RDC-RC1-OS-'+$runId)
$src=Join-Path $trial 'Source'
$sentinel=Join-Path $temp ('RDC-RC1-OS-SENTINEL-'+$runId+'.txt')
$sentinelBytes=[Text.Encoding]::UTF8.GetBytes('RDC RC1 disposable outside sentinel '+$runId)
$hashes=@{}
$creation=$null;$processRows=New-Object 'System.Collections.Generic.List[object]'
$hostProcess=$null;$firstGui=$null;$secondGui=$null;$duplicateHost=$null
$ownedGui=New-Object 'System.Collections.Generic.List[System.Diagnostics.Process]'
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
 $creation=New-Rc1AtCreation $runId $project $hashes $sentinelBytes $acl
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
 # Compile the exact product wire into the harness process for a foreign-PID negative.
 Add-Type -Path (Join-Path $src 'RdcOwnerWire.cs') -ReferencedAssemblies @(
  'System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
 $duration=if($Cycles -eq 10){120}else{35}
 $args='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+
  (Join-Path $src 'rc1-tray-host.ps1')+'" -FakeOnly -TrialRoot "'+$trial+
  '" -TrialAutoExitSeconds '+$duration+' -TrialReopenCount '+$Cycles
 if($InjectStartFailure){$args+=' -TrialFailGuiStartOnce'}
 if($InjectConstructorFailure){$args+=' -TrialFailConstructorOnce'}
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
 $processRows.Add(@{Kind='Host';Pid=$hostProcess.Id;BirthUtcTicks=$hostBorn;
  SessionId=$hostProcess.SessionId;ParentPid=$PID;Exe=$powerShellFile})
 Write-Output ('OS_HOST_PID='+$hostProcess.Id+' UTC_TICKS='+$hostBorn+' SESSION='+$hostProcess.SessionId)
 $lastGuiPid=0
 $observedPids=New-Object 'System.Collections.Generic.HashSet[int]'
 for($cycle=0;$cycle -le $Cycles;$cycle++){
  $currentGui=WaitOwnGui $hostProcess $lastGuiPid 18
  $ownedGui.Add($currentGui)
  $guiBorn=$currentGui.StartTime.ToUniversalTime().Ticks
  $processRows.Add(@{Kind='Gui';Pid=$currentGui.Id;BirthUtcTicks=$guiBorn;
   SessionId=$currentGui.SessionId;ParentPid=$hostProcess.Id;Exe=$powerShellFile})
  Check ((Verified $currentGui $powerShellFile $hostProcess.Id) -and
    $currentGui.SessionId -eq $hostProcess.SessionId -and
    $observedPids.Add($currentGui.Id)) ('OS GUI generation '+$cycle+' exact unique OS identity')
  Write-Output ('OS_GUI_'+$cycle+'_PID='+$currentGui.Id+' UTC_TICKS='+$guiBorn+
    ' SESSION='+$currentGui.SessionId)
  if($cycle -eq 0){
   $firstGui=$currentGui
   # The harness PID is NOT the authenticated GUI PID. Even its own exact
   # private test ticket must not grant the harness permission to act as GUI.
   $stateRoot=Join-Path $trial 'owner-state'
   $runs=@([IO.Directory]::GetDirectories($stateRoot))
   if($runs.Count -ne 1){throw 'OS_12_AMBIGUOUS_TICKET_RUN'}
   $ticketPath=Join-Path $runs[0] 'gui-ticket.json'
   PathSafe $ticketPath
   if(-not [IO.File]::Exists($ticketPath)){throw 'OS_12_TICKET_MISSING'}
   $ticket=[RdcOwnerWire]::Decode([IO.File]::ReadAllText($ticketPath,[Text.Encoding]::UTF8))
   if([int]$ticket.hostPid -ne $hostProcess.Id -or
      [long]$ticket.hostTicks -ne $hostBorn -or
      [int]$ticket.hostSession -ne $hostProcess.SessionId){throw 'OS_12_HOST_TICKET_MISMATCH'}
   $expectedHost=[string]$ticket.hostPid+'|'+[string]$ticket.hostTicks+'|'+[string]$ticket.hostSession
   $foreignHello=[RdcOwnerWire]::Request('HELLO',[string]$ticket.nonce,[string]$ticket.hostGeneration,0,$null,1)
   $denial=[RdcOwnerWire]::Decode([RdcOwnerWire]::Call([string]$ticket.pipe,$expectedHost,$foreignHello,1200))
   Check ([string]$denial.type -ceq 'ERROR' -and [string]$denial.code -ceq 'GUI_OS_IDENTITY') 'OS-12 foreign process cannot impersonate GUI with ticket'
   Check (Verified $hostProcess $powerShellFile $PID) 'OS-12 Host responsive after denied outsider IPC'
   # OS-23: oversized frame is refused without parsing it or hanging the Host.
   $bad=[IO.Pipes.NamedPipeClientStream]::new('.',[string]$ticket.pipe,
     [IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
   try{
    $bad.Connect(1200)
    $tooLarge=[BitConverter]::GetBytes([uint32]([RdcOwnerWire]::MaxRequest+1))
    $bad.Write($tooLarge,0,4)
    $bad.Flush()
   }finally{$bad.Dispose()}
   Start-Sleep -Milliseconds 200
   # A declared 16-byte payload containing only one byte must time out.
   $hung=[IO.Pipes.NamedPipeClientStream]::new('.',[string]$ticket.pipe,
     [IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
   try{
    $hung.Connect(1200)
    $partial=[BitConverter]::GetBytes([uint32]16)
    $hung.Write($partial,0,4)
    $hung.Write([byte[]]@(65),0,1)
    $hung.Flush()
    Start-Sleep -Milliseconds 1550
   }finally{$hung.Dispose()}
   Check (Verified $hostProcess $powerShellFile $PID) 'OS-23 Host survives oversized and partial frames'
   Write-Output ('OS_HOST_EPOCH='+[string]$ticket.hostGeneration)
   if($ProbeDuplicateHost){
    # A second launcher may only be a disposable *refused* Host.
    $dupPsi=New-Object Diagnostics.ProcessStartInfo
    $dupPsi.FileName=$powerShellFile
    $dupPsi.Arguments='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+
     (Join-Path $src 'rc1-tray-host.ps1')+'" -FakeOnly -TrialRoot "'+$trial+
     '" -TrialAutoExitSeconds 20'
    $dupPsi.WorkingDirectory=$src;$dupPsi.UseShellExecute=$false
    $dupPsi.CreateNoWindow=$true
    $dupPsi.RedirectStandardOutput=$true;$dupPsi.RedirectStandardError=$true
    $duplicateHost=[Diagnostics.Process]::Start($dupPsi)
    if(-not $duplicateHost){throw 'OS_03_DUPLICATE_PROCESS_NULL'}
    Check (Verified $duplicateHost $powerShellFile $PID) 'OS-03 duplicate launcher exact temporary identity'
    $dupOut=$duplicateHost.StandardOutput.ReadToEndAsync()
    $dupErr=$duplicateHost.StandardError.ReadToEndAsync()
    if(-not $duplicateHost.WaitForExit(14000)){throw 'OS_03_DUPLICATE_HOST_DID_NOT_REFUSE'}
    $dupText=$dupErr.GetAwaiter().GetResult()
    Check ($duplicateHost.ExitCode -ne 0 -and
      $dupText.Contains('RC1_HOST_ALREADY_RUNNING_NO_KILL')) 'OS-03 second Host refused by singleton without a kill'
    Check (Verified $hostProcess $powerShellFile $PID) 'OS-03 original Host survives duplicate'
    Write-Output ('OS_REFUSED_DUP_HOST_PID='+$duplicateHost.Id+
      ' UTC_TICKS='+$duplicateHost.StartTime.ToUniversalTime().Ticks+
      ' EXIT='+$duplicateHost.ExitCode)
   }
  }
  if($cycle -eq 1){$secondGui=$currentGui}
  if($cycle -lt $Cycles){
   # The GUI must have time to fetch authoritative snapshot AND events.
   Start-Sleep -Milliseconds 1800
   [uint32]$hwndPid=0
   [void][RdcRc1OsMessage]::GetWindowThreadProcessId($currentGui.MainWindowHandle,[ref]$hwndPid)
   if($hwndPid -ne $currentGui.Id -or
      $currentGui.StartTime.ToUniversalTime().Ticks -ne $guiBorn -or
      $hostProcess.StartTime.ToUniversalTime().Ticks -ne $hostBorn -or
      -not (Verified $currentGui $powerShellFile $hostProcess.Id)){
    throw 'OS_GUI_HWND_OWNER_MISMATCH'
   }
   if(-not [RdcRc1OsMessage]::PostMessage($currentGui.MainWindowHandle,0x0010,
      [IntPtr]::Zero,[IntPtr]::Zero)){throw 'OS_WM_CLOSE_REFUSED'}
   Check ($currentGui.WaitForExit(7000)) ('OS-01 native WM_CLOSE exits only GUI generation '+$cycle)
   Check (-not $hostProcess.HasExited -and
      $hostProcess.StartTime.ToUniversalTime().Ticks -eq $hostBorn) ('OS Host persists after GUI '+$cycle)
  }
  $lastGuiPid=$currentGui.Id
 }
 Check ($ownedGui.Count -eq ($Cycles+1)) 'OS exact GUI generation count'
 if($Cycles -eq 10){Check ($observedPids.Count -eq 11) 'OS-02 ten GUI process replacements'}
 if($InjectStartFailure){Check ($secondGui -ne $null) 'OS-19 injected first Process.Start failure followed by GUI A/B'}
 Check ($hostProcess.WaitForExit(($duration+15)*1000)) 'OS bounded cooperative Host exit'
 Check ($ownedGui[$ownedGui.Count-1].HasExited) 'OS final GUI exits through Host closeGeneration'
 $allExited=$true
 foreach($knownGui in $ownedGui){if(-not $knownGui.HasExited){$allExited=$false}}
 $safeToClean=($fail -eq 0 -and $hostProcess.HasExited -and $allExited)
}catch{
 $script:fail++
 Write-Output ('FAIL OS_EXCEPTION '+$_.Exception.Message)
}finally{
 # Dedicated trial Host has 35s (one cycle) or 120s (ten cycles) cooperative self-exit.
 # A failed GUI assertion is NOT permission to terminate it forcibly.
 if($hostProcess){
  try{if(-not $hostProcess.HasExited){[void]$hostProcess.WaitForExit(45000)}}catch{}
  try{$hostProcess.Refresh()}catch{}
 }
 if($outTask -and $outTask.IsCompleted){
  $out=[string]$outTask.Result
  if($out.Length>2000){$out=$out.Substring(0,2000)}
  Write-Output ('OS_HOST_STDOUT '+$out)
  $expectedGuiCount=$Cycles+1
  Check ($out.Contains('RC1_TRIAL_IPC_SNAPSHOT_GUI_COUNT='+$expectedGuiCount+' EVENT_GUI_COUNT='+$expectedGuiCount)) 'OS authenticated IPC snapshots and event polls for all GUI generations'
  if($out -match 'RC1_TRIAL_IPC_REJECTED=([0-9]+) TIMEOUTS=([0-9]+) PEAK_ACTIVE=([0-9]+)'){
   $rejectCount=[int]$Matches[1];$timeoutCount=[int]$Matches[2];$peak=[int]$Matches[3]
   Check ($rejectCount -ge 1 -and $timeoutCount -ge 1 -and $peak -le 2) 'OS-23 bounded oversize/partial frame refusal and worker limit'
  }else{Check $false 'OS-23 transport metrics available'}
  if($InjectConstructorFailure){
   Check ($out.Contains('RC1_TRIAL_CONSTRUCTOR_REFUSED_AND_CLEAN')) 'OS-21 partial constructor cleans IPC/mutex/private state, retry succeeds'
  }
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
 $liveGui=@($ownedGui|Where-Object{-not $_.HasExited})
 if($liveHost -or $liveGui.Count){$safeToClean=$false;Write-Output ('NOT CLEAN: test-owned process survivor(s) '+$liveGui.Count+'; NO FORCE KILL')}
 if($fail){$safeToClean=$false}
 # Independent OS inventory of any test-root command-line survivor.
 try{
  $survivors=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{
   $_.CommandLine -and $_.CommandLine.IndexOf($trial,[StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  Check ($survivors.Count -eq 0) 'OS independent no trial-root process survivors'
  if($survivors.Count){$safeToClean=$false}
  Write-Output ('OS_TRIAL_SURVIVOR_COUNT='+$survivors.Count)
 }catch{$script:fail++;$safeToClean=$false;Write-Output 'NOT CLEAN: OS survivor inventory unavailable'}
 # G7 F1: sentinel absence/unreadability/redirection is a mandatory FAIL.
 # Never proceed to cleanup before exact bytes, run binding and no-reparse.
 $sentinelOk=$false
 try{
  Assert-Rc1MandatorySentinel $runId $sentinelBytes $creation
  $sentinelOk=$true
 }catch{
  $safeToClean=$false
  Write-Output ('NOT CLEAN: mandatory sentinel refused '+$_.Exception.Message)
 }
 Check $sentinelOk 'OS mandatory outside sentinel exact bytes, path and run binding'
 if(-not $sentinelOk){$safeToClean=$false}
 # Process attestation is independently created next to (not inside) the root
 # only after OS-observed Host and GUI identities and absence of survivors.
 if($creation -and $hostProcess -and $hostProcess.HasExited -and $liveGui.Count -eq 0 -and
    $processRows.Count -ge 2 -and $survivors.Count -eq 0){
  try{
   New-Rc1AtExit $runId $creation ($processRows.ToArray())
   Write-Output ('OS_G7_ATTESTED_RUN='+$runId)
  }catch{
   $safeToClean=$false;$script:fail++
   Write-Output ('NOT CLEAN: process provenance not recorded '+$_.Exception.Message)
  }
 }else{
  $safeToClean=$false
  Write-Output 'NOT CLEAN: incomplete OS process attestation'
 }
 if($fail){$safeToClean=$false}
 if($safeToClean){
  try{
   Remove-Rc1AttestedFixture -runId $runId
   Write-Output 'OS_DISPOSABLE_CLEAN=TRUE'
  }catch{
   $script:fail++
   Write-Output ('NOT CLEAN: attested exact-file cleanup refused '+$_.Exception.Message)
  }
 }else{Write-Output ('NOT CLEAN: preserved exact trial root '+$trial+' PROOF='+ (Get-Rc1Paths $runId).Proof)}
 foreach($knownGui in $ownedGui){$knownGui.Dispose()}
 if($duplicateHost){$duplicateHost.Dispose()}
 if($hostProcess){$hostProcess.Dispose()}
}
Write-Output ('RC1_OS_SMOKE_PASS='+$pass+' FAIL='+$fail+' NOT_CHECKED='+$notChecked)
if($fail){exit 1}
exit 0
