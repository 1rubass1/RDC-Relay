# Isolated C# review-package verification / durable-stage compatibility.
# Only synthetic disposable Temp files; no build, install, Host, Remote, ARP.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$types=@(Add-Type -Path @(
 (Join-Path $repo 'Installer\RdcReleaseDurableStage.cs'),
 (Join-Path $repo 'Installer\RdcReleaseReviewPackage.cs')
) -ReferencedAssemblies @('System.dll','System.Core.dll',
 'System.Web.Extensions.dll') -PassThru -ErrorAction Stop)
$review=@($types|Where-Object{$_.Name -ceq 'RdcReleaseReviewPackage'})|Select-Object -First 1
$stage=@($types|Where-Object{$_.Name -ceq 'RdcReleaseDurableStage'})|Select-Object -First 1
$binding=[Reflection.BindingFlags]'Static,NonPublic,Public'
$members=@($review.GetField('Required',$binding).GetValue($null))
$verify=$review.GetMethod('Validate',$binding)
$prepare=$stage.GetMethod('Prepare',$binding)
$recover=$stage.GetMethod('Recover',$binding)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
function Refused([scriptblock]$operation,[string]$name){
 try{& $operation|Out-Null;Check $false $name}
 catch{
  $message=$_.Exception.ToString()
  Check ($message -match 'RDC_REVIEW_|RDC_STAGE_') $name
 }
}
$dir=Join-Path $env:TEMP ('RDC-V16-ReviewTest-'+[Guid]::NewGuid().ToString('N'))
$pkg=Join-Path $dir 'package'
$payload=Join-Path $pkg 'payload'
[void][IO.Directory]::CreateDirectory($payload)
$utf8=New-Object Text.UTF8Encoding($false)
function LoadManifest {
 return (Get-Content (Join-Path $pkg 'review-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json)
}
function WriteManifest([object]$model){
 [IO.File]::WriteAllText((Join-Path $pkg 'review-manifest.json'),
  ($model|ConvertTo-Json -Depth 10),$utf8)
}
function VerifyPackage {
 return ,($verify.Invoke($null,[object[]]@([string]$pkg)))
}
try{
 Check ($members.Count -eq 27 -and
  @($members|Select-Object -Unique).Count -eq $members.Count) 'exact 27-member Host GUI review allowlist'
 Check ($members -ccontains 'Source/rc1-owner-gui.ps1' -and
  $members -ccontains 'Source/rc1-tray-host.ps1' -and
  $members -ccontains 'RdcOwnerRuntime.dll') 'separate GUI Host DLL contract'
 Check ($members -cnotcontains 'Source/rc1-candidate.json' -and
  $members -cnotcontains 'RC1 Pilot Launcher.exe' -and
  $members -cnotcontains 'RC1 Pilot Setup.exe') 'private release marker and installer excluded'
 $rows=@()
 foreach($member in $members){
  $file=Join-Path $payload ($member.Replace('/',[IO.Path]::DirectorySeparatorChar))
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
  $content=if($member -ceq 'Source/version.txt'){'1.6.0'}
  elseif($member -ceq 'Source/release-review.json'){
   '{"kind":"FULL_HOST_GUI_SOURCE_REVIEW_ONLY","version":"1.6.0","installable":false,"launchEnabled":false}'
  }else{'synthetic-review:'+ $member}
  if($member -cin @('Source/remote-window.ps1','Source/rc1-tray-host.ps1',
    'Source/rc1-quota-client.ps1','Source/update.ps1')){
   $content="# synthetic review script"+[Environment]::NewLine+
    "throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'"+[Environment]::NewLine+$content
  }
  [IO.File]::WriteAllText($file,$content,$utf8)
  $rows += [ordered]@{
   name=$member;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();
   bytes=[long]([IO.FileInfo]$file).Length
  }
 }
 $original=[ordered]@{
  schema=1;kind='FULL_HOST_GUI_SOURCE_REVIEW_ONLY';version='1.6.0';publisher='RUBASS';
  installable=$false;publishable=$false;launchEnabled=$false;files=$rows
 }
 WriteManifest $original
 $validated=VerifyPackage
 Check ($validated.Count -eq 27) 'real C# contract accepts exact inert source package'
 Check ($validated[0].Length -gt 0) 'trusted-metadata candidate has bounded lengths'
 $compiler=@((Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|
  Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
 if(-not $compiler){throw 'RDC_REVIEW_CSC_TEST_UNAVAILABLE'}
 $checker=Join-Path $dir 'OfflineReviewCheck.exe'
 $sources=@(
  (Join-Path $repo 'Installer/RdcReleaseDurableStage.cs'),
  (Join-Path $repo 'Installer/RdcReleaseReviewPackage.cs'),
  (Join-Path $repo 'Installer/RdcReleaseReviewVerifier.cs')
 )
 $checkerArguments=@('/nologo','/target:exe','/optimize+',
  '/main:RdcReleaseReviewVerifier',('/out:'+$checker),
  '/reference:System.Core.dll','/reference:System.Web.Extensions.dll')+$sources
 & $compiler @checkerArguments |Out-Null
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($checker)){
  throw 'RDC_REVIEW_CHECKER_COMPILE_FAILED'
 }
 $meta=[Diagnostics.FileVersionInfo]::GetVersionInfo($checker)
 Check ($meta.FileVersion -ceq '1.6.0.0' -and $meta.CompanyName -ceq 'RUBASS') 'standalone verifier carries the distinct release identity'
 function CheckBinary([bool]$withArgs){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$checker
  $psi.Arguments=if($withArgs){'--verify "'+$pkg+'"'}else{''}
  $psi.UseShellExecute=$false
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $psi.CreateNoWindow=$true
  $proc=[Diagnostics.Process]::Start($psi)
  if(!$proc.WaitForExit(10000)){
   $proc.Kill();throw 'RDC_REVIEW_CHECKER_TEST_TIMEOUT'
  }
  return @{Exit=$proc.ExitCode;Out=$proc.StandardOutput.ReadToEnd();Err=$proc.StandardError.ReadToEnd()}
 }
 $report=CheckBinary $true
 Check ($report.Exit -eq 0 -and $report.Out.Contains('RDC_RELEASE_REVIEW_PACKAGE_PASS=27 FAIL=0')) 'standalone verifier accepts intact extracted review package'
 $refusal=CheckBinary $false
 Check ($refusal.Exit -eq 42 -and $refusal.Err.Contains('RDC_RELEASE_REVIEW_NO_INSTALL_OR_REMOTE')) 'standalone verifier has no default launch path'
 $planMethod=$stage.GetMethod('Plan',[Reflection.BindingFlags]'Static,NonPublic')
 $planArgs=New-Object object[] 2
 $planArgs[0]=$validated
 $planArgs[1]=$null
 Refused {[void]$planMethod.Invoke($null,$planArgs)} 'review-only marker rejected by durable release plan'
 $store=Join-Path $dir 'store'
 [void][IO.Directory]::CreateDirectory($store)
 Refused {[void]$prepare.Invoke($null,[object[]]@([string]$payload,[string]$store,$validated))} 'review-only package cannot enter installable durable stage'
 Check (-not [IO.Directory]::Exists((Join-Path $store 'releases'))) 'stage refuses before writing a transaction journal'
 Check (-not [IO.File]::Exists((Join-Path $dir 'RDC Relay.lnk'))) 'no shortcut created by read-only verification'
 $originalCopy=[IO.File]::ReadAllBytes((Join-Path $payload 'RdcOwnerRuntime.dll'))
 [IO.File]::AppendAllText((Join-Path $payload 'RdcOwnerRuntime.dll'),'corrupt')
 Refused {VerifyPackage} 'tampered runtime hash is rejected'
 [IO.File]::WriteAllBytes((Join-Path $payload 'RdcOwnerRuntime.dll'),$originalCopy)
 $model=LoadManifest;$model.installable=$true;WriteManifest $model
 Refused {VerifyPackage} 'installable=true forbidden'
 $model=LoadManifest;$model.installable=$false;$model.launchEnabled=$true;WriteManifest $model
 Refused {VerifyPackage} 'launchEnabled=true forbidden'
 $model=LoadManifest;$model.launchEnabled=$false;$model.publishable=$true;WriteManifest $model
 Refused {VerifyPackage} 'publishable=true forbidden'
 $model=LoadManifest;$model.publishable=$false;$model.kind='PRIVATE_FULL_RC1';WriteManifest $model
 Refused {VerifyPackage} 'private pilot kind refused'
 $model=LoadManifest;$model.kind='FULL_HOST_GUI_SOURCE_REVIEW_ONLY';$model.version='1.5.18';WriteManifest $model
 Refused {VerifyPackage} 'legacy version refused'
 $model=LoadManifest;$model.version='1.6.0';$model.publisher='UMAS';WriteManifest $model
 Refused {VerifyPackage} 'publisher mismatch refused'
 WriteManifest $original
 $guardFile=Join-Path $payload 'Source\rc1-tray-host.ps1'
 $guardBackup=[IO.File]::ReadAllBytes($guardFile)
 $guardText=[IO.File]::ReadAllText($guardFile,[Text.Encoding]::UTF8)
 [IO.File]::WriteAllText($guardFile,
  $guardText.Replace("throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'",
   "throw 'RDC_REVIEW_TEST_REMOVED_GUARD'"),$utf8)
 $model=LoadManifest
 $guardEntry=@($model.files|Where-Object{$_.name -ceq 'Source/rc1-tray-host.ps1'})[0]
 $guardEntry.bytes=[long]([IO.FileInfo]$guardFile).Length
 $guardEntry.sha256=(Get-FileHash -LiteralPath $guardFile -Algorithm SHA256).Hash.ToLowerInvariant()
 WriteManifest $model
 Refused {VerifyPackage} 'removed launch guard refused even with matching modified hashes'
 [IO.File]::WriteAllBytes($guardFile,$guardBackup)
 WriteManifest $original
 $model=LoadManifest;$model.files=@($model.files|Select-Object -Skip 1);WriteManifest $model
 Refused {VerifyPackage} 'missing manifest member refused'
 WriteManifest $original
 $model=LoadManifest;$model.files[0].name='../escape.ps1';WriteManifest $model
 Refused {VerifyPackage} 'unlisted traversal rejected before path resolution'
 WriteManifest $original
 $model=LoadManifest;$model.files[0].name=$model.files[1].name;WriteManifest $model
 Refused {VerifyPackage} 'duplicate member rejected'
 WriteManifest $original
 $model=LoadManifest;$model.files[0].sha256='G'*64;WriteManifest $model
 Refused {VerifyPackage} 'nonhex SHA rejected'
 WriteManifest $original
 $model=LoadManifest;$model.files[0].bytes=-1;WriteManifest $model
 Refused {VerifyPackage} 'negative member length rejected'
 WriteManifest $original
 [IO.File]::WriteAllText((Join-Path $payload 'Source\rc1-candidate.json'),'private marker',$utf8)
 Refused {VerifyPackage} 'extra private marker refused by filesystem allowlist'
 [IO.File]::Delete((Join-Path $payload 'Source\rc1-candidate.json'))
 [IO.File]::WriteAllText((Join-Path $payload 'unknown.exe'),'unexpected',$utf8)
 Refused {VerifyPackage} 'extra file refused by filesystem allowlist'
 [IO.File]::Delete((Join-Path $payload 'unknown.exe'))
 $versionFile=Join-Path $payload 'Source\version.txt'
 [IO.File]::WriteAllText($versionFile,'1.5.18',$utf8)
 Refused {VerifyPackage} 'legacy source version not accepted even if hashes remain unchanged'
 [IO.File]::WriteAllText($versionFile,'1.6.0',$utf8)
 WriteManifest $original
 Check ((VerifyPackage).Count -eq 27) 'fixture restores exact validated candidate'
 $builder=Join-Path $repo 'Scripts\build-v16-release-review.ps1'
 $script=[IO.File]::ReadAllText($builder,[Text.Encoding]::UTF8)
 Check ($script.Contains("if(-not " + '$Build' + "){Write-Output 'RDC_V16_REVIEW_BUILDER_INERT_USE_BUILD';exit 42}")) 'builder requires explicit Build switch or exits inert'
 Check ($script.Contains('RDC_V16_REVIEW_REQUIRES_CLEAN_SOURCE') -and
  $script.Contains('RDC_V16_REVIEW_WRONG_TOPIC_BRANCH')) 'review builder requires clean exact branch'
 Check ($script.Contains('RDC_V16_NOT_INSTALLABLE_NOT_LAUNCHABLE=TRUE') -and
  -not $script.Contains('Start-Process') -and -not $script.Contains('New-ItemProperty')) 'review builder neither runs product nor writes OS metadata'
 Check ($script.Contains("'Source/version.txt','Source/release-review.json','RdcOwnerRuntime.dll'") -and
  $script.Contains("'1.6.0'+[Environment]::NewLine")) 'review version file generated independently from legacy checkout'
}finally{
 if(Test-Path -LiteralPath $dir){
  # Reject symlink test-fixture deletion through uncontrolled paths.
  $entries=@(Get-ChildItem -LiteralPath $dir -Recurse -Force)
  if(@($entries|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count){
   throw 'RDC_REVIEW_TEST_FIXTURE_REPARSE_REFUSED'
  }
  Remove-Item -LiteralPath $dir -Recurse -Force
 }
}
Write-Output ('RDC_V16_RELEASE_REVIEW_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
