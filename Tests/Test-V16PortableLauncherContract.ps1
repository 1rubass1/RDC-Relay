# Pure production launcher contract + disposable exact-manifest negative tests.
# Compiles the launcher as a library; NEVER invokes its Main or starts a Host.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Installer\Rc1CandidateLauncher.cs'
$types=@(Add-Type -Path @($source,(Join-Path $root 'Installer\RdcNodePrerequisite.cs'),(Join-Path $root 'Source\RdcOwnerStartup.cs')) -ReferencedAssemblies @('System.Core.dll',
 'System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll') -PassThru)
$type=$types|Where-Object{$_.Name -ceq 'RdcRc1CandidateLauncher'}|Select-Object -First 1
if(-not $type){throw 'COMPILED_LAUNCHER_TYPE_ABSENT'}
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$intent=$type.GetMethod('FullLaunchRequested',$flags)
$validate=$type.GetMethod('ValidatePortablePackage',$flags)
$required=$type.GetField('PortableFiles',$flags)
$pass=0;$fail=0
function Check([bool]$yes,[string]$label){
 if($yes){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Allowed([string[]]$argsForMode){
 $arr=New-Object 'System.Object[]' 1
 $arr[0]=$argsForMode
 return [bool]$intent.Invoke($null,$arr)
}
function ValidManifest([string]$location){
 try{
  [void]$validate.Invoke($null,[object[]]@([string]$location))
  return $true
 }catch{return $false}
}
Check ($null -ne $intent -and $null -ne $validate -and $null -ne $required) 'compiled launcher provides intent and manifest contract'
Check (Allowed ([string[]]@())) 'zero-argument double-click is authorized intent'
Check (Allowed ([string[]]@('--full'))) 'Setup explicit --full preserved'
foreach($case in @(
 [string[]]@('--unknown'),
 [string[]]@('--full','extra'),
 [string[]]@('--Full'),
 [string[]]@(''),
 [string[]]@('--owner-approved-manual-upgrade')
)){
 Check (-not (Allowed $case)) ('only exact full launch intents accepted: '+[string]::Join(' ',[string[]]$case))
}
$manifestFiles=[string[]]$required.GetValue($null)
Check ($manifestFiles.Length -eq 27 -and
 ($manifestFiles|Select-Object -Unique).Count -eq 27 -and
 $manifestFiles -contains 'Source/RdcOwnerLogParts.cs' -and
 $manifestFiles -contains 'Source/rc1-candidate.json' -and
 $manifestFiles -contains 'RC1 Pilot Launcher.exe') 'exact 27 required package members bound into compiled launcher'
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$fixture=Join-Path $base ('RDC-RC1-LAUNCH-CONTRACT-'+[Guid]::NewGuid().ToString('N'))
$paths=New-Object 'System.Collections.Generic.List[string]'
try{
 [void][IO.Directory]::CreateDirectory($fixture)
 $rows=@()
 foreach($name in $manifestFiles){
  $path=Join-Path $fixture ($name.Replace('/','\'))
  $parent=[IO.Path]::GetDirectoryName($path)
  if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
  [IO.File]::WriteAllText($path,'fake owned fixture '+$name,[Text.Encoding]::UTF8)
  $paths.Add($path)
  $rows+=@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
 }
 $manifest=@{
  candidate='1.6.0 RC1';kind='PRIVATE_FULL_RC1';ownerMode='FULL_HOST_GUI_RC1';
  installable=$true;publishable=$false;files=@($rows)
 }
 $manifestFile=Join-Path $fixture 'owner-source-manifest.json'
 function WriteManifest {
  [IO.File]::WriteAllText($manifestFile,($manifest|ConvertTo-Json -Depth 8),
    (New-Object Text.UTF8Encoding($false)))
 }
 WriteManifest
 $paths.Add($manifestFile)
 Check (ValidManifest $fixture) 'all exact members with correct SHA pass'
 $tamper=Join-Path $fixture 'Source\rc1-owner-gui.ps1'
 $original=[IO.File]::ReadAllBytes($tamper)
 try{
  [IO.File]::AppendAllText($tamper,'changing even one source byte',[Text.Encoding]::UTF8)
  Check (-not (ValidManifest $fixture)) 'tampered payload hash rejected'
 }finally{[IO.File]::WriteAllBytes($tamper,$original)}
 [IO.File]::Delete($manifestFile)
 Check (-not (ValidManifest $fixture)) 'missing manifest rejected'
 WriteManifest
 $manifest.publishable=$true;WriteManifest
 Check (-not (ValidManifest $fixture)) 'public/release marker rejected'
 $manifest.publishable=$false;WriteManifest
 $manifest.ownerMode='OBSERVED_READ_ONLY_RC1';WriteManifest
 Check (-not (ValidManifest $fixture)) 'wrong owner mode refused'
 $manifest.ownerMode='FULL_HOST_GUI_RC1';WriteManifest
 $manifest.files=@($rows[0..20]+$rows[0]);WriteManifest
 Check (-not (ValidManifest $fixture)) 'duplicate member replacing required item refused'
 $manifest.files=@($rows);WriteManifest
 Check (ValidManifest $fixture) 'valid manifest recovers after negative controls'
}catch{
 $fail++;Write-Output ('FAIL launcher fixture '+$_.Exception.Message)
}finally{
 if([IO.Directory]::Exists($fixture)){
  try{
   if([IO.Path]::GetFileName($fixture) -cnotmatch '^RDC-RC1-LAUNCH-CONTRACT-[a-f0-9]{32}$' -or
    [IO.Path]::GetDirectoryName($fixture) -cne $base){throw 'LAUNCH_TEST_SCOPE_REFUSED'}
   $actual=@([IO.Directory]::GetFiles($fixture,'*',[IO.SearchOption]::AllDirectories))
   if($actual.Count -ne $paths.Count){throw 'LAUNCH_TEST_FOREIGN_FILES'}
   foreach($p in $actual){
    if(-not $paths.Contains($p) -or
     ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
     throw 'LAUNCH_TEST_UNEXPECTED_MEMBER'
    }
   }
   foreach($p in $actual){[IO.File]::Delete($p)}
   $dirs=@([IO.Directory]::GetDirectories($fixture,'*',[IO.SearchOption]::AllDirectories))|Sort-Object Length -Descending
   foreach($d in $dirs){[IO.Directory]::Delete($d,$false)}
   [IO.Directory]::Delete($fixture,$false)
   Check (-not [IO.Directory]::Exists($fixture)) 'contract fixture exactly removed'
  }catch{$fail++;Write-Output ('FAIL contract cleanup refused '+$_.Exception.Message)}
 }
}
Write-Output ('RC1_PORTABLE_LAUNCH_CONTRACT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
