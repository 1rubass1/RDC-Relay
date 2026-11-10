# G113 — exercise real Owner Stop and Help WinForms dialogs from AST.
# Fake controls only. Never start/stop/logout Remote, Host or browser.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($errors.Count -eq 0) 'production GUI source parses'
foreach($name in @('New-RdcOwnerStopDialog','Show-RdcOwnerStopConfirmation',
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

$content='RDC Relay 1.6.0 RC1'+[Environment]::NewLine+[Environment]::NewLine+
 ('Текст справки, доступный для прокрутки. ' * 55)
$help=New-RdcOwnerHelpDialog $content
try{
 $layout=@($help.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 $header=$layout.GetControlFromPosition(0,0)
 $body=$layout.GetControlFromPosition(0,1)
 $buttons=$layout.GetControlFromPosition(0,2)
 $close=@($buttons.Controls|Where-Object{$_.Name -ceq 'rc1-help-close'})|Select-Object -First 1
 Check ($help.Name -ceq 'rc1-help-dialog' -and
  $help.Text -ceq 'RDC Relay — справка' -and
  $help.FormBorderStyle -eq [Windows.Forms.FormBorderStyle]::FixedDialog -and
  $help.StartPosition -eq [Windows.Forms.FormStartPosition]::CenterParent -and
  -not $help.ShowInTaskbar) 'Help has matching modal title and fixed dialog container'
 Check ($help.Font.Name -ceq $stop.Font.Name -and
  $help.BackColor.ToArgb() -eq ([Drawing.Color]::FromArgb(29,32,36)).ToArgb() -and
  $help.ForeColor.ToArgb() -eq ([Drawing.Color]::Gainsboro).ToArgb()) 'Help uses Account Switch dark colors and font'
 Check ($header.Text -ceq 'Справка / О программе' -and
  $header.Font.Bold -and $layout.RowCount -eq 3) 'Help has clear header, reading area and footer'
 Check ($body -is [Windows.Forms.RichTextBox] -and
  $body.Text -ceq $content -and $body.ReadOnly -and $body.WordWrap -and
  $body.ScrollBars -eq [Windows.Forms.RichTextBoxScrollBars]::Vertical -and
  $body.Dock -eq [Windows.Forms.DockStyle]::Fill -and
  $body.BorderStyle -eq [Windows.Forms.BorderStyle]::None) 'Help preserves all content in scrollable read-only text'
 Check ($buttons.Controls.Count -eq 1 -and
  $close.Text -ceq 'Закрыть' -and $close.Size.Width -eq 96 -and
  $close.Size.Height -eq 34 -and
  $help.AcceptButton -eq $close -and $help.CancelButton -eq $close) 'Help footer uses same account-button styling with Enter/Esc close'
 $help.PerformLayout();$layout.PerformLayout()
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
$helpHandler=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text.Contains('Show-RdcOwnerHelp $helpText') -and
 $n.Extent.Text.Contains('$helpText =')
},$true))|Select-Object -First 1
Check ($null -ne $helpHandler) 'Help menu uses new Owner modal'
if($helpHandler){
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
 $helpClick=& ([scriptblock]::Create($helpHandler.Extent.Text))
 & $helpClick
  Check ($script:capturedHelp.Contains('Host запускает Desktop Commander Remote 0.2.52.') -and
   $script:capturedHelp.Contains('PID Remote: —')) 'existing managed-Host Help content and diagnostics preserved'
}
Write-Output ('RC1_OWNER_STOP_HELP_DIALOGS_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0