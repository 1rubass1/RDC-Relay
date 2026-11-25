# Isolated *review-only* 1.6.0 full Host/GUI source package.
# Never creates a Setup, launcher, installed app, shortcuts or registry keys.
# It does not execute any Host, GUI, Remote, installer or update script.
param([switch]$Build)
$ErrorActionPreference='Stop'
if(-not $Build){Write-Output 'RDC_V16_REVIEW_BUILDER_INERT_USE_BUILD';exit 42}
$repo=Split-Path -Parent $PSScriptRoot
$branch=(& git -C $repo branch --show-current)
if($LASTEXITCODE -ne 0 -or $branch.Trim() -cne 'fix/rc1-tray-exit-prompt'){
 throw 'RDC_V16_REVIEW_WRONG_TOPIC_BRANCH'
}
$dirty=@(& git -C $repo status --porcelain --untracked-files=normal)
if($LASTEXITCODE -ne 0 -or @($dirty|Where-Object{$_}).Count -ne 0){
 throw 'RDC_V16_REVIEW_REQUIRES_CLEAN_SOURCE'
}
$head=(& git -C $repo rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $head -notmatch '^[a-f0-9]{40}$'){
 throw 'RDC_V16_REVIEW_HEAD_UNKNOWN'
}
$src=Join-Path $repo 'Source'
$assetIcon=Join-Path $repo 'Assets\RDCRelay.ico'
$approvedIcon='5FF100E2AB72453E081AF5C0157BAF41C8BCA57130C4CC42C8BDE9C612FCF1DC'
$approvedTray='64A4009133FFB5B7CC89BD71D85B37BA2897EE5C7A715BC3C3C014625CEC3B23'
foreach($path in @($assetIcon,(Join-Path $src 'RDCRelay.ico'))){
 if(-not [IO.File]::Exists($path) -or
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $approvedIcon){
  throw 'RDC_V16_REVIEW_ICON_NOT_APPROVED'
 }
}
if((Get-FileHash -LiteralPath (Join-Path $src 'RdcTrayV04.bin') -Algorithm SHA256).Hash -cne $approvedTray){
 throw 'RDC_V16_REVIEW_TRAY_NOT_APPROVED'
}
# These names must be *exactly* the C# contract's fixed package members.
# No rc1-candidate.json, legacy launcher, external desktop shortcut or setup.
$required=@(
 'Source/remote-window.ps1','Source/rc1-tray-host.ps1',
 'Source/rc1-owner-gui.ps1','Source/rc1-remote-observer.ps1',
 'Source/rc1-quota-client.ps1','Source/RdcOwnerWire.cs',
 'Source/RdcOwnerRuntime.cs','Source/RdcOwnerProcess.cs',
 'Source/RdcOwnerTicketStore.cs','Source/RdcOwnerRemoteState.cs',
 'Source/RdcOwnerManagedProcess.cs','Source/RdcOwnerLogParts.cs','Source/RdcOwnerStartup.cs','Source/RdcUiLanguage.cs',
 'Source/lang/ru-RU.json','Source/lang/en-US.json',
 'Source/RDCRelay.ico','Source/RdcTrayV04.bin',
 'Source/divider-caustic.ps','Source/divider-caustic-detail.ps',
 'Source/divider-particles.ps','Source/divider-particles-core.ps',
 'Source/update-notice.ps1','Source/update.ps1',
 'Source/version.txt','Source/release-review.json','RdcOwnerRuntime.dll'
)
$contract=Join-Path $repo 'Installer\RdcReleaseReviewPackage.cs'
$stage=Join-Path $repo 'Installer\RdcReleaseDurableStage.cs'
$types=@(Add-Type -Path @($contract,$stage) -ReferencedAssemblies @(
 'System.Core.dll','System.Web.Extensions.dll','System.dll') -PassThru -ErrorAction Stop)
$reviewType=@($types|Where-Object{$_.Name -ceq 'RdcReleaseReviewPackage'})|Select-Object -First 1
$stageType=@($types|Where-Object{$_.Name -ceq 'RdcReleaseDurableStage'})|Select-Object -First 1
if(!$reviewType -or !$stageType){throw 'RDC_V16_REVIEW_COMPILER_TYPES_MISSING'}
$binding=[Reflection.BindingFlags]'Static,NonPublic,Public'
$fromCode=@($reviewType.GetField('Required',$binding).GetValue($null))
if($fromCode.Count -ne $required.Count -or
   @($required|Where-Object{$fromCode -cnotcontains $_}).Count -ne 0){
 throw 'RDC_V16_REVIEW_BUILD_CONTRACT_DRIFT'
}
$compiler=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
 (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'))|
 Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
if(-not $compiler){throw 'RDC_V16_REVIEW_CSC_NOT_FOUND'}
function Check-Path([string]$path) {
 $cursor=[IO.Path]::GetFullPath($path)
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'RDC_V16_REVIEW_REPARSE_REFUSED'
   }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if(-not $parent -or $parent -ceq $cursor){break}
  $cursor=$parent
 }
}
$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
Check-Path $temporary
$buildId=[Guid]::NewGuid().ToString('N')
$output=Join-Path $temporary ('RDC-V16-REVIEW-'+$buildId)
if([IO.Directory]::Exists($output) -or [IO.File]::Exists($output)){throw 'RDC_V16_REVIEW_ROOT_COLLISION'}
$package=Join-Path $output 'package'
$payload=Join-Path $package 'payload'
[void][IO.Directory]::CreateDirectory($payload)
$copyNames=@($required|Where-Object{$_ -notin @('Source/version.txt','Source/release-review.json','RdcOwnerRuntime.dll')})
foreach($name in $copyNames){
 $from=Join-Path $repo ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
 $to=Join-Path $payload ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
 Check-Path $from
 Check-Path $to
 if(-not [IO.File]::Exists($from)){throw ('RDC_V16_REVIEW_SOURCE_MISSING '+$name)}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
 [IO.File]::Copy($from,$to,$false)
}
# The review ZIP must be inert even when a user manually runs a .ps1.
# Insert a throw into copies only; never modify or execute repository Source.
# A separate review marker remains visible for tooling and future validation.
foreach($name in @('remote-window.ps1','rc1-tray-host.ps1','rc1-quota-client.ps1','update.ps1')){
 $path=Join-Path $payload ('Source\'+$name)
 $bytes=[IO.File]::ReadAllBytes($path)
 $hasBom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
  $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
 $content=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
 $needle=if($content.Contains('$ErrorActionPreference=''Stop''')){
  '$ErrorActionPreference=''Stop'''
 }else{'$ErrorActionPreference = ''Stop'''}
 $index=$content.IndexOf($needle,[StringComparison]::Ordinal)
 if($index -lt 0 -or $content.IndexOf($needle,$index+1,[StringComparison]::Ordinal) -ge 0){
  throw ('RDC_V16_REVIEW_SCRIPT_ENTRYPOINT_UNEXPECTED '+$name)
 }
 $insert=$index+$needle.Length
 $revised=$content.Substring(0,$insert)+
  [Environment]::NewLine+"throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'"+
  $content.Substring($insert)
 [IO.File]::WriteAllText($path,$revised,(New-Object Text.UTF8Encoding([bool]$hasBom)))
}
# A release-review version is generated; repository's stable 1.5.18 version
# and blocked pilot marker remain UNMODIFIED.
[IO.File]::WriteAllText((Join-Path $payload 'Source\version.txt'),
 '1.6.0'+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
$reviewMarker=[ordered]@{
 kind='FULL_HOST_GUI_SOURCE_REVIEW_ONLY';version='1.6.0';
 installable=$false;launchEnabled=$false
}
[IO.File]::WriteAllText((Join-Path $payload 'Source\release-review.json'),
 ($reviewMarker|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
$dll=Join-Path $payload 'RdcOwnerRuntime.dll'
$sourceCode=@(
 'RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs',
 'RdcOwnerRuntime.cs'
)|ForEach-Object{Join-Path $payload ('Source\'+$_)}
$arguments=@('/nologo','/target:library',('/out:'+$dll),
 '/reference:System.Core.dll','/reference:System.Web.Extensions.dll',
 '/reference:System.Security.dll','/reference:System.Windows.Forms.dll',
 '/reference:System.Drawing.dll','/reference:System.Management.dll')+$sourceCode
$diagnostic=@(& $compiler @arguments 2>&1)
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){
 $safe=@($diagnostic|Select-Object -First 8|ForEach-Object{[string]$_})
 throw ('RDC_V16_REVIEW_HOST_COMPILE_FAILED '+($safe -join '|'))
}
$rows=@()
foreach($name in $required){
 $path=Join-Path $payload ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
 Check-Path $path
 $info=Get-Item -LiteralPath $path -Force
 if(-not $info -or $info.Length -le 0){throw ('RDC_V16_REVIEW_EMPTY_MEMBER '+$name)}
 $rows += [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();bytes=[long]$info.Length}
}
$manifest=[ordered]@{
 schema=1;kind='FULL_HOST_GUI_SOURCE_REVIEW_ONLY';version='1.6.0';publisher='RUBASS';
 installable=$false;publishable=$false;launchEnabled=$false;files=$rows
}
[IO.File]::WriteAllText((Join-Path $package 'review-manifest.json'),
 ($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
$verify=$reviewType.GetMethod('Validate',$binding)
if(!$verify){throw 'RDC_V16_REVIEW_VERIFY_METHOD_MISSING'}
$checked=$verify.Invoke($null,[object[]]@([string]$package))
if($checked.Count -ne $required.Count){throw 'RDC_V16_REVIEW_VALIDATION_MEMBER_COUNT'}
# A review bundle must NOT be installable through the durable stage.
# Production Setup will package unguarded, audited release files with an
# embedded trusted manifest; this candidate must fail the stage preflight.
$planMethod=$stageType.GetMethod('Plan',[Reflection.BindingFlags]'NonPublic,Static')
if($null -eq $planMethod){throw 'RDC_V16_REVIEW_STAGE_PLAN_MISSING'}
$argumentsForPlan=New-Object object[] 2
$argumentsForPlan[0]=$checked
$argumentsForPlan[1]=$null
$denied=$false
try{[void]$planMethod.Invoke($null,$argumentsForPlan)}
catch{
 # PowerShell may wrap the reflected IOException as MethodInvocationException
 # before the CLR TargetInvocationException reaches this catch.
 $cause=$_.Exception
 while($null -ne $cause){
  if($cause.Message -ceq 'RDC_STAGE_REVIEW_MARKER_REFUSED'){
   $denied=$true;break
  }
  $cause=$cause.InnerException
 }
 if(-not $denied){throw}
}
if(-not $denied){throw 'RDC_V16_REVIEW_UNSAFE_STAGE_ACCEPTANCE'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipPath=Join-Path $output 'RDC-Relay-1.6.0-FullHostGui-REVIEW.zip'
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
 $zip=New-Object IO.Compression.ZipArchive -ArgumentList @($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($name in @($required|ForEach-Object{'payload/'+$_})+@('review-manifest.json')){
   [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,
    (Join-Path $package ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))),
    $name,[IO.Compression.CompressionLevel]::Optimal)
  }
 }finally{$zip.Dispose()}
}finally{$stream.Dispose()}
$reader=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 $expected=@($required|ForEach-Object{'payload/'+$_})+@('review-manifest.json')
 $actual=@($reader.Entries|ForEach-Object{$_.FullName})
 if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -cnotcontains $_}).Count -ne 0){
  throw 'RDC_V16_REVIEW_ZIP_MEMBER_MISMATCH'
 }
 foreach($entry in $reader.Entries){
  $sourcePath=Join-Path $package ($entry.FullName.Replace('/',[IO.Path]::DirectorySeparatorChar))
  $h=[Security.Cryptography.SHA256]::Create()
  $input=$entry.Open()
  try{$digest=[BitConverter]::ToString($h.ComputeHash($input)).Replace('-','')}
  finally{$input.Dispose();$h.Dispose()}
  if($digest -cne (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash){
   throw ('RDC_V16_REVIEW_ZIP_HASH_MISMATCH '+$entry.FullName)
  }
 }
}finally{$reader.Dispose()}
# Verifier is outside the payload ZIP (no executable/hash self-reference).
# The standalone console is read-only and refuses to install/launch.
$verifier=Join-Path $output 'RDC-Relay-1.6.0-Offline-Review-Check.exe'
$checkerSource=Join-Path $repo 'Installer\RdcReleaseReviewVerifier.cs'
$checkerArguments=@('/nologo','/target:exe','/optimize+',
 '/main:RdcReleaseReviewVerifier',('/out:'+$verifier),
 '/reference:System.Core.dll','/reference:System.Web.Extensions.dll')+
 @($contract,$stage,$checkerSource)
$checkerDiagnostics=@(& $compiler @checkerArguments 2>&1)
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($verifier)){
 $safe=@($checkerDiagnostics|Select-Object -First 8|ForEach-Object{[string]$_})
 throw ('RDC_V16_REVIEW_CHECKER_COMPILE_FAILED '+($safe -join '|'))
}
$exeVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($verifier)
if($exeVersion.FileVersion -cne '1.6.0.0' -or $exeVersion.CompanyName -cne 'RUBASS'){
 throw 'RDC_V16_REVIEW_VERIFIER_VERSION_OR_COMPANY_INVALID'
}
Write-Output ('RDC_V16_REVIEW_SOURCE_COMMIT='+$head)
Write-Output ('RDC_V16_REVIEW_PACKAGE='+$package)
Write-Output ('RDC_V16_REVIEW_ZIP='+$zipPath)
Write-Output ('RDC_V16_REVIEW_CHECKER='+$verifier)
Write-Output ('RDC_V16_REVIEW_ZIP_SHA256='+(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash)
Write-Output ('RDC_V16_REVIEW_MEMBERS='+$required.Count)
Write-Output 'RDC_V16_REVIEW_BUILD_PASS=1'
Write-Output 'RDC_V16_NOT_INSTALLABLE_NOT_LAUNCHABLE=TRUE'
