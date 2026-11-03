# F1 adversarial tests for actual G0 packer; never launch any installer/Remote.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Scripts\rc1-package-integrity.ps1')
$source=Join-Path $root 'dist\v1.6.0-RC1-BLOCKED-PREFLIGHT'
$preflightZip=Join-Path $root 'dist\RDCRelay-1.6.0-RC1-BLOCKED-PREFLIGHT.zip'
$packer=Join-Path $root 'Scripts\pack-rc1-preflight.ps1'
$pass=0;$fail=0
function Test([bool]$ok,[string]$label) {
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Denied([scriptblock]$action){
 try{& $action | Out-Null;return $false}
 catch{return $true}
}
$proof=Get-Rc1PreflightProof -Folder $source -ArchivePath $preflightZip
Test ($proof.Files -eq 7 -and $proof.Digests.Count -eq 6) 'existing G0 manifest/archive exact set'
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$id=[guid]::NewGuid().ToString('N')
$fixture=Join-Path $temp ('RDC-RC1-F1-'+$id)
if([IO.Directory]::Exists($fixture) -or [IO.File]::Exists($fixture)){throw 'Test root collision'}
$stage=Join-Path $fixture 'stage'
[void][IO.Directory]::CreateDirectory($stage)
$marker=Join-Path $stage 'rc1-preflight-manifest.json'
$valid=[IO.File]::ReadAllBytes((Join-Path $source 'rc1-preflight-manifest.json'))
try{
 foreach($name in $script:Rc1RequiredAll){[IO.File]::Copy((Join-Path $source $name),(Join-Path $stage $name))}
 Test (-not (Denied {Get-Rc1PreflightProof -Folder $stage})) 'fixture valid'
 $model=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
 $model.files[1]=$model.files[0]
 [IO.File]::WriteAllText($marker,($model|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
 Test (Denied {Get-Rc1PreflightProof -Folder $stage}) 'duplicate manifest record replaces mandatory entry'
 $priorPreference=$ErrorActionPreference
 $ErrorActionPreference='Continue'
 try{$output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packer -FixtureRoot $fixture 2>&1);$packerExit=$LASTEXITCODE}
 finally{$ErrorActionPreference=$priorPreference}
 Test ($LASTEXITCODE -ne 0 -and -not [IO.File]::Exists((Join-Path $fixture 'proof-only.zip'))) 'duplicate manifest: nonzero packer, no trusted ZIP'
 [IO.File]::WriteAllBytes($marker,$valid)
 $model=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
 $model.files[1].sha256=$null
 [IO.File]::WriteAllText($marker,($model|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
 Test (Denied {Get-Rc1PreflightProof -Folder $stage}) 'missing SHA256 rejected'
 $priorPreference=$ErrorActionPreference
 $ErrorActionPreference='Continue'
 try{$output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packer -FixtureRoot $fixture 2>&1);$packerExit=$LASTEXITCODE}
 finally{$ErrorActionPreference=$priorPreference}
 Test ($LASTEXITCODE -ne 0 -and -not [IO.File]::Exists((Join-Path $fixture 'proof-only.zip'))) 'missing digest: packer nonzero'
 [IO.File]::WriteAllBytes($marker,$valid)
 $changed=Join-Path $stage 'RdcOwnerProcess.cs'
 [IO.File]::AppendAllText($changed,([Environment]::NewLine+'// altered fixture'))
 Test (Denied {Get-Rc1PreflightProof -Folder $stage}) 'modified mandatory member rejected'
 $priorPreference=$ErrorActionPreference
 $ErrorActionPreference='Continue'
 try{$output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packer -FixtureRoot $fixture 2>&1);$packerExit=$LASTEXITCODE}
 finally{$ErrorActionPreference=$priorPreference}
 Test ($LASTEXITCODE -ne 0 -and -not [IO.File]::Exists((Join-Path $fixture 'proof-only.zip'))) 'altered bytes: packer nonzero'
 [IO.File]::Copy((Join-Path $source 'RdcOwnerProcess.cs'),$changed,$true)
 [IO.File]::WriteAllText((Join-Path $stage 'extra.txt'),'unlisted')
 Test (Denied {Get-Rc1PreflightProof -Folder $stage}) 'extra staged file rejected'
 [IO.File]::Delete((Join-Path $stage 'extra.txt'))
 $priorPreference=$ErrorActionPreference
 $ErrorActionPreference='Continue'
 try{$output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packer -FixtureRoot $fixture 2>&1);$packerExit=$LASTEXITCODE}
 finally{$ErrorActionPreference=$priorPreference}
 Test ($LASTEXITCODE -eq 0 -and [IO.File]::Exists((Join-Path $fixture 'proof-only.zip'))) 'valid disposable fixture packer creates ZIP'
 $arch=Join-Path $fixture 'proof-only.zip'
 Test (-not (Denied {Get-Rc1PreflightProof -Folder $stage -ArchivePath $arch})) 'generated ZIP matches all manifest digests'
 Test (Denied {Assert-Rc1ExactNames @('RdcOwnerProcess.dll','RdcOwnerProcess.dll') $script:Rc1RequiredPayload 'negative'}) 'duplicate name rejected'
 Test (Denied {Assert-Rc1ExactNames @('rdcownerprocess.dll') @('RdcOwnerProcess.dll') 'negative'}) 'wrong case name rejected'
 Test (Denied {Assert-Rc1ExactNames @('../RdcOwnerProcess.dll') @('RdcOwnerProcess.dll') 'negative'}) 'path traversal name rejected'
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 foreach($case in @('unexpected','duplicate')){
  $badZip=Join-Path $fixture ($case+'.zip')
  $fs=[IO.File]::Open($badZip,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
   $zip=New-Object IO.Compression.ZipArchive -ArgumentList @($fs,[IO.Compression.ZipArchiveMode]::Create,$true)
   try{
    foreach($name in $script:Rc1RequiredAll){
     [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $stage $name),$name,[IO.Compression.CompressionLevel]::Optimal)
    }
    $entryName=if($case -eq 'unexpected'){'intruder.cs'}else{'RdcOwnerProcess.cs'}
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $stage 'RdcOwnerProcess.cs'),$entryName,[IO.Compression.CompressionLevel]::Optimal)
   }finally{$zip.Dispose()}
  }finally{$fs.Dispose()}
  Test (Denied {Get-Rc1PreflightProof -Folder $stage -ArchivePath $badZip}) ($case+' ZIP member rejected')
 }
}finally{
 $known=@('stage','proof-only.zip','unexpected.zip','duplicate.zip')
 if([IO.Directory]::Exists($fixture)){
  [void](Assert-Rc1PathTree $fixture)
  $entries=@([IO.Directory]::GetFileSystemEntries($fixture))
  if(@($entries|Where-Object{$known -cnotcontains [IO.Path]::GetFileName($_)}).Count){throw 'NOT CLEAN unexpected test root entry'}
  foreach($entry in $entries){[void](Assert-Rc1PathTree $entry)}
  if([IO.Directory]::Exists($stage)){
   $files=@([IO.Directory]::GetFileSystemEntries($stage))
   if(@($files|Where-Object{$script:Rc1RequiredAll -cnotcontains [IO.Path]::GetFileName($_)}).Count){throw 'NOT CLEAN unexpected staging entry'}
  }
  [IO.Directory]::Delete($fixture,$true)
 }
}
Write-Output ('RC1_F1_NEGATIVE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
