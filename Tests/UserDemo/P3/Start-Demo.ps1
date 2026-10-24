# Start only a fresh isolated P3 fixture, without installing anything.
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Fixture'
$state=Join-Path $PSScriptRoot 'RunState'
$marker=Join-Path $state 'active-demo.json'
. (Join-Path $PSScriptRoot 'P3-Ownership.ps1')
Assert-P3NoLinks $PSScriptRoot
if([IO.Directory]::Exists($state)){Assert-P3NoLinks $state}
elseif([IO.File]::Exists($state)){throw 'NOT CLEAN: RunState is not a directory'}
function Get-DemoProcess([string]$Root){
  $hostScript=Join-Path $Root 'Host.ps1'
  return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop|Where-Object{
    ([string]$_.CommandLine).Contains(' -File "'+$hostScript+'"')
  })
}
if(Test-Path -LiteralPath $marker){
  # Never silently replace a stale/altered marker or create a second Host.
  $old=Get-P3BoundRun $state
  throw ('NOT CLEAN: previous test run '+$old.MarkerData.RunId+' remains registered. Finish/verify cleanup first.')
}
$id=[guid]::NewGuid().ToString('N')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P3-'+$id)
if(Test-Path -LiteralPath $root){throw 'Случайное совпадение каталога: запуск отменён'}
[void](New-Item -ItemType Directory -Path $root -ErrorAction Stop)
foreach($name in @('Host.ps1','Gui.ps1','DemoGui.ps1','P1Core.cs','P1Wire.cs','rdc-banner.png')){
 Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $root $name) -ErrorAction Stop
}
Add-Type -Path (Join-Path $source 'P1Wire.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
$ps=Join-Path $PSHOME 'powershell.exe'
$hostScript=Join-Path $root 'Host.ps1'
$cmd='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$hostScript+'" -FixtureRoot "'+$root+'" -Instance '+$id+' -ControllerPid '+$PID+' -ControllerTicks '+[P1Wire]::Born($PID)+' -InteractiveDemo'
$proc=Start-Process -FilePath $ps -ArgumentList $cmd -WindowStyle Hidden -PassThru
$auth=Join-Path $root 'controller-auth.json'
$sw=[Diagnostics.Stopwatch]::StartNew()
while(-not(Test-Path -LiteralPath $auth) -and $sw.ElapsedMilliseconds -lt 9000){
 $proc.Refresh()
 if($proc.HasExited){throw ('Test Host failed; exit code '+$proc.ExitCode)}
 Start-Sleep -Milliseconds 120
}
if(-not(Test-Path -LiteralPath $auth)){throw ('Test Host has not created IPC rendezvous; PID '+$proc.Id)}
[void](New-Item -Path $state -ItemType Directory -Force)
Assert-P3NoLinks $state
Assert-P3NoLinks $marker $true
$info=[P1Wire]::Decode([IO.File]::ReadAllText($auth,[Text.Encoding]::UTF8))
$born=$proc.StartTime.ToUniversalTime().Ticks
if([int]$info.hostPid -ne $proc.Id -or [long]$info.hostTicks -ne $born){
 throw 'NOT CLEAN: actual Host PID/start time differs from authenticated rendezvous'
}
$proof=[guid]::NewGuid().ToString('N')
$hashes=@{}
foreach($name in @('Host.ps1','Gui.ps1','DemoGui.ps1','P1Core.cs','P1Wire.cs','rdc-banner.png')){
 $hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash
}
$details=[pscustomobject]@{Schema=1;RunId=$id;RunProof=$proof;Root=$root;HostPID=$proc.Id;HostStartTicks=$born;HostGeneration=[string]$info.hostGeneration;DemoVersion='A'}
$owner=[pscustomobject]@{Schema=1;RunId=$id;RunProof=$proof;Root=$root;HostPID=$proc.Id;HostStartTicks=$born;HostGeneration=[string]$info.hostGeneration;FileHashes=$hashes}
[IO.File]::WriteAllText((Join-Path $root 'p3-owner.json'),($owner|ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding($true)))
# CreateNew never opens an inserted marker/symlink between validation and write.
Assert-P3NoLinks $state
Assert-P3NoLinks $marker $true
$markerBytes=[Text.Encoding]::UTF8.GetBytes(($details|ConvertTo-Json -Compress))
$markerStream=New-Object IO.FileStream($marker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$markerStream.Write($markerBytes,0,$markerBytes.Length);$markerStream.Flush($true)}finally{$markerStream.Dispose()}
$check=Get-P3BoundRun $state
if($check.MarkerData.RunId -ne $id){throw 'NOT CLEAN: run marker attestation failed'}
Write-Output ('Тестовый RDC Relay запущен. Host PID: '+$proc.Id)
Write-Output ('Тестовый каталог: '+$root)
Write-Output 'Закройте окно X и снова откройте его через значок RDC Relay DEMO в трее.'
Write-Output 'Для версии B используйте соседний файл "GUI версия B.cmd".'
Write-Output 'Для полного завершения: контекстное меню тестового значка в трее.'
if($SelfTest){
 $record=[P1Wire]::Decode([IO.File]::ReadAllText($auth,[Text.Encoding]::UTF8))
 $ident=([string]$record.hostPid)+'|'+([string]$record.hostTicks)+'|'+([string]$record.hostSession)
 $seq=0
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $guiReady=$false
 while($watch.ElapsedMilliseconds -lt 8000){
  $seq++
  $wire=[P1Wire]::Request('TEST_STATE',[string]$record.nonce,[string]$record.hostGeneration,0,$null,[long]$seq)
  $answer=[P1Wire]::Decode([P1Wire]::Call([string]$record.pipe,$ident,$wire,1200))
  if($answer.type -eq 'SNAPSHOT' -and $answer.payload.guiConnected){$guiReady=$true;break}
  Start-Sleep -Milliseconds 140
 }
 if(-not $guiReady){throw 'SELFTEST: GUI did not authenticate'}
 Write-Output ('SELFTEST_GUI_A_PID='+$answer.payload.guiPid+' HOST_PID='+$answer.payload.hostPid)
 $seq++
 $wire=[P1Wire]::Request('TEST_USER_FINISH',[string]$record.nonce,[string]$record.hostGeneration,0,$null,[long]$seq)
 $exitAnswer=[P1Wire]::Decode([P1Wire]::Call([string]$record.pipe,$ident,$wire,1200))
 if($exitAnswer.type -ne 'SNAPSHOT'){throw 'SELFTEST: shared menu exit route rejected'}
 if(-not $proc.WaitForExit(9000)){throw 'SELFTEST: owned demo Host did not exit'}
 $cleanOutput=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Check-And-Cleanup.ps1') 2>&1)
 $cleanExit=$LASTEXITCODE
 $cleanOutput|ForEach-Object{Write-Output $_}
 if($cleanExit -ne 0){throw ('SELFTEST: cleanup failed with exit '+$cleanExit)}
 if([IO.Directory]::Exists($root)){throw 'SELFTEST: owned fixture directory survived'}
 if([IO.File]::Exists($marker)){throw 'SELFTEST: own-run marker survived'}
 if(@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object{
   ([string]$_.CommandLine).Contains(' -File "'+$hostScript+'"') -or
   ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $root 'Gui.ps1')+'"')
 }).Count){throw 'SELFTEST: own-run Host or GUI survived'}
 Write-Output 'P3_SELFTEST_EXIT=0'
}
