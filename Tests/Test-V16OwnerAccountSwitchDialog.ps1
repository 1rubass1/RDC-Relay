# G108: verify real Owner account-switch warning dialog and cancel/yes control.
# Only disposable WinForms controls; never invoke Remote, Host or browser.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
$source=[IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$condition,[string]$label){
 if($condition){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($errors.Count -eq 0) 'real GUI source parses on Windows PowerShell 5.1'
foreach($name in @('New-RdcOwnerAccountSwitchDialog','Show-RdcOwnerAccountSwitchConfirmation')){
 $def=$ast.Find({param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
 },$true)
 if(-not $def){throw ('MISSING_PRODUCTION_ACCOUNT_DIALOG '+$name)}
 . ([scriptblock]::Create($def.Extent.Text))
}
$dialog=New-RdcOwnerAccountSwitchDialog
$exact=@(
 'Сначала откройте сайт Desktop Commander и войдите в аккаунт, на который хотите переключиться.',
 'Смена аккаунта разорвёт текущее соединение и отзовёт авторизацию этого устройства.',
 'После выхода из аккаунта RDC Relay запустит новый Remote и начнёт процедуру авторизации устройства.',
 'Продолжить смену аккаунта?'
)
try{
 Check ($dialog.Text -ceq 'Смена аккаунта Desktop Commander') 'dialog title matches approved owner wording'
 Check ($dialog.FormBorderStyle -eq [Windows.Forms.FormBorderStyle]::FixedDialog -and
  $dialog.StartPosition -eq [Windows.Forms.FormStartPosition]::CenterParent -and
  -not $dialog.ShowInTaskbar -and -not $dialog.MaximizeBox) 'modal dialog fixed and centers over owner without taskbar duplicate'
 $layout=@($dialog.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})|Select-Object -First 1
 Check ($null -ne $layout -and $layout.RowCount -eq 6 -and
  $layout.ColumnCount -eq 1) 'paragraphs retain intended vertical reading order'
 $warningRow=$layout.GetControlFromPosition(0,0)
 $icon=$warningRow.GetControlFromPosition(0,0)
 $labels=@($warningRow.GetControlFromPosition(1,0))
 for($i=1;$i -lt 4;$i++){
  $labels+=@($layout.GetControlFromPosition(0,$i))
 }
 Check ($warningRow.Name -ceq 'rc1-account-switch-warning-row' -and
  $warningRow.ColumnCount -eq 2 -and $icon.Name -ceq 'rc1-account-switch-warning-icon' -and
  $icon.Image.Width -eq 32 -and $icon.Image.Height -eq 32 -and
  -not $icon.TabStop) 'actual standard Windows warning triangle sits in first row only'
 $same=$true
 for($i=0;$i -lt 4;$i++){
  if($labels[$i].Text -cne $exact[$i]){$same=$false}
 }
 Check $same 'four approved phrases exactly match owner edits, without extra headings'
 Check ($labels[0].Font.Bold -and
  -not $labels[1].Font.Bold -and -not $labels[2].Font.Bold -and
  -not $labels[3].Font.Bold) 'only opening website login instruction is bold'
 Check ($dialog.BackColor.ToArgb() -eq ([Drawing.Color]::FromArgb(29,32,36)).ToArgb() -and
  $dialog.ForeColor.ToArgb() -eq ([Drawing.Color]::Gainsboro).ToArgb() -and
  $dialog.Font.Name -ceq 'Segoe UI') 'dialog follows existing Owner GUI dark colors and font'
 Check (($labels|Where-Object{$_.Text -match 'удалённое|Внимание|Перед началом|ChatGPT'}).Count -eq 0) 'removed old third block, remote adjective and unwanted headings'
 $bottom=$layout.GetControlFromPosition(0,5)
 $site=$bottom.GetControlFromPosition(0,0)
 $right=$bottom.GetControlFromPosition(1,0)
 $buttons=@($right.Controls)
 $no=@($buttons|Where-Object{$_.Name -ceq 'rc1-account-switch-no'})|Select-Object -First 1
 $yes=@($buttons|Where-Object{$_.Name -ceq 'rc1-account-switch-yes'})|Select-Object -First 1
 Check ($bottom.Name -ceq 'rc1-account-switch-bottom-row' -and
  $bottom.ColumnCount -eq 2 -and $site.Name -ceq 'rc1-account-switch-signout-website' -and
  $site.Text -ceq 'Выйти из аккаунта' -and $site.Width -eq (2 * $no.Width) -and
  $site.DialogResult -eq [Windows.Forms.DialogResult]::None) 'web account helper is double-width in left half and never accepts switch'
 Check ($buttons.Count -eq 2 -and $no.Text -ceq 'Нет' -and
  $yes.Text -ceq 'Да') 'explicit yes/no controls and no additional action'
 Check ($no.DialogResult -eq [Windows.Forms.DialogResult]::No -and
  $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes -and
  $dialog.AcceptButton -eq $no -and $dialog.CancelButton -eq $no) 'Enter and Escape default to safe No, Yes only by explicit choice'
 $dialog.PerformLayout()
 $layout.PerformLayout()
 $warningRow.PerformLayout()
 $bottom.PerformLayout()
 $right.PerformLayout()
 $layoutOk=($labels|Where-Object{$_.Height -le 0}).Count -eq 0
 for($i=1;$i -lt 4;$i++){
  if($labels[$i].Right -gt $layout.ClientSize.Width -or
   ($i -gt 1 -and $labels[$i].Top -le $labels[$i-1].Top)){$layoutOk=$false}
 }
 Check $layoutOk 'measured paragraphs remain inside client bounds'
 $firstX=$warningRow.Left+$labels[0].Left
 $otherX=$labels[1].Left
 Check ($firstX -gt ($otherX+32) -and $icon.Left -lt $labels[0].Left -and
   $labels[1].Left -eq $labels[2].Left -and $labels[2].Left -eq $labels[3].Left) 'only bold paragraph indented; remaining three start at same original left edge'
 $siteLeft=$bottom.Left+$site.Left
 $noRight=$bottom.Left+$right.Left+$no.Right
 $leftGap=$siteLeft
 $rightGap=$layout.ClientSize.Width-$noRight
 Check ([Math]::Abs($leftGap-$rightGap) -le 3 -and
  $site.Top -ge 0 -and $no.Top -ge 0) ('site and No buttons have symmetric row edge insets: left='+$leftGap+' right='+$rightGap)
 Check ($site.Top -eq ($right.Top+$no.Top) -and
  $site.Bottom -le $bottom.Height -and
  $no.Bottom -le $right.Height) 'all three buttons share exact baseline with no clipping'
 $script:siteClicks=0
 $script:openedSite=''
 function Start-Process {
  [CmdletBinding()]
  param([string]$FilePath)
  $script:siteClicks++
  $script:openedSite=$FilePath
 }
 try{
  # An unshown WinForms Button suppresses PerformClick (CanSelect=false).
  # Raise its genuine protected OnClick event, with the browser mocked.
  $onClick=[Windows.Forms.Button].GetMethod('OnClick',
   [Reflection.BindingFlags]'Instance,NonPublic')
  [void]$onClick.Invoke($site,[object[]]@([EventArgs]::Empty))
  Check ($script:siteClicks -eq 1 -and
    $script:openedSite -ceq 'https://mcp.desktopcommander.app/' -and
    $dialog.DialogResult -eq [Windows.Forms.DialogResult]::None) 'site button opens only verified official dashboard and leaves dialog awaiting Yes/No'
 }finally{Remove-Item function:Start-Process -ErrorAction SilentlyContinue}
}finally{$dialog.Dispose()}
$handlers=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $node.Extent.Text.Contains("Show-RdcOwnerAccountSwitchConfirmation")
},$true))
# Prefer the owner click handler containing SWITCH_ACCOUNT, not the
# production function body which is itself another AST scope.
$handler=@($handlers|Where-Object{$_.Extent.Text.Contains('$script:ownerQueuedAction=') -and
 $_.Extent.Text.Contains("SWITCH_ACCOUNT")})|Select-Object -First 1
Check ($null -ne $handler) 'existing Owner account click route contains the new modal'
if($handler){
 $text=$handler.Extent.Text
 Check ($text.Contains('if (-not $script:ownerManagedMode -or -not $script:ownerCanSwitchAccount) { return }') -and
  $text.Contains('if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }') -and
  $text.Contains('$script:ownerQueuedAction='+"'SWITCH_ACCOUNT'")) 'managed Host capability gate and explicit Yes remain mandatory'
 Check (-not $text.Contains('[Windows.Forms.MessageBox]::Show($message') -and
  -not $text.Contains('Войдите в тот же аккаунт')) 'old Owner MessageBox and ChatGPT instruction removed'
 $click=& ([scriptblock]::Create($handler.Extent.Text))
 $OwnerGui=$true
 $script:ownerManagedMode=$true
 $script:ownerCanSwitchAccount=$true
 $script:ownerQueuedAction=''
 $script:mockDecision=[Windows.Forms.DialogResult]::No
 $script:confirmationCount=0
 function Show-RdcOwnerAccountSwitchConfirmation {
  $script:confirmationCount++
  return $script:mockDecision
 }
 function Set-State {param([string]$name,[string]$description,[Drawing.Color]$color)
  $script:stateCalls++
 }
 $script:stateCalls=0
 $item=New-Object Windows.Forms.ToolStripMenuItem('Switch account')
 try{
  $switchAccountItem=$item
  $item.Add_Click($click)
  $item.PerformClick()
  Check ($script:ownerQueuedAction -ceq '' -and
   $script:ownerCanSwitchAccount -and $item.Enabled -and
   $script:confirmationCount -eq 1 -and $script:stateCalls -eq 0) 'No decision never queues logout or changes capabilities'
  $script:mockDecision=[Windows.Forms.DialogResult]::Yes
  $item.PerformClick()
  Check ($script:ownerQueuedAction -ceq 'SWITCH_ACCOUNT' -and
   -not $script:ownerCanSwitchAccount -and -not $item.Enabled -and
   $script:confirmationCount -eq 2 -and $script:stateCalls -eq 1) 'explicit Yes queues precisely existing authenticated Host action'
  $item.Enabled=$true;$script:ownerCanSwitchAccount=$false
  $item.PerformClick()
  Check ($script:confirmationCount -eq 2) 'Host capability denial prevents presenting confirmation'
 }finally{$item.Dispose()}
}
Write-Output ('RC1_OWNER_ACCOUNT_SWITCH_DIALOG_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0