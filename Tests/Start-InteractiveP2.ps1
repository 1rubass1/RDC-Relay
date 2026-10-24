# Starts ONLY RDC-P2-<GUID> disposable GUI/Host, no real Remote.
# Launch from a Windows PowerShell 5.1 session with interactive Explorer.
param([switch]$Quiet)
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Prototypes\ARCH-016-P2'
$guid=[guid]::NewGuid().ToString('N')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P2-'+$guid)
if(Test-Path -LiteralPath $root){throw 'Fresh P2 fixture path already exists'}
[void](New-Item -ItemType Directory -Path $root -ErrorAction Stop)
foreach($file in @('P1Core.cs','P1Wire.cs','Host.ps1','Gui.ps1')){
  Copy-Item -LiteralPath (Join-Path $source $file) -Destination $root -ErrorAction Stop
}
Add-Type -Path (Join-Path $source 'P1Wire.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
$hostFile=Join-Path $root 'Host.ps1'
$psExe=Join-Path $PSHOME 'powershell.exe'
$arguments='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$hostFile+'" -FixtureRoot "'+$root+'" -Instance '+$guid+' -ControllerPid '+$PID+' -ControllerTicks '+[P1Wire]::Born($PID)+' -InteractiveDemo'
$process=Start-Process -FilePath $psExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
try{
  $auth=Join-Path $root 'controller-auth.json'
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not(Test-Path -LiteralPath $auth) -and $watch.ElapsedMilliseconds -lt 8000){
    if($process.HasExited){throw ('P2 Host failed to start; exit '+$process.ExitCode)}
    Start-Sleep -Milliseconds 110
  }
  if(-not(Test-Path -LiteralPath $auth)){throw ('Host did not create protected rendezvous; own Host PID '+$process.Id+' must be checked before intervention')}
  $secret=[P1Wire]::Decode([IO.File]::ReadAllText($auth,[Text.Encoding]::UTF8))
  $identity=([string]$secret.hostPid)+'|'+([string]$secret.hostTicks)+'|'+([string]$secret.hostSession)
  $seq=1
  $snapshot=$null
  for($i=0;$i -lt 24;$i++){
    $json=[P1Wire]::Request('TEST_STATE',[string]$secret.nonce,[string]$secret.hostGeneration,0,$null,[long]$seq)
    $seq++
    try{
      $answer=[P1Wire]::Decode([P1Wire]::Call([string]$secret.pipe,$identity,$json,900))
      if($answer.type -eq 'SNAPSHOT'){$snapshot=$answer.payload}
      if($snapshot -and $snapshot.guiConnected){break}
    }catch{}
    Start-Sleep -Milliseconds 180
  }
  Write-Output ('P2_DEMO_DIRECTORY='+$root)
  Write-Output ('P2_DEMO_HOST_PID='+$process.Id)
  if($snapshot){
    Write-Output ('P2_DEMO_GUI_PID='+$snapshot.guiPid)
    Write-Output ('P2_DEMO_FAKE_REMOTE='+$snapshot.remoteId)
    Write-Output ('P2_DEMO_TRAY_VISIBLE='+$snapshot.trayVisible)
    Write-Output ('P2_DEMO_GUI_BUILD='+$snapshot.guiBuild)
  }else{
    Write-Output 'P2_DEMO_GUI=NOT_CHECKED (Host started but GUI authentication not confirmed)'
  }
  Write-Output 'To change build: close GUI X, run Set-P2DemoBuild.ps1 -FixtureRoot <P2_DEMO_DIRECTORY> -Build B'
  Write-Output 'To reopen: double-click RDC Relay P2 SANDBOX tray icon.'
  Write-Output 'To stop only this demo: close GUI X, right-click the P2 tray icon and choose Stop P2 test Host.'
  Write-Output 'To remove only fixture files after Host exits: Remove-P2DemoFiles.ps1 -FixtureRoot <P2_DEMO_DIRECTORY>'
}finally{
  if($process.HasExited){$process.Dispose()}
}
