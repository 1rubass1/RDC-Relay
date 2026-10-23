# PROG-004: pure classifier contract; no Remote execution, I/O, GUI or processes.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Source/remote-window.ps1'
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Source syntax errors'}
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-RemoteLineClassification'},$true)
if(-not $node){throw 'No pure classifier'}
. ([scriptblock]::Create($node.Extent.Text))
function Assert([bool]$ok,[string]$why){if(-not $ok){throw $why}}
$cases=@(
    @('Desktop Commander Remote is connected','','','ready',$false),
    @('Presence tracked (device fake visible)','', '', 'ready',$false),
    @('Authenticating with Remote MCP server','','','auth',$false),
    @('waiting for authentication','','','auth',$false),
    @('Remote session expired and could not be renewed','','','session-lost',$false),
    @('Restart the terminal running Desktop Commander to reconnect','','','session-lost',$false),
    @('This device is now offline for remote calls','','','session-lost',$false),
    @('Device startup failed: synthetic','','','startup-failed',$false),
    @('Local Desktop Commander MCP went away (closed)','','','local-mcp',$false),
    @('Could not restart local Desktop Commander MCP: synthetic','','','local-mcp',$false),
    @('Channel error: synthetic','','','transport-offline',$false),
    @('Channel closed','','','transport-offline',$false),
    @('Device marked as offline','','','transport-offline',$false),
    @('Device registered, but NOT reachable','','','remote-unreachable',$false),
    @('Realtime channel is not open','','','remote-unreachable',$false),
    @('Channel subscription timed out','','','remote-unreachable',$false),
    @('Presence track remained unavailable','','','remote-unreachable',$false),
    @('Presence published but the device row could not be updated','','','remote-unreachable',$false),
    @('Local Desktop Commander MCP restarted; device is online again','','','',$false),
    @('Local Desktop Commander MCP restarted; device is online again','local-mcp','','ready',$false),
    @('🔧 Received tool call a: test','','received','',$false),
    @('✅ Tool call a completed:','','completed','',$false),
    @('❌ Tool call a failed: synthetic','','failed','',$false),
    @('🔧Received tool call a: test','','','',$false),
    @('✅ Tool call a Completed:','','','',$false),
    @('{"text":"Channel error: synthetic"}','','','transport-offline',$true),
    @(' [text] Presence tracked (device fixture online)','','','ready',$true),
    @('tool stdout: Channel error: synthetic','','','transport-offline',$false),
    @('Channel error: broken; Presence tracked (device fake online)','','','ready',$false),
    @('','','','',$false),
    @('   ','','','',$false),
    @('Unknown event name','','','',$false)
)
$script:remoteReady=$true;$script:remoteFaultKind='sentinel'
$script:activeToolCalls=19;$script:manualStopRequested=$true
$count=0
foreach($row in $cases){
    $result=Get-RemoteLineClassification ([string]$row[0]) ([string]$row[1])
    Assert ($result.ToolKind -ceq [string]$row[2]) ('tool mismatch '+$count)
    Assert ($result.HealthKind -ceq [string]$row[3]) ('health mismatch '+$count)
    Assert ($result.IsSerializedToolPayload -eq [bool]$row[4]) ('payload mismatch '+$count)
    Assert ($script:remoteReady -and $script:remoteFaultKind -eq 'sentinel' -and $script:activeToolCalls -eq 19 -and $script:manualStopRequested) ('classifier mutated state '+$count)
    $count++
}
Write-Output ("PURE CLASSIFIER: PASS="+$count+" FAIL=0")
