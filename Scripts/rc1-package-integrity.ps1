# RDC Relay 1.6 RC1 G0 package integrity verification. Pure file inspection;
# never runs the candidate, any installer, any user process or Remote.
$script:Rc1RequiredPayload=@(
 'RdcOwnerProcess.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe',
 'RdcOwnerProcess.cs','rc1-candidate.json','V1-6-0-OWNER-PILOT.md'
)
$script:Rc1RequiredAll=@($script:Rc1RequiredPayload)+@('rc1-preflight-manifest.json')
function Assert-Rc1PathTree([string]$Path) {
 $full=[IO.Path]::GetFullPath($Path)
 $cursor=$full
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw ('REFUSED: reparse component '+$cursor)
   }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if(-not $parent -or $parent -ceq $cursor){break}
  $cursor=$parent
 }
 return $full
}
function Assert-Rc1ExactNames([string[]]$Actual,[string[]]$Expected,[string]$Label) {
 if($Actual.Count -ne $Expected.Count){throw ('REFUSED: '+$Label+' count differs from required set')}
 $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
 foreach($n in $Actual){
  if([string]::IsNullOrWhiteSpace($n) -or
     $n -match '[\\/]' -or $n -in @('.','..') -or
     $Expected -cnotcontains $n -or -not $seen.Add($n)){
   throw ('REFUSED: missing, duplicate, wrong-case or unknown '+$Label+' name '+$n)
  }
 }
 foreach($need in $Expected){if(-not $seen.Contains($need)){throw ('REFUSED: missing '+$Label+' required '+$need)}}
}
function Get-Rc1PreflightProof([string]$Folder,[string]$ArchivePath='') {
 $folder=(Assert-Rc1PathTree $Folder)
 if(-not [IO.Directory]::Exists($folder)){throw 'REFUSED: preflight folder absent'}
 $actualPaths=@([IO.Directory]::GetFileSystemEntries($folder))
 $actualNames=@($actualPaths|ForEach-Object {[IO.Path]::GetFileName($_)})
 Assert-Rc1ExactNames $actualNames $script:Rc1RequiredAll 'staging'
 foreach($path in $actualPaths){
  [void](Assert-Rc1PathTree $path)
  if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::Directory) -ne 0){throw ('REFUSED: unexpected directory '+$path)}
 }
 $manifestPath=Join-Path $folder 'rc1-preflight-manifest.json'
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($manifest.candidate -cne '1.6.0 RC1' -or
    $manifest.channel -cne 'NONINSTALLABLE_PREFLIGHT' -or
    $manifest.installable -ne $false -or
    $manifest.publishable -ne $false -or
    $manifest.realRemoteEnabled -ne $false -or
    $manifest.autoUpdateEnabled -ne $false){throw 'REFUSED: missing G0 fail-closed marker'}
 $records=@($manifest.files)
 $names=@($records|ForEach-Object{[string]$_.name})
 Assert-Rc1ExactNames $names $script:Rc1RequiredPayload 'manifest'
 $digests=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
 foreach($record in $records){
  $name=[string]$record.name
  $digest=[string]$record.sha256
  if($digest -cnotmatch '^[A-F0-9]{64}$'){throw ('REFUSED: missing or malformed SHA256 '+$name)}
  $path=Join-Path $folder $name
  $real=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  if($real -cne $digest){throw ('REFUSED: mismatched SHA256 '+$name)}
  $digests.Add($name,$digest)
 }
 $manifestDigest=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
 if($ArchivePath){
  [void](Assert-Rc1PathTree $ArchivePath)
  Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try{
   $entries=@($zip.Entries)
   $entryNames=@($entries|ForEach-Object{$_.FullName})
   Assert-Rc1ExactNames $entryNames $script:Rc1RequiredAll 'archive'
   foreach($entry in $entries){
    if($entry.Name -cne $entry.FullName){throw ('REFUSED: ZIP path alias '+$entry.FullName)}
    $expected=if($entry.FullName -ceq 'rc1-preflight-manifest.json'){$manifestDigest}else{$digests[$entry.FullName]}
    $sha=[Security.Cryptography.SHA256]::Create()
    $stream=$entry.Open()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
    finally{$stream.Dispose();$sha.Dispose()}
    if($hash -cne $expected){throw ('REFUSED: archive differs from attested digest '+$entry.FullName)}
   }
  }finally{$zip.Dispose()}
 }
 return [pscustomobject]@{Files=$script:Rc1RequiredAll.Count;Digests=$digests;ManifestDigest=$manifestDigest}
}
