# Isolated, user-approved observer-pilot update. Never controls Desktop Commander Remote.
# Non-executing by default. Only verified own Host can receive cooperative WM_QUIT.
param([switch]$Execute,[string]$Package,[int]$ExpectedHostPid=0,[long]$ExpectedHostBorn=0,
      [int]$ExpectedRemotePid=0,[long]$ExpectedRemoteBorn=0)
$ErrorActionPreference='Stop'
if(-not $Execute){Write-Output 'RC1_OBSERVER_UPGRADE_INERT_USE_EXECUTE';exit 42}
$repo=Split-Path -Parent $PSScriptRoot
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'RDCRelayOwnerPilot\1.6.0-RC1\app'
$pilotRoot=Split-Path -Parent $app
$expectedHostScript=Join-Path $app 'Source\rc1-tray-host.ps1'
$expectedExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$backup=$null
$moved=$false
function Assert-ExactPath([string]$path){
 $current=[IO.Path]::GetFullPath($path)
 while($current){
  if([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)){
   if(([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RC1_UPGRADE_REPARSE_DENIED'}
  }
  $parent=[IO.Path]::GetDirectoryName($current)
  if(-not $parent -or $parent -ceq $current){break}
  $current=$parent
 }
}
function Assert-Manifest([string]$dir){
 Assert-ExactPath $dir
 $manifestPath=Join-Path $dir 'owner-source-manifest.json'
 if(-not [IO.File]::Exists($manifestPath)){throw 'RC1_UPGRADE_MANIFEST_ABSENT'}
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($manifest.candidate -cne '1.6.0 RC1' -or
    $manifest.observerMode -cne 'OBSERVED_READ_ONLY_RC1' -or
    @($manifest.files).Count -ne 19){throw 'RC1_UPGRADE_WRONG_CANDIDATE'}
 $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
 foreach($row in $manifest.files){
  $name=[string]$row.name
  if($name -notmatch '^(Source/[A-Za-z0-9_.-]+|RdcOwnerRuntime\.dll|RC1 Pilot Launcher\.exe)$' -or
     -not $seen.Add($name)){throw 'RC1_UPGRADE_MANIFEST_NAME'}
  $file=Join-Path $dir ($name.Replace('/','\'))
  Assert-ExactPath $file
  if(-not [IO.File]::Exists($file) -or
     (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne [string]$row.sha256){
   throw ('RC1_UPGRADE_HASH_MISMATCH '+$name)
  }
 }
 $marker=Get-Content -LiteralPath (Join-Path $dir 'Source\rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($marker.installable -ne $true -or $marker.publishable -ne $false -or
    $marker.autoUpdateEnabled -ne $false -or
    $marker.observerMode -cne 'OBSERVED_READ_ONLY_RC1'){throw 'RC1_UPGRADE_MARKER'}
}
function Get-VerifiedHost{
 if($ExpectedHostPid -lt 1 -or $ExpectedHostBorn -lt 1){throw 'RC1_UPGRADE_HOST_EVIDENCE_REQUIRED'}
 $row=Get-CimInstance Win32_Process -Filter ('ProcessId='+$ExpectedHostPid)
 $proc=Get-Process -Id $ExpectedHostPid -ErrorAction Stop
 if(-not $row -or $proc.HasExited -or $proc.StartTime.ToUniversalTime().Ticks -ne $ExpectedHostBorn -or
    -not [string]::Equals([IO.Path]::GetFullPath([string]$row.ExecutablePath),
      [IO.Path]::GetFullPath($expectedExe),[StringComparison]::OrdinalIgnoreCase) -or
    ([string]$row.CommandLine).IndexOf($expectedHostScript,[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
    ([string]$row.CommandLine).IndexOf('-ObserveExisting',[StringComparison]::OrdinalIgnoreCase) -lt 0){
  throw 'RC1_UPGRADE_OWN_HOST_IDENTITY_MISMATCH'
 }
 $others=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
  ([string]$_.CommandLine).IndexOf((Join-Path $app 'Source\'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
  [int]$_.ProcessId -ne $ExpectedHostPid
 })
 if($others.Count -ne 0){throw ('RC1_UPGRADE_GUI_OR_OTHER_PROCESS_STILL_RUNNING '+$others.Count)}
 return $proc
}
function Assert-LiveRemote{
 if($ExpectedRemotePid -lt 1 -or $ExpectedRemoteBorn -lt 1){throw 'RC1_UPGRADE_REMOTE_EVIDENCE_REQUIRED'}
 $p=Get-Process -Id $ExpectedRemotePid -ErrorAction Stop
 if($p.HasExited -or $p.StartTime.ToUniversalTime().Ticks -ne $ExpectedRemoteBorn){
  throw 'RC1_UPGRADE_REMOTE_CHANGED'
 }
 . (Join-Path $repo 'Source\rc1-remote-observer.ps1')
 $id=Get-Rc1ObservedRemoteIdentity
 if($id.Pid -ne $ExpectedRemotePid -or $id.Born -ne $ExpectedRemoteBorn -or
   -not (Test-Rc1ObservedRemoteIdentity $id)){throw 'RC1_UPGRADE_REMOTE_IDENTITY_UNVERIFIED'}
}
try{
 if([string]::IsNullOrWhiteSpace($Package)){throw 'RC1_UPGRADE_PACKAGE_REQUIRED'}
 $Package=[IO.Path]::GetFullPath($Package)
 if([IO.Path]::GetDirectoryName($Package) -notlike '*\dist\RDCRelay-1.6.0-RC1-ObserverPilot-*'){
  throw 'RC1_UPGRADE_PACKAGE_NOT_ISOLATED'
 }
 Assert-Manifest $Package
 Assert-Manifest $app
 Assert-LiveRemote
 $hostProcess=Get-VerifiedHost
 # Own Host GUI must already have exited normally (X). Never terminate a GUI.
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Rc1PilotQuit {
 [DllImport("user32.dll",SetLastError=true)]
 public static extern bool PostThreadMessage(uint id,uint msg,UIntPtr w,IntPtr l);
}
'@
 $signalled=0
 foreach($thread in $hostProcess.Threads){
  try{if([Rc1PilotQuit]::PostThreadMessage([uint32]$thread.Id,0x0012,[UIntPtr]::Zero,[IntPtr]::Zero)){$signalled++}}catch{}
 }
 if($signalled -lt 1){throw 'RC1_UPGRADE_COOPERATIVE_HOST_QUIT_NOT_DELIVERED'}
 Write-Output ('RC1_UPGRADE_OWN_HOST_QUIT_MESSAGES='+$signalled)
 $exited=$false
 for($n=0;$n -lt 80;$n++){
  $present=Get-Process -Id $ExpectedHostPid -ErrorAction SilentlyContinue
  if($null -eq $present){$exited=$true;break}
  if($present.StartTime.ToUniversalTime().Ticks -ne $ExpectedHostBorn){
   throw 'RC1_UPGRADE_HOST_PID_REUSED'
  }
  Start-Sleep -Milliseconds 250
 }
 if(-not $exited){throw 'RC1_UPGRADE_OWN_HOST_DID_NOT_EXIT'}
 Write-Output 'RC1_UPGRADE_OLD_HOST_EXITED_COOPERATIVELY=TRUE'
 Assert-LiveRemote
 # All old payload is preserved in a new, exact, non-overwriting sibling.
 Assert-ExactPath $pilotRoot
 $backup=Join-Path $pilotRoot ('app-backup-'+[Guid]::NewGuid().ToString('N'))
 if([IO.Directory]::Exists($backup) -or [IO.File]::Exists($backup)){throw 'RC1_UPGRADE_BACKUP_COLLISION'}
 [IO.Directory]::Move($app,$backup);$moved=$true
 $setup=Join-Path $Package 'RC1 Pilot Setup.exe'
 Assert-ExactPath $setup
 $env:RDC_RC1_OWNER_G1_GO='YES'
 try{
  $setupProc=Start-Process -FilePath $setup -ArgumentList '--owner-approved-side-by-side' -Wait -PassThru
 }finally{Remove-Item Env:RDC_RC1_OWNER_G1_GO -ErrorAction SilentlyContinue}
 if($setupProc.ExitCode -ne 0){throw ('RC1_UPGRADE_SETUP_EXIT_'+$setupProc.ExitCode)}
 Assert-Manifest $app
 Write-Output ('RC1_UPGRADE_ROLLBACK_BACKUP='+$backup)
 Write-Output 'RC1_UPGRADE_NEW_SETUP_EXIT=0'
 # PowerShell Start-Process -Wait waits for DESCENDANTS including the durable
 # Host, so wait on the short-lived Launcher handle only.
 $launch=Start-Process -FilePath (Join-Path $app 'RC1 Pilot Launcher.exe') -ArgumentList '--observe-existing' -PassThru
 if(-not $launch.WaitForExit(15000)){throw 'RC1_UPGRADE_LAUNCHER_TIMEOUT'}
 if($launch.ExitCode -ne 0){throw ('RC1_UPGRADE_NEW_LAUNCHER_EXIT_'+$launch.ExitCode)}
 Start-Sleep -Seconds 4
 $newHosts=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
  ([string]$_.CommandLine).IndexOf((Join-Path $app 'Source\rc1-tray-host.ps1'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
  ([string]$_.CommandLine).IndexOf('-ObserveExisting',[StringComparison]::OrdinalIgnoreCase) -ge 0
 })
 if($newHosts.Count -ne 1){throw 'RC1_UPGRADE_NEW_HOST_NOT_UNIQUE'}
 Assert-LiveRemote
 Write-Output ('RC1_UPGRADE_NEW_HOST_PID='+$newHosts[0].ProcessId)
 Write-Output 'RC1_UPGRADE_REMOTE_PRESERVED=TRUE'
 Write-Output 'RC1_UPGRADE_COMPLETED=TRUE'
 exit 0
}catch{
 Write-Output ('RC1_UPGRADE_FAIL='+$_.Exception.Message)
 if($moved -and -not [IO.Directory]::Exists($app) -and [IO.Directory]::Exists($backup)){
  try{[IO.Directory]::Move($backup,$app);Write-Output 'RC1_UPGRADE_OLD_PAYLOAD_RESTORED=TRUE'}
  catch{Write-Output ('RC1_UPGRADE_RESTORE_REQUIRES_OWNER='+$_.Exception.Message)}
 }
 exit 42
}
