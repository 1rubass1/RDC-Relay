# PROG-003: source characterization only. All process/IO hooks are fakes.
# Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tests/Test-RemoteCharacterization.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'Source/remote-window.ps1'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw "Source parse errors: $($parseErrors.Count)"}
$names=@('Schedule-AutoReconnect','Set-RemoteFault','Clear-RemoteFault','Mark-RemoteReady','Update-RemoteHealthFromLine','Refresh-DividerActivitySession','Convert-ToCleanLogText','Limit-UiEvent','Add-CompletedEvent','Commit-CurrentEvent','Append-CurrentEvent','Test-StartupBoundaryLine','Process-RemoteLine','Add-RemoteChunk','Begin-RemoteOperation','Complete-RemoteOperation','Update-RemoteOperation','Invoke-AutoReconnect','Set-RemoteActionsEnabled','Reset-RemoteHandle')
foreach($name in $names){
    $n=$ast.Find({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true)
    if(-not $n){throw "Function absent: $name"}
    . ([scriptblock]::Create($n.Extent.Text))
}
$script:passed=0
function Assert([bool]$condition,[string]$why){if(-not $condition){throw $why}}
function Case([string]$name,[scriptblock]$body){
    try { & $body; Write-Output "PASS: $name"; $script:passed++ }
    catch { Write-Output "FAIL: $name : $($_.Exception.Message)"; $script:failed++; }
}
function New-FakeProcess([bool]$exited=$false,[int]$code=0){
    $p=[pscustomobject]@{HasExited=$exited;ExitCode=$code;Id=12345;Disposed=$false}
    $p|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    return $p
}
$nl=[Environment]::NewLine
$SelfTest=$false; $Preview=$false
$remoteReconnectDelaysSeconds=@(2.0,5.0,10.0)
$activityMinHoldSeconds=10.0;$activityMaxHoldSeconds=30.0
$activityInterruptedTimeoutSeconds=60.0
$uiEventMaxChars=8000;$uiStartupMaxChars=30000
$script:eventBlocks=New-Object System.Collections.ArrayList
$script:logs=New-Object System.Collections.ArrayList
function Add-Log([string]$text){[void]$script:logs.Add($text)}
function Render-CompactLog {}
function Update-AccountFromLog([string]$text){}
function Set-DividerWorkState([bool]$state){$script:working=$state}
function Set-DividerFaultState([bool]$state){$script:faultVisual=$state}
function Start-DividerRecoveryFlash {$script:flashes++}
function Set-DividerStoppedState([bool]$state){$script:stoppedVisual=$state}
function Set-DividerStartupState([bool]$state){}
function Set-FinishButtonMode([bool]$state){}
function Set-State($name,$message,$color){$script:state=$name}
function Read-LiveLog {}
function Set-AccountDisplay($email){}
function Start-Remote {$script:starts++}
function Stop-Remote {if($script:proc -and -not $script:proc.HasExited){$script:remoteOperation.Process=New-FakeProcess}}
$finish=[pscustomobject]@{Enabled=$true}
$accountButton=[pscustomobject]@{Enabled=$true}
$switchAccountItem=[pscustomobject]@{Enabled=$true}
$reconnectItem=[pscustomobject]@{Enabled=$true}
$form=[pscustomobject]@{CloseCount=0}
$form|Add-Member ScriptMethod Close {$this.CloseCount++}
function Reset-Fixture {
    $script:remoteReady=$false;$script:remoteFaultLatched=$false;$script:remoteFaultKind=''
    $script:remoteFaultReason='';$script:remoteFaultAt=$null
    $script:remoteConnectDeadline=$null;$script:remoteInteractiveAuth=$false
    $script:autoReconnectAt=$null;$script:autoReconnectAttempt=0
    $script:manualStopRequested=$false;$script:stopping=$false
    $script:supervisorRestarting=$false;$script:preserveFaultOnStop=$false
    $script:initializing=$false;$script:remoteOperation=$null
    $script:proc=$null;$script:closeRequested=$false;$script:allowClose=$false
    $script:activeToolCalls=0;$script:lastToolCompletedAt=$null
    $script:lastToolMarkerAt=$null;$script:activityHoldUntil=$null
    $script:activityGapEwmaSeconds=3.0;$script:activityHoldSeconds=10.0
    $script:currentEvent='';$script:currentEventTruncated=$false
    $script:remoteLineBuffer='';$script:startupBlock=''
    $script:startupComplete=$false;$script:seenFirstRemoteEvent=$false;$script:tailNeedsMarker=$false
    $script:flashes=0;$script:starts=0;$script:working=$false;$script:stoppedVisual=$false
    $script:logs.Clear();$script:eventBlocks.Clear()
    foreach($b in @($finish,$accountButton,$switchAccountItem,$reconnectItem)){$b.Enabled=$true}
}
Case 'ready, duplicate ready and transition flash' {
    Reset-Fixture
    Update-RemoteHealthFromLine 'Desktop Commander Remote is connected'
    Assert ($script:remoteReady -and $script:flashes -eq 1) 'initial ready'
    Update-RemoteHealthFromLine 'Presence tracked (device fixture visible as online)'
    Assert ($script:flashes -eq 1) 'duplicate flash'
}
Case 'transport fault needs presence, not subscription' {
    Reset-Fixture; Mark-RemoteReady
    Update-RemoteHealthFromLine 'Channel error: synthetic'
    Assert ($script:remoteFaultKind -eq 'transport-offline' -and -not $script:remoteReady) 'transport latch'
    Update-RemoteHealthFromLine 'Channel subscribed (recovered after 1 attempt)'
    Assert (-not $script:remoteReady -and $script:remoteFaultLatched) 'premature ready'
    Update-RemoteHealthFromLine 'Presence tracked (device fixture visible as online)'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and -not $script:autoReconnectAt) 'recover'
}
Case 'session expiry schedules bounded retry once' {
    Reset-Fixture
    Update-RemoteHealthFromLine 'Remote session expired and could not be renewed'
    Assert ($script:remoteFaultKind -eq 'session-lost' -and $script:autoReconnectAt) 'missing retry'
    $first=$script:autoReconnectAt; $count=$script:logs.Count
    Update-RemoteHealthFromLine 'Remote session expired and could not be renewed'
    Assert ($script:autoReconnectAt -eq $first -and $script:logs.Count -eq $count) 'duplicate retry/log'
    $script:autoReconnectAt=$null;$script:autoReconnectAttempt=3
    Schedule-AutoReconnect 'exhausted'
    Assert (-not $script:autoReconnectAt -and $script:remoteFaultReason -like '*3 попыток*') 'exhausted'
}
Case 'tool failure remains latched on presence and clears on success' {
    Reset-Fixture
    Process-RemoteLine '🔧 Received tool call fixture: begin'
    Process-RemoteLine '❌ Tool call fixture failed: synthetic'
    Assert ($script:remoteFaultKind -eq 'tool-failed') 'failure latch'
    Update-RemoteHealthFromLine 'Presence tracked (device fixture visible as online)'
    Assert ($script:remoteFaultLatched -and $script:remoteReady) 'presence cleared tool failure'
    Process-RemoteLine '✅ Tool call fixture completed:'
    Assert (-not $script:remoteFaultLatched -and $script:remoteReady) 'completion did not clear'
}
Case 'serialized payload and marker-looking content do not fault health' {
    Reset-Fixture;Mark-RemoteReady
    Process-RemoteLine '🔧 Received tool call foo: Channel error: synthetic'
    Process-RemoteLine '{"error":"Channel error: from tool output"}'
    Process-RemoteLine '[{"message":"Channel closed"}]'
    Assert (-not $script:remoteFaultLatched) 'payload interpreted as telemetry'
}
Case 'manual stop guards health and suppresses retries' {
    Reset-Fixture;$script:manualStopRequested=$true
    Update-RemoteHealthFromLine 'Channel closed'
    Set-RemoteFault 'session-lost' 'synthetic' $true
    Assert (-not $script:remoteFaultLatched -and -not $script:autoReconnectAt) 'manual stop faulted'
}
Case 'chunk splitting and six-event bounded ring' {
    Reset-Fixture
    Add-RemoteChunk "🔧 Received tool call a: begin"
    Assert ($script:activeToolCalls -eq 0) 'processed incomplete chunk'
    Add-RemoteChunk "`n"
    Assert ($script:activeToolCalls -eq 1) 'lost split marker'
    for($i=0;$i -lt 8;$i++){Process-RemoteLine "✅ Tool call fixture$i completed:"}
    Commit-CurrentEvent
    Assert ($script:eventBlocks.Count -eq 6) 'ring size'
    Assert ($script:activeToolCalls -eq 0) 'completion count below zero'
}
Case 'log ANSI removal, CR normalization and event truncation' {
    Reset-Fixture
    $clean=Convert-ToCleanLogText ([char]27+'[31mred'+[char]27+'[0m'+"`rx")
    Assert ($clean -eq ("red`r`nx")) 'cleanup'
    $item=Limit-UiEvent ('x'*9000)
    Assert ($item.Length -le 8000 -and $item.Contains('полный вывод')) 'bounded UI event'
}
Case 'stale activity retires without fault' {
    Reset-Fixture
    Process-RemoteLine '🔧 Received tool call slow: begin'
    $script:lastToolMarkerAt=(Get-Date).AddSeconds(-61)
    Refresh-DividerActivitySession
    Assert ($script:activeToolCalls -eq 0 -and -not $script:remoteFaultLatched) 'silence triggered fault'
}
Case 'operation stop is asynchronous and leaves neutral state' {
    Reset-Fixture;$script:proc=New-FakeProcess
    Begin-RemoteOperation 'stop'
    Assert ($script:manualStopRequested -and -not $finish.Enabled) 'stop guard/actions'
    Update-RemoteOperation
    Assert ($script:remoteOperation -ne $null) 'finished while child still alive'
    $script:proc.HasExited=$true;$script:remoteOperation.Process.HasExited=$true
    Update-RemoteOperation
    Assert ($null -eq $script:remoteOperation -and $script:stoppedVisual -and $script:starts -eq 0) 'stop completion'
}
Case 'failed termination never restarts' {
    Reset-Fixture;$script:proc=New-FakeProcess
    Begin-RemoteOperation 'restart'
    $script:remoteOperation.Process.HasExited=$true
    $script:remoteOperation.Process.ExitCode=1
    Update-RemoteOperation
    Assert ($script:starts -eq 0 -and $script:remoteFaultKind -eq 'operation-failed') 'unsafe restart'
}
Case 'retry action is scheduled but does not run in test mode' {
    Reset-Fixture; $script:autoReconnectAt=(Get-Date).AddSeconds(-1)
    $SelfTest=$true
    Invoke-AutoReconnect
    Assert ($script:starts -eq 0 -and $script:autoReconnectAttempt -eq 0) 'self-test reconnect launched'
    $SelfTest=$false
}
Write-Output "TOTAL: PASS=$script:passed FAIL=$script:failed"
if($script:failed){exit 1}
