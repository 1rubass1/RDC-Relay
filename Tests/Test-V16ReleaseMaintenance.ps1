# No live installation, registry, shortcuts, Host or Remote actions.
# Compiles the actual future-release policy and instantiates native WinForms
# maintenance surfaces on a temporary STA test process only (never ShowDialog).
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$files=@('Installer\RdcReleaseUiCatalog.Generated.cs','Installer\RdcReleaseUiLanguage.cs',
 'Installer\RdcReleaseMaintenancePolicy.cs','Installer\RdcReleaseMaintenanceDialog.cs','Installer\RdcReleasePathDialog.cs')|
 ForEach-Object{Join-Path $repo $_}
$pass=0;$fail=0
function Check([bool]$v,[string]$label){
 if($v){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
try{
 $compiled=@(Add-Type -Path $files -ReferencedAssemblies @('System.Windows.Forms.dll','System.Drawing.dll') -PassThru)
 $evType=@($compiled|Where-Object{$_.Name -ceq 'RdcMaintenanceEvidence'})|Select-Object -First 1
 $polType=@($compiled|Where-Object{$_.Name -ceq 'RdcReleaseMaintenancePolicy'})|Select-Object -First 1
 $uiType=@($compiled|Where-Object{$_.Name -ceq 'RdcReleaseMaintenanceDialog'})|Select-Object -First 1
 if(!$evType -or !$polType -or !$uiType){throw 'MAINTENANCE_PRODUCTION_TYPES_MISSING'}
 $flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
 $inst=[Reflection.BindingFlags]'Instance,NonPublic,Public'
 $decide=$polType.GetMethod('Decide',$flags)
 $allowed=$polType.GetMethod('IsAllowed',$flags)
 if(!$decide -or !$allowed){throw 'MAINTENANCE_DECISION_METHODS_MISSING'}
 $scan=$polType.GetMethod('InspectKnownShortcuts',$flags)
 $checkPath=$polType.GetMethod('CheckPath',$flags)
 Check ($null -ne $scan -and $null -ne $checkPath) 'installer detects both Desktop and Start Menu shortcut identities'
 $desktop=[string][Environment]::GetFolderPath('DesktopDirectory')
 $desktopLink=[string](Join-Path $desktop 'RDC Relay.lnk')
 $args1=New-Object object[] 2
 $args1[0]=[string]$desktopLink;$args1[1]=[bool]$true
 Check ([bool]$checkPath.Invoke($null,$args1)) 'actual Windows OneDrive/cloud Desktop ancestry passes bounded OS tag validation'
 $local=[string](Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'RDCRelayOwnerPilot')
 $args2=New-Object object[] 2
 $args2[0]=[string]$local;$args2[1]=[bool]$false
 Check ([bool]$checkPath.Invoke($null,$args2)) 'real pilot data root path can be inspected without altering it'
 function Evidence{
  $e=[Activator]::CreateInstance($evType)
  foreach($pair in @(@('Registered',$true),@('DisplayName','RDC Relay'),@('Publisher','UMAS'),
   @('RegistryVersion','1.5.18'),@('InstallRoot','C:\Test\RDC'),
   @('DiskVersion','1.5.18'),@('EntryPresent',$true),@('GuiPresent',$true),
   @('UpdaterPresent',$true))){
    $evType.GetField([string]$pair[0],$inst).SetValue($e,$pair[1])
  }
  return $e
 }
 function Field($e,[string]$name,$value){$evType.GetField($name,$inst).SetValue($e,$value)}
 function Decision($e,[string]$version){
  return $decide.Invoke($null,[object[]]@($e,$version))
 }
 function Kind($d){return [string]($d.GetType().GetField('Kind',$inst).GetValue($d))}
 function Reason($d){return [string]($d.GetType().GetField('Reason',$inst).GetValue($d))}
 $fresh=Evidence;Field $fresh 'Registered' $false
 Check ((Kind (Decision $fresh '1.6.0')) -ceq 'Fresh') 'no installed evidence allows only fresh installation'
 $orphan=Evidence;Field $orphan 'Registered' $false;Field $orphan 'OrphanedFiles' $true
 Check ((Kind (Decision $orphan '1.6.0')) -ceq 'Refuse') 'orphaned program payload cannot be treated as fresh'
 $noRegPilot=Evidence;Field $noRegPilot 'Registered' $false;Field $noRegPilot 'PilotOverlay' $true
 Check ((Kind (Decision $noRegPilot '1.6.0')) -ceq 'Refuse') 'unregistered pilot shortcut cannot create second installation'
 $older=Decision (Evidence) '1.6.0'
 Check ((Kind $older) -ceq 'Upgrade') 'verified 1.5.18 gets update/remove choice'
 $same=Evidence;Field $same 'RegistryVersion' '1.6.0';Field $same 'DiskVersion' '1.6.0'
 $repair=Decision $same '1.6.0'
 Check ((Kind $repair) -ceq 'Repair') 'matching 1.6.0 gets repair/remove choice'
 $newer=Evidence;Field $newer 'RegistryVersion' '1.6.1';Field $newer 'DiskVersion' '1.6.1'
 $block=Decision $newer '1.6.0'
 Check ((Kind $block) -ceq 'NewerInstalled' -and (Reason $block) -ceq 'DOWNGRADE_REFUSED') 'newer installed version blocks downgrade'
 $semantic=Evidence;Field $semantic 'RegistryVersion' '1.10.0';Field $semantic 'DiskVersion' '1.10.0'
 Check ((Kind (Decision $semantic '1.9.9')) -ceq 'NewerInstalled') 'semantic version ordering (1.10 higher than 1.9)'
 $unknown=Evidence;Field $unknown 'Publisher' 'OTHER'
 Check ((Kind (Decision $unknown '1.6.0')) -ceq 'Refuse') 'unrecognized publisher fails closed'
 $mismatch=Evidence;Field $mismatch 'DiskVersion' '1.5.19'
 Check ((Kind (Decision $mismatch '1.6.0')) -ceq 'Refuse') 'registry and disk version mismatch fails closed'
 $invalid=Evidence;Field $invalid 'RegistryVersion' '1.5.18-RC1'
 Check ((Kind (Decision $invalid '1.6.0')) -ceq 'Refuse') 'ambiguous prerelease identity fails closed'
 $broken=Evidence;Field $broken 'GuiPresent' $false
 Check ((Kind (Decision $broken '1.6.0')) -ceq 'Refuse') 'missing runtime files must not offer ordinary upgrade'
 $repairMissing=Evidence;Field $repairMissing 'RegistryVersion' '1.6.0';Field $repairMissing 'DiskVersion' '1.6.0'
 Field $repairMissing 'GuiPresent' $false;Field $repairMissing 'UpdaterPresent' $false
 Check ((Kind (Decision $repairMissing '1.6.0')) -ceq 'Repair') 'same-version repair can restore missing GUI/updater files'
 $machine=Evidence;Field $machine 'MachineConflict' $true
 Check ((Kind (Decision $machine '1.6.0')) -ceq 'Refuse') 'machine-wide registered product blocks per-user copy'
 $duplicate=Evidence;Field $duplicate 'DuplicateRegistration' $true
 Check ((Kind (Decision $duplicate '1.6.0')) -ceq 'Refuse') 'duplicate uninstall registry identity blocks installation'
 $foreign=Evidence;Field $foreign 'ForeignShortcut' $true
 Check ((Kind (Decision $foreign '1.6.0')) -ceq 'Refuse') 'foreign shortcut cannot be overwritten'
 $reparse=Evidence;Field $reparse 'DirectoryReparse' $true
 Check ((Kind (Decision $reparse '1.6.0')) -ceq 'Refuse') 'reparse installation path cannot be trusted'
 $untrusted=Evidence;Field $untrusted 'UntrustedInstallRoot' $true
 Check ((Kind (Decision $untrusted '1.6.0')) -ceq 'Refuse') 'network or protected drive-root install identity fails closed'
 $pilot=Evidence;Field $pilot 'PilotOverlay' $true
 $pilotDecision=Decision $pilot '1.6.0'
 Check ((Kind $pilotDecision) -ceq 'Refuse' -and
  (Reason $pilotDecision) -ceq 'PILOT_MIGRATION_NOT_VERIFIED') 'stable ARP with pilot shortcut needs verified migration, not overwrite'
 $failure=Evidence;Field $failure 'DiscoveryError' 'IOException'
 Check ((Kind (Decision $failure '1.6.0')) -ceq 'Refuse') 'failed registry or shortcut inspection blocks install'
 $invalidTarget=$false
 try{$null=Decision (Evidence) '1.6.0 RC1'}catch{$invalidTarget=$true}
 Check $invalidTarget 'installer version must be strict three-component numeric'
 $actionType=@($compiled|Where-Object{$_.Name -ceq 'RdcMaintenanceAction'})|Select-Object -First 1
 function Can($d,[string]$action){
  $a=New-Object object[] 2
  $a[0]=$d;$a[1]=[Enum]::Parse($actionType,$action)
  return [bool]$allowed.Invoke($null,$a)
 }
 Check ((Can $older 'Update') -and (Can $older 'Uninstall') -and
  -not (Can $older 'Repair')) 'upgrade permits update/remove only'
 Check ((Can $repair 'Repair') -and (Can $repair 'Uninstall') -and
  -not (Can $repair 'Update')) 'same-version maintenance permits repair/remove only'
 Check ((Can $block 'Cancel') -and -not (Can $block 'Uninstall') -and
  -not (Can $block 'Install')) 'downgrade never authorizes install or uninstall'
 Check (-not (Can $pilotDecision 'Update') -and
  -not (Can $pilotDecision 'Uninstall')) 'unverified pilot migration cannot dispatch destructive actions'
 Check ((Can (Decision $fresh '1.6.0') 'Install') -and
  -not (Can (Decision $fresh '1.6.0') 'Uninstall')) 'fresh installation cannot be used as uninstall route'
 $view=[Activator]::CreateInstance($uiType,$inst,$null,[object[]]@($older,'ru-RU'),$null)
 try{
  $heading=@($view.Controls.Find('RdcMaintenanceHeading',$true))
  $desc=@($view.Controls.Find('RdcMaintenanceDescription',$true))
  $primary=@($view.Controls.Find('RdcMaintenancePrimary',$true))
  $remove=@($view.Controls.Find('RdcMaintenanceRemove',$true))
  $cancel=@($view.Controls.Find('RdcMaintenanceCancel',$true))
  Check ($heading.Count -eq 1 -and $heading[0].Text -ceq 'Доступно обновление' -and
   $desc[0].Text.Contains('1.5.18') -and $desc[0].Text.Contains('1.6.0')) 'update dialog uses clear installed and target versions'
  Check ($primary.Count -eq 1 -and $primary[0].Text -ceq 'Обновить' -and
   $remove.Count -eq 1 -and $remove[0].Text -ceq 'Удалить' -and
   $cancel.Count -eq 1 -and $cancel[0].Text -ceq 'Отмена') 'update dialog provides explicit actions, no technical buttons'
  Check ($null -ne $view.AcceptButton -and $null -ne $view.CancelButton) 'update dialog supports keyboard accept and escape'
 }finally{$view.Dispose()}
 $view=[Activator]::CreateInstance($uiType,$inst,$null,[object[]]@($repair,'ru-RU'),$null)
 try{
  $primary=@($view.Controls.Find('RdcMaintenancePrimary',$true))
  $remove=@($view.Controls.Find('RdcMaintenanceRemove',$true))
  Check ($primary.Count -eq 1 -and $primary[0].Text -ceq 'Восстановить' -and
   $remove.Count -eq 1 -and $remove[0].Text -ceq 'Удалить') 'matching version offers repair or uninstall'
 }finally{$view.Dispose()}
 foreach($decision in @($block,$pilotDecision)){
  $view=[Activator]::CreateInstance($uiType,$inst,$null,[object[]]@($decision,'ru-RU'),$null)
  try{
   $primary=@($view.Controls.Find('RdcMaintenancePrimary',$true))
   $remove=@($view.Controls.Find('RdcMaintenanceRemove',$true))
   $close=@($view.Controls.Find('RdcMaintenanceCancel',$true))
   Check ($primary.Count -eq 0 -and $remove.Count -eq 0 -and
    $close.Count -eq 1 -and $close[0].Text -ceq 'Закрыть') 'blocked install has Close only, never a destructive operation'
  }finally{$view.Dispose()}
 }
 $e=Evidence;Field $e 'DisplayName' 'Fake Relay'
 Check ((Kind (Decision $e '1.6.0')) -ceq 'Refuse') 'product name mismatch cannot hijack registry'
}catch{
 $fail++
 Write-Output ('FAIL MAINTENANCE_TEST_EXCEPTION '+$_.Exception.GetType().Name+' '+$_.Exception.Message)
}
Write-Output ('RC1_RELEASE_MAINTENANCE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
