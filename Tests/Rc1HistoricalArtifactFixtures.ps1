# Self-contained, NONINSTALLABLE G0/G4 format fixtures for current RC1 tests.
# The legacy artifacts are historical review formats, NOT release candidates.
# Only new exactly scoped folders below the OS Temp directory are modified.
# No installed app/Remote/GUI/network/shortcut/build-output is touched.
$script:Rc1HistoricalFixtureRepo=Split-Path -Parent $PSScriptRoot
$script:Rc1HistoricalG0Payload=@(
 'RdcOwnerProcess.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe',
 'RdcOwnerProcess.cs','rc1-candidate.json','V1-6-0-OWNER-PILOT.md'
)
$script:Rc1HistoricalG4Source=@(
 'remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerProcess.cs',
 'RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','rc1-candidate.json',
 'RDCRelay.ico','divider-caustic.ps','divider-caustic-detail.ps',
 'divider-particles.ps','divider-particles-core.ps','update-notice.ps1','update.ps1'
)
$script:Rc1HistoricalG4Payload=@(
 @($script:Rc1HistoricalG4Source|ForEach-Object{'Source/'+$_})+
 @('RdcOwnerRuntime.dll','RC1 BLOCKED - Launcher.exe','RC1 BLOCKED - Setup.exe',
   'Installer/Rc1CandidateSetup.cs','Installer/Rc1CandidateLauncher.cs',
   'RC1 BLOCKED - Owner Setup.exe','RC1 BLOCKED - Owner Launcher.exe')
)
function Assert-Rc1HistoricCompiler {
 $compiler=@(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
 )|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
 if(-not $compiler){throw 'HISTORIC_FIXTURE_CSC_UNAVAILABLE'}
 return [string]$compiler
}
function Invoke-Rc1HistoricCompile([string]$compiler,[string[]]$arguments,[string]$result){
 $messages=@(& $compiler @arguments 2>&1)
 $code=$LASTEXITCODE
 if($code -ne 0 -or -not [IO.File]::Exists($result)){
  $safe=($messages|ForEach-Object{[string]$_}) -join ' | '
  if($safe.Length -gt 2000){$safe=$safe.Substring(0,2000)}
  throw ('HISTORIC_FIXTURE_COMPILE_FAILED '+[IO.Path]::GetFileName($result)+
   ' EXIT='+$code+' DIAGNOSTIC='+$safe)
 }
}
function Assert-Rc1HistoricBlockedMarker([string]$root) {
 $marker=Get-Content -LiteralPath (Join-Path $root 'Source\rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($marker.candidate -cne '1.6.0 RC1' -or $marker.installable -ne $false -or
   $marker.publishable -ne $false -or $marker.liveRemoteEnabled -ne $false -or
   $marker.autoUpdateEnabled -ne $false){
  throw 'HISTORIC_FIXTURE_REQUIRES_BLOCKED_SOURCE_MARKER'
 }
}
function Assert-Rc1HistoricStageRoot([object]$fixture){
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
 $full=[IO.Path]::GetFullPath([string]$fixture.Root).TrimEnd([char]92)
 if([IO.Path]::GetDirectoryName($full) -cne $temp -or
  [IO.Path]::GetFileName($full) -cnotmatch '^RDC-RC1-LEGACY-FIXTURE-[a-f0-9]{32}$' -or
  [IO.Path]::GetFullPath([string]$fixture.Stage) -cne (Join-Path $full 'stage') -or
  [IO.Path]::GetFullPath([string]$fixture.Archive) -cne (Join-Path $full 'legacy-proof.zip')){
  throw 'HISTORIC_FIXTURE_TEMP_BOUNDARY_REFUSED'
 }
 $cursor=$full
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'HISTORIC_FIXTURE_REPARSE_PARENT_REFUSED'
   }
  }
  $next=[IO.Path]::GetDirectoryName($cursor)
  if(-not $next -or $next -ceq $cursor){break}
  $cursor=$next
 }
}
function Remove-Rc1HistoricalFixture([object]$fixture) {
 if($null -eq $fixture){return}
 Assert-Rc1HistoricStageRoot $fixture
 if(-not [IO.Directory]::Exists($fixture.Root)){return}
 # Do not traverse any link. Only allow the exact generated fixture schema:
 # Temp/root/{stage/{Source,Installer,files},legacy-proof.zip}.
 $dirs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 [void]$dirs.Add([string]$fixture.Root)
 [void]$dirs.Add([string]$fixture.Stage)
 if($fixture.Kind -ceq 'G4'){
  [void]$dirs.Add((Join-Path $fixture.Stage 'Source'))
  [void]$dirs.Add((Join-Path $fixture.Stage 'Installer'))
 }
 $files=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($name in @($fixture.Expected)){
  [void]$files.Add((Join-Path $fixture.Stage $name.Replace('/',[IO.Path]::DirectorySeparatorChar)))
 }
 if($fixture.Kind -cne 'CompileOnly'){[void]$files.Add([string]$fixture.Archive)}
 $pending=New-Object 'System.Collections.Generic.Stack[string]'
 $pending.Push([string]$fixture.Root)
 while($pending.Count -gt 0){
  $at=$pending.Pop()
  if(-not $dirs.Contains($at)){throw ('HISTORIC_FIXTURE_UNEXPECTED_DIR '+$at)}
  if(([IO.File]::GetAttributes($at) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw ('HISTORIC_FIXTURE_UNTRUSTED_DIR '+$at)
  }
  foreach($entry in [IO.Directory]::GetFileSystemEntries($at)){
   $attr=[IO.File]::GetAttributes($entry)
   if(($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw ('HISTORIC_FIXTURE_UNTRUSTED_ENTRY '+$entry)
   }
   if(($attr -band [IO.FileAttributes]::Directory) -ne 0){
    if(-not $dirs.Contains($entry)){throw ('HISTORIC_FIXTURE_FOREIGN_DIR '+$entry)}
    $pending.Push($entry)
   }elseif(-not $files.Contains($entry)){
    throw ('HISTORIC_FIXTURE_FOREIGN_FILE '+$entry)
   }
  }
 }
 [IO.Directory]::Delete([string]$fixture.Root,$true)
 if([IO.Directory]::Exists($fixture.Root)){throw 'HISTORIC_FIXTURE_CLEANUP_UNCONFIRMED'}
}
function New-Rc1HistoricalFixture([ValidateSet('G0','G4','CompileOnly')][string]$Kind) {
 $repo=$script:Rc1HistoricalFixtureRepo
 if($Kind -cne 'CompileOnly'){Assert-Rc1HistoricBlockedMarker $repo}
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
 $fixtureRoot=Join-Path $temp ('RDC-RC1-LEGACY-FIXTURE-'+[Guid]::NewGuid().ToString('N'))
 if([IO.File]::Exists($fixtureRoot) -or [IO.Directory]::Exists($fixtureRoot)){
  throw 'HISTORIC_FIXTURE_TEMP_COLLISION'
 }
 $stage=Join-Path $fixtureRoot 'stage'
 $archive=Join-Path $fixtureRoot 'legacy-proof.zip'
 $expected=switch($Kind){
  'G0' {@($script:Rc1HistoricalG0Payload)+@('rc1-preflight-manifest.json')}
  'G4' {@($script:Rc1HistoricalG4Payload)+@('owner-source-manifest.json')}
  'CompileOnly' {@('RdcOwnerRuntime.STATIC_TEST.dll')}
 }
 $fixture=[pscustomobject]@{
  Kind=$Kind;Root=$fixtureRoot;Stage=$stage;Archive=$archive;Expected=[string[]]$expected
 }
 Assert-Rc1HistoricStageRoot $fixture
 [void][IO.Directory]::CreateDirectory($stage)
 try{
  if($Kind -ceq 'CompileOnly'){return $fixture}
  $compiler=Assert-Rc1HistoricCompiler
  $src=Join-Path $repo 'Source'
  $inst=Join-Path $repo 'Installer'
  if($Kind -ceq 'G0'){
   $library=Join-Path $stage 'RdcOwnerProcess.dll'
   Invoke-Rc1HistoricCompile $compiler @('/nologo','/target:library',('/out:'+$library),
    (Join-Path $src 'RdcOwnerProcess.cs')) $library | Out-Null
   foreach($choice in @(
    @{Name='RC1 BLOCKED - Launcher.exe';Source='Launcher.cs'},
    @{Name='RC1 BLOCKED - Setup.exe';Source='Setup.cs'}
   )){
    $file=Join-Path $stage $choice.Name
    $sources=@((Join-Path $inst $choice.Source))
    if($choice.Source -ceq 'Setup.cs'){
     $sources+=@(Join-Path $inst 'RdcReleaseInstallState.cs')
     $sources+=@(Join-Path $inst 'RdcReleaseMetadataSnapshot.cs')
    }
    $compilerArgs=@('/nologo','/target:winexe',
     '/define:RDC_RC1_BLOCKED','/reference:System.Windows.Forms.dll',
     ('/out:'+$file))+$sources
    Invoke-Rc1HistoricCompile $compiler $compilerArgs $file | Out-Null
   }
   foreach($entry in @(
    @{Name='RdcOwnerProcess.cs';Path=(Join-Path $src 'RdcOwnerProcess.cs')},
    @{Name='rc1-candidate.json';Path=(Join-Path $src 'rc1-candidate.json')},
    @{Name='V1-6-0-OWNER-PILOT.md';Path=(Join-Path $repo 'docs\dev\planning\V1-6-0-OWNER-PILOT.md')}
   )){
    [IO.File]::Copy([string]$entry.Path,(Join-Path $stage $entry.Name),$false)
   }
   $rows=@($script:Rc1HistoricalG0Payload|ForEach-Object{
    [ordered]@{name=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $_) -Algorithm SHA256).Hash}
   })
   $manifest=[ordered]@{
    candidate='1.6.0 RC1';channel='NONINSTALLABLE_PREFLIGHT';
    installable=$false;publishable=$false;realRemoteEnabled=$false;
    autoUpdateEnabled=$false;sourceVersion='1.5.18';files=$rows
   }
   [IO.File]::WriteAllText((Join-Path $stage 'rc1-preflight-manifest.json'),
    ($manifest|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
  }else{
   foreach($folder in @('Source','Installer')){
    [void][IO.Directory]::CreateDirectory((Join-Path $stage $folder))
   }
   foreach($name in $script:Rc1HistoricalG4Source){
    [IO.File]::Copy((Join-Path $src $name),(Join-Path $stage ('Source/'+$name)),$false)
   }
   foreach($name in @('Rc1CandidateSetup.cs','Rc1CandidateLauncher.cs')){
    [IO.File]::Copy((Join-Path $inst $name),(Join-Path $stage ('Installer/'+$name)),$false)
   }
   # Compile current product C# source, but stamp ONLY a blocked historical
   # review-format manifest. This fixture is NOT a historical real release.
   $runtimeDll=Join-Path $stage 'RdcOwnerRuntime.dll'
   $cs=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
    'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerRuntime.cs')|
    ForEach-Object{Join-Path $src $_}
   # Historical review ZIP is deliberately frozen/noninstallable, but the
   # current runtime source needs its shared C# language catalog at compile time.
   # Include it in compilation, not in the historical blocked payload allowlist.
   $cs+=@(Join-Path $src 'RdcUiLanguage.cs')
   Invoke-Rc1HistoricCompile $compiler (@('/nologo','/target:library',
    '/reference:System.Core.dll','/reference:System.Web.Extensions.dll',
    '/reference:System.Security.dll','/reference:System.Windows.Forms.dll',
    '/reference:System.Drawing.dll','/reference:System.Management.dll',
    ('/out:'+$runtimeDll))+$cs) $runtimeDll | Out-Null
   foreach($choice in @(
    @{Name='RC1 BLOCKED - Launcher.exe';Source='Launcher.cs'},
    @{Name='RC1 BLOCKED - Setup.exe';Source='Setup.cs'},
    @{Name='RC1 BLOCKED - Owner Setup.exe';Source='Rc1CandidateSetup.cs'},
    @{Name='RC1 BLOCKED - Owner Launcher.exe';Source='Rc1CandidateLauncher.cs'}
   )){
    $file=Join-Path $stage $choice.Name
    $sources=@((Join-Path $inst $choice.Source))
    if($choice.Source -ceq 'Setup.cs'){
     $sources+=@(Join-Path $inst 'RdcReleaseInstallState.cs')
     $sources+=@(Join-Path $inst 'RdcReleaseMetadataSnapshot.cs')
    }
    if($choice.Source -ceq 'Rc1CandidateSetup.cs'){
     $sources+=@(Join-Path $inst 'Rc1ManualUpgrade.cs')
    }
    $compilerArgs=@('/nologo','/target:winexe',
     '/define:RDC_RC1_BLOCKED','/reference:System.Core.dll',
     '/reference:System.Web.Extensions.dll','/reference:System.Windows.Forms.dll',
     '/reference:System.Management.dll',
     ('/out:'+$file))+$sources
    Invoke-Rc1HistoricCompile $compiler $compilerArgs $file | Out-Null
   }
   $rows=@($script:Rc1HistoricalG4Payload|ForEach-Object{
    $p=Join-Path $stage $_
    [ordered]@{name=$_;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash;bytes=([IO.FileInfo]$p).Length}
   })
   $manifest=[ordered]@{
    candidate='1.6.0 RC1';kind='PRODUCT_SOURCE_REVIEW_ONLY';
    installable=$false;publishable=$false;liveRemoteEnabled=$false;
    autoUpdateEnabled=$false;ownerGuiUsesOriginalSource=$true;files=$rows
   }
   [IO.File]::WriteAllText((Join-Path $stage 'owner-source-manifest.json'),
    ($manifest|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
  }
  # Produce an exact ZIP containing only the generated manifest and files.
  Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
  $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
   $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
   try{
    foreach($name in [string[]]$fixture.Expected){
     [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,
      (Join-Path $stage $name),$name,[IO.Compression.CompressionLevel]::Optimal)
    }
   }finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  if($Kind -ceq 'G0'){
   . (Join-Path $repo 'Scripts\rc1-package-integrity.ps1')
   $proof=Get-Rc1PreflightProof -Folder $stage -ArchivePath $archive
   if($proof.Files -ne 7 -or $proof.Digests.Count -ne 6){throw 'HISTORIC_G0_PROOF_FAILED'}
  }
  return $fixture
 }catch{
  try{Remove-Rc1HistoricalFixture $fixture}
  catch{Write-Output ('HISTORIC_FIXTURE_RETAINED_FOR_INSPECTION '+$fixtureRoot)}
  throw
 }
}
