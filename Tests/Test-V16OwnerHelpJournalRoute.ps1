# G121: Help icon next to title -> direct About -> real retained Owner journal.
# AST-driven real WinForms controls and click; no installed app, Host or Remote.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
$raw=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
Check ($errors.Count -eq 0) 'production GUI source parses'
Check ($raw.Contains('$helpButton = New-Object Windows.Forms.Button') -and
 $raw.Contains('$helpButton.Image=([Drawing.SystemIcons]::Question).ToBitmap()') -and
 $raw.Contains('$helpButton.AccessibleName='+ "'Справка / О программе'") -and
 $raw.Contains('$top.Controls.Add($titleHost,1,0)') -and
 $raw.Contains('if(-not $OwnerGui){[void]$titleHost.Controls.Add($helpButton)}') -and
 $raw.Contains('$bottom.Controls.Add($helpButton,2,0)') -and
 -not $raw.Contains('$actions.Controls.Add($helpButton)')) 'native blue Help icon is in owner footer, not title or Stop/Account actions'
Check (-not $raw.Contains('$helpMenu =') -and
 -not $raw.Contains('$helpMenu.Show(') -and
 -not $raw.Contains('$openLogItem.Add_Click(') -and
 -not $raw.Contains('$aboutItem.Add_Click(')) 'superseded Help context menu and invisible-focus journal action removed'
Check ($raw.Contains('$helpButton.FlatStyle=[Windows.Forms.FlatStyle]::Flat') -and
 $raw.Contains('$helpButton.FlatAppearance.BorderSize=0') -and
 $raw.Contains('$helpButton.FlatAppearance.MouseOverBackColor=$helpButton.BackColor') -and
 $raw.Contains('$helpButton.FlatAppearance.MouseDownBackColor=$helpButton.BackColor') -and
 $raw.Contains('$helpButton.UseVisualStyleBackColor=$false')) 'Help stays borderless with no hover or pressed background color'
Check ($raw.Contains('$helpButton.TabStop = $true') -and
 $raw.Contains('$helpButton.AccessibleRole=[Windows.Forms.AccessibleRole]::PushButton')) 'Help retains keyboard Tab access and accessible button role'
$direct=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text -match '(?s)^\{\s*try \{ Show-RdcAbout \}\s*finally \{ \$form\.ActiveControl=\$null \}\s*\}$'
},$true))
Check ($direct.Count -eq 1 -and
 $raw.Contains('$helpButton.Add_Click({') -and
 -not $raw.Contains('$helpMenu =')) 'Help click directly opens About without an intermediate menu'
Check (-not $raw.Contains('$helpButton.Add_MouseDown({') -and
 $raw.Contains('Do not change focus during MouseDown: WinForms may then suppress the Click.')) 'no mouse-down focus manipulation can suppress native button click'
if($direct.Count -eq 1) {
 $script:aboutClicks=0
 function Show-RdcAbout {$script:aboutClicks++}
 $form=New-Object Windows.Forms.Form
 $helpButton=New-Object Windows.Forms.Button
 $form.ShowInTaskbar=$false
 $form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
 $form.Location=[Drawing.Point]::new(-10000,-10000)
 $form.Size=[Drawing.Size]::new(170,100)
 $helpButton.Location=[Drawing.Point]::new(10,10)
 $helpButton.Size=[Drawing.Size]::new(32,32)
 [void]$form.Controls.Add($helpButton)
 try {
  $click=& ([scriptblock]::Create($direct[0].Extent.Text))
  $helpButton.Add_Click($click)
  $form.Show()
  $form.ActiveControl=$helpButton
  $helpButton.PerformClick()
  Check ($script:aboutClicks -eq 1 -and $form.ActiveControl -eq $null) 'actual WinForms PerformClick opens About and releases lingering focus'
  # Dispatch button-local mouse messages to its own isolated, off-screen HWND;
  # no system cursor, installed GUI, tray, or Remote is touched.
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RdcHelpButtonMouseTest {
 [DllImport("user32.dll",CharSet=CharSet.Auto)]
 public static extern IntPtr SendMessage(IntPtr hWnd,uint msg,IntPtr wParam,IntPtr lParam);
}
'@
  $form.ActiveControl=$helpButton
  $localPoint=[IntPtr]::new((6 -shl 16) -bor 6)
  [void][RdcHelpButtonMouseTest]::SendMessage($helpButton.Handle,0x0201,[IntPtr]::new(1),$localPoint)
  [void][RdcHelpButtonMouseTest]::SendMessage($helpButton.Handle,0x0202,[IntPtr]::Zero,$localPoint)
  [Windows.Forms.Application]::DoEvents()
  Check ($script:aboutClicks -eq 2 -and $form.ActiveControl -eq $null) 'native WM_LBUTTONDOWN/UP opens About exactly once, without residual focus'
 }finally{$form.Close();$form.Dispose()}
}
foreach($name in @('Get-RdcOwnerJournalText','New-RdcOwnerJournalDialog',
 'Show-RdcOwnerJournal','New-RdcOwnerHelpDialog')){
 $fn=$ast.Find({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
  $n.Name -ceq $name
 },$true)
 if(-not $fn){throw ('G121_PRODUCTION_FUNCTION_MISSING '+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
$script:ownerTextFontFamily='Consolas'
$script:eventBlocks=New-Object System.Collections.ArrayList
$script:currentEvent=''
Check ((Get-RdcOwnerJournalText) -ceq 'Журнал пока пуст.') 'empty event history explicitly shows empty journal, never a blank window'
for($i=1;$i -le 12;$i++){
 [void]$script:eventBlocks.Add(('000{0:D3} │ Событие {0}' -f $i))
}
$script:currentEvent='000013 │ Текущая операция'
$snapshot=Get-RdcOwnerJournalText
Check ($snapshot.Contains('000001 │ Событие 1') -and
 $snapshot.Contains('000012 │ Событие 12') -and
 $snapshot.Contains('000013 │ Текущая операция') -and
 @($snapshot -split [Environment]::NewLine).Count -ge 13) 'journal snapshot contains all retained events and active event, not last viewport-size six'
Check ($raw.Contains('while ($script:eventBlocks.Count -gt $retained)') -and
 $raw.Contains('$retained=if($OwnerGui){64}else{6}') -and
 -not $raw.Contains('Start-Process -FilePath $notepad -ArgumentList')) 'Owner journal uses existing bounded Host event history without reading raw logs or opening Notepad'
$journal=New-RdcOwnerJournalDialog $snapshot
try{
 Check ($journal.Name -ceq 'rc1-journal-dialog' -and
  $journal.Text -ceq 'RDC Relay — журнал' -and
  $journal.Text -notmatch 'RC1|v1|1\.6' -and
  $journal.StartPosition -eq [Windows.Forms.FormStartPosition]::CenterParent -and
  -not $journal.ShowInTaskbar) 'real journal opens in dedicated, version-free modal window'
 $layout=@($journal.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $heading=$layout.GetControlFromPosition(0,0)
 $body=$layout.GetControlFromPosition(0,1)
 $footer=$layout.GetControlFromPosition(0,2)
 $close=@($footer.Controls|Where-Object{$_.Name -ceq 'rc1-journal-close'})|Select-Object -First 1
 Check ($heading.Text -ceq 'Журнал' -and $heading.Font.Bold -and
  $body.Text -ceq $snapshot -and
  $body.Name -ceq 'rc1-journal-content') 'journal dialog actually displays entire captured event snapshot'
 Check ($body.ReadOnly -and
  -not $body.WordWrap -and
  -not $body.DetectUrls -and
  $body.ScrollBars -eq [Windows.Forms.RichTextBoxScrollBars]::Both -and
  $body.Dock -eq [Windows.Forms.DockStyle]::Fill) 'journal is read-only, scrollable both directions and disables auto-open URLs'
 Check ($body.BackColor.ToArgb() -eq $journal.BackColor.ToArgb() -and
  $body.ForeColor.ToArgb() -eq $journal.ForeColor.ToArgb() -and
  $close.Text -ceq 'Закрыть' -and
  $journal.AcceptButton -eq $close -and
  $journal.CancelButton -eq $close) 'journal follows dark Help styling with keyboard dismiss'
 $journal.PerformLayout();$layout.PerformLayout()
 Check ($body.ClientSize.Width -gt 320 -and $body.ClientSize.Height -gt 150 -and
  $close.Right -le $footer.ClientSize.Width -and
  $close.Bottom -le $footer.ClientSize.Height) 'actual journal modal content and Close footer fit without clipping'
}finally{$journal.Dispose()}
$help=New-RdcOwnerHelpDialog 'Пример справки'
try {
 $layout=@($help.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $buttons=$layout.GetControlFromPosition(0,2)
 $show=$buttons.GetControlFromPosition(0,0)
 $close=$buttons.GetControlFromPosition(1,0)
 Check ($show.Name -ceq 'rc1-help-show-journal' -and
  $show.Text -ceq 'Показать журнал' -and
  $show.Width -eq 160 -and
  $close.Text -ceq 'Закрыть' -and
  $show.Left -lt $close.Left) 'actual Help footer has Show Journal on left and Close on right'
 $script:journalClicks=0
 $script:journalParent=$null
 function Show-RdcOwnerJournal([Windows.Forms.Form]$parent){
  $script:journalClicks++
  $script:journalParent=$parent
 }
 $onClick=$show.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
 [void]$onClick.Invoke($show,[object[]]@([EventArgs]::Empty))
 Check ($script:journalClicks -eq 1 -and
  [object]::ReferenceEquals($script:journalParent,$help)) 'real Show Journal control click opens journal with Help as modal parent, never focuses hidden main pane'
}finally{$help.Dispose()}
$showFn=$ast.Find({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -ceq 'Show-RdcOwnerJournal'
},$true)
Check ($showFn.Extent.Text.Contains('Get-RdcOwnerJournalText') -and
 $showFn.Extent.Text.Contains('New-RdcOwnerJournalDialog $snapshot') -and
 $showFn.Extent.Text.Contains('$journal.ShowDialog($parent)') -and
 $showFn.Extent.Text.Contains('$journal.Dispose()')) 'actual journal command creates visible nested modal from safe history and disposes it'
# G122 postmortem: the G121 Help context-menu item was removed, but its
# old OwnerGui capability writes still caused an early startup exception.
$ownerPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\rc1-owner-gui.ps1'
$ownerSource=[IO.File]::ReadAllText($ownerPath,[Text.Encoding]::UTF8)
$parsedTokens=$null;$ownerParseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile(
 $ownerPath,[ref]$parsedTokens,[ref]$ownerParseErrors)
Check ($ownerParseErrors.Count -eq 0 -and
 -not ([regex]::IsMatch($ownerSource,'(?m)^\s*\$openLogItem\s*(?:\.|\[|=)'))) 'OwnerGui never dereferences the removed G121 Help menu item'
Check ($ownerSource.IndexOf('$initialCapabilities=$handshake.payload.capabilities',
 [StringComparison]::Ordinal) -ge 0 -and
 $ownerSource.IndexOf('$initialCapabilities=$handshake.payload.capabilities',
 [StringComparison]::Ordinal) -lt
 $ownerSource.IndexOf('$script:ownerJournalAllowed=[bool]$initialCapabilities.sanitizedJournal',
 [StringComparison]::Ordinal) -and
 $ownerSource.Contains('$script:ownerJournalAllowed=[bool]$snapshot.capabilities.sanitizedJournal') -and
 $raw.Contains('$showJournal.Enabled=(-not $OwnerGui) -or [bool]$script:ownerJournalAllowed')) 'Host-sanctioned journal capability binds to the new About button at startup and refresh'
$OwnerGui=$true
$script:ownerJournalAllowed=$false
$restricted=New-RdcOwnerHelpDialog 'Test authenticated capability disabled'
try{
 $parent=@($restricted.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $journalButton=$parent.GetControlFromPosition(0,2).GetControlFromPosition(0,0)
 Check (-not $journalButton.Enabled) 'sanitized journal disabled when Owner capability is denied'
}finally{$restricted.Dispose()}
$script:ownerJournalAllowed=$true
$allowed=New-RdcOwnerHelpDialog 'Test authenticated capability enabled'
try{
 $parent=@($allowed.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $journalButton=$parent.GetControlFromPosition(0,2).GetControlFromPosition(0,0)
 Check ($journalButton.Enabled) 'sanitized journal enabled only when Owner capability allows'
}finally{$allowed.Dispose()}
# Owner-only journal is now a separate diagnostic view rather than a
# larger copy of the compact six-line activity pane. The 1.5 legacy fallback
# above must continue displaying its original eventBlocks unchanged.
. $ownerPath
$OwnerGui=$true
$script:eventBlocks=New-Object System.Collections.ArrayList
[void]$script:eventBlocks.Add('LOWER_PANE_ONLY_UNRELATED')
$script:currentEvent=''
$script:ownerDetailedJournal=New-Object 'System.Collections.Generic.List[string]'
$script:ownerRecentDiagnostics=@(
 'Managed mode initialized','Managed state: Ready',
 'password=SHOULD_NOT_DISPLAY','C:\\Private\\secret.txt')
$script:ownerJournalRemoteState='Ready'
$script:ownerJournalRemotePid=17531
$script:ownerJournalOwnership='Owned'
$script:ownerJournalToolActivity='working'
$script:ownerJournalLastSnapshotUtc=[DateTime]::UtcNow
for($i=1;$i -le 540;$i++){
 Add-Rc1OwnerDetailedEvent 'Remote' ('{0:D6} │ 🔧 Чтение файла → sample.md' -f $i)
}
Check ($script:ownerDetailedJournal.Count -eq 512 -and
 $script:ownerDetailedJournal[0].Contains('000029') -and
 $script:ownerDetailedJournal[511].Contains('000540')) 'full journal independently retains last 512 sanitized events, rather than compact 64'
Add-Rc1OwnerDetailedEvent 'Unknown' 'INJECTED_SOURCE'
Add-Rc1OwnerDetailedEvent 'Remote' 'password=TOP_SECRET'
Add-Rc1OwnerDetailedEvent 'Remote' 'C:\\Private\\secret.txt'
Check ($script:ownerDetailedJournal.Count -eq 512 -and
 -not (@($script:ownerDetailedJournal) -join ' ').Contains('TOP_SECRET')) 'journal rejects untrusted origins, raw paths and sensitive arguments'
$snapshot=Get-RdcOwnerJournalText
Check ($snapshot.Contains('подробный диагностический журнал') -and
 $snapshot.Contains('ДИАГНОСТИКА HOST') -and
 $snapshot.Contains('Managed state: Ready') -and
 $snapshot.Contains('Процесс Remote: PID 17531') -and
 $snapshot.Contains('Remote: Ready | Режим: Owned | Активность: working')) 'full journal shows actual sanitized Host diagnostics, connection state and Remote PID'
Check ($snapshot.Contains('000540') -and $snapshot.Contains('000029') -and
 -not $snapshot.Contains('000001 │ 🔧') -and
 -not $snapshot.Contains('LOWER_PANE_ONLY_UNRELATED')) 'full journal uses separate retained history, not lower-pane eventBlocks'
Check (-not $snapshot.Contains('password=') -and
 -not $snapshot.Contains('SHOULD_NOT_DISPLAY') -and
 -not $snapshot.Contains('C:\\Private') -and
 -not $snapshot.Contains('TOP_SECRET') -and
 $snapshot.Contains('время выполнения команды') ) 'full diagnostic journal filters private details and labels GUI receipt timestamps honestly'
$fullDialog=New-RdcOwnerJournalDialog $snapshot
try{
 $inner=@($fullDialog.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $journalBody=$inner.GetControlFromPosition(0,1)
 Check ($journalBody.Text -ceq $snapshot -and
  $journalBody.TextLength -gt 18000 -and $journalBody.ReadOnly -and
  -not $journalBody.WordWrap) 'real journal dialog displays all retained diagnostic text without viewport clipping'
}finally{$fullDialog.Dispose()}
$OwnerGui=$false
Write-Output ('RC1_HELP_JOURNAL_ROUTE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0