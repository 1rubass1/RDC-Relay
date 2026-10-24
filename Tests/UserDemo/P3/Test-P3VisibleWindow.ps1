# OS-level visible GUI/window check on disposable P2 fixture in current desktop.
# No mouse/keyboard injection, no Explorer restart, no product/real Remote calls.
$ErrorActionPreference='Stop'
$src=Join-Path $PSScriptRoot 'Fixture'
$guid=[guid]::NewGuid().ToString('N')
$dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P3-'+$guid)
$hostProcess=$null;$auth=$null;$script:seq=0;$failed=$false
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $src 'P1Wire.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class P3NativeClose {
  [DllImport("user32.dll",SetLastError=true)]
  public static extern bool PostMessage(IntPtr hwnd,int msg,IntPtr wparam,IntPtr lparam);
}
'@
function Assert([bool]$v,[string]$why){if(-not $v){throw $why}}
function Send([string]$verb){
    $script:seq++
    $wire=[P1Wire]::Request($verb,[string]$script:auth.nonce,[string]$script:auth.hostGeneration,0,$null,[long]$script:seq)
    return [P1Wire]::Decode([P1Wire]::Call([string]$script:auth.pipe,$script:identity,$wire,1200))
}
function Await([scriptblock]$predicate,[int]$deadline=12500){
    $sw=[Diagnostics.Stopwatch]::StartNew()
    do{
        try{
            $r=Send 'TEST_STATE'
            if($r.type -eq 'SNAPSHOT' -and (& $predicate $r.payload)){return $r.payload}
        }catch{}
        Start-Sleep -Milliseconds 140
    }while($sw.ElapsedMilliseconds -lt $deadline)
    throw ('State timed out '+$deadline+'ms')
}
function WindowOf([int]$guiPid){
    $guiFile=Join-Path $dir 'Gui.ps1'
    $row=@(Get-CimInstance Win32_Process -Filter ("ProcessId="+$guiPid))
    Assert ($row.Count -eq 1 -and ([string]$row[0].CommandLine).Contains(' -File "'+$guiFile+'"') -and $row[0].ParentProcessId -eq $hostProcess.Id) 'GUI PID is not an owned P2 child'
    $proc=[Diagnostics.Process]::GetProcessById($guiPid)
    $sw=[Diagnostics.Stopwatch]::StartNew()
    do{
        $proc.Refresh()
        if($proc.MainWindowHandle -ne [IntPtr]::Zero -and $proc.MainWindowTitle.Contains('демонстрация')){return $proc.MainWindowHandle}
        Start-Sleep -Milliseconds 120
    }while($sw.ElapsedMilliseconds -lt 5000)
    throw ('Visible GUI main HWND not found for PID '+$guiPid)
}
try{
    [void](New-Item -ItemType Directory -Path $dir)
    foreach($n in @('P1Core.cs','P1Wire.cs','Host.ps1','Gui.ps1','DemoGui.ps1','rdc-banner.png')){Copy-Item -LiteralPath (Join-Path $src $n) -Destination $dir}
    $hostFile=Join-Path $dir 'Host.ps1'
    $psExe=Join-Path $PSHOME 'powershell.exe'
    $args='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$hostFile+'" -FixtureRoot "'+$dir+'" -Instance '+$guid+' -ControllerPid '+$PID+' -ControllerTicks '+[P1Wire]::Born($PID)+' -InteractiveDemo'
    $hostProcess=Start-Process -FilePath $psExe -ArgumentList $args -WindowStyle Hidden -PassThru
    $authPath=Join-Path $dir 'controller-auth.json'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path $authPath) -and $watch.ElapsedMilliseconds -lt 8500){
        if($hostProcess.HasExited){throw 'P3 Host exited before auth file'}
        Start-Sleep -Milliseconds 125
    }
    Assert (Test-Path $authPath) 'Host auth rendezvous absent'
    $script:auth=[P1Wire]::Decode([IO.File]::ReadAllText($authPath,[Text.Encoding]::UTF8))
    $script:identity=([string]$auth.hostPid)+'|'+([string]$auth.hostTicks)+'|'+([string]$auth.hostSession)
    $a=Await {param($s) $s.guiConnected -and $s.guiBuild -eq 'A'}
    Assert ([bool]$a.trayVisible -and $a.fake) 'P3 interactive NotifyIcon not set visible'
    $hwndA=WindowOf([int]$a.guiPid)
    Write-Output ('VISIBLE_GUI_A_PID='+$a.guiPid+' HWND='+$hwndA)
    Write-Output ('PERSISTENT_HOST_PID='+$a.hostPid+' FAKE_REMOTE_ID='+$a.remoteId)
    Start-Sleep -Milliseconds 700
    Assert ([P3NativeClose]::PostMessage($hwndA,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'native WM_CLOSE to owned GUI A failed'
    $closed=Await {param($s) $s.guiPid -eq 0}
    Assert ($closed.hostPid -eq $a.hostPid -and $closed.remoteId -eq $a.remoteId) 'Host changed after native GUI close'
    Write-Output ('PASS: native WM_CLOSE closed GUI A; Host='+$closed.hostPid)
    $gui=Join-Path $dir 'DemoGui.ps1'
    $original=[IO.File]::ReadAllText($gui,[Text.Encoding]::UTF8)
    Assert ($original.Contains("$"+"GuiBuild='A'")) 'P3 A build marker missing'
    $setter=Join-Path $PSScriptRoot 'Set-GuiBuild.ps1'
    $setOutput=@(& $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $setter -FixtureRoot $dir -Build B 2>&1)
    Assert ($LASTEXITCODE -eq 0) ('owner demo build helper failed: '+($setOutput -join ' '))
    Assert ([IO.File]::ReadAllText($gui,[Text.Encoding]::UTF8).Contains("$"+"GuiBuild='B'")) 'helper did not update fixture GUI source'
    $before=Send 'TEST_STATE'
    $reopen=Send 'TEST_TRAY_DOUBLE_CLICK'
    Assert ($reopen.type -eq 'SNAPSHOT') 'same tray-open handler did not return'
    $b=Await {param($s) $s.guiConnected -and $s.guiBuild -eq 'B'}
    Assert ($b.hostPid -eq $a.hostPid -and $b.remoteId -eq $a.remoteId -and $b.guiPid -ne $a.guiPid) 'GUI B broke persistent Host contract'
    $hwndB=WindowOf([int]$b.guiPid)
    Write-Output ('VISIBLE_GUI_B_PID='+$b.guiPid+' HWND='+$hwndB)
    Write-Output ('TRAY_ACTIVATIONS='+$b.trayActivations)
    Assert ((Send 'TEST_TRAY_DOUBLE_CLICK').payload.guiPid -eq $b.guiPid) 'double dispatch spawned duplicate GUI'
    $current=$b
    $currentHwnd=$hwndB
    $cyclePids=New-Object Collections.Generic.HashSet[int]
    [void]$cyclePids.Add([int]$a.guiPid)
    for($cycle=1;$cycle -le 10;$cycle++){
        Assert ([P3NativeClose]::PostMessage($currentHwnd,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'native owned GUI close failed'
        $down=Await {param($s) $s.guiPid -eq 0}
        Assert ($down.hostPid -eq $a.hostPid -and $down.remoteId -eq $a.remoteId) 'Host or fake UUID changed during GUI cycles'
        [void](Send 'TEST_TRAY_DOUBLE_CLICK')
        $current=Await {param($s) $s.guiConnected -and $s.guiBuild -eq 'B'}
        Assert (-not $cyclePids.Contains([int]$current.guiPid)) 'GUI PID repeated within demo fixture'
        [void]$cyclePids.Add([int]$current.guiPid)
        $currentHwnd=WindowOf([int]$current.guiPid)
    }
    Write-Output ('PASS: 10 complete native GUI close-and-reopen cycles; distinct GUI PIDs='+$cyclePids.Count)
    # Invoke the exact test-owned exit route shared with the tray Exit menu.
    $ending=Send 'TEST_USER_FINISH'
    Assert ($ending.type -eq 'SNAPSHOT') 'test-only confirmed P3 exit route denied'
    Assert ($hostProcess.WaitForExit(8000)) 'P3 Host did not exit after its own GUI finished'
    Write-Output ('PASS: shared user-exit route closed own GUI and test Host; host PID '+$a.hostPid+' unchanged until exit')
} catch{
    $failed=$true
    Write-Output ('FAIL: '+$_.Exception.Message)
} finally {
    if($hostProcess -and -not $hostProcess.HasExited){
        try{
            $row=@(Get-CimInstance Win32_Process -Filter ("ProcessId="+$hostProcess.Id))
            if($row.Count -eq 1 -and ([string]$row[0].CommandLine).Contains(' -File "'+(Join-Path $dir 'Host.ps1')+'"') -and $hostProcess.StartTime.ToUniversalTime().Ticks -eq [P1Wire]::Born($hostProcess.Id)){
                if($script:auth){
                    $s=Send 'TEST_STATE'
                    if($s.payload.guiPid -gt 0){[void](Send 'TEST_CLOSE');[void](Await {param($s) $s.guiPid -eq 0} 5000)}
                    [void](Send 'TEST_END')
                    Assert ($hostProcess.WaitForExit(7500)) 'test Host did not exit cooperatively'
                }
            }else{throw 'Host process identity cannot be verified for IPC cleanup'}
        }catch{$failed=$true;Write-Output ('CLEANUP_FAIL='+$_.Exception.Message)}
    }
    $remaining=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object{
        ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $dir 'Host.ps1')+'"') -or
        ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $dir 'Gui.ps1')+'"')
    })
    Write-Output ('VISIBLE_FIXTURE_SURVIVORS='+(@($remaining|ForEach-Object{$_.ProcessId}) -join ','))
    if($remaining.Count){$failed=$true}
    if($hostProcess -and $hostProcess.HasExited){$hostProcess.Dispose()}
    if(-not $failed){
        try{Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop}
        catch{$failed=$true;Write-Output ('CLEANUP_FAIL='+$_.Exception.Message)}
    }
    if($failed){Write-Output ('NOT_CLEAN_VISIBLE_FIXTURE='+$dir)}
}
if($failed){exit 1}
Write-Output 'P3_VISIBLE_WINDOW_TEST_EXIT=0'
