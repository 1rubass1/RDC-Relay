# Verify Owner GUI refreshes on the independent Remote state revision, not only Host events.
# No OS Host/GUI or Desktop Commander processes are created in this test.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Source'
$file=Join-Path $source 'rc1-owner-gui.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
$gui=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
Check ($errors.Count -eq 0) 'Owner GUI has valid PowerShell syntax'
Check ($gui.Contains('$script:ownerLastShownRemoteRevision=-1')) 'initial GUI Remote revision is unset'
Check ($gui.Contains('$remoteRevision=[long]$remoteSnapshot.revision')) 'GUI uses authoritative Remote snapshot revision'
Check ($gui.Contains('$remoteRevision -ne $script:ownerLastShownRemoteRevision')) 'Remote-only revision triggers status repaint'
Check ($gui.Contains('$script:ownerLastShownRemoteRevision=$remoteRevision')) 'Remote revision checkpoint advances'
Check ($gui.Contains('if($script:ownerRealMode)') -and $gui.Contains('$script:startupBlock=[string]::Join($nl,@(') -and
 $gui.Contains('Remote Connection')) 'original upper pane receives a sanitized connection summary'
Check ($gui.Contains('switch([string]$remoteSnapshot.state)') -and
 $gui.Contains("'Ready' {'Connected'}") -and $gui.Contains("'Fault' {'Connection fault'}")) 'header renders allowlisted state descriptions'
Check ($gui.Contains("'Ownership: '+$modeLabel") -and
 $gui.Contains('$safeOriginalHeader=$candidateHeader.TrimEnd()') -and
 $gui.Contains('$candidateHeader -cnotmatch')) 'summary fallback and validated full original header exclude raw tool calls'
Add-Type -Path @((Join-Path $source 'RdcOwnerProcess.cs'),(Join-Path $source 'RdcOwnerRemoteState.cs')) -ReferencedAssemblies @('System.Core.dll','System.dll')
$state=New-Object RdcOwnerRemoteState
$state.EnableManaged()
$before=$state.Snapshot()
$state.ManagedStatus(98989,$true,'Connecting','Starting pinned Desktop Commander Remote')
$connecting=$state.Snapshot()
$state.ManagedStatus(98989,$true,'Ready','Remote connected')
$ready=$state.Snapshot()
Check ([long]$connecting.revision -gt [long]$before.revision -and
 [long]$ready.revision -gt [long]$connecting.revision) 'Host Remote state revision advances without Host event'
Check ($ready.state -ceq 'Ready' -and $ready.transportReady -ceq 'MANAGED_READY') 'Remote readiness is independently exposed in snapshot'
Write-Output ('RC1_OWNER_GUI_REVISION_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
