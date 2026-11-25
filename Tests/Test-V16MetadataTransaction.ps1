# Real Windows registry/files, isolated random HKCU test subtree.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Add-Type -Path @((Join-Path $repo 'Installer\RdcV16MetadataTransaction.cs'),(Join-Path $repo 'Installer\Rc1ManualUpgrade.cs')) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll,System.Management.dll
$type=([AppDomain]::CurrentDomain.GetAssemblies()|ForEach-Object{$_.GetType('RdcV16MetadataTransaction',$false)}|Where-Object{$_})[0]
$flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
$id=[Guid]::NewGuid().ToString('N')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-Metadata-Test-'+$id)
$sub='Software\RDCRelayMetadataTest-'+$id
$parent=$null;$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
function Call($method,[object[]]$parameters){$type.GetMethod($method,$flags).Invoke($null,$parameters)}
function Refuse($method,[object[]]$parameters,[string]$reason){
 try{[void](Call $method $parameters);return $false}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};if($e.Message -cne $reason){Write-Host ('EXPECTED='+$reason+' ACTUAL='+$e.Message)};return $e.Message -ceq $reason}
}
try{
 [void][IO.Directory]::CreateDirectory($root)
 $desktop=Join-Path $root 'Desktop';$programs=Join-Path $root 'Programs';$release=Join-Path $root 'release'
 foreach($dir in @($desktop,$programs,$release)){[void][IO.Directory]::CreateDirectory($dir)}
 [void][IO.Directory]::CreateDirectory((Join-Path $release 'Source'))
 [IO.File]::WriteAllText((Join-Path $release 'Source\version.txt'),'1.6.0')
 $maintenance=Join-Path $root 'Maintenance.exe';[IO.File]::WriteAllBytes($maintenance,[byte[]](77,90,1))
 $parent=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
 $dl=Join-Path $desktop 'RDC Relay.lnk';$ml=Join-Path $programs 'RDC Relay.lnk'
 [byte[]]$beforeD=1,2,3;[byte[]]$beforeM=4,5,6;[byte[]]$afterD=7,8,9;[byte[]]$afterM=10,11,12
 [IO.File]::WriteAllBytes($dl,$beforeD);[IO.File]::WriteAllBytes($ml,$beforeM)
 $key=$parent.CreateSubKey('RDC Relay')
 try{
  $key.SetValue('DisplayName','RDC Relay')
  $key.SetValue('DisplayVersion','1.5.18')
  $key.SetValue('Publisher','RUBASS')
  $key.SetValue('UninstallString','legacy-placeholder')
  $key.SetValue('NoModify',1,[Microsoft.Win32.RegistryValueKind]::DWord)
  $key.SetValue('Expandable','%LOCALAPPDATA%',[Microsoft.Win32.RegistryValueKind]::ExpandString)
 }finally{$key.Dispose()}
 function Version{
  $key=$parent.OpenSubKey('RDC Relay');try{if($key){return $key.GetValue('DisplayVersion')}}finally{if($key){$key.Dispose()}}
 }
 function Bytes($p,[byte[]]$b){return [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) -ceq [Convert]::ToBase64String($b)}
 $journal=Join-Path $root 'activation.json'
 $prep=[object[]]@($parent,[string]$desktop,[string]$programs,[string]$release,[string]$maintenance,[string]$journal,$afterD,$afterM)
 $apply=[object[]]@($parent,[string]$journal,[string]$desktop,[string]$programs)
 [void](Call 'Prepare' $prep)
 Check ((Version) -ceq '1.5.18' -and (Bytes $dl $beforeD) -and (Bytes $ml $beforeM)) 'prepare writes journal only'
 Check ([IO.File]::Exists($journal)) 'durable journal exists'
 [void](Call 'Apply' $apply)
 Check ((Version) -ceq '1.6.0' -and (Bytes $dl $afterD) -and (Bytes $ml $afterM)) 'new registration and both links published'
 $key=$parent.OpenSubKey('RDC Relay');try{
  Check ($key.GetValue('UninstallString') -ceq ('"'+$maintenance+'" --uninstall')) 'exact maintenance route'
  Check ($key.GetValueKind('NoRepair') -eq [Microsoft.Win32.RegistryValueKind]::DWord) 'typed registry metadata'
 }finally{$key.Dispose()}
 [void](Call 'Apply' $apply)
 Check ((Version) -ceq '1.6.0') 'idempotent publication'
 $removalJournal=Join-Path $root 'removal.json'
 $removal=[object[]]@($parent,[string]$desktop,[string]$programs,[string]$release,[string]$maintenance,[string]$removalJournal,$afterD,$afterM)
 $remove=[object[]]@($parent,[string]$removalJournal,[string]$desktop,[string]$programs)
 [IO.File]::WriteAllBytes($ml,$beforeM)
 Check (Refuse 'PrepareRemoval' $removal 'V16_METADATA_UNINSTALL_LINK_IDENTITY') 'refuse unrelated menu shortcut during removal'
 [IO.File]::WriteAllBytes($ml,$afterM)
 [void](Call 'PrepareRemoval' $removal)
 Check ((Version) -ceq '1.6.0' -and (Bytes $dl $afterD) -and (Bytes $ml $afterM)) 'removal preparation non-mutating'
 [void](Call 'Apply' $remove)
 $key=$parent.OpenSubKey('RDC Relay');try{Check (!$key -and !(Test-Path $dl) -and !(Test-Path $ml)) 'remove exact registration and shortcuts'}finally{if($key){$key.Dispose()}}
 $proof=[object[]]@($parent,[string]$removalJournal,[string]$desktop,[string]$programs,[string]$release,[string]$maintenance)
 Check (Call 'IsCompletedRemoval' $proof) 'completed removal permits reinstall'
 $wrong=[object[]]@($parent,[string]$removalJournal,[string]$desktop,[string]$programs,[string](Join-Path $root 'other-release'),[string]$maintenance)
 Check (!(Call 'IsCompletedRemoval' $wrong)) 'other release ledger rejected'
 [IO.File]::WriteAllBytes($dl,$beforeD)
 Check (Refuse 'IsCompletedRemoval' $proof 'V16_METADATA_LINK_VERIFY') 'unexpected shortcut blocks reinstall proof'
 [IO.File]::Delete($dl)
 [void](Call 'RecoverRollback' $remove)
 Check ((Version) -ceq '1.6.0' -and (Bytes $dl $afterD) -and (Bytes $ml $afterM)) 'interrupted removal recoverable'
 Check (Refuse 'IsCompletedRemoval' $proof 'V16_METADATA_REGISTRY_VERIFY') 'restored installation is not completed removal'
 $runtimeJournal=Join-Path $root 'runtime-removal.json'
 $retired=$release+'.retired-'+[Guid]::NewGuid().ToString('N')
 $runtimePrep=[object[]]@($parent,[string]$desktop,[string]$programs,[string]$release,[string]$maintenance,[string]$runtimeJournal,$afterD,$afterM,[string]$retired,1)
 [void](Call 'PrepareRemovalRuntime' $runtimePrep)
 $runtimeRead=[object[]]@($parent,[string]$runtimeJournal,[string]$desktop,[string]$programs,[string]$release,[string]$maintenance)
 $runtimePlan=Call 'ReadRemovalRecovery' $runtimeRead
 Check ($runtimePlan.RetiredPath -ceq $retired -and $runtimePlan.StartupBefore -eq 1) 'removal journal binds retirement and startup state'
 $runtimeApply=[object[]]@($parent,[string]$runtimeJournal,[string]$desktop,[string]$programs)
 [void](Call 'Apply' $runtimeApply)
 Check ((Call 'ReadRemovalRecovery' $runtimeRead).RetiredPath -ceq $retired) 'post-removal state supports recovery'
 [void](Call 'RecoverRollback' $runtimeApply)
 Check ((Version) -ceq '1.6.0' -and (Bytes $dl $afterD) -and (Bytes $ml $afterM)) 'runtime journal restores shell state'
 [IO.File]::Delete($runtimeJournal)
 $runtimePrep[8]=[string](Join-Path $root 'foreign')
 Check (Refuse 'PrepareRemovalRuntime' $runtimePrep 'V16_REMOVAL_RUNTIME_IDENTITY') 'out of scope retirement refused'
 [IO.File]::Delete($removalJournal)
 [void](Call 'RecoverRollback' $apply)
 Check ((Version) -ceq '1.5.18' -and (Bytes $dl $beforeD) -and (Bytes $ml $beforeM)) 'exact legacy state restored'
 $key=$parent.OpenSubKey('RDC Relay');try{
  Check ($key.GetValueKind('Expandable') -eq [Microsoft.Win32.RegistryValueKind]::ExpandString -and $key.GetValue('Expandable',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ceq '%LOCALAPPDATA%') 'registry expand string roundtrip'
 }finally{$key.Dispose()}
 # Simulate abrupt process exit after only one link and one registry value.
 [IO.File]::WriteAllBytes($dl,$afterD)
 $key=$parent.OpenSubKey('RDC Relay',$true);try{$key.SetValue('DisplayVersion','1.6.0')}finally{$key.Dispose()}
 [void](Call 'RecoverRollback' $apply)
 Check ((Version) -ceq '1.5.18' -and (Bytes $dl $beforeD) -and (Bytes $ml $beforeM)) 'partial publish recovered'
 [IO.File]::WriteAllBytes($ml,[byte[]](42))
 Check (Refuse 'RecoverRollback' $apply 'V16_METADATA_FOREIGN_LINK_CHANGE') 'unrelated link change refuses rollback'
 Check ((Version) -ceq '1.5.18' -and (Bytes $ml ([byte[]](42)))) 'refusal leaves unrelated change untouched'
 [IO.File]::WriteAllBytes($ml,$beforeM)
 $key=$parent.OpenSubKey('RDC Relay',$true);try{$key.SetValue('DisplayVersion','9.9.9')}finally{$key.Dispose()}
 Check (Refuse 'Apply' $apply 'V16_METADATA_FOREIGN_REGISTRY_CHANGE') 'unrelated registry change refuses publication'
 $key=$parent.OpenSubKey('RDC Relay',$true);try{$key.SetValue('DisplayVersion','1.5.18')}finally{$key.Dispose()}
 $j=[IO.File]::ReadAllText($journal)
 [IO.File]::AppendAllText($journal,'tamper')
 Check (Refuse 'Apply' $apply 'V16_METADATA_JOURNAL_HASH') 'corrupt journal refused'
 [IO.File]::WriteAllText($journal,$j)
 Check (Refuse 'Prepare' $prep 'V16_METADATA_EXISTING_JOURNAL') 'existing recovery journal never overwritten'
 [IO.File]::Delete($journal)
 $parent.DeleteSubKey('RDC Relay',$false)
 [IO.File]::Delete($dl);[IO.File]::Delete($ml)
 [void](Call 'Prepare' $prep)
 [void](Call 'Apply' $apply)
 Check ((Version) -ceq '1.6.0') 'fresh registration applied'
 [void](Call 'RecoverRollback' $apply)
 $key=$parent.OpenSubKey('RDC Relay')
 try{Check (!$key -and !(Test-Path $dl) -and !(Test-Path $ml)) 'fresh failed install removes only created metadata'}finally{if($key){$key.Dispose()}}
}finally{
 if($parent){$parent.Dispose();[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sub,$false)}
 if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
'RDC_V16_METADATA_PASS='+$pass+' FAIL=0'
