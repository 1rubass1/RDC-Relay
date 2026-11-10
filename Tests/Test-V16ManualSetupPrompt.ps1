# G111: source-derived install confirmation and build-version contract.
# Disposable compilation and fictitious Desktop paths only; no Setup.Main,
# real installation, Host, Remote, network, account or shortcut changes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$src=Join-Path $repo 'Source'
$installer=Join-Path $repo 'Installer'
$builder=Join-Path $repo 'Scripts\build-rc1-full.ps1'
$contractFile=Join-Path $repo 'Scripts\rc1-version-contract.ps1'
$passed=0;$failed=0
function Check([bool]$result,[string]$label) {
 if($result){$script:passed++;Write-Output ('PASS '+$label)}
 else{$script:failed++;Write-Output ('FAIL '+$label)}
}
. $contractFile
$actual=Assert-Rc1CandidateVersionContract -SourceDirectory $src -InstallerDirectory $installer
Check ($actual -ceq '1.6.0 RC1') 'current builder version is sourced from official candidate marker'
$builderText=[IO.File]::ReadAllText($builder,[Text.Encoding]::UTF8)
Check ($builderText.Contains('Assert-Rc1CandidateVersionContract') -and
 $builderText.Contains('candidate=$candidateVersion') -and
 $builderText.Contains('RC1_SOURCE_MUST_REMAIN_BLOCKED')) 'builder requires version contract before creating both payload and embedded manifest'
$setupText=[IO.File]::ReadAllText((Join-Path $installer 'Rc1CandidateSetup.cs'),[Text.Encoding]::UTF8)
$manualText=[IO.File]::ReadAllText((Join-Path $installer 'Rc1ManualUpgrade.cs'),[Text.Encoding]::UTF8)
$guard=$setupText.IndexOf('if(args.Length==0 && HasPrimaryDesktopShortcut(desktop))',[StringComparison]::Ordinal)
$prompt=$setupText.IndexOf('"Установить RDC Relay "+version+" как основную оболочку?"',[StringComparison]::Ordinal)
$validation=$setupText.IndexOf('ValidateSource(source);',[StringComparison]::Ordinal)
$activate=$setupText.IndexOf('RdcRc1ManualUpgrade.ActivateDesktop(release,local,desktop)',[StringComparison]::Ordinal)
Check ($validation -gt 0 -and $validation -lt $guard -and $guard -lt $prompt -and $prompt -lt $activate) 'short upgrade question only after verified embedded payload and existing-shortcut check'
Check ($setupText.Contains('MessageBoxDefaultButton.Button2') -and
 $setupText.Contains('if(answer!=System.Windows.Forms.DialogResult.Yes)return 1;') -and
 -not $setupText.Contains('Файлы рабочей 1.5.18 останутся для отката.')) 'one-line confirmation defaults No and drops old diagnostic paragraph'
Check ($manualText.Contains('bool firstInstall=!HasPrimaryDesktopShortcut(desktop)') -and
 $setupText.Contains('return RdcRc1ManualUpgrade.HasPrimaryDesktopShortcut(desktop)')) 'prompt and shortcut activation share the exact same first-install criterion'
Check ($setupText.Contains('RC1_MANIFEST_CANDIDATE_VERSION_MISMATCH')) 'installer refuses mismatch between embedded manifest and included candidate identity'
$work=Join-Path ([IO.Path]::GetTempPath()) ('RdcSetupPrompt-'+[Guid]::NewGuid().ToString('N'))
$sourceCopy=Join-Path $work 'Source'
$installerCopy=Join-Path $work 'Installer'
$desktop=Join-Path $work 'Desktop'
$exeDll=Join-Path $work 'SetupProbe.dll'
try {
 foreach($dir in @($work,$sourceCopy,$installerCopy,$desktop)){
  [void][IO.Directory]::CreateDirectory($dir)
 }
 foreach($f in @('rc1-candidate.json','remote-window.ps1','rc1-owner-gui.ps1')){
  [IO.File]::Copy((Join-Path $src $f),(Join-Path $sourceCopy $f),$false)
 }
 foreach($f in @('Rc1CandidateSetup.cs','Rc1CandidateLauncher.cs')){
  [IO.File]::Copy((Join-Path $installer $f),(Join-Path $installerCopy $f),$false)
 }
 function Contract-Error([string]$expected){
  try{
   [void](Assert-Rc1CandidateVersionContract -SourceDirectory $sourceCopy -InstallerDirectory $installerCopy)
   return $false
  }catch{
   return $_.Exception.Message.Contains($expected)
  }
 }
 $originalMarker=[IO.File]::ReadAllText((Join-Path $sourceCopy 'rc1-candidate.json'),[Text.Encoding]::UTF8)
 [IO.File]::WriteAllText((Join-Path $sourceCopy 'rc1-candidate.json'),
  $originalMarker.Replace('1.6.0 RC1','1.6.1 RC2'),(New-Object Text.UTF8Encoding($false)))
 Check (Contract-Error 'RC1_BUILD_GUI_VERSION_MISMATCH') 'changed candidate marker versus actual GUI version FAILS builder contract'
 [IO.File]::WriteAllText((Join-Path $sourceCopy 'rc1-candidate.json'),$originalMarker,(New-Object Text.UTF8Encoding($false)))
 foreach($item in @(
  @('remote-window.ps1',$sourceCopy,'RC1_BUILD_GUI_VERSION_MISMATCH'),
  @('rc1-owner-gui.ps1',$sourceCopy,'RC1_BUILD_OWNER_HELLO_VERSION_MISMATCH'),
  @('Rc1CandidateLauncher.cs',$installerCopy,'RC1_BUILD_LAUNCHER_VERSION_MISMATCH'),
  @('Rc1CandidateSetup.cs',$installerCopy,'RC1_BUILD_SETUP_VERSION_MISMATCH')
 )){
  $f=Join-Path $item[1] $item[0]
  $original=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($f,$original.Replace('1.6.0 RC1','1.6.1 RC2'),
    (New-Object Text.UTF8Encoding($false)))
  Check (Contract-Error $item[2]) ('tampered '+$item[0]+' version FAILS the builder contract')
  [IO.File]::WriteAllText($f,$original,(New-Object Text.UTF8Encoding($false)))
 }
 $compiler=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|
  Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
 if(-not $compiler){throw 'NO_CSC_FOR_G111_TEST'}
 $args=@('/nologo','/target:library',('/out:'+$exeDll),
  '/reference:System.Core.dll','/reference:System.Web.Extensions.dll',
  '/reference:System.Management.dll','/reference:System.Windows.Forms.dll',
  (Join-Path $installer 'Rc1CandidateSetup.cs'),
  (Join-Path $installer 'Rc1ManualUpgrade.cs'))
 $buildOutput=@(& $compiler @args 2>&1)
 Check ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($exeDll)) 'real production Setup and shortcut-switch code compile in disposable library'
 if(-not [IO.File]::Exists($exeDll)){throw ('SETUP_COMPILE_REFUSED '+($buildOutput -join ' '))}
 $assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exeDll))
 $type=$assembly.GetType('RdcRc1CandidateSetup',$true)
 $flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
 $shortcut=$type.GetMethod('HasPrimaryDesktopShortcut',$flags)
 $version=$type.GetMethod('ValidatedCandidateDisplayVersion',$flags)
 if(-not $shortcut -or -not $version){throw 'ACTUAL_SETUP_PROBE_METHOD_NOT_FOUND'}
 $desktopArgs=New-Object 'System.Object[]' 1
 $desktopArgs[0]=[string]$desktop
 Check (-not [bool]$shortcut.Invoke($null,$desktopArgs)) 'genuine Setup returns FIRST INSTALL when primary shortcut absent'
 [IO.File]::WriteAllText((Join-Path $desktop 'Unrelated.lnk'),'fake')
 Check (-not [bool]$shortcut.Invoke($null,$desktopArgs)) 'unrelated file does not trigger upgrade confirmation'
 [IO.File]::WriteAllText((Join-Path $desktop 'RDC Relay.lnk'),'fake only, no COM')
 Check ([bool]$shortcut.Invoke($null,$desktopArgs)) 'genuine Setup detects existing primary shortcut for confirmation'
 [IO.File]::Delete((Join-Path $desktop 'RDC Relay.lnk'))
 Check (-not [bool]$shortcut.Invoke($null,$desktopArgs)) 'removing primary shortcut returns to fresh-install state'
 $manifestArgs=New-Object 'System.Object[]' 1
 $manifestArgs[0]=[string]$work
 $manifestFile=Join-Path $work 'owner-source-manifest.json'
 [IO.File]::WriteAllText($manifestFile,'{"candidate":"1.6.0 RC1"}')
 Check ([string]$version.Invoke($null,$manifestArgs) -ceq '1.6.0 RC1') 'compiled Setup displays version from embedded-manifest format'
 [IO.File]::WriteAllText($manifestFile,'{"candidate":"1.6.1 RC2"}')
 Check ([string]$version.Invoke($null,$manifestArgs) -ceq '1.6.1 RC2') 'future RC2 label follows manifest automatically, no hardcoded warning number'
 [IO.File]::WriteAllText($manifestFile,'{"candidate":"garbage"}')
 $bad=$false
 try{[void]$version.Invoke($null,$manifestArgs)}catch{
  $bad=([string]$_.Exception.InnerException.Message).Contains('RC1_DISPLAY_VERSION_INVALID')
 }
 Check $bad 'bad version metadata fails closed instead of displaying false version'
}finally{
 if([IO.Directory]::Exists($work)){[IO.Directory]::Delete($work,$true)}
}
Write-Output ('RC1_MANUAL_SETUP_PROMPT_PASS='+$passed+' FAIL='+$failed)
if($failed){exit 1}
exit 0