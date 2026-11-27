# Public identity preflight, separate from publication authorization.
# Retain the installed compatibility namespace; public product identity is
# explicit, and the old flat updater remains unconditionally blocked.
function Set-RdcV16PublicIdentity {
 param([string]$Payload,[string]$InstallerStage,[string[]]$SetupSources)
 function Edit([string]$path,[string]$old,[string]$new){
  $raw=[IO.File]::ReadAllBytes($path);$s=[IO.File]::ReadAllText($path)
  if([regex]::Matches($s,[regex]::Escape($old)).Count -ne 1){throw ('PUBLIC_IDENTITY_DRIFT '+[IO.Path]::GetFileName($path)+' '+$old)}
  [IO.File]::WriteAllText($path,$s.Replace($old,$new),(New-Object Text.UTF8Encoding(($raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191))))
 }
 # Public GUI is Host-only, regardless of the presence of the old marker.
 $gui=Join-Path $Payload 'remote-window.ps1'
 Edit $gui '# Branch-only RC1 source marker blocks accidental legacy GUI execution against' ('if(-not $OwnerGui){throw ''RDC_PUBLIC_HOST_GUI_REQUIRED''}'+[Environment]::NewLine+'# Branch-only RC1 source marker blocks accidental legacy GUI execution against')
 $startup=Join-Path $Payload 'RdcOwnerStartup.cs'
 # Accept qualified installed predecessors only for migration. Public
 # startup dispatch must resolve the exact active immutable package.
 Edit $startup 'Convert.ToString(data["kind"])!="FULL_HOST_GUI_V16_QUALIFICATION"' '(Convert.ToString(data["kind"])!="FULL_HOST_GUI_V16_PUBLIC"&&Convert.ToString(data["kind"])!="FULL_HOST_GUI_V16_QUALIFICATION")'
 Edit $startup 'Convert.ToBoolean(data["publishable"]))return false;' 'Convert.ToBoolean(data["publishable"])!=(Convert.ToString(data["kind"])=="FULL_HOST_GUI_V16_PUBLIC"))return false;'
 $launcher=Join-Path $InstallerStage 'Rc1CandidateLauncher.cs'
 Edit $launcher '"FULL_HOST_GUI_V16_QUALIFICATION"' '"FULL_HOST_GUI_V16_PUBLIC"'
 Edit $launcher 'Convert.ToBoolean(manifest["publishable"]))' '!Convert.ToBoolean(manifest["publishable"]))'
 Edit $launcher 'Convert.ToBoolean(values["publishable"]) ||' '!Convert.ToBoolean(values["publishable"]) ||'
 $setup=Join-Path $InstallerStage 'Rc1CandidateSetup.cs'
 Edit $setup 'bool privateSideBySide=args.Length==1 && args[0]=="--owner-approved-side-by-side";' 'bool privateSideBySide=false; // Public setup has no private staging mode.'
 # Installed predecessor can be qualification or public; a package used
 # as this Setup's own embedded input MUST be public and version exact.
 Edit $setup '(string)manifest["kind"]!="FULL_HOST_GUI_V16_QUALIFICATION"||Convert.ToBoolean(manifest["publishable"])' '((string)manifest["kind"]!="FULL_HOST_GUI_V16_PUBLIC"&&(string)manifest["kind"]!="FULL_HOST_GUI_V16_QUALIFICATION")||Convert.ToBoolean(manifest["publishable"])!=((string)manifest["kind"]=="FULL_HOST_GUI_V16_PUBLIC")'
 Edit $setup 'Convert.ToBoolean(candidate["publishable"]) ||' 'Convert.ToBoolean(candidate["publishable"])!=Convert.ToBoolean(manifest["publishable"]) ||'
 Edit $setup 'ValidateInstalledSource(root);if(RdcV16MetadataTransaction.ReleaseVersion(root)' 'ValidateInstalledSource(root);if((string)ReadJson(Path.Combine(root,"owner-source-manifest.json"))["kind"]!="FULL_HOST_GUI_V16_PUBLIC")throw new InvalidOperationException("V16_PUBLIC_SETUP_KIND");if(RdcV16MetadataTransaction.ReleaseVersion(root)'
 # Preserve older qualified launcher names and package paths so previous
 # data and owned process exclusion remain valid. Do not enable the
 # flat legacy update path; only the independent full Host feed is used.
 $out=@()
 foreach($source in $SetupSources){
  $dest=Join-Path $InstallerStage ([IO.Path]::GetFileName($source))
  [IO.File]::Copy($source,$dest,$false)
  $out+=@($dest)
 }
 Set-RdcV16PublicLauncher -Payload $Payload -InstallerStage $InstallerStage -SetupSources $out
 return $out
}

# Public launcher and startup dispatcher use a stable product name.
function Set-RdcV16PublicLauncher {
 param([string]$Payload,[string]$InstallerStage,[string[]]$SetupSources)
 function Edit([string]$path,[string]$old,[string]$new,[int]$count=1){
  $raw=[IO.File]::ReadAllBytes($path);$s=[IO.File]::ReadAllText($path)
  if([regex]::Matches($s,[regex]::Escape($old)).Count -ne $count){throw ('PUBLIC_LAUNCHER_DRIFT '+[IO.Path]::GetFileName($path)+' '+$old)}
  [IO.File]::WriteAllText($path,$s.Replace($old,$new),(New-Object Text.UTF8Encoding(($raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191))))
 }
 $startup=Join-Path $Payload 'RdcOwnerStartup.cs'
 Edit $startup 'const string LauncherName="RC1 Pilot Launcher.exe";' @'
 const string LauncherName="RDC Relay.exe";
 const string PriorLauncherName="RC1 Pilot Launcher.exe";
 public static string ReleaseLauncher(string release){
  string manifest=Path.Combine(release,"owner-source-manifest.json");Safe(manifest);
  var d=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(manifest,new UTF8Encoding(false,true)));
  return Convert.ToString(d["kind"])=="FULL_HOST_GUI_V16_PUBLIC"?LauncherName:PriorLauncherName;
 }
'@
 Edit $startup 'Path.Combine(release,LauncherName);' 'Path.Combine(release,ReleaseLauncher(release));' 2
 Edit $startup 'Convert.ToString(row["name"])==LauncherName' 'Convert.ToString(row["name"])==Path.GetFileName(launcher)'
 Edit $startup 'if(args.Trim()!="--full"||Path.GetFileName(target)!=LauncherName)return null;' 'if(args.Trim()!="--full"||(Path.GetFileName(target)!=LauncherName&&Path.GetFileName(target)!=PriorLauncherName))return null;'
 Edit $startup 'return VerifiedRelease(release,local)?release:null;' 'return VerifiedRelease(release,local)&&Path.GetFileName(target)==ReleaseLauncher(release)?release:null;'
 # New dispatcher uses a separate owned file; legacy dispatcher is never
 # overwritten. It can still dispatch the previous immutable package.
 Edit $startup 'const string DispatcherName="RDC Relay.exe";' 'const string DispatcherName="RDC Relay Startup.exe";'
 Edit $startup 'const string MarkerName=".startup-dispatch-v1";' 'const string MarkerName=".startup-dispatch-v2";'
 Edit $startup ' public static int RegistrationState(RegistryKey key,string local){' @'
 public static bool PriorDispatcherOwned(string local){
  try{
   string exe=Path.Combine(Pilot(local),"RDC Relay.exe"),marker=Path.Combine(Pilot(local),".startup-dispatch-v1");Safe(exe);Safe(marker);
   if(!File.Exists(exe)||!File.Exists(marker)||new FileInfo(marker).Length!=64)return false;
   string expected=File.ReadAllText(marker,Encoding.ASCII);
   return Digest(expected)&&Hash(exe)==expected;
  }catch{return false;}
 }
 static string PriorCommand(string local){return "\""+Path.Combine(Pilot(local),"RDC Relay.exe")+"\" --startup-dispatch";}
 public static int RegistrationState(RegistryKey key,string local){
'@
 Edit $startup 'String.Equals((string)value,Command(local),StringComparison.Ordinal)&&DispatcherOwned(local)?1:-1;' '((String.Equals((string)value,Command(local),StringComparison.Ordinal)&&DispatcherOwned(local))||(String.Equals((string)value,PriorCommand(local),StringComparison.Ordinal)&&PriorDispatcherOwned(local)))?1:-1;'
 Edit $startup 'if(state==0)key.SetValue(ValueName,Command(local),RegistryValueKind.String);' 'if(state==0||!String.Equals(Convert.ToString(key.GetValue(ValueName,null)),Command(local),StringComparison.Ordinal))key.SetValue(ValueName,Command(local),RegistryValueKind.String);'
 Edit $startup ' public static bool CanDispatch(string executable){' @'
 public static void MigrateDispatcher(string release,string local){
  using(var key=Registry.CurrentUser.CreateSubKey(RunKey)){
   int state=RegistrationState(key,local);
   if(state<0)throw new IOException("V16_FOREIGN_STARTUP");
   if(state==1&&String.Equals(Convert.ToString(key.GetValue(ValueName,null)),PriorCommand(local),StringComparison.Ordinal)){
    EnsureDispatcher(release,local);
    SetRegistration(key,local,true);
   }
  }
 }
 public static bool CanDispatch(string executable){
'@
 # Source contains separate exact package validation and dispatch lookup.
 $launcher=Join-Path $InstallerStage 'Rc1CandidateLauncher.cs'
 Edit $launcher '"RdcOwnerRuntime.dll","RC1 Pilot Launcher.exe"' '"RdcOwnerRuntime.dll","RDC Relay.exe"'
 Edit $launcher 'Path.Combine(release,"RC1 Pilot Launcher.exe")' 'Path.Combine(release,RdcOwnerStartup.ReleaseLauncher(release))'
 $setup=Join-Path $InstallerStage 'Rc1CandidateSetup.cs'
 Edit $setup '"RC1 Pilot Launcher.exe"' '"RDC Relay.exe"' 2
 # Installed qualification manifests have the old launcher name, while the
 # public embedded candidate has only the new name.
 Edit $setup 'string[] validationRequired=Required;' 'string[] validationRequired=(string)manifest["kind"]=="FULL_HOST_GUI_V16_PUBLIC"?Required:Required.Select(x=>x=="RDC Relay.exe"?"RC1 Pilot Launcher.exe":x).ToArray();'
 $manual=Join-Path $InstallerStage 'Rc1ManualUpgrade.cs'
 Edit $manual 'Path.Combine(release,"RC1 Pilot Launcher.exe")' 'Path.Combine(release,"RDC Relay.exe")'
 Edit $manual 'bool isOldRc1=String.Equals(Path.GetFileName(oldFull),"RC1 Pilot Launcher.exe",StringComparison.OrdinalIgnoreCase)&&' 'bool isOldRc1=(String.Equals(Path.GetFileName(oldFull),"RC1 Pilot Launcher.exe",StringComparison.OrdinalIgnoreCase)||String.Equals(Path.GetFileName(oldFull),"RDC Relay.exe",StringComparison.OrdinalIgnoreCase))&&'
 $maintenance=Join-Path $InstallerStage 'RdcV16IntegratedMaintenance.cs'
 Edit $maintenance 'Path.Combine(release,Launcher)' 'Path.Combine(release,RdcOwnerStartup.ReleaseLauncher(release))'
 # Prior startup migration is performed after exact active release is
 # registered. Preserve original disabled state and refuse foreign Run.
 Edit $maintenance '    if(RegisteredRelease(local)==null)throw new IOException("V16_REGISTRATION_VERIFY");' @'
    if(RegisteredRelease(local)==null)throw new IOException("V16_REGISTRATION_VERIFY");
    RdcOwnerStartup.MigrateDispatcher(release,local);
'@
}
