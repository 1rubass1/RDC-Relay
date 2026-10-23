# PROG-003: source characterization only. All process/IO hooks are fakes.
# Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File Tests/Test-RemoteCharacterization.ps1
param([string]$SourcePath = '', [string]$TracePath = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = if ($SourcePath) { [IO.Path]::GetFullPath($SourcePath) } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'Source/remote-window.ps1' }
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw "Source parse errors: $($parseErrors.Count)"}
$names=@('Schedule-AutoReconnect','Set-RemoteFault','Clear-RemoteFault','Mark-RemoteReady','Get-RemoteLineClassification','Update-RemoteHealthFromLine','Refresh-DividerActivitySession','Convert-ToCleanLogText','Limit-UiEvent','Add-CompletedEvent','Commit-CurrentEvent','Append-CurrentEvent','Test-StartupBoundaryLine','Set-StartupFromProbe','Reset-CompactLogSession','Process-RemoteLine','Add-RemoteChunk','Begin-RemoteOperation','Complete-RemoteOperation','Update-RemoteOperation','Invoke-AutoReconnect','Set-RemoteActionsEnabled','Reset-RemoteHandle')
foreach($name in $names){
    $n=$ast.Find({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true)
    if(-not $n){if($name -eq "Get-RemoteLineClassification"){continue}; throw "Function absent: $name"}
    . ([scriptblock]::Create($n.Extent.Text))
}
$script:passed=0; $script:failed=0
$script:records=New-Object System.Collections.ArrayList
function Assert([bool]$condition,[string]$why){if(-not $condition){throw $why}}
function Case([string]$name,[scriptblock]$body){
    $failBefore=$script:failed
    try { & $body; Write-Output "PASS: $name"; $script:passed++ }
    catch { Write-Output "FAIL: $name : $($_.Exception.Message)"; $script:failed++; }
    $normalizedLogs=@($script:logs | ForEach-Object { ([string]$_) -replace '\[\d{2}:\d{2}:\d{2}\]','[TIME]' })
    [void]$script:records.Add([ordered]@{
        Case=$name; Passed=[bool]($script:failed -eq $failBefore)
        Ready=[bool]$script:remoteReady; Latched=[bool]$script:remoteFaultLatched
        Fault=[string]$script:remoteFaultKind; Auth=[bool]$script:remoteInteractiveAuth
        Active=[int]$script:activeToolCalls; Working=[bool]$script:working
        FaultVisual=[bool]$script:faultVisual; Flashes=[int]$script:flashes
        Retry=[bool]$script:autoReconnectAt; RetryAttempt=[int]$script:autoReconnectAttempt
        Hold=[bool]$script:activityHoldUntil; ConnectDeadline=[bool]$script:remoteConnectDeadline
        Startup=[bool]$script:startupComplete; CurrentEvent=[string]$script:currentEvent
        CurrentTruncated=[bool]$script:currentEventTruncated; StartupBlock=[string]$script:startupBlock
        Events=@($script:eventBlocks | ForEach-Object { [string]$_ }); Logs=$normalizedLogs
        Effects=@($script:effects | ForEach-Object { [string]$_ })
    })
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
$script:effects=New-Object System.Collections.ArrayList
function Trace-Effect([string]$value){[void]$script:effects.Add($value)}
function Add-Log([string]$text){[void]$script:logs.Add($text); Trace-Effect (('log:'+$text) -replace '\[\d{2}:\d{2}:\d{2}\]','[TIME]')}
function Render-CompactLog {Trace-Effect 'render'}
function Update-AccountFromLog([string]$text){}
function Set-DividerWorkState([bool]$state){$script:working=$state; Trace-Effect ('work:'+$state)}
function Set-DividerFaultState([bool]$state){$script:faultVisual=$state; Trace-Effect ('fault:'+$state)}
function Start-DividerRecoveryFlash {$script:flashes++; Trace-Effect 'recovery-flash'}
function Set-DividerStoppedState([bool]$state){$script:stoppedVisual=$state; Trace-Effect ('stopped:'+$state)}
function Set-DividerStartupState([bool]$state){Trace-Effect ('startup:'+$state)}
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
    $script:logs.Clear();$script:eventBlocks.Clear();$script:effects.Clear()
    $script:faultVisual=$false
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

# PROG-003A: these tests intentionally preserve anomalies; do not correct source.
# Only already-decoded strings enter AST-loaded functions. Real reader is NOT CHECKED.
Case 'duplicate starts and matching duplicate successes use a global count' {
    Reset-Fixture
    Process-RemoteLine '🔧 Received tool call repeated: begin'
    Process-RemoteLine '🔧 Received tool call repeated: begin'
    Assert ($script:activeToolCalls -eq 2 -and $script:working) 'duplicate starts counted'
    Process-RemoteLine '✅ Tool call repeated completed:'
    Assert ($script:activeToolCalls -eq 1 -and -not $script:remoteReady -and -not $script:activityHoldUntil) 'first completion'
    Process-RemoteLine '✅ Tool call repeated completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady -and $script:flashes -eq 1) 'second completion'
    Assert ($script:activityHoldUntil -and $script:working) 'completion hold'
    Commit-CurrentEvent
    Assert ($script:eventBlocks.Count -eq 4) 'marker event count'
}
Case 'orphan completion and duplicate establish ready without a start' {
    Reset-Fixture
    Process-RemoteLine '✅ Tool call orphan completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady -and $script:flashes -eq 1) 'orphan completion'
    Assert ($script:activityHoldUntil -and $script:working) 'orphan hold/activity'
    $before=$script:logs.Count
    Process-RemoteLine '✅ Tool call orphan completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:flashes -eq 1 -and $script:logs.Count -eq $before) 'repeated orphan'
}
Case 'failure after success relatches fault then late success clears it' {
    Reset-Fixture
    Process-RemoteLine '✅ Tool call x completed:'
    Process-RemoteLine '❌ Tool call x failed: delayed'
    Assert ($script:activeToolCalls -eq 0 -and -not $script:remoteReady -and -not $script:working) 'late failure'
    Assert ($script:remoteFaultKind -eq 'tool-failed' -and $script:faultVisual -and -not $script:activityHoldUntil) 'fault visuals'
    $faultAt=$script:remoteFaultAt;$before=$script:logs.Count
    Process-RemoteLine '❌ Tool call x failed: repeated'
    Assert ($script:logs.Count -eq $before -and $script:remoteFaultAt -eq $faultAt) 'duplicate fault logging'
    Process-RemoteLine '✅ Tool call x completed:'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 2) 'success recovery'
    Assert ($script:logs.Count -gt $before) 'recovery log missing'
}
Case 'overlapping calls clear another failure on the last completion' {
    Reset-Fixture
    Process-RemoteLine '🔧 Received tool call alpha: begin'
    Process-RemoteLine '🔧 Received tool call beta: begin'
    Process-RemoteLine '❌ Tool call alpha failed: error'
    Assert ($script:activeToolCalls -eq 1 -and $script:working -and $script:remoteFaultKind -eq 'tool-failed') 'overlap failure'
    Process-RemoteLine '✅ Tool call beta completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady -and -not $script:remoteFaultLatched) 'overlap recovery'
    Assert ($script:flashes -eq 1 -and $script:activityHoldUntil) 'overlap side effects'
    Process-RemoteLine '❌ Tool call beta failed: late contradiction'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteFaultKind -eq 'tool-failed' -and -not $script:remoteReady) 'late contradiction'
}
Case 'mismatched tool IDs are not correlated' {
    Reset-Fixture
    Process-RemoteLine '🔧 Received tool call alpha: start'
    Process-RemoteLine '✅ Tool call unrelated completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady) 'wrong ID completion'
    Process-RemoteLine '❌ Tool call alpha failed: arrived late'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteFaultLatched) 'late ID failure'
}
Case 'duplicate failures consume count but log once for same fault' {
    Reset-Fixture
    Process-RemoteLine '🔧 Received tool call alpha: start'
    Process-RemoteLine '🔧 Received tool call beta: start'
    Process-RemoteLine '❌ Tool call alpha failed: first'
    Process-RemoteLine '❌ Tool call alpha failed: duplicate'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteFaultKind -eq 'tool-failed') 'duplicate consumed beta'
    Assert ($script:logs.Count -eq 1 -and -not $script:working) 'duplicate logs and activity'
}
Case 'near-match and embedded emoji tool markers are not classified' {
    Reset-Fixture;$script:startupComplete=$true
    $near=@(
        '🔧Received tool call x: begin',
        '🔧 received tool call x: begin',
        ' 🔧 Received tool call x: begin',
        'quoted 🔧 Received tool call x: begin',
        '✅ Tool call x completed',
        '✅ Tool call x Completed:',
        '✅  Tool call x completed:',
        '❌ Tool call x failed',
        '❌ Tool call x Failed:',
        '{"text":"🔧 Received tool call x: begin"}'
    )
    foreach($line in $near){Process-RemoteLine $line}
    Assert ($script:activeToolCalls -eq 0 -and -not $script:remoteReady -and -not $script:remoteFaultLatched) 'near marker state'
    Assert ($script:currentEvent.Contains('quoted 🔧')) 'nonmarkers disappeared'
    Process-RemoteLine '🔧 Received tool call x: begin'
    Assert ($script:activeToolCalls -eq 1) 'exact marker missed'
    Process-RemoteLine '✅ Tool call x completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady) 'exact success missed'
}
Case 'braced, bracketed and non-JSON payload have asymmetric health classification' {
    Reset-Fixture;Mark-RemoteReady
    Process-RemoteLine '   {"text":"Channel error: payload"}'
    Process-RemoteLine ' [{"text":"Device marked as offline"}]'
    Process-RemoteLine '[stdout] Channel error: payload'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched) 'bracketed escaped payload'
    Process-RemoteLine 'tool stdout: Channel error: fabricated payload'
    Assert ($script:remoteFaultKind -eq 'transport-offline' -and -not $script:remoteReady) 'non-JSON substring missed'
    Process-RemoteLine 'tool output: Presence tracked (device invented online)'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 2) 'non-JSON restore'
}
Case 'embedded health text inside user output causes real health transitions' {
    Reset-Fixture
    Process-RemoteLine 'tool output says: Presence tracked (device demo online)'
    Assert ($script:remoteReady -and $script:flashes -eq 1) 'embedded presence'
    Process-RemoteLine 'the document contains "Remote session expired and could not be renewed"'
    Assert ($script:remoteFaultKind -eq 'session-lost' -and -not $script:remoteReady -and $script:autoReconnectAt) 'embedded session'
    Assert ($script:logs.Count -ge 3) 'embedded health side effects absent'
}
Case 'ready dominates channel error within one contradictory line' {
    Reset-Fixture
    Process-RemoteLine 'Channel error: broken; Presence tracked (device fake online)'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 1) 'channel-first'
    Process-RemoteLine 'Presence tracked (device fake online); Channel error: broken'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 1) 'presence-first'
    Process-RemoteLine 'Channel error: broken'
    Assert ($script:remoteFaultKind -eq 'transport-offline' -and -not $script:remoteReady) 'separate later fault'
}
Case 'opposite ordering of separate channel and Presence signals changes state' {
    Reset-Fixture
    Process-RemoteLine 'Channel error: broken'
    Process-RemoteLine 'Presence tracked (device fake online)'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 1) 'loss then ready'
    Reset-Fixture
    Process-RemoteLine 'Presence tracked (device fake online)'
    Process-RemoteLine 'Channel error: broken'
    Assert (-not $script:remoteReady -and $script:remoteFaultKind -eq 'transport-offline' -and $script:flashes -eq 1) 'ready then loss'
    Process-RemoteLine 'Channel subscribed (recovered after 1 attempt)'
    Process-RemoteLine 'Device marked as online'
    Assert (-not $script:remoteReady -and $script:remoteFaultLatched) 'intermediate signals wrongly restored'
}
Case 'expiry then ready clears pending retry, reverse order schedules' {
    Reset-Fixture
    Process-RemoteLine 'Remote session expired and could not be renewed'
    Assert ($script:remoteFaultKind -eq 'session-lost' -and $script:autoReconnectAt) 'expiry'
    Process-RemoteLine 'Desktop Commander Remote is connected'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and -not $script:autoReconnectAt) 'ready cancellation'
    Reset-Fixture
    Process-RemoteLine 'Desktop Commander Remote is connected'
    Process-RemoteLine 'Remote session expired and could not be renewed'
    Assert (-not $script:remoteReady -and $script:remoteFaultKind -eq 'session-lost' -and $script:autoReconnectAt) 'reverse expiry'
}
Case 'local executor restart needs prior local-mcp fault, handshake is not ready' {
    Reset-Fixture; Mark-RemoteReady
    Process-RemoteLine 'Local Desktop Commander MCP went away (stdio closed)'
    Assert ($script:remoteFaultKind -eq 'local-mcp' -and -not $script:remoteReady) 'executor loss'
    Process-RemoteLine 'Connected to Desktop Commander MCP'
    Assert ($script:remoteFaultLatched -and -not $script:remoteReady) 'premature handshake'
    Process-RemoteLine 'Local Desktop Commander MCP restarted; device is online again'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 2) 'executor recovery'
    Process-RemoteLine 'Channel closed'
    Process-RemoteLine 'Local Desktop Commander MCP restarted; device is online again'
    Assert ($script:remoteFaultKind -eq 'transport-offline' -and -not $script:remoteReady) 'other fault mistaken for executor'
}
Case 'UTF-8 roundtrip and already-decoded Unicode split across chunks' {
    Reset-Fixture
    $start='🔧 Received tool call имя🚀: начало'
    $success='✅ Tool call имя🚀 completed:'
    $eol=[string][char]13+[string][char]10
    $wire=$start+$eol+$success+$eol
    $decoded=[Text.Encoding]::UTF8.GetString([Text.Encoding]::UTF8.GetBytes($wire))
    Assert ($wire -ceq $decoded) 'synthetic UTF-8 roundtrip'
    # Split inside the initial emoji surrogate pair and within the first line.
    Add-RemoteChunk $decoded.Substring(0,1)
    Assert ($script:activeToolCalls -eq 0) 'half surrogate consumed'
    Add-RemoteChunk $decoded.Substring(1,$start.Length-2)
    Assert ($script:activeToolCalls -eq 0) 'unterminated line consumed'
    Add-RemoteChunk $decoded.Substring($start.Length-1)
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady) 'marker sequence'
    Commit-CurrentEvent
    Assert ($script:eventBlocks.Count -eq 2) 'unicode marker count'
    Assert ($script:eventBlocks[0] -ceq $start) 'unicode start (Limit-UiEvent trims trailing CRLF)'
    Assert ($script:eventBlocks[1] -ceq $success) 'unicode success (Limit-UiEvent trims trailing CRLF)'
}
Case 'split CR LF adds an extra blank line through early normalization' {
    Reset-Fixture
    $start='🔧 Received tool call splitcr: begin'
    $cr=[string][char]13;$lf=[string][char]10
    Add-RemoteChunk ($start+$cr+$lf)
    $single=$script:currentEvent
    Reset-Fixture
    Add-RemoteChunk ($start+$cr)
    Assert ($script:activeToolCalls -eq 1) 'early CR'
    Add-RemoteChunk $lf
    Assert ($script:activeToolCalls -eq 1) 'second LF affected count'
    Assert ($script:currentEvent -ceq ($single+$nl)) 'expected duplicated EOL'
}
Case 'startup footer freezes header, marker-free live episode committed' {
    Reset-Fixture
    $footer='Run these in a new Terminal, or after disconnecting.'
    $eol=[string][char]13+[string][char]10
    Add-RemoteChunk ('START HEADER'+$eol+$footer+$eol)
    Assert ($script:startupComplete -and $script:startupBlock.Contains($footer)) 'footer state'
    Assert ($script:eventBlocks.Count -eq 0) 'startup recorded as event'
    Add-RemoteChunk ('Channel error: broken'+$eol+'Recreating channel...'+$eol+'Presence tracked (device demo online)'+$eol)
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched) 'runtime health'
    Assert ($script:eventBlocks.Count -eq 1 -and -not $script:currentEvent) 'episode not committed'
    Assert ($script:eventBlocks[0].Contains('Channel error:') -and $script:eventBlocks[0].Contains('Recreating channel...') -and $script:eventBlocks[0].Contains('Presence tracked')) 'runtime missing'
    Assert (-not $script:startupBlock.Contains('Channel error:')) 'runtime leaked to header'
}
Case 'marker before footer ends startup; late footer is activity text' {
    Reset-Fixture
    $lf=[string][char]10
    Add-RemoteChunk ('BOOT'+$lf+'🔧 Received tool call early: begin'+$lf)
    Assert ($script:startupComplete -and $script:startupBlock.Contains('BOOT')) 'marker startup boundary'
    Assert (-not $script:startupBlock.Contains('Received tool call')) 'marker in header'
    Add-RemoteChunk ('Run these in a new Terminal, or after disconnecting.'+$lf)
    Assert ($script:currentEvent.Contains('Run these in a new Terminal')) 'late footer misplaced'
    Process-RemoteLine '✅ Tool call early completed:'
    Commit-CurrentEvent
    Assert ($script:eventBlocks.Count -eq 2 -and $script:eventBlocks[0].StartsWith('🔧') -and $script:eventBlocks[1].StartsWith('✅')) 'event order'
}
Case 'startup probe boundary stops on footer or embedded Received text' {
    Reset-Fixture
    $eol=[string][char]13+[string][char]10
    Set-StartupFromProbe ('BOOT'+$eol+'Run these in a new Terminal, or after disconnecting.'+$eol+'Channel error: not header')
    Assert ($script:startupComplete -and -not $script:startupBlock.Contains('Channel error:')) 'footer probe'
    Reset-Fixture
    Set-StartupFromProbe ('BOOT'+$eol+'Some Received tool call x inside text'+$eol+'AFTER')
    Assert ($script:startupComplete -and -not $script:startupBlock.Contains('Received tool call') -and -not $script:startupBlock.Contains('AFTER')) 'embedded text probe'
}
Case 'event ring keeps exact last six events in chronological order' {
    Reset-Fixture; $script:startupComplete=$true
    for($i=0;$i -lt 8;$i++){
        Process-RemoteLine ('🔧 Received tool call seq'+$i+': begin')
        Commit-CurrentEvent
    }
    Assert ($script:eventBlocks.Count -eq 6 -and $script:activeToolCalls -eq 8) 'ring count'
    for($i=0;$i -lt 6;$i++){
        $expected='🔧 Received tool call seq'+($i+2)+': begin'
        Assert ($script:eventBlocks[$i].StartsWith($expected)) ('ring order '+$i)
    }
}
Case 'long event truncates at 8000 and startup header caps at 30000' {
    Reset-Fixture; $script:startupComplete=$true
    Process-RemoteLine ('Payload: '+('Ж'*9000))
    Process-RemoteLine 'ignored continuation'
    Assert ($script:currentEventTruncated -and $script:currentEvent.Length -le 8000) 'event stream max'
    Commit-CurrentEvent
    Assert ($script:eventBlocks.Count -eq 1 -and $script:eventBlocks[0].Contains('полный вывод')) 'truncation marker'
    Assert ($script:eventBlocks[0].Length -le 8000) 'visible event max'
    Reset-Fixture
    Add-RemoteChunk (('H'*30050)+[string][char]10)
    Assert ($script:startupBlock.Length -eq 30000) 'header cap'
}
Case 'near-full appended event overflows internally, then commit clamps' {
    Reset-Fixture; $script:startupComplete=$true
    Process-RemoteLine ('x'*7995)
    Process-RemoteLine 'second'
    Assert ($script:currentEventTruncated -and $script:currentEvent.Length -gt 8000) 'internal overflow anomaly'
    Commit-CurrentEvent
    Assert ($script:eventBlocks.Count -eq 1 -and $script:eventBlocks[0].Length -le 8000) 'visible max'
}


# PROG-004 mandatory PRE-CHANGE classification/effects matrix.
Case 'health ready signatures and conditional local recovery' {
    foreach($line in @('Desktop Commander Remote is connected','Presence tracked (device fixture online)')){
        Reset-Fixture;Update-RemoteHealthFromLine $line
        Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 1) ('ready '+$line)
        Assert ($script:logs.Count -eq 1 -and -not $script:autoReconnectAt) 'ready effects'
    }
    Reset-Fixture;Update-RemoteHealthFromLine 'Local Desktop Commander MCP restarted; device is online again'
    Assert (-not $script:remoteReady -and $script:flashes -eq 0) 'local restart without prior fault'
    Update-RemoteHealthFromLine 'Local Desktop Commander MCP went away (closed)'
    Update-RemoteHealthFromLine 'Local Desktop Commander MCP restarted; device is online again'
    Assert ($script:remoteReady -and -not $script:remoteFaultLatched -and $script:flashes -eq 1) 'conditional restart'
}
Case 'health authentication alternative signatures without false fault' {
    foreach($line in @('Authenticating with Remote MCP server','waiting for authentication')){
        Reset-Fixture;$script:remoteConnectDeadline=(Get-Date).AddSeconds(30)
        Update-RemoteHealthFromLine $line
        Assert ($script:remoteInteractiveAuth -and -not $script:remoteConnectDeadline) ('auth '+$line)
        Assert (-not $script:remoteReady -and -not $script:remoteFaultLatched -and $script:logs.Count -eq 0 -and $script:flashes -eq 0) 'auth effects'
        Update-RemoteHealthFromLine 'Presence tracked (device fixture online)'
        Assert ($script:remoteReady -and -not $script:remoteInteractiveAuth -and $script:flashes -eq 1) 'auth recovery'
    }
}
Case 'health each fatal session signature latches and schedules once' {
    foreach($line in @('Remote session expired and could not be renewed','Restart the terminal running Desktop Commander to reconnect','This device is now offline for remote calls')){
        Reset-Fixture;Update-RemoteHealthFromLine $line
        Assert ($script:remoteFaultKind -eq 'session-lost' -and $script:remoteFaultLatched -and -not $script:remoteReady) ('session '+$line)
        Assert ($script:autoReconnectAt -and $script:logs.Count -eq 2 -and $script:faultVisual -and $script:flashes -eq 0) 'session effects'
    }
}
Case 'health startup failed variant schedules reconnect' {
    Reset-Fixture; Update-RemoteHealthFromLine 'Device startup failed: synthetic'
    Assert ($script:remoteFaultKind -eq 'startup-failed' -and $script:remoteFaultLatched -and $script:autoReconnectAt) 'startup state'
    Assert ($script:logs.Count -eq 2 -and $script:faultVisual -and $script:flashes -eq 0) 'startup effects'
}
Case 'health local executor alternate signatures do not schedule' {
    foreach($line in @('Local Desktop Commander MCP went away (closed)','Could not restart local Desktop Commander MCP: error')){
        Reset-Fixture;$script:remoteConnectDeadline=(Get-Date).AddSeconds(30)
        Update-RemoteHealthFromLine $line
        Assert ($script:remoteFaultKind -eq 'local-mcp' -and $script:remoteFaultLatched -and -not $script:remoteConnectDeadline) ('local '+$line)
        Assert (-not $script:autoReconnectAt -and $script:logs.Count -eq 1 -and $script:faultVisual) 'local effects'
    }
}
Case 'health every transport failure signature latches without retry' {
    foreach($line in @('Channel error: synthetic','Channel closed','Device marked as offline')){
        Reset-Fixture;$script:remoteConnectDeadline=(Get-Date).AddSeconds(30)
        Update-RemoteHealthFromLine $line
        Assert ($script:remoteFaultKind -eq 'transport-offline' -and $script:remoteFaultLatched -and -not $script:remoteConnectDeadline) ('transport '+$line)
        Assert (-not $script:autoReconnectAt -and $script:logs.Count -eq 1 -and $script:faultVisual -and $script:flashes -eq 0) 'transport effects'
    }
}
Case 'health every unreachable signal latches without retry' {
    foreach($line in @('Device registered, but NOT reachable','Realtime channel is not open','Channel subscription timed out','Presence track remained unavailable','Presence published but the device row could not be updated')){
        Reset-Fixture;$script:remoteConnectDeadline=(Get-Date).AddSeconds(30)
        Update-RemoteHealthFromLine $line
        Assert ($script:remoteFaultKind -eq 'remote-unreachable' -and $script:remoteFaultLatched -and -not $script:remoteConnectDeadline) ('unreachable '+$line)
        Assert (-not $script:autoReconnectAt -and $script:logs.Count -eq 1 -and $script:faultVisual -and $script:flashes -eq 0) 'unreachable effects'
    }
}
Case 'health empty whitespace unknown online and subscription ignored' {
    foreach($line in @('','  ',([string][char]9),'Unknown output lorem ipsum','Channel subscribed (recovered after 5 attempts)','Device marked as online')){
        Reset-Fixture;Update-RemoteHealthFromLine $line
        Assert (-not $script:remoteReady -and -not $script:remoteFaultLatched -and -not $script:remoteInteractiveAuth) ('ignored '+$line)
        Assert ($script:logs.Count -eq 0 -and $script:flashes -eq 0 -and -not $script:autoReconnectAt) 'ignored effects'
    }
}
Case 'health direct update has manual-stop and stopping guards' {
    foreach($field in @('manualStopRequested','stopping')){
        Reset-Fixture;Set-Variable -Scope Script -Name $field -Value $true
        Update-RemoteHealthFromLine 'Remote session expired and could not be renewed'
        Update-RemoteHealthFromLine 'Presence tracked (device fixture online)'
        Assert (-not $script:remoteFaultLatched -and -not $script:remoteReady -and $script:logs.Count -eq 0 -and $script:flashes -eq 0) ('stop guard '+$field)
        Assert (-not $script:autoReconnectAt) 'stop scheduled retry'
    }
}
Case 'health precedence between adjacent branch categories' {
    $pairs=@(
        @('Desktop Commander Remote is connected','Remote session expired and could not be renewed','ready'),
        @('Authenticating with Remote MCP server','Device startup failed: synthetic','auth'),
        @('Remote session expired and could not be renewed','Device startup failed: synthetic','session-lost'),
        @('Device startup failed: synthetic','Local Desktop Commander MCP went away (offline)','startup-failed'),
        @('Local Desktop Commander MCP went away (offline)','Channel error: offline','local-mcp'),
        @('Channel error: offline','Device registered, but NOT reachable','transport-offline')
    )
    foreach($p in $pairs){
        Reset-Fixture;Process-RemoteLine ($p[0]+'; '+$p[1])
        if($p[2] -eq 'ready'){Assert ($script:remoteReady -and -not $script:remoteFaultLatched) 'ready priority';continue}
        if($p[2] -eq 'auth'){Assert ($script:remoteInteractiveAuth -and -not $script:remoteFaultLatched) 'auth priority';continue}
        Assert ($script:remoteFaultKind -eq $p[2]) ('fault priority '+$p[2])
    }
}
Case 'classification unknown exact markers and payload filtering' {
    Reset-Fixture;$script:startupComplete=$true
    foreach($line in @('','  ','✅ Tool call x completed','❌ Tool call x failed','🔧Received tool call x','unknown tool output')){Process-RemoteLine $line}
    Assert ($script:activeToolCalls -eq 0 -and -not $script:remoteReady -and -not $script:remoteFaultLatched) 'unknown lines classified'
    Process-RemoteLine '🔧 Received tool call x: Channel error: embedded'
    Assert ($script:activeToolCalls -eq 1 -and -not $script:remoteFaultLatched) 'received marker guard'
    Process-RemoteLine '✅ Tool call x completed:'
    Assert ($script:activeToolCalls -eq 0 -and $script:remoteReady -and $script:flashes -eq 1) 'complete marker'
    Process-RemoteLine '❌ Tool call x failed: bad'
    Assert ($script:remoteFaultKind -eq 'tool-failed' -and -not $script:remoteReady -and -not $script:working -and $script:faultVisual) 'failure marker'
    Process-RemoteLine '   {"detail":"Presence tracked (device synthetic online)"}'
    Process-RemoteLine '   [plain output] Presence tracked (device synthetic online)'
    Assert ($script:remoteFaultKind -eq 'tool-failed' -and -not $script:remoteReady) 'serialized guard'
    Process-RemoteLine 'payload: Presence tracked (device synthetic online)'
    Assert ($script:remoteReady -and $script:remoteFaultKind -eq 'tool-failed' -and $script:flashes -eq 1) 'free-text preserves tool fault'
}
Case 'health tool-timeout latch preserves ready until successful completion' {
    Reset-Fixture;$script:remoteReady=$true
    Set-RemoteFault 'tool-timeout' 'synthetic tool timeout' $false
    Assert ($script:remoteReady -and $script:remoteFaultKind -eq 'tool-timeout' -and $script:faultVisual) 'timeout preserves ready'
    Update-RemoteHealthFromLine 'Presence tracked (device fixture online)'
    Assert ($script:remoteFaultLatched -and $script:remoteReady -and $script:flashes -eq 0) 'timeout survives presence'
    Process-RemoteLine '✅ Tool call timeout_fixture completed:'
    Assert (-not $script:remoteFaultLatched -and $script:remoteReady -and $script:flashes -eq 1 -and $script:logs.Count -eq 2) 'timeout clears on success'
}
Case 'health case-insensitive substring priority is preserved' {
    Reset-Fixture;Process-RemoteLine 'some DESKTOP COMMANDER REMOTE IS CONNECTED inside output'
    Assert ($script:remoteReady -and $script:flashes -eq 1) 'ready substring'
    Process-RemoteLine 'DEVICE STARTUP FAILED: xyz; channel closed'
    Assert ($script:remoteFaultKind -eq 'startup-failed' -and $script:autoReconnectAt) 'startup priority'
    Process-RemoteLine 'WAITING FOR AUTHENTICATION; channel closed'
    Assert ($script:remoteInteractiveAuth -and $script:remoteFaultKind -eq 'startup-failed') 'auth priority'
}

# The minimum is an explicit coverage tripwire, not an assertion of real-system safety.
$expectedMinimumCases=46
$executedCases=$script:passed+$script:failed
if($executedCases -lt $expectedMinimumCases){Write-Output "FAIL: only $executedCases cases; minimum $expectedMinimumCases"; exit 1}
if ($TracePath) {
    $dest=[IO.Path]::GetFullPath($TracePath)
    $payload=ConvertTo-Json -InputObject @($script:records.ToArray()) -Depth 7 -Compress
    [IO.File]::WriteAllText($dest,$payload,(New-Object Text.UTF8Encoding($false)))
    Write-Output ("TRACE_SHA256="+(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash)
}
Write-Output "TOTAL: PASS=$script:passed FAIL=$script:failed"
if($script:failed){exit 1}
