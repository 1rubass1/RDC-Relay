# Independent read-only validation of the actual ZIP and checker binary.
# Extraction, corruption injection and cleanup occur only in disposable Temp.
param(
 [Parameter(Mandatory=$true)][string]$Archive,
 [Parameter(Mandatory=$true)][string]$Checker
)
$ErrorActionPreference='Stop'
if(-not [IO.Path]::IsPathRooted($Archive) -or
   -not [IO.Path]::IsPathRooted($Checker)){throw 'RDC_REVIEW_ABSOLUTE_ARTIFACTS_REQUIRED'}
foreach($file in @($Archive,$Checker)){
 if(-not [IO.File]::Exists($file)){throw ('RDC_REVIEW_ARTIFACT_MISSING '+[IO.Path]::GetFileName($file))}
 if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'RDC_REVIEW_ARTIFACT_LINK_REFUSED'
 }
}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$pass=0;$fail=0
function Check([bool]$condition,[string]$name){
 if($condition){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
function RunVerifier([string]$path){
 $p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName=$Checker
 $p.Arguments=if($path){'--verify "'+$path+'"'}else{''}
 $p.UseShellExecute=$false
 $p.RedirectStandardOutput=$true
 $p.RedirectStandardError=$true
 $p.CreateNoWindow=$true
 $process=[Diagnostics.Process]::Start($p)
 if(!$process.WaitForExit(12000)){
  try{$process.Kill()}catch{}
  throw 'RDC_REVIEW_CHECKER_TIMEOUT'
 }
 return @{Exit=$process.ExitCode;Out=$process.StandardOutput.ReadToEnd();Err=$process.StandardError.ReadToEnd()}
}
$root=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) ('RDC-REVIEW-SMOKE-'+[Guid]::NewGuid().ToString('N'))
if(([IO.Directory]::Exists($root) -or [IO.File]::Exists($root))){throw 'RDC_REVIEW_TEMP_COLLISION'}
[void][IO.Directory]::CreateDirectory($root)
try{
 $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
 try{
  $members=@($zip.Entries)
  Check ($members.Count -eq 28) 'ZIP has exactly 27 payload entries and one manifest'
  $names=@($members|ForEach-Object{$_.FullName})
  Check (@($names|Select-Object -Unique).Count -eq 28 -and
    $names -ccontains 'review-manifest.json' -and
    $names -ccontains 'payload/Source/release-review.json') 'ZIP members exact unique review-only marker'
  $safe=$true
  foreach($name in $names){
   if($name.Contains('\') -or $name.StartsWith('/') -or
     $name.Split('/') -contains '..' -or
     $name.EndsWith('/') -or $name.Contains(':')){$safe=$false;break}
  }
  Check $safe 'ZIP entries contain no absolute or traversing paths'
 }finally{$zip.Dispose()}
 if(!$safe){throw 'RDC_REVIEW_ZIP_UNSAFE'}
 [IO.Compression.ZipFile]::ExtractToDirectory($Archive,$root)
 $manifest=Get-Content (Join-Path $root 'review-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check ($manifest.kind -ceq 'FULL_HOST_GUI_SOURCE_REVIEW_ONLY' -and
  $manifest.version -ceq '1.6.0' -and $manifest.publisher -ceq 'RUBASS' -and
  !$manifest.installable -and !$manifest.publishable -and !$manifest.launchEnabled) 'metadata explicitly review-only and numeric v1.6.0'
 Check ($manifest.files.Count -eq 27 -and
  @($manifest.files|Where-Object{$_.name -ceq 'Source/rc1-candidate.json'}).Count -eq 0) '26 source runtime members plus generated marker, no private pilot'
 $all=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
 Check ($all.Count -eq 28) 'extraction creates no unexpected files'
 $observed=RunVerifier $root
 Check ($observed.Exit -eq 0 -and
  $observed.Out.Contains('RDC_RELEASE_REVIEW_PACKAGE_PASS=27 FAIL=0')) 'compiled offline checker verifies full archive bytes'
 Check ($observed.Out.Contains('RDC_RELEASE_REVIEW_INSTALLABLE=FALSE')) 'verifier never reports install-ready'
 $inert=RunVerifier ''
 Check ($inert.Exit -eq 42 -and
  $inert.Err.Contains('RDC_RELEASE_REVIEW_NO_INSTALL_OR_REMOTE')) 'default checker execution refuses product launch'
 foreach($name in @('remote-window.ps1','rc1-tray-host.ps1','rc1-quota-client.ps1','update.ps1')){
  $script=Join-Path $root ('payload\Source\'+$name)
  $lines=@(Get-Content -LiteralPath $script -TotalCount 25 -Encoding UTF8)
  Check ($lines -ccontains "throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'") ('inert script entrypoint '+$name)
 }
 $dll=Join-Path $root 'payload\RdcOwnerRuntime.dll'
 $original=[IO.File]::ReadAllBytes($dll)
 [IO.File]::AppendAllText($dll,'synthetic-corruption')
 $tampered=RunVerifier $root
 Check ($tampered.Exit -eq 42 -and
   $tampered.Err.Contains('RDC_RELEASE_REVIEW_PACKAGE_REFUSED')) 'modified Host DLL is refused'
 [IO.File]::WriteAllBytes($dll,$original)
 $restored=RunVerifier $root
 Check ($restored.Exit -eq 0 -and
  $restored.Out.Contains('RDC_RELEASE_REVIEW_PACKAGE_PASS=27')) 'restored bytes pass independent verification'
 $version=Join-Path $root 'payload\Source\version.txt'
 Check ([IO.File]::ReadAllText($version,[Text.Encoding]::UTF8).Trim() -ceq '1.6.0') 'generated release version is not 1.5.x'
 Write-Output ('RDC_V16_REVIEW_ARCHIVE_SHA256='+(Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash)
}finally{
 if([IO.Directory]::Exists($root)){
  $entries=@(Get-ChildItem -LiteralPath $root -Recurse -Force)
  if(@($entries|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count){
   throw 'RDC_REVIEW_TEMP_REPARSE_REFUSED'
  }
  Remove-Item -LiteralPath $root -Recurse -Force
 }
}
Write-Output ('RDC_V16_REVIEW_ARTIFACT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
