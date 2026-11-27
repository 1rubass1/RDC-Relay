# Rebuild the public architecture from the selected source tree.
# Feed manifests are NEVER rewritten by this command.
param([switch]$Build)
$ErrorActionPreference='Stop'
if(!$Build){throw 'RDC_PUBLIC_BUILD_REQUIRES_BUILD'}
$repo=Split-Path -Parent $PSScriptRoot
$full=Join-Path $repo 'FullHost'
$src=Join-Path $full 'Source'
$inst=Join-Path $full 'Installer'
$identity=[IO.File]::ReadAllText((Join-Path $full 'verified-package-manifest.json'))|ConvertFrom-Json
$v=[IO.File]::ReadAllText((Join-Path $src 'version.txt')).Trim()
if($v -cnotmatch '^\d+\.\d+\.\d+$' -or [Version]$v -lt [Version]'1.6.0' -or $identity.candidate -cne $v -or $identity.kind -cne 'FULL_HOST_GUI_V16_PUBLIC' -or !$identity.publishable){throw 'PUBLIC_BUILD_IDENTITY'}
$runtime=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs')
$sourceNames=@('remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1','rc1-remote-observer.ps1','rc1-quota-client.ps1')+$runtime+@('lang/ru-RU.json','lang/en-US.json','rc1-candidate.json','RDCRelay.ico','RdcTrayV04.bin','divider-caustic.ps','divider-caustic-detail.ps','divider-particles.ps','divider-particles-core.ps','update-notice.ps1','version.txt','THIRD_PARTY_NOTICES.txt')
$members=@($sourceNames|ForEach-Object{'Source/'+$_})+@('RdcOwnerRuntime.dll','RDC Relay.exe')
if($identity.files.Count -ne $members.Count -or @($identity.files.name|Select-Object -Unique).Count -ne $members.Count -or @($identity.files.name|Where-Object{$members -cnotcontains $_}).Count){throw 'PUBLIC_BUILD_ALLOWLIST'}
function Safe($path){
 for($p=[IO.Path]::GetFullPath($path);$p;$p=[IO.Path]::GetDirectoryName($p)){
  if((Test-Path -LiteralPath $p) -and ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint)){throw 'PUBLIC_BUILD_REPARSE'}
 }
}
$dist=Join-Path $repo 'dist';Safe $dist
$stage=Join-Path $dist ('RDCRelay-'+$v+'-Rebuild-'+[Guid]::NewGuid().ToString('N'))
$package=Join-Path $stage 'package'
[void][IO.Directory]::CreateDirectory($package)
foreach($n in $sourceNames){
 $p=Join-Path $src $n;Safe $p
 $row=@($identity.files|Where-Object name -ceq ('Source/'+$n))
 if($row.Count -ne 1 -or (Get-FileHash -LiteralPath $p).Hash -cne $row[0].sha256){throw ('PUBLIC_BUILD_SOURCE_HASH '+$n)}
 $dst=Join-Path $package ('Source/'+$n)
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
 [IO.File]::Copy($p,$dst,$false)
}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path -LiteralPath $compiler)){throw 'PUBLIC_BUILD_COMPILER'}
$icon=Join-Path $src 'RDCRelay.ico'
$runtimeDll=Join-Path $package 'RdcOwnerRuntime.dll'
& $compiler /nologo /target:library ('/out:'+$runtimeDll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll @($runtime|ForEach-Object{Join-Path $src $_})
if($LASTEXITCODE -ne 0){throw 'PUBLIC_BUILD_RUNTIME'}
$launcher=Join-Path $package 'RDC Relay.exe'
& $compiler /nologo /target:winexe /optimize+ ('/win32icon:'+$icon) /reference:System.Core.dll /reference:System.Web.Extensions.dll ('/out:'+$launcher) (Join-Path $inst 'Rc1CandidateLauncher.cs') (Join-Path $src 'RdcOwnerStartup.cs') (Join-Path $inst 'AssemblyInfo.cs')
if($LASTEXITCODE -ne 0){throw 'PUBLIC_BUILD_LAUNCHER'}
$rows=@(foreach($n in $members){[ordered]@{name=$n;sha256=(Get-FileHash -LiteralPath (Join-Path $package $n)).Hash}})
$m=[ordered]@{candidate=$v;kind='FULL_HOST_GUI_V16_PUBLIC';installable=$true;publishable=$true;ownerMode='FULL_HOST_GUI_RC1';files=$rows}
$mp=Join-Path $package 'owner-source-manifest.json'
[IO.File]::WriteAllText($mp,($m|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
$setup=Join-Path $package ('RDC.Relay.Setup.v'+$v+'.exe')
$resourceArgs=@(@($members)+@('owner-source-manifest.json')|ForEach-Object{('/resource:'+(Join-Path $package $_)+',RdcPayload.'+$_.Replace('/','.'))})
$setupSrc=@('Rc1CandidateSetup.cs','Rc1ManualUpgrade.cs','AssemblyInfo.cs','RdcReleaseLegacyMigrationLease.cs','RdcV16MetadataTransaction.cs','RdcV16IntegratedMaintenance.cs')|ForEach-Object{Join-Path $inst $_}
& $compiler /nologo /target:winexe /optimize+ /define:RDC_RC1_FULL_SETUP ('/win32icon:'+$icon) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Management.dll ('/out:'+$setup) @resourceArgs @setupSrc (Join-Path $src 'RdcOwnerStartup.cs') (Join-Path $src 'RdcUiLanguage.cs')
if($LASTEXITCODE -ne 0){throw 'PUBLIC_BUILD_SETUP'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipPath=Join-Path $stage ('RDC.Relay.v'+$v+'.Portable.zip')
$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($n in @($members)+@('owner-source-manifest.json')){[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $package $n),$n,[IO.Compression.CompressionLevel]::Optimal)}}finally{$zip.Dispose()}
# The package's actual source and embedded resources must agree before
# any output is considered for release review.
$binding=[Reflection.BindingFlags]'Static,NonPublic,Public'
$sa=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($setup))
$la=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($launcher))
[void]$sa.GetType('RdcRc1CandidateSetup',$true).GetMethod('ValidateSource',$binding).Invoke($null,@([string]$package))
[void]$la.GetType('RdcRc1CandidateLauncher',$true).GetMethod('ValidatePortablePackage',$binding).Invoke($null,@([string]$package))
if($sa.GetManifestResourceNames().Count -ne ($members.Count+1)){throw 'PUBLIC_BUILD_RESOURCE_SCOPE'}
foreach($n in @($members)+@('owner-source-manifest.json')){
 $f=$sa.GetManifestResourceStream('RdcPayload.'+$n.Replace('/','.'))
 if(!$f){throw 'PUBLIC_BUILD_RESOURCE_MISSING'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$h=[BitConverter]::ToString($sha.ComputeHash($f)).Replace('-','')}finally{$sha.Dispose();$f.Dispose()}
 if($h -cne (Get-FileHash -LiteralPath (Join-Path $package $n)).Hash){throw 'PUBLIC_BUILD_RESOURCE_HASH'}
}
'PUBLIC_REBUILD_PACKAGE='+$package
'PUBLIC_REBUILD_SETUP_SHA256='+(Get-FileHash -LiteralPath $setup).Hash
'PUBLIC_REBUILD_PORTABLE_SHA256='+(Get-FileHash -LiteralPath $zipPath).Hash
'PUBLIC_REBUILD_PASS'
'NO_FEED_MUTATION_OR_PUBLICATION=TRUE'
