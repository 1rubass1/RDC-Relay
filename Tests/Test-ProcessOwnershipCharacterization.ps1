# PROG-005A: AST functions executed ONLY against in-memory fakes.
# Never dot-source the application, invoke real WMI, start/kill a process or touch logs.
# powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Tests/Test-ProcessOwnershipCharacterization.ps1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source/remote-window.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw "Source parser errors: $($errors.Count)"}
$functionNames=@('Find-ExistingRemote','Start-Remote','Stop-Remote','Begin-RemoteOperation','Update-RemoteOperation','Complete-RemoteOperation','Set-RemoteActionsEnabled','Reset-RemoteHandle','Refresh-Window')
foreach($name in $functionNames){
    $n=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $name},$true)
    if(-not $n){throw "Missing source function: $name"}
    . ([scriptblock]::Create($n.Extent.Text))
}
$script:passed=0;$script:failed=0
function Assert([bool]$ok,[string]$label){if(-not $ok){throw $label}}
function Case([string]$name,[scriptblock]$action){
    try { & $action; Write-Output ('PASS: '+$name);$script:passed++ }
    catch { Write-Output ('FAIL: '+$name+' :: '+$_.Exception.Message);$script:failed++ }
}
function New-FakeProcess([int]$id=101,[bool]$exited=$false,[int]$exitCode=0) {
    $p=[pscustomobject]@{Id=$id;StartTime=[datetime]'2025-01-01';HasExited=$exited;ExitCode=$exitCode;Disposed=$false;RefreshCount=0;MainWindowHandle=[IntPtr]::Zero}
    $p|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    $p|Add-Member ScriptMethod Refresh {$this.RefreshCount++}
    return $p
}
function New-Wmi([int]$id,[string]$name,[string]$cmd){
    return [pscustomobject]@{ProcessId=$id;Name=$name;CommandLine=$cmd;CreationDate='20251001000000.000000+000'}
}
# Explicit fail-closed fakes. A call to the real system cannot slip through.
function Get-CimInstance {param($ClassName,$ErrorAction) $script:wmiQueries++;if($script:wmiFailure){throw 'fake WMI failure'};return $script:wmiRows}
function Get-Process {param([int]$Id,$ErrorAction) $script:processQueries++;if($script:missingPids -contains $Id){throw 'fake PID missing'};if($script:fakeProcesses.ContainsKey($Id)){return $script:fakeProcesses[$Id]};throw ('Unmocked PID '+$Id)}
function Start-NoWindowCmd {
    param([string]$commandLine)
    [void]$script:commandCalls.Add($commandLine)
    if($script:launcherFailure){throw 'synthetic launcher error'}
    if($script:launcherReturnsNull){return $null}
    return (New-FakeProcess (9000+$script:commandCalls.Count))
}
function Resolve-NpxPath {return 'C:\Fixture\npx.cmd'}
function Test-Path {param($Path,$LiteralPath,$PathType,$ErrorAction) return $false}
function Copy-Item {throw 'filesystem copy forbidden by fixture'}
function Remove-Item {throw 'filesystem deletion forbidden by fixture'}
function Repair-DesktopCommanderNpxCache {throw 'cache touch forbidden'}
function Reset-CompactLogSession {$script:logResets++}
function Set-DividerStoppedState([bool]$on){$script:stopped=$on}
function Set-DividerStartupState([bool]$on){$script:starting=$on}
function Set-FinishButtonMode([bool]$running){$script:finishMode=$running}
function Set-State($name,$detail,$color){$script:state=$name}
function Set-RuntimeDisplay {param($headline,$detail,$on) $script:runtimeDisplay=$headline}
function Add-Log([string]$entry){[void]$script:logCalls.Add($entry)}
function Read-LiveLog {$script:readCalls++}
function Set-AccountDisplay($email){$script:accountCleared++}
function Clear-RemoteFault {$script:faultKind='';$script:faultCleared++}
function Set-RemoteFault($kind,$reason,$retry){$script:faultKind=$kind;$script:faultRetry=[bool]$retry}
function Schedule-AutoReconnect($reason){$script:scheduled++}
function Set-DividerFaultState([bool]$on){$script:faultVisual=$on}
function Apply-SystemFrameTheme {}
function Refresh-DividerActivitySession {$script:activityRefreshes++}
function Invoke-AutoReconnect {$script:reconnectInvocations++}
function Update-RdcUpdateNoticePolling {throw 'updater forbidden in fixture'}
function Repair-DesktopCommanderMissingNpxPackageJson {return $false}
function Test-DesktopCommanderBootstrapFailure {return $false}
$logPath='C:\Fixture\RDC-mock-only-remote.log'
$root='C:\Fixture'
$desktopCommanderPackage='mock-package-only'
$nl=[Environment]::NewLine
$remoteConnectGraceSeconds=30
$SelfTest=$true;$Preview=$false
$finish=[pscustomobject]@{Enabled=$true}
$accountButton=[pscustomobject]@{Enabled=$true}
$switchAccountItem=[pscustomobject]@{Enabled=$true}
$reconnectItem=[pscustomobject]@{Enabled=$true}
$vScroll=[pscustomobject]@{IsDragging=$false}
$hScroll=[pscustomobject]@{IsDragging=$false}
$log=[pscustomobject]@{}
$log|Add-Member ScriptMethod GetViewPosition {return [Drawing.Point]::new(11,22)}
$form=[pscustomobject]@{CloseCount=0}
$form|Add-Member ScriptMethod Close {$this.CloseCount++}
function Reset-Fixture {
    $script:wmiRows=@();$script:wmiFailure=$false;$script:wmiQueries=0
    $script:fakeProcesses=@{};$script:missingPids=@();$script:processQueries=0
    $script:commandCalls=New-Object Collections.ArrayList
    $script:logCalls=New-Object Collections.ArrayList
    $script:launcherFailure=$false;$script:launcherReturnsNull=$false
    $script:proc=$null;$script:reader=$null;$script:remoteOperation=$null;$script:initializing=$false
    $script:manualStopRequested=$false;$script:stopping=$false;$script:supervisorRestarting=$false
    $script:preserveFaultOnStop=$false;$script:remoteReady=$false;$script:remoteFaultLatched=$false
    $script:autoReconnectAt=$null;$script:autoReconnectAttempt=0;$script:remoteConnectDeadline=$null
    $script:remoteInteractiveAuth=$false;$script:exitHandled=$false
    $script:closeRequested=$false;$script:allowClose=$false
    $script:logResets=0;$script:faultCleared=0;$script:faultKind=''
    $script:faultRetry=$false;$script:readCalls=0;$script:scheduled=0;$script:accountCleared=0
    $script:state='';$script:runtimeDisplay='';$script:stopped=$false;$script:starting=$false
    $script:finishMode=$false;$script:freezeViewport=$false;$script:smartFollow=$true
    $script:enableUpdateNotice=$false;$script:uiInteracting=$false;$script:activityRefreshes=0;$script:reconnectInvocations=0
    $script:userHorizontalX=0;$script:closeRequested=$false;$script:startTime=(Get-Date)
    $form.CloseCount=0
    foreach($button in @($finish,$accountButton,$switchAccountItem,$reconnectItem)){$button.Enabled=$true}
}
function Set-Candidates {
    $script:wmiRows=@(
      (New-Wmi 201 'cmd.exe' ('cmd /c npx desktop-commander remote > "'+$logPath+'"')),
      (New-Wmi 202 'cmd.exe' ('cmd /c npx desktop-commander remote > "'+$logPath+'"'))
    )
    $script:fakeProcesses[201]=New-FakeProcess 201
    $script:fakeProcesses[202]=New-FakeProcess 202
}
Case 'find ignores unrelated executable, partial command, other installation and missing command line' {
    Reset-Fixture
    $script:wmiRows=@(
        (New-Wmi 101 'powershell.exe' ('desktop-commander remote '+$logPath)),
        (New-Wmi 102 'cmd.exe' ('desktop-commander '+$logPath)),
        (New-Wmi 103 'cmd.exe' ('desktop-commander remote C:\Other\remote.log')),
        (New-Wmi 104 'cmd.exe' ''),
        (New-Wmi 105 'cmd.exe' ('desktop-commander remotely '+$logPath))
    )
    Assert ($null -eq (Find-ExistingRemote)) 'nonmatching candidate adopted'
    Assert ($script:processQueries -eq 1) 'legacy substring also matches remotely, then missing PID is swallowed'
}
Case 'find accepts remotely as a false-positive substring when process exists' {
    Reset-Fixture
    $script:wmiRows=@(New-Wmi 105 'cmd.exe' ('desktop-commander remotely '+$logPath))
    $script:fakeProcesses[105]=New-FakeProcess 105
    Assert ((Find-ExistingRemote).Id -eq 105) 'substring remotely no longer matches'
}
Case 'find adopts first matching process even with two indistinguishable candidates' {
    Reset-Fixture;Set-Candidates
    $found=Find-ExistingRemote
    Assert ($found.Id -eq 201 -and $script:processQueries -eq 1) 'not first candidate'
}
Case 'find is case-insensitive but requires this log-path substring' {
    Reset-Fixture
    $script:wmiRows=@(New-Wmi 211 'cmd.exe' ('NPX DESKTOP-COMMANDER REMOTE > "'+$logPath.ToUpperInvariant()+'"'))
    $script:fakeProcesses[211]=New-FakeProcess 211
    Assert ((Find-ExistingRemote).Id -eq 211) 'case mismatch'
}
Case 'find returns null on WMI failure, vanished PID or absent candidate' {
    Reset-Fixture;$script:wmiFailure=$true
    Assert ($null -eq (Find-ExistingRemote)) 'WMI error leaked'
    Reset-Fixture;Set-Candidates;$script:missingPids=@(201)
    Assert ($null -eq (Find-ExistingRemote)) 'first candidate failure not swallowed'
    Assert ($script:processQueries -eq 1) 'fallback to second candidate unexpectedly'
    Reset-Fixture
    Assert ($null -eq (Find-ExistingRemote)) 'no-candidate match'
}
Case 'find does not check PID creation time or process identity after WMI' {
    Reset-Fixture;Set-Candidates
    $script:fakeProcesses[201].StartTime=[datetime]'2035-01-01'
    Assert ((Find-ExistingRemote).Id -eq 201) 'timestamp unexpectedly checked'
}
Case 'start adopts remote without launcher, no ownership metadata' {
    Reset-Fixture;Set-Candidates
    Start-Remote
    Assert ($script:proc.Id -eq 201 -and $script:commandCalls.Count -eq 0) 'adoption launched another'
    Assert (-not $script:remoteReady -and $script:remoteConnectDeadline -and $script:logResets -eq 1) 'adoption state'
    Assert ($script:state -eq 'Проверка связи…' -and $script:runtimeDisplay -eq 'PID 201') 'adoption UI status'
}
Case 'start already alive returns without WMI or new launcher' {
    Reset-Fixture;$script:proc=New-FakeProcess 111
    Start-Remote
    Assert ($script:wmiQueries -eq 0 -and $script:commandCalls.Count -eq 0) 'duplicate start'
}
Case 'start with no candidate constructs hidden cmd npx redirection' {
    Reset-Fixture
    Start-Remote
    Assert ($script:commandCalls.Count -eq 1 -and $script:proc.Id -eq 9001) 'missing fake startup command'
    Assert ($script:commandCalls[0].Contains('remote > "'+$logPath+'" 2>&1')) 'launcher missing log redirection'
    Assert ($script:commandCalls[0].Contains('npx.cmd') -and $script:remoteConnectDeadline) 'missing npx or deadline'
}
Case 'start on WMI failure falls through to a new launch' {
    Reset-Fixture;$script:wmiFailure=$true
    Start-Remote
    Assert ($script:commandCalls.Count -eq 1 -and $script:proc.Id -eq 9001) 'WMI loss did not start fresh'
}
Case 'start when cmd launch fails records fault and queues reconnect' {
    Reset-Fixture;$script:launcherFailure=$true
    Start-Remote
    Assert ($script:faultKind -eq 'startup-error' -and $script:faultRetry -and $script:exitHandled) 'missing startup failure'
    Assert ($script:state -eq 'Ошибка запуска' -and $script:commandCalls.Count -eq 1) 'wrong startup error effects'
}
Case 'stop no handle or already exited sends no taskkill' {
    Reset-Fixture;Stop-Remote
    Assert ($script:commandCalls.Count -eq 0) 'no-handle stop'
    $script:proc=New-FakeProcess 221 $true;Stop-Remote
    Assert ($script:commandCalls.Count -eq 0) 'exited stop'
}
Case 'stop adopted process passes its PID into taskkill /T /F without identity check' {
    Reset-Fixture;Set-Candidates
    Start-Remote
    $script:remoteOperation=[pscustomobject]@{Action='stop';Stage='stopping';Process=$null;Deadline=(Get-Date).AddSeconds(10);Failure=''}
    Stop-Remote
    Assert ($script:commandCalls.Count -eq 1) 'taskkill was not dispatched through fake'
    Assert ($script:commandCalls[0].Contains('taskkill.exe') -and $script:commandCalls[0].Contains('/PID 201 /T /F')) 'unexpected stop command'
    Assert ($script:stopping -and $script:remoteOperation.Process.Id -eq 9001) 'stop state'
    Assert ($script:freezeViewport -and -not $finish.Enabled -and $script:state -eq 'Завершается…') 'stop view freeze'
}
Case 'stop uses stale PID after handle starts at different creation time' {
    Reset-Fixture
    $script:proc=New-FakeProcess 333
    $script:proc.StartTime=[datetime]'2040-01-01'
    $script:remoteOperation=[pscustomobject]@{Action='stop';Stage='stopping';Process=$null;Deadline=(Get-Date).AddSeconds(10);Failure=''}
    Stop-Remote
    Assert ($script:commandCalls.Count -eq 1 -and $script:commandCalls[0].Contains('/PID 333 /T /F')) 'identity now checked'
}
Case 'stop still issues taskkill while tool activity may be in flight' {
    Reset-Fixture
    $script:activeToolCalls=3;$script:proc=New-FakeProcess 444
    $script:remoteOperation=[pscustomobject]@{Action='stop';Stage='stopping';Process=$null;Deadline=(Get-Date).AddSeconds(10);Failure=''}
    Stop-Remote
    Assert ($script:activeToolCalls -eq 3 -and $script:commandCalls.Count -eq 1) 'in-flight tools blocked stop'
}
Case 'stop failure is surfaced by async operation, no duplicate restart' {
    Reset-Fixture;$script:proc=New-FakeProcess 555
    Begin-RemoteOperation 'restart'
    Assert ($script:remoteOperation -and $script:commandCalls.Count -eq 1) 'restart missing stop'
    $script:remoteOperation.Process.HasExited=$true;$script:remoteOperation.Process.ExitCode=1
    Update-RemoteOperation
    Assert ($script:faultKind -eq 'operation-failed' -and $script:commandCalls.Count -eq 1) 'unexpected restart after failure'
    Assert ($script:remoteOperation -eq $null -and $finish.Enabled -and -not $script:stopping) 'stop failure cleanup'
}
Case 'stop timeout leaves original handle and fault without relaunch' {
    Reset-Fixture;$script:proc=New-FakeProcess 566
    Begin-RemoteOperation 'restart'
    $script:remoteOperation.Deadline=(Get-Date).AddSeconds(-1)
    Update-RemoteOperation
    Assert ($script:faultKind -eq 'operation-failed' -and $script:proc.Id -eq 566) 'timeout handle/fault'
    Assert ($script:commandCalls.Count -eq 1 -and $script:remoteOperation -eq $null) 'timeout started relaunch'
}
Case 'duplicate Begin operations suppressed before another taskkill' {
    Reset-Fixture;$script:proc=New-FakeProcess 577
    Begin-RemoteOperation 'close'
    Begin-RemoteOperation 'restart'
    Assert ($script:commandCalls.Count -eq 1 -and $script:remoteOperation.Action -eq 'close') 'duplicate operation'
}
Case 'successful close waits for stop and then closes Form once' {
    Reset-Fixture;$script:proc=New-FakeProcess 588
    Begin-RemoteOperation 'close'
    Update-RemoteOperation
    Assert ($form.CloseCount -eq 0) 'Form closed early'
    $script:proc.HasExited=$true;$script:remoteOperation.Process.HasExited=$true
    Update-RemoteOperation
    Assert ($form.CloseCount -eq 1 -and $script:allowClose -and $script:commandCalls.Count -eq 1) 'Form close completion'
}
Case 'pending close suppresses logout and does not create logout command' {
    Reset-Fixture;$script:proc=New-FakeProcess 599;$script:closeRequested=$true
    Begin-RemoteOperation 'logout'
    $script:proc.HasExited=$true;$script:remoteOperation.Process.HasExited=$true
    Update-RemoteOperation
    Assert ($form.CloseCount -eq 1 -and $script:commandCalls.Count -eq 1) 'logout started despite close'
}
Case 'logout after stop starts synthetic npx --logout, then may restart' {
    Reset-Fixture;$script:proc=New-FakeProcess 610
    Begin-RemoteOperation 'logout'
    $script:proc.HasExited=$true;$script:remoteOperation.Process.HasExited=$true
    Update-RemoteOperation
    Assert ($script:remoteOperation.Stage -eq 'logout' -and $script:commandCalls.Count -eq 2) 'logout stage'
    Assert ($script:commandCalls[1].Contains('remote --logout')) 'missing logout argument'
    Assert ($script:commandCalls[1].Contains('logout-session.log')) 'logout log path'
}
Case 'supervisor reconnect preserves state of fault only until operation dispatch' {
    Reset-Fixture;$script:proc=New-FakeProcess 620;$script:supervisorRestarting=$true
    Begin-RemoteOperation 'reconnect'
    Assert ($script:commandCalls.Count -eq 1 -and $script:stopping) 'reconnect did not stop'
    Assert ($script:state -eq 'Переподключение…') 'wrong reconnect label'
}
Case 'refresh alive hidden process is monitored without window-handle check or hang kill' {
    Reset-Fixture
    $script:proc=New-FakeProcess 701
    $script:proc.MainWindowHandle=[IntPtr]::Zero
    $script:remoteConnectDeadline=(Get-Date).AddSeconds(-1)
    Refresh-Window
    Assert ($script:proc.RefreshCount -eq 1 -and $script:state -eq 'Подключается…') 'alive no-window monitor'
    Assert (-not $script:remoteConnectDeadline -and $script:reconnectInvocations -eq 0) 'deadline wrongly treated as transport fault'
    Assert ($script:commandCalls.Count -eq 0 -and $script:faultKind -eq '') 'hung/no-window started process action'
}
Case 'refresh alive Remote ready is healthy despite hidden GUI' {
    Reset-Fixture
    $script:proc=New-FakeProcess 702;$script:remoteReady=$true
    Refresh-Window
    Assert ($script:state -eq 'Работает' -and $script:proc.RefreshCount -eq 1) 'ready state'
    Assert ($script:commandCalls.Count -eq 0 -and $script:reconnectInvocations -eq 0) 'undesired supervisor action'
}
Case 'refresh alive process displays fault/auth before connecting state' {
    Reset-Fixture
    $script:proc=New-FakeProcess 703;$script:remoteFaultLatched=$true
    $script:remoteFaultReason='mock transport fault'
    Refresh-Window
    Assert ($script:state -eq 'Проблема связи') 'fault priority'
    $script:remoteFaultLatched=$false;$script:remoteInteractiveAuth=$true
    Refresh-Window
    Assert ($script:state -eq 'Ожидание авторизации…') 'auth priority'
}
Case 'refresh exited process latches process-exit fault exactly once' {
    Reset-Fixture;$script:proc=New-FakeProcess 704 $true 9
    Refresh-Window
    Assert ($script:faultKind -eq 'process-exit' -and $script:faultRetry -and $script:exitHandled) 'process-exit classification'
    Assert ($script:proc.RefreshCount -eq 1 -and $script:logCalls.Count -eq 1) 'exit log'
    Refresh-Window
    Assert ($script:proc.RefreshCount -eq 2 -and $script:logCalls.Count -eq 1) 'double exit report'
}
Case 'refresh returns early during initialization, active operation or UI drag' {
    Reset-Fixture;$script:proc=New-FakeProcess 705
    $script:initializing=$true
    function Complete-RuntimeInitialization {$script:initPolls++}
    $script:initPolls=0
    Refresh-Window
    Assert ($script:initPolls -eq 1 -and $script:proc.RefreshCount -eq 0) 'initializing case'
    $script:initializing=$false;$script:remoteOperation=[pscustomobject]@{Action='close';Stage='stopping';Process=$null;Deadline=(Get-Date).AddSeconds(3);Failure=''}
    # Do not invoke an operation against any PID: mock the operation update.
    function Update-RemoteOperation {$script:opPolls++}
    $script:opPolls=0
    Refresh-Window
    Assert ($script:opPolls -eq 1 -and $script:proc.RefreshCount -eq 0) 'operation priority'
    $script:remoteOperation=$null;$script:uiInteracting=$true
    Refresh-Window
    Assert ($script:proc.RefreshCount -eq 0 -and $script:logCalls.Count -eq 0) 'UI drag priority'
}
$minimum=27
$executed=$script:passed+$script:failed
if($executed -lt $minimum){Write-Output ('FAIL: test count '+$executed+' below '+$minimum);exit 1}
Write-Output ('TOTAL PROG-005A PROCESS: PASS='+$script:passed+' FAIL='+$script:failed)
if($script:failed){exit 1}
