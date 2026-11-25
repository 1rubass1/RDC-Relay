# Test actual Full Host/GUI release path UI and read-only validation only.
# Never ShowDialog, create installed directories or launch Setup/Host/Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$files=@('Installer\RdcReleaseUiCatalog.Generated.cs','Installer\RdcReleaseUiLanguage.cs','Installer\RdcReleasePathDialog.cs')|ForEach-Object{Join-Path $repo $_}
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
try{
 $compiled=@(Add-Type -Path $files -ReferencedAssemblies @('System.Windows.Forms.dll','System.Drawing.dll') -PassThru -ErrorAction Stop)
 $policy=@($compiled|Where-Object{$_.Name -ceq 'RdcReleaseInstallLocation'})|Select-Object -First 1
 $ui=@($compiled|Where-Object{$_.Name -ceq 'RdcReleasePathDialog'})|Select-Object -First 1
 $stat=[Reflection.BindingFlags]'Static,NonPublic,Public'
 $instance=[Reflection.BindingFlags]'Instance,NonPublic,Public'
 $validate=$policy.GetMethod('TryValidate',$stat)
 $suggest=$policy.GetMethod('SuggestedPath',$stat)
 $ctor=$ui.GetConstructor($instance,$null,[Type[]]@([string],[string],[string]),$null)
 $localeCtor=$ui.GetConstructor($instance,$null,[Type[]]@([string],[string],[string],[string]),$null)
 Check ($null -ne $validate -and $null -ne $suggest -and $null -ne $ctor) 'future release-only path policy and dialog are compiled'
 if($null -eq $validate -or $null -eq $ctor){throw 'RELEASE_PATH_DIALOG_MISSING'}
 function Probe([string]$target,[string]$current,[string]$legacy){
  $args=New-Object object[] 5
  $args[0]=[string]$target;$args[1]=[string]$current
  $args[2]=[string]$legacy;$args[3]='';$args[4]=''
  $accepted=[bool]$validate.Invoke($null,$args)
  return @($accepted,[string]$args[3],[string]$args[4])
 }
 $default=[string]$suggest.Invoke($null,@())
 $local=[Environment]::GetFolderPath('LocalApplicationData')
 $legacy=Join-Path $local 'RemoteDesktopCommanderLauncher'
 Check ($default -ieq (Join-Path $local 'Programs\RDC Relay')) 'default path is per-user Programs/RDC Relay'
 $good=Probe $default '' $legacy
 Check ($good[0] -and $good[1] -ieq $default) 'proposed new install path accepted without creating it'
 Check (-not (Probe '' '' $legacy)[0] -and
  -not (Probe 'RDC Relay' '' $legacy)[0]) 'empty and relative paths denied'
 $root=[IO.Path]::GetPathRoot($local)
 Check (-not (Probe $root '' $legacy)[0]) 'drive root cannot become product install directory'
 Check (-not (Probe ([Environment]::GetFolderPath('Windows')) '' $legacy)[0] -and
  -not (Probe (Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\RDC Relay') '' $legacy)[0]) 'Windows and System32 trees refused'
 Check (-not (Probe (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'RDC Relay') '' $legacy)[0]) 'per-user install cannot target administrator-protected Program Files'
 Check (-not (Probe $legacy '' $legacy)[0] -and
  -not (Probe (Join-Path $legacy 'RDC Relay') '' $legacy)[0]) 'the original stable 1.5.18 installation is preserved'
 Check (-not (Probe (Join-Path ([IO.Path]::GetTempPath()) 'RDC Relay') '' $legacy)[0]) 'temporary test and cache trees refused'
 Check (-not (Probe '\\example.invalid\share\RDC Relay' '' $legacy)[0]) 'network UNC paths refused'
 Check (-not (Probe (Join-Path $local 'Programs\RDC Relay..') '' $legacy)[0]) 'ambiguous trailing-dot directory refused'
 Check (-not (Probe (Join-Path $local 'Programs\RDC Relay:stream') '' $legacy)[0]) 'alternate data stream colon cannot be an install directory'
 Check (-not (Probe (Join-Path $local 'RDCRelayOwnerPilot\Another Release') '' $legacy)[0]) 'existing pilot Remote vault and release tree are protected'
 $different=Join-Path $local 'Programs\Different RDC Directory'
 Check (-not (Probe $different $default $legacy)[0] -and
  [string](Probe $different $default $legacy)[2] -ceq 'RELOCATION_REQUIRES_SEPARATE_WORKFLOW') 'verified existing release cannot be silently relocated'
 $same=Probe $default $default $legacy
 Check ($same[0] -and $same[1] -ieq $default) 'verified reinstall preserves the existing directory'
 $form=$localeCtor.Invoke(@([string]'1.6.0',[string]'',[string]$legacy,[string]'ru-RU'))
 try{
  $textbox=@($form.Controls.Find('RdcInstallPath',$true))
  $browse=@($form.Controls.Find('RdcInstallBrowse',$true))
  $confirm=@($form.Controls.Find('RdcInstallConfirm',$true))
  $cancel=@($form.Controls.Find('RdcInstallCancel',$true))
  Check ($textbox.Count -eq 1 -and $textbox[0].Text -ieq $default -and
   $browse.Count -eq 1 -and $browse[0].Enabled) 'new installation dialog offers default directory with browse control'
  Check ($confirm.Count -eq 1 -and $confirm[0].Text -ceq 'Установить' -and
   $cancel.Count -eq 1 -and $cancel[0].DialogResult -eq 'Cancel' -and
   $null -ne $form.AcceptButton -and $null -ne $form.CancelButton) 'dialog has install, cancel and Windows keyboard defaults'
  $form.PerformLayout()
  Check ($cancel[0].Right -lt $cancel[0].Parent.ClientSize.Width -and
   $confirm[0].Left -gt 0 -and
   $confirm[0].Right -lt $cancel[0].Left) 'install and cancel buttons fit the footer without clipping'
  Check ($form.Text -ceq 'Установка RDC Relay 1.6.0' -and
   $form.FormBorderStyle -eq 'FixedDialog' -and $form.AutoScaleMode -eq 'Font') 'localized one-page WinForms path dialog supports font scaling'
 }finally{$form.Dispose()}
 $existing=$localeCtor.Invoke(@([string]'1.6.0',[string]$default,[string]$legacy,[string]'ru-RU'))
 try{
  $textbox=@($existing.Controls.Find('RdcInstallPath',$true))
  $browse=@($existing.Controls.Find('RdcInstallBrowse',$true))
  Check ($textbox.Count -eq 1 -and $textbox[0].ReadOnly -and
   $browse.Count -eq 1 -and -not $browse[0].Enabled -and
   @($existing.Controls.Find('RdcInstallConfirm',$true))[0].Text -ceq 'Продолжить') 'existing release folder offers Continue and blocks accidental relocation'
 }finally{$existing.Dispose()}
 $choose=$ui.GetMethod('Choose',$stat,$null,
  [Type[]]@([string],[string],[string],[string].MakeByRefType()),$null)
 Check ($null -ne $choose -and
  $ui.IsSubclassOf([Windows.Forms.Form])) 'dialog exposes a modal integration entrypoint, without being invoked in tests'
}catch{
 $fail++;Write-Output ('FAIL RELEASE_PATH_DIALOG_EXCEPTION '+$_.Exception.GetType().Name+' '+$_.Exception.Message)
}
Write-Output ('RC1_RELEASE_PATH_DIALOG_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
