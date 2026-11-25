# Real WinForms previews of PREPARED release Setup dialogs in disposable Windows.
# NO ShowDialog, NO click, NO Setup/Uninstall/Repair, NO Host, NO credentials.
# Screenshots are NOT proof of a working 1.6 installer transaction.
param([string]$OutputDir=(Join-Path $env:TEMP 'RdcReleaseVisual'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root=Split-Path -Parent $PSScriptRoot
$files=@('RdcReleaseUiCatalog.Generated.cs','RdcReleaseUiLanguage.cs',
 'RdcReleaseMaintenancePolicy.cs','RdcReleaseMaintenanceDialog.cs','RdcReleasePathDialog.cs') |
 ForEach-Object{Join-Path (Join-Path $root 'Installer') $_}
$types=@(Add-Type -Path $files -ReferencedAssemblies @(
 'System.Windows.Forms.dll','System.Drawing.dll') -PassThru -ErrorAction Stop)
function TypeByName([string]$name){
 $value=@($types|Where-Object{$_.Name -ceq $name})|Select-Object -First 1
 if(!$value){throw ('RDC_VISUAL_TYPE_MISSING '+$name)}
 return $value
}
$kind=TypeByName 'RdcMaintenanceKind'
$decisionType=TypeByName 'RdcMaintenanceDecision'
$maintenance=TypeByName 'RdcReleaseMaintenanceDialog'
$pathDialog=TypeByName 'RdcReleasePathDialog'
$flags=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$decisionConstructor=$decisionType.GetConstructor($flags,$null,
 [Type[]]@($kind,[string],[string],[string],[string]),$null)
$maintenanceConstructor=$maintenance.GetConstructor($flags,$null,
 [Type[]]@($decisionType,[string]),$null)
$pathConstructor=$pathDialog.GetConstructor($flags,$null,
 [Type[]]@([string],[string],[string],[string]),$null)
if(!$decisionConstructor -or !$maintenanceConstructor -or !$pathConstructor){
 throw 'RDC_VISUAL_CONSTRUCTOR_MISSING'
}
[void][IO.Directory]::CreateDirectory($OutputDir)
$records=New-Object 'System.Collections.Generic.List[string]'
$counter=0
$dpiX=0;$dpiY=0
function Capture($form,[string]$locale,[string]$scenario){
 $file=Join-Path $OutputDir ($locale+'-'+$scenario+'.png')
 try{
  $form.ShowInTaskbar=$false
  $form.TopMost=$true
  $form.StartPosition=[Windows.Forms.FormStartPosition]::CenterScreen
  $form.Show()
  $form.Activate()
  [Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 150
  [Windows.Forms.Application]::DoEvents()
  if($form.IsDisposed -or !$form.Visible){throw 'FORM_NOT_VISIBLE'}
  if($form.Width -lt 450 -or $form.Height -lt 200){throw 'FORM_GEOMETRY_INVALID'}
  foreach($container in @($form)+@($form.Controls)){
   foreach($control in @($container.Controls)){
    if(!$control.Visible){continue}
    if($control.Left -lt 0 -or $control.Top -lt 0 -or
       $control.Right -gt ($container.ClientSize.Width+2) -or
       $control.Bottom -gt ($container.ClientSize.Height+2)){
     throw ('CONTROL_OUTSIDE_CLIENT '+$locale+' '+$scenario+' '+$control.Name)
    }
   }
  }
  $dpi=$form.CreateGraphics()
  try{
   $script:dpiX=$dpi.DpiX;$script:dpiY=$dpi.DpiY
  }finally{$dpi.Dispose()}
  $png=New-Object Drawing.Bitmap($form.Width,$form.Height)
  try{
   $graphics=[Drawing.Graphics]::FromImage($png)
   try{$graphics.CopyFromScreen($form.Left,$form.Top,0,0,$png.Size)}
   finally{$graphics.Dispose()}
   $png.Save($file,[Drawing.Imaging.ImageFormat]::Png)
  }finally{$png.Dispose()}
  if((Get-Item $file).Length -lt 3500){throw ('PNG_TOO_SMALL '+$file)}
  $script:counter++
  $info='PASS_SCREEN '+$locale+' '+$scenario+' '+$form.Width+'x'+$form.Height+
    ' DPI='+$script:dpiX+'x'+$script:dpiY+' TITLE='+$form.Text
  [void]$script:records.Add($info)
  Write-Output $info
 }finally{$form.Close();$form.Dispose()}
}
foreach($locale in @('ru-RU','en-US')){
 foreach($scenario in @('path-fresh','path-existing')){
  $current=if($scenario -eq 'path-existing'){'C:\RDC-Verified'}else{''}
  $form=$pathConstructor.Invoke(@('1.6.0',$current,'C:\RDC-Stable',$locale))
  $inputBox=@($form.Controls.Find('RdcInstallPath',$true))[0]
  $browse=@($form.Controls.Find('RdcInstallBrowse',$true))[0]
  $ok=@($form.Controls.Find('RdcInstallConfirm',$true))[0]
  $cancel=@($form.Controls.Find('RdcInstallCancel',$true))[0]
  if(!$ok -or !$cancel -or !$inputBox -or !$browse){throw 'PATH_FORM_CONTROLS_MISSING'}
  $existing=$scenario -eq 'path-existing'
  if($inputBox.ReadOnly -ne $existing -or $browse.Enabled -eq $existing -or
     $form.CancelButton -ne $cancel){throw 'PATH_SAFETY_CONTRACT_CHANGED'}
  $expectedButton=if($existing){if($locale -ceq 'ru-RU'){'Продолжить'}else{'Continue'}}
                  else{if($locale -ceq 'ru-RU'){'Установить'}else{'Install'}}
  if($ok.Text -cne $expectedButton){throw 'PATH_BUTTON_LOCALE_OR_MODE_CHANGED'}
  Capture $form $locale $scenario
 }
 foreach($test in @(
  @{Kind='Upgrade';Existing='1.5.18';Reason='VERIFIED'},
  @{Kind='Repair';Existing='1.6.0';Reason='VERIFIED'},
  @{Kind='NewerInstalled';Existing='1.7.0';Reason='DOWNGRADE_REFUSED'},
  @{Kind='Refuse';Existing='1.5.18';Reason='PILOT_MIGRATION_NOT_VERIFIED'}
  )){
  $enum=[Enum]::Parse($kind,$test.Kind)
  $decision=$decisionConstructor.Invoke(@($enum,[string]$test.Existing,
   '1.6.0','C:\RDC-Test',[string]$test.Reason))
  $form=$maintenanceConstructor.Invoke(@($decision,$locale))
  if(!$form.CancelButton){throw 'MAINTENANCE_ESCAPE_MISSING'}
  $primary=@($form.Controls.Find('RdcMaintenancePrimary',$true))
  $remove=@($form.Controls.Find('RdcMaintenanceRemove',$true))
  if($test.Kind -in @('Refuse','NewerInstalled')){
   if($primary.Count -ne 0 -or $remove.Count -ne 0){throw 'BLOCKED_MODE_ACTIONS_PRESENT'}
  }else{
   if($primary.Count -ne 1 -or $remove.Count -ne 1){throw 'ALLOWED_ACTIONS_MISSING'}
  }
  Capture $form $locale ('maintenance-'+$test.Kind.ToLowerInvariant())
 }
}
if($counter -ne 12){throw ('RDC_VISUAL_BAD_COUNT '+$counter)}
[IO.File]::WriteAllLines((Join-Path $OutputDir 'visual-summary.txt'),
 $records.ToArray(),(New-Object Text.UTF8Encoding($true)))
Write-Output ('RDC_RELEASE_VISUAL_SCREENSHOTS='+$counter+' FAIL=0')
