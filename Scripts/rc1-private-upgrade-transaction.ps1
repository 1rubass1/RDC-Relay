# Production private RC1 candidate manifest attestation and recoverable late-upgrade.
# Inert when dot-sourced. Never starts, stops, logs out, or touches Desktop Commander Remote.
$script:Rc1UpgRequired=@(
 'Source/remote-window.ps1','Source/rc1-tray-host.ps1','Source/rc1-owner-gui.ps1',
 'Source/rc1-remote-observer.ps1','Source/RdcOwnerWire.cs','Source/RdcOwnerRuntime.cs',
 'Source/RdcOwnerProcess.cs','Source/RdcOwnerTicketStore.cs','Source/RdcOwnerRemoteState.cs',
 'Source/rc1-candidate.json','Source/RDCRelay.ico',
 'Source/divider-caustic.ps','Source/divider-caustic-detail.ps',
 'Source/divider-particles.ps','Source/divider-particles-core.ps',
 'Source/update-notice.ps1','Source/update.ps1','RdcOwnerRuntime.dll',
 'RC1 Pilot Launcher.exe'
)
function Assert-Rc1UpgNoReparse([string]$path){
 $cursor=[IO.Path]::GetFullPath($path)
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'RC1_UPGRADE_REPARSE_DENIED'
   }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if(-not $parent -or $parent -ceq $cursor){break}
  $cursor=$parent
 }
}
function Assert-Rc1UpgPayload([string]$dir,[string]$expectedManifestSha=''){
 $dir=[IO.Path]::GetFullPath($dir).TrimEnd([char]92)
 Assert-Rc1UpgNoReparse $dir
 if(-not [IO.Directory]::Exists($dir)){throw 'RC1_UPGRADE_APP_ABSENT'}
 $manifestPath=Join-Path $dir 'owner-source-manifest.json'
 Assert-Rc1UpgNoReparse $manifestPath
 if(-not [IO.File]::Exists($manifestPath)){throw 'RC1_UPGRADE_MANIFEST_ABSENT'}
 $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
 if($expectedManifestSha -and $manifestSha -cne $expectedManifestSha){throw 'RC1_UPGRADE_MANIFEST_FINGERPRINT_MISMATCH'}
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
 if($manifest.candidate -cne '1.6.0 RC1' -or
    $manifest.observerMode -cne 'OBSERVED_READ_ONLY_RC1' -or
    $manifest.publishable -ne $false -or $manifest.installable -ne $true -or
    @($manifest.files).Count -ne $script:Rc1UpgRequired.Count){throw 'RC1_UPGRADE_BAD_MANIFEST'}
 $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
 foreach($row in $manifest.files){
  $name=[string]$row.name
  if($script:Rc1UpgRequired -cnotcontains $name -or -not $seen.Add($name) -or
     [string]$row.sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'RC1_UPGRADE_MANIFEST_MEMBER'}
  $file=Join-Path $dir ($name.Replace('/','\'))
  Assert-Rc1UpgNoReparse $file
  if(-not [IO.File]::Exists($file) -or
     (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne [string]$row.sha256){
   throw ('RC1_UPGRADE_FILE_HASH '+$name)
  }
 }
 foreach($name in $script:Rc1UpgRequired){
  if(-not $seen.Contains($name)){throw ('RC1_UPGRADE_MISSING_MEMBER '+$name)}
 }
 $actual=@([IO.Directory]::GetFiles($dir,'*',[IO.SearchOption]::AllDirectories) |
  ForEach-Object{$_.Substring($dir.Length+1).Replace('\','/')})
 $expected=@($script:Rc1UpgRequired)+@('owner-source-manifest.json')
 if($actual.Count -ne $expected.Count -or
    @($actual|Where-Object{$expected -cnotcontains $_}).Count -ne 0){
  throw 'RC1_UPGRADE_UNKNOWN_OR_MISSING_FILES'
 }
 $dirs=@([IO.Directory]::GetDirectories($dir,'*',[IO.SearchOption]::AllDirectories) |
  ForEach-Object{$_.Substring($dir.Length+1).Replace('\','/')})
 if($dirs.Count -ne 1 -or $dirs[0] -cne 'Source'){throw 'RC1_UPGRADE_UNKNOWN_DIRECTORIES'}
 $candidate=Get-Content -LiteralPath (Join-Path $dir 'Source\rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($candidate.installable -ne $true -or $candidate.publishable -ne $false -or
    $candidate.autoUpdateEnabled -ne $false -or
    $candidate.observerMode -cne 'OBSERVED_READ_ONLY_RC1' -or
    $candidate.remoteStopEnabled -ne $false -or
    $candidate.remoteLaunchEnabled -ne $false -or
    $candidate.accountMutationEnabled -ne $false){throw 'RC1_UPGRADE_MARKER_NOT_OBSERVER'}
 return $manifestSha
}
function Test-Rc1UpgNoActiveApp([string]$app,[string[]]$TrialInjectedActive=@()){
 if(@($TrialInjectedActive).Count -ne 0){return $false}
 # The caller has no authority to stop any unknown/running RC1 process.
 # Check both persistent PowerShell Host/GUI and the short-lived Launcher.
 $rows=@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object{
  $line=[string]$_.CommandLine
  $line.IndexOf((Join-Path $app 'Source\'),[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
  $line.IndexOf((Join-Path $app 'RC1 Pilot Launcher.exe'),[StringComparison]::OrdinalIgnoreCase) -ge 0
 })
 return $rows.Count -eq 0
}
function Invoke-Rc1UpgRecover([string]$app,[string]$backup,
 [string]$oldManifestSha,[string]$newManifestSha,[bool]$newAppPublishedByThisRun,
 [string[]]$TrialInjectedActive=@()){
 $app=[IO.Path]::GetFullPath($app).TrimEnd([char]92)
 $backup=[IO.Path]::GetFullPath($backup).TrimEnd([char]92)
 $root=[IO.Path]::GetDirectoryName($app)
 if([IO.Path]::GetFileName($app) -cne 'app' -or
    [IO.Path]::GetDirectoryName($backup) -cne $root -or
    [IO.Path]::GetFileName($backup) -cnotmatch '^app-backup-[a-f0-9]{32}$' -or
    $oldManifestSha -cnotmatch '^[A-F0-9]{64}$' -or
    $newManifestSha -cnotmatch '^[A-F0-9]{64}$'){
  throw 'RC1_UPGRADE_RECOVERY_SCOPE'
 }
 Assert-Rc1UpgNoReparse $root
 $checkOld=Assert-Rc1UpgPayload $backup $oldManifestSha
 $failed=''
 if([IO.Directory]::Exists($app) -or [IO.File]::Exists($app)){
  if(-not $newAppPublishedByThisRun){throw 'RC1_UPGRADE_RECOVERY_UNPROVEN_NEW_APP'}
  [void](Assert-Rc1UpgPayload $app $newManifestSha)
  if(-not (Test-Rc1UpgNoActiveApp $app $TrialInjectedActive)){
   throw 'RC1_UPGRADE_RECOVERY_NEW_APP_ACTIVE'
  }
  $failed=Join-Path $root ('app-failed-'+[Guid]::NewGuid().ToString('N'))
  if([IO.Directory]::Exists($failed) -or [IO.File]::Exists($failed)){
   throw 'RC1_UPGRADE_RECOVERY_FAILED_ARCHIVE_COLLISION'
  }
  [IO.Directory]::Move($app,$failed)
 }
 if([IO.Directory]::Exists($app) -or [IO.File]::Exists($app)){throw 'RC1_UPGRADE_RECOVERY_TARGET_OCCUPIED'}
 # Copy an independently attested previous RC1 app to a new private stage.
 # Keep the source backup and the failed candidate separately recoverable.
 $stage=Join-Path $root ('.restore-'+[Guid]::NewGuid().ToString('N'))
 if([IO.Directory]::Exists($stage) -or [IO.File]::Exists($stage)){throw 'RC1_UPGRADE_RECOVERY_STAGE_COLLISION'}
 [void][IO.Directory]::CreateDirectory($stage)
 foreach($name in @($script:Rc1UpgRequired)+@('owner-source-manifest.json')){
  $src=Join-Path $backup ($name.Replace('/','\'))
  $dst=Join-Path $stage ($name.Replace('/','\'))
  $parent=[IO.Path]::GetDirectoryName($dst)
  if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
  [IO.File]::Copy($src,$dst,$false)
 }
 [void](Assert-Rc1UpgPayload $stage $oldManifestSha)
 [IO.Directory]::Move($stage,$app)
 [void](Assert-Rc1UpgPayload $app $oldManifestSha)
 return @{Status='RESTORED_VERIFIED_PREVIOUS_RC1';App=$app;Backup=$backup;FailedApp=$failed}
}
