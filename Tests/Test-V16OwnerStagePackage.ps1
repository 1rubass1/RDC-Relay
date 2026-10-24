# Full original-GUI product SOURCE review bundle; NOT an installable RC1.
# Inspects only ignored dist files. No Setup/Launcher/GUI/Remote execution.
param([switch]$InjectFailure)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $root 'dist\v1.6.0-RC1-PRODUCT-SOURCE-NOT-INSTALLABLE'
$zipFile=Join-Path $root 'dist\RDCRelay-1.6.0-RC1-PRODUCT-SOURCE-NOT-INSTALLABLE.zip'
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
try{
 $manFile=Join-Path $folder 'owner-source-manifest.json'
 $man=Get-Content -LiteralPath $manFile -Raw -Encoding UTF8|ConvertFrom-Json
 Check ($man.candidate -ceq '1.6.0 RC1' -and $man.kind -ceq 'PRODUCT_SOURCE_REVIEW_ONLY' -and
   $man.installable -eq $false -and $man.liveRemoteEnabled -eq $false -and
   $man.publishable -eq $false -and $man.autoUpdateEnabled -eq $false) 'source bundle explicitly noninstallable'
 $payload=@('remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
  'RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerProcess.cs','rc1-candidate.json',
  'RDCRelay.ico','divider-caustic.ps','divider-caustic-detail.ps',
  'divider-particles.ps','divider-particles-core.ps','update-notice.ps1','update.ps1')
 $allowed=@($payload|ForEach-Object{'Source/'+$_})+@('RdcOwnerRuntime.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe')
 $allowedAll=@($allowed)+@('owner-source-manifest.json')
 $records=@($man.files)
 $names=@($records|ForEach-Object{[string]$_.name})
 Check ($records.Count -eq $allowed.Count -and (@($names|Select-Object -Unique).Count -eq $allowed.Count) -and
  @($names|Where-Object{$allowed -cnotcontains $_}).Count -eq 0) 'manifest exact unique case-sensitive set'
 $all=@(Get-ChildItem -LiteralPath $folder -Recurse -File -Force|ForEach-Object{$_.FullName.Substring($folder.Length+1).Replace('\','/')})
 Check ($all.Count -eq $allowedAll.Count -and (@($all|Select-Object -Unique).Count -eq $allowedAll.Count) -and
  @($all|Where-Object{$allowedAll -cnotcontains $_}).Count -eq 0) 'staging exact unique set'
 foreach($item in $records){
  $n=[string]$item.name
  $digest=[string]$item.sha256
  Check ($digest -cmatch '^[A-F0-9]{64}$' -and
    $digest -ceq (Get-FileHash -LiteralPath (Join-Path $folder $n) -Algorithm SHA256).Hash) ('staging digest '+$n)
 }
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($zipFile)
 try{
  $entries=@($zip.Entries)
  $zipNames=@($entries|ForEach-Object{$_.FullName})
  Check ($entries.Count -eq $allowedAll.Count -and (@($zipNames|Select-Object -Unique).Count -eq $allowedAll.Count) -and
    @($zipNames|Where-Object{$allowedAll -cnotcontains $_}).Count -eq 0) 'ZIP exact unique case-sensitive set'
  foreach($entry in $entries){
   $sha=[Security.Cryptography.SHA256]::Create();$stream=$entry.Open()
   try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
   finally{$stream.Dispose();$sha.Dispose()}
   Check ($actual -ceq (Get-FileHash -LiteralPath (Join-Path $folder $entry.FullName) -Algorithm SHA256).Hash) ('ZIP SHA256 '+$entry.FullName)
  }
 }finally{$zip.Dispose()}
 Check (-not (Test-Path -LiteralPath (Join-Path $folder 'Source\update-manifest.json'))) 'stable updater manifest omitted'
 Check (-not (Test-Path -LiteralPath (Join-Path $folder 'Source\RDC Relay.cmd'))) 'stable legacy launcher omitted'
 Check (-not (Test-Path -LiteralPath (Join-Path $folder 'Source\remote-session.log'))) 'real user log omitted'
 Check (-not (Test-Path -LiteralPath (Join-Path $folder 'Source\device.json'))) 'real account token store omitted'
 Check ((Get-Content -LiteralPath (Join-Path $folder 'Source\rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json).installable -eq $false) 'source boot marker blocks inadvertent full Remote'
 if($InjectFailure){Check $false 'deliberate package check fails nonzero'}
}catch{$fail++;Write-Output ('FAIL exception '+$_.Exception.Message)}
Write-Output ('RC1_OWNER_STAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
