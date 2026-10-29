# Real Windows managed-mode GUI/IPC attach, intentionally NO Remote startup.
# This test does not call Runtime.Run or TryAutoStartManagedRemote.
param([int]$TimeoutSeconds=25)
$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'
$owner=$null
$gui=$null
$failed=$false
$remoteBefore=$null
function RemoteSnapshot {
 $rows=@(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
  Where-Object {$_.CommandLine -match '@wonderwhy-er/desktop-commander@0\.2\.52 remote'})
 return @($rows|ForEach-Object {
  [PSCustomObject]@{Pid=[int]$_.ProcessId;Birth=([datetime]$_.CreationDate).ToUniversalTime().Ticks}
 })
}
try{
 $remoteBefore=@(RemoteSnapshot)
 if($remoteBefore.Count -lt 1 -or $remoteBefore.Count -gt 4){throw 'OS_TEST_REQUIRES_EXISTING_PINNED_REMOTE'}
 $self=[Diagnostics.Process]::GetCurrentProcess()
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 Add-Type -Path @(
  (Join-Path $src 'RdcOwnerWire.cs'),(Join-Path $src 'RdcOwnerProcess.cs'),
  (Join-Path $src 'RdcOwnerTicketStore.cs'),(Join-Path $src 'RdcOwnerRemoteState.cs'),
  (Join-Path $src 'RdcOwnerManagedProcess.cs'),(Join-Path $src 'RdcOwnerRuntime.cs')
 ) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll',
  'System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
 $owner=New-Object RdcOwnerRuntime -ArgumentList @($src,$true)
 $owner.EnableManagedRemote()
 if($owner.TryAutoStartManagedRemote()){throw 'PRE_GUI_AUTOSTART_MUST_REFUSE'}
 'OS_REMOTE_PRE_GUI_START_REFUSED=TRUE'
 $owner.OpenGui()
 $end=[datetime]::UtcNow.AddSeconds($TimeoutSeconds)
 $guiRow=$null
 while([datetime]::UtcNow -lt $end){
  $rows=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
   $_.ParentProcessId -eq $PID -and $_.CommandLine -match '-OwnerGui\s' -and
   $_.CommandLine -match [regex]::Escape((Join-Path $src 'remote-window.ps1'))
  })
  if($rows.Count -eq 1){$guiRow=$rows[0];$gui=Get-Process -Id $guiRow.ProcessId -ErrorAction Stop}
  if($owner.Status -ceq 'CONNECTED' -and $gui -and $gui.MainWindowHandle -ne [IntPtr]::Zero){break}
  Start-Sleep -Milliseconds 250
 }
 if($owner.Status -cne 'CONNECTED' -or -not $gui -or $gui.MainWindowHandle -eq [IntPtr]::Zero){
  throw ('MANAGED_GUI_ATTACH_FAILED_STATUS_'+$owner.Status+'_CATEGORY_'+($owner.LastGuiError -split ':')[0])
 }
 'OS_MANAGED_GUI_AUTHENTICATED=TRUE'
 'OS_MANAGED_GUI_WINDOW_PRESENT=TRUE'
 'OS_MANAGED_GUI_PID='+$gui.Id
 $remoteAfter=@(RemoteSnapshot)
 $beforeIds=@($remoteBefore|ForEach-Object{[string]$_.Pid+'|'+[string]$_.Birth}|Sort-Object)
 $afterIds=@($remoteAfter|ForEach-Object{[string]$_.Pid+'|'+[string]$_.Birth}|Sort-Object)
 if($beforeIds.Count -ne $afterIds.Count -or (@(Compare-Object $beforeIds $afterIds).Count -ne 0)){
  throw 'EXTERNAL_REMOTE_IDENTITY_CHANGED'
 }
 'OS_EXISTING_REMOTE_IDENTITY_UNCHANGED=TRUE'
} catch{
 $failed=$true
 'OS_MANAGED_GUI_TEST_ERROR='+$_.Exception.Message
}finally{
 if($gui){
  try{
   if(-not $gui.HasExited){
    $close=$gui.CloseMainWindow()
    'OS_GUI_COOPERATIVE_CLOSE_REQUESTED='+$close
    if(-not $close -or -not $gui.WaitForExit(15000)){$failed=$true;'OS_GUI_NOT_CLEAN=TRUE'}
   }
  }catch{$failed=$true;'OS_GUI_CLOSE_ERROR_CATEGORY='+$_.Exception.GetType().Name}
 }
 if($owner){
  try{
   $m=$owner.GetType().GetMethod('RefreshGui',[Reflection.BindingFlags]'Instance,NonPublic')
   if($m){$m.Invoke($owner,@())|Out-Null}
   if($owner.Status -ne 'NONE'){$failed=$true;'OS_UNVERIFIED_GUI_STATUS='+$owner.Status}
   $owner.Dispose()
  }catch{$failed=$true;'OS_HOST_NOT_CLEAN_CATEGORY='+$_.Exception.GetType().Name}
 }
 $remoteFinal=@(RemoteSnapshot)
 if($remoteBefore.Count -ge 1){
  $beforeIds=@($remoteBefore|ForEach-Object{[string]$_.Pid+'|'+[string]$_.Birth}|Sort-Object)
  $finalIds=@($remoteFinal|ForEach-Object{[string]$_.Pid+'|'+[string]$_.Birth}|Sort-Object)
  if($beforeIds.Count -ne $finalIds.Count -or (@(Compare-Object $beforeIds $finalIds).Count -ne 0)){
   $failed=$true;'OS_REMOTE_FINAL_MISMATCH=TRUE'
  }
 }
}
if($failed){exit 1}
'OS_MANAGED_GUI_TICKET_PASS=TRUE'
exit 0
