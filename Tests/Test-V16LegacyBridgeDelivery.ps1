param([Parameter(Mandatory=$true)][string]$Stage)
# Exact released updater, offline HTTP fixture, disposable Git object store.
$ErrorActionPreference='Stop'
$stageSource=Join-Path $Stage 'Source'
$baseSetup=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'RDC.Relay.Setup.v1.5.18.exe'
if((Get-FileHash -LiteralPath $baseSetup).Hash -cne 'D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190'){throw 'BASE_HASH'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-BridgeDelivery-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
try{
 $base=Join-Path $root 'Base';$gitRoot=Join-Path $root 'Feed';$served=Join-Path $root 'Served';$install=Join-Path $root 'Installed'
 foreach($d in @($base,$gitRoot,$served,$install)){[void][IO.Directory]::CreateDirectory($d)}
 $asm=[Reflection.Assembly]::ReflectionOnlyLoadFrom($baseSetup)
 function Resource($name,$path){
  $input=$asm.GetManifestResourceStream('RdcPayload.'+$name)
  if(!$input){throw 'RESOURCE_MISSING'}
  try{$f=[IO.File]::Open($path,[IO.FileMode]::CreateNew);try{$input.CopyTo($f)}finally{$f.Dispose()}}finally{$input.Dispose()}
 }
 Resource 'update-manifest.json' (Join-Path $base 'update-manifest.json')
 $original=[IO.File]::ReadAllText((Join-Path $base 'update-manifest.json'))|ConvertFrom-Json
 foreach($row in $original.files){
  $n=if($row.name -ceq 'RDC Relay.cmd'){'launch.cmd'}else{$row.name}
  Resource $n (Join-Path $base $row.name)
  Check ((Get-FileHash -LiteralPath (Join-Path $base $row.name)).Hash -ceq $row.sha256) ('released byte identity '+$row.name)
  [IO.File]::Copy((Join-Path $base $row.name),(Join-Path $install $row.name),$false)
 }
 $manifest=[IO.File]::ReadAllText((Join-Path $stageSource 'update-manifest.json'))|ConvertFrom-Json
 Check ($manifest.version -ceq '1.5.18' -and !$manifest.migration.ready -and $manifest.files.Count -eq 11) 'legacy flat version held, offer inactive'
 git -C $gitRoot init --quiet
 git -C $gitRoot config core.autocrlf false
 if($LASTEXITCODE -ne 0){throw 'GIT_INIT'}
 $members=@($manifest.files.name)+@('update-manifest.json')
 foreach($n in $members){
  $path=Join-Path $stageSource $n
  $blob=(& git -C $gitRoot hash-object -w --no-filters -- $path).Trim()
  if($LASTEXITCODE -ne 0 -or $blob -cnotmatch '^[0-9a-f]{40}$'){throw 'GIT_BLOB'}
  & git -C $gitRoot update-index --add --cacheinfo "100644,$blob,Source/$n"
  if($LASTEXITCODE -ne 0){throw 'GIT_INDEX'}
 }
 $tree=(& git -C $gitRoot write-tree).Trim()
 $zip=Join-Path $root 'feed.zip'
 & git -C $gitRoot archive --format=zip "--output=$zip" $tree
 if($LASTEXITCODE -ne 0){throw 'GIT_ARCHIVE'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory($zip,$served)
 $feed=Join-Path $served 'Source'
 foreach($row in $manifest.files){Check ((Get-FileHash -LiteralPath (Join-Path $feed $row.name)).Hash -ceq $row.sha256) ('raw Git blob digest '+$row.name)}
 # Run actual released updater; only HTTP is substituted with exact
 # immutable Git-exported bytes. No production paths, network or registry.
 $wrapper=Join-Path $root 'Invoke-OfflineUpdater.ps1'
 $code=@'
param([string]$Updater,[string]$Install,[string]$Feed,[string]$Version,[string]$Corrupt)
$ErrorActionPreference='Stop'
function Invoke-WebRequest {
 param([string]$Uri,$Headers,[switch]$UseBasicParsing,[int]$TimeoutSec,[string]$OutFile)
 if($Uri -ceq 'https://api.github.com/repos/1rubass1/RDC-Relay/commits/stable'){
  return [pscustomobject]@{Content='{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'}
 }
 $prefix='https://raw.githubusercontent.com/1rubass1/RDC-Relay/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Source/'
 if(!$Uri.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'UNEXPECTED_NETWORK_ROUTE'}
 $name=[Uri]::UnescapeDataString($Uri.Substring($prefix.Length))
 if($name -match '[\\/]' -or $name -notin @('remote-window.ps1','update-notice.ps1','divider-caustic.ps','divider-caustic-detail.ps','divider-particles.ps','divider-particles-core.ps','RDCRelay.ico','version.txt','update.ps1','RDC Relay.cmd','legacy-migration.ps1','update-manifest.json')){throw 'UNEXPECTED_MEMBER'}
 $p=Join-Path $Feed $name
 if($OutFile){
  [IO.File]::Copy($p,$OutFile,$false)
  if($Corrupt -and $name -ceq $Corrupt){[IO.File]::AppendAllText($OutFile,'corruption fixture')}
 }else{return [pscustomobject]@{Content=[IO.File]::ReadAllText($p)}}
}
& $Updater -InstallRoot $Install -CurrentVersion $Version -Force
exit $LASTEXITCODE
'@
 [IO.File]::WriteAllText($wrapper,$code,(New-Object Text.UTF8Encoding($true)))
 $updater=Join-Path $base 'update.ps1'
 function Run([string]$version,[string]$corrupt=''){
  $args=@('-NoProfile','-NonInteractive','-File',$wrapper,'-Updater',$updater,'-Install',$install,'-Feed',$feed,'-Version',$version)
  if($corrupt){$args+=@('-Corrupt',$corrupt)}
  & powershell.exe @args
  return $LASTEXITCODE
 }
 $rc=Run '1.5.18' 'legacy-migration.ps1'
 Check ($rc -eq 1) 'tampered delivery refuses update'
 foreach($row in $original.files){Check ((Get-FileHash -LiteralPath (Join-Path $install $row.name)).Hash -ceq $row.sha256) ('original retained '+$row.name)}
 Check (!(Test-Path (Join-Path $install 'legacy-migration.ps1'))) 'failed download creates no bridge'
 $rc=Run '1.5.18'
 Check ($rc -eq 42) 'real 1.5.18 same-version updater applies bridge'
 foreach($row in $manifest.files){Check ((Get-FileHash -LiteralPath (Join-Path $install $row.name)).Hash -ceq $row.sha256) ('installed bridge digest '+$row.name)}
 Check (([IO.File]::ReadAllText((Join-Path $install 'version.txt'))).Trim() -ceq '1.5.18') 'legacy version unchanged'
 Check ((Run '1.5.18') -eq 0) 'already delivered bridge is idempotent'
 Check ((Run '1.6.0') -eq 0) 'legacy feed cannot downgrade numeric new client'
 'RDC_LEGACY_DELIVERY_PASS='+$pass+' FAIL=0'
}finally{
 # Isolated temp root generated by this script, no production data.
 if([IO.Directory]::Exists($root)){Get-ChildItem -LiteralPath $root -Force -Recurse -File | ForEach-Object{if($_.Attributes -band [IO.FileAttributes]::ReadOnly){$_.IsReadOnly=$false}};Remove-Item -LiteralPath $root -Force -Recurse}
}
