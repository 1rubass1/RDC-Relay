# RDC Relay 1.6.0 RC1 persistent product Tray Host entry point.
# This source branch is NOT an installer or live-Remote candidate.
# Require explicit -FakeOnly; real Remote supervision is blocked pending
# owner-approved disposable OS process tree testing and independent review.
param([switch]$FakeOnly,[string]$TrialRoot='',
 [switch]$TrialFailGuiStartOnce,[int]$TrialAutoExitSeconds=0,[switch]$TrialReopenOnce)
$ErrorActionPreference='Stop'
if(-not $FakeOnly){throw 'RC1_NOT_AUTHORIZED_FOR_LIVE_REMOTE'}
$root=[IO.Path]::GetFullPath($PSScriptRoot)
foreach($name in @('remote-window.ps1','rc1-owner-gui.ps1','RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerProcess.cs')){
 if(-not [IO.File]::Exists((Join-Path $root $name))){throw ('RC1_REQUIRED_RUNTIME_MISSING: '+$name)}
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $root 'RdcOwnerWire.cs'),(Join-Path $root 'RdcOwnerProcess.cs'),(Join-Path $root 'RdcOwnerTicketStore.cs'),(Join-Path $root 'RdcOwnerRemoteState.cs'),(Join-Path $root 'RdcOwnerRuntime.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.dll')
$owner=$null
try{
 if($TrialRoot){
  $owner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true,$TrialRoot,
   [bool]$TrialFailGuiStartOnce,$TrialAutoExitSeconds,[bool]$TrialReopenOnce)
 }else{
  if($TrialFailGuiStartOnce -or $TrialAutoExitSeconds -ne 0 -or $TrialReopenOnce){throw 'RC1_TRIAL_ROOT_REQUIRED'}
  $owner=New-Object RdcOwnerRuntime -ArgumentList @($root,$true)
 }
 # Only verified own GUI process may be launched. The host never discovers,
 # starts, adopts, reconnects or kills a real Desktop Commander Remote.
 $owner.OpenGui()
 if($TrialFailGuiStartOnce){
  if($owner.Status -cne 'NONE'){throw 'RC1_TRIAL_F2_TICKET_NOT_RETRYABLE'}
  Write-Output 'RC1_TRIAL_F2_FIRST_START_REFUSED_AND_CLEAN'
  $owner.OpenGui()
 }
 if($TrialRoot){Write-Output ('RC1_TRIAL_GUI_STATUS='+$owner.Status+' LAST_ERROR='+$owner.LastGuiError)}
 $owner.Run()
}finally{
 if($owner){$owner.Dispose()}
}
