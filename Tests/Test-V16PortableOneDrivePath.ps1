# P2 OneDrive Portable path: read-only OS Desktop probe + isolated junction.
# No files are created on Desktop and no Host/Remote/Installer is executed.
$ErrorActionPreference='Stop'
$r=Split-Path -Parent $PSScriptRoot
$src=Join-Path $r 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerLogParts.cs','RdcOwnerStartup.cs','RdcUiLanguage.cs','RdcOwnerRuntime.cs') |
 ForEach-Object {Join-Path $src $_}
$files=@($files)+@(Join-Path $r 'Installer\Rc1CandidateLauncher.cs')
Add-Type -Path $files -ReferencedAssemblies @(
 'System.Core.dll','System.Web.Extensions.dll','System.Security.dll',
 'System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
$launcher=[RdcOwnerStartup].Assembly.GetType('RdcRc1CandidateLauncher')
$manual=@(Add-Type -Path (Join-Path $r 'Installer\Rc1ManualUpgrade.cs') -ReferencedAssemblies @(
 'System.Management.dll') -PassThru | Where-Object {$_.Name -ceq 'RdcRc1ManualUpgrade'})[0]
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$hostGuard=([RdcOwnerRuntime]).GetMethod('CheckParents',$flags)
$job=([RdcOwnerManagedProcess]).GetMethod('SafePath',$flags)
$portable=$launcher.GetMethod('CheckPortablePath',$flags)
$manualCheck=$manual.GetMethod('CheckPath',$flags)
$policy=([RdcOwnerManagedProcess]).Assembly.GetType('RdcOwnerCloudDesktopPath',$false)
$pass=0;$fail=0
function Check([bool]$value,[string]$label){
 if($value){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Allows([Reflection.MethodInfo]$method,[string]$path){
 if($null -eq $method){return $false}
 try{[void]$method.Invoke($null,[object[]]@([string]$path));return $true}
 catch{return $false}
}
function Denies([Reflection.MethodInfo]$method,[string]$path){
 if($null -eq $method){return $false}
 return -not (Allows $method $path)
}
$desktop=[IO.Path]::GetFullPath([Environment]::GetFolderPath('DesktopDirectory'))
$cloudRoot=[IO.Path]::GetDirectoryName($desktop)
$uncreated=Join-Path $desktop 'P2_NONEXISTENT_PORTABLE_PROBE\Source\remote-window.ps1'
$desktopAttributes=[IO.File]::GetAttributes($desktop)
$cloudAttributes=[IO.File]::GetAttributes($cloudRoot)
Check (($desktopAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and
       ($cloudAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'real STARMER Desktop and OneDrive ancestors are Cloud reparse directories'
Check (Allows $manualCheck $uncreated) 'already approved manual Setup cloud ancestor policy allows real Desktop'
Check (Allows $hostGuard $uncreated) 'production Host source path under real OneDrive Desktop accepted'
Check (Allows $job $uncreated) 'production managed Job cwd under real OneDrive Desktop accepted'
Check (Allows $portable $uncreated) 'production Portable launcher source path under real OneDrive Desktop accepted'
Check (Denies $manualCheck $cloudRoot) 'baseline Setup does not permit arbitrary OneDrive root'
Check (Denies $hostGuard $cloudRoot) 'Host does not permit arbitrary OneDrive root'
Check (Denies $job $cloudRoot) 'managed Job does not permit arbitrary OneDrive root'
Check (Denies $portable $cloudRoot) 'Portable launcher does not permit arbitrary OneDrive root'
Check ($null -ne $policy) 'production Host and Job share exact Cloud Desktop ancestor policy'
if($policy){
 $allowed=$policy.GetMethod('IsWindowsDesktopCloudAncestor',
  [Reflection.BindingFlags]'Public,Static,NonPublic')
 Check ($null -ne $allowed) 'Cloud Files tag verified using OS handle, not directory name'
 if($allowed){
  $arr=[object[]]@([string]$desktop,[string]$uncreated)
  Check ([bool]$allowed.Invoke($null,$arr)) 'Cloud Files tag accepted only on OS Desktop ancestry'
  $arr=[object[]]@([string]$cloudRoot,[string]$cloudRoot)
  Check (-not [bool]$allowed.Invoke($null,$arr)) 'OneDrive outside OS Desktop selection cannot self-authorize'
 }
}
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$fixture=Join-Path $base ('RDC-RC1-ONEDRIVE-P2-'+[Guid]::NewGuid().ToString('N'))
$junction=Join-Path $fixture 'untrusted-junction'
$target=Join-Path $fixture 'target'
try{
 [void][IO.Directory]::CreateDirectory($fixture)
 [void][IO.Directory]::CreateDirectory($target)
 $item=New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop
 if(-not (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'JUNCTION_NOT_CREATED'}
 $bad=Join-Path $junction 'Source\remote-window.ps1'
 Check (Denies $hostGuard $bad) 'Host rejects temp junction instead of following it'
 Check (Denies $job $bad) 'managed Job rejects temp junction instead of following it'
 Check (Denies $portable $bad) 'Portable launcher rejects temp junction instead of following it'
 Check (Denies $manualCheck $bad) 'baseline Setup rejects temp junction'
 Check (Allows $hostGuard (Join-Path $target 'Source\remote-window.ps1')) 'Host permits ordinary non-cloud Temp path'
 Check (Allows $job (Join-Path $target 'Source\remote-window.ps1')) 'managed Job permits ordinary non-cloud Temp path'
 Check (Allows $portable (Join-Path $target 'Source\remote-window.ps1')) 'Portable permits ordinary non-cloud Temp path'
}finally{
 if([IO.Directory]::Exists($fixture)){
  try{
   if([IO.Path]::GetDirectoryName($fixture) -cne $base -or
      [IO.Path]::GetFileName($fixture) -cnotmatch '^RDC-RC1-ONEDRIVE-P2-[a-f0-9]{32}$'){
    throw 'TEST_ROOT_SCOPE_REFUSED'
   }
   if([IO.Directory]::Exists($junction)){
    if(([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -eq 0){throw 'JUNCTION_CHANGED'}
    [IO.Directory]::Delete($junction,$false)
   }
   [IO.Directory]::Delete($target,$false)
   [IO.Directory]::Delete($fixture,$false)
   Check (-not [IO.Directory]::Exists($fixture)) 'isolated junction fixture cleaned without traversing target'
  }catch{$fail++;Write-Output ('FAIL fixture cleanup '+$_.Exception.Message)}
 }
}
Write-Output ('RC1_PORTABLE_ONEDRIVE_PATH_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
