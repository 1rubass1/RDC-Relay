# Read-only Remote observer classifier and guard tests. Never starts/stops Remote.
param([switch]$InspectLive)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Source\rc1-remote-observer.ps1')
$pass=0;$fail=0
function Check([bool]$good,[string]$name){
 if($good){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
try{
 $cases=@(
  @{Text='Desktop Commander Remote is connected';State='Ready';Marker='Remote connected'},
  @{Text='Presence tracked (device hidden-secret-value)';State='Ready';Marker='Remote connected'},
  @{Text='Authenticating with Remote MCP server';State='AuthPending';Marker='Authentication pending'},
  @{Text='Channel error: fake-secret-xyz';State='Fault';Marker='Remote channel unavailable'},
  @{Text='Device startup failed: fake-secret-xyz';State='Fault';Marker='Remote start failed'},
  @{Text='Local Desktop Commander MCP went away (fake-secret-xyz)';State='Reconnecting';Marker='Local MCP recovering'},
  @{Text='🔧 Received tool call secret-arguments';State='';Marker='Remote tool started'},
  @{Text='✅ Tool call secret completed: hidden';State='';Marker='Remote tool completed'},
  @{Text='❌ Tool call secret failed: hidden';State='';Marker='Remote tool failed'}
 )
 foreach($case in $cases){
  $result=Get-Rc1ObservedMarker $case.Text
  Check ($result.State -ceq $case.State -and $result.Marker -ceq $case.Marker -and
    $result.Marker.IndexOf('secret',[StringComparison]::OrdinalIgnoreCase) -lt 0) ('observer fixed allowlist '+$case.Marker)
 }
 Check ($null -eq (Get-Rc1ObservedMarker '{"password":"hidden"}')) 'JSON payload not forwarded over IPC'
 Check ($null -eq (Get-Rc1ObservedMarker 'Received tool call inside ordinary prose')) 'embedded tool marker not forwarded'
 Check ($null -eq (Get-Rc1ObservedMarker 'Unclassified private logfile line')) 'raw unclassified log suppressed'
 $scriptPath=Join-Path $root 'Source\rc1-remote-observer.ps1'
 $src=[IO.File]::ReadAllText($scriptPath)
 Check ($src.Contains('Get-CimInstance Win32_Process') -and
   $src.Contains('Test-Rc1ObservedRemoteIdentity') -and
   $src.Contains('Born') -and
   $src.Contains('@wonderwhy-er/desktop-commander@0.2.52')) 'PID birth and pinned commandline inspected'
 Check (-not [regex]::IsMatch($src,'(?im)^[^#\r\n]*(?:Stop-Process|taskkill|\.Kill\(|remote --logout|Process\.Start)')) 'observer has no Remote control or spawn code'
 $e=$null;$t=$null
 [void][Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$t,[ref]$e)
 Check ($e.Count -eq 0) 'observer script parsed on Windows PowerShell'
 $fixture=Join-Path ([IO.Path]::GetTempPath()) ('rc1-bootstrap-'+[Guid]::NewGuid().ToString('N')+'.log')
 try{
  [IO.File]::WriteAllText($fixture,("secret=should-not-leak"+[Environment]::NewLine+
    "Desktop Commander Remote is connected"+[Environment]::NewLine+
    "Channel closed secret=should-not-leak"+[Environment]::NewLine),[Text.Encoding]::UTF8)
  $sample=Get-Rc1ObservedHealthBootstrap $fixture
  Check ($sample.Complete -and $sample.State -ceq 'Fault' -and
    $sample.Detail.IndexOf('secret',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'bootstrap selects latest health state, redacts raw log'
  [IO.File]::WriteAllText($fixture,("Channel closed"+[Environment]::NewLine+
    "Desktop Commander Remote is connected"+[Environment]::NewLine),[Text.Encoding]::UTF8)
  $sample=Get-Rc1ObservedHealthBootstrap $fixture
  Check ($sample.Complete -and $sample.State -ceq 'Ready') 'bootstrap recognizes health recovery ordering'
  [IO.File]::WriteAllText($fixture,'password=must-never-cross-IPC',[Text.Encoding]::UTF8)
  $sample=Get-Rc1ObservedHealthBootstrap $fixture
  Check ($sample.Complete -and $sample.State -ceq 'Connecting') 'bootstrap cannot invent channel readiness'
 }finally{
  if([IO.File]::Exists($fixture)){[IO.File]::Delete($fixture)}
 }
 if($InspectLive){
  $identity=Get-Rc1ObservedRemoteIdentity
  Check (Test-Rc1ObservedRemoteIdentity $identity) 'existing OS PID/birth/session/exe verified'
  $alive=(Get-Process -Id $identity.Pid -ErrorAction Stop)
  Check ($alive.StartTime.ToUniversalTime().Ticks -eq $identity.Born) 'live Remote not stopped or restarted'
  $liveHistory=Get-Rc1ObservedHealthBootstrap $identity.Log
  Check ($liveHistory.Complete) 'live legacy log read within bounded health bootstrap'
  Write-Output ('OBSERVED_LIVE_BOOTSTRAP_STATE='+$liveHistory.State+' LINES='+$liveHistory.Lines)
  # Simulate a stale PID birth record only; never stop/replace actual Remote.
  $stale=@{};foreach($key in $identity.Keys){$stale[$key]=$identity[$key]}
  $stale.Born=([long]$identity.Born)-1
  $sink=[pscustomobject]@{Target=0;Alive=$false;Status='';Marker=''}
  Add-Member -InputObject $sink -MemberType ScriptMethod -Name RetargetObservedRemote -Value {param([int]$newProcessId)$this.Target=$newProcessId}
  Add-Member -InputObject $sink -MemberType ScriptMethod -Name UpdateObservedRemote -Value {param([bool]$alive,[string]$state,[string]$detail)$this.Alive=$alive;$this.Status=$state}
  Add-Member -InputObject $sink -MemberType ScriptMethod -Name ObservedMarker -Value {param([string]$marker)$this.Marker=$marker}
  Invoke-Rc1RemoteObserverPoll $sink $stale
  Check ($sink.Target -eq $identity.Pid -and $sink.Alive -and
    $sink.Marker -ceq 'Remote launcher replaced' -and $stale.Born -eq $identity.Born) 'stale birth safely reacquires verified same PID without process control'
 }
}catch{ $fail++;Write-Output ('FAIL exception '+$_.Exception.Message)}
Write-Output ('RC1_OBSERVED_REMOTE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0