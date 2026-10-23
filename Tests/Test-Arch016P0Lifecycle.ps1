# ARCH-016-P0 disposable real WinForms process + Named Pipes test (fake Remote only).
# Windows PowerShell 5.1 -STA, no production applications, no Stop-Process/taskkill.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Prototypes\ARCH-016-P0\Ipc.ps1')
$psexe=Join-Path $PSHOME 'powershell.exe'
$fixture=Join-Path $PSScriptRoot 'Prototypes\ARCH-016-P0'
$work=Join-Path ([IO.Path]::GetTempPath()) ('RDC-ARCH016P0-'+[guid]::NewGuid().ToString('N'))
$pipeName='rdcrelay-arch016p0-'+[guid]::NewGuid().ToString('N')
$hostProcess=$null
$hostStartTime=$null
$expectedMinimumCases=15
$pass=0;$fail=0
$script:directGuiStarts=New-Object Collections.ArrayList
function Assert([bool]$cond,[string]$message) {if(-not $cond){throw $message}}
function Check([string]$name,[scriptblock]$action) {
    try {& $action; Write-Output ('PASS: '+$name);$script:pass++}
    catch {Write-Output ('FAIL: '+$name+' :: '+$_.Exception.Message);$script:fail++}
}

# Every process the fixture recognizes must match the unique disposable script
# directory. Read-only WMI is used only for identification/reporting, never
# to terminate a process (no Stop-Process/taskkill).
function Get-RemainingFixtureProcesses {
    $rows=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)
    $pathPrefix=[IO.Path]::GetFullPath($work).TrimEnd([char]92)+[char]92
    return @($rows | Where-Object {
        $line=[string]$_.CommandLine
        $line.IndexOf($pathPrefix,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        ($line.IndexOf('TrayHost.ps1',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
         $line.IndexOf('Gui.ps1',[StringComparison]::OrdinalIgnoreCase) -ge 0) -and
        $_.Name -ieq 'powershell.exe'
    })
}
function Confirm-OwnHost {
    if (-not $hostProcess -or $hostProcess.HasExited) {return $false}
    if (-not $hostStartTime) {return $false}
    $row=@(Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId="+$hostProcess.Id) -ErrorAction Stop)
    if($row.Count -ne 1) {return $false}
    $line=[string]$row[0].CommandLine
    if($row[0].Name -ine 'powershell.exe' -or
       $line.IndexOf($hostScript,[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
       $line.IndexOf($script,[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
       $line.IndexOf($pipeName,[StringComparison]::Ordinal) -lt 0 -or
       $line.IndexOf(' -TestMode',[StringComparison]::OrdinalIgnoreCase) -lt 0) {
       return $false
    }
    $current=Get-Process -Id $hostProcess.Id -ErrorAction Stop
    return ($current.StartTime -eq $hostStartTime)
}
# Connection check only: never read a server-controlled reply while probing
# for teardown, even if a simulated server has stopped processing requests.
function Test-FixturePipePresent {
    $client=New-Object IO.Pipes.NamedPipeClientStream(
        '.', $pipeName,[IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::None)
    try {
        $client.Connect(240)
        return $true
    } catch [TimeoutException] {
        return $false
    } catch [IO.IOException] {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Send([string]$command) {
    return (Invoke-ProbePipe -Name $pipeName -Command $command -TimeoutMs 1000)
}
function Await([scriptblock]$predicate,[int]$timeoutMs=9000) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $item=Send 'STATE'
            if (& $predicate $item) {return $item}
        } catch {}
        Start-Sleep -Milliseconds 140
    } while ($watch.ElapsedMilliseconds -lt $timeoutMs)
    throw ('Timed out after '+$timeoutMs+' ms')
}
function Assert-Unchanged($snapshot,$reference,[string]$context) {
    Assert ($snapshot.hostPid -eq $reference.hostPid) ('Host restarted '+$context)
    Assert ($snapshot.remoteId -ceq $reference.remoteId) ('Fake Remote identity changed '+$context)
}
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    foreach($name in @('Ipc.ps1','Gui.ps1','TrayHost.ps1')){
        Copy-Item -LiteralPath (Join-Path $fixture $name) -Destination (Join-Path $work $name)
    }
    $script=Join-Path $work 'Gui.ps1'
    $original=[IO.File]::ReadAllText($script,[Text.Encoding]::UTF8)
    Assert ($original.Contains("$"+"GuiBuild = 'A'")) 'GUI version-marker code not found'
    $hostScript=Join-Path $work 'TrayHost.ps1'
    $stdOut=Join-Path $work 'host-stdout.txt'
    $stdErr=Join-Path $work 'host-stderr.txt'
    $arguments='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$hostScript+'" -PipeName '+$pipeName+' -GuiScript "'+$script+'" -TestMode'
    $hostProcess=Start-Process -FilePath $psexe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr
    $hostStartTime=$hostProcess.StartTime
    $initial=Await {param($s) $s.ok -and $s.trayAllocated}
    Write-Output ('PROTOTYPE_HOST_PID='+$initial.hostPid+' FAKE_REMOTE_ID='+$initial.remoteId)
    Check 'Host initializes fake kernel and allocates tray icon (hidden in automation)' {
        Assert ($initial.hostPid -eq $hostProcess.Id -and $initial.tick -ge 1 -and $initial.guiStarts -eq 0) 'host startup'
        Assert ($initial.trayAllocated) 'NotifyIcon not allocated'
    }
    $later=Await {param($s) $s.tick -ge ($initial.tick+4)}
    Check 'Kernel heartbeat progresses with zero GUI processes' {
        Assert-Unchanged $later $initial 'idle'
        Assert ($later.guiPid -eq 0 -and $later.guiStarts -eq 0) 'idle spawned GUI'
    }
    $r=Send 'TRAY_DOUBLE_CLICK'
    $a=Await {param($s) $s.guiConnected -and $s.guiVersion -eq 'A'}
    Check 'Synthetic tray double click opens a real WinForms GUI process A' {
        Assert-Unchanged $a $initial 'A'
        Assert ($a.guiStarts -eq 1 -and $a.guiPid -ne $hostProcess.Id -and $a.trayDoubleClicks -eq 1) 'incorrect GUI A launch'
    }
    [void](Send 'OPEN');[void](Send 'OPEN')
    [void](Send 'TRAY_DOUBLE_CLICK')
    $same=Send 'STATE'
    Check 'Repeated opens and tray event do not launch a second GUI' {
        Assert ($same.guiStarts -eq 1 -and $same.guiPid -eq $a.guiPid -and $same.trayDoubleClicks -eq 2) 'duplicate child'
    }
    $duplicate=Start-Process -FilePath $psexe -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -PipeName '+$pipeName+' -TestMode') -WindowStyle Hidden -PassThru
    [void]$script:directGuiStarts.Add(@{Pid=$duplicate.Id;StartedAt=$duplicate.StartTime;Role='duplicate'})
    try {
        Assert ($duplicate.WaitForExit(8000)) 'stray GUI handshake did not terminate'
        $dupeExit=$duplicate.ExitCode
    } finally {$duplicate.Dispose()}
    $afterDupe=Send 'STATE'
    Check 'Direct second GUI is rejected by host handshake without affecting A' {
        Assert ($dupeExit -eq 5 -and $afterDupe.guiPid -eq $a.guiPid) 'duplicate accepted'
        Assert ($afterDupe.ipcRejections -ge 1) 'duplicate not registered as rejected'
    }
    [void](Send 'DROP_NEXT_STATE')
    Start-Sleep -Milliseconds 750
    $afterLoss=Send 'STATE'
    Check 'Transient IPC loss does not reset background fake Remote or GUI' {
        Assert-Unchanged $afterLoss $initial 'IPC dropout'
        Assert ($afterLoss.guiPid -eq $a.guiPid -and $afterLoss.guiConnected) 'temporary dropout killed GUI'
        Assert ($afterLoss.tick -gt $same.tick) 'heartbeat stopped on IPC dropout'
    }
    [void](Send 'CLOSE_GUI')
    $closedA=Await {param($s) $s.guiPid -eq 0 -and $s.guiCloses -ge 1}
    Check 'X-equivalent Form.Close ends GUI A and preserves host' {
        Assert-Unchanged $closedA $initial 'A closed'
        Assert ($closedA.guiStarts -eq 1 -and $closedA.tick -gt $a.tick) 'host/GUI close semantics'
    }
    $changed=$original.Replace("$"+"GuiBuild = 'A'","$"+"GuiBuild = 'B'")
    Assert ($changed -cne $original) 'No source replacement occurred'
    [IO.File]::WriteAllText($script,$changed,(New-Object Text.UTF8Encoding($true)))
    $newGuiSha=(Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash
    [void](Send 'TRAY_DOUBLE_CLICK')
    $b=Await {param($s) $s.guiConnected -and $s.guiVersion -eq 'B'}
    Check 'Edited GUI program B loads from disk without restarting old kernel' {
        Assert-Unchanged $b $initial 'B'
        Assert ($b.guiStarts -eq 2 -and $b.guiPid -ne $a.guiPid) 'new GUI code not executed'
        Assert ($b.tick -gt $closedA.tick) 'kernel did not advance throughout hot reload'
    }
    Write-Output ('PROTOTYPE_B_GUI_SOURCE_SHA256='+$newGuiSha)
    [void](Send 'CLOSE_GUI')
    $closedB=Await {param($s) $s.guiPid -eq 0 -and $s.guiCloses -ge 2}
    # Intentional GUI source/runtime failure, confined to disposable TEMP copy.
    $faulted=$changed.Replace("$"+"GuiBuild = 'B'","$"+"GuiBuild = 'B'"+[Environment]::NewLine+"throw 'P0_EXPECTED_GUI_FAILURE'")
    [IO.File]::WriteAllText($script,$faulted,(New-Object Text.UTF8Encoding($true)))
    [void](Send 'OPEN')
    $failedGui=Await {param($s) $s.guiPid -eq 0 -and $s.guiLaunchFailures -ge 1}
    Check 'Crash of newly loaded GUI leaves same host/kernel running' {
        Assert-Unchanged $failedGui $initial 'bad GUI'
        Assert ($failedGui.guiStarts -eq 3 -and $failedGui.guiLaunchFailures -eq 1) 'crashed GUI not recognized'
    }
    [IO.File]::WriteAllText($script,$changed,(New-Object Text.UTF8Encoding($true)))
    [void](Send 'OPEN')
    $recovered=Await {param($s) $s.guiConnected -and $s.guiVersion -eq 'B' -and $s.guiStarts -eq 4}
    Check 'Repair/relaunch after bad GUI succeeds on same host' {
        Assert-Unchanged $recovered $initial 'recovered GUI'
    }
    [void](Send 'CLOSE_GUI')
    $noGui=Await {param($s) $s.guiPid -eq 0 -and $s.guiCloses -ge 4}
    Check 'No GUI leaves monitor active; no implicit Remote start/stop' {
        Assert ($noGui.tick -gt $failedGui.tick -and $noGui.guiStarts -eq 4) 'core continuity'
        Assert-Unchanged $noGui $initial 'final no GUI'
    }
    # Seven additional complete open/close cycles (ten successful GUI instances
    # overall, counting A, B and recovered B). Each executes the same real
    # WinForms Form.Close route; no process is force-killed.
    $roundsCompleted=0
    for ($i=1; $i -le 7; $i++) {
        [void](Send 'TRAY_DOUBLE_CLICK')
        $cycle=Await {param($s) $s.guiConnected -and $s.guiVersion -eq 'B'}
        Assert ($cycle.guiStarts -eq (4+$i)) ('cycle '+$i+' did not create new GUI')
        [void](Send 'OPEN')
        $noDuplicate=Send 'STATE'
        Assert ($noDuplicate.guiStarts -eq $cycle.guiStarts) ('cycle '+$i+' duplicate')
        [void](Send 'CLOSE_GUI')
        $idle=Await {param($s) $s.guiPid -eq 0 -and $s.guiCloses -ge (4+$i)}
        Assert-Unchanged $idle $initial ('cycle '+$i)
        $roundsCompleted++
    }
    Check 'Ten separate successful GUI processes across A/B revisions, no leaks' {
        Assert ($roundsCompleted -eq 7 -and $idle.guiStarts -eq 11 -and $idle.guiCloses -eq 11) 'ten-cycle accounting'
        Assert ($idle.tick -gt $noGui.tick) 'kernel heartbeat stopped across reopen cycles'
    }
    $badProtocol=$changed.Replace("$"+"ProtocolVersion = '1'","$"+"ProtocolVersion = '2'")
    Assert ($badProtocol -cne $changed) 'protocol marker missing'
    [IO.File]::WriteAllText($script,$badProtocol,(New-Object Text.UTF8Encoding($true)))
    [void](Send 'OPEN')
    $skew=Await {param($s) $s.guiPid -eq 0 -and $s.guiLaunchFailures -ge 2}
    Check 'Incompatible GUI IPC protocol is rejected; host remains active' {
        Assert-Unchanged $skew $initial 'version mismatch'
        Assert ($skew.guiStarts -eq 12 -and $skew.guiLaunchFailures -eq 2) 'version gate not enforced'
    }
    [IO.File]::WriteAllText($script,$changed,(New-Object Text.UTF8Encoding($true)))
    # Missing host: startup handshake fails, never starts an alternate host.
    $badPipe='rdcrelay-arch016p0-'+[guid]::NewGuid().ToString('N')
    $unreachable=Start-Process -FilePath $psexe -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -PipeName '+$badPipe+' -TestMode') -WindowStyle Hidden -PassThru
    [void]$script:directGuiStarts.Add(@{Pid=$unreachable.Id;StartedAt=$unreachable.StartTime;Role='unreachable'})
    try {
        Assert ($unreachable.WaitForExit(6500)) 'unreachable GUI did not fail promptly'
        $badExit=$unreachable.ExitCode
    } finally {$unreachable.Dispose()}
    Check 'Missing IPC host rejects GUI without starting any Remote' {
        Assert ($badExit -eq 5) 'unexpected orphan GUI exit code'
        $post=Send 'STATE'
        Assert-Unchanged $post $initial 'missing-host negative'
        Assert ($post.guiStarts -eq 12) 'orphan launched another GUI'
    }
} catch {
    $fail++
    Write-Output ('FAIL: lifecycle harness exception :: '+$_.Exception.Message)
} finally {
    # Fail closed. Only a Process handle returned by THIS test's Start-Process,
    # with matching PID + StartTime + Win32_Process CommandLine, may receive
    # the unique fixture pipe's cooperative close/shutdown requests.
    # No real PID is killed if the host fails or refuses the request.
    $cleanupErrors=New-Object Collections.ArrayList
    $knownHostPid=if($hostProcess){$hostProcess.Id}else{0}
    Write-Output ('CLEANUP_HOST_PID='+$knownHostPid)
    if($hostProcess) {
        try {
            if(-not $hostProcess.HasExited) {
                if(-not (Confirm-OwnHost)) {
                    throw 'Host PID/start-time/command line identity unverifiable: no IPC shutdown sent'
                }
                Write-Output 'CLEANUP_HOST_IDENTITY=VERIFIED'
                # Ask only our identified host to close its own GUI. Await is
                # bounded, and each IPC connect/response now has a deadline.
                $current=Send 'STATE'
                if ($current.guiPid -ne 0) {
                    Write-Output ('CLEANUP_GUI_REQUESTED_PID='+$current.guiPid)
                    [void](Send 'CLOSE_GUI')
                    [void](Await {param($s) $s.guiPid -eq 0} 4500)
                }
                [void](Send 'END_TEST_HOST')
                if(-not $hostProcess.WaitForExit(7000)) {
                    throw ('Owned host PID '+$hostProcess.Id+' failed to exit within 7000 ms; no forced kill')
                }
            }
        } catch {
            [void]$cleanupErrors.Add($_.Exception.Message)
        }
    }
    # Bound a final independent OS-level inspection; it also sees GUI children
    # if the host is already gone and cannot report its most recent GUI PID.
    $remaining=@()
    try {
        $clock=[Diagnostics.Stopwatch]::StartNew()
        do {
            $remaining=@(Get-RemainingFixtureProcesses)
            if($remaining.Count -eq 0){break}
            Start-Sleep -Milliseconds 150
        } while($clock.ElapsedMilliseconds -lt 3500)
        Write-Output ('CLEANUP_REMAINING_PROCESS_COUNT='+$remaining.Count)
        foreach($row in $remaining){
            $kind=if(([string]$row.CommandLine).IndexOf('TrayHost.ps1',[StringComparison]::OrdinalIgnoreCase) -ge 0){'Host'}else{'GUI'}
            Write-Output ('CLEANUP_REMAINING_OWNED_PID='+$row.ProcessId+' PARENT='+$row.ParentProcessId+' KIND='+$kind)
        }
        if($remaining.Count -gt 0){
            [void]$cleanupErrors.Add('Verified disposable fixture processes remain after bounded wait; escalation required')
        }
    } catch {
        Write-Output ('CLEANUP_PROCESS_INVENTORY=NOT_CHECKED '+$_.Exception.Message)
        [void]$cleanupErrors.Add('Cannot prove absence of fixture-owned processes: '+$_.Exception.Message)
    }
    try {
        $pipePresent=Test-FixturePipePresent
        $hostAlive=($hostProcess -and -not $hostProcess.HasExited)
        if($pipePresent -or $hostAlive){
            Write-Output ('CLEANUP_PIPE_RELEASED=FAIL; hostAlive='+[bool]$hostAlive+' pipeConnects='+[bool]$pipePresent)
            [void]$cleanupErrors.Add('Host or named pipe remains after bounded wait')
        } else {
            Write-Output 'CLEANUP_PIPE_RELEASED=PASS'
        }
    } catch {
        [void]$cleanupErrors.Add('Pipe-release verification failed: '+$_.Exception.Message)
    }
    if($hostProcess -and $hostProcess.HasExited){
        $hostProcess.Dispose()
    }
    if($cleanupErrors.Count -eq 0) {
        Write-Output 'CLEANUP_RESULT=PASS (no forced termination)'
        $pass++
    } else {
        foreach($item in $cleanupErrors){Write-Output ('CLEANUP_FAIL: '+$item)}
        Write-Output 'CLEANUP_RESULT=FAIL (no forced termination)'
        $fail++
    }
    $executed=$pass+$fail
    if($executed -lt $expectedMinimumCases){
        Write-Output ('FAIL: coverage minimum '+$expectedMinimumCases+' but only '+$executed+' cases executed')
        $fail++
    }
    if($fail -eq 0) {
        try {
            # Remove only the unpredictable subdirectory created by this test.
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Output ('FAIL: own TEMP cleanup: '+$_.Exception.Message)
            $fail++
        }
    }
    if($fail -gt 0){
        Write-Output 'DIAGNOSTICS_RETAINED=true; investigate fixture-owned PID report before manual action'
        Write-Output ('DIAGNOSTIC_DIR='+$work)
        if(Test-Path (Join-Path $work 'host-stderr.txt')){
            Get-Content -LiteralPath (Join-Path $work 'host-stderr.txt') -Tail 10
        }
    }
}
Write-Output ('TOTAL ARCH-016-P0: PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
