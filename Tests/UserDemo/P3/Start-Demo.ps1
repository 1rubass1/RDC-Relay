# Start only a fresh isolated P3 fixture, without installing anything.
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Fixture'
$state=Join-Path $PSScriptRoot 'RunState'
$marker=Join-Path $state 'active-demo.json'
function Get-DemoProcess([string]$Root){
  $hostScript=Join-Path $Root 'Host.ps1'
  return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop|Where-Object{
    ([string]$_.CommandLine).Contains(' -File "'+$hostScript+'"')
  })
}
if(Test-Path -LiteralPath $marker){
 try{
  $previous=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  $previousRoot=[IO.Path]::GetFullPath([string]$previous.Root).TrimEnd([char]92)
  if([IO.Path]::GetDirectoryName($previousRoot) -eq $temp -and [IO.Path]::GetFileName($previousRoot) -cmatch '^RDC-P3-[0-9a-f]{32}$'){
    $running=Get-DemoProcess $previousRoot
    if($running.Count){
      Write-Output ('Тестовый Host уже работает, PID: '+($running.ProcessId -join ','))
      Write-Output 'Используйте значок RDC Relay DEMO в системном трее.'
      exit 0
    }
  }
 }catch{Write-Output 'Не удалось проверить предыдущую запись запуска. Новые процессы пока не созданы.';throw}
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
$details=[pscustomobject]@{Root=$root;HostPID=$proc.Id;HostStartTicks=$proc.StartTime.ToUniversalTime().Ticks;DemoVersion='A'}
[IO.File]::WriteAllText($marker,($details|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($true)))
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
 & (Join-Path $PSScriptRoot 'Check-And-Cleanup.ps1')
 if(-not $?){throw 'SELFTEST: cleanup was not confirmed'}
 Write-Output 'P3_SELFTEST_EXIT=0'
}
