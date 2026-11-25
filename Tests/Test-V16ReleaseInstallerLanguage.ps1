# Future RDC Relay 1.6 Setup localized dialog/UI tests, without Setup execution,
# registry, shortcuts, credentials, installed app, Remote or any login.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Installer'
$files=@('RdcReleaseUiCatalog.Generated.cs','RdcReleaseUiLanguage.cs',
 'RdcReleaseMaintenancePolicy.cs','RdcReleaseMaintenanceDialog.cs','RdcReleasePathDialog.cs')|
 ForEach-Object{Join-Path $src $_}
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$compiled=@(Add-Type -Path $files -ReferencedAssemblies @('System.Windows.Forms.dll','System.Drawing.dll') -PassThru -ErrorAction Stop)
function TypeByName([string]$name){
 $found=@($compiled|Where-Object{$_.Name -ceq $name})|Select-Object -First 1
 if($null -eq $found){throw ('MISSING_COMPILER_TYPE '+$name)}
 return $found
}
$cat=TypeByName 'RdcReleaseUiCatalog'
$language=TypeByName 'RdcReleaseUiLanguage'
$kind=TypeByName 'RdcMaintenanceKind'
$decisionType=TypeByName 'RdcMaintenanceDecision'
$maintenance=TypeByName 'RdcReleaseMaintenanceDialog'
$pathType=TypeByName 'RdcReleasePathDialog'
$static=[Reflection.BindingFlags]'Static,NonPublic,Public'
$instance=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$ru=$cat.GetField('Russian',$static).GetValue($null)
$en=$cat.GetField('English',$static).GetValue($null)
Check ($ru.Count -eq 36 -and $en.Count -eq 36) '36 embedded installer translation entries including legacy staging'
$ruSource=(Get-Content (Join-Path $root 'Source\lang\ru-RU.json') -Raw -Encoding UTF8|ConvertFrom-Json).strings
$enSource=(Get-Content (Join-Path $root 'Source\lang\en-US.json') -Raw -Encoding UTF8|ConvertFrom-Json).strings
# Dotted keys require lookup through PSObject.Properties, not direct property syntax.
$match=$true
foreach($key in @($ru.Keys)){
 $originalRu=@($ruSource.PSObject.Properties|Where-Object{$_.Name -ceq $key}|Select-Object -First 1)
 $originalEn=@($enSource.PSObject.Properties|Where-Object{$_.Name -ceq $key}|Select-Object -First 1)
 if(-not $en.ContainsKey($key) -or $originalRu.Count -ne 1 -or $originalEn.Count -ne 1 -or
  [string]$ru[$key] -cne [string]$originalRu[0].Value -or
  [string]$en[$key] -cne [string]$originalEn[0].Value){$match=$false;break}
}
Check $match 'embedded resources byte-semantic-equal to original Source/lang strings'
$suggest=$language.GetMethod('Suggested',$static)
$resolve=$language.GetMethod('Resolve',$static,$null,[Type[]]@([bool],[string],[string]),$null)
$translate=$language.GetMethod('Text',$static)
$format=$language.GetMethod('Format',$static)
Check ($suggest.Invoke($null,@('ru-RU',$false)) -ceq 'ru-RU' -and
 $suggest.Invoke($null,@('en-US',$false)) -ceq 'en-US' -and
 $suggest.Invoke($null,@('de-DE',$false)) -ceq 'en-US') 'fresh install suggests ru-RU on Russian Windows and en-US otherwise'
Check ($suggest.Invoke($null,@('en-US',$true)) -ceq 'ru-RU' -and
 $suggest.Invoke($null,@('de-DE',$true)) -ceq 'ru-RU') 'existing installations without preference remain Russian'
$tmp=Join-Path $env:TEMP ('RdcInstallerLang-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tmp)
try{
 $preference=Join-Path $tmp 'ui-language.json'
 function ResolveTest([bool]$existing,[string]$culture){
  $argsForLocale=New-Object object[] 3
  $argsForLocale[0]=[bool]$existing
  $argsForLocale[1]=[string]$preference
  $argsForLocale[2]=[string]$culture
  return [string]$resolve.Invoke($null,$argsForLocale)
 }
 Check ((ResolveTest $false 'de-DE') -ceq 'en-US' -and
  (ResolveTest $true 'de-DE') -ceq 'ru-RU') 'missing preference selects fresh-vs-existing default without creating a file'
 Check (-not [IO.File]::Exists($preference)) 'language resolution is read-only'
 [IO.File]::WriteAllText($preference,'{"version":1,"locale":"en-US"}',(New-Object Text.UTF8Encoding($false)))
 Check ((ResolveTest $true 'ru-RU') -ceq 'en-US' -and
  (ResolveTest $false 'ru-RU') -ceq 'en-US') 'explicit English preference overrides Windows locale for fresh and upgrade'
 [IO.File]::WriteAllText($preference,'{"version":1,"locale":"ru-RU"}',(New-Object Text.UTF8Encoding($false)))
 Check ((ResolveTest $true 'en-US') -ceq 'ru-RU' -and
  (ResolveTest $false 'en-US') -ceq 'ru-RU') 'explicit Russian preference wins on English Windows'
 [IO.File]::WriteAllText($preference,'{"version":1,"locale":"en-US","evil":true}',(New-Object Text.UTF8Encoding($false)))
 Check ((ResolveTest $false 'en-US') -ceq 'ru-RU') 'invalid extra JSON keys fail closed to Russian'
 [IO.File]::WriteAllText($preference,'{"version":2,"locale":"en-US"}',(New-Object Text.UTF8Encoding($false)))
 Check ((ResolveTest $false 'en-US') -ceq 'ru-RU') 'future preference schema version is not silently accepted'
 [IO.File]::WriteAllText($preference,'{"version":1,"locale":"xx-XX"}',(New-Object Text.UTF8Encoding($false)))
 Check ((ResolveTest $false 'en-US') -ceq 'ru-RU') 'unsupported preferred locale fails closed'
 [IO.File]::WriteAllText($preference,('a'*130),(New-Object Text.UTF8Encoding($false)))
 Check ((ResolveTest $false 'en-US') -ceq 'ru-RU') 'oversized preference is refused'
 [IO.File]::Delete($preference)
}finally{if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}}
Check ($translate.Invoke($null,@('en-US','installer.maintenance.cancel','Отмена')) -ceq 'Cancel' -and
 $translate.Invoke($null,@('xx-XX','installer.maintenance.cancel','Отмена')) -ceq 'Отмена') 'known language translated, unsupported language falls back to Russian'
Check ($format.Invoke($null,@('en-US','installer.path.windowTitle',
 'Установка RDC Relay {version}','1.6.0',$null,$null)) -ceq 'Installing RDC Relay 1.6.0') 'release path title has a validated version placeholder'
Check ($format.Invoke($null,@('en-US','installer.path.windowTitle',
 'Установка RDC Relay {version}','private/secret',$null,$null)) -ceq 'Installing RDC Relay ?') 'untrusted versions never render unbounded strings'
$decisionCtor=$decisionType.GetConstructor($instance,$null,
 [Type[]]@($kind,[string],[string],[string],[string]),$null)
$maintCtor=$maintenance.GetConstructor($instance,$null,[Type[]]@($decisionType,[string]),$null)
$pathCtor=$pathType.GetConstructor($instance,$null,[Type[]]@([string],[string],[string],[string]),$null)
if(!$decisionCtor -or !$maintCtor -or !$pathCtor){throw 'LOCALIZED_CONSTRUCTOR_MISSING'}
function Mode([string]$name,[string]$installed,[string]$reason){
 return $decisionCtor.Invoke(@([Enum]::Parse($kind,$name),$installed,'1.6.0','C:\RDC-Test',$reason))
}
function MaintForm($decision,[string]$locale){return $maintCtor.Invoke(@($decision,$locale))}
function PForm([string]$locale,[string]$root){return $pathCtor.Invoke(@('1.6.0',$root,'C:\RDC-Test-Stable',$locale))}
foreach($locale in @('ru-RU','en-US')){
 $english=$locale -ceq 'en-US'
 foreach($scenario in @(
  @{Mode='Upgrade';Installed='1.5.18';Reason='VERIFIED';Header='installer.maintenance.upgradeHeading';Action='installer.maintenance.update'},
  @{Mode='Repair';Installed='1.6.0';Reason='VERIFIED';Header='installer.maintenance.installedHeading';Action='installer.maintenance.repair'},
  @{Mode='NewerInstalled';Installed='1.7.0';Reason='DOWNGRADE_REFUSED';Header='installer.maintenance.newerHeading';Action=''},
  @{Mode='Refuse';Installed='1.5.18';Reason='PILOT_MIGRATION_NOT_VERIFIED';Header='installer.maintenance.errorHeading';Action=''}
  )){
  $form=MaintForm (Mode $scenario.Mode $scenario.Installed $scenario.Reason) $locale
  try{
   $header=@($form.Controls.Find('RdcMaintenanceHeading',$true))[0]
   $details=@($form.Controls.Find('RdcMaintenanceDescription',$true))[0]
   $cancel=@($form.Controls.Find('RdcMaintenanceCancel',$true))[0]
   $primary=@($form.Controls.Find('RdcMaintenancePrimary',$true))
   $remove=@($form.Controls.Find('RdcMaintenanceRemove',$true))
   $expected=if($english){$en}else{$ru}
   Check ($header.Text -ceq $expected[$scenario.Header] -and
    $form.Text -ceq $expected['installer.maintenance.title']) ($locale+' maintenance heading '+$scenario.Mode)
   Check ($details.Text.Contains($scenario.Installed) -and $details.Text.Contains('1.6.0') -or
     $scenario.Mode -eq 'Refuse') ($locale+' detail preserves trusted version text '+$scenario.Mode)
   Check ($null -ne $form.CancelButton -and
    $cancel.DialogResult -eq [Windows.Forms.DialogResult]::Cancel) ($locale+' Cancel/Escape safe '+$scenario.Mode)
   if($scenario.Action){
    Check ($primary.Count -eq 1 -and $remove.Count -eq 1 -and
     $primary[0].Text -ceq $expected[$scenario.Action] -and
     $remove[0].Text -ceq $expected['installer.maintenance.uninstall']) ($locale+' localized actions '+$scenario.Mode)
   }else{
    Check ($primary.Count -eq 0 -and $remove.Count -eq 0 -and
     $cancel.Text -ceq $expected['installer.maintenance.close']) ($locale+' refused/downgrade remains close-only '+$scenario.Mode)
   }
  }finally{$form.Dispose()}
 }
 foreach($existing in @($false,$true)){
  $rootValue=if($existing){'C:\RDC-Verified'}else{''}
  $form=PForm $locale $rootValue
  try{
   $labels=@($form.Controls|Where-Object{$_ -is [Windows.Forms.Label]})
   $pathBox=@($form.Controls.Find('RdcInstallPath',$true))[0]
   $browse=@($form.Controls.Find('RdcInstallBrowse',$true))[0]
   $confirm=@($form.Controls.Find('RdcInstallConfirm',$true))[0]
   $cancel=@($form.Controls.Find('RdcInstallCancel',$true))[0]
   $expected=if($english){$en}else{$ru}
   Check ($form.Text -ceq $expected['installer.path.windowTitle'].Replace('{version}','1.6.0') -and
    $confirm.Text -ceq $expected[$(if($existing){'installer.path.continue'}else{'installer.path.install'})] -and
    $cancel.Text -ceq $expected['installer.path.cancel']) ($locale+' path dialog title/buttons')
   Check ($browse.Text -ceq $expected['installer.path.browse'] -and
    $browse.Enabled -eq (!$existing) -and
    $pathBox.ReadOnly -eq $existing) ($locale+' Browse and verified path immutability '+$existing)
   Check ($form.CancelButton -eq $cancel -and $form.AcceptButton -eq $confirm -and
    $cancel.DialogResult -eq [Windows.Forms.DialogResult]::Cancel) ($locale+' path keyboard default is unchanged '+$existing)
  }finally{$form.Dispose()}
 }
}
$chooseMaintenance=$maintenance.GetMethod('Choose',$static,$null,
 [Type[]]@($decisionType,[string]),$null)
$chooseLocation=$pathType.GetMethod('Choose',$static,$null,
 [Type[]]@([string],[string],[string],[string],[string].MakeByRefType()),$null)
Check ($null -ne $chooseMaintenance -and $null -ne $chooseLocation) 'future Setup entrypoint may pass explicit language without changing decision authorization'
Write-Output ('RC1_RELEASE_INSTALLER_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
