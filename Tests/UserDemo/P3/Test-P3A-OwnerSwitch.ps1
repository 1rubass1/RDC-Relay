# P3A: end-to-end owner A -> X -> safe Switch-GuiBuild -> B -> own Exit.
$ErrorActionPreference='Stop'
$ps=Join-Path $PSHOME 'powershell.exe'
$state=Join-Path $PSScriptRoot 'RunState'
$marker=Join-Path $state 'active-demo.json'
if([IO.File]::Exists($marker)){throw 'Cannot run alongside an existing owner demo'}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class P3AOwnerClose {
 [DllImport("user32.dll",SetLastError=true)]
 public static extern bool PostMessage(IntPtr hwnd,uint msg,IntPtr a,IntPtr b);
}
'@
$script:seq=0;$run=$null;$hostProc=$null;$pass=0;$failed=$false
function Assert([bool]$yes,[string]$label){
 if(-not $yes){throw ('FAIL '+$label)}
 $script:pass++;Write-Output ('PASS '+$label)
}
function Send([string]$verb){
 $script:seq++
 $wire=[P1Wire]::Request($verb,[string]$script:auth.nonce,[string]$script:auth.hostGeneration,0,$null,[long]$script:seq)
 return [P1Wire]::Decode([P1Wire]::Call([string]$script:auth.pipe,$script:identity,$wire,1200))
}
function Await([scriptblock]$predicate,[int]$limit=15000){
 $sw=[Diagnostics.Stopwatch]::StartNew();$last=''
 do{
  try{
   $result=Send 'TEST_STATE'
   if($result.type -eq 'SNAPSHOT' -and (& $predicate $result.payload)){return $result.payload}
  }catch{$last=$_.Exception.Message}
  Start-Sleep -Milliseconds 180
 }while($sw.ElapsedMilliseconds -lt $limit)
 throw ('Fixture state timeout; last IPC error '+$last)
}
try{
 & (Join-Path $PSScriptRoot 'Start-Demo.ps1') | Out-Null
 . (Join-Path $PSScriptRoot 'P3-Ownership.ps1')
 $run=Get-P3BoundRun $state
 $hostProc=[Diagnostics.Process]::GetProcessById([int]$run.MarkerData.HostPID)
 Assert ($hostProc.StartTime.ToUniversalTime().Ticks -eq [long]$run.MarkerData.HostStartTicks) 'owned Host PID and birth time'
 $script:auth=[P1Wire]::Decode([IO.File]::ReadAllText((Join-Path $run.Root 'controller-auth.json'),[Text.Encoding]::UTF8))
 $script:identity=([string]$auth.hostPid)+'|'+([string]$auth.hostTicks)+'|'+([string]$auth.hostSession)
 $a=Await {param($s) $s.guiConnected -and $s.guiBuild -eq 'A'}
 $guiRow=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$a.guiPid))
 Assert ($guiRow.Count -eq 1 -and $guiRow[0].ParentProcessId -eq $hostProc.Id -and
 ([string]$guiRow[0].CommandLine).Contains(' -File "'+(Join-Path $run.Root 'Gui.ps1')+'"')) 'GUI A belongs to exactly this Host'
 $aProc=[Diagnostics.Process]::GetProcessById([int]$a.guiPid)
 $aIdentity=$aProc.Id.ToString()+'|'+$aProc.StartTime.ToUniversalTime().Ticks
 $hwnd=$aProc.MainWindowHandle
 Assert ($hwnd -ne [IntPtr]::Zero -and [P3AOwnerClose]::PostMessage($hwnd,16,[IntPtr]::Zero,[IntPtr]::Zero)) 'close only owned GUI A with WM_CLOSE'
 Assert ($aProc.WaitForExit(8000)) 'GUI A process ended'
 $aProc.Dispose()
 [void](Await {param($s) $s.guiPid -eq 0})
 $switch=@(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Switch-GuiBuild.ps1'))
 $exitCode=$LASTEXITCODE
 Assert ($exitCode -eq 0) ('A-to-B update helper exit 0: '+($switch -join ' '))
 $newBound=Get-P3BoundRun $state
 Assert ([string]$newBound.OwnerData.FileHashes.'DemoGui.ps1' -ceq (Get-FileHash (Join-Path $newBound.Root 'DemoGui.ps1') -Algorithm SHA256).Hash) 'updated B hash is correctly bound to own-run metadata'
 [void](Send 'TEST_TRAY_DOUBLE_CLICK')
 $b=Await {param($s) $s.guiConnected -and $s.guiBuild -eq 'B'}
 $bProc=[Diagnostics.Process]::GetProcessById([int]$b.guiPid)
 $bIdentity=$bProc.Id.ToString()+'|'+$bProc.StartTime.ToUniversalTime().Ticks
 Assert ($aIdentity -cne $bIdentity -and $a.hostPid -eq $b.hostPid -and $a.remoteId -eq $b.remoteId) 'real B process, same Host PID and mock UUID'
 $bProc.Dispose()
 $ending=Send 'TEST_USER_FINISH'
 Assert ($ending.type -eq 'SNAPSHOT' -and $hostProc.WaitForExit(10000)) 'shared owner Exit stops own B GUI and Host'
 $hostProc.Dispose();$hostProc=$null
 $clean=@(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Check-And-Cleanup.ps1'))
 Assert ($LASTEXITCODE -eq 0 -and -not [IO.Directory]::Exists($run.Root) -and -not [IO.File]::Exists($marker)) 'owner A-B cleanup removed only own root and marker'
}catch{
 $failed=$true
 Write-Output ('FAIL '+$_.Exception.Message)
}finally{
 if($run -and [IO.Directory]::Exists($run.Root)){
  try{
   if($script:auth -and $hostProc -and -not $hostProc.HasExited){
    $s=Send 'TEST_USER_FINISH'
    if($s.type -eq 'SNAPSHOT' -and $hostProc.WaitForExit(9000)){
     $hostProc.Dispose()
     $p=Start-Process -FilePath $ps -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Check-And-Cleanup.ps1')+'"') -PassThru -Wait -WindowStyle Hidden
     if($p.ExitCode -eq 0){Write-Output 'OWN_FAIL_FIXTURE_RECOVERED'}
     else{Write-Output ('NOT CLEAN own fixture '+$run.Root)}
     $p.Dispose()
    }
   }
  }catch{Write-Output ('NOT CLEAN owned fixture '+$run.Root+' '+$_.Exception.Message)}
 }
}
Write-Output ('P3A_OWNER_SWITCH_PASS='+$pass+' FAIL='+[int]$failed)
if($failed){exit 1};exit 0
