param([Parameter(Mandatory=$true)][string]$PortableZip,[switch]$UseSystemDesktop)
# Real Explorer-equivalent shell activation of extracted private RC1 Portable.
# A scoped named-event fake Host is pre-created: the launcher can *only*
# signal the local test event; it never spawns or controls the real Remote.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$pass=0;$fail=0;$fixture=$null;$activation=$null;$ready=$null
function Check([bool]$good,[string]$label){
 if($good){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Launch([string]$path,[string]$arguments,[bool]$expectedSuccess,[string]$name) {
 $script:activation.Reset() | Out-Null
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$path;$psi.Arguments=$arguments
 $psi.UseShellExecute=$true
 $psi.WorkingDirectory=$script:fixture
 $p=[Diagnostics.Process]::Start($psi)
 if($null -eq $p){throw ('LAUNCH_NO_PROCESS '+$name)}
 try{
  if(-not $p.WaitForExit(15000)){throw ('LAUNCH_TIMEOUT_NO_FORCE_KILL '+$name+' PID='+$p.Id)}
  $signaled=$script:activation.WaitOne(0)
  Check (($p.ExitCode -eq $(if($expectedSuccess){0}else{42})) -and
   ($signaled -eq $expectedSuccess)) ($name+' exit='+$p.ExitCode+' fakeActivation='+$signaled)
 }finally{$p.Dispose()}
}
# The optional path exercises the actual STARMER OneDrive Desktop. Only a
# uniquely named, entirely disposable test directory is ever created there.
# Never modify the user's existing shortcut, installed app, Remote or other
# Desktop entries. Standard mode remains under the OS temp directory.
$base=if($UseSystemDesktop){
 [IO.Path]::GetFullPath([Environment]::GetFolderPath('DesktopDirectory')).TrimEnd([char]92)
}else{[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)}
if(-not [IO.Directory]::Exists($base)){throw 'PORTABLE_TEST_BASE_MISSING'}
$expectedBase=if($UseSystemDesktop){
 [IO.Path]::GetFullPath([Environment]::GetFolderPath('DesktopDirectory')).TrimEnd([char]92)
}else{[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)}
if($base -cne $expectedBase){throw 'PORTABLE_TEST_BASE_CHANGED'}
$fixture=Join-Path $base ('RDC-RC1-PORTABLE-TEST-'+[Guid]::NewGuid().ToString('N'))
Write-Output ('PORTABLE_TEST_MODE='+$(if($UseSystemDesktop){'OS_DESKTOP_CLOUD'}else{'SYSTEM_TEMP'}))
$zipEntries=@()
try{
 if(-not [IO.File]::Exists($PortableZip)){throw 'PORTABLE_ZIP_NOT_FOUND'}
 $archive=[IO.Compression.ZipFile]::OpenRead($PortableZip)
 try{
  $zipEntries=@($archive.Entries | ForEach-Object{$_.FullName})
  Check ($zipEntries.Count -eq 28 -and $zipEntries -ccontains 'RC1 Pilot Launcher.exe' -and
   $zipEntries -ccontains 'owner-source-manifest.json' -and
   $zipEntries -ccontains 'Source/rc1-candidate.json') 'portable ZIP includes EXE, manifest and Source root'
  foreach($name in $zipEntries){
   if($name -notmatch '\A(?:Source/(?:lang/)?[A-Za-z0-9_.-]+|[A-Za-z0-9_. -]+)\z' -or
    $name.IndexOf('..',[StringComparison]::Ordinal) -ge 0){throw ('UNSAFE_ZIP_MEMBER '+$name)}
  }
 }finally{$archive.Dispose()}
 [void][IO.Directory]::CreateDirectory($fixture)
 [IO.Compression.ZipFile]::ExtractToDirectory($PortableZip,$fixture)
 # Validate the unmodified extracted ZIP first. Then replace ONLY the Host
 # entrypoint with a fake throw and update its manifest SHA in this private
 # fixture. If named-event activation ever fails unexpectedly, the launcher
 # cannot start the real Remote; its fallback child only throws and exits.
 $source=Join-Path $fixture 'Source'
 $manifestFile=Join-Path $fixture 'owner-source-manifest.json'
 $verified=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8|ConvertFrom-Json
 $allCorrect=$true
 foreach($row in $verified.files){
  $entry=Join-Path $fixture ([string]$row.name).Replace('/','\')
  if(-not [IO.File]::Exists($entry) -or
     (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash -cne [string]$row.sha256){
   $allCorrect=$false;break
  }
 }
 Check $allCorrect 'unmodified extracted ZIP exactly matches all manifest SHA256'
 if(-not $allCorrect){throw 'UNMODIFIED_ZIP_CONTENT_NOT_TRUSTED'}
 $fakeHost=Join-Path $source 'rc1-tray-host.ps1'
 [IO.File]::WriteAllText($fakeHost,"throw 'RC1_TEST_INERT_HOST_NEVER_REMOTE'"+[Environment]::NewLine,
  (New-Object Text.UTF8Encoding($false)))
 $hostRow=@($verified.files|Where-Object{$_.name -ceq 'Source/rc1-tray-host.ps1'})
 if($hostRow.Count -ne 1){throw 'FAKE_HOST_MANIFEST_MEMBER_NOT_EXACT'}
 $hostRow[0].sha256=(Get-FileHash -LiteralPath $fakeHost -Algorithm SHA256).Hash
 [IO.File]::WriteAllText($manifestFile,($verified|ConvertTo-Json -Depth 8),
  (New-Object Text.UTF8Encoding($false)))
 $launcher=Join-Path $fixture 'RC1 Pilot Launcher.exe'
 $assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($launcher))
 $type=$assembly.GetType('RdcRc1CandidateLauncher',$true)
 $flags=[Reflection.BindingFlags]'Static,NonPublic'
 $keyName=$type.GetMethod('GuiEventName',$flags)
 if(-not $keyName){throw 'PACKAGED_LAUNCHER_EVENT_HELPER_MISSING'}
 [string]$source=Join-Path $fixture 'Source'
 $open=[string]$keyName.Invoke($null,[object[]]@([string]$source))
 $guiReady=$open.Replace('RdcRelayRC1Open-','RdcRelayRC1GuiReady-')
 $wasCreated=$false
 $activation=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$open,[ref]$wasCreated)
 if(-not $wasCreated){throw 'TEST_EVENT_COLLISION'}
 $wasCreated=$false
 $ready=[Threading.EventWaitHandle]::new($true,[Threading.EventResetMode]::ManualReset,$guiReady,[ref]$wasCreated)
 if(-not $wasCreated){throw 'TEST_READY_EVENT_COLLISION'}
 Launch $launcher '' $true 'ordinary Explorer double-click, no arguments'
 Launch $launcher '--full' $true 'existing Setup --full compatibility'
 Launch $launcher '--unknown' $false 'unknown argument denied without signal'
 Launch $launcher '--full --extra' $false 'extra argument denied without signal'
 $marker=Join-Path $source 'rc1-candidate.json'
 $originalMarker=[IO.File]::ReadAllBytes($marker)
 try{
  [IO.File]::WriteAllText($marker,'{"candidate":"1.6.0 RC1","installable":false}',[Text.Encoding]::UTF8)
  Launch $launcher '' $false 'blocked candidate cannot be unlocked by double-click'
 }finally{[IO.File]::WriteAllBytes($marker,$originalMarker)}
 # A changed (even syntactically valid) packaged Host/GUI source must be
 # rejected before any activation signal or process spawn.
 $gui=Join-Path $source 'rc1-owner-gui.ps1'
 $originalGui=[IO.File]::ReadAllBytes($gui)
 try{
  [IO.File]::AppendAllText($gui,'# mutated private payload',[Text.Encoding]::UTF8)
  Launch $launcher '' $false 'changed GUI payload hash denied before activation'
 }finally{[IO.File]::WriteAllBytes($gui,$originalGui)}
 # A Portable without its required manifest must never execute the Host.
 $manifest=Join-Path $fixture 'owner-source-manifest.json'
 $originalManifest=[IO.File]::ReadAllBytes($manifest)
 try{
  [IO.File]::Delete($manifest)
  Launch $launcher '' $false 'missing Portable manifest fails closed'
 }finally{[IO.File]::WriteAllBytes($manifest,$originalManifest)}
}catch{
 $fail++;Write-Output ('FAIL portable fixture '+$_.Exception.Message)
}finally{
 if($activation){$activation.Dispose()}
 if($ready){$ready.Dispose()}
 if($fixture -and [IO.Directory]::Exists($fixture)){
  try{
   $name=[IO.Path]::GetFileName($fixture)
   if($name -cnotmatch '^RDC-RC1-PORTABLE-TEST-[a-f0-9]{32}$' -or
    [IO.Path]::GetDirectoryName($fixture) -cne $base -or
    $base -cne $expectedBase){throw 'TEST_ROOT_SCOPE_REFUSED'}
   $files=@([IO.Directory]::GetFiles($fixture,'*',[IO.SearchOption]::AllDirectories))
   if($files.Count -ne $zipEntries.Count){throw 'TEST_ROOT_FOREIGN_FILE_COUNT'}
   foreach($f in $files){
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'TEST_FILE_REPARSE_DENIED'}
    $relative=$f.Substring($fixture.Length+1).Replace('\','/')
    if($zipEntries -cnotcontains $relative){throw ('TEST_FOREIGN_FILE '+$relative)}
   }
   foreach($f in $files){[IO.File]::Delete($f)}
   $dirs=@([IO.Directory]::GetDirectories($fixture,'*',[IO.SearchOption]::AllDirectories))|
    Sort-Object Length -Descending
   foreach($d in $dirs){[IO.Directory]::Delete($d,$false)}
   [IO.Directory]::Delete($fixture,$false)
   Check (-not [IO.Directory]::Exists($fixture)) 'disposable ZIP content removed exactly'
  }catch{$fail++;Write-Output ('FAIL fixture cleanup refused '+$_.Exception.Message)}
 }
}
Write-Output ('RC1_PORTABLE_DOUBLE_CLICK_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
