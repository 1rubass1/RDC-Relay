# G96: isolated account-switch contract and private-Job logout execution.
# Only a generated fake npx.cmd under Windows TEMP is executed; no real
# Desktop Commander, credentials, browser, Host, Remote or network operations.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-SWITCH-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$fake=Join-Path $root 'npx.cmd'
$pass=0;$fail=0;$job=$null;$second=$null
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
function Wait-OwnCompletion($process) {
 $result=[pscustomobject]@{Finished=$false;ExitCode=-999}
 for($i=0;$i -lt 80;$i++){
  $exitCode=0
  if($process.TryGetCompletedExitCode([ref]$exitCode)){
   $result.Finished=$true;$result.ExitCode=$exitCode;break
  }
  Start-Sleep -Milliseconds 50
 }
 return $result
}
try{
 $hostSource=Get-Content -LiteralPath (Join-Path $repo 'Source\RdcOwnerRuntime.cs') -Raw -Encoding UTF8
 $guiSource=Get-Content -LiteralPath (Join-Path $repo 'Source\remote-window.ps1') -Raw -Encoding UTF8
 $ownerSource=Get-Content -LiteralPath (Join-Path $repo 'Source\rc1-owner-gui.ps1') -Raw -Encoding UTF8
 Check ($hostSource.Contains('void BeginManagedAccountSwitch()') -and
  $hostSource.Contains('StopManagedRemote();') -and
  $hostSource.Contains('if(AnotherDesktopCommanderRemote()||AnotherLegacyShell())') -and
  $hostSource.Contains('if(action=="SWITCH_ACCOUNT")BeginManagedAccountSwitch();')) 'Host owns logout route after verified Remote stop'
 Check ($hostSource.Contains('accountLogoutProcess.TryGetCompletedExitCode(out code)') -and
  $hostSource.Contains('if(code!=0)throw') -and
  $hostSource.Contains('StartManagedRemote();') -and
  $hostSource.Contains('accountLogoutDeadlineUtc=DateTime.UtcNow.AddSeconds(60)')) 'success, failure and timeout have distinct outcomes'
 Check ($hostSource.Contains('"switchAccount",managedMode && !observedMode && trialRoot==null') -and
  $hostSource.Contains('if(accountLogoutProcess!=null)return Error(requestId,"ACCOUNT_CHANGE_IN_PROGRESS")')) 'adopted/fake/busy account actions denied by Host'
 Check ($guiSource.Contains('$script:ownerQueuedAction=''SWITCH_ACCOUNT''') -and
  $guiSource.Contains('[Windows.Forms.MessageBoxButtons]::YesNo') -and
  $ownerSource.Contains('$script:ownerCanSwitchAccount=[bool]$snapshot.capabilities.switchAccount')) 'confirmation and GUI follow authenticated capability'
 Check (-not $hostSource.Contains('device.json') -and
  -not $hostSource.Contains('.mqtt/identity.json')) 'Host never directly edits official device credentials'
 [IO.File]::WriteAllLines($fake,@('@echo off','if "%~4"=="--logout" exit /b 0','exit /b 23'),[Text.Encoding]::ASCII)
 Add-Type -Path (Join-Path $repo 'Source\RdcOwnerManagedProcess.cs')
 $job=New-Object RdcOwnerManagedProcess
 $blocked=$false
 try{$job.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout --extra',
  $root,(Join-Path $root 'invalid.log'))}catch{$blocked=$true}
 Check $blocked 'logout accepts only exact pinned package and arguments'
 $job.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout',
  $root,(Join-Path $root 'logout-success.log'))
 $result=Wait-OwnCompletion $job
 Check ($result.Finished -and $result.ExitCode -eq 0 -and -not $job.Running) 'fake logout exit 0, Job fully drained'
 $job.Dispose();$job=$null
 [IO.File]::WriteAllLines($fake,@('@echo off','exit /b 23'),[Text.Encoding]::ASCII)
 $second=New-Object RdcOwnerManagedProcess
 $second.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout',
  $root,(Join-Path $root 'logout-fail.log'))
 $result=Wait-OwnCompletion $second
 Check ($result.Finished -and $result.ExitCode -eq 23 -and -not $second.Running) 'fake logout failure exit 23 cannot be mistaken for success'
}catch{$fail++;Write-Output ('FAIL unexpected '+$_.Exception.GetType().Name+': '+$_.Exception.Message)}
finally{
 $safe=$true
 foreach($proc in @($job,$second)){
  if($null -eq $proc){continue}
  try{
   if($proc.Running){$safe=$proc.StopOwnedOnly(10000) -and $safe}
  }catch{$safe=$false}
  $proc.Dispose()
 }
 try{
  if(-not $safe){throw 'DISPOSABLE_JOB_SURVIVOR'}
  if([IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92) -or
    [IO.Path]::GetFileName($root) -cnotmatch '^RDC-RC1-SWITCH-[a-f0-9]{32}$'){throw 'TEMP_BOUNDARY'}
  foreach($item in @(Get-ChildItem -LiteralPath $root -Force)){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
     @('npx.cmd','logout-success.log','logout-fail.log') -cnotcontains $item.Name){throw 'UNKNOWN_TEMP_MEMBER'}
  }
  [IO.Directory]::Delete($root,$true)
  Check (-not [IO.Directory]::Exists($root)) 'disposable fake-only switch fixture cleaned'
 }catch{$fail++;Write-Output ('FAIL cleanup retained '+$root+' '+$_.Exception.Message)}
}
Write-Output ('RC1_OWNER_SWITCH_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
