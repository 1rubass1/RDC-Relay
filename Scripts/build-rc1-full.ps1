# Build a separately identified full owner-Host/GUI 1.6.0 RC1 Setup + Portable.
# This command NEVER executes Setup, Launcher, GUI or Desktop Commander Remote.
param([switch]$Build,[switch]$ReleaseQualification,[string]$QualificationVersion="1.6.0",[switch]$PublicPreflight)
$ErrorActionPreference='Stop'
if(-not $Build){Write-Output 'RC1_FULL_BUILD_INERT_USE_BUILD';exit 42}
if($PublicPreflight -and !$ReleaseQualification){throw 'V16_PUBLIC_PREFLIGHT_REQUIRES_NUMERIC_BUILD'}
$repo=Split-Path -Parent $PSScriptRoot
$branch=(git -C $repo branch --show-current).Trim()
if($branch -cne 'feature/v1.6-host-gui-owner-pilot' -and
   $branch -cne 'feature/rc1-tray-v04-gui-reactivation' -and
   $branch -cne 'feature/rc1-update-width-help-align' -and
   $branch -cne 'feature/rc1-version-text-up1' -and
   $branch -cne 'feature/rc1-russian-header-state' -and
   $branch -cne 'feature/rc1-header-capsule-indicator' -and
   $branch -cne 'feature/rc1-capsule-bottom-up2-shift15' -and
   $branch -cne 'feature/rc1-capsule-header-right1' -and
   $branch -cne 'feature/rc1-banner-leftcol-top2' -and
   $branch -cne 'feature/rc1-banner-two-blank-columns' -and
   $branch -cne 'fix/rc1-stale-ready-link-health' -and
   $branch -cne 'fix/rc1-portable-double-click' -and
   $branch -cne 'fix/rc1-utf8-stream-events' -and
   $branch -cne 'fix/rc1-portable-onedrive-desktop' -and
   $branch -cne 'fix/rc1-self-contained-regressions' -and
   $branch -cne 'fix/rc1-r2-readiness-proof' -and
   $branch -cne 'fix/rc1-r3-observer-partial-stream' -and
   $branch -cne 'fix/rc1-r3-buffered-observer-lines' -and
   $branch -cne 'fix/rc1-tray-exit-prompt' -and
   !($branch -ceq 'integration/v1.6.0-replacement' -and $ReleaseQualification -and $QualificationVersion -ceq '1.6.0')){
 throw 'RC1_WRONG_FEATURE_BRANCH'
}
$src=Join-Path $repo 'Source'
# The base desktop/installer icon remains separately approved. The Host now
# uses the distinct, attested tray v04 state bundle loaded at runtime.
$approvedIconSha='5FF100E2AB72453E081AF5C0157BAF41C8BCA57130C4CC42C8BDE9C612FCF1DC'
foreach($icon in @((Join-Path $repo 'Assets\RDCRelay.ico'),(Join-Path $src 'RDCRelay.ico'))){
 if(-not [IO.File]::Exists($icon) -or
   (Get-FileHash -Algorithm SHA256 -LiteralPath $icon).Hash -cne $approvedIconSha){
  throw 'RC1_APPROVED_APP_ICON_V04_MISMATCH'
 }
}
$approvedTraySha='64A4009133FFB5B7CC89BD71D85B37BA2897EE5C7A715BC3C3C014625CEC3B23'
$trayBundle=Join-Path $src 'RdcTrayV04.bin'
if(-not [IO.File]::Exists($trayBundle) -or
   (Get-FileHash -LiteralPath $trayBundle -Algorithm SHA256).Hash -cne $approvedTraySha){
 throw 'RC1_APPROVED_TRAY_V04_MISMATCH'
}
$marker=Get-Content -LiteralPath (Join-Path $src 'rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
. (Join-Path $PSScriptRoot 'rc1-version-contract.ps1')
$candidateVersion=[string](Assert-Rc1CandidateVersionContract -SourceDirectory $src -InstallerDirectory (Join-Path $repo 'Installer'))
if($candidateVersion -cne '1.6.0 RC1' -or $marker.installable -ne $false -or
 $marker.publishable -ne $false -or $marker.autoUpdateEnabled -ne $false){
 throw 'RC1_SOURCE_MUST_REMAIN_BLOCKED'
}
$names=@(
 'remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'rc1-remote-observer.ps1','rc1-quota-client.ps1','RdcOwnerWire.cs','RdcOwnerRuntime.cs',
 'RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs',
 'RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs',
 'lang/ru-RU.json','lang/en-US.json',
 'rc1-candidate.json','RDCRelay.ico','RdcTrayV04.bin','divider-caustic.ps',
 'divider-caustic-detail.ps','divider-particles.ps','divider-particles-core.ps',
 'update-notice.ps1','update.ps1'
)
# Numeric Full Host packages never contain the retired flat updater.
if($ReleaseQualification){$names=@($names|Where-Object {$_ -cne 'update.ps1'})}
function Check-Path([string]$path){
 $cursor=[IO.Path]::GetFullPath($path)
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'RC1_BUILD_REPARSE_DENIED'
   }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if(-not $parent -or $parent -ceq $cursor){break}
  $cursor=$parent
 }
}
if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'RC1_DUPLICATE_ALLOWLIST'}
foreach($name in $names){
 $f=Join-Path $src $name;Check-Path $f
 if(-not [IO.File]::Exists($f)){throw ('RC1_REQUIRED_SOURCE_MISSING '+$name)}
}
$compiler=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
 (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|
 Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
if(-not $compiler){throw 'RC1_NO_NET_FRAMEWORK_COMPILER'}
$dist=Join-Path $repo 'dist'
Check-Path $dist
if(-not [IO.Directory]::Exists($dist)){[void][IO.Directory]::CreateDirectory($dist)}
if($QualificationVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or [Version]$QualificationVersion -lt [Version]'1.6.0' -or (!$ReleaseQualification -and $QualificationVersion -cne '1.6.0')){throw 'V16_QUALIFICATION_VERSION'}
$prefix=if($PublicPreflight){'RDCRelay-'+$QualificationVersion+'-PublicPreflight-'}elseif($ReleaseQualification){'RDCRelay-'+$QualificationVersion+'-Qualification-'}else{'RDCRelay-1.6.0-RC1-Full-'}
$stage=Join-Path $dist ($prefix+[Guid]::NewGuid().ToString('N'))
$package=Join-Path $stage 'package'
$payload=Join-Path $package 'Source'
[void][IO.Directory]::CreateDirectory($payload)
foreach($name in $names){
 $destination=Join-Path $payload $name
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
 [IO.File]::Copy((Join-Path $src $name),$destination,$false)
}
$installerBuild=Join-Path $repo 'Installer'
$identityAssembly=@()
$packageKind='PRIVATE_FULL_RC1'
if($ReleaseQualification){
 $installerBuild=Join-Path $stage 'build-source'
 [void][IO.Directory]::CreateDirectory($installerBuild)
 foreach($file in @('Rc1CandidateSetup.cs','Rc1CandidateLauncher.cs','Rc1ManualUpgrade.cs','RdcNodePrerequisite.cs')){
  [IO.File]::Copy((Join-Path $repo ('Installer/'+$file)),(Join-Path $installerBuild $file),$false)
 }
 [IO.File]::Copy((Join-Path $src 'THIRD_PARTY_NOTICES.txt'),(Join-Path $payload 'THIRD_PARTY_NOTICES.txt'),$false)
 . (Join-Path $PSScriptRoot 'v16-release-identity.ps1')
 Set-RdcV16QualificationIdentity -Payload $payload -InstallerStage $installerBuild -version $QualificationVersion
 $names+=@('version.txt','THIRD_PARTY_NOTICES.txt')
 $candidateVersion=$QualificationVersion
 $packageKind=if($PublicPreflight){'FULL_HOST_GUI_V16_PUBLIC'}else{'FULL_HOST_GUI_V16_QUALIFICATION'}
 $assemblyInfo=Join-Path $installerBuild 'AssemblyInfo.cs'
 [IO.File]::WriteAllText($assemblyInfo,'[assembly:System.Reflection.AssemblyCompany("RUBASS")][assembly:System.Reflection.AssemblyProduct("RDC Relay")][assembly:System.Reflection.AssemblyVersion("'+$QualificationVersion+'.0")][assembly:System.Reflection.AssemblyFileVersion("'+$QualificationVersion+'.0")]',(New-Object Text.UTF8Encoding($false)))
 $identityAssembly=@($assemblyInfo)
}
$setupOnlySources=@()
if($ReleaseQualification){
 $setupOnlySources=@((Join-Path $repo 'Installer\RdcReleaseLegacyMigrationLease.cs'),(Join-Path $repo 'Installer\RdcV16MetadataTransaction.cs'),(Join-Path $repo 'Installer\RdcV16IntegratedMaintenance.cs'))
 if($PublicPreflight){
  . (Join-Path $PSScriptRoot 'v16-public-identity.ps1')
  $setupOnlySources=@(Set-RdcV16PublicIdentity -Payload $payload -InstallerStage $installerBuild -SetupSources $setupOnlySources)
 }
}
# Only this disposable candidate gets an installable marker. Repository's
# source guard stays blocked; stable updater and public publication stay off.
$pilot=[ordered]@{
 candidate=$candidateVersion;stableTarget=[string]$marker.stableTarget;
 status=$(if($PublicPreflight){'PUBLIC_RELEASE'}elseif($ReleaseQualification){'RELEASE_QUALIFICATION'}else{'OWNER_FULL_RC1'});installable=$true;publishable=[bool]$PublicPreflight;
 liveRemoteEnabled=$true;ownerMode='FULL_HOST_GUI_RC1';
 stableManifestEnabled=$false;autoUpdateEnabled=$false;
 accountMutationEnabled=$true;remoteStopEnabled=$true;
 remoteLaunchEnabled=$true;separateOwnerApprovalRequired=$false;
 reason='Owner-confirmed logout and new pairing only for Host-owned Remote; existing Remote remains Adopted read-only'
}
[IO.File]::WriteAllText((Join-Path $payload 'rc1-candidate.json'),
 ($pilot|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
$dll=Join-Path $package 'RdcOwnerRuntime.dll'
& $compiler /nologo /target:library ('/out:'+$dll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll (Join-Path $payload 'RdcOwnerWire.cs') (Join-Path $payload 'RdcOwnerProcess.cs') (Join-Path $payload 'RdcOwnerTicketStore.cs') (Join-Path $payload 'RdcOwnerRemoteState.cs') (Join-Path $payload 'RdcOwnerManagedProcess.cs') (Join-Path $payload 'RdcOwnerLogParts.cs') (Join-Path $payload 'RdcOwnerStartup.cs') (Join-Path $payload 'RdcUiLanguage.cs') (Join-Path $payload 'RdcOwnerRuntime.cs')
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){throw 'RC1_FULL_RUNTIME_COMPILE_FAILED'}
$launcherName=if($PublicPreflight){'RDC Relay.exe'}else{'RC1 Pilot Launcher.exe'}
$launcher=Join-Path $package $launcherName
& $compiler /nologo /target:winexe /optimize+ ('/win32icon:'+(Join-Path $payload 'RDCRelay.ico')) /reference:System.Core.dll /reference:System.Web.Extensions.dll ('/out:'+$launcher) /reference:System.Windows.Forms.dll (Join-Path $installerBuild 'Rc1CandidateLauncher.cs') (Join-Path $installerBuild 'RdcNodePrerequisite.cs') (Join-Path $payload 'RdcOwnerStartup.cs') @identityAssembly
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($launcher)){throw 'RC1_FULL_LAUNCHER_COMPILE_FAILED'}
$required=@($names|ForEach-Object{'Source/'+$_})+@('RdcOwnerRuntime.dll',$launcherName)
$rows=@()
foreach($n in $required){
 $f=Join-Path $package $n;Check-Path $f
 $rows += [ordered]@{name=$n;sha256=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
}
$manifest=[ordered]@{
 candidate=$candidateVersion;kind=$packageKind;
 installable=$true;publishable=[bool]$PublicPreflight;ownerMode='FULL_HOST_GUI_RC1';
 files=$rows
}
$manifestFile=Join-Path $package 'owner-source-manifest.json'
[IO.File]::WriteAllText($manifestFile,($manifest|ConvertTo-Json -Depth 10),
 (New-Object Text.UTF8Encoding($false)))
$setupName=if($PublicPreflight){'RDC.Relay.Setup.v'+$QualificationVersion+'.exe'}else{'RC1 Pilot Setup.exe'}
$setup=Join-Path $package $setupName
# Keep the published Setup.exe independently downloadable: all validated
# runtime files and the exact source manifest live inside its PE resources.
$resourceArgs=@(@($required)+@('owner-source-manifest.json')|
 ForEach-Object{('/resource:'+(Join-Path $package $_)+',RdcPayload.'+$_.Replace('/','.'))})
& $compiler /nologo /target:winexe /optimize+ /define:RDC_RC1_FULL_SETUP ('/win32icon:'+(Join-Path $payload 'RDCRelay.ico')) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Management.dll ('/out:'+$setup) $resourceArgs /reference:System.Windows.Forms.dll (Join-Path $installerBuild 'Rc1CandidateSetup.cs') (Join-Path $installerBuild 'RdcNodePrerequisite.cs') (Join-Path $installerBuild 'Rc1ManualUpgrade.cs') (Join-Path $payload 'RdcOwnerStartup.cs') (Join-Path $payload 'RdcUiLanguage.cs') @identityAssembly @setupOnlySources
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($setup)){throw 'RC1_FULL_SETUP_COMPILE_FAILED'}
# Source manifest is exact. Setup itself remains a separate distributable.
$actual=@(Get-ChildItem -LiteralPath $package -Recurse -File -Force|
 ForEach-Object{$_.FullName.Substring($package.Length+1).Replace('\','/')})
$expected=@($required)+@('owner-source-manifest.json',$setupName)
if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -cnotcontains $_}).Count -gt 0){
 throw 'RC1_FULL_EXACT_STAGE_MEMBERS_MISMATCH'
}
foreach($row in $rows){
 if((Get-FileHash -LiteralPath (Join-Path $package $row.name) -Algorithm SHA256).Hash -cne $row.sha256){
  throw 'RC1_FULL_STAGE_SHA_MISMATCH'
 }
}
# Verify the *compiled PE native icon*, not just an embedded payload file.
# Uses Windows icon extraction and exact pixels from the 32px ICO PNG frame.
# It never executes Setup, Launcher, Host, GUI or Remote.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $repo 'Tests\Test-V16AppIconV04.ps1') -SetupPath $setup -LauncherPath $launcher
if($LASTEXITCODE -ne 0){throw 'RC1_FULL_NATIVE_APP_ICON_V04_FAILED'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$portableName=if($PublicPreflight){'RDC.Relay.v'+$QualificationVersion+'.Portable.zip'}elseif($ReleaseQualification){'RDCRelay-'+$QualificationVersion+'-Qualification-Portable.zip'}else{'RDCRelay-1.6.0-RC1-Full-Portable.zip'}
$portable=Join-Path $stage $portableName
$fs=[IO.File]::Open($portable,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
 $zip=New-Object IO.Compression.ZipArchive -ArgumentList @($fs,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($member in @($required)+@('owner-source-manifest.json')){
   [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,
    (Join-Path $package $member),$member,[IO.Compression.CompressionLevel]::Optimal)
  }
 }finally{$zip.Dispose()}
}finally{$fs.Dispose()}
$verify=[IO.Compression.ZipFile]::OpenRead($portable)
try{
 $members=@($verify.Entries)
 if($members.Count -ne ($required.Count+1)){throw 'RC1_FULL_PORTABLE_MEMBERS'}
 foreach($entry in $members){
  $sha=[Security.Cryptography.SHA256]::Create();$stream=$entry.Open()
  try{$digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
  finally{$stream.Dispose();$sha.Dispose()}
  if($digest -cne (Get-FileHash -LiteralPath (Join-Path $package $entry.FullName) -Algorithm SHA256).Hash){
   throw ('RC1_FULL_PORTABLE_HASH_MISMATCH '+$entry.FullName)
  }
 }
}finally{$verify.Dispose()}
Write-Output ('RC1_FULL_PACKAGE='+$package)
Write-Output ('RC1_FULL_SETUP='+$setup)
Write-Output ('RC1_FULL_PORTABLE='+$portable)
Write-Output ('RC1_FULL_SETUP_SHA256='+(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash)
Write-Output ('RC1_FULL_PORTABLE_SHA256='+(Get-FileHash -LiteralPath $portable -Algorithm SHA256).Hash)
Write-Output ('RC1_FULL_PAYLOAD_MEMBERS='+$required.Count)
Write-Output 'RC1_FULL_PREPARED_NOT_INSTALLED=TRUE'
if($ReleaseQualification){
 foreach($exe in @($setup,$launcher)){
  $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
  if($info.FileVersion -cne ($QualificationVersion+'.0') -or $info.CompanyName -cne 'RUBASS'){throw 'RDC_V16_QUALIFICATION_PE_VERSION'}
 }
 Write-Output ('RDC_V16_QUALIFICATION_NUMERIC_VERSION='+$QualificationVersion)
 if($PublicPreflight){Write-Output 'RDC_V16_PUBLIC_PREFLIGHT_ONLY_NO_PUBLICATION=TRUE'}else{Write-Output 'RDC_V16_QUALIFICATION_NOT_PUBLISHABLE=TRUE'}
}