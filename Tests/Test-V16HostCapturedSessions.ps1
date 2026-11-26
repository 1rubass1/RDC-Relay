# Exercise actual Host capture/start/refresh/stop with a local synthetic npx.cmd.
# No normal Host construction, WMI discovery, npx/npm, real Remote, or IPC.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$src=Join-Path $repo 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs')|ForEach-Object{Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RdcEndSessionProbe {
 [DllImport("user32.dll",EntryPoint="SendMessageW")]
 public static extern IntPtr Send(IntPtr hwnd,uint msg,IntPtr wParam,IntPtr lParam);
 [DllImport("user32.dll")]
 public static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll")]
 public static extern IntPtr GetParent(IntPtr hwnd);
}
'@
$window=$null
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-HOST-LOG-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$fake=Join-Path $root 'npx.cmd'
$logs=Join-Path $root 'Logs'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$runtime=[Runtime.Serialization.FormatterServices]::GetUninitializedObject([RdcOwnerRuntime])
$state=New-Object RdcOwnerRemoteState
$state.EnableManaged()
$pass=0
function Check([bool]$ok,[string]$name){if(-not $ok){throw ('FAIL '+$name)};$script:pass++;Write-Output ('PASS '+$name)}
function Set-Field([string]$name,[object]$value){$runtime.GetType().GetField($name,$flags).SetValue($runtime,$value)}
function Get-Field([string]$name){$runtime.GetType().GetField($name,$flags).GetValue($runtime)}
function Call-Host([string]$name,[object[]]$parameters){$method=$runtime.GetType().GetMethod($name,$flags);if($parameters.Count -eq 2){$method.Invoke($runtime,[object[]]@([string]$parameters[0],[string]$parameters[1]))}else{$method.Invoke($runtime,$null)}}
function Wait-State([string]$expected){
 $timer=[Diagnostics.Stopwatch]::StartNew()
 do{[void](Call-Host RefreshManagedRemote @());if($state.Snapshot()['state'] -ceq $expected){return $true};Start-Sleep -Milliseconds 25}while($timer.ElapsedMilliseconds -lt 6000)
 return $false
}
function Read-Previous{
 $parts=@(Get-ChildItem -LiteralPath (Join-Path $logs 'PreviousSession') -File -Filter '*.log')
 if($parts.Count -ne 1){throw 'FIXTURE_EXPECT_ONE_PART'}
 [IO.File]::ReadAllText($parts[0].FullName)
}
try{
 Set-Field 'gate' (New-Object object)
 Set-Field 'sourceRoot' $root
 Set-Field 'managedMode' $true
 Set-Field 'remoteSupervisor' $state
 Set-Field 'toolJournal' (New-Object RdcOwnerToolJournal)
 Set-Field 'managedLogStream' (New-Object RdcOwnerUtf8LogBuffer)
 Set-Field 'events' (New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[string,object]]')
 Set-Field 'managedBannerArt' (New-Object 'System.Collections.Generic.List[string]')
 Set-Field 'managedStartupHeader' (New-Object 'System.Collections.Generic.List[string]')
 [IO.File]::WriteAllText($fake,"@echo off"+[Environment]::NewLine+'echo Desktop Commander Remote is connected'+[Environment]::NewLine+'echo test-raw-stderr 1>&2'+[Environment]::NewLine+'ping.exe -n 30 127.0.0.1 > NUL'+[Environment]::NewLine)
 [void](Call-Host StartManagedCapture @($fake,$logs))
 Check (Wait-State 'Ready') 'actual Host parser consumes captured pipe and establishes Ready'
 Check (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession\.rdc-accepted-v1')) 'Host persists acceptance only after readiness evidence'
 Check (-not (Test-Path -LiteralPath (Join-Path $logs 'PreviousSession'))) 'new accepted current is not prematurely published'
 [void](Call-Host StopManagedRemote @())
 Check ($state.Snapshot()['state'] -ceq 'Disconnected' -and $null -eq (Get-Field 'managedLogPump')) 'explicit Stop drains and closes actual Host capture'
 $first=Read-Previous
 Check ($first.Contains('Desktop Commander Remote is connected') -and $first.Contains('test-raw-stderr')) 'completed session includes both original streams'
 [IO.File]::WriteAllText($fake,"@echo off"+[Environment]::NewLine+'echo Device startup failed: test'+[Environment]::NewLine+'exit /b 9'+[Environment]::NewLine)
 [void](Call-Host StartManagedCapture @($fake,$logs))
 Check (Wait-State 'Disconnected') 'failed synthetic Job exits and Host notices'
 $timer=[Diagnostics.Stopwatch]::StartNew()
 while($null -ne (Get-Field 'managedLogSessions') -and $timer.ElapsedMilliseconds -lt 4000){[void](Call-Host RefreshManagedRemote @());Start-Sleep -Milliseconds 25}
 Check ($null -eq (Get-Field 'managedLogSessions') -and -not (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession'))) 'failed current finalized after verified Job completion'
 $failed=@(Get-ChildItem -LiteralPath (Join-Path $logs 'LastUnacceptedSession') -File -Filter '*.log')
 Check ($failed.Count -eq 1 -and [IO.File]::ReadAllText($failed[0].FullName).Contains('Device startup failed: test')) 'failed output retained in independent slot'
 Check ((Read-Previous) -ceq $first) 'failed launch does not replace successful previous'
 [IO.File]::WriteAllText($fake,"@echo off"+[Environment]::NewLine+'echo Desktop Commander Remote is connected'+[Environment]::NewLine+'echo second-session'+[Environment]::NewLine+'ping.exe -n 30 127.0.0.1 > NUL'+[Environment]::NewLine)
 [void](Call-Host StartManagedCapture @($fake,$logs))
 Check (Wait-State 'Ready') 'next valid session can start after failed launch'
 [void](Call-Host StopManagedRemote @())
 Check ((Read-Previous).Contains('second-session') -and -not (Read-Previous).Contains('test-raw-stderr')) 'next valid completion replaces previous only once'
 Check ([IO.File]::ReadAllText($failed[0].FullName).Contains('Device startup failed: test')) 'successful session does not remove failed output'
 # Deliver real native messages only to our isolated hidden test HWND.
 # No OS shutdown, broadcast, logoff, reboot or real Host process is used.
 [IO.File]::WriteAllText($fake,"@echo off"+[Environment]::NewLine+'echo Desktop Commander Remote is connected'+[Environment]::NewLine+'echo windows-end-session'+[Environment]::NewLine+'ping.exe -n 30 127.0.0.1 > NUL'+[Environment]::NewLine)
 [void](Call-Host StartManagedCapture @($fake,$logs))
 Check (Wait-State 'Ready') 'new session ready for Windows notification test'
 $before=Read-Previous
 $action=[Delegate]::CreateDelegate([Action],$runtime,$runtime.GetType().GetMethod('ConfirmWindowsEndSession',$flags))
 $window=New-Object RdcOwnerEndSessionWindow -ArgumentList $action
 Check ($window.Handle -ne [IntPtr]::Zero -and -not [RdcEndSessionProbe]::IsWindowVisible($window.Handle) -and [RdcEndSessionProbe]::GetParent($window.Handle) -eq [IntPtr]::Zero) 'native notification window is hidden and top-level'
 $job=Get-Field 'managedProcess'
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $reply=[RdcEndSessionProbe]::Send($window.Handle,0x11,[IntPtr]::Zero,[IntPtr]::Zero)
 Check ($reply.ToInt64() -eq 1 -and $watch.ElapsedMilliseconds -lt 1000 -and $job.Running) 'query immediately permits end-session without stopping Remote'
 [void][RdcEndSessionProbe]::Send($window.Handle,0x16,[IntPtr]::Zero,[IntPtr]::Zero)
 Check ($job.Running -and (Get-Field 'windowsEnding') -eq 0 -and (Read-Previous) -ceq $before -and (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession'))) 'cancelled Windows end-session neither stops nor rotates'
 $watch.Restart()
 [void][RdcEndSessionProbe]::Send($window.Handle,0x16,[IntPtr]1,[IntPtr]::Zero)
 Check ($watch.ElapsedMilliseconds -lt 3000 -and -not $job.Running -and (Get-Field 'windowsEnding') -eq 1) 'confirmed notification stops verified Job within callback budget'
 Check ($null -eq (Get-Field 'managedLogSessions') -and -not (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession')) -and (Read-Previous).Contains('windows-end-session')) 'confirmed shutdown drains then publishes successful session'
 $after=Read-Previous
 [void][RdcEndSessionProbe]::Send($window.Handle,0x16,[IntPtr]1,[IntPtr]::Zero)
 Check ((Read-Previous) -ceq $after) 'duplicate confirmation is idempotent'
 $denied=$false
 try{[void](Call-Host StartManagedCapture @($fake,$logs))}catch{$denied=$_.Exception.ToString().Contains('RC1_WINDOWS_ENDING')}
 Check $denied 'confirmed end-session denies new Remote launch'
 $window.Dispose();$window=$null
 # Fresh synthetic lifetime. An unaccepted authorization attempt must
 # preserve previous even if Windows ends the session while it is pending.
 Set-Field 'windowsEnding' 0
 [IO.File]::WriteAllText($fake,"@echo off"+[Environment]::NewLine+'echo waiting for authentication'+[Environment]::NewLine+'ping.exe -n 30 127.0.0.1 > NUL'+[Environment]::NewLine)
 [void](Call-Host StartManagedCapture @($fake,$logs))
 Check (Wait-State 'AuthPending') 'unaccepted session waiting for authorization'
 $window=New-Object RdcOwnerEndSessionWindow -ArgumentList $action
 [void][RdcEndSessionProbe]::Send($window.Handle,0x16,[IntPtr]1,[IntPtr]([long]2147483648))
 Check ((Read-Previous) -ceq $after -and -not (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession'))) 'confirmed logoff during failed/pending startup preserves previous'
 $window.Dispose();$window=$null
 # An in-flight action can hold Host gate. Confirmation never waits for it.
 Set-Field 'windowsEnding' 0
 [IO.File]::WriteAllText($fake,"@echo off"+[Environment]::NewLine+'echo Desktop Commander Remote is connected'+[Environment]::NewLine+'echo deferred-recovery'+[Environment]::NewLine+'ping.exe -n 30 127.0.0.1 > NUL'+[Environment]::NewLine)
 [void](Call-Host StartManagedCapture @($fake,$logs))
 Check (Wait-State 'Ready') 'accepted current before simulated shutdown contention'
 $job=Get-Field 'managedProcess'
 $window=New-Object RdcOwnerEndSessionWindow -ArgumentList $action
 $g=Get-Field 'gate'
 [Threading.Monitor]::Enter($g)
 try{
  $watch.Restart()
  [void][RdcEndSessionProbe]::Send($window.Handle,0x16,[IntPtr]1,[IntPtr]::Zero)
  Check ($watch.ElapsedMilliseconds -lt 1000 -and (Get-Field 'windowsEnding') -eq 1 -and $job.Running -and (Read-Previous) -ceq $after) 'busy gate defers to recovery without blocking end-session or shifting previous'
 }finally{[Threading.Monitor]::Exit($g)}
 # Model OS teardown AFTER callback: only stop the exact fixture Job, let
 # its pump drain, then release the session lease WITHOUT Host publication.
 Check ($job.StopOwnedOnly(10000)) 'simulated teardown drains fixture Job'
 $pump=Get-Field 'managedLogPump'
 Check ($pump.WaitForCompletion(3000) -and $pump.CleanEof) 'simulated teardown leaves committed raw parts'
 $store=Get-Field 'managedLogSessions'
 $store.Dispose();$job.Dispose()
 Set-Field 'managedLogSessions' $null;Set-Field 'managedLogPump' $null;Set-Field 'managedProcess' $null
 Check ((Read-Previous) -ceq $after -and (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession'))) 'interrupted callback leaves recoverable current and intact previous'
 $recovered=New-Object RdcOwnerLogSessions -ArgumentList $logs
 try{$recovered.Recover()}finally{$recovered.Dispose()}
 Check ((Read-Previous).Contains('deferred-recovery') -and -not (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession'))) 'next session store recovers accepted log after incomplete Windows shutdown'
 $window.Dispose();$window=$null
 Set-Field 'windowsEnding' 0;Set-Field 'managedMode' $false;Set-Field 'observedMode' $true
 $observedPrevious=Read-Previous
 $window=New-Object RdcOwnerEndSessionWindow -ArgumentList $action
 [void][RdcEndSessionProbe]::Send($window.Handle,0x16,[IntPtr]1,[IntPtr]::Zero)
 Check ((Read-Previous) -ceq $observedPrevious -and -not (Test-Path -LiteralPath (Join-Path $logs 'CurrentSession'))) 'observed mode cannot publish or modify owned session storage'

}finally{
 if($window){$window.Dispose()}
 $job=Get-Field 'managedProcess'
 $pump=Get-Field 'managedLogPump'
 $store=Get-Field 'managedLogSessions'
 $safe=$true
 if($job -and $job.HasStarted){
  try{$code=0;if(-not $job.TryGetCompletedExitCode([ref]$code)){$safe=$job.StopOwnedOnly(10000)}}catch{$safe=$false}
 }
 if($pump -and -not $pump.WaitForCompletion(3000)){$safe=$false}
 if(-not $safe){throw 'HOST_LOG_FIXTURE_SURVIVOR_RETAIN'}
 if($store){$store.Dispose()}
 if($job){$job.Dispose()}
 if([IO.Path]::GetFileName($root) -cnotmatch '^RDC-HOST-LOG-[a-f0-9]{32}$' -or [IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)){throw 'HOST_LOG_FIXTURE_SCOPE'}
 foreach($e in Get-ChildItem -LiteralPath $root -Force){
  if(($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @('Logs','npx.cmd') -cnotcontains $e.Name){throw 'HOST_LOG_FIXTURE_UNKNOWN'}
 }
 if([IO.Directory]::Exists($logs)){
  foreach($e in Get-ChildItem -LiteralPath $logs -Force){
   if(($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @('CurrentSession','PreviousSession','RetiredSession','LastUnacceptedSession','RetiredUnacceptedSession','.rdc-session-lock-v1') -cnotcontains $e.Name){throw 'HOST_LOG_FIXTURE_UNKNOWN'}
   if($e.PSIsContainer){
    foreach($f in Get-ChildItem -LiteralPath $e.FullName -Force){
     if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Name -cnotmatch '^(\.rdc-(session|accepted)-v1|\d{4}-\d{2}-\d{2}_part-\d+\.log)$'){throw 'HOST_LOG_FIXTURE_UNKNOWN_PART'}
    }
   }
  }
 }
 [IO.Directory]::Delete($root,$true)
}
Write-Output ('RDC_HOST_LOG_PASS='+$pass)
