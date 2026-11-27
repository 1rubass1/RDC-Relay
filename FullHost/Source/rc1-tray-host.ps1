# RDC Relay 1.6.0 RC1 persistent product Tray Host entry point.
# FAKE_ONLY and OBSERVED_READ_ONLY remain isolated. Full mode either observes
# an external Remote without control or starts a new private Job-owned Remote.
param([switch]$FakeOnly,[switch]$ObserveExisting,[switch]$Full,[switch]$Background,[int]$ObserveAutoExitSeconds=0,
 [string]$TrialRoot='',[switch]$TrialFailGuiStartOnce,[switch]$TrialFailConstructorOnce,
 [int]$TrialAutoExitSeconds=0,[switch]$TrialReopenOnce,[int]$TrialReopenCount=0)
$ErrorActionPreference='Stop'
if($Background -and -not $Full){throw 'RC1_BACKGROUND_FULL_REQUIRED'}
if(([int][bool]$FakeOnly+[int][bool]$ObserveExisting+[int][bool]$Full) -ne 1){
 throw 'RC1_SELECT_EXACTLY_ONE_MODE'
}
if($Full -and ($TrialRoot -or $TrialFailGuiStartOnce -or $TrialFailConstructorOnce -or
 $TrialAutoExitSeconds -ne 0 -or $TrialReopenOnce -or $TrialReopenCount -ne 0 -or
 $ObserveAutoExitSeconds -ne 0)){throw 'RC1_FULL_TRIAL_FLAGS_FORBIDDEN'}
if($ObserveExisting -and ($TrialRoot -or $TrialFailGuiStartOnce -or $TrialFailConstructorOnce -or
 $TrialAutoExitSeconds -ne 0 -or $TrialReopenOnce -or $TrialReopenCount -ne 0)){
 throw 'RC1_OBSERVER_TRIAL_FLAGS_FORBIDDEN'
}
if($ObserveAutoExitSeconds -ne 0 -and (-not $ObserveExisting -or
 $ObserveAutoExitSeconds -lt 15 -or $ObserveAutoExitSeconds -gt 60)){
 throw 'RC1_OBSERVER_AUTOEXIT_BOUNDS'
}
$root=[IO.Path]::GetFullPath($PSScriptRoot)
foreach($name in @('remote-window.ps1','rc1-owner-gui.ps1','rc1-quota-client.ps1','RdcOwnerWire.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerProcess.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs')){
 if(-not [IO.File]::Exists((Join-Path $root $name))){throw ('RC1_REQUIRED_RUNTIME_MISSING: '+$name)}
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $root 'RdcOwnerWire.cs'),(Join-Path $root 'RdcOwnerProcess.cs'),(Join-Path $root 'RdcOwnerTicketStore.cs'),(Join-Path $root 'RdcOwnerRemoteState.cs'),(Join-Path $root 'RdcOwnerManagedProcess.cs'),(Join-Path $root 'RdcOwnerLogParts.cs'),(Join-Path $root 'RdcOwnerStartup.cs'),(Join-Path $root 'RdcUiLanguage.cs'),(Join-Path $root 'RdcOwnerRuntime.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
if($Background -and (-not [RdcOwnerStartup]::IsActiveSource($root) -or [RdcOwnerStartup]::State() -ne 1)){throw 'RC1_STARTUP_INSTALL_REQUIRED'}
# The old source-root mutex is release-specific. Before starting a product
# Full Host, refuse any second RC1 Host from another release root; otherwise
# two idle Hosts could both acquire independent mutexes and later start Remote.
if($Full){
 try{
  $otherHosts=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop |
   Where-Object { $_.ProcessId -ne $PID -and
    $_.CommandLine -match '(?i)-File\s+"?[^"]*rc1-tray-host\.ps1"?\s+-Full(?:\s|$)' })
 }catch{throw 'RC1_OTHER_RELEASE_HOST_SCAN_UNAVAILABLE'}
 if($otherHosts.Count -gt 0){throw 'RC1_OTHER_RELEASE_HOST_STILL_RUNNING'}
}
$owner=$null
$observerTimer=$null
$quotaTimer=$null
$script:quotaPollProcess=$null
function Test-Rc1QuotaDisplayEnabled([string]$path) {
 try {
  if([string]::IsNullOrWhiteSpace($path)){return $false}
  # No preference is the historical behavior: quota display and refresh ON.
  if(-not [IO.File]::Exists($path)){return $true}
  $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if(($file.Length -ne 10 -and $file.Length -ne 11) -or
     ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
  # 'enabled-v1' is accepted for migration from the uninstalled G101 trial.
  # Explicit 'disabled-v1', malformed files and IO errors fail closed.
  return [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq 'enabled-v1'
 }catch{return $false}
}
$quotaDisplayPath=Join-Path (Join-Path $env:LOCALAPPDATA 'RDCRelayOwnerPilot') 'quota-display.opt-in'
try{
 if($ObserveExisting -or $Full){
  . (Join-Path $root 'rc1-remote-observer.ps1')
  $owner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true)
  $observer=$null
  if($Full){
   try{$observer=Initialize-Rc1RemoteObserver $owner}catch{
    $reason=[string]$_.Exception.Message
    if($reason -match 'RC1_OBSERVER_AMBIGUOUS_OR_ABSENT_0|RC1_OBSERVER_LEGACY_LOG_NOT_FOUND'){
     # Do not start real Remote until the first GUI has authenticated to Host.
     # Managed auto-start is armed by EnableManagedRemote and gated by GUI HELLO.
     $owner.EnableManagedRemote()
    }else{throw}
   }
  }else{$observer=Initialize-Rc1RemoteObserver $owner}
  if($observer){
  # Read-only monitoring does not send ANY command to the pinned Remote.
  Invoke-Rc1RemoteObserverPoll $owner $observer
  $observerClock=[Diagnostics.Stopwatch]::StartNew()
  $observerTimer=New-Object Windows.Forms.Timer
  $observerTimer.Interval=750
  $observerTimer.Add_Tick({
   try{Invoke-Rc1RemoteObserverPoll $owner $observer}catch{
    $owner.UpdateObservedRemote($false,'Fault','RC1 observer failed; Remote not controlled')
   }
   if($observer.HandoffComplete){
    $observerTimer.Stop()
    # Managed autostart is gated by the replacement GUI's authenticated
    # HELLO in the Host pulse; never spawn Remote during GUI transition.
    return
   }
   if($ObserveAutoExitSeconds -gt 0 -and $observerClock.Elapsed.TotalSeconds -ge $ObserveAutoExitSeconds){
    $owner.RequestObservedDetach()
   }
  })
  $observerTimer.Start()
  }
 }else{
 if($TrialReopenOnce -and $TrialReopenCount -ne 0){throw 'RC1_TRIAL_REOPEN_CONFLICT'}
 if($TrialReopenCount -lt 0 -or $TrialReopenCount -gt 10){throw 'RC1_TRIAL_REOPEN_LIMIT'}
 if($TrialRoot){
  $reopenCount=if($TrialReopenOnce){1}else{$TrialReopenCount}
  if($TrialFailConstructorOnce){
   $temporaryOwner=$null
   try{
    $temporaryOwner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true,$TrialRoot,
     $false,$TrialAutoExitSeconds,[int]$reopenCount,$true)
    if($temporaryOwner){$temporaryOwner.Dispose()}
    throw 'RC1_TRIAL_CONSTRUCTOR_DID_NOT_FAIL'
   }catch{
    if(-not $_.Exception.ToString().Contains('RC1_TRIAL_INJECTED_CONSTRUCTOR_FAILURE')){throw}
   }
   $ownState=Join-Path $TrialRoot 'owner-state'
   if([IO.Directory]::Exists($ownState) -and
      [IO.Directory]::GetFileSystemEntries($ownState).Length -ne 0){throw 'RC1_TRIAL_CONSTRUCTOR_LEFT_FILES'}
   Write-Output 'RC1_TRIAL_CONSTRUCTOR_REFUSED_AND_CLEAN'
  }
  $owner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true,$TrialRoot,
   [bool]$TrialFailGuiStartOnce,$TrialAutoExitSeconds,[int]$reopenCount)
 }else{
  if($TrialFailGuiStartOnce -or $TrialFailConstructorOnce -or $TrialAutoExitSeconds -ne 0 -or $TrialReopenOnce -or $TrialReopenCount -ne 0){throw 'RC1_TRIAL_ROOT_REQUIRED'}
  $owner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true)
 }
 } # end fake-only trial/normal route
 # Full Host may have started its OWN Remote; an existing external Remote
 # is still observed passively without importing any process-stop authority.
 if(-not $Background){
 $owner.OpenGui()
 # Retry one immediately rejected GUI spawn only after the ticket store has
 # proved cleanup (NONE). Never retry an unverified child or a live GUI.
 if(-not $TrialRoot -and $owner.Status -ceq 'NONE'){$owner.OpenGui()}
 # A new product Host with no GUI must not leave a misleading tray icon.
 # Propagate only a fixed failure category; never log private ticket data.
 if(-not $TrialRoot -and $owner.Status -in @('NONE','UNVERIFIED')){
  throw ('RC1_INITIAL_GUI_'+$owner.Status)
 }
 }
 if($TrialFailGuiStartOnce){
  if($owner.Status -cne 'NONE'){throw 'RC1_TRIAL_F2_TICKET_NOT_RETRYABLE'}
  Write-Output 'RC1_TRIAL_F2_FIRST_START_REFUSED_AND_CLEAN'
  $owner.OpenGui()
 }
 if($TrialRoot){Write-Output ('RC1_TRIAL_GUI_STATUS='+$owner.Status+' LAST_ERROR='+$owner.LastGuiError)}
 # A separate strictly read-only OAuth MCP client polls only who_am_i.
 # The device-agent session is never reused, logged out or inspected.
 if($Full -and -not $TrialRoot){
  $quotaScript=Join-Path $root 'rc1-quota-client.ps1'
  $script:quotaPolicy=New-Object RdcOwnerQuotaRefreshPolicy
  $script:quotaClock=[Diagnostics.Stopwatch]::StartNew()
  $script:quotaPollProcess=$null
  $script:quotaAttemptAccount=''
  $script:quotaAttemptObserved=[DateTime]::MinValue
  $quotaCache=[RdcOwnerTrayQuotaSnapshot]::CachePath
  $quotaVault=Join-Path (Join-Path $env:LOCALAPPDATA 'RDCRelayOwnerPilot') 'quota-oauth-user.dpapi'
  $quotaTimer=New-Object Windows.Forms.Timer
  $quotaTimer.Interval=15000
  $quotaTimer.Add_Tick({
   # Persistent script-scoped scheduler state survives WinForms event scopes.
   # GUI-open hints never start another worker or bypass failure backoff.
   try{
    $now=[DateTime]::UtcNow
    $elapsed=[long][Math]::Floor($script:quotaClock.Elapsed.TotalSeconds)
    if($script:quotaPollProcess -and $script:quotaPollProcess.HasExited){
     $completed=[RdcOwnerTrayQuotaSnapshot]::Inspect($quotaCache,$script:quotaAttemptAccount,$now)
     $success=$completed.Fresh($now,5) -and $completed.ObservedUtc -gt $script:quotaAttemptObserved
     $script:quotaPolicy.Complete($elapsed,$success)
     $script:quotaPollProcess.Dispose();$script:quotaPollProcess=$null
     $script:quotaAttemptAccount='';$script:quotaAttemptObserved=[DateTime]::MinValue
    }
    $enabled=Test-Rc1QuotaDisplayEnabled $quotaDisplayPath
    $activeAccount=[string]$owner.ActiveManagedAccount
    $eligibleAccount=[string]$owner.QuotaManagedAccount
    $generation=[long]$owner.QuotaGuiOpenGeneration
    if(-not $enabled -or -not $eligibleAccount){
     [void]$script:quotaPolicy.Decide($elapsed,$enabled,'','',$generation,'unknown',$false,$false,[bool]$script:quotaPollProcess)
     return
    }
    $observation=[RdcOwnerTrayQuotaSnapshot]::Inspect($quotaCache,$eligibleAccount,$now)
    $vaultState=[RdcOwnerTrayQuotaSnapshot]::VaultState($quotaVault)
    $cacheState=if($vaultState -ceq 'unknown'){'unknown'}else{$observation.State}
    $mode=$script:quotaPolicy.Decide($elapsed,$enabled,$eligibleAccount,$activeAccount,$generation,
     $cacheState,$observation.Fresh($now,5),($vaultState -ceq 'present'),[bool]$script:quotaPollProcess)
    if(-not $mode){return}
    # Recheck the current preference and account immediately before spawn.
    if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath) -or
       -not [string]::Equals($eligibleAccount,[string]$owner.QuotaManagedAccount,[StringComparison]::OrdinalIgnoreCase) -or
       ($mode -ceq '-Authorize' -and -not [string]::Equals($eligibleAccount,[string]$owner.ActiveManagedAccount,[StringComparison]::OrdinalIgnoreCase))){
     $script:quotaPolicy.Complete($elapsed,$false);return
    }
    $script:quotaAttemptAccount=$eligibleAccount
    $script:quotaAttemptObserved=$observation.ObservedUtc
    try{
     $script:quotaPollProcess=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
      '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$quotaScript+'"'),$mode
     ) -WindowStyle Hidden -PassThru -ErrorAction Stop
    }catch{$script:quotaPolicy.Complete($elapsed,$false)}
   }catch{} # Host and Remote remain usable if quota state is unavailable.
  })
  # Initial/periodic refresh, plus a bounded hint from each GUI generation.
  $quotaTimer.Start()
 }
 $owner.Run()
}finally{
 if($quotaTimer){$quotaTimer.Stop();$quotaTimer.Dispose()}
 if($script:quotaPollProcess){$script:quotaPollProcess.Dispose()}
 if($observerTimer){$observerTimer.Stop();$observerTimer.Dispose()}
 if($owner){$owner.Dispose()}
}
