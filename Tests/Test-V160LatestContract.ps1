# Isolated latest-channel compatibility; no actual Host, Remote, npm or auth.
$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs')|ForEach-Object{Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
$t=[RdcOwnerRuntime];$static=[Reflection.BindingFlags]'Static,NonPublic';$instance=[Reflection.BindingFlags]'Instance,NonPublic'
$header=$t.GetMethod('TrySafeStartupLine',$static)
$marker=$t.GetMethod('SafeRemoteMarker',$static)
$accept=$t.GetMethod('AcceptManagedStartupLine',$instance)
$pass=0
function Check([bool]$ok,[string]$name){if(!$ok){throw ('FAIL '+$name)};$script:pass++;'PASS '+$name}
function Header([string]$line,[bool]$expected){$a=[object[]]@($line,'');Check (([bool]$header.Invoke($null,$a)) -eq $expected) ('header '+$expected)}
function Marker([string]$line,[string]$expected){$a=[object[]]@($line,'');[void]$marker.Invoke($null,$a);Check ($a[1] -ceq $expected) ('state '+$expected)}
Header '   - Version:      0.3.4' $true
Header '   - Version: 0.3.4 token=fixture' $false
Header '   - Version: 99999999999.3.4' $false
Header '   - Server URL: https://private.invalid/fixture' $false
Marker 'Waiting for authorization' 'AuthPending'
Marker ([char]0x2705+' Device ready:') 'Ready'
Marker 'Device ready: untrusted suffix' ''
Marker 'Device registered, but NOT reachable - no command can arrive yet:' 'Fault'
Marker 'Retrying in the background; commands start working once you see Device ready:' ''
Marker 'Connected to Remote MCP' ''
Marker ([char]::ConvertFromUtf32(0x1F44B)+' Presence tracked (device aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee)') ''
Marker ([char]0x2705+' Device ready (device aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee)') ''
Marker 'Channel joined but the device row could not be updated - not ready' 'Fault'
Marker 'Failed to update device status: fixture' 'Fault'
Marker '[DEBUG] Failed to set status online: fixture' 'Fault'
Marker 'Desktop Commander Remote is connected with untrusted suffix' ''
Marker '{"output":"Device ready:"}' ''
$r=[Runtime.Serialization.FormatterServices]::GetUninitializedObject($t)
$list=New-Object 'System.Collections.Generic.List[string]'
$t.GetField('managedStartupHeader',$instance).SetValue($r,$list)
$t.GetField('remoteSupervisor',$instance).SetValue($r,(New-Object RdcOwnerRemoteState))
for($i=0;$i -lt 200;$i++){[void]$accept.Invoke($r,@('Downloading Chrome: 0%'))}
Check ($list.Count -eq 0) 'untrusted download rows not retained'
foreach($line in @('Starting MCP Device...','   - Version:      0.3.4','Device ready:','Desktop Commander Remote is connected')){[void]$accept.Invoke($r,@($line))}
Check ($list.Count -eq 4 -and $list[1].Contains('0.3.4')) 'real header survives 200 rejected progress lines'
[void]$accept.Invoke($r,@('Received tool call fixture: read_file {}'))
[void]$accept.Invoke($r,@('   - Version: 9.9.9'))
Check ($list.Count -eq 4) 'tool activity closes header capture'
$normalize=$t.GetMethod('ManagedConsoleLine',$static)
function Normalize([string]$line){return [string]$normalize.Invoke($null,@($line))}
$ready=[char]0x2705+' Device ready:'
Check ((Normalize ('[23:27:08] '+$ready)) -ceq $ready) 'observed timestamp framing removed'
Check ((Normalize $ready) -ceq $ready) 'legacy framing unchanged'
Check ((Normalize '[24:27:08] Device ready:') -ceq '[24:27:08] Device ready:') 'invalid timestamp rejected'
Check ((Normalize '[23:60:08] Device ready:') -ceq '[23:60:08] Device ready:') 'invalid minute rejected'
Check ((Normalize '[23:27:08] [23:27:08] Device ready:') -ceq '[23:27:08] Device ready:') 'only one prefix removed'
Marker (Normalize ('[23:27:08] '+$ready)) 'Ready'
Marker (Normalize '[23:24:07] Authenticating with Remote MCP server...') 'AuthPending'
Marker (Normalize '[23:27:09] Device registered, but NOT reachable') 'Fault'
Marker (Normalize '[23:27:08] {"output":"Device ready:"}') ''
Marker (Normalize '[23:27:08] [23:27:08] Device ready:') ''
Header (Normalize '[23:27:08]    - Version:      0.3.4') $true
Header (Normalize '[23:27:08]    - Version: 0.3.4 secret=fixture') $false
'RDC_LATEST_CONTRACT_PASS='+$pass
