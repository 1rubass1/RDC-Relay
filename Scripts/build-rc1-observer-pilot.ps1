# Build a separately identified, owner-only 1.6.0 RC1 OBSERVER Setup + Portable.
# This command NEVER executes Setup, Launcher, GUI or Desktop Commander Remote.
param([switch]$Build)
$ErrorActionPreference='Stop'
if(-not $Build){Write-Output 'RC1_OBSERVER_BUILD_INERT_USE_BUILD';exit 42}
$repo=Split-Path -Parent $PSScriptRoot
if((git -C $repo branch --show-current).Trim() -cne 'feature/v1.6-host-gui-owner-pilot'){
 throw 'RC1_WRONG_FEATURE_BRANCH'
}
$src=Join-Path $repo 'Source'
$marker=Get-Content -LiteralPath (Join-Path $src 'rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($marker.candidate -cne '1.6.0 RC1' -or $marker.installable -ne $false -or
 $marker.publishable -ne $false -or $marker.autoUpdateEnabled -ne $false){
 throw 'RC1_SOURCE_MUST_REMAIN_BLOCKED'
}
$names=@(
 'remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'rc1-remote-observer.ps1','RdcOwnerWire.cs','RdcOwnerRuntime.cs',
 'RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs',
 'rc1-candidate.json','RDCRelay.ico','divider-caustic.ps',
 'divider-caustic-detail.ps','divider-particles.ps','divider-particles-core.ps',
 'update-notice.ps1','update.ps1'
)
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
$stage=Join-Path $dist ('RDCRelay-1.6.0-RC1-ObserverPilot-'+[Guid]::NewGuid().ToString('N'))
$package=Join-Path $stage 'package'
$payload=Join-Path $package 'Source'
[void][IO.Directory]::CreateDirectory($payload)
foreach($name in $names){
 [IO.File]::Copy((Join-Path $src $name),(Join-Path $payload $name),$false)
}
# Only this disposable candidate gets an installable marker. Repository's
# source guard stays blocked; stable updater and public publication stay off.
$pilot=[ordered]@{
 candidate='1.6.0 RC1';stableTarget='1.6.0';
 status='OWNER_OBSERVER_PILOT';installable=$true;publishable=$false;
 liveRemoteEnabled=$true;observerMode='OBSERVED_READ_ONLY_RC1';
 stableManifestEnabled=$false;autoUpdateEnabled=$false;
 accountMutationEnabled=$false;remoteStopEnabled=$false;
 remoteLaunchEnabled=$false;separateOwnerApprovalRequired=$false;
 reason='User-approved private side-by-side read-only attachment to existing pinned Remote'
}
[IO.File]::WriteAllText((Join-Path $payload 'rc1-candidate.json'),
 ($pilot|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
$dll=Join-Path $package 'RdcOwnerRuntime.dll'
& $compiler /nologo /target:library ('/out:'+$dll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $payload 'RdcOwnerWire.cs') (Join-Path $payload 'RdcOwnerProcess.cs') (Join-Path $payload 'RdcOwnerTicketStore.cs') (Join-Path $payload 'RdcOwnerRemoteState.cs') (Join-Path $payload 'RdcOwnerRuntime.cs')
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){throw 'RC1_PILOT_RUNTIME_COMPILE_FAILED'}
$launcher=Join-Path $package 'RC1 Pilot Launcher.exe'
& $compiler /nologo /target:winexe /optimize+ /reference:System.Core.dll /reference:System.Web.Extensions.dll ('/out:'+$launcher) (Join-Path $repo 'Installer\Rc1CandidateLauncher.cs')
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($launcher)){throw 'RC1_PILOT_LAUNCHER_COMPILE_FAILED'}
$required=@($names|ForEach-Object{'Source/'+$_})+@('RdcOwnerRuntime.dll','RC1 Pilot Launcher.exe')
$rows=@()
foreach($n in $required){
 $f=Join-Path $package $n;Check-Path $f
 $rows += [ordered]@{name=$n;sha256=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
}
$manifest=[ordered]@{
 candidate='1.6.0 RC1';kind='PRIVATE_OBSERVER_PILOT';
 installable=$true;publishable=$false;observerMode='OBSERVED_READ_ONLY_RC1';
 files=$rows
}
$manifestFile=Join-Path $package 'owner-source-manifest.json'
[IO.File]::WriteAllText($manifestFile,($manifest|ConvertTo-Json -Depth 10),
 (New-Object Text.UTF8Encoding($false)))
$setup=Join-Path $package 'RC1 Pilot Setup.exe'
& $compiler /nologo /target:winexe /optimize+ /reference:System.Core.dll /reference:System.Web.Extensions.dll ('/out:'+$setup) (Join-Path $repo 'Installer\Rc1CandidateSetup.cs')
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($setup)){throw 'RC1_PILOT_SETUP_COMPILE_FAILED'}
# Source manifest is exact. Setup itself remains a separate distributable.
$actual=@(Get-ChildItem -LiteralPath $package -Recurse -File -Force|
 ForEach-Object{$_.FullName.Substring($package.Length+1).Replace('\','/')})
$expected=@($required)+@('owner-source-manifest.json','RC1 Pilot Setup.exe')
if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -cnotcontains $_}).Count -gt 0){
 throw 'RC1_PILOT_EXACT_STAGE_MEMBERS_MISMATCH'
}
foreach($row in $rows){
 if((Get-FileHash -LiteralPath (Join-Path $package $row.name) -Algorithm SHA256).Hash -cne $row.sha256){
  throw 'RC1_PILOT_STAGE_SHA_MISMATCH'
 }
}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$portable=Join-Path $stage 'RDCRelay-1.6.0-RC1-Observer-Portable.zip'
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
 if($members.Count -ne ($required.Count+1)){throw 'RC1_PILOT_PORTABLE_MEMBERS'}
 foreach($entry in $members){
  $sha=[Security.Cryptography.SHA256]::Create();$stream=$entry.Open()
  try{$digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
  finally{$stream.Dispose();$sha.Dispose()}
  if($digest -cne (Get-FileHash -LiteralPath (Join-Path $package $entry.FullName) -Algorithm SHA256).Hash){
   throw ('RC1_PILOT_PORTABLE_HASH_MISMATCH '+$entry.FullName)
  }
 }
}finally{$verify.Dispose()}
Write-Output ('RC1_PILOT_PACKAGE='+$package)
Write-Output ('RC1_PILOT_SETUP='+$setup)
Write-Output ('RC1_PILOT_PORTABLE='+$portable)
Write-Output ('RC1_PILOT_SETUP_SHA256='+(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash)
Write-Output ('RC1_PILOT_PORTABLE_SHA256='+(Get-FileHash -LiteralPath $portable -Algorithm SHA256).Hash)
Write-Output ('RC1_PILOT_PAYLOAD_MEMBERS='+$required.Count)
Write-Output 'RC1_PILOT_PREPARED_NOT_INSTALLED=TRUE'