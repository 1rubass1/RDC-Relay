param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $ProjectRoot 'Source\remote-window.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'GUI parse failed' }
# Load only the state machine, with fake process handles and UI sinks. Never
# launch, stop, log out, or inspect the user's actual Desktop Commander server.
$names=@('Begin-RemoteOperation','Complete-RemoteOperation','Update-RemoteOperation','Set-RemoteActionsEnabled','Reset-RemoteHandle','Complete-RuntimeInitialization')
foreach($name in $names) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
function Assert($condition,[string]$message) { if(-not $condition){throw $message} }
function New-FakeProcess([bool]$exited=$false,[int]$code=0) {
    $p=[pscustomobject]@{HasExited=$exited;ExitCode=$code;Id=123;Disposed=$false}
    $p | Add-Member ScriptMethod Dispose { $this.Disposed=$true }
    return $p
}
function Set-State { param($name,$message,$color) $script:state=$name }
function Add-Log { param($text) }
function Read-LiveLog {}
function Set-AccountDisplay { param($email) }
function Set-FinishButtonMode { param($running) }
function Set-RemoteFault { param($kind,$reason,$retry) $script:fault=$kind }
function Schedule-AutoReconnect { param($reason) }
function Resolve-NpxPath { return 'C:\Fake\npx.cmd' }
function Start-NoWindowCmd { param($command) $script:lastChild=New-FakeProcess; return $script:lastChild }
function Stop-Remote {
    if($script:proc -and -not $script:proc.HasExited) {
        $script:remoteOperation.Process=New-FakeProcess
    }
}
function Start-Remote { $script:startCalls++; $script:wasSupervisor=$script:supervisorRestarting; $script:proc=New-FakeProcess }
function Hide-LegacyRemoteTerminal {}
$finish=[pscustomobject]@{Enabled=$true}
$accountButton=[pscustomobject]@{Enabled=$true}
$switchAccountItem=[pscustomobject]@{Enabled=$true}
$reconnectItem=[pscustomobject]@{Enabled=$true}
$form=[pscustomobject]@{CloseCount=0}
$form | Add-Member ScriptMethod Close {$this.CloseCount++}
$root=$env:TEMP; $nl=[Environment]::NewLine; $desktopCommanderPackage='test-only'
$script:initializing=$false; $script:remoteOperation=$null
$script:startCalls=0; $script:closeRequested=$false

foreach($action in @('stop','restart','logout','reconnect')) {
    $script:proc=New-FakeProcess
    $before=$script:startCalls
    Begin-RemoteOperation $action
    Assert (-not $finish.Enabled) 'Actions not disabled while pending'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Update-RemoteOperation
    Assert ($watch.ElapsedMilliseconds -lt 250) 'Pending process blocked UI polling'
    Assert ($null -ne $script:remoteOperation) 'Pending operation completed early'
    $script:proc.HasExited=$true
    $script:remoteOperation.Process.HasExited=$true
    Update-RemoteOperation
    if($action -eq 'logout') {
        Assert ($script:remoteOperation.Stage -eq 'logout') 'Logout did not start after stop'
        Update-RemoteOperation
        Assert ($script:startCalls -eq $before) 'Restart began before logout finished'
        $script:remoteOperation.Process.HasExited=$true
        Update-RemoteOperation
    }
    Assert ($null -eq $script:remoteOperation -and $finish.Enabled) 'Operation did not complete'
    $expected=if($action -eq 'stop'){$before}else{$before+1}
    Assert ($script:startCalls -eq $expected) 'Unexpected restart count'
    if($action -eq 'reconnect') { Assert $script:wasSupervisor 'Reconnect lost supervisor flag' }
}
Write-Output 'PASS: nonblocking stop/restart/logout/reconnect ordering'

$script:proc=New-FakeProcess
$before=$script:startCalls
Begin-RemoteOperation 'restart'
$script:remoteOperation.Process.HasExited=$true
$script:remoteOperation.Process.ExitCode=1
Update-RemoteOperation
Assert ($script:startCalls -eq $before -and $script:fault -eq 'operation-failed') 'Failed stop restarted remote'
Assert $finish.Enabled 'Failed operation left controls disabled'
Write-Output 'PASS: failed stop leaves server handle and does not start a duplicate'

$script:proc=New-FakeProcess $true
Begin-RemoteOperation 'logout'
Update-RemoteOperation
$script:remoteOperation.Deadline=(Get-Date).AddSeconds(-1)
Update-RemoteOperation
Assert ($script:remoteOperation.Stage -eq 'logout-timeout') 'Logout timeout not handled'
$script:remoteOperation.Process.HasExited=$true
Update-RemoteOperation
Assert ($null -eq $script:remoteOperation -and $script:startCalls -eq $before) 'Timed-out logout restarted remote'
Write-Output 'PASS: logout timeout cleanup is asynchronous'

$script:proc=New-FakeProcess
$script:closeRequested=$true
Begin-RemoteOperation 'close'
Update-RemoteOperation
Assert ($form.CloseCount -eq 0) 'Window closed before stop completed'
$script:proc.HasExited=$true; $script:remoteOperation.Process.HasExited=$true
Update-RemoteOperation
Assert ($form.CloseCount -eq 1 -and $script:allowClose) 'Close did not finish after stop'
Write-Output 'PASS: window close waits without blocking'

$script:initializing=$true; $script:updateProc=New-FakeProcess
Complete-RuntimeInitialization
Assert ($script:initializing -and $form.CloseCount -eq 1) 'Pending update finished early'
$script:updateProc.HasExited=$true
Complete-RuntimeInitialization
Assert ($form.CloseCount -eq 2 -and $script:startCalls -eq $before) 'Close during update started remote'
Write-Output 'PASS: pending update and close request do not start remote'
Write-Output 'UI LIFECYCLE TESTS PASSED'
