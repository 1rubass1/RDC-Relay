# RDC Relay 1.6.0 RC1 persistent product Tray Host entry point.
# Candidate supports isolated fake testing OR read-only observation of the
# user's already running pinned Remote, never start/stop/reconnect/logout.
param([switch]$FakeOnly,[switch]$ObserveExisting,[int]$ObserveAutoExitSeconds=0,
 [string]$TrialRoot='',[switch]$TrialFailGuiStartOnce,[switch]$TrialFailConstructorOnce,
 [int]$TrialAutoExitSeconds=0,[switch]$TrialReopenOnce,[int]$TrialReopenCount=0)
$ErrorActionPreference='Stop'
if([bool]$FakeOnly -eq [bool]$ObserveExisting){throw 'RC1_SELECT_EXACTLY_ONE_MODE'}
if($ObserveExisting -and ($TrialRoot -or $TrialFailGuiStartOnce -or $TrialFailConstructorOnce -or
 $TrialAutoExitSeconds -ne 0 -or $TrialReopenOnce -or $TrialReopenCount -ne 0)){
 throw 'RC1_OBSERVER_TRIAL_FLAGS_FORBIDDEN'
}
if($ObserveAutoExitSeconds -ne 0 -and (-not $ObserveExisting -or
 $ObserveAutoExitSeconds -lt 15 -or $ObserveAutoExitSeconds -gt 60)){
 throw 'RC1_OBSERVER_AUTOEXIT_BOUNDS'
}
$root=[IO.Path]::GetFullPath($PSScriptRoot)
foreach($name in @('remote-window.ps1','rc1-owner-gui.ps1','RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerProcess.cs')){
 if(-not [IO.File]::Exists((Join-Path $root $name))){throw ('RC1_REQUIRED_RUNTIME_MISSING: '+$name)}
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $root 'RdcOwnerWire.cs'),(Join-Path $root 'RdcOwnerProcess.cs'),(Join-Path $root 'RdcOwnerTicketStore.cs'),(Join-Path $root 'RdcOwnerRemoteState.cs'),(Join-Path $root 'RdcOwnerRuntime.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.dll')
$owner=$null
$observerTimer=$null
try{
 if($ObserveExisting){
  . (Join-Path $root 'rc1-remote-observer.ps1')
  $owner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true)
  $observer=Initialize-Rc1RemoteObserver $owner
  # Read-only monitoring does not send ANY command to the pinned Remote.
  Invoke-Rc1RemoteObserverPoll $owner $observer
  $observerClock=[Diagnostics.Stopwatch]::StartNew()
  $observerTimer=New-Object Windows.Forms.Timer
  $observerTimer.Interval=750
  $observerTimer.Add_Tick({
   try{Invoke-Rc1RemoteObserverPoll $owner $observer}catch{
    $owner.UpdateObservedRemote($false,'Fault','RC1 observer failed; Remote not controlled')
   }
   if($ObserveAutoExitSeconds -gt 0 -and $observerClock.Elapsed.TotalSeconds -ge $ObserveAutoExitSeconds){
    $owner.RequestObservedDetach()
   }
  })
  $observerTimer.Start()
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
 # Only the RC1 GUI is started here. Real Remote observation is passive:
 # no process spawn, stop, restart, adoption of kill authority or logout.
 $owner.OpenGui()
 if($TrialFailGuiStartOnce){
  if($owner.Status -cne 'NONE'){throw 'RC1_TRIAL_F2_TICKET_NOT_RETRYABLE'}
  Write-Output 'RC1_TRIAL_F2_FIRST_START_REFUSED_AND_CLEAN'
  $owner.OpenGui()
 }
 if($TrialRoot){Write-Output ('RC1_TRIAL_GUI_STATUS='+$owner.Status+' LAST_ERROR='+$owner.LastGuiError)}
 $owner.Run()
}finally{
 if($observerTimer){$observerTimer.Stop();$observerTimer.Dispose()}
 if($owner){$owner.Dispose()}
}
