# Isolated G122 native tray control contract. No Host, Remote or user tray starts.
# Exercise the exact production C# menu with fake callbacks and disposable prefs.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$hostFile=Join-Path $root 'Source\RdcOwnerRuntime.cs'
$source=[IO.File]::ReadAllText($hostFile,[Text.Encoding]::UTF8)
$first=$source.IndexOf('// Native tray menu:',[StringComparison]::Ordinal)
$last=$source.IndexOf('public sealed class RdcOwnerRuntime : IDisposable {',$first,[StringComparison]::Ordinal)
if($first -lt 0 -or $last -le $first){throw 'OWNER_TRAY_MENU_SOURCE_MARKERS_MISSING'}
$menuSource='using System; using System.IO; using System.Text; using System.Drawing; using System.Windows.Forms;'+
 [Environment]::NewLine+$source.Substring($first,$last-$first)
Add-Type -TypeDefinition $menuSource -ReferencedAssemblies @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll')
$pass=0;$fail=0
function Check([bool]$yes,[string]$name){
 if($yes){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$script:actions=New-Object 'System.Collections.Generic.List[string]'
$callback=[Action[string]]{param($verb)[void]$script:actions.Add($verb)}
$menu=New-Object RdcOwnerTrayMenu -ArgumentList @($callback)
try{
 $items=@($menu.Menu.Items)
 $labels=@($items|ForEach-Object{if($_ -is [Windows.Forms.ToolStripSeparator]){'---'}else{$_.Text}})
 $expected=@(
  'Открыть окно RDC Relay','---','Сменить аккаунт','Переподключить','---',
  'Управление устройствами','Выводить остаток вызовов','---',
  'Запустить','---','Справка о программе','---','Завершить RDC Relay')
 Check ($labels.Count -eq $expected.Count -and
  [string]::Join('|',$labels) -ceq [string]::Join('|',$expected)) 'native tray groups: open / account / devices+quota / control / Help / exit, five separators'
 Check (@($items|Where-Object{$_ -is [Windows.Forms.ToolStripSeparator]}).Count -eq 5 -and
  -not $labels.Contains('Remote: готов к управляемому запуску')) 'removed redundant read-only status line; no extra dividers'
 $menu.Refresh($false,$false,$false,$false,$false,$false,$true)
 Check ($menu.OpenItem.Enabled -and $menu.HelpItem.Enabled -and $menu.ExitItem.Enabled -and
  -not $menu.SwitchItem.Enabled -and -not $menu.ReconnectItem.Enabled -and
  -not $menu.DevicesItem.Enabled -and -not $menu.QuotaItem.Enabled -and
  -not $menu.StartStopItem.Enabled) 'fake-only Host permits Help/open/exit, refuses owned Remote actions'
 $menu.Refresh($false,$true,$false,$false,$false,$false,$true)
 Check ($menu.DevicesItem.Enabled -and -not $menu.SwitchItem.Enabled -and
  -not $menu.ReconnectItem.Enabled -and -not $menu.StartStopItem.Enabled -and
  -not $menu.QuotaItem.Enabled) 'Adopted Remote is read-only: official devices link only'
 $menu.Refresh($true,$false,$false,$false,$false,$false,$true)
 Check ($menu.StartStopItem.Text -ceq 'Запустить' -and $menu.StartStopItem.Enabled -and
  $menu.QuotaItem.Enabled -and $menu.QuotaItem.Checked -and
  -not $menu.SwitchItem.Enabled -and -not $menu.ReconnectItem.Enabled) 'idle Host-owned Remote exposes Start and checked quota'
 $menu.StartStopItem.PerformClick()
 Check ($script:actions.Count -eq 1 -and $script:actions[0] -ceq 'START') 'actual native Start click dispatches START once'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$false)
 Check ($menu.StartStopItem.Text -ceq 'Остановить' -and
  $menu.SwitchItem.Enabled -and $menu.ReconnectItem.Enabled -and
  -not $menu.QuotaItem.Checked) 'ready Host-owned Remote exposes Stop, Switch, Reconnect and unchecked quota'
 $menu.SwitchItem.PerformClick()
 $menu.ReconnectItem.PerformClick()
 $menu.StartStopItem.PerformClick()
 $menu.DevicesItem.PerformClick()
 $menu.HelpItem.PerformClick()
 $menu.OpenItem.PerformClick()
 Check ([string]::Join(',',$script:actions) -ceq
  'START,SWITCH_ACCOUNT,RECONNECT,STOP,DEVICES,HELP,OPEN') 'native clicks dispatch exact stable commands and never execute Host actions in test'
 $menu.QuotaItem.PerformClick()
 Check ($menu.QuotaItem.Checked -and $script:actions[$script:actions.Count-1] -ceq 'QUOTA_ON') 'native quota check dispatches enabled state'
 $menu.QuotaItem.PerformClick()
 Check (-not $menu.QuotaItem.Checked -and $script:actions[$script:actions.Count-1] -ceq 'QUOTA_OFF') 'native quota uncheck dispatches disabled state'
 $menu.Refresh($true,$false,$true,$false,$false,$false,$true)
 Check (-not $menu.SwitchItem.Enabled -and $menu.ReconnectItem.Enabled) 'switching account gated on Ready; reconnect allowed for running Connecting'
 $menu.Refresh($true,$false,$true,$true,$true,$false,$true)
 Check (-not $menu.StartStopItem.Enabled -and -not $menu.SwitchItem.Enabled -and
  -not $menu.ReconnectItem.Enabled -and $menu.QuotaItem.Enabled) 'logout Job disables concurrent Remote actions'
 $menu.Refresh($true,$false,$true,$true,$false,$true,$true)
 Check (-not $menu.ExitItem.Enabled -and -not $menu.StartStopItem.Enabled -and
  -not $menu.OpenItem.Enabled) 'Host shutdown disables new tray commands'
 $menu.Refresh($false,$true,$false,$false,$false,$false,$true)
 $before=$script:actions.Count
 $menu.StartStopItem.PerformClick()
 $menu.SwitchItem.PerformClick()
 Check ($script:actions.Count -eq $before) 'disabled borrowed-Remote commands have no user action callback'
}finally{$menu.Dispose()}
$pref=[RdcOwnerTrayQuotaPreference]
$state=Join-Path ([IO.Path]::GetTempPath()) ('RdcTrayQuota-'+[Guid]::NewGuid().ToString('N'))
$path=Join-Path $state 'quota-display.opt-in'
try{
 Check ([RdcOwnerTrayQuotaPreference]::Enabled($path)) 'shared preference defaults ON for missing marker'
 [RdcOwnerTrayQuotaPreference]::Set($path,$false)
 Check (-not [RdcOwnerTrayQuotaPreference]::Enabled($path) -and
  [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq 'disabled-v1') 'Host tray OFF writes GUI/Host-compatible disabled-v1 marker'
 [RdcOwnerTrayQuotaPreference]::Set($path,$false)
 Check (-not [RdcOwnerTrayQuotaPreference]::Enabled($path) -and
  @(Get-ChildItem -LiteralPath $state -Filter '*.tmp').Count -eq 0 -and
  @(Get-ChildItem -LiteralPath $state -Filter '*.bak').Count -eq 0) 'repeated OFF atomically replaces marker with no temporary residue'
 [RdcOwnerTrayQuotaPreference]::Set($path,$true)
 Check ([RdcOwnerTrayQuotaPreference]::Enabled($path) -and
  -not [IO.File]::Exists($path)) 'Host tray ON removes opt-out so GUI/Host automatic quota resumes'
 [IO.File]::WriteAllText($path,'enabled-v1',(New-Object Text.UTF8Encoding($false)))
 Check ([RdcOwnerTrayQuotaPreference]::Enabled($path)) 'legacy enabled-v1 migration compatible'
 [IO.File]::WriteAllText($path,'invalid',(New-Object Text.UTF8Encoding($false)))
 Check (-not [RdcOwnerTrayQuotaPreference]::Enabled($path)) 'malformed setting fails closed'
 [RdcOwnerTrayQuotaPreference]::Set($path,$true)
 Check ([RdcOwnerTrayQuotaPreference]::Enabled($path) -and -not (Test-Path -LiteralPath $path)) 'enable repairs malformed setting'
}finally{
 if(Test-Path -LiteralPath $path){[IO.File]::Delete($path)}
 if(Test-Path -LiteralPath $state){[IO.Directory]::Delete($state,$true)}
}
$gui=[IO.File]::ReadAllText((Join-Path $root 'Source\rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
Check ($source.Contains('new RdcOwnerTrayMenu(HandleTrayMenuAction)') -and
 $source.Contains('trayMenu.Menu.Opening+=(s,e)=>RefreshTrayMenu()') -and
 $source.Contains('tray.ContextMenuStrip=trayMenu.Menu') -and
 -not $source.Contains('trayStatusItem')) 'actual Host installs grouped menu and removes old status label'
Check ($source.Contains('BeginManagedAccountSwitch()') -and
 $source.Contains('StopManagedRemote();StartManagedRemote();') -and
 $source.Contains('if(!managedMode||observedMode') -and
 $source.Contains('ConfirmTrayAction(prompt,') -and
 $source.Contains('MessageBoxDefaultButton.Button2')) 'direct tray Remote actions reuse guarded owned Job methods with No-default confirmations'
Check ($source.Contains('https://mcp.desktopcommander.app/') -and
 $source.Contains('RdcOwnerTrayQuotaPreference.Set(RdcOwnerTrayQuotaPreference.CurrentPath') -and
 $source.Contains('RdcOwnerTrayQuotaPreference.Enabled(RdcOwnerTrayQuotaPreference.CurrentPath')) 'official devices route and exact shared quota preference'
Check ($source.Contains('trayHelpSequence=trayHelpSequence==Int32.MaxValue?1:trayHelpSequence+1') -and
 $source.Contains('trayHelpExpiresUtc=DateTime.UtcNow.AddSeconds(20)') -and
 $source.Contains('{"trayHelpSequence",DateTime.UtcNow<=trayHelpExpiresUtc?trayHelpSequence:0}') -and
 $gui.Contains('$script:ownerTrayHelpSeenSequence=0') -and
 $gui.Contains('$trayHelpSeq=[int]$snapshot.trayHelpSequence') -and
 $gui.Contains('$script:ownerTrayHelpSeenSequence=$trayHelpSeq') -and
 $gui.Contains('Show-RdcAbout')) 'authenticated Host snapshot triggers existing About exactly once per tray request'
Write-Output ('RC1_OWNER_TRAY_MENU_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
