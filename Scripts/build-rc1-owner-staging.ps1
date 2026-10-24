# 1.6.0 RC1 product SOURCE staging / full UI asset manifest, NOT installable.
# Never starts any candidate/installer/Remote, writes only a new ignored dist path.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$branch=(git -C $root branch --show-current).Trim()
if($branch -cne 'feature/v1.6-host-gui-owner-pilot'){throw 'REFUSED wrong RC1 branch'}
$gate=Get-Content -LiteralPath (Join-Path $src 'rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($gate.candidate -cne '1.6.0 RC1' -or $gate.installable -ne $false -or
  $gate.liveRemoteEnabled -ne $false -or $gate.autoUpdateEnabled -ne $false -or
  $gate.publishable -ne $false){throw 'REFUSED nonblocked candidate marker'}
$dist=Join-Path $root 'dist'
$out=Join-Path $dist 'v1.6.0-RC1-PRODUCT-SOURCE-NOT-INSTALLABLE'
$zipPath=Join-Path $dist 'RDCRelay-1.6.0-RC1-PRODUCT-SOURCE-NOT-INSTALLABLE.zip'
if([IO.Directory]::Exists($out) -or [IO.File]::Exists($out) -or [IO.File]::Exists($zipPath)){
 throw 'REFUSED existing owner-stage output; no implicit overwrite'
}
$names=@(
 'remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerProcess.cs',
 'rc1-candidate.json','RDCRelay.ico',
 'divider-caustic.ps','divider-caustic-detail.ps',
 'divider-particles.ps','divider-particles-core.ps',
 'update-notice.ps1','update.ps1'
)
if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'Duplicate source allowlist'}
foreach($name in $names){
 $sourcePath=Join-Path $src $name
 if(-not [IO.File]::Exists($sourcePath) -or
    ([IO.File]::GetAttributes($sourcePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw ('REFUSED missing/reparse source file '+$name)
 }
}
$test=Join-Path $root 'Tests\Test-V16ProductHostGuiSource.ps1'
$proof=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $test 2>&1)
$code=$LASTEXITCODE
if($code -ne 0 -or ($proof -join ' ') -notmatch 'RC1_PRODUCT_SOURCE_PASS=19 FAIL=0'){
 throw ('REFUSED: static original-GUI Host source test failed '+$code)
}
$compiler=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
 (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
if(-not $compiler){throw 'NOT CHECKED: no .NET Framework compiler'}
[void](New-Item -ItemType Directory -Path $out -ErrorAction Stop)
$payloadDir=Join-Path $out 'Source'
[void](New-Item -ItemType Directory -Path $payloadDir -ErrorAction Stop)
foreach($name in $names){Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $payloadDir $name) -ErrorAction Stop}
$dll=Join-Path $out 'RdcOwnerRuntime.dll'
& $compiler /nologo /target:library ('/out:'+$dll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $payloadDir 'RdcOwnerWire.cs') (Join-Path $payloadDir 'RdcOwnerRuntime.cs')
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){throw 'RC1 Host/IPC compile failed; output is NOT INSTALLABLE'}
foreach($p in @(
 @{Out='RC1 BLOCKED - Launcher.exe';File='Launcher.cs'},
 @{Out='RC1 BLOCKED - Setup.exe';File='Setup.cs'}
)){
 $target=Join-Path $out $p.Out
 & $compiler /nologo /target:winexe /optimize+ /define:RDC_RC1_BLOCKED /reference:System.Windows.Forms.dll ('/out:'+$target) (Join-Path (Join-Path $root 'Installer') $p.File)
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($target)){throw ('RC1 guarded compile failed '+$p.Out)}
}
$relative=@($names|ForEach-Object{'Source/'+$_})+@('RdcOwnerRuntime.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe')
$manifestEntries=@()
foreach($member in $relative){
 $p=Join-Path $out $member
 $manifestEntries+= [ordered]@{name=$member;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash;bytes=[IO.FileInfo]$p|Select-Object -ExpandProperty Length}
}
$manifest=[ordered]@{
 candidate='1.6.0 RC1';kind='PRODUCT_SOURCE_REVIEW_ONLY';
 installable=$false;publishable=$false;liveRemoteEnabled=$false;autoUpdateEnabled=$false;
 ownerGuiUsesOriginalSource=$true;
 note='Host fake-only; actual Remote ownership and full Exit awaiting authorized trials';
 files=$manifestEntries
}
$manifestPath=Join-Path $out 'owner-source-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
$all=@($relative)+@('owner-source-manifest.json')
$actual=@(Get-ChildItem -LiteralPath $out -Recurse -File -Force|ForEach-Object{$_.FullName.Substring($out.Length+1).Replace('\','/')})
if($actual.Count -ne $all.Count -or @($actual|Where-Object{$all -cnotcontains $_}).Count){throw 'REFUSED source package entries differ from manifest'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$fs=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
 $zip=New-Object IO.Compression.ZipArchive -ArgumentList @($fs,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($n in $all){
   [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $out $n),$n,[IO.Compression.CompressionLevel]::Optimal)
  }
 }finally{$zip.Dispose()}
}finally{$fs.Dispose()}
$check=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 $entries=@($check.Entries);$entryNames=@($entries|ForEach-Object{$_.FullName})
 if($entries.Count -ne $all.Count -or @($entryNames|Select-Object -Unique).Count -ne $all.Count -or
  @($entryNames|Where-Object{$all -cnotcontains $_}).Count){throw 'REFUSED ZIP exact set invalid'}
 foreach($entry in $entries){
  $sha=[Security.Cryptography.SHA256]::Create();$s=$entry.Open()
  try{$h=[BitConverter]::ToString($sha.ComputeHash($s)).Replace('-','')}
  finally{$s.Dispose();$sha.Dispose()}
  if($h -cne (Get-FileHash -LiteralPath (Join-Path $out $entry.FullName) -Algorithm SHA256).Hash){
   throw ('REFUSED archive digest mismatch '+$entry.FullName)
  }
 }
}finally{$check.Dispose()}
Write-Output ('RC1_PRODUCT_SOURCE_MEMBERS='+$all.Count)
Write-Output ('RC1_PRODUCT_SOURCE_ZIP_SHA256='+(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash)
Write-Output ('RC1_PRODUCT_SOURCE_ZIP_BYTES='+(Get-Item -LiteralPath $zipPath).Length)
Write-Output 'RC1_PRODUCT_SOURCE_NOT_INSTALLABLE=TRUE'
