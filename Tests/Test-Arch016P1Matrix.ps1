# ARCH-016-P1 matrix: disposable powershell.exe Host and GUI, FAKE REMOTE ONLY.
param([switch]$InjectFailureAtGui)
$ErrorActionPreference='Stop'
$src=Join-Path $PSScriptRoot 'Prototypes\ARCH-016-P1'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $src 'P1Wire.cs'),(Join-Path $src 'P1Core.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll')
$psExe=Join-Path $PSHOME 'powershell.exe'
$id=[guid]::NewGuid().ToString('N')
$dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P1-'+$id)
$hostProcess=$null
$pass=0;$fail=0;$notChecked=0
function Assert([bool]$ok,[string]$why){if(-not $ok){throw $why}}
function Check([string]$code,[scriptblock]$body){
    try{& $body;Write-Output ('PASS '+$code);$script:pass++}
    catch{Write-Output ('FAIL '+$code+': '+$_.Exception.Message);$script:fail++}
}
function NotChecked([string]$code,[string]$why){Write-Output ('NOT CHECKED '+$code+': '+$why);$script:notChecked++}
function Await([scriptblock]$predicate,[int]$deadline=11000) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        try{
            $r=Send 'TEST_STATE'
            if(& $predicate $r.payload){return $r.payload}
        }catch{}
        Start-Sleep -Milliseconds 140
    }while($watch.ElapsedMilliseconds -lt $deadline)
    throw ('Timed out: '+$deadline+'ms')
}
function Send([string]$verb,[long]$after=0,[string]$requestId=''){
    if(-not $script:auth){throw 'fixture control auth not initialized'}
    if(-not $requestId){$requestId=[guid]::NewGuid().ToString('N')}
    $raw=[P1Wire]::Request($verb,[string]$script:auth.nonce,[string]$script:auth.hostGeneration,$after,$requestId)
    return [P1Wire]::Decode([P1Wire]::Call([string]$script:auth.pipe,$script:identity,$raw,900))
}
function RawFrame([byte[]]$header,[byte[]]$body) {
    $c=New-Object IO.Pipes.NamedPipeClientStream('.',[string]$script:auth.pipe,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    try{
        $c.Connect(700)
        $c.Write($header,0,$header.Length)
        if($body){$c.Write($body,0,$body.Length)}
        $c.Flush()
    } finally {$c.Dispose()}
}
function GuiReady {return (Await {param($s) $s.guiConnected -and $s.guiPid -gt 0})}
function CloseGui{
    $a=Send 'TEST_CLOSE'
    return (Await {param($s) $s.guiPid -eq 0})
}
function WmiResidual {
    $rows=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'")
    return @($rows|Where-Object {
        $cmd=[string]$_.CommandLine
        $cmd.IndexOf($script:dir,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        ($cmd.IndexOf('Host.ps1',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $cmd.IndexOf('Gui.ps1',[StringComparison]::OrdinalIgnoreCase) -ge 0)
    })
}
try {
    [void](New-Item -ItemType Directory -Force -Path $dir)
    foreach($name in @('P1Wire.cs','P1Core.cs','Host.ps1','Gui.ps1')){
        Copy-Item -LiteralPath (Join-Path $src $name) -Destination $dir
    }
    $guiPath=Join-Path $dir 'Gui.ps1'
    $hostPath=Join-Path $dir 'Host.ps1'
    $script:hostArgs='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$hostPath+'" -FixtureRoot "'+$dir+'" -Instance '+$id+' -ControllerPid '+$PID+' -ControllerTicks '+[P1Wire]::Born($PID)
    $hostProcess=Start-Process -FilePath $psExe -ArgumentList $script:hostArgs -WindowStyle Hidden -PassThru
    $script:hostBirth=$hostProcess.StartTime.ToUniversalTime().Ticks
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $controlPath=Join-Path $dir 'controller-auth.json'
    while(-not(Test-Path $controlPath) -and $watch.ElapsedMilliseconds -lt 9000){
        if($hostProcess.HasExited){throw 'Host exited before creating authenticated rendezvous'}
        Start-Sleep -Milliseconds 100
    }
    Assert (Test-Path $controlPath) 'Controller rendezvous missing'
    $script:auth=[P1Wire]::Decode([IO.File]::ReadAllText($controlPath,[Text.Encoding]::UTF8))
    $script:identity=([string]$auth.hostPid)+'|'+([string]$auth.hostTicks)+'|'+([string]$auth.hostSession)
    $initial=Await {param($s) $s.tick -gt 1}
    Write-Output ('FIXTURE_HOST_PID='+$initial.hostPid+' GENERATION='+$initial.hostGeneration+' FAKE_REMOTE='+$initial.remoteId)
    Check 'P1-01' { Assert ($initial.guiPid -eq 0 -and $initial.fake -and $initial.tick -ge 2) 'fake-only host not ticking' }
    $opened=(Send 'TEST_OPEN').payload
    $a=GuiReady
    Check 'P1-05' { Assert ($opened.hostGeneration -eq $initial.hostGeneration -and $a.guiBuild -eq 'A') 'valid framed snapshot / GUI A' }
    $same=(Send 'TEST_OPEN').payload
    Check 'P1-03' {Assert ($same.guiStarts -eq 1 -and $same.guiPid -eq $a.guiPid) 'duplicate open'}
    Check 'P1-10' {
        $ticket=[P1Wire]::Decode([IO.File]::ReadAllText((Join-Path $dir 'gui-ticket.json'),[Text.Encoding]::UTF8))
        $forged=[P1Wire]::Decode([P1Wire]::Request('HELLO',[string]$ticket.nonce,[string]$ticket.hostGeneration))
        $forged['clientPid']=$a.guiPid
        $hostId=([string]$ticket.hostPid)+'|'+([string]$ticket.hostTicks)+'|'+([string]$ticket.hostSession)
        $reject=[P1Wire]::Decode([P1Wire]::Call([string]$ticket.pipe,$hostId,[P1Wire]::Json.Serialize($forged),1100))
        Assert ($reject.code -eq 'UNAUTHORIZED') 'self-claimed PID spoof succeeded'
    }
    Check 'P1-12' {
        $invalid='123|123|'+$auth.hostSession
        $err=$false
        try{[void][P1Wire]::Call([string]$auth.pipe,$invalid,[P1Wire]::Request('TEST_STATE',[string]$auth.nonce,[string]$auth.hostGeneration),700)}catch{$err=$true}
        Assert $err 'GUI/fixture allowed a false Host OS PID'
    }
    Check 'P1-13' {
        foreach($verb in @('STOP','LOGOUT','END_TEST_HOST','SCRIPT_EXEC','RESTART')){
            $r=Send $verb
            Assert ($r.code -eq 'NOT_ALLOWED') ('disallowed verb '+$verb)
        }
        Assert ((Send 'TEST_STATE').payload.hostPid -eq $initial.hostPid) 'host stopped by unknown verb'
    }
    Check 'P1-14' {
        $idempotent=[guid]::NewGuid().ToString('N')
        $first=Send 'TEST_STATE' 0 $idempotent
        $again=Send 'TEST_STATE' 0 $idempotent
        Assert ($first.type -eq 'SNAPSHOT' -and $again.code -eq 'REPLAY') 'repeated request ID allowed'
        $old=[P1Wire]::Request('TEST_STATE','expired-token',[string]$auth.hostGeneration)
        $r=[P1Wire]::Decode([P1Wire]::Call([string]$auth.pipe,$script:identity,$old,900))
        Assert ($r.code -eq 'UNAUTHORIZED') 'stale nonce allowed'
    }
    Check 'P1-15' {
        $bad=[P1Wire]::Decode([P1Wire]::Request('TEST_STATE',[string]$auth.nonce,[string]$auth.hostGeneration))
        $bad['protocol']=2
        $v=[P1Wire]::Decode([P1Wire]::Call([string]$auth.pipe,$script:identity,[P1Wire]::Json.Serialize($bad),900))
        Assert ($v.code -eq 'VERSION') 'version mismatch accepted'
        $stale=[P1Wire]::Request('TEST_STATE',[string]$auth.nonce,'oldgeneration')
        $g=[P1Wire]::Decode([P1Wire]::Call([string]$auth.pipe,$script:identity,$stale,900))
        Assert ($g.code -eq 'STALE_GENERATION') 'generation mismatch accepted'
    }
    Check 'P1-06' {
        foreach($n in @([uint32]0,[uint32]8193,[uint32]4294967295)){
            RawFrame ([BitConverter]::GetBytes($n)) @()
        }
        $r=Send 'TEST_STATE'
        Assert ($r.type -eq 'SNAPSHOT') 'oversized/invalid frame froze host'
    }
    Check 'P1-07' {
        RawFrame ([byte[]](1,2)) @()
        RawFrame ([BitConverter]::GetBytes([uint32]16)) ([byte[]](123,34,120))
        $before=(Send 'TEST_STATE').payload.tick
        Start-Sleep -Milliseconds 1450
        Assert ((Send 'TEST_STATE').payload.tick -gt $before) 'partial frame stalled heartbeat'
    }
    Check 'P1-08' {
        $c=New-Object IO.Pipes.NamedPipeClientStream('.',[string]$auth.pipe,[IO.Pipes.PipeDirection]::InOut)
        try{
            $c.Connect(800)
            $start=(Send 'TEST_STATE').payload.tick
            [void](Send 'TEST_DROP')
            Start-Sleep -Milliseconds 1600
            Assert ((Send 'TEST_STATE').payload.tick -gt $start) 'held connection stopped WinForms timer'
        } finally {$c.Dispose()}
    }
    Check 'P1-09' {
        $ticks=(Send 'TEST_STATE').payload.tick
        for($i=0;$i -lt 15;$i++){RawFrame ([BitConverter]::GetBytes([uint32]0)) @()}
        $live=(Send 'TEST_STATE').payload
        Assert ($live.tick -ge $ticks -and $live.guiWorkerActive -le 2) 'unbounded accept workers'
    }
    Check 'P1-16' {
        $base=(Send 'TEST_STATE').payload
        [void](Send 'TEST_EVENT');[void](Send 'TEST_EVENT')
        $now=(Send 'TEST_STATE').payload
        Assert ($now.revision -gt $base.revision -and $now.lastEventSeq -gt $base.lastEventSeq) 'nonmonotonic authoritative state'
    }
    Check 'P1-17' {
        [void](Send 'TEST_BLOCK_EVENTS')
        for($i=0;$i -lt 270;$i++){[void](Send 'TEST_EVENT')}
        $now=(Send 'TEST_STATE').payload
        Assert ($now.eventCount -le 256 -and $now.lastEventSeq -gt 256) 'event ring unbounded'
        [void](Send 'TEST_UNBLOCK_EVENTS')
        $recovered=Await {param($s) $s.guiGapReports -gt 0 -and $s.guiResyncSnapshots -gt 0} 6000
        Assert ($recovered.guiConnected -and $recovered.hostPid -eq $initial.hostPid) 'GUI event gap snapshot recovery'
    }
    Check 'P1-18' {
        $second=Start-Process -FilePath $psExe -ArgumentList $script:hostArgs -WindowStyle Hidden -PassThru
        try{
            Assert ($second.WaitForExit(6500)) 'duplicate host remained running'
            Assert ((Send 'TEST_STATE').payload.hostPid -eq $initial.hostPid) 'duplicate took over host'
        }finally{if($second.HasExited){$second.Dispose()}}
    }
    Check 'P1-19' {
        $invalid='98765|98765|'+$auth.hostSession;$blocked=$false
        try{[void][P1Wire]::Call([string]$auth.pipe,$invalid,[P1Wire]::Request('TEST_STATE',[string]$auth.nonce,[string]$auth.hostGeneration),700)}catch{$blocked=$true}
        Assert $blocked 'stale rendezvous accepted'
    }
    Check 'P1-20' {
        $blocked=$false
        try{[void][P1Core]::new($dir,(Join-Path $env:windir 'notepad.exe'),[guid]::NewGuid().ToString('N'),$PID,[P1Wire]::Born($PID))}catch{$blocked=$true}
        Assert $blocked 'external GUI path accepted'
    }
    $after=CloseGui
    $gsrc=[IO.File]::ReadAllText($guiPath,[Text.Encoding]::UTF8)
    Assert ($gsrc.Contains("$"+"GuiBuild='A'")) 'version marker absent'
    $updated=$gsrc.Replace("$"+"GuiBuild='A'","$"+"GuiBuild='B'")
    [IO.File]::WriteAllText($guiPath,$updated,(New-Object Text.UTF8Encoding($true)))
    [void](Send 'TEST_OPEN')
    $b=GuiReady
    Check 'P1-02' {
        Assert ($b.guiBuild -eq 'B' -and $b.guiPid -ne $a.guiPid -and $b.hostPid -eq $initial.hostPid -and $b.remoteId -eq $initial.remoteId) 'GUI A/B hot replacement failed'
    }
    if($InjectFailureAtGui){Assert $false 'P1_INJECTED_ASSERTION_WITH_LIVE_GUI'}
    $done=CloseGui
    $cycles=0
    for($i=0;$i -lt 8;$i++){
        [void](Send 'TEST_OPEN');$v=GuiReady
        [void](Send 'TEST_OPEN')
        Assert ((Send 'TEST_STATE').payload.guiPid -eq $v.guiPid) 'reopen race'
        [void](CloseGui);$cycles++
    }
    Assert ($cycles -eq 8 -and (Send 'TEST_STATE').payload.guiPid -eq 0) 'P1-03 repeated-cycle assertion'
    Check 'P1-04' {
        # Pre-HELLO and post-HELLO error injections are confined to TEMP GUI.
        $before=$updated.Replace("$"+"GuiBuild='B'","$"+"GuiBuild='B'"+[Environment]::NewLine+"throw 'BEFORE_HELLO'")
        [IO.File]::WriteAllText($guiPath,$before,(New-Object Text.UTF8Encoding($true)))
        [void](Send 'TEST_OPEN')
        $bad=Await {param($s) $s.guiPid -eq 0}
        Write-Output 'P104_PRE_HELLO_EXITED'
        Assert ($bad.guiFailures -gt 0) 'pre-HELLO crash ignored'
        # Deliberate source corruption after HELLO's if-block.
        $afterHello=$updated.Replace('$form=New-Object Windows.Forms.Form', "throw 'POST_HELLO'"+[Environment]::NewLine+'$form=New-Object Windows.Forms.Form')
        [IO.File]::WriteAllText($guiPath,$afterHello,(New-Object Text.UTF8Encoding($true)))
        [void](Send 'TEST_OPEN')
        [void](Await {param($s) $s.guiPid -eq 0})
        Write-Output 'P104_POST_HELLO_EXITED'
        [IO.File]::WriteAllText($guiPath,$updated,(New-Object Text.UTF8Encoding($true)))
        [void](Send 'TEST_OPEN');[void](GuiReady)
        Write-Output 'P104_RECOVERY_GUI_ATTACHED'
        Start-Sleep -Milliseconds 400
        [void](CloseGui)
        Write-Output 'P104_RECOVERY_GUI_EXITED'
    }
    if(-not $InjectFailureAtGui) {
        Check 'P1-22' {
            # A fresh disposable negative matrix must fail while its GUI is
            # active, yet clean its own Host/GUI/pipe without forced process kill.
            $negative=New-Object Diagnostics.Process
            $negative.StartInfo.FileName=$psExe
            $negative.StartInfo.Arguments='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -InjectFailureAtGui'
            $negative.StartInfo.UseShellExecute=$false
            $negative.StartInfo.CreateNoWindow=$true
            $negative.StartInfo.RedirectStandardOutput=$true
            $negative.StartInfo.RedirectStandardError=$true
            try {
                Assert ($negative.Start()) 'negative matrix did not spawn'
                $stdout=$negative.StandardOutput.ReadToEndAsync()
                $stderr=$negative.StandardError.ReadToEndAsync()
                Assert ($negative.WaitForExit(60000)) ('Negative matrix owned PID '+$negative.Id+' exceeded bounded 60s; no forced kill')
                Assert ($stdout.Wait(2000) -and $stderr.Wait(2000)) 'negative diagnostics read timed out'
                $text=$stdout.Result
                Assert ($negative.ExitCode -ne 0 -and $text.Contains('P1_INJECTED_ASSERTION_WITH_LIVE_GUI')) 'artificial assertion did not fail'
                $match=[regex]::Matches($text,'(?m)^DIAGNOSTIC_DIR=(.+?)\r?$')
                Assert ($match.Count -eq 1) 'negative failure diagnostic path absent'
                $negativeDir=[IO.Path]::GetFullPath($match[0].Groups[1].Value.Trim())
                Assert ([IO.Path]::GetFileName($negativeDir) -match '^RDC-P1-[a-f0-9]{32}$') 'foreign negative dir'
                Assert ($negativeDir.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) 'negative path outside TEMP'
                $live=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
                    ([string]$_.CommandLine).IndexOf($negativeDir,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    (([string]$_.CommandLine).Contains('Host.ps1') -or ([string]$_.CommandLine).Contains('Gui.ps1'))
                })
                Assert ($live.Count -eq 0) ('owned negative process remains: '+($live.ProcessId -join ','))
                # Dedicated protocol pipe is also gone because its Host exited.
                Assert ($text.Contains('REMAINING_FIXTURE_PIDS=')) 'negative cleanup inventory omitted'
                Remove-Item -LiteralPath $negativeDir -Recurse -Force -ErrorAction Stop
            } finally {if($negative.HasExited){$negative.Dispose()}}
        }
        Check 'P1-23' {
            $suite=@(
              'Test-Arch016P0Lifecycle.ps1','Test-Arch016P0ANegative.ps1',
              'Test-ProcessOwnershipCharacterization.ps1','Test-WindowLifecycleCharacterization.ps1',
              'Test-RemoteCharacterization.ps1','Test-RemoteLineClassifier.ps1',
              'Test-UiLifecycle.ps1','Test-NpxRecovery.ps1'
            )
            foreach($name in $suite){
                $result=@(& $psExe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name) 2>&1)
                Assert ($LASTEXITCODE -eq 0) ('regression '+$name+' failed: '+(@($result|Select-Object -Last 2) -join ' '))
            }
            $baseline='E:\Projects\GitSync\RDC\RDC-Relay PROG-003A\Source\remote-window.ps1'
            if(Test-Path -LiteralPath $baseline){
                $out=@(& $psExe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-RemoteClassifierParity.ps1') -BaselineSourcePath $baseline 2>&1)
                Assert ($LASTEXITCODE -eq 0) ('classifier parity regression: '+(@($out|Select-Object -Last 2) -join ' '))
            } else {
                throw 'baseline immutable source unavailable for parity; P1-23 cannot pass'
            }
        }
    }
    NotChecked 'P1-11' 'Different Windows logon / remote SMB peer requires separately approved session/network sandbox'
    NotChecked 'P1-21' 'Physical tray mouse/X, DPI, Explorer restart require approved UI-only desktop session'
    NotChecked 'P1-24' 'Actual distribution ZIP inclusion/exclusion needs separate packaging gate'
} catch {
    Write-Output ('FAIL: P1 harness exception: '+$_.Exception.Message)
    $fail++
} finally {
    if($hostProcess){
        try{
            if(-not $hostProcess.HasExited){
                $owned=(Get-CimInstance Win32_Process -Filter ('ProcessId='+$hostProcess.Id))
                Assert ($owned -and ([string]$owned.CommandLine).Contains($hostPath) -and ([string]$owned.CommandLine).Contains($dir) -and $hostProcess.StartTime.ToUniversalTime().Ticks -eq $script:hostBirth) 'Host PID/time/command identity not verified'
                if($script:auth) {
                    $state=Send 'TEST_STATE'
                    if($state.payload.guiPid -gt 0){[void](Send 'TEST_CLOSE');[void](Await {param($s) $s.guiPid -eq 0} 4500)}
                    [void](Send 'TEST_END')
                }
                Assert ($hostProcess.WaitForExit(7500)) 'Owned Host failed cooperative exit (no force kill)'
            }
        }catch{Write-Output ('CLEANUP_FAIL: '+$_.Exception.Message);$fail++}
    }
    try{
        $until=[Diagnostics.Stopwatch]::StartNew()
        do{$residual=@(WmiResidual);if($residual.Count -eq 0){break};Start-Sleep -Milliseconds 120}while($until.ElapsedMilliseconds -lt 3500)
        Write-Output ('REMAINING_FIXTURE_PIDS='+(@($residual|ForEach-Object{$_.ProcessId}) -join ','))
        Assert ($residual.Count -eq 0) 'Fixture-owned process remained; NEVER force kill'
    }catch{Write-Output ('CLEANUP_FAIL: '+$_.Exception.Message);$fail++}
    if($hostProcess -and $hostProcess.HasExited){$hostProcess.Dispose()}
    if($fail -eq 0){
        try{Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop}
        catch{Write-Output ('CLEANUP_FAIL: '+$_.Exception.Message);$fail++}
    } else {Write-Output ('DIAGNOSTIC_DIR='+$dir)}
}
if(-not $InjectFailureAtGui -and ($pass+$fail+$notChecked) -lt 24){$fail++;Write-Output 'FAIL: incomplete 24-row acceptance matrix'}
Write-Output ('TOTAL ARCH-016-P1 MATRIX: PASS='+$pass+' FAIL='+$fail+' NOT_CHECKED='+$notChecked)
if($fail){exit 1}
