# Tests shared preference against isolated files only. No real Host or GUI launch.
$ErrorActionPreference='Stop'
$r=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $r 'Source\RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$pass=0;$fail=0
function Check([bool]$condition,[string]$name){
 if($condition){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-AutoConnect-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
try{
 $p=Join-Path $dir 'preference'
 Check ([RdcOwnerAutoConnectPreference]::Enabled($p)) 'missing preference preserves existing auto-connect default'
 [RdcOwnerAutoConnectPreference]::InitializeDisabled($p)
 Check (-not [RdcOwnerAutoConnectPreference]::Enabled($p) -and [IO.File]::ReadAllText($p) -ceq 'disabled-v1') 'fresh installed preference is explicitly off'
 [RdcOwnerAutoConnectPreference]::Set($p,$true)
 [RdcOwnerAutoConnectPreference]::InitializeDisabled($p)
 Check ([RdcOwnerAutoConnectPreference]::Enabled($p)) 'initializer never overwrites existing on choice'
 [RdcOwnerAutoConnectPreference]::Set($p,$false)
 Check (-not [RdcOwnerAutoConnectPreference]::Enabled($p)) 'explicit off persists'
 Check ([IO.File]::ReadAllText($p) -ceq 'disabled-v1') 'off stored as an explicit marker'
 [RdcOwnerAutoConnectPreference]::Set($p,$true)
 Check ([RdcOwnerAutoConnectPreference]::Enabled($p)) 'explicit on persists'
 Check ([IO.File]::ReadAllText($p) -ceq 'enabled-v1') 'on stored as an explicit marker'
 [IO.File]::WriteAllText($p,'unexpected')
 Check (-not [RdcOwnerAutoConnectPreference]::Enabled($p)) 'corruption fails closed'
 [RdcOwnerAutoConnectPreference]::Set($p,$true)
 Check ([RdcOwnerAutoConnectPreference]::Enabled($p)) 'explicit on repairs corruption'
 Check (@(Get-ChildItem -LiteralPath $dir -File).Count -eq 1) 'no leaked temporary files'
 $hostSource=[IO.File]::ReadAllText((Join-Path $r 'Source\RdcOwnerRuntime.cs'))
 $gui=[IO.File]::ReadAllText((Join-Path $r 'Source\rc1-owner-gui.ps1'))
 Check ($hostSource.Contains('if(!RdcOwnerAutoConnectPreference.Enabled(RdcOwnerAutoConnectPreference.CurrentPath)){autoStartPending=false;return false;}') -and
  $hostSource.Contains('!guiAuthenticated||guiState!="CONNECTED"')) 'automatic launch still requires preference and authenticated GUI'
 Check ($hostSource.Contains('if(!enabled)autoStartPending=false;') -and $gui.Contains('[RdcOwnerAutoConnectPreference]::Set([RdcOwnerAutoConnectPreference]::CurrentPath')) 'tray and GUI share preference without stopping Remote'
 foreach($lang in @('ru-RU','en-US')){
  $catalog=[RdcUiLanguage]::LoadResources((Join-Path $r 'Source'),$lang)
  Check ($catalog.ContainsKey('tray.menu.autoConnect') -and $catalog.ContainsKey('tray.menu.autoConnectTooltip') -and $catalog.ContainsKey('tray.notice.autoConnectSaveFailed')) ('complete '+$lang+' localization')
 }
}finally{[IO.Directory]::Delete($dir,$true)}
Write-Output ('RDC_AUTOCONNECT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
