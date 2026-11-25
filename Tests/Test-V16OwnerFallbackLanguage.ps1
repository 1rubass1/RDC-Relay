# Owner GUI sanitized startup fallback: only presentation is localized.
# No Host / Remote / IPC / GUI processes are started.
$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'
Add-Type -Path (Join-Path $src 'RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$ru=[RdcUiLanguage]::LoadResources($src,'ru-RU')
$en=[RdcUiLanguage]::LoadResources($src,'en-US')
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
$renderer=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$truth,[string]$title){
 if($truth){$script:pass++;Write-Output ('PASS '+$title)}
 else{$script:fail++;Write-Output ('FAIL '+$title)}
}
Check ($ru.Count -eq $en.Count -and $ru.Count -ge 261) 'same fixed 261-key RU/EN catalogs'
$keys=@(
 'owner.fallback.status.connecting','owner.fallback.status.authenticating',
 'owner.fallback.status.reconnecting','owner.fallback.status.connectionFault',
 'owner.fallback.status.disconnected','owner.fallback.status.unknown',
 'owner.fallback.status.online','owner.fallback.value.notReported',
 'owner.fallback.value.notStarted','owner.fallback.ownership.managed',
 'owner.fallback.ownership.adopted','owner.fallback.proof.receivedMarker',
 'owner.fallback.proof.unconfirmed','owner.fallback.label.status',
 'owner.fallback.label.user','owner.fallback.label.deviceName',
 'owner.fallback.label.deviceId','owner.fallback.label.process',
 'owner.fallback.label.ownership'
)
foreach($key in $keys){
 Check ($gui.Contains(("Get-RdcOwnerUiText '"+$key+"'")) -and
  $ru.ContainsKey($key) -and $en.ContainsKey($key) -and
  -not [String]::IsNullOrWhiteSpace($ru[$key]) -and
  -not [String]::IsNullOrWhiteSpace($en[$key])) ('source uses both locale values for '+$key)
}
Check ($keys.Count -eq 19 -and
 -not $gui.Contains("Get-RdcOwnerUiText 'owner.fallback.status.connected'") -and
 $gui.Contains("Get-RdcOwnerUiText 'owner.fallback.status.online'")) 'Connected is intentionally represented by the Online display key'
Check ($gui.Contains("'Ready' {'Connected'}") -and
 $gui.Contains("'Fault' {'Connection fault'}") -and
 $gui.Contains('switch -CaseSensitive ($safeState)')) 'original validated Host codes select the display-only state label'
Check ($gui.Contains("'Remote Connection'") -and
 $renderer.Contains('const string marker = "Remote Connection";') -and
 $renderer.Contains('StyleStartupBanner(Color leftColor, Color rightColor)')) 'protected banner styling marker is byte-identical'
Check ($gui.Contains('$safeOriginalHeader=$candidateHeader.TrimEnd()') -and
 $gui.Contains('$candidateHeader -cnotmatch') -and
 $gui.Contains('if($safeOriginalHeader){')) 'actual safe vendor header remains unmodified'
foreach($lang in @($ru,$en)){
 Check ($lang['owner.fallback.label.status'].EndsWith(' ') -and
  $lang['owner.fallback.label.user'].EndsWith(' ') -and
  $lang['owner.fallback.label.ownership'].EndsWith(' ')) 'language-specific labels preserve separators'
}
Check ($gui.Contains('$script:ownerLastShownRevision=-1') -and
 $gui.Contains('$script:ownerLastShownRemoteRevision=-1') -and
 $gui.Contains('if($script:ownerRealMode){')) 'locale change prompts fallback refresh using next normal Host snapshot'
Check ($en['owner.fallback.status.online'] -ceq 'Online' -and
 $ru['owner.fallback.status.online'] -cne 'Online') 'English/Russian Online display differs while status code remains invariant'
Write-Output ('RC1_FALLBACK_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
