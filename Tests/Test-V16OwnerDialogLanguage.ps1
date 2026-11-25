# Production Owner confirmation forms with RU/EN captions; isolated WinForms objects.
# No Host, Remote, browser, named pipe, installed client or preference write.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$sourceRoot=Join-Path $root 'Source'
$sourcePath=Join-Path $sourceRoot 'remote-window.ps1'
. (Join-Path $PSScriptRoot 'Import-V16OwnerModalButtonType.ps1') -SourcePath $sourcePath
Add-Type -Path (Join-Path $sourceRoot 'RdcUiLanguage.cs') -ReferencedAssemblies @(
 'System.dll','System.Core.dll','System.Web.Extensions.dll')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count -ne 0){throw 'OWNER_MODAL_SOURCE_PARSE_ERROR'}
foreach($name in @('Get-RdcOwnerDialogText','New-RdcOwnerStopDialog',
 'New-RdcOwnerReconnectDialog','New-RdcOwnerAccountSwitchDialog')){
 $fn=$ast.Find({param($node)
   $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
   $node.Name -ceq $name},$true)
 if(-not $fn){throw ('MISSING_MODAL_FUNCTION '+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
$OwnerGui=$true
function Get-RdcOwnerUiText([string]$key,[string]$fallback){
 return [RdcUiLanguage]::Text($script:ownerUiTexts,$key,$fallback)
}
$pass=0;$fail=0
function Check([bool]$yes,[string]$why){
 if($yes){$script:pass++;Write-Output ('PASS '+$why)}
 else{$script:fail++;Write-Output ('FAIL '+$why)}
}
foreach($locale in @('ru-RU','en-US')){
 $script:ownerUiTexts=[RdcUiLanguage]::LoadResources($sourceRoot,$locale)
 $en=$locale -ceq 'en-US'
 Check ($script:ownerUiTexts.Count -ge 146) ('loads validated UI resource keys for '+$locale)
 $stop=New-RdcOwnerStopDialog
 try{
  $question=@($stop.Controls.Find('rc1-stop-remote-question',$true))[0]
  $no=@($stop.Controls.Find('rc1-stop-remote-no',$true))[0]
  $yes=@($stop.Controls.Find('rc1-stop-remote-yes',$true))[0]
  Check ($stop.Text -ceq $(if($en){'Stopping Remote'}else{'Остановка Remote'}) -and
   $question.Text -ceq $(if($en){'Stop Remote?'}else{'Остановить Remote?'})) ('Stop title/body localized '+$locale)
  Check ($no.Text -ceq $(if($en){'No'}else{'Нет'}) -and
   $yes.Text -ceq $(if($en){'Yes'}else{'Да'}) -and
   $stop.AcceptButton -eq $no -and $stop.CancelButton -eq $no -and
   $stop.ActiveControl -eq $no) ('Stop Enter/Escape still safe No '+$locale)
  Check ($no.DialogResult -eq [Windows.Forms.DialogResult]::No -and
   $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes) ('Stop action results invariant '+$locale)
  $stop.PerformLayout()
  Check ($question.Width -gt 0 -and $question.Right -le $stop.ClientSize.Width) ('Stop label fits '+$locale)
 }finally{$stop.Dispose()}
 $reconnect=New-RdcOwnerReconnectDialog
 try{
  $question=@($reconnect.Controls.Find('rc1-reconnect-remote-question',$true))[0]
  $no=@($reconnect.Controls.Find('rc1-reconnect-remote-no',$true))[0]
  $yes=@($reconnect.Controls.Find('rc1-reconnect-remote-yes',$true))[0]
  Check ($reconnect.Text -ceq $(if($en){'Reconnecting Remote'}else{'Переподключение Remote'}) -and
   $question.Text -ceq $(if($en){'Reconnect Remote?'}else{'Переподключить Remote?'})) ('Reconnect title/body localized '+$locale)
  Check ($no.Text -ceq $(if($en){'No'}else{'Нет'}) -and
   $yes.Text -ceq $(if($en){'Yes'}else{'Да'}) -and
   $reconnect.AcceptButton -eq $no -and $reconnect.CancelButton -eq $no) ('Reconnect Enter/Escape safe No '+$locale)
  Check ($no.DialogResult -eq [Windows.Forms.DialogResult]::No -and
   $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes) ('Reconnect action results invariant '+$locale)
 }finally{$reconnect.Dispose()}
 $account=New-RdcOwnerAccountSwitchDialog
 try{
  $layout=@($account.Controls|Where-Object{$_ -is [Windows.Forms.TableLayoutPanel]})[0]
  $intro=$layout.GetControlFromPosition(0,0).GetControlFromPosition(1,0)
  $last=$layout.GetControlFromPosition(0,3)
  $site=@($account.Controls.Find('rc1-account-switch-signout-website',$true))[0]
  $no=@($account.Controls.Find('rc1-account-switch-no',$true))[0]
  $yes=@($account.Controls.Find('rc1-account-switch-yes',$true))[0]
  Check ($account.Text -ceq $(if($en){'Switch Desktop Commander account'}else{'Смена аккаунта Desktop Commander'}) -and
    $intro.Text -ceq $(if($en){'First open the Desktop Commander website and sign in to the account you want to switch to.'}else{'Сначала откройте сайт Desktop Commander и войдите в аккаунт, на который хотите переключиться.'})) ('Account title and first paragraph localized '+$locale)
  Check ($last.Text -ceq $(if($en){'Continue switching accounts?'}else{'Продолжить смену аккаунта?'}) -and
   $site.Text -ceq $(if($en){'Sign out'}else{'Выйти из аккаунта'})) ('Account warning and site helper localized '+$locale)
  Check ($no.Text -ceq $(if($en){'No'}else{'Нет'}) -and
    $yes.Text -ceq $(if($en){'Yes'}else{'Да'}) -and
    $account.AcceptButton -eq $no -and $account.CancelButton -eq $no -and
    $site.DialogResult -eq [Windows.Forms.DialogResult]::None) ('Account Enter/Escape and site helper stay non-destructive '+$locale)
  Check ($no.DialogResult -eq [Windows.Forms.DialogResult]::No -and
    $yes.DialogResult -eq [Windows.Forms.DialogResult]::Yes) ('Account Yes only by explicit selection '+$locale)
  $account.PerformLayout();$layout.PerformLayout()
  $firstRight=$intro.Right
  $lastRight=$last.Right
  Check ($intro.Height -gt 0 -and $last.Height -gt 0 -and
    $firstRight -le $layout.ClientSize.Width -and $lastRight -le $layout.ClientSize.Width) ('Account paragraphs fit form width '+$locale)
 }finally{$account.Dispose()}
}
Write-Output ('RC1_OWNER_DIALOG_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
