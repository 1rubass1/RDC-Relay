# PROG-005A: inspect and invoke source's FormClosing, FormClosed and duplicate-GUI
# scriptblock with faked WMI, process, clock, sleep, mutex and shell foreground.
# The production script is NOT dot-sourced; Windows UI/Remote never launched.
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source/remote-window.ps1'
$raw=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$t=$null;$errs=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$t,[ref]$errs)
if($errs.Count){throw "source parse errors: $($errs.Count)"}
function Extract-FormHandler([string]$name){
    $match=[regex]::Match($raw,('(?s)\$form\.Add_'+$name+'\(\{(?<body>.*?)\r?\n\}\)'))
    if(-not $match.Success){throw ('Form handler not found: '+$name)}
    return [scriptblock]::Create($match.Groups['body'].Value)
}
$closing=Extract-FormHandler 'FormClosing'
$closed=Extract-FormHandler 'FormClosed'
# Use original complete singleton body (only 'exit 0' replaced with sentinel).
# The AST location is verified rather than copying a second implementation.
$node=$ast.Find({
    param($n)
    $n -is [Management.Automation.Language.IfStatementAst] -and
    $n.Extent.Text.StartsWith('if (-not $ownsWindow) {',[StringComparison]::Ordinal) -and
    $n.Extent.Text.Contains('Stop-Process -Id $peer.ProcessId -Force')
},$true)
if(-not $node){throw 'GUI singleton ownership branch not found in source AST'}
$singletonText=$node.Extent.Text
if(([regex]::Matches($singletonText,'exit 0')).Count -ne 2){throw 'Unexpected singleton exit count'}
$singletonText=$singletonText.Replace('exit 0',"throw 'FIXTURE_DUPLICATE_LAUNCHER_EXIT'")
$singletonText=$singletonText.Replace('$PSScriptRoot','$script:fixtureScriptRoot')
# The production statement writes at top-level; the fixture executes it as
# a nested scriptblock, so bind this top-level variable to fixture script scope.
$singletonText=$singletonText.Replace('$ownsWindow','$script:ownsWindow')
$script:fixtureScriptRoot=Split-Path -Parent $source
$singleton=[scriptblock]::Create($singletonText)
# Purely managed API stand-ins, never call Win32/user32 or display a real Form.
Add-Type -TypeDefinition @'
using System;
public static class RdcShellIdentity {
    public static int ShowCount=0;
    public static int ActivateCount=0;
    public static bool ShowWindow(IntPtr p,int mode) {ShowCount++;return true;}
    public static bool SetForegroundWindow(IntPtr p) {ActivateCount++;return true;}
}
'@
$script:passed=0;$script:failed=0
function Assert([bool]$cond,[string]$message){if(-not $cond){throw $message}}
function Case([string]$name,[scriptblock]$run){
    try { & $run;Write-Output ('PASS: '+$name);$script:passed++ }
    catch {Write-Output ('FAIL: '+$name+' :: '+$_.Exception.Message);$script:failed++}
}
function Fake-Resource{
    $o=[pscustomobject]@{Stopped=0;Disposed=0}
    $o|Add-Member ScriptMethod Stop {$this.Stopped++}
    $o|Add-Member ScriptMethod Dispose {$this.Disposed++}
    return $o
}
function Fake-Process([int]$id,[int]$handle=0,[int]$age=20,[bool]$exited=$false){
    $p=[pscustomobject]@{Id=$id;MainWindowHandle=[IntPtr]$handle;StartTime=([datetime]'2030-01-01').AddSeconds(-$age);HasExited=$exited;Disposed=0}
    $p|Add-Member ScriptMethod Dispose {$this.Disposed++}
    return $p
}
# Every OS-touching verb present in the singleton branch is replaced here.
function Get-CimInstance {param($ClassName,$ErrorAction) return $script:wmiRows}
function Get-Process {param([int]$Id,$ErrorAction) if($script:lostPids -contains $Id){throw 'fake vanished PID'};if($script:procs.ContainsKey($Id)){return $script:procs[$Id]};throw ('unmocked pid '+$Id)}
function Stop-Process {
    param([int]$Id,[switch]$Force,$ErrorAction)
    Assert ($script:procs.ContainsKey($Id)) 'mock Stop-Process called on unknown ID'
    [void]$script:killCalls.Add($Id)
}
function Start-Sleep {param([int]$Milliseconds) $script:sleepCalls++}
function Get-Date {
    $script:fakeNow=$script:fakeNow.AddMilliseconds(200)
    return $script:fakeNow
}
function Begin-RemoteOperation([string]$action) {
    $script:beginCalls++
    $script:beginAction=$action
    # Imitate only the handler-visible pending flag; original FSM tested elsewhere.
    if(-not $script:remoteOperation){$script:remoteOperation=[pscustomobject]@{Action=$action}}
}
function Dispose-RdcUpdateNotice {$script:updateDisposeCalls++}
$SelfTest=$false;$Preview=$false
$form=[pscustomobject]@{HideCount=0}
$form|Add-Member ScriptMethod Hide {$this.HideCount++}
function Reset-Form {
    $script:proc=$null;$script:reader=$null;$script:timer=(Fake-Resource)
    Set-Variable -Scope Script -Name timer -Value $script:timer
    $script:shortcutSyncTimer=$null
    $script:enableUpdateNotice=$false;$script:updateDisposeCalls=0
    $script:initializing=$false;$script:remoteOperation=$null
    $script:allowClose=$false;$script:closeRequested=$false
    $script:beginCalls=0;$script:beginAction=''
    $form.HideCount=0
    $script:SelfTest=$false;$script:Preview=$false
}
function Close-Once {
    $e=[pscustomobject]@{Cancel=$false}
    & $closing $form $e
    return $e
}
Case 'X while Remote running cancels close and begins destructive close operation' {
    Reset-Form;$script:proc=Fake-Process 111
    $e=Close-Once
    Assert ($e.Cancel -and $script:closeRequested -and $script:beginAction -eq 'close' -and $script:beginCalls -eq 1) 'close route'
    Assert ($form.HideCount -eq 0) 'X unexpectedly hidden Form'
}
Case 'X for adopted Remote uses same close route (no ownership distinction)' {
    Reset-Form;$script:proc=Fake-Process 222
    $e=Close-Once
    Assert ($e.Cancel -and $script:beginAction -eq 'close' -and $form.HideCount -eq 0) 'adopted close path'
}
Case 'X with no Remote handle allows Form to close directly' {
    Reset-Form
    $e=Close-Once
    Assert (-not $e.Cancel -and $script:beginCalls -eq 0 -and -not $script:closeRequested) 'no process close'
}
Case 'X with exited process handle allows Form to close directly' {
    Reset-Form;$script:proc=Fake-Process 333 0 20 $true
    $e=Close-Once
    Assert (-not $e.Cancel -and $script:beginCalls -eq 0) 'exited process'
}
Case 'X during initialization is canceled and deferred without stop' {
    Reset-Form;$script:initializing=$true;$script:proc=Fake-Process 444
    $e=Close-Once
    Assert ($e.Cancel -and $script:closeRequested -and $script:beginCalls -eq 0) 'init deferred'
}
Case 'X during existing operation only sets closeRequested, no second stop' {
    Reset-Form;$script:remoteOperation=[pscustomobject]@{Action='restart'}
    $e=Close-Once
    Assert ($e.Cancel -and $script:closeRequested -and $script:beginCalls -eq 0) 'pending operation'
}
Case 'X twice with fake pending operation starts only first close' {
    Reset-Form;$script:proc=Fake-Process 555
    $first=Close-Once;$second=Close-Once
    Assert ($first.Cancel -and $second.Cancel -and $script:beginCalls -eq 1 -and $script:closeRequested) 'duplicate X'
}
Case 'controlled allowClose exits immediately even with active Remote' {
    Reset-Form;$script:allowClose=$true;$script:proc=Fake-Process 666
    $e=Close-Once
    Assert (-not $e.Cancel -and $script:beginCalls -eq 0) 'controlled exit guard'
}
Case 'SelfTest and Preview bypass close interception' {
    foreach($mode in @('SelfTest','Preview')){
        Reset-Form;$script:proc=Fake-Process 777
        Set-Variable -Scope Script -Name $mode -Value $true
        $e=Close-Once
        Assert (-not $e.Cancel -and $script:beginCalls -eq 0) $mode
    }
}
Case 'FormClosed stops timer and disposes reader and process' {
    Reset-Form;$script:proc=Fake-Process 888;$script:reader=Fake-Resource
    & $closed
    Assert ($timer.Stopped -eq 1 -and $script:proc.Disposed -eq 1 -and $script:reader.Disposed -eq 1) 'resource disposal'
}
Case 'FormClosed cancels and disposes shortcut timer and update notice' {
    Reset-Form;$script:shortcutSyncTimer=Fake-Resource;$script:enableUpdateNotice=$true
    $shortcut=$script:shortcutSyncTimer
    & $closed
    Assert ($timer.Stopped -eq 1 -and $shortcut.Stopped -eq 1 -and $shortcut.Disposed -eq 1) 'timer disposal'
    Assert ($script:shortcutSyncTimer -eq $null -and $script:updateDisposeCalls -eq 1) 'notice dispose'
}
function Reset-Singleton {
    $script:wmiRows=@();$script:procs=@{};$script:lostPids=@()
    $script:killCalls=New-Object Collections.ArrayList
    $script:sleepCalls=0
    $script:fakeNow=[datetime]'2030-01-01'
    $script:ownsWindow=$false
    $script:mutexDisposed=0;$script:mutexWaitCount=0;$script:reacquire=$false
    $script:windowMutex=[pscustomobject]@{}
    $script:windowMutex|Add-Member ScriptMethod Dispose {$script:mutexDisposed++}
    $script:windowMutex|Add-Member ScriptMethod WaitOne {param($timeout) $script:mutexWaitCount++;return [bool]$script:reacquire}
    $script:reactivated=$false
    $script:SelfTest=$false;$script:Preview=$false
    [RdcShellIdentity]::ShowCount=0;[RdcShellIdentity]::ActivateCount=0
}
function Add-Peer([int]$id,[int]$handle=0,[int]$age=20,[string]$suffix=''){
    $needle=Join-Path $script:fixtureScriptRoot 'remote-window.ps1'
    $p=[pscustomobject]@{ProcessId=$id;Name='powershell.exe';CommandLine=('-File "'+$needle+'" '+$suffix)}
    $script:wmiRows+=,$p
    $proc=Fake-Process $id $handle $age
    # Date from Fake-Process created at same fixture origin, age matters.
    $script:procs[$id]=$proc
}
function Invoke-Singleton {
    try {
        & $singleton
        return 'TAKEOVER'
    } catch {
        if($_.Exception.Message -eq 'FIXTURE_DUPLICATE_LAUNCHER_EXIT'){return 'SECOND_EXIT'}
        throw
    }
}
Case 'second launcher reactivates visible peer via shell focus, never kills' {
    Reset-Singleton;Add-Peer 301 456
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 0) 'visible peer termination'
    Assert ([RdcShellIdentity]::ShowCount -eq 1 -and [RdcShellIdentity]::ActivateCount -eq 1) 'window focus'
    Assert ($script:mutexDisposed -eq 1 -and $script:mutexWaitCount -eq 0) 'mutex behavior'
}
Case 'hidden healthy older GUI is force-killed by second launcher (legacy hazard)' {
    Reset-Singleton;Add-Peer 302 0 90;$script:reacquire=$true
    $result=Invoke-Singleton
    Assert ($result -eq 'TAKEOVER' -and $script:killCalls.Count -eq 1 -and $script:killCalls[0] -eq 302) 'hidden GUI legacy kill'
    Assert ($script:mutexWaitCount -eq 1 -and $script:ownsWindow) 'takeover after forced stop'
}
Case 'young hidden GUI is not killed; second launcher exits instead' {
    Reset-Singleton;Add-Peer 303 0 0
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 0) 'young GUI killed'
    Assert ($script:mutexDisposed -eq 1) 'second launcher mutex not disposed'
}
Case 'hidden old GUI force-killed even if mutex cannot be acquired' {
    Reset-Singleton;Add-Peer 304 0 90
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 1 -and $script:mutexWaitCount -eq 1) 'unconditional old GUI kill'
}
Case 'two matching hidden GUI PIDs can both be force-killed' {
    Reset-Singleton;Add-Peer 305 0 90;Add-Peer 306 0 90
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 2) 'ambiguous candidate kill'
    Assert ($script:killCalls -contains 305 -and $script:killCalls -contains 306) 'candidate set'
}
Case 'vanished peer PID is ignored; second launcher exits without killing' {
    Reset-Singleton;Add-Peer 307 0 90;$script:lostPids=@(307)
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 0) 'stale PID kill'
}
Case 'no matching peer and mutex unavailable exits silently' {
    Reset-Singleton
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 0 -and $script:mutexDisposed -eq 1) 'no matching peer'
}
Case 'only exact script command peer is considered; Preview and SelfTest excluded' {
    Reset-Singleton;Add-Peer 308 0 90 '-Preview';Add-Peer 309 0 90 '-SelfTest'
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 0) 'excluded special instances'
}
Case 'candidate must be powershell.exe and contain this runtime path' {
    Reset-Singleton;Add-Peer 310 0 90
    $script:wmiRows[0].Name='cmd.exe'
    $result=Invoke-Singleton
    Assert ($result -eq 'SECOND_EXIT' -and $script:killCalls.Count -eq 0) 'non GUI candidate'
}
Case 'singleton requires visible MainWindowHandle; cannot reopen hidden Form' {
    Reset-Singleton;Add-Peer 311 0 90
    [void](Invoke-Singleton)
    Assert ([RdcShellIdentity]::ShowCount -eq 0 -and [RdcShellIdentity]::ActivateCount -eq 0) 'hidden Form reactivated'
    Assert ($script:killCalls.Count -eq 1) 'missing documented destructive fallback'
}
$minimum=21
$executed=$script:passed+$script:failed
if($executed -lt $minimum){Write-Output ('FAIL: only '+$executed+' cases; expected at least '+$minimum);exit 1}
Write-Output ('TOTAL PROG-005A WINDOW: PASS='+$script:passed+' FAIL='+$script:failed)
if($script:failed){exit 1}
