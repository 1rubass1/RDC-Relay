# G111 — compile real release installer, exercise pure install-state decision
# and disposable shortcut metadata rollback. NEVER call Setup.Main, launch
# Remote, write actual HKCU/HKLM registration or touch installed shortcuts.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'Source'
$install=Join-Path $repo 'Installer'
$pass=0;$fail=0
function Check([bool]$value,[string]$name){
 if($value){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-REL-POLICY-'+[Guid]::NewGuid().ToString('N'))
try{
 [void][IO.Directory]::CreateDirectory($root)
 $compiler=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|
  Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
 if(-not $compiler){throw 'RDC_RELEASE_TEST_COMPILER_MISSING'}
 $version=Join-Path $root 'version.txt'
 $manifest=Join-Path $root 'update-manifest.json'
 [IO.File]::WriteAllText($version,'1.5.18')
 [IO.File]::WriteAllText($manifest,'{"version":"1.5.18","files":[]}')
 $dll=Join-Path $root 'ReleasePolicy.dll'
 $args=@('/nologo','/target:library',('/out:'+$dll),
  '/reference:System.Windows.Forms.dll',
  ('/resource:'+$version+',RdcPayload.version.txt'),
  ('/resource:'+$manifest+',RdcPayload.update-manifest.json'),
  (Join-Path $install 'Setup.cs'),
  (Join-Path $install 'RdcReleaseInstallState.cs'),
  (Join-Path $install 'RdcReleaseMetadataSnapshot.cs'))
 $compilerResult=@(& $compiler @args 2>&1)
 Check ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($dll)) 'complete stable Setup and both release helper classes compile'
 if(-not [IO.File]::Exists($dll)){throw ('RDC_RELEASE_COMPILE_FAILED '+($compilerResult -join ' '))}
 $privateDll=Join-Path $root 'PrivateSetupTest.dll'
 $privateArgs=@('/nologo','/target:library',('/out:'+$privateDll),'/define:RDC_INSTALLER_TEST')
 $privateArgs+=@($args|Where-Object{$_ -notlike '/out:*' -and
  $_ -ne '/nologo' -and $_ -ne '/target:library'})
 $privateResult=@(& $compiler @privateArgs 2>&1)
 Check ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($privateDll)) 'private test-only installer variant compiles separately'
 if(-not [IO.File]::Exists($privateDll)){throw ('RDC_PRIVATE_TEST_BUILD_FAILED '+($privateResult -join ' '))}
 $launcherInfo=Join-Path $root 'LauncherAssembly.cs'
 [IO.File]::WriteAllText($launcherInfo,'using System.Reflection; [assembly: AssemblyVersion("1.5.18.0")]')
 $launcherDll=Join-Path $root 'PortableLauncher.dll'
 $launcherArgs=@('/nologo','/target:library',('/out:'+$launcherDll),
  '/reference:System.Windows.Forms.dll',(Join-Path $install 'Launcher.cs'),$launcherInfo)
 $launcherResult=@(& $compiler @launcherArgs 2>&1)
 Check ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($launcherDll)) 'portable launcher compiles with generated release assembly version'
 if([IO.File]::Exists($launcherDll)){
  $launcherAsm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($launcherDll))
  $company=@($launcherAsm.GetCustomAttributes([Reflection.AssemblyCompanyAttribute],$false))[0]
  Check ($company.Company -ceq 'RUBASS' -and
   $launcherAsm.GetName().Version.ToString() -ceq '1.5.18.0') 'actual portable launcher assembly has RUBASS and packaged version'
 }
 $a=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
 $policy=$a.GetType('RdcReleaseInstallState',$true)
 $setup=$a.GetType('SetupProgram',$true)
 $snap=$a.GetType('RdcReleaseMetadataSnapshot',$true)
 $stat=[Reflection.BindingFlags]'Static,NonPublic,Public'
 $instance=[Reflection.BindingFlags]'Instance,NonPublic,Public'
 $eval=$policy.GetMethod('Evaluate',$stat)
 $prompt=$policy.GetMethod('Prompt',$stat)
 $assert=$setup.GetMethod('AssertEmbeddedVersion',$stat)
 function Eval-State([bool]$registered,[string]$name,[string]$publisher,
  [string]$regVer,[string]$regRoot,[string]$diskVer,
  [bool]$gui,[bool]$updater,[bool]$files){
  $temp=Join-Path $root 'TestInstall'
  $call=New-Object 'System.Object[]' 10
  $call[0]=[bool]$registered
  $call[1]=[string]$name
  $call[2]=[string]$publisher
  $call[3]=[string]$regVer
  $call[4]=[string]$regRoot
  $call[5]=[string]$temp
  $call[6]=[string]$diskVer
  $call[7]=[bool]$gui
  $call[8]=[bool]$updater
  $call[9]=[bool]$files
  $decision=$eval.Invoke($null,$call)
  return @(
   [string]$decision.GetType().GetField('Mode',$instance).GetValue($decision),
   [string]$decision.GetType().GetField('Reason',$instance).GetValue($decision)
  )
 }
 $same=Join-Path $root 'TestInstall'
 $v=Eval-State $false '' '' '' '' '' $false $false $false
 Check ($v[0] -eq 'Fresh') 'no registration and no payload classified FRESH'
 $v=Eval-State $true 'RDC Relay' 'UMAS' '1.5.18' $same '1.5.18' $true $true $true
 Check ($v[0] -eq 'Upgrade') 'existing historical UMAS registration can upgrade safely'
 $v=Eval-State $true 'RDC Relay' 'RUBASS' '1.6.0' $same '1.6.0' $true $true $true
 Check ($v[0] -eq 'Upgrade') 'new RUBASS registration recognized after release'
 $v=Eval-State $false '' '' '' '' '' $true $true $true
 Check ($v[0] -eq 'Refuse' -and $v[1] -eq 'UNREGISTERED_PAYLOAD') 'orphan files are not mistaken for clean install'
 $v=Eval-State $true 'RDC Relay' 'UNKNOWN' '1.5.18' $same '1.5.18' $true $true $true
 Check ($v[0] -eq 'Refuse' -and $v[1] -eq 'UNKNOWN_PRODUCT') 'unknown publisher fails closed'
 $v=Eval-State $true 'Other App' 'RUBASS' '1.5.18' $same '1.5.18' $true $true $true
 Check ($v[0] -eq 'Refuse') 'foreign product with shared registry identity rejected'
 $v=Eval-State $true 'RDC Relay' 'RUBASS' '1.5.18' (Join-Path $root 'Wrong') '1.5.18' $true $true $true
 Check ($v[0] -eq 'Refuse' -and $v[1] -eq 'INSTALL_ROOT_MISMATCH') 'wrong install path fails closed'
 $v=Eval-State $true 'RDC Relay' 'UMAS' '1.5.18' $same '1.6.0' $true $true $true
 Check ($v[0] -eq 'Refuse' -and $v[1] -eq 'REGISTRY_DISK_VERSION_MISMATCH') 'registry/disk version disagreement fails closed'
 $v=Eval-State $true 'RDC Relay' 'RUBASS' '1.6.0' $same '1.6.0' $false $true $true
 Check ($v[0] -eq 'Refuse' -and $v[1] -eq 'INSTALLED_PAYLOAD_INCOMPLETE') 'missing GUI aborts upgrade'
 $v=Eval-State $true 'RDC Relay' 'RUBASS' '1.6.0' $same '1.6.0' $true $false $true
 Check ($v[0] -eq 'Refuse') 'missing updater aborts upgrade'
 $v=Eval-State $true 'RDC Relay' 'RUBASS' 'garbage' $same 'garbage' $true $true $true
 Check ($v[0] -eq 'Refuse') 'malformed installed version aborts upgrade'
 $one=New-Object 'System.Object[]' 1
 $one[0]='1.6.1'
 Check ([string]$prompt.Invoke($null,$one) -ceq
  'Установить RDC Relay 1.6.1 как основную оболочку?') 'confirmation contains only versioned target line'
 $one[0]='1.5.18'
 [void]$assert.Invoke($null,$one)
 Check $true 'embedded version matches embedded update manifest'
 $rejected=$false
 try{$one[0]='1.5.19';[void]$assert.Invoke($null,$one)}catch{$rejected=$true}
 Check $rejected 'embedded manifest/target version mismatch fails before modification'
 $desktop=Join-Path $root 'fake-desktop'
 $programs=Join-Path $root 'fake-startmenu'
 [void][IO.Directory]::CreateDirectory($desktop)
 [void][IO.Directory]::CreateDirectory($programs)
 $old=Join-Path $desktop 'RDC Relay.lnk'
 $legacy=Join-Path $programs 'Remote Desktop Commander.lnk'
 $new=Join-Path $desktop 'CommanderRelay.lnk'
 [IO.File]::WriteAllText($old,'original-primary-shortcut')
 [IO.File]::WriteAllText($legacy,'original-legacy-shortcut')
 $ctor=$snap.GetConstructor($instance,$null,[type[]]@([string],[string],[bool]),$null)
 if(-not $ctor){throw 'RDC_RELEASE_DISPOSABLE_SNAPSHOT_CTOR_NOT_FOUND'}
 $ctorArgs=New-Object 'System.Object[]' 3
 $ctorArgs[0]=[string]$desktop
 $ctorArgs[1]=[string]$programs
 $ctorArgs[2]=[bool]$false
 $snapshot=$ctor.Invoke($ctorArgs)
 [IO.File]::WriteAllText($old,'NEW RELEASE')
 [IO.File]::Delete($legacy)
 [IO.File]::WriteAllText($new,'added-in-failed-install')
 [void]$snap.GetMethod('Restore',$instance).Invoke($snapshot,@())
 Check ([IO.File]::ReadAllText($old) -ceq 'original-primary-shortcut' -and
  [IO.File]::ReadAllText($legacy) -ceq 'original-legacy-shortcut' -and
  -not [IO.File]::Exists($new)) 'actual rollback restores, recreates and removes disposable shortcuts'
 [void]$snap.GetMethod('Restore',$instance).Invoke($snapshot,@())
 Check ([IO.File]::ReadAllText($old) -ceq 'original-primary-shortcut') 'snapshot restore idempotent'
 $scriptSource=[IO.File]::ReadAllText((Join-Path $source 'remote-window.ps1'),[Text.Encoding]::UTF8)
 $build=[IO.File]::ReadAllText((Join-Path $repo 'Scripts\build-release.ps1'),[Text.Encoding]::UTF8)
 $setupSource=[IO.File]::ReadAllText((Join-Path $install 'Setup.cs'),[Text.Encoding]::UTF8)
 Check ($scriptSource.Contains("SetValue('Publisher','RUBASS'") -and
  $setupSource.Contains('SetValue("Publisher", "RUBASS"') -and
  $build.Contains('AssemblyCompany("RUBASS")')) 'release Setup, GUI registration and exe metadata all use RUBASS'
 Check ($scriptSource.Contains("Join-Path "+'$root'+ " 'version.txt'") -and
  $build.Contains('RdcPayload.version.txt') -and
  $setupSource.Contains('AssertEmbeddedVersion(newVersion)')) 'GUI and Setup derive version from packaged version.txt'
 $launcherSource=[IO.File]::ReadAllText((Join-Path $install 'Launcher.cs'),[Text.Encoding]::UTF8)
 $updaterSource=[IO.File]::ReadAllText((Join-Path $source 'update.ps1'),[Text.Encoding]::UTF8)
 Check ($launcherSource.Contains('AssemblyCompany("RUBASS")') -and
  -not $launcherSource.Contains('AssemblyCompany("UMAS")')) 'portable launcher company metadata also uses RUBASS'
 Check ($updaterSource.Contains('Sync-RdcInstalledRegistration -NewVersion') -and
  $updaterSource.Contains('Restore-RdcInstalledRegistration') -and
  $updaterSource.Contains("SetValue('DisplayVersion'") -and
  $updaterSource.Contains("SetValue('Publisher','RUBASS'")) 'stable updater synchronizes version and publisher with rollback on failure'
 $tokens=$null;$parseErrors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'update.ps1'),[ref]$tokens,[ref]$parseErrors)
 Check ($parseErrors.Count -eq 0) 'stable updater source parses after registry transaction changes'
 Check ($build.Contains('RDC_RELEASE_REFUSES_OWNER_PILOT_MARKER') -and
  $build.Contains('RDC_RELEASE_REQUIRES_MAIN_OR_STABLE_BRANCH') -and
  $build.Contains('RDC_RELEASE_REQUIRES_CLEAN_TREE') -and
  $build.Contains('RDC_RELEASE_SELFTEST_REQUIRED') -and
  $setupSource.Contains('RDC_RELEASE_UNSAFE_INSTALL_FLAGS')) 'release builder requires stable clean tree, complete tests, and no pilot marker'
 Check ($setupSource.IndexOf('metadata = new RdcReleaseMetadataSnapshot',[StringComparison]::Ordinal) -lt
  $setupSource.IndexOf('transaction.Apply();',[StringComparison]::Ordinal) -and
  $setupSource.Contains('metadata.Restore()')) 'release Setup snapshots before mutation and requests metadata rollback after failure'
}catch{
 $fail++
 Write-Output ('FAIL RELEASE_POLICY_TEST_EXCEPTION '+$_.Exception.Message)
}finally{
 if([IO.Directory]::Exists($root)) {
  if([IO.Path]::GetFileName($root) -notmatch '^RDC-REL-POLICY-[a-f0-9]{32}$' -or
   [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($root)).TrimEnd([char]92) -cne
    [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)) {
   Write-Output ('NOT CLEAN DISPOSABLE_PATH_REFUSED '+$root);$fail++
  }else{[IO.Directory]::Delete($root,$true)}
 }
}
Write-Output ('RC1_RELEASE_INSTALL_POLICY_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0