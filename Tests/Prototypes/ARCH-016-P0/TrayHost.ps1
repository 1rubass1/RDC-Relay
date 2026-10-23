# ARCH-016-P0 disposable Tray Host with FAKE Remote, never the installed RDC Relay.
param(
    [Parameter(Mandatory=$true)][string]$PipeName,
    [Parameter(Mandatory=$true)][string]$GuiScript,
    [switch]$TestMode,
    [switch]$DisplayTray
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Ipc.ps1')
Assert-ProbePipeName $PipeName
$GuiScript=[IO.Path]::GetFullPath($GuiScript)
$allowedDir=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char]92)+[char]92
if (-not $GuiScript.StartsWith($allowedDir,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'GUI must reside within disposable prototype folder'
}
if (-not (Test-Path -LiteralPath $GuiScript -PathType Leaf)) {throw 'Missing disposable GUI script'}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$script:fakeRemoteIdentity=[Guid]::NewGuid().ToString('N')
$script:fakeMonitorTicks=0
$script:guiProcess=$null
$script:guiPid=0
$script:guiVersion=''
$script:guiConnected=$false
$script:guiStarts=0
$script:guiCloses=0
$script:guiLaunchFailures=0
$script:guiLastExit=-1
$script:trayDoubleClicks=0
$script:closeGeneration=0
$script:expectedGuiClose=$false
$script:ipcRejections=0
$script:dropNextState=$false
$script:stopTestAt=[datetime]::MaxValue
$script:ipcServer=$null
$script:pendingConnection=$null
$script:context=New-Object Windows.Forms.ApplicationContext
$script:notify=New-Object Windows.Forms.NotifyIcon
$script:menu=New-Object Windows.Forms.ContextMenuStrip
$openItem=New-Object Windows.Forms.ToolStripMenuItem 'Open test GUI (fake Remote)'
[void]$script:menu.Items.Add($openItem)
$script:notify.Icon=[Drawing.SystemIcons]::Application
$script:notify.Text='RDC ARCH-016 P0 - FAKE Remote'
$script:notify.ContextMenuStrip=$script:menu
$script:notify.Visible=(-not $TestMode -or $DisplayTray)
function Get-HostSnapshot {
    return @{
        ok=$true; hostPid=$PID; remoteId=$script:fakeRemoteIdentity
        tick=$script:fakeMonitorTicks; guiPid=$script:guiPid
        guiVersion=$script:guiVersion; guiConnected=$script:guiConnected
        guiStarts=$script:guiStarts; guiCloses=$script:guiCloses
        guiLaunchFailures=$script:guiLaunchFailures
        guiLastExit=$script:guiLastExit; trayDoubleClicks=$script:trayDoubleClicks
        closeGeneration=$script:closeGeneration; ipcRejections=$script:ipcRejections
        trayAllocated=($null -ne $script:notify)
    }
}
function Open-ProbeGui {
    # Exactly one GUI. Never inspect, stop, adopt, or start any Remote process.
    if ($script:guiProcess -and -not $script:guiProcess.HasExited) {return}
    if ($script:guiProcess) { $script:guiProcess.Dispose();$script:guiProcess=$null }
    $script:guiConnected=$false;$script:guiPid=0;$script:guiVersion=''
    $script:expectedGuiClose=$false
    $a='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$GuiScript+'" -PipeName '+$PipeName
    if ($TestMode){$a+=' -TestMode'}
    try {
        $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $a -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $child){throw 'GUI launch returned no process'}
        $script:guiProcess=$child
        $script:guiPid=$child.Id
        $script:guiStarts++
    } catch {
        $script:guiPid=0
        $script:guiLaunchFailures++
    }
}
function Handle-ProbeRequest([string]$request) {
    if ([string]::IsNullOrWhiteSpace($request) -or $request.Length -gt 256) {
        return @{ok=$false;error='request-size-or-empty'}
    }
    $parts=$request.Split('|')
    switch ($parts[0]) {
        'STATE' {return (Get-HostSnapshot)}
        'OPEN' {Open-ProbeGui;return (Get-HostSnapshot)}
        'TRAY_DOUBLE_CLICK' {
            if (-not $TestMode){return @{ok=$false;error='test-command-disabled'}}
            $script:trayDoubleClicks++
            Open-ProbeGui
            return (Get-HostSnapshot)
        }
        'HELLO' {
            if ($parts.Count -ne 4 -or $parts[3] -ne '1' -or $parts[1] -notmatch '^\d{1,10}$' -or $parts[2] -notmatch '^[A-Za-z0-9_-]{1,24}$') {
                return @{ok=$false;error='invalid-handshake'}
            }
            if (-not $script:guiProcess -or $script:guiProcess.HasExited -or ([int]$parts[1]) -ne $script:guiPid -or $script:guiConnected) {
                $script:ipcRejections++
                return @{ok=$false;error='second-or-unexpected-gui'}
            }
            $script:guiVersion=$parts[2]
            $script:guiConnected=$true
            return (Get-HostSnapshot)
        }
        'BYE' {
            if ($parts.Count -eq 2 -and $parts[1] -match '^\d+$' -and [int]$parts[1] -eq $script:guiPid) {
                $script:guiConnected=$false
                return @{ok=$true}
            }
            return @{ok=$false;error='unregistered-gui'}
        }
        'CLOSE_GUI' {
            if (-not $TestMode){return @{ok=$false;error='test-command-disabled'}}
            $script:closeGeneration++
            $script:expectedGuiClose=$true
            return (Get-HostSnapshot)
        }
        'DROP_NEXT_STATE' {
            if (-not $TestMode){return @{ok=$false;error='test-command-disabled'}}
            $script:dropNextState=$true
            return @{ok=$true}
        }
        'END_TEST_HOST' {
            if (-not $TestMode){return @{ok=$false;error='test-command-disabled'}}
            if ($script:guiProcess -and -not $script:guiProcess.HasExited) {
                return @{ok=$false;error='close-gui-before-host'}
            }
            $script:stopTestAt=(Get-Date).AddMilliseconds(450)
            return @{ok=$true}
        }
        default {return @{ok=$false;error='unknown-command'}}
    }
}
function New-ProbeServer {
    # Explicit per-current-user DACL, no Everyone/Anonymous grant.
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl=New-Object IO.Pipes.PipeSecurity
    $acl.SetAccessRuleProtection($true,$false)
    $rule=New-Object IO.Pipes.PipeAccessRule(
        $sid,[IO.Pipes.PipeAccessRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
    return [IO.Pipes.NamedPipeServerStream]::new(
        $PipeName,[IO.Pipes.PipeDirection]::InOut,1,
        [IO.Pipes.PipeTransmissionMode]::Byte,
        [IO.Pipes.PipeOptions]::Asynchronous,
        4096,4096,$acl)
}
function Start-ProbeWait {
    $script:ipcServer=New-ProbeServer
    $script:pendingConnection=$script:ipcServer.BeginWaitForConnection($null,$null)
}
$openItem.Add_Click({ Open-ProbeGui })
$script:notify.Add_DoubleClick({ $script:trayDoubleClicks++; Open-ProbeGui })
$script:timer=New-Object Windows.Forms.Timer
$script:timer.Interval=75
$script:timer.Add_Tick({
    try {
        $script:fakeMonitorTicks++
        if ($script:guiProcess -and $script:guiProcess.HasExited) {
            $script:guiLastExit=$script:guiProcess.ExitCode
            if (-not $script:guiConnected -and -not $script:expectedGuiClose) {
                $script:guiLaunchFailures++
            }
            $script:guiProcess.Dispose();$script:guiProcess=$null
            $script:guiPid=0;$script:guiConnected=$false;$script:guiCloses++
        }
        if ($script:pendingConnection -and $script:pendingConnection.IsCompleted) {
            $reader=$null;$writer=$null
            try {
                $script:ipcServer.EndWaitForConnection($script:pendingConnection)
                $encoding=New-Object Text.UTF8Encoding($false)
                $reader=New-Object IO.StreamReader($script:ipcServer,$encoding,$false,1024,$true)
                $writer=New-Object IO.StreamWriter($script:ipcServer,$encoding,1024,$true)
                $writer.AutoFlush=$true
                $command=$reader.ReadLine()
                if ($script:dropNextState -and $command -eq 'STATE') {
                    $script:dropNextState=$false
                    # Intentionally disconnect just this one request to simulate IPC loss.
                } else {
                    $response=Handle-ProbeRequest $command
                    $writer.WriteLine(($response | ConvertTo-Json -Compress -Depth 4))
                }
            } catch {
                $script:ipcRejections++
            } finally {
                if ($writer){$writer.Dispose()}
                if ($reader){$reader.Dispose()}
                if ($script:ipcServer){$script:ipcServer.Dispose()}
                $script:ipcServer=$null;$script:pendingConnection=$null
                if ((Get-Date) -lt $script:stopTestAt){Start-ProbeWait}
            }
        }
        if ((Get-Date) -ge $script:stopTestAt){$script:context.ExitThread()}
    } catch {
        # Fail visibly and stay alive for diagnosis; never run process termination.
        $script:ipcRejections++
    }
})
try {
    Start-ProbeWait
    $script:timer.Start()
    [Windows.Forms.Application]::Run($script:context)
} finally {
    $script:timer.Stop();$script:timer.Dispose()
    if ($script:ipcServer){$script:ipcServer.Dispose()}
    if ($script:guiProcess){$script:guiProcess.Dispose()}
    $script:notify.Visible=$false
    $script:notify.Dispose()
    $script:menu.Dispose()
    $script:context.Dispose()
}
