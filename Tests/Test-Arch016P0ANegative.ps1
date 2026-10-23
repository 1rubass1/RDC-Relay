# ARCH-016-P0A independent disposable negative controls; no real Remote or forced kill.
$ErrorActionPreference='Stop'
$original=Join-Path $PSScriptRoot 'Test-Arch016P0Lifecycle.ps1'
$source=[IO.File]::ReadAllText($original,[Text.Encoding]::UTF8)
$psExe=Join-Path $PSHOME 'powershell.exe'
$script:passed=0;$script:failed=0
function Assert([bool]$ok,[string]$why){if(-not $ok){throw $why}}
function Run-Negative([string]$name,[string]$mutated,[bool]$expectGuiCleanup) {
    $id=[guid]::NewGuid().ToString('N')
    $copy=Join-Path $PSScriptRoot ('_ARCH016P0A-negative-'+$id+'.ps1')
    $logFolder=Join-Path ([IO.Path]::GetTempPath()) ('RDC-ARCH016P0A-control-'+$id)
    $out=Join-Path $logFolder 'stdout.txt'
    $err=Join-Path $logFolder 'stderr.txt'
    $process=$null;$safeToErase=$false
    try {
        [void](New-Item -ItemType Directory -Path $logFolder -ErrorAction Stop)
        [IO.File]::WriteAllText($copy,$mutated,(New-Object Text.UTF8Encoding($true)))
        $process=Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$copy+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if(-not $process.WaitForExit(65000)){throw ('OWNED_NEGATIVE_RUNNER_REMAINS_PID='+$process.Id+'; NO FORCE KILL')}
        $exitCode=$process.ExitCode
        $output=[IO.File]::ReadAllText($out,[Text.Encoding]::UTF8)
        Assert ($exitCode -eq 1) ('expected exit 1; actual '+$exitCode)
        Assert ($output.Contains('CLEANUP_HOST_IDENTITY=VERIFIED')) 'host PID identity was not verified'
        Assert ($output.Contains('CLEANUP_REMAINING_PROCESS_COUNT=0')) 'owned-process inventory not empty'
        Assert ($output.Contains('CLEANUP_PIPE_RELEASED=PASS')) 'named pipe not released'
        Assert ($output.Contains('CLEANUP_RESULT=PASS')) 'cooperative cleanup failed'
        if($expectGuiCleanup) {
            Assert ($output.Contains('CLEANUP_GUI_REQUESTED_PID=')) 'live GUI cleanup not requested'
            Assert ($output.Contains('P0A deliberate early failure with GUI still running')) 'failure not detected'
        } else {
            Assert ($output.Contains('FAIL: coverage minimum 15 but only 14 cases executed')) 'skip did not fail coverage guard'
            Assert ($output.Contains('TOTAL ARCH-016-P0: PASS=14 FAIL=1')) 'skip not reported correctly'
        }
        $paths=[regex]::Matches($output,'(?m)^DIAGNOSTIC_DIR=(.+?)\r?$')
        Assert ($paths.Count -eq 1) 'fixture diagnostic path missing or ambiguous'
        $reported=[IO.Path]::GetFullPath($paths[0].Groups[1].Value.Trim())
        $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)+[char]92
        Assert ($reported.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) 'fixture diagnostics outside TEMP'
        Assert ([IO.Path]::GetFileName($reported) -match '^RDC-ARCH016P0-[0-9a-f]{32}$') 'wrong fixture diagnostic basename'
        if(Test-Path -LiteralPath $reported){Remove-Item -LiteralPath $reported -Recurse -Force -ErrorAction Stop}
        $safeToErase=$true
        Write-Output ('PASS: '+$name+' : exit=1; host/GUI=0; IPC released')
        $script:passed++
    } catch {
        Write-Output ('FAIL: '+$name+' : '+$_.Exception.Message)
        $script:failed++
    } finally {
        if($process -and $process.HasExited){$process.Dispose()}
        if($safeToErase) {
            if(Test-Path -LiteralPath $copy){Remove-Item -LiteralPath $copy -Force}
            if(Test-Path -LiteralPath $logFolder){Remove-Item -LiteralPath $logFolder -Recurse -Force}
        } else {
            Write-Output ('NEGATIVE_DIAGNOSTICS_RETAINED='+$logFolder)
            Write-Output ('NEGATIVE_COPY_RETAINED='+$copy)
            if(Test-Path -LiteralPath $out){Get-Content -LiteralPath $out -Tail 20}
            if(Test-Path -LiteralPath $err){Get-Content -LiteralPath $err -Tail 10}
        }
    }
}
# Skip a single Check while continuing the full scenario.
$skipAnchor="Check 'Kernel heartbeat progresses with zero GUI processes' {"
Assert ($source.Contains($skipAnchor)) 'skip anchor missing'
$skip=$source.Replace($skipAnchor,"Skip-Check 'Kernel heartbeat progresses with zero GUI processes' {")
$marker="function Send([string]"+'$command'+") {"
Assert ($skip.Contains($marker)) 'helper anchor missing'
$helper="function Skip-Check([string]"+'$name'+",[scriptblock]"+'$action'+"){ Write-Output ('SKIPPED: '+"+'$name'+") }"+[Environment]::NewLine
$skip=$skip.Replace($marker,$helper+$marker)
Run-Negative 'skipped-case coverage guard' $skip $false
# Crash before normal close while an owned GUI is still running.
$crashAnchor="[void](Send 'OPEN');[void](Send 'OPEN')"
Assert ($source.Contains($crashAnchor)) 'injected failure anchor missing'
$crash=$source.Replace($crashAnchor,"throw 'P0A deliberate early failure with GUI still running'"+[Environment]::NewLine+'    '+$crashAnchor)
Run-Negative 'failing assertion with live test GUI' $crash $true
Write-Output ('TOTAL ARCH-016-P0A NEGATIVE: PASS='+$passed+' FAIL='+$failed)
if($failed){exit 1}
