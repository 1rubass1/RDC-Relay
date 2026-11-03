# RC1 G0 preflight archive: intentionally not installable.
# No product installer, real Remote, stable update feed or release operations.
param([string]$FixtureRoot='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'rc1-package-integrity.ps1')
$dist=Join-Path $root 'dist'
$folder=Join-Path $dist 'v1.6.0-RC1-BLOCKED-PREFLIGHT'
$dest=Join-Path $dist 'RDCRelay-1.6.0-RC1-BLOCKED-PREFLIGHT.zip'
if($FixtureRoot){
 # Only an explicitly isolated, directly under-TEMP GUID fixture is accepted.
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
 $fixture=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd([char]92)
 if(-not [String]::Equals([IO.Path]::GetDirectoryName($fixture),$temp,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($fixture) -cnotmatch '^RDC-RC1-F1-[0-9a-f]{32}$'){
  throw 'REFUSED: fixture must be the single verified TEMP/RDC-RC1-F1-GUID root'
 }
 $folder=Join-Path $fixture 'stage'
 $dest=Join-Path $fixture 'proof-only.zip'
}
if([IO.File]::Exists($dest) -or [IO.Directory]::Exists($dest)){
 throw 'REFUSED: preflight output already exists; do not overwrite'
}
[void](Assert-Rc1PathTree $folder)
[void](Assert-Rc1PathTree (Split-Path -Parent $dest))
$proof=Get-Rc1PreflightProof -Folder $folder
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
# Write to a unique private incomplete entry; publish only AFTER validating every
# ZIP record against each SHA-256 attested by the exact-set manifest.
$stageZip=$dest+'.incomplete-'+[guid]::NewGuid().ToString('N')
$created=$false
try {
 $handle=[IO.File]::Open($stageZip,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try {
  $zip=New-Object IO.Compression.ZipArchive -ArgumentList @($handle,[IO.Compression.ZipArchiveMode]::Create,$true)
  try {
   foreach($name in $script:Rc1RequiredAll){
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip,(Join-Path $folder $name),$name,[IO.Compression.CompressionLevel]::Optimal)
   }
  }finally{$zip.Dispose()}
 }finally{$handle.Dispose()}
 $proof=Get-Rc1PreflightProof -Folder $folder -ArchivePath $stageZip
 if([IO.File]::Exists($dest)){throw 'REFUSED: output target appeared during validation'}
 [IO.File]::Move($stageZip,$dest)
 $created=$true
}finally{
 if(-not $created -and [IO.File]::Exists($stageZip)){
  # Only this invocation's known incomplete path, not an existing artifact.
  [IO.File]::Delete($stageZip)
 }
}
Write-Output ('RC1_PREFLIGHT_ZIP='+$dest)
Write-Output ('RC1_PREFLIGHT_ZIP_SHA256='+(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash)
Write-Output ('RC1_PREFLIGHT_ZIP_BYTES='+(Get-Item -LiteralPath $dest).Length)
Write-Output ('RC1_PREFLIGHT_ZIP_MEMBERS='+$proof.Files+' MATCHED=ALL')
Write-Output 'RC1_PILOT_NOT_INSTALLABLE=TRUE'
