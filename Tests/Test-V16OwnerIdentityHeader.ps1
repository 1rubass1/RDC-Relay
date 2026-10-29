# Isolated parsing and controlled IPC identity display. No real Remote is read or launched.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'))
$runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'))
$hostScript=[IO.File]::ReadAllText((Join-Path $src 'rc1-tray-host.ps1'))
$setup=[IO.File]::ReadAllText((Join-Path $root 'Installer\Rc1CandidateSetup.cs'))
$passes=0;$fails=0
function Check([bool]$ok,[string]$desc){if($ok){$script:passes++;Write-Output ('PASS '+$desc)}else{$script:fails++;Write-Output ('FAIL '+$desc)}}
Add-Type -Path @((Join-Path $src 'RdcOwnerWire.cs'),(Join-Path $src 'RdcOwnerProcess.cs'),(Join-Path $src 'RdcOwnerTicketStore.cs'),(Join-Path $src 'RdcOwnerRemoteState.cs'),(Join-Path $src 'RdcOwnerManagedProcess.cs'),(Join-Path $src 'RdcOwnerRuntime.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
$method=([RdcOwnerRuntime]).GetMethod('TrySafeIdentityLine',[Reflection.BindingFlags]'Static,NonPublic')
Check ($null -ne $method) 'Host validates private Remote header lines'
function ParseSafe([string]$line,[string]$label,[string]$value,[bool]$allowed){
 $args=[object[]]@($line,'','')
 $success=[bool]$method.Invoke($null,$args)
 Check ($success -eq $allowed -and (-not $success -or ($args[1] -ceq $label -and $args[2] -ceq $value))) ('Host parser '+$(if($allowed){'accepts '}else{'denies '})+$label)
}
if($method){
 ParseSafe '- User: tester@example.org' 'user' 'tester@example.org' $true
 ParseSafe '- Device Name: STARMER (Work)' 'deviceName' 'STARMER (Work)' $true
 ParseSafe '- Device ID: 12345678-1234-1234-1234-123456789abc' 'deviceId' '12345678-1234-1234-1234-123456789abc' $true
 ParseSafe 'User: tester@example.org' 'user' '' $false
 ParseSafe '- User: bearer-token' 'user' '' $false
 ParseSafe ('- Device Name: hi'+[char]10+'malicious') 'deviceName' '' $false
 ParseSafe '- Device Name: bad<script>' 'deviceName' '' $false
 ParseSafe '- Device ID: token-secret' 'deviceId' '' $false
}
Check ($runtime.Contains('AcceptManagedIdentityLine(cleanLine)')) 'Host consumes only owned managed log header'
Check ($runtime.Contains('remoteSupervisor.NoteHostEvent("Owned Remote identity metadata received: "+field)')) 'Metadata mutation increments independent Remote revision'
Check ($runtime.Contains('"remoteIdentity"') -and $runtime.Contains('managedMode?managedAccount:""')) 'Identity IPC data provided only by managed Host'
Check ($gui.Contains('Set-AccountDisplay $safeUser')) 'Authenticated GUI updates existing original footer account'
Check ($gui.Contains("('- Device Name: '") -and $gui.Contains("('- Device ID: '") -and $gui.Contains("('- User: '")) 'Original upper pane renders structured account and device header'
Check (-not $setup.Contains('MessageBoxIcon.Information')) 'Setup has no redundant informational completion popup'
Check ($hostScript.Contains('RC1_OTHER_RELEASE_HOST_STILL_RUNNING')) 'New Full Host prevents cross-release duplicate Hosts'
Write-Output ('RC1_OWNER_IDENTITY_PASS='+$passes+' FAIL='+$fails)
if($fails){exit 1}
exit 0
