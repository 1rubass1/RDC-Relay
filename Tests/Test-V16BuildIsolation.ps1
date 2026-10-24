# G0 RC1 preflight: static/product-package checks only; NEVER executes installers.
param([switch]$InjectFailure)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Source'
$out=Join-Path $root 'dist\v1.6.0-RC1-BLOCKED-PREFLIGHT'
$zipPath=Join-Path $root 'dist\RDCRelay-1.6.0-RC1-BLOCKED-PREFLIGHT.zip'
$pass=0;$fail=0
function Check([bool]$ok,[string]$why) {
 if($ok){$script:pass++;Write-Output ('PASS '+$why)}
 else{$script:fail++;Write-Output ('FAIL '+$why)}
}
try{
 $metadata=Get-Content -LiteralPath (Join-Path $source 'rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check ($metadata.candidate -ceq '1.6.0 RC1' -and $metadata.stableTarget -ceq '1.6.0') 'candidate identity distinct from future stable tag'
 Check ($metadata.installable -eq $false -and $metadata.publishable -eq $false) 'installation and public release explicitly refused'
 Check ($metadata.autoUpdateEnabled -eq $false -and $metadata.stableManifestEnabled -eq $false) 'RC1 stable feed disabled'
 Check ((Get-Content -LiteralPath (Join-Path $source 'version.txt') -Raw).Trim() -eq '1.5.18') 'legacy version source unchanged'
 $upd=Get-Content -LiteralPath (Join-Path $source 'update.ps1') -Raw -Encoding UTF8
 $stopStart=$upd.IndexOf('function Stop-RdcInstalledProcesses',[StringComparison]::Ordinal)
 $guard=$upd.IndexOf('RC1_UPDATE_BLOCKED',[StringComparison]::Ordinal)
 Check ($guard -gt 0 -and $stopStart -gt $guard) 'early updater gate before user-process operations'
 $setup=Get-Content -LiteralPath (Join-Path $root 'Installer\Setup.cs') -Raw -Encoding UTF8
 $launch=Get-Content -LiteralPath (Join-Path $root 'Installer\Launcher.cs') -Raw -Encoding UTF8
 Check ($setup.Contains('#if RDC_RC1_BLOCKED') -and $setup.IndexOf('return 42;') -lt $setup.IndexOf('transaction =')) 'RC1 setup compile guard precedes install transaction'
 Check ($launch.Contains('#if RDC_RC1_BLOCKED') -and $launch.IndexOf('return 42;') -lt $launch.IndexOf('Process.Start(psi)')) 'RC1 launcher compile guard precedes process spawn'
 $originalBuilder=Get-Content -LiteralPath (Join-Path $root 'Scripts\build-release.ps1') -Raw -Encoding UTF8
 Check ($originalBuilder.Contains("'^\d+\.\d+\.\d+$'")) 'stable builder numeric version gate retained'
 $manifest=Get-Content -LiteralPath (Join-Path $out 'rc1-preflight-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check ($manifest.candidate -ceq '1.6.0 RC1' -and $manifest.channel -ceq 'NONINSTALLABLE_PREFLIGHT' -and -not $manifest.installable) 'preflight manifest is never stable release'
 $names=@('RdcOwnerProcess.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe',
          'RdcOwnerProcess.cs','rc1-candidate.json','V1-6-0-OWNER-PILOT.md')
 $listed=@($manifest.files|ForEach-Object{$_.name})
 Check ($listed.Count -eq $names.Count -and @($listed|Where-Object{$names -cnotcontains $_}).Count -eq 0) 'manifest allowlist exactly matches candidate evidence'
 foreach($f in $manifest.files){
  Check ((Get-FileHash -LiteralPath (Join-Path $out $f.name) -Algorithm SHA256).Hash -ceq [string]$f.sha256) ('preflight file digest '+$f.name)
 }
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
 try{
  $members=@($zip.Entries)
  Check ($members.Count -eq $names.Count+1) 'ZIP contains only verified preflight files'
  foreach($member in $members){
   $sha=[Security.Cryptography.SHA256]::Create();$stream=$member.Open()
   try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
   Check ($actual -ceq (Get-FileHash -LiteralPath (Join-Path $out $member.FullName) -Algorithm SHA256).Hash) ('ZIP SHA256 '+$member.FullName)
  }
 }finally{$zip.Dispose()}
 Check (-not (Test-Path -LiteralPath (Join-Path $out 'remote-session.log'))) 'no real Remote log present in preflight'
 if($InjectFailure){Check $false 'injected assertion must return nonzero'}
}catch{$fail++;Write-Output ('FAIL exception '+$_.Exception.Message)}
Write-Output ('RC1_BUILD_ISOLATION_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
