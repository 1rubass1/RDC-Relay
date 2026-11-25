# Only the isolated qualification staging tree is modified. The source marker
# and existing private RC1 build remain blocked for public publication.
function Set-RdcV16QualificationIdentity {
 param([Parameter(Mandatory=$true)][string]$Payload,[Parameter(Mandatory=$true)][string]$InstallerStage,[string]$version='1.6.0')
 if($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or [Version]$version -lt [Version]'1.6.0'){throw 'V16_BAD_BUILD_VERSION'}
 function Change-StagedText($path,[scriptblock]$change){
  $raw=[IO.File]::ReadAllBytes($path)
  $bom=$raw.Length -ge 3 -and $raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191
  $text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
  $new=& $change $text
  [IO.File]::WriteAllText($path,[string]$new,(New-Object Text.UTF8Encoding($bom)))
 }
 function Replace-Exact($text,$old,$new){
  if([regex]::Matches($text,[regex]::Escape($old)).Count -ne 1){throw ('V16_QUALIFICATION_IDENTITY_DRIFT '+$old)}
  return $text.Replace($old,$new)
 }
 # Numeric version must agree on both sides of authenticated IPC as well as
 # the visible title, manifest validation, installer and startup dispatcher.
 foreach($name in @('remote-window.ps1','rc1-owner-gui.ps1','RdcOwnerRuntime.cs','RdcOwnerStartup.cs','lang/ru-RU.json','lang/en-US.json')){
  Change-StagedText (Join-Path $Payload $name) {
   param($s)
   if(!$s.Contains('1.6.0 RC1')){throw ('V16_QUALIFICATION_VERSION_MISSING '+$name)}
   $s.Replace('1.6.0 RC1',$version)
  }
 }
 foreach($name in @('Rc1CandidateSetup.cs','Rc1CandidateLauncher.cs','Rc1ManualUpgrade.cs')){
  Change-StagedText (Join-Path $InstallerStage $name) {
   param($s)
   if(!$s.Contains('1.6.0 RC1')){throw ('V16_QUALIFICATION_VERSION_MISSING '+$name)}
   $s.Replace('1.6.0 RC1',$version)
  }
 }
 foreach($name in @('RdcOwnerStartup.cs')){
  Change-StagedText (Join-Path $Payload $name) {
   param($s)
   $s=Replace-Exact $s '"PRIVATE_FULL_RC1"' '"FULL_HOST_GUI_V16_QUALIFICATION"'
   $s=Replace-Exact $s ('Convert.ToString(data["candidate"])!="'+$version+'"') '!ValidNumericVersion(Convert.ToString(data["candidate"]))'
   Replace-Exact $s ' public static bool VerifiedRelease(string release,string local){' @'
 static bool ValidNumericVersion(string text){
  Version v;
  return text!=null&&Regex.IsMatch(text,@"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z")&&Version.TryParse(text,out v)&&v>=new Version(1,6,0);
 }
 public static bool VerifiedRelease(string release,string local){
'@
  }
 }
 Change-StagedText (Join-Path $InstallerStage 'Rc1CandidateLauncher.cs') {
  param($s)
  $s=Replace-Exact $s '"PRIVATE_FULL_RC1"' '"FULL_HOST_GUI_V16_QUALIFICATION"'
  Replace-Exact $s 'ValidatePortablePackage(root);' ('ValidatePortablePackage(root);'+[Environment]::NewLine+'   string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);'+[Environment]::NewLine+'   if(RdcOwnerStartup.VerifiedRelease(root,local)&&RdcOwnerStartup.FreshIntentExists(local))throw new InvalidOperationException("V16_FRESH_INTENT_INCOMPLETE");')
 }
 Change-StagedText (Join-Path $InstallerStage 'Rc1CandidateSetup.cs') {
  param($s)
  # Release qualification holds the legacy GUI/updater exclusion through
  # prerequisite revalidation, immutable staging and shortcut activation.
  $s=Replace-Exact $s 'string extracted=null;' 'string extracted=null; RdcReleaseLegacyMigrationLease legacyLease=null;'
  $s=Replace-Exact $s 'if(args.Length==0 && !EnsureNodePrerequisite(registered||priorShortcut))return 1;' ('if(registered){legacyLease=new RdcReleaseLegacyMigrationLease(Path.Combine(local,"RemoteDesktopCommanderLauncher")); if(!HasRegisteredStableInstallation(local))throw new IOException("RDC_V16_PREDECESSOR_CHANGED");}'+[Environment]::NewLine+'    if(args.Length==0 && !EnsureNodePrerequisite(registered||priorShortcut))return 1;')
  $s=Replace-Exact $s 'string result=RdcRc1ManualUpgrade.ActivateDesktop(release,local,desktop);' ('string result=RdcRc1ManualUpgrade.ActivateDesktop(release,local,desktop);'+[Environment]::NewLine+'    if(legacyLease!=null){legacyLease.Dispose();legacyLease=null;}')
  $s=Replace-Exact $s 'if(extracted!=null){' ('if(legacyLease!=null)legacyLease.Dispose();'+[Environment]::NewLine+'   if(extracted!=null){')
  $s=Replace-Exact $s ('if((string)manifest["candidate"]!="'+$version+'")') 'if(!RdcV16MetadataTransaction.IsFullVersion((string)manifest["candidate"])||(string)manifest["kind"]!="FULL_HOST_GUI_V16_QUALIFICATION"||Convert.ToBoolean(manifest["publishable"])||RdcV16MetadataTransaction.ReleaseVersion(root)!=(string)manifest["candidate"])'
  $s=Replace-Exact $s 'if(File.Exists(gui)||File.Exists(updater)||File.Exists(versionFile))' 'if((File.Exists(gui)||File.Exists(updater)||File.Exists(versionFile))&&!RdcV16IntegratedMaintenance.HasRetainedRollback(localRoot))'
  $s=Replace-Exact $s 'if(freshDefaults&&result=="CREATED"){' ('if(result=="SWITCHED_STABLE"||result=="CREATED")RdcOwnerAutoConnectPreference.InitializeDisabled(RdcOwnerAutoConnectPreference.CurrentPath);'+[Environment]::NewLine+'    if(freshDefaults){')
  $s=Replace-Exact $s 'string release=RdcRc1ManualUpgrade.Prepare(source,local,Required);' @'
    if(args.Length==0){
     freshDefaults=RdcOwnerStartup.BeginFreshIntent(source,local,freshDefaults);
     if(freshDefaults&&(registered||priorShortcut)){
      string active=RdcOwnerStartup.ActiveRelease();
      if(active==null||!RdcOwnerStartup.BeginFreshIntent(active,local,false))throw new IOException("V16_FRESH_INTENT_PREDECESSOR");
     }
    }else if(RdcOwnerStartup.FreshIntentExists(local))throw new IOException("V16_FRESH_INTENT_INTERACTIVE_REQUIRED");
    string release=RdcRc1ManualUpgrade.Prepare(source,local,Required);
'@
  $s=Replace-Exact $s 'RdcOwnerStartup.InitializeFreshInstalled(Path.Combine(release,"Source"));' 'RdcOwnerStartup.FinishFreshIntent(release,local);'
  $s=Replace-Exact $s 'static bool NodeEnglish(bool existing)' 'internal static bool NodeEnglish(bool existing)'
  $s=Replace-Exact $s 'static void ValidateSource(string root){' ('internal static void ValidateSource(string root){ValidateInstalledSource(root);if(RdcV16MetadataTransaction.ReleaseVersion(root)!="'+$version+'")throw new InvalidOperationException("V16_SETUP_WRONG_VERSION");}'+[Environment]::NewLine+' internal static void ValidateInstalledSource(string root){')
  $s=Replace-Exact $s 'bool registered=HasRegisteredStableInstallation(local);' ('RdcV16IntegratedMaintenance.AssertNoDowngrade(local,source);'+[Environment]::NewLine+'    bool registered=HasRegisteredStableInstallation(local);')
  $s=Replace-Exact $s 'string stable=Path.Combine(localRoot,"RemoteDesktopCommanderLauncher");' ('if(RdcV16IntegratedMaintenance.IsRegistered(localRoot))return true;'+[Environment]::NewLine+'  string stable=Path.Combine(localRoot,"RemoteDesktopCommanderLauncher");')
  $s=Replace-Exact $s 'string extracted=null; RdcReleaseLegacyMigrationLease legacyLease=null;' 'string extracted=null; RdcReleaseLegacyMigrationLease legacyLease=null; IDisposable maintenanceLease=null;'
  $s=Replace-Exact $s 'bool privateSideBySide=args.Length==1' ('if(args.Length==1&&args[0]=="--uninstall")return RdcV16IntegratedMaintenance.RunRemoval(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),Required);'+[Environment]::NewLine+'   bool privateSideBySide=args.Length==1')
  $s=Replace-Exact $s 'string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);' ('maintenanceLease=RdcV16IntegratedMaintenance.Acquire(local);'+[Environment]::NewLine+'    using(var recoveryLease=new RdcReleaseLegacyMigrationLease(Path.Combine(local,"RemoteDesktopCommanderLauncher"))){RdcV16IntegratedMaintenance.RecoverActivation(local);}'+[Environment]::NewLine+'    string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);')
  $s=Replace-Exact $s 'if(legacyLease!=null)legacyLease.Dispose();' ('if(legacyLease!=null)legacyLease.Dispose();'+[Environment]::NewLine+'   if(maintenanceLease!=null)maintenanceLease.Dispose();')
  Replace-Exact $s '@"^[0-9]+\.[0-9]+\.[0-9]+ RC[1-9][0-9]*$"' '@"^[0-9]+\.[0-9]+\.[0-9]+$"'
 }
 Change-StagedText (Join-Path $InstallerStage 'Rc1ManualUpgrade.cs') {
  param($s)
  foreach($method in @('string OldHostMutexName','void CheckPath','bool NoPinnedRemoteVerified','string ReadShortcut','object OpenShortcut')){
   $s=Replace-Exact $s ('static '+$method) ('internal static '+$method)
  }
  $a=$s.IndexOf('   if(firstInstall){')
  $b=$s.IndexOf('  }finally{',$a)
  if($a -lt 0 -or $b -le $a){throw 'V16_ACTIVATION_DRIFT'}
  $new=@'
   RdcV16IntegratedMaintenance.Publish(release,localRoot,desktop,temporary,previousRc1HostIdle);
   return firstInstall?"CREATED":switchedFromStable?"SWITCHED_STABLE":"SWITCHED_RC1";
'@
  $s=$s.Substring(0,$a)+$new+[Environment]::NewLine+$s.Substring($b)
  Replace-Exact $s 'return "ALREADY_ACTIVE";' 'if(RdcV16IntegratedMaintenance.IsRegistered(localRoot))return "ALREADY_ACTIVE";'
 }
 # The full Host feed is deliberately separate from the legacy flat-file feed.
 Change-StagedText (Join-Path $Payload 'update-notice.ps1') {
  param($s)
  $t=$null;$e=$null
  $ast=[Management.Automation.Language.Parser]::ParseInput($s,[ref]$t,[ref]$e)
  if($e.Count){throw 'V16_NOTICE_PARSE'}
  $nodes=@($ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq 'Get-RdcAvailableVersionFromManifest'},$true))
  if($nodes.Count -ne 1){throw 'V16_NOTICE_FUNCTION_DRIFT'}
  $new=@'
function Get-RdcAvailableVersionFromManifest([string]$Raw) {
    $script:rdcFullHostOffer=$null
    try{
        $manifest=$Raw.TrimStart([char]0xFEFF)|ConvertFrom-Json -ErrorAction Stop
        if($manifest.schema -isnot [int] -or $manifest.schema -ne 1 -or
           $manifest.architecture -cne 'full-host-gui' -or
           $manifest.ready -isnot [bool] -or !$manifest.ready -or
           [string]$manifest.version -cnotmatch '^\d+\.\d+\.\d+$' -or
           [string]$appVersion -cnotmatch '^\d+\.\d+\.\d+$'){return $null}
        $remote=[Version]$manifest.version
        $local=[Version]$appVersion
        if($local -lt [Version]'1.6.0' -or $remote -le $local -or
           [string]$manifest.tag -cne ('v'+$manifest.version) -or
           [string]$manifest.asset -cne ('RDC.Relay.Setup.v'+$manifest.version+'.exe') -or
           [string]$manifest.sha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or
           ($manifest.bytes -isnot [int] -and $manifest.bytes -isnot [long]) -or
           $manifest.bytes -le 0 -or $manifest.bytes -gt 100MB){return $null}
        $script:rdcFullHostOffer=[pscustomobject]@{
            Version=[string]$manifest.version
            Digest=([string]$manifest.sha256).ToUpperInvariant()
            Bytes=[long]$manifest.bytes
            Uri=[Uri]('https://github.com/1rubass1/RDC-Relay/releases/download/'+$manifest.tag+'/'+$manifest.asset)
        }
        return $script:rdcFullHostOffer.Version
    }catch{return $null}
}
'@
  $s=$s.Substring(0,$nodes[0].Extent.StartOffset)+$new+$s.Substring($nodes[0].Extent.EndOffset)
  $s=Replace-Exact $s '/Source/update-manifest.json' '/Source/full-host-update-manifest.json'
  $clickStart=$s.IndexOf('$script:rdcNoticeControl.Add_Click({')
  $clickEnd=$s.IndexOf('function Get-RdcAvailableVersionFromManifest',$clickStart)
  if($clickStart -lt 0 -or $clickEnd -le $clickStart){throw 'V16_UPDATE_CLICK_DRIFT'}
  $click=@'
$script:rdcNoticeControl.Add_Click({
    if($SelfTest -or !$OwnerGui -or $script:rdcNoticeInstalling){return}
    Start-RdcFullHostUpdate
})
'@
  $s=$s.Substring(0,$clickStart)+$click+[Environment]::NewLine+[Environment]::NewLine+$s.Substring($clickEnd)
  $s=Replace-Exact $s '$script:rdcNoticeActive = $true' ('$script:rdcNoticeActive = $true'+[Environment]::NewLine+'    $script:rdcNoticeControl.VisualPreviewOnly= -not (Test-RdcFullHostInstalled)')
  $s=Replace-Exact $s '$script:rdcNoticeControl.TabStop = -not $script:ownerUpdateDemoMode' '$script:rdcNoticeControl.TabStop = -not $script:rdcNoticeControl.VisualPreviewOnly'
  $s=Replace-Exact $s 'function Dispose-RdcUpdateNotice {' ('function Dispose-RdcUpdateNotice {'+[Environment]::NewLine+'    Clear-RdcFullHostDownload')
  $s=Replace-Exact $s 'function Update-RdcUpdateNoticePolling {' ('function Update-RdcUpdateNoticePolling {'+[Environment]::NewLine+'    if($script:rdcFullHostDownload){return}')
  # Append the helper to this existing manifest-bound payload member.
  $s+[Environment]::NewLine+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'v16-full-host-update.ps1'),[Text.Encoding]::UTF8)
 }

 foreach($name in @('lang/ru-RU.json','lang/en-US.json')){
  Change-StagedText (Join-Path $Payload $name) {
   param($s)
   $lang=$s|ConvertFrom-Json
   if($name -eq 'lang/ru-RU.json'){
    $words=[ordered]@{'update.owner.idleTooltip'='Проверка обновлений RDC Relay.';'update.owner.availableAccessible'='Доступна версия RDC Relay v{version}.';'update.owner.availableTooltip'='Установить версию v{version}.';'update.owner.failed'='Не удалось завершить обновление.';'update.owner.stopFirst'='Перед обновлением остановите Remote.';'update.owner.confirm'='Установить RDC Relay {version}?'}
   }else{
    $words=[ordered]@{'update.owner.idleTooltip'='Checking RDC Relay updates.';'update.owner.availableAccessible'='RDC Relay v{version} is available.';'update.owner.availableTooltip'='Install version v{version}.';'update.owner.failed'='Update did not complete.';'update.owner.stopFirst'='Stop Remote before updating.';'update.owner.confirm'='Install RDC Relay {version}?'}
   }
   # Preserve the approved resource shape and replace only the existing
   # update keys; add the three new messages adjacent to those keys.
   $s=$s -replace '(?m)^(\s*)"update\.owner\.idleTooltip": "[^"]*",',('$1"update.owner.idleTooltip": "'+$words['update.owner.idleTooltip']+'",')
   $s=$s -replace '(?m)^(\s*)"update\.owner\.availableAccessible": "[^"]*",',('$1"update.owner.availableAccessible": "'+$words['update.owner.availableAccessible']+'",')
   $s=$s -replace '(?m)^(\s*)"update\.owner\.availableTooltip": "[^"]*",',('$1"update.owner.availableTooltip": "'+$words['update.owner.availableTooltip']+'",'+[Environment]::NewLine+'$1"update.owner.failed": "'+$words['update.owner.failed']+'",'+[Environment]::NewLine+'$1"update.owner.stopFirst": "'+$words['update.owner.stopFirst']+'",'+[Environment]::NewLine+'$1"update.owner.confirm": "'+$words['update.owner.confirm']+'",')
   $null=$s|ConvertFrom-Json
   # Only human-facing text. Protocol names, IDs, internal directory and
   # ownership mutex names are intentionally unchanged for migration work.
   $s.Replace('RDC Relay RC1','RDC Relay').Replace('RC1: ','RDC Relay: ').Replace('RC1 is observing','RDC Relay is observing').Replace('owned by RC1','owned by RDC Relay').Replace('RC1 will create','RDC Relay will create').Replace(' | RC1','').Replace('из RC1','из приложения').Replace('принадлежит RC1','принадлежит RDC Relay').Replace('RC1 создаст','RDC Relay создаст')
  }
 }
 # The two explicit additions must be present in both compiled allowlists.
 foreach($name in @('Rc1CandidateSetup.cs','Rc1CandidateLauncher.cs')){
  Change-StagedText (Join-Path $InstallerStage $name) {
   param($s)
   Replace-Exact $s '"Source/update-notice.ps1","Source/update.ps1",' '"Source/update-notice.ps1","Source/update.ps1","Source/version.txt","Source/THIRD_PARTY_NOTICES.txt",'
  }
 }
 [IO.File]::WriteAllText((Join-Path $Payload 'version.txt'),$version+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
}