# Read-only Owner transient UI status localization validation; no Host/Remote or real IPC.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
Add-Type -Path (Join-Path $src 'RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$pass=0;$fail=0
function Check([bool]$condition,[string]$name){
 if($condition){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$en=[RdcUiLanguage]::LoadResources($src,'en-US')
$ru=[RdcUiLanguage]::LoadResources($src,'ru-RU')
Check ($en.Count -eq $ru.Count -and $en.Count -ge 260) 'both locale resources have complete matching extension'
foreach($lang in @('ru-RU','en-US')){
 $map=if($lang -ceq 'ru-RU'){$ru}else{$en}
 foreach($key in @('owner.initial.observedName','owner.initial.observedDetail','owner.initial.managedName',
 'owner.initial.fakeName','owner.initial.fakeDetail',
 'owner.runtime.fakeHost','owner.runtime.managedWaiting','owner.error.navigationDetail',
 'owner.error.actionDetail','owner.error.hostDetail','owner.progress.switchDetail',
 'help.owner.observed','help.owner.managed','help.owner.fake',
 'journal.owner.diagHeading','journal.owner.title','journal.owner.copy','journal.owner.saveError')){
  Check (-not [string]::IsNullOrWhiteSpace([RdcUiLanguage]::Text($map,$key,''))) ($lang+' key '+$key)
 }
}
Check ($en['owner.initial.fakeName'] -ceq 'Test mode' -and
 $en['owner.runtime.notConnected'] -ceq 'Remote NOT connected | RC1') 'English fake-only GUI clearly identifies disconnected test mode'
Check ($en['owner.error.hostDetail'].Contains('stopping is prohibited') -and
 $en['owner.error.navigationDetail'].Contains('Remote was not changed')) 'English IPC/nav failures preserve safety guidance'
Check ($ru['owner.error.actionDetail'].Contains('{action}') -and
 $en['owner.error.actionDetail'].Contains('{action}')) 'denied-action label accepts only one named placeholder'
$code=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
Check ($code.Contains("switch -CaseSensitive ([string]$"+'script:ownerRequestedAction)') -and
 $code.Contains("'START' {(Get-RdcOwnerUiText") -and $code.Contains("'STOP' {(Get-RdcOwnerUiText") -and
 $code.Contains("'RECONNECT' {(Get-RdcOwnerUiText") -and
 $code.Contains("'SWITCH_ACCOUNT' {(Get-RdcOwnerUiText")) 'action denial displays only allowlisted action names'
Check (-not $code.Contains("'Host не подтвердил '+$"+'script:ownerRequestedAction') -and
 $code.Contains("Get-RdcOwnerUiText 'owner.action.unknown'")) 'unrecognized IPC action never echoed in translated GUI'
Check ($code.Contains("Get-RdcOwnerUiText 'owner.error.hostDetail'") -and
 $code.Contains('$script:ownerCanStop=$false') -and
 $code.Contains('$script:ownerLastSafePresentation=$null')) 'IPC failure keeps stop disabled and invalidates safe display cache'
Check ($code.Contains("Get-RdcOwnerUiText 'owner.initial.fakeEvent'") -and
 $code.Contains("Get-RdcOwnerUiText 'owner.initial.managedEvent'") -and
 $code.Contains("Get-RdcOwnerUiText 'owner.initial.observedEvent'")) 'all three initial GUI activity messages are locale-backed'
$original=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'),[Text.Encoding]::UTF8)
Check ($original.Contains("Get-RdcOwnerDialogText 'owner.progress.switchName'") -and
 $original.Contains('$script:ownerQueuedAction='+ "'SWITCH_ACCOUNT'") -and
 $original.Contains('if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }')) 'translated account transition retains explicit Yes requirement'
$errors=$null;$tokens=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'rc1-owner-gui.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Owner GUI PowerShell 5.1 parses'
$errors=$null;$tokens=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'remote-window.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'shared GUI source PowerShell 5.1 parses'
Write-Output ('RC1_REMAINING_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
