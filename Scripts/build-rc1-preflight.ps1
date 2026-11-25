# G0-only RC1 preflight. This is explicitly NOT an installable build.
# No stable update manifest, no existing installed files, no Remote processes.
param([switch]$SkipContractTests)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Source'
$markerPath=Join-Path $source 'rc1-candidate.json'
$marker=Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8|ConvertFrom-Json
if($marker.candidate -cne '1.6.0 RC1' -or $marker.status -cne 'BLOCKED_PREINSTALLATION' -or
   $marker.installable -ne $false -or $marker.publishable -ne $false -or $marker.liveRemoteEnabled -ne $false){
 throw 'REFUSED: RC1 gate metadata not fail-closed'
}
$stableVersion=(Get-Content -LiteralPath (Join-Path $source 'version.txt') -Raw -Encoding UTF8).Trim()
if($stableVersion -cne '1.5.18'){throw 'REFUSED: source stable version changed before integration GO'}
$branch=(git -C $root branch --show-current).Trim()
if($branch -cne 'feature/v1.6-host-gui-owner-pilot'){throw 'REFUSED: wrong repository branch'}
if(-not $SkipContractTests){
 $test=Join-Path $root 'Tests\Test-V16OwnerContract.ps1'
 $result=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $test 2>&1)
 $status=$LASTEXITCODE
 $result|ForEach-Object{Write-Output $_}
 if($status -ne 0 -or ($result -join ' ') -notmatch 'V16_OWNER_CONTRACT_PASS=17 FAIL=0'){
  throw 'REFUSED: production owner contract fake-only tests failed'
 }
 $negative=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $test -InjectFailure 2>&1)
 $badExit=$LASTEXITCODE
 if($badExit -eq 0){throw 'REFUSED: negative assertion failed to trigger nonzero status'}
 Write-Output ('OWNER_ASSERTION_NEGATIVE_EXIT='+$badExit)
}
$compiler=@(
 (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
 (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
if(-not $compiler){throw 'NOT CHECKED: .NET Framework C# compiler unavailable'}
$dist=Join-Path $root 'dist'
$out=Join-Path $dist 'v1.6.0-RC1-BLOCKED-PREFLIGHT'
if([IO.Directory]::Exists($out) -or [IO.File]::Exists($out)){
 throw ('REFUSED: existing preflight output. Inspect manually; no implicit overwrite: '+$out)
}
[void](New-Item -ItemType Directory -Path $out -ErrorAction Stop)
$lib=Join-Path $out 'RdcOwnerProcess.dll'
& $compiler /nologo /target:library /optimize+ ('/out:'+$lib) (Join-Path $source 'RdcOwnerProcess.cs')
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($lib)){throw 'Owner contract C# assembly compilation failed'}
$launcher=Join-Path $out 'RC1 BLOCKED - Launcher.exe'
$setup=Join-Path $out 'RC1 BLOCKED - Setup.exe'
foreach($job in @(
 @{Out=$launcher;Source=(Join-Path $root 'Installer\Launcher.cs')},
 @{Out=$setup;Source=(Join-Path $root 'Installer\Setup.cs')}
)){
 & $compiler /nologo /target:winexe /optimize+ /platform:anycpu /define:RDC_RC1_BLOCKED /reference:System.Windows.Forms.dll ('/out:'+$job.Out) $job.Source
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($job.Out)){throw ('Blocked-only executable failed to compile: '+$job.Out)}
}
$files=@(
 @{Name='RdcOwnerProcess.cs';From=(Join-Path $source 'RdcOwnerProcess.cs')},
 @{Name='rc1-candidate.json';From=$markerPath},
 @{Name='V1-6-0-OWNER-PILOT.md';From=(Join-Path $root 'docs\dev\planning\V1-6-0-OWNER-PILOT.md')}
)
foreach($item in $files){Copy-Item -LiteralPath $item.From -Destination (Join-Path $out $item.Name) -ErrorAction Stop}
$allowed=@('RdcOwnerProcess.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe',
           'RdcOwnerProcess.cs','rc1-candidate.json','V1-6-0-OWNER-PILOT.md')
$manifestEntries=@()
foreach($name in $allowed){
 $f=Join-Path $out $name
 $manifestEntries+= [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
}
$manifest=[ordered]@{
 candidate='1.6.0 RC1';channel='NONINSTALLABLE_PREFLIGHT';installable=$false;
 publishable=$false;autoUpdateEnabled=$false;realRemoteEnabled=$false;
 reason='No verified real Host/GUI integration or owned Remote process-tree tests';
 sourceVersion=$stableVersion;files=$manifestEntries
}
$manifestText=$manifest|ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $out 'rc1-preflight-manifest.json'),$manifestText,(New-Object Text.UTF8Encoding($false)))
Write-Output ('RC1_PREFLIGHT_ARTIFACT='+$out)
Write-Output 'RC1_PREFLIGHT_STATUS=BLOCKED_NOT_INSTALLABLE'
Write-Output ('RC1_PREFLIGHT_COMPILED_FILES='+$allowed.Count+' LISTED_HASHES='+$manifestEntries.Count)
Write-Output 'RC1_PUBLISH_INSTALL_LIVE_REMOTE=REFUSED'
