# Isolated G122 native tray control contract. No Host, Remote or user tray starts.
# Exercise the exact production C# menu with fake callbacks and disposable prefs.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$hostFile=Join-Path $root 'Source\RdcOwnerRuntime.cs'
$source=[IO.File]::ReadAllText($hostFile,[Text.Encoding]::UTF8)
$first=$source.IndexOf('// Mirror of the GUI renderer, unchanged',[StringComparison]::Ordinal)
$last=$source.IndexOf('public sealed class RdcOwnerRuntime : IDisposable {',$first,[StringComparison]::Ordinal)
if($first -lt 0 -or $last -le $first){throw 'OWNER_TRAY_MENU_SOURCE_MARKERS_MISSING'}
$menuSource='using System.Drawing; using System.Drawing.Drawing2D; using System.Windows.Forms;'+
 [Environment]::NewLine+[IO.File]::ReadAllText((Join-Path $root 'Source\RdcUiLanguage.cs'),[Text.Encoding]::UTF8)+
 [Environment]::NewLine+$source.Substring($first,$last-$first)
Add-Type -TypeDefinition $menuSource -ReferencedAssemblies @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll')
$pass=0;$fail=0
function Check([bool]$yes,[string]$name){
 if($yes){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$script:actions=New-Object 'System.Collections.Generic.List[string]'
$callback=[Action[string]]{param($verb)[void]$script:actions.Add($verb)}
$menu=New-Object RdcOwnerTrayMenu -ArgumentList @($callback)
try{
 # Exact user-approved copy for the native tray Exit confirmation, with
 # unchanged Yes/No and safe default No in every runtime mode.
 $exitBegin=$source.IndexOf('trayExitItem.Click+=(s,e)=>{',[StringComparison]::Ordinal)
 $questionBegin=if($exitBegin -ge 0){$source.IndexOf('string question=',$exitBegin,[StringComparison]::Ordinal)}else{-1}
 $dialogBegin=if($exitBegin -ge 0){$source.IndexOf('if(!RdcOwnerTrayConfirmation.Ask(question,',$exitBegin,[StringComparison]::Ordinal)}else{-1}
 $questionCode=if($questionBegin -ge 0 -and $dialogBegin -gt $questionBegin){
  $source.Substring($questionBegin,$dialogBegin-$questionBegin).Trim()
 }else{''}
 Check ($questionCode -ceq 'string question=RdcUiLanguage.Text(exitLabels,"tray.confirm.exit","Завершить RDC Relay?");') 'tray Exit shows only the short user-approved confirmation question'
 $exitDialog=if($dialogBegin -ge 0){$source.Substring($dialogBegin,[Math]::Min(260,$source.Length-$dialogBegin))}else{''}
 Check ($exitDialog.Contains('"RDC Relay 1.6.0 RC1",exitLabels,false))return;')) 'tray Exit uses localized confirmation and requires explicit Yes'
 foreach($locale in @('ru-RU','en-US')){
  $catalog=[RdcUiLanguage]::LoadResources((Join-Path $root 'Source'),$locale)
  $expected=if($locale -eq 'en-US'){'Exit RDC Relay?'}else{'Завершить RDC Relay?'}
  $question=$catalog['tray.confirm.exit']
  $dialog=[RdcOwnerTrayConfirmation]::Create($question,'RDC Relay',$catalog,$false)
  try{
   $yes=@($dialog.Controls.Find('rc1-tray-confirm-yes',$true))[0]
   $no=@($dialog.Controls.Find('rc1-tray-confirm-no',$true))[0]
   Check ($question -ceq $expected -and $yes.Text -ceq $(if($locale -eq 'en-US'){'Yes'}else{'Да'}) -and $no.Text -ceq $(if($locale -eq 'en-US'){'No'}else{'Нет'})) "exit question and buttons match $locale"
   Check ($dialog.AcceptButton -eq $no -and $dialog.CancelButton -eq $no -and $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes -and $no.DialogResult -eq [Windows.Forms.DialogResult]::No) "safe default and cancel $locale"
   $dialog.StartPosition='Manual';$dialog.Location=[Drawing.Point]::new(-12000,-12000)
   $timer=New-Object Windows.Forms.Timer
   $timer.Interval=150
   $timer.Add_Tick({$timer.Stop();$no.PerformClick()})
   try{$timer.Start();$result=$dialog.ShowDialog();Check ($result -eq [Windows.Forms.DialogResult]::No -and $dialog.ClientSize.Width -ge 220 -and $dialog.ClientSize.Height -ge 90) "actual modal No and layout $locale"}finally{$timer.Dispose()}
  }finally{$dialog.Dispose()}
 }
 $items=@($menu.Menu.Items)
 $labels=@($items|ForEach-Object{if($_ -is [Windows.Forms.ToolStripSeparator]){'---'}else{$_.Text}})
 $expected=@(
  'Открыть окно RDC Relay','---','Сменить аккаунт','Переподключить','Запустить','Автоподключение','---',
  'Управление устройствами','Выводить остаток вызовов','---','Автозапуск','Автообновление','Язык / Language',
  'Справка о программе','---','Завершить RDC Relay')
 Check ($labels.Count -eq $expected.Count -and
  [string]::Join('|',$labels) -ceq [string]::Join('|',$expected)) 'native tray groups: open / account actions / devices+quota+auto-update / Help / exit, four separators'
 Check (@($items|Where-Object{$_ -is [Windows.Forms.ToolStripSeparator]}).Count -eq 4 -and
  -not $labels.Contains('Remote: готов к управляемому запуску')) 'removed redundant read-only status line; no extra dividers'
 # Capture the complete native tray popup, not a freestanding renderer.
 # This guards against menu-coordinate separator lines clipped by row graphics.
 $popup=$menu.Menu
 $popup.PerformLayout()
 $bitmap=New-Object Drawing.Bitmap($popup.Width,$popup.Height)
 try{
  $popup.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
  $ink=if([Windows.Forms.SystemInformation]::HighContrast){
   [Drawing.SystemColors]::WindowText
  }else{[Drawing.Color]::FromArgb(188,195,207)}
  $visible=0;$complete=0
  foreach($separator in @($popup.Items|Where-Object{$_ -is [Windows.Forms.ToolStripSeparator]})){
   $y=$separator.Bounds.Top+[int]($separator.Height/2)
   $bright=0
   for($x=$separator.Bounds.Left;$x -lt $separator.Bounds.Right;$x++){
    if($bitmap.GetPixel($x,$y).ToArgb() -eq $ink.ToArgb()){$bright++}
   }
   if($bright -eq $separator.Width -and $bright -gt 20){$complete++}
   $visible += $bright
  }
  Check ($complete -eq 4 -and $visible -ge 80) 'complete native tray popup visibly paints all four separators edge to edge'
  $popup.Items[0].Select()
  $popup.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
  $chosen=$bitmap.GetPixel(28,$popup.Items[0].Bounds.Top+[int]($popup.Items[0].Height/2))
  Check ([Windows.Forms.SystemInformation]::HighContrast -or
   ($chosen.R -eq 65 -and $chosen.G -eq 54 -and $chosen.B -eq 86)) 'native tray selected row matches purple Account highlight'
 }finally{$bitmap.Dispose()}
 $menu.Refresh($false,$false,$false,$false,$false,$false,$true,$true)
 Check ($menu.OpenItem.Enabled -and $menu.HelpItem.Enabled -and $menu.ExitItem.Enabled -and
  -not $menu.SwitchItem.Enabled -and -not $menu.ReconnectItem.Enabled -and
  -not $menu.DevicesItem.Enabled -and -not $menu.QuotaItem.Enabled -and
  -not $menu.StartStopItem.Enabled -and
  $menu.AutoUpdateItem.Enabled -and $menu.AutoUpdateItem.Checked) 'fake-only Host allows per-user auto-update preference, refuses owned Remote actions'
 $menu.Refresh($false,$true,$false,$false,$false,$false,$true,$true)
 Check ($menu.DevicesItem.Enabled -and -not $menu.SwitchItem.Enabled -and
  -not $menu.ReconnectItem.Enabled -and -not $menu.StartStopItem.Enabled -and
  -not $menu.QuotaItem.Enabled -and $menu.AutoUpdateItem.Enabled) 'Adopted Remote is read-only but personal auto-update preference remains available'
 $menu.Refresh($true,$false,$false,$false,$false,$false,$true,$true)
 Check ($menu.StartStopItem.Text -ceq 'Запустить' -and $menu.StartStopItem.Enabled -and
  $menu.QuotaItem.Enabled -and $menu.QuotaItem.Checked -and
  -not $menu.SwitchItem.Enabled -and -not $menu.ReconnectItem.Enabled) 'idle Host-owned Remote exposes Start and checked quota'
 $menu.StartStopItem.PerformClick()
 Check ($script:actions.Count -eq 1 -and $script:actions[0] -ceq 'START') 'actual native Start click dispatches START once'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$false,$true)
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
 # Language control uses distinct invariant commands, unrelated to Remote operations.
 $beforeLang=$script:actions.Count
 $menu.LanguageRussianItem.PerformClick()
 $menu.LanguageEnglishItem.PerformClick()
 Check ($script:actions.Count -eq $beforeLang+2 -and
   $script:actions[$beforeLang] -ceq 'LANGUAGE_RU' -and
   $script:actions[$beforeLang+1] -ceq 'LANGUAGE_EN') 'native tray locale selection dispatches only language commands'
 $enCatalog=[RdcUiLanguage]::LoadResources((Join-Path $root 'Source'),'en-US')
 $menu.Refresh($true,$false,$false,$false,$false,$false,$true,$true)
 $menu.ApplyLanguage('en-US',$enCatalog)
 Check ($menu.StartStopItem.Text -ceq 'Start' -and
  $menu.OpenItem.Text -ceq 'Open RDC Relay window' -and
  $menu.LanguageEnglishItem.Checked -and -not $menu.LanguageRussianItem.Checked) 'English tray labels and language check reflect selection without changing Remote state'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$true,$true)
 $menu.ApplyLanguage('en-US',$enCatalog)
 Check ($menu.StartStopItem.Text -ceq 'Stop') 'running state still chooses Stop in English'
 $ruCatalog=[RdcUiLanguage]::LoadResources((Join-Path $root 'Source'),'ru-RU')
 $menu.ApplyLanguage('ru-RU',$ruCatalog)
 Check ($menu.StartStopItem.Text -ceq 'Остановить' -and
  $menu.LanguageRussianItem.Checked -and -not $menu.LanguageEnglishItem.Checked) 'Russian tray labels restored without user Remote action'
 # Locale and display text are not part of command dispatch.
 $before=$script:actions.Count
 $menu.Refresh($true,$false,$false,$false,$false,$false,$false,$true)
 $menu.StartStopItem.Text='Stop'
 $menu.StartStopItem.PerformClick()
 Check ($script:actions.Count -eq $before+1 -and $script:actions[$before] -ceq 'START') 'localized Stop text cannot change Host idle START action'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$false,$true)
 $menu.StartStopItem.Text='Start'
 $menu.StartStopItem.PerformClick()
 Check ($script:actions.Count -eq $before+2 -and $script:actions[$before+1] -ceq 'STOP') 'localized Start text cannot change Host running STOP action'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$false,$true)
 $menu.QuotaItem.PerformClick()
 Check ($menu.QuotaItem.Checked -and $script:actions[$script:actions.Count-1] -ceq 'QUOTA_ON') 'native quota check dispatches enabled state'
 $menu.QuotaItem.PerformClick()
 Check (-not $menu.QuotaItem.Checked -and $script:actions[$script:actions.Count-1] -ceq 'QUOTA_OFF') 'native quota uncheck dispatches disabled state'
 $menu.AutoUpdateItem.PerformClick()
 Check (-not $menu.AutoUpdateItem.Checked -and
  $script:actions[$script:actions.Count-1] -ceq 'AUTO_UPDATE_OFF') 'auto-update check-off dispatches persisted OFF request'
 $menu.AutoUpdateItem.PerformClick()
 Check ($menu.AutoUpdateItem.Checked -and
  $script:actions[$script:actions.Count-1] -ceq 'AUTO_UPDATE_ON') 'auto-update check-on dispatches ON request'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$false,$false)
 Check (-not $menu.AutoUpdateItem.Checked -and $menu.AutoUpdateItem.Enabled) 'reopening native menu re-reads externally changed auto-update OFF'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$false,$true)
 Check ($menu.AutoUpdateItem.Checked) 'reopening native menu re-reads externally changed auto-update ON'
 $menu.Refresh($true,$false,$true,$true,$false,$false,$true,$true,$false)
 Check (-not $menu.AutoConnectItem.Checked -and $menu.AutoConnectItem.Enabled -and
  $null -ne $menu.HelpItem.Image -and $menu.HelpItem.Name -ceq 'rc1-tray-help') 'auto-connect state independent of auto-update and Help has the native question icon'
 $menu.AutoConnectItem.PerformClick()
 Check ($menu.AutoConnectItem.Checked -and $script:actions[$script:actions.Count-1] -ceq 'AUTO_CONNECT_ON') 'native auto-connect ON click is a preference command'
 $menu.AutoConnectItem.PerformClick()
 Check (-not $menu.AutoConnectItem.Checked -and $script:actions[$script:actions.Count-1] -ceq 'AUTO_CONNECT_OFF') 'native auto-connect OFF click is a preference command'
 $menu.Refresh($true,$false,$true,$false,$false,$false,$true,$true)
 Check (-not $menu.SwitchItem.Enabled -and $menu.ReconnectItem.Enabled) 'switching account gated on Ready; reconnect allowed for running Connecting'
 $menu.Refresh($true,$false,$true,$true,$true,$false,$true,$true)
 Check (-not $menu.StartStopItem.Enabled -and -not $menu.SwitchItem.Enabled -and
  -not $menu.ReconnectItem.Enabled -and $menu.QuotaItem.Enabled) 'logout Job disables concurrent Remote actions'
 $menu.Refresh($true,$false,$true,$true,$false,$true,$true,$true)
 Check (-not $menu.ExitItem.Enabled -and -not $menu.StartStopItem.Enabled -and
  -not $menu.OpenItem.Enabled -and -not $menu.AutoUpdateItem.Enabled) 'Host shutdown disables new tray commands'
 $menu.Refresh($false,$true,$false,$false,$false,$false,$true,$true)
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
# Cross-process / cross-UI durable auto-update preference contract:
# actual native Host class and actual GUI PowerShell preference functions.
$autoRoot=Join-Path ([IO.Path]::GetTempPath()) ('RdcTrayAutoUpdate-'+[Guid]::NewGuid().ToString('N'))
$autoPath=Join-Path $autoRoot 'auto-update.opt-out'
$psFile=Join-Path $root 'Source\remote-window.ps1'
$psTokens=$null;$psErrors=$null
$psAst=[Management.Automation.Language.Parser]::ParseFile($psFile,[ref]$psTokens,[ref]$psErrors)
Check ($psErrors.Count -eq 0) 'actual GUI script parses with update preference functions'
foreach($fn in @('Test-RdcAutoUpdateEnabled','Set-RdcAutoUpdateEnabled')){
 $f=$psAst.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fn},$true)
 if(-not $f){throw ('GUI_UPDATE_PREFERENCE_FUNCTION_MISSING: '+$fn)}
 . ([scriptblock]::Create($f.Extent.Text))
}
try{
 Check ([RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  (Test-RdcAutoUpdateEnabled $autoPath)) 'auto-update ON by default in both tray Host and account menu'
 [RdcOwnerTrayAutoUpdatePreference]::Set($autoPath,$false)
 Check (-not [RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  -not (Test-RdcAutoUpdateEnabled $autoPath) -and
  [IO.File]::ReadAllText($autoPath,[Text.Encoding]::UTF8) -ceq 'disabled-v1') 'tray OFF persists same opt-out understood by account GUI'
 Set-RdcAutoUpdateEnabled $autoPath $true
 Check ([RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  (Test-RdcAutoUpdateEnabled $autoPath) -and
  -not [IO.File]::Exists($autoPath)) 'GUI ON persists default and immediately restores tray check'
 Set-RdcAutoUpdateEnabled $autoPath $false
 Check (-not [RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  -not (Test-RdcAutoUpdateEnabled $autoPath)) 'GUI OFF is read by tray after reopen, independent of Remote mode'
 Set-RdcAutoUpdateEnabled $autoPath $false
 Check (-not [RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  @(Get-ChildItem -LiteralPath $autoRoot -Filter '*.tmp').Count -eq 0 -and
  @(Get-ChildItem -LiteralPath $autoRoot -Filter '*.bak').Count -eq 0) 'repeated OFF is atomic and has no leaked temporary files'
 [IO.File]::WriteAllText($autoPath,'enabled-v1',(New-Object Text.UTF8Encoding($false)))
 Check ([RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  (Test-RdcAutoUpdateEnabled $autoPath)) 'legacy enabled-v1 marker accepted by both views'
 [IO.File]::WriteAllText($autoPath,'invalid',(New-Object Text.UTF8Encoding($false)))
 Check (-not [RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  -not (Test-RdcAutoUpdateEnabled $autoPath)) 'corrupted setting fails closed, never silently enables automatic update'
 [RdcOwnerTrayAutoUpdatePreference]::Set($autoPath,$true)
 Check ([RdcOwnerTrayAutoUpdatePreference]::Enabled($autoPath) -and
  -not [IO.File]::Exists($autoPath)) 're-enabling repairs corrupted setting without touching live software'
}finally{
 if([IO.File]::Exists($autoPath)){[IO.File]::Delete($autoPath)}
 if([IO.Directory]::Exists($autoRoot)){[IO.Directory]::Delete($autoRoot,$true)}
}
$rw=[IO.File]::ReadAllText($psFile,[Text.Encoding]::UTF8)
Check (-not $rw.Contains('$autoUpdateAuthItem') -and
 -not $rw.Contains('$languageMenuItem') -and
 $rw.Contains('$accountMenu.Items.Add($quotaAuthItem)') -and
 $source.Contains('AutoUpdateItem.CheckOnClick=true') -and
 $source.Contains('Menu.Items.Add(AutoUpdateItem)') -and
 $source.Contains('Menu.Items.Add(LanguageItem)') -and
 $rw.Contains('Test-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath')) 'account menu retains quota; tray exclusively owns program settings and persisted update preference'
Check ($rw.Contains('($script:updateInstallRequested -or') -and
 $rw.Contains('(-not $SkipUpdate -and (Test-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath))') -and
 -not $rw.Contains('if ($OwnerGui) { Start-RuntimeInitialization')) 'startup opt-out never suppresses explicit update click or enables RC1 blocked installer'
$gui=[IO.File]::ReadAllText((Join-Path $root 'Source\rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
Check ($source.Contains('new RdcOwnerTrayMenu(HandleTrayMenuAction)') -and
 $source.Contains('trayMenu.Menu.Opening+=(s,e)=>RefreshTrayMenu()') -and
 $source.Contains('tray.ContextMenuStrip=trayMenu.Menu') -and
 -not $source.Contains('trayStatusItem')) 'actual Host installs grouped menu and removes old status label'
Check ($source.Contains('BeginManagedAccountSwitch()') -and
 $source.Contains('StopManagedRemote();StartManagedRemote();') -and
 $source.Contains('if(!managedMode||observedMode') -and
 $source.Contains('ConfirmTrayAction(prompt,') -and
 ($source.Contains('dialog.AcceptButton=no;dialog.CancelButton=no;') -and $source.Contains('return dialog.ShowDialog()==DialogResult.Yes;'))) 'direct tray Remote actions reuse guarded owned Job methods with No-default confirmations'
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
