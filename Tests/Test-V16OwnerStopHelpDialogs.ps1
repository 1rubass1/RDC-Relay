# G113/G114 — exercise real Owner Stop, Reconnect and Help dialogs from AST.
# Fake controls only. Never start/stop/logout Remote, Host or browser.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
. (Join-Path $PSScriptRoot 'Import-V16OwnerModalButtonType.ps1') -SourcePath $src
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($errors.Count -eq 0) 'production GUI source parses'
foreach($name in @('New-RdcOwnerAccountSwitchDialog',
 'New-RdcOwnerStopDialog','Show-RdcOwnerStopConfirmation',
 'New-RdcOwnerReconnectDialog','Show-RdcOwnerReconnectConfirmation',
 'New-RdcOwnerHelpDialog','Show-RdcOwnerHelp')){
 $fn=$ast.Find({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
  $n.Name -ceq $name
 },$true)
 if(-not $fn){throw ('MISSING_PRODUCTION_OWNER_DIALOG '+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
$stop=New-RdcOwnerStopDialog
try{
 Check ($stop.Name -ceq 'rc1-stop-remote-confirmation' -and
  $stop.Text -ceq 'Остановка Remote' -and
  $stop.FormBorderStyle -eq [Windows.Forms.FormBorderStyle]::FixedDialog -and
  $stop.StartPosition -eq [Windows.Forms.FormStartPosition]::CenterParent -and
  -not $stop.ShowInTaskbar -and -not $stop.MaximizeBox) 'Owner Stop has dedicated compact modal title, centered and fixed'
 Check ($stop.Font.Name -ceq 'Segoe UI' -and
  $stop.BackColor.ToArgb() -eq ([Drawing.Color]::FromArgb(29,32,36)).ToArgb() -and
  $stop.ForeColor.ToArgb() -eq ([Drawing.Color]::Gainsboro).ToArgb()) 'Stop matches account confirmation dark theme and Segoe UI'
 $layout=@($stop.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $row=$layout.GetControlFromPosition(0,0)
 $warning=$row.GetControlFromPosition(0,0)
 $message=$row.GetControlFromPosition(1,0)
 $buttons=$layout.GetControlFromPosition(0,1)
 $no=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-stop-remote-no'})|Select-Object -First 1
 $yes=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-stop-remote-yes'})|Select-Object -First 1
 Check ($no -is [RdcModalButton] -and $yes -is [RdcModalButton]) 'Stop actions share main rounded button style'
 Check ($layout.RowCount -eq 2 -and $row.ColumnCount -eq 2 -and
  $warning.Image.Width -eq 32 -and $warning.Image.Height -eq 32 -and
  -not $warning.TabStop) 'compact layout uses account-style standard warning icon'
 # Check the actual named content label, not the form caption.
 Check ($message.Text -ceq 'Остановить Remote?' -and $message.Font.Bold -and
  $message.Name -ceq 'rc1-stop-remote-question' -and
  @($stop.Controls|Where-Object{$_ -is [Windows.Forms.Label]}).Count -eq 0) 'body contains only the exact bold user-approved stop question'
 Check ($buttons.Controls.Count -eq 2 -and $no.Text -ceq 'Нет' -and
  $yes.Text -ceq 'Да' -and $no.Width -eq 96 -and $yes.Width -eq 96 -and
  $no.Height -eq 34 -and $yes.Height -eq 34) 'same Yes/No dimensions and ordering as Account Switch'
 Check ($no.DialogResult -eq [Windows.Forms.DialogResult]::No -and
  $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes -and
  $stop.AcceptButton -eq $no -and $stop.CancelButton -eq $no -and
  $stop.ActiveControl -eq $no) 'Stop default Enter/Escape is safe No, explicit Yes required'
 $stop.PerformLayout();$layout.PerformLayout();$row.PerformLayout();$buttons.PerformLayout()
 Check ($message.Width -gt 0 -and $message.Height -gt 0 -and
  $message.Right -le $row.ClientSize.Width -and
  $no.Bottom -le $buttons.ClientSize.Height -and
  $yes.Bottom -le $buttons.ClientSize.Height) 'Stop question and action buttons fit inside dialog'
}finally{$stop.Dispose()}

$reconnect=New-RdcOwnerReconnectDialog
try {
 $layout=@($reconnect.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $row=$layout.GetControlFromPosition(0,0)
 $warning=$row.GetControlFromPosition(0,0)
 $question=$row.GetControlFromPosition(1,0)
 $buttons=$layout.GetControlFromPosition(0,1)
 $no=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-reconnect-remote-no'})|Select-Object -First 1
 $yes=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-reconnect-remote-yes'})|Select-Object -First 1
 Check ($no -is [RdcModalButton] -and $yes -is [RdcModalButton]) 'Reconnect actions share main rounded button style'
 Check ($reconnect.Name -ceq 'rc1-reconnect-remote-confirmation' -and
  $reconnect.Text -ceq 'Переподключение Remote' -and
  $reconnect.ClientSize.Width -eq 480 -and $reconnect.ClientSize.Height -eq 168 -and
  $reconnect.FormBorderStyle -eq [Windows.Forms.FormBorderStyle]::FixedDialog) 'Reconnect has same compact modal geometry and dedicated title'
 Check ($question.Name -ceq 'rc1-reconnect-remote-question' -and
  $question.Text -ceq 'Переподключить Remote?' -and $question.Font.Bold -and
  $reconnect.Controls.Find('rc1-stop-remote-question',$true).Count -eq 0) 'Reconnect body contains only exact user-approved question'
 $expectedQuestion=([Drawing.SystemIcons]::Question).ToBitmap()
 $expectedWarning=([Drawing.SystemIcons]::Warning).ToBitmap()
 try {
  # Compare actual pixel-color signatures to ensure the icon was not left
  # as the old standard blue Question system icon.
  Check ($warning.Name -ceq 'rc1-reconnect-remote-warning-icon' -and
   $warning.Image.Width -eq 32 -and $warning.Image.Height -eq 32 -and
   $warning.AccessibleDescription -ceq 'Стандартный значок предупреждения.' -and
   -not $warning.TabStop -and
   $warning.Image.GetPixel(16,16).ToArgb() -eq $expectedWarning.GetPixel(16,16).ToArgb()) 'Reconnect reuses actual Windows exclamation warning icon, not Question'
 }finally{$expectedQuestion.Dispose();$expectedWarning.Dispose()}
 Check ($reconnect.BackColor.ToArgb() -eq ([Drawing.Color]::FromArgb(29,32,36)).ToArgb() -and
  $reconnect.Font.Name -ceq 'Segoe UI' -and $buttons.Controls.Count -eq 2) 'Reconnect dark palette and buttons match Stop'
 Check ($no.Text -ceq 'Нет' -and $yes.Text -ceq 'Да' -and
  $no.Size.Width -eq 96 -and $yes.Size.Width -eq 96 -and
  $reconnect.AcceptButton -eq $no -and $reconnect.CancelButton -eq $no -and
  $reconnect.ActiveControl -eq $no -and
  $no.DialogResult -eq [Windows.Forms.DialogResult]::No -and
  $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes) 'Reconnect Enter/Escape defaults safely to No, Yes requires explicit action'
 $reconnect.PerformLayout();$layout.PerformLayout();$row.PerformLayout();$buttons.PerformLayout()
 Check ($question.Width -gt 0 -and $question.Height -gt 0 -and
  $question.Right -le $row.ClientSize.Width -and
  $no.Bottom -le $buttons.Height -and $yes.Bottom -le $buttons.Height) 'Reconnect label and action buttons fit without clipping'
}finally{$reconnect.Dispose()}

# Compare against the real Account Switch form, not an arbitrary guessed
# modal target. Both forms use the same fixed dark WinForms design system.
$account=New-RdcOwnerAccountSwitchDialog
try { $accountHeight=$account.ClientSize.Height }
finally { $account.Dispose() }
$brief='RDC Relay 1.6.0 RC1'+[Environment]::NewLine+
 'Краткая справка по программе.'+[Environment]::NewLine+'PID Remote: —'
$shortHelp=New-RdcOwnerHelpDialog $brief
try {
 Check ($shortHelp.ClientSize.Height -ge 220 -and
  $shortHelp.ClientSize.Height -lt $accountHeight) 'short help content opens in proportionally smaller dialog'
 $shortHeight=$shortHelp.ClientSize.Height
}finally{$shortHelp.Dispose()}
$realManaged='RDC Relay 1.6.0 RC1'+[Environment]::NewLine+[Environment]::NewLine+
 'Host запускает Desktop Commander Remote 0.2.52.'+[Environment]::NewLine+[Environment]::NewLine+
 'Закрытие окна закрывает только GUI; Host и Remote продолжают работать.'+[Environment]::NewLine+
 'Повторное открытие через трей восстанавливает состояние и журнал.'+[Environment]::NewLine+
 'Статистику вызовов при необходимости можно подключить повторно в меню «Аккаунт».'+
 [Environment]::NewLine+[Environment]::NewLine+'PID Remote: —'
$managedHelp=New-RdcOwnerHelpDialog $realManaged
try {
 Check ($managedHelp.ClientSize.Height -ge $shortHeight -and
  $managedHelp.ClientSize.Height -le $accountHeight -and
  $managedHelp.ClientSize.Height -lt 480) 'actual managed Host help fits account-style height rather than 480px'
}finally{$managedHelp.Dispose()}
$content='RDC Relay 1.6.0 RC1'+[Environment]::NewLine+[Environment]::NewLine+
 ('Текст справки, доступный для прокрутки. ' * 55)
$help=New-RdcOwnerHelpDialog $content
try{
 $layout=@($help.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $headerRow=$layout.GetControlFromPosition(0,0)
 $helpIcon=$headerRow.GetControlFromPosition(0,0)
 $header=$headerRow.GetControlFromPosition(1,0)
 $body=$layout.GetControlFromPosition(0,1)
 $buttons=$layout.GetControlFromPosition(0,2)
 $close=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-help-close'})|Select-Object -First 1
 $journalButton=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-help-show-journal'})|Select-Object -First 1
 Check ($journalButton -is [RdcModalButton] -and $close -is [RdcModalButton]) 'Help actions use common modal button style'
 Check ($help.Name -ceq 'rc1-help-dialog' -and
  $help.Text -ceq 'RDC Relay — справка' -and
  $help.FormBorderStyle -eq [Windows.Forms.FormBorderStyle]::FixedDialog -and
  $help.StartPosition -eq [Windows.Forms.FormStartPosition]::CenterParent -and
  -not $help.ShowInTaskbar) 'Help has matching modal title and fixed dialog container'
 Check ($help.Font.Name -ceq $stop.Font.Name -and
  $help.BackColor.ToArgb() -eq ([Drawing.Color]::FromArgb(29,32,36)).ToArgb() -and
  $help.ForeColor.ToArgb() -eq ([Drawing.Color]::Gainsboro).ToArgb()) 'Help uses Account Switch dark colors and font'
 Check ($header.Text -ceq 'Справка / О программе' -and
  $header.Font.Bold -and $layout.RowCount -eq 3 -and
  $headerRow.Name -ceq 'rc1-help-heading-row' -and
  $headerRow.ColumnCount -eq 2) 'Help has clear header, reading area and footer'
 Check ($helpIcon.Name -ceq 'rc1-help-question-icon' -and
  $helpIcon.Image.Width -eq 32 -and $helpIcon.Image.Height -eq 32 -and
  $helpIcon.AccessibleDescription -ceq 'Стандартный значок вопроса.' -and
  -not $helpIcon.TabStop) 'Help header has standard circled question-mark icon'
 Check ($body.BackColor.ToArgb() -eq $help.BackColor.ToArgb() -and
  $body.ForeColor.ToArgb() -eq $help.ForeColor.ToArgb()) 'Help content is seamless with dark form background, no contrasting grey panel'
 Check ($help.ClientSize.Height -eq $accountHeight -and
  $help.ClientSize.Width -eq 660) 'long help text caps at actual Account Switch client height and retains wide text column'
 Check ($body -is [Windows.Forms.RichTextBox] -and
  $body.Text -ceq $content -and $body.ReadOnly -and $body.WordWrap -and
  $body.ScrollBars -eq [Windows.Forms.RichTextBoxScrollBars]::Vertical -and
  $body.Dock -eq [Windows.Forms.DockStyle]::Fill -and
  $body.BorderStyle -eq [Windows.Forms.BorderStyle]::None) 'Help preserves all content in scrollable read-only text'
 Check ($buttons -is [Windows.Forms.TableLayoutPanel] -and
  $buttons.ColumnCount -eq 2 -and $buttons.Controls.Count -eq 2 -and
  $journalButton.Text -ceq 'Показать журнал' -and
  $journalButton.Width -eq 160 -and
  $buttons.GetControlFromPosition(0,0) -eq $journalButton -and
  $buttons.GetControlFromPosition(1,0) -eq $close -and
  $close.Text -ceq 'Закрыть' -and $close.Size.Width -eq 96 -and
  $close.Size.Height -eq 34 -and
  $help.AcceptButton -eq $close -and $help.CancelButton -eq $close) 'Help footer has left Show Journal and right default Close'
 $help.PerformLayout();$layout.PerformLayout();$headerRow.PerformLayout();$buttons.PerformLayout()
 Check ($journalButton.Left -lt $close.Left -and
  $journalButton.Right -le $close.Left -and
  $journalButton.Bottom -le $buttons.Height) 'Show Journal is visible at left of footer with no overlap'
 Check ($header.Left -gt $helpIcon.Left+32 -and
  $header.Right -le $headerRow.ClientSize.Width) 'Help heading aligns after native icon without clipping'
 Check ($body.Width -gt 0 -and $body.Height -gt 0 -and
  $body.Right -le $layout.ClientSize.Width -and
  $close.Bottom -le $buttons.Height) 'Help scroll area and footer visible without overlap'
}finally{$help.Dispose()}

$stopHandler=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text.Contains('Show-RdcOwnerStopConfirmation') -and
 $n.Extent.Text.Contains('$script:ownerQueuedAction')
},$true))|Select-Object -First 1
Check ($null -ne $stopHandler) 'real Stop button uses new confirmation'
if($stopHandler){
 $click=& ([scriptblock]::Create($stopHandler.Extent.Text))
 $OwnerGui=$true
 $script:ownerManagedMode=$true
 $script:ownerCanStop=$true
 $script:ownerCanStart=$false
 $script:ownerQueuedAction=''
 $script:decision=[Windows.Forms.DialogResult]::No
 $script:confirmCalls=0
 function Show-RdcOwnerStopConfirmation {
  $script:confirmCalls++
  return $script:decision
 }
 # Direct invocation of production click code avoids WinForms suppressing
 # an event on an unshown Button in this artificial test harness.
 & $click
 Check ($script:ownerQueuedAction -ceq '' -and $script:confirmCalls -eq 1) 'No never queues Remote Stop'
  $script:decision=[Windows.Forms.DialogResult]::Yes
  & $click
  Check ($script:ownerQueuedAction -ceq 'STOP' -and $script:confirmCalls -eq 2) 'Yes queues only existing STOP action'
  $script:ownerQueuedAction=''
  $script:ownerCanStop=$false;$script:ownerCanStart=$false
  & $click
  Check ($script:ownerQueuedAction -ceq '' -and $script:confirmCalls -eq 2) 'missing Host STOP capability bypasses confirmation'
}
$reconnectHandler=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text.Contains('Show-RdcOwnerReconnectConfirmation') -and
 $n.Extent.Text.Contains('$script:ownerQueuedAction')
},$true))|Select-Object -First 1
Check ($null -ne $reconnectHandler) 'real Reconnect menu routes through the new warning confirmation'
if($reconnectHandler){
 $click=& ([scriptblock]::Create($reconnectHandler.Extent.Text))
 $OwnerGui=$true
 $script:ownerManagedMode=$true
 $script:ownerCanReconnect=$true
 $script:ownerQueuedAction=''
 $script:reconnectDecision=[Windows.Forms.DialogResult]::No
 $script:reconnectConfirmCalls=0
 function Show-RdcOwnerReconnectConfirmation {
  $script:reconnectConfirmCalls++
  return $script:reconnectDecision
 }
 & $click
 Check ($script:ownerQueuedAction -ceq '' -and $script:reconnectConfirmCalls -eq 1) 'Reconnect No does not queue Remote or Host actions'
 $script:reconnectDecision=[Windows.Forms.DialogResult]::Yes
 & $click
 Check ($script:ownerQueuedAction -ceq 'RECONNECT' -and
  $script:reconnectConfirmCalls -eq 2) 'Reconnect explicit Yes queues only existing Host RECONNECT action'
 $script:ownerQueuedAction=''
 $script:ownerCanReconnect=$false
 & $click
 Check ($script:ownerQueuedAction -ceq '' -and
  $script:reconnectConfirmCalls -eq 2) 'Reconnect capability denial bypasses confirmation'
 $script:ownerCanReconnect=$true
 $script:ownerManagedMode=$false
 & $click
 Check ($script:ownerQueuedAction -ceq '' -and
  $script:reconnectConfirmCalls -eq 2) 'Reconnect observed mode cannot open confirmation or queue Remote'
}
$helpHandler=$ast.Find({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -ceq 'Show-RdcAbout'
},$true)
Check ($null -ne $helpHandler) 'direct Help action uses the Owner modal'
if($helpHandler){
 . ([scriptblock]::Create($helpHandler.Extent.Text))
 $OwnerGui=$true
 $script:ownerObservedMode=$false
 $script:ownerManagedMode=$true
 $script:ownerRemotePid=0
 $nl=[Environment]::NewLine
 $appVersion='1.6.0 RC1'
 $script:capturedHelp=''
 function Show-RdcOwnerHelp {param([string]$content)
  $script:capturedHelp=$content
  return [Windows.Forms.DialogResult]::OK
 }
 Show-RdcAbout
  Check ($script:capturedHelp.Contains('Host запускает Desktop Commander Remote 0.2.52.') -and
   $script:capturedHelp.Contains('PID Remote: —')) 'existing managed-Host Help content and diagnostics preserved'
}
Write-Output ('RC1_OWNER_STOP_HELP_DIALOGS_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0