# G0 only: package the already compiled, explicitly noninstallable RC1 proof.
# No release tags, manifest feed publication, stable updater or install action.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dist=Join-Path $root 'dist'
$folder=Join-Path $dist 'v1.6.0-RC1-BLOCKED-PREFLIGHT'
$dest=Join-Path $dist 'RDCRelay-1.6.0-RC1-BLOCKED-PREFLIGHT.zip'
if([IO.File]::Exists($dest)){throw 'REFUSED: existing RC1 archive; never overwrite an unverified artifact'}
if(-not [IO.Directory]::Exists($folder)){throw 'REFUSED: no verified RC1 preflight folder'}
$manifestPath=Join-Path $folder 'rc1-preflight-manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.candidate -cne '1.6.0 RC1' -or $manifest.channel -cne 'NONINSTALLABLE_PREFLIGHT' -or
 $manifest.installable -ne $false -or $manifest.publishable -ne $false -or $manifest.realRemoteEnabled -ne $false){
 throw 'REFUSED: preflight is not explicitly noninstallable'
}
$allowed=@('RdcOwnerProcess.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe',
 'RdcOwnerProcess.cs','rc1-candidate.json','V1-6-0-OWNER-PILOT.md')
$expected=@($allowed)+@('rc1-preflight-manifest.json')
$actual=@([IO.Directory]::GetFileSystemEntries($folder))
if($actual.Count -ne $expected.Count -or @($manifest.files).Count -ne $allowed.Count){
 throw 'REFUSED: unexpected preflight package files/count'
}
foreach($entry in $actual){
 $name=[IO.Path]::GetFileName($entry)
 $attrs=[IO.File]::GetAttributes($entry)
 if($expected -cnotcontains $name -or
   ($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
   ($attrs -band [IO.FileAttributes]::Directory) -ne 0){throw ('REFUSED: unknown or redirected entry '+$name)}
}
foreach($entry in @($manifest.files)){
 if($allowed -cnotcontains [string]$entry.name){throw 'REFUSED: unlisted hash entry'}
 $f=Join-Path $folder $entry.name
 if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -cne [string]$entry.sha256){
  throw ('REFUSED: source member changed after compilation '+$entry.name)
 }
}
# No standalone stable Setup or Updater may appear in the archive. The two
# compiled Windows executables return 42 under RDC_RC1_BLOCKED, never install.
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$handle=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
 $zip=New-Object IO.Compression.ZipArchive -ArgumentList @($handle,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($name in $expected){
   [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $folder $name),$name,[IO.Compression.CompressionLevel]::Optimal)
  }
 }finally{$zip.Dispose()}
}finally{$handle.Dispose()}
$check=[IO.Compression.ZipFile]::OpenRead($dest)
try{
 $items=@($check.Entries)
 if($items.Count -ne $expected.Count){throw 'REFUSED: ZIP entry count mismatch'}
 foreach($item in $items){
  if($expected -cnotcontains $item.FullName){throw 'REFUSED: unknown ZIP content'}
  $stream=$item.Open();$sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
  if($hash -cne (Get-FileHash -LiteralPath (Join-Path $folder $item.FullName) -Algorithm SHA256).Hash){
   throw ('REFUSED: ZIP/member mismatch '+$item.FullName)
  }
 }
}finally{$check.Dispose()}
Write-Output ('RC1_PREFLIGHT_ZIP='+$dest)
Write-Output ('RC1_PREFLIGHT_ZIP_SHA256='+(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash)
Write-Output ('RC1_PREFLIGHT_ZIP_BYTES='+(Get-Item -LiteralPath $dest).Length)
Write-Output ('RC1_PREFLIGHT_ZIP_MEMBERS='+$expected.Count+' MATCHED=ALL')
Write-Output 'RC1_PILOT_NOT_INSTALLABLE=TRUE'
