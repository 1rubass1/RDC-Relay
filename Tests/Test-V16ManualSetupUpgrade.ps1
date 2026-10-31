# Source-level product Manual Setup replacement contract in disposable USER temp only.
# No live installer, Remote process, stable shortcut or installed app modified.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'Scripts\rc1-private-upgrade-transaction.ps1')
$type=Add-Type -Path (Join-Path $repo 'Installer\Rc1ManualUpgrade.cs') -ReferencedAssemblies @('System.Management.dll') -PassThru |
 Where-Object{$_.Name -eq 'RdcRc1ManualUpgrade'} | Select-Object -First 1
if(-not $type){throw 'RC1_MANUAL_PRODUCT_TYPE_NOT_COMPILED'}
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$prepare=$type.GetMethod('Prepare',$flags)
$activate=$type.GetMethod('ActivateDesktop',$flags)
$pathCheck=$type.GetMethod('CheckPath',$flags)
$canDefer=$type.GetMethod('CanDeferPreviousHost',$flags)
if(-not $prepare -or -not $activate -or -not $pathCheck){throw 'RC1_MANUAL_PRODUCT_METHODS_MISSING'}
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
Check ($null -ne $canDefer) 'MANUAL old Host defer decision available'
if($canDefer){
 Check ([bool]$canDefer.Invoke($null,[object[]]@($true,$true,$true))) 'MANUAL active RC1 Host with verified no Remote can stage deferred upgrade'
 Check (-not [bool]$canDefer.Invoke($null,[object[]]@($true,$true,$false))) 'MANUAL active RC1 Host with Remote or unknown denies'
 Check (-not [bool]$canDefer.Invoke($null,[object[]]@($false,$true,$true))) 'MANUAL unrelated Host cannot receive RC1 defer privilege'
 Check (-not [bool]$canDefer.Invoke($null,[object[]]@($true,$false,$true))) 'MANUAL deferred route only when old Host really active'
}
# STARMER's OS-reported Desktop is under OneDrive Cloud Files reparse
# directories. Read-only product path validation must accept that exact
# Windows Cloud tag while rejecting any arbitrary junction/symlink.
[void]$pathCheck.Invoke($null,[object[]]@([Environment]::GetFolderPath('DesktopDirectory')))
Check $true 'MANUAL real OS Cloud Files Desktop path accepted'
[void]$pathCheck.Invoke($null,[object[]]@([IO.Path]::Combine(
 [Environment]::GetFolderPath('DesktopDirectory'),'RDC Relay.lnk')))
Check $true 'MANUAL real Desktop shortcut path accepted'
$oneDrive=[IO.Path]::GetDirectoryName([Environment]::GetFolderPath('DesktopDirectory'))
if(([IO.File]::GetAttributes($oneDrive) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
 $denied=$false
 try{[void]$pathCheck.Invoke($null,[object[]]@($oneDrive))}catch{$denied=$true}
 Check $denied 'MANUAL unrelated Cloud root remains refused'
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-MANUAL-'+[Guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($root)
 [IO.File]::WriteAllText((Join-Path $root 'run-sentinel.txt'),[IO.Path]::GetFileName($root))
 $package=Join-Path $root 'package'
 $local=Join-Path $root 'local'
 $desktop=Join-Path $root 'desktop'
 [void][IO.Directory]::CreateDirectory($package)
 [void][IO.Directory]::CreateDirectory($local)
 [void][IO.Directory]::CreateDirectory($desktop)
 $required=[string[]]@($script:Rc1UpgRequired)
 foreach($name in $required){
  $f=Join-Path $package ($name.Replace('/','\'))
  $parent=[IO.Path]::GetDirectoryName($f)
  if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
  [IO.File]::WriteAllText($f,('G8_MANUAL_DISPOSABLE_'+$name))
 }
 [IO.File]::WriteAllText((Join-Path $package 'owner-source-manifest.json'),'ONE_TIME_G8_MANUAL')
 $a=New-Object object[] 3
 $a[0]=[string]$package;$a[1]=[string]$local;$a[2]=[string[]]$required
 $release=[string]$prepare.Invoke($null,$a)
 Check ([IO.Directory]::Exists($release) -and
  [IO.File]::Exists((Join-Path $release 'RC1 Pilot Launcher.exe'))) 'MANUAL immutable first release staged'
 Check ((Get-FileHash -LiteralPath (Join-Path $release 'owner-source-manifest.json') -Algorithm SHA256).Hash -eq
  (Get-FileHash -LiteralPath (Join-Path $package 'owner-source-manifest.json') -Algorithm SHA256).Hash) 'MANUAL manifest SHA preserved'
 $again=[string]$prepare.Invoke($null,$a)
 Check ($release -ceq $again) 'MANUAL identical setup idempotent'
 [IO.File]::WriteAllText((Join-Path $release 'Source\remote-window.ps1'),'UNAPPROVED_MODIFICATION')
 $denied=$false;try{[void]$prepare.Invoke($null,$a)}catch{$denied=$true}
 Check $denied 'MANUAL altered previous release fails closed'
 [IO.File]::WriteAllText((Join-Path $release 'Source\remote-window.ps1'),
  'G8_MANUAL_DISPOSABLE_Source/remote-window.ps1')
 $legacy=Join-Path $local 'RemoteDesktopCommanderLauncher'
 [void][IO.Directory]::CreateDirectory($legacy)
 [IO.File]::WriteAllText((Join-Path $legacy 'version.txt'),'1.5.18')
 [IO.File]::WriteAllText((Join-Path $legacy 'remote-window.ps1'),'G8_LEGACY_FAKE')
 $shortcutFile=Join-Path $desktop 'RDC Relay.lnk'
 $ws=New-Object -ComObject WScript.Shell
 $short=$ws.CreateShortcut($shortcutFile)
 $short.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $short.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $legacy 'remote-window.ps1')+'"'
 $short.Save()
 $b=New-Object object[] 3
 $b[0]=[string]$release;$b[1]=[string]$local;$b[2]=[string]$desktop
 $switch=[string]$activate.Invoke($null,$b)
 $active=$ws.CreateShortcut($shortcutFile)
 Check ($switch -ceq 'SWITCHED_STABLE' -and
  $active.TargetPath -ieq (Join-Path $release 'RC1 Pilot Launcher.exe')) 'MANUAL recognized stable shortcut switched'
 $backup=@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($release)) -Filter 'primary-shortcut-backup-*.lnk' -File)
 Check ($backup.Count -eq 1 -and
  $ws.CreateShortcut($backup[0].FullName).TargetPath -ieq $short.TargetPath) 'MANUAL old shortcut recoverably backed up'
 Check (([string]$activate.Invoke($null,$b)) -ceq 'ALREADY_ACTIVE') 'MANUAL repeated shortcut switch idempotent'
 # A later RC1 may have a live Host. Exact old Host mutex locks out
 # shortcut replacement until the earlier Host has fully exited.
 # All checks run against a disposable fake release; no real Host involved.
 $nextPackage=Join-Path $root 'next-package'
 [void][IO.Directory]::CreateDirectory($nextPackage)
 foreach($name in $required){
  $input=Join-Path $package ($name.Replace('/','\'))
  $output=Join-Path $nextPackage ($name.Replace('/','\'))
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
  [IO.File]::Copy($input,$output,$false)
 }
 [IO.File]::WriteAllText((Join-Path $nextPackage 'owner-source-manifest.json'),'ONE_TIME_G8_NEXT_RELEASE')
 $a[0]=[string]$nextPackage
 $nextRelease=[string]$prepare.Invoke($null,$a)
 $b[0]=[string]$nextRelease
 $mutexMethod=$type.GetMethod('OldHostMutexName',$flags)
 if(-not $mutexMethod){throw 'MANUAL_OLD_HOST_MUTEX_METHOD_MISSING'}
 $oldHostMutex=[string]$mutexMethod.Invoke($null,[object[]]@($release))
 $created=$false
 $held=[System.Threading.Mutex]::new($true,$oldHostMutex,[ref]$created)
 if(-not $created){throw 'MANUAL_DISPOSABLE_HOST_MUTEX_ALREADY_TAKEN'}
 try{
  $denied=$false;try{[void]$activate.Invoke($null,$b)}catch{$denied=$true}
  Check ($denied -and $nextRelease -cne $release -and
   $ws.CreateShortcut($shortcutFile).TargetPath -ieq (Join-Path $release 'RC1 Pilot Launcher.exe') -and
   [IO.Directory]::Exists($nextRelease) -and
   @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($release)) -Filter 'primary-shortcut-backup-*.lnk' -File).Count -eq 1) 'MANUAL live old Host mutex denies RC1 replacement without touching old files'
 }finally{$held.ReleaseMutex();$held.Dispose()}
 $switch=[string]$activate.Invoke($null,$b)
 Check ($switch -ceq 'SWITCHED_RC1' -and
  $ws.CreateShortcut($shortcutFile).TargetPath -ieq (Join-Path $nextRelease 'RC1 Pilot Launcher.exe') -and
  @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($release)) -Filter 'primary-shortcut-backup-*.lnk' -File).Count -eq 2) 'MANUAL exited old Host permits RC1 to RC1 shortcut handoff with backup'
 $badDesktop=Join-Path $root 'unrelated-desktop'
 [void][IO.Directory]::CreateDirectory($badDesktop)
 $bad=Join-Path $badDesktop 'RDC Relay.lnk'
 $badLink=$ws.CreateShortcut($bad)
 $badLink.TargetPath=Join-Path $env:WINDIR 'System32\notepad.exe'
 $badLink.Save()
 $before=(Get-FileHash -LiteralPath $bad -Algorithm SHA256).Hash
 $b[2]=[string]$badDesktop
 $denied=$false;try{[void]$activate.Invoke($null,$b)}catch{$denied=$true}
 Check ($denied -and (Get-FileHash -LiteralPath $bad -Algorithm SHA256).Hash -eq $before) 'MANUAL foreign shortcut preserved'
 $trickDesktop=Join-Path $root 'trick-desktop'
 [void][IO.Directory]::CreateDirectory($trickDesktop)
 $trickPath=Join-Path $trickDesktop 'RDC Relay.lnk'
 $trick=$ws.CreateShortcut($trickPath)
 $trick.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $trick.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+
  (Join-Path $legacy 'remote-window.ps1')+'" -Command evil'
 $trick.Save()
 $before=(Get-FileHash -LiteralPath $trickPath -Algorithm SHA256).Hash
 $b[2]=[string]$trickDesktop
 $denied=$false;try{[void]$activate.Invoke($null,$b)}catch{$denied=$true}
 Check ($denied -and (Get-FileHash -LiteralPath $trickPath -Algorithm SHA256).Hash -eq $before) 'MANUAL piggybacked legacy args denied'
 $newDesktop=Join-Path $root 'new-desktop'
 [void][IO.Directory]::CreateDirectory($newDesktop)
 $b[2]=[string]$newDesktop
 Check (([string]$activate.Invoke($null,$b)) -ceq 'CREATED' -and
  [IO.File]::Exists((Join-Path $newDesktop 'RDC Relay.lnk'))) 'MANUAL first install shortcut created'
}catch{$fail++;Write-Output ('FAIL MANUAL exception '+$_.Exception.Message)}
finally{
 try{
  if([IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92) -or
   [IO.Path]::GetFileName($root) -cnotmatch '^RDC-RC1-MANUAL-[a-f0-9]{32}$' -or
   [IO.File]::ReadAllText((Join-Path $root 'run-sentinel.txt')) -cne [IO.Path]::GetFileName($root)){
   throw 'MANUAL_CLEANUP_SCOPE_REFUSED'
  }
  foreach($entry in @(Get-ChildItem -LiteralPath $root -Force -Recurse)){
   if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'MANUAL_CLEANUP_REPARSE'}
  }
  [IO.Directory]::Delete($root,$true)
  Check (-not [IO.Directory]::Exists($root)) 'MANUAL disposable root cleaned'
 }catch{$fail++;Write-Output ('FAIL MANUAL ROOT NOT CLEAN '+$root)}
}
Write-Output ('RC1_MANUAL_SETUP_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
