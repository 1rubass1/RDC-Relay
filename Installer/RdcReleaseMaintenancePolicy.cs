// RDC Relay 1.6 release-only maintenance discovery and deterministic decisions.
// READ ONLY: never installs, uninstalls, changes registry or signals Host/Remote.
// Designed to fail closed for mismatched/foreign Windows installation identity.
// Keep separate from the shipping 1.5.x Setup and private RC1 pilot.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using Microsoft.Win32;

internal enum RdcMaintenanceKind {
 Fresh, Upgrade, Repair, NewerInstalled, Refuse
}
internal enum RdcMaintenanceAction {
 Cancel, Install, Update, Repair, Uninstall
}
internal sealed class RdcMaintenanceEvidence {
 internal bool Registered;
 internal string DisplayName="";
 internal string Publisher="";
 internal string RegistryVersion="";
 internal string InstallRoot="";
 internal string DiskVersion="";
 internal bool GuiPresent;
 internal bool UpdaterPresent;
 internal bool EntryPresent;
 internal bool MachineConflict;
 internal bool DuplicateRegistration;
 internal bool ForeignShortcut;
 internal bool PilotOverlay;
 internal bool OrphanedFiles;
 internal bool DirectoryReparse;
 internal bool UntrustedInstallRoot;
 internal string DiscoveryError="";
}
internal sealed class RdcMaintenanceDecision {
 internal readonly RdcMaintenanceKind Kind;
 internal readonly string InstalledVersion;
 internal readonly string TargetVersion;
 internal readonly string InstallRoot;
 internal readonly string Reason;
 internal RdcMaintenanceDecision(RdcMaintenanceKind kind,string installed,string target,string root,string reason){
  Kind=kind;InstalledVersion=installed;TargetVersion=target;InstallRoot=root;Reason=reason;
 }
}
internal static class RdcReleaseMaintenancePolicy {
 internal const string UninstallPath=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\RDC Relay";
 const string UninstallBase=@"Software\Microsoft\Windows\CurrentVersion\Uninstall";
 // Setup must enforce this again after closing the choice form, against
 // freshly detected evidence. UI button availability is not authorization.
 internal static bool IsAllowed(RdcMaintenanceDecision d,RdcMaintenanceAction action){
  if(d==null)return false;
  if(action==RdcMaintenanceAction.Cancel)return true;
  switch(d.Kind){
   case RdcMaintenanceKind.Fresh:return action==RdcMaintenanceAction.Install;
   case RdcMaintenanceKind.Upgrade:
    return action==RdcMaintenanceAction.Update||action==RdcMaintenanceAction.Uninstall;
   case RdcMaintenanceKind.Repair:
    return action==RdcMaintenanceAction.Repair||action==RdcMaintenanceAction.Uninstall;
   default:return false;
  }
 }
 static bool Same(string a,string b){
  return String.Equals(a,b,StringComparison.OrdinalIgnoreCase);
 }
 static Version Parse(string value) {
  if(String.IsNullOrEmpty(value)||!Regex.IsMatch(value,@"\A[0-9]+\.[0-9]+\.[0-9]+\z"))return null;
  try{return new Version(value);}catch{return null;}
 }
 internal static RdcMaintenanceDecision Decide(RdcMaintenanceEvidence e,string setupVersion) {
  Version target=Parse(setupVersion);
  if(target==null)throw new ArgumentException("RDC_INVALID_SETUP_VERSION");
  string blank="";
  if(e==null)return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"DISCOVERY_MISSING");
  if(!String.IsNullOrEmpty(e.DiscoveryError))
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"DISCOVERY_FAILED");
  if(e.MachineConflict||e.DuplicateRegistration)
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"PRODUCT_IDENTITY_CONFLICT");
  if(e.DirectoryReparse||e.UntrustedInstallRoot||e.ForeignShortcut)
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"UNVERIFIED_PATH_OR_SHORTCUT");
  if(!e.Registered) {
   if(e.OrphanedFiles||e.PilotOverlay)
    return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"UNREGISTERED_EXISTING_INSTALL");
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Fresh,blank,setupVersion,blank,"NO_PREVIOUS_INSTALL");
  }
  if(!Same(e.DisplayName,"RDC Relay")||
    !(Same(e.Publisher,"UMAS")||Same(e.Publisher,"RUBASS")))
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"UNKNOWN_PRODUCT");
  if(String.IsNullOrWhiteSpace(e.InstallRoot)||!e.EntryPresent)
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"INCOMPLETE_INSTALL");
  Version registry=Parse(e.RegistryVersion);
  Version disk=Parse(e.DiskVersion);
  if(registry==null||disk==null||registry.CompareTo(disk)!=0)
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"VERSION_MISMATCH");
  // A same-version repair can restore missing program binaries, but never
  // infer product identity only from a registry entry when the version
  // marker itself is missing. For upgrades, the predecessor must be whole.
  bool filesMissing=!e.GuiPresent||!e.UpdaterPresent;
  if(filesMissing&&registry.CompareTo(target)!=0)
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,blank,setupVersion,blank,"INCOMPLETE_INSTALL");
  // RC1 pilot changed the main Desktop shortcut but retained 1.5.18 ARP.
  // Never overwrite that shortcut or claim stable and pilot are one install.
  if(e.PilotOverlay)
   return new RdcMaintenanceDecision(RdcMaintenanceKind.Refuse,e.RegistryVersion,setupVersion,e.InstallRoot,"PILOT_MIGRATION_NOT_VERIFIED");
  int cmp=registry.CompareTo(target);
  if(cmp<0)return new RdcMaintenanceDecision(RdcMaintenanceKind.Upgrade,e.RegistryVersion,setupVersion,e.InstallRoot,"OLDER_INSTALLED");
  if(cmp==0)return new RdcMaintenanceDecision(RdcMaintenanceKind.Repair,e.RegistryVersion,setupVersion,e.InstallRoot,"SAME_VERSION");
  return new RdcMaintenanceDecision(RdcMaintenanceKind.NewerInstalled,e.RegistryVersion,setupVersion,e.InstallRoot,"DOWNGRADE_REFUSED");
 }
 // Never assume HKLM is safe because current-user registration is absent.
 // Enumeration also rejects duplicate named registrations under other keys.
 static int CountNamed(RegistryHive hive,RegistryView view){
  int count=0;
  using(RegistryKey root=RegistryKey.OpenBaseKey(hive,view))
  using(RegistryKey entries=root.OpenSubKey(UninstallBase,false)){
   if(entries==null)return 0;
   string[] names=entries.GetSubKeyNames();
   if(names.Length>4096)throw new IOException("UNINSTALL_ENUMERATION_UNBOUNDED");
   foreach(string keyName in names){
    if(Same(keyName,"RDC Relay")){count++;continue;}
    using(RegistryKey key=entries.OpenSubKey(keyName,false)){
     if(key!=null&&Same(Convert.ToString(key.GetValue("DisplayName","")),"RDC Relay"))count++;
    }
    if(count>1)return count;
   }
  }
  return count;
 }
 [StructLayout(LayoutKind.Sequential)]
 struct FileAttributeTagInfo {public uint Attributes;public uint Tag;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,
  uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int infoClass,
  out FileAttributeTagInfo info,uint size);
 static bool IsTrustedDesktopCloudAncestor(string inspected,string requested){
  // Only the OS Desktop chain may use the Windows Cloud Files reparse tag.
  // Junctions, arbitrary symlinks, and user's installed program root
  // never receive this exception.
  string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
  if(String.IsNullOrWhiteSpace(desktop))return false;
  desktop=Path.GetFullPath(desktop);
  bool onDesktop=Same(requested,desktop)||
   requested.StartsWith(desktop+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
  bool trustedAncestor=Same(inspected,desktop)||
   desktop.StartsWith(inspected+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
  if(!onDesktop||!trustedAncestor||!Directory.Exists(inspected))return false;
  using(SafeFileHandle handle=CreateFile(inspected,0,7,IntPtr.Zero,3,
    0x02000000u|0x00200000u,IntPtr.Zero)){
   if(handle==null||handle.IsInvalid)return false;
   FileAttributeTagInfo tag;
   if(!GetFileInformationByHandleEx(handle,9,out tag,8))return false;
   return (tag.Tag & 0xFFFF0FFFu)==0x9000001Au;
  }
 }
 static bool CheckPath(string path,bool allowDesktopCloud){
  string full=Path.GetFullPath(path);
  string cursor=full;
  while(!String.IsNullOrEmpty(cursor)){
   if(File.Exists(cursor)||Directory.Exists(cursor)){
    if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0 &&
        !(allowDesktopCloud&&IsTrustedDesktopCloudAncestor(cursor,full)))return false;
   }
   string parent=Path.GetDirectoryName(cursor);
   if(String.IsNullOrEmpty(parent)||Same(parent,cursor))break;
   cursor=parent;
  }
  return true;
 }
 static string DefaultLegacyRoot() {
  return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
   "RemoteDesktopCommanderLauncher");
 }
 // Inspect both the Desktop and Start Menu primary shortcuts. Missing
 // links are repairable; mismatched links are a possible second app owner.
 static void InspectOneShortcut(RdcMaintenanceEvidence e,string folder,bool allowDesktopCloud){
  if(String.IsNullOrWhiteSpace(folder))throw new IOException("SHORTCUT_PATH_UNAVAILABLE");
  string link=Path.Combine(folder,"RDC Relay.lnk");
  if(!File.Exists(link))return;
  if(!CheckPath(link,allowDesktopCloud)){e.ForeignShortcut=true;return;}
  Type shellType=Type.GetTypeFromProgID("WScript.Shell");
  if(shellType==null)throw new IOException("WScript_SHELL_UNAVAILABLE");
  object shell=null,shortcut=null;
  try{
   shell=Activator.CreateInstance(shellType);
   shortcut=shellType.InvokeMember("CreateShortcut",
    System.Reflection.BindingFlags.InvokeMethod,null,shell,new object[]{link});
   Type t=shortcut.GetType();
   string target=Convert.ToString(t.InvokeMember("TargetPath",
    System.Reflection.BindingFlags.GetProperty,null,shortcut,new object[0]));
   string arguments=Convert.ToString(t.InvokeMember("Arguments",
    System.Reflection.BindingFlags.GetProperty,null,shortcut,new object[0])).Trim();
   if(String.IsNullOrWhiteSpace(target)){e.ForeignShortcut=true;return;}
   string full=Path.GetFullPath(target);
   string legacyScript=Path.Combine(DefaultLegacyRoot(),"remote-window.ps1");
   bool legacy=Same(full,Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe")) &&
    (Same(arguments,"-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+legacyScript+"\"")||
     Same(arguments,"-NoProfile -STA -ExecutionPolicy Bypass -File \""+legacyScript+"\""));
   if(legacy&&e.Registered&&Same(e.InstallRoot,DefaultLegacyRoot()))return;
   // Recognize RC1 only as a special migration state; never trust its
   // contents solely on this shortcut's name.
   string pilot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "RDCRelayOwnerPilot","1.6.0-RC1");
   if(Same(Path.GetFileName(full),"RC1 Pilot Launcher.exe")&&
      full.StartsWith(pilot+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)){
    e.PilotOverlay=true;return;
   }
   // Later public 1.6 launcher can be recognized only when a verified
   // release install root is registered, never by filename alone.
   if(e.Registered && Same(full,Path.Combine(e.InstallRoot,"RDC Relay.exe")))return;
   e.ForeignShortcut=true;
  }finally{
   if(shortcut!=null)System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shortcut);
   if(shell!=null)System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
  }
 }
 static void InspectKnownShortcuts(RdcMaintenanceEvidence e){
  InspectOneShortcut(e,Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),true);
  InspectOneShortcut(e,Environment.GetFolderPath(Environment.SpecialFolder.Programs),false);
 }
 internal static RdcMaintenanceEvidence Detect() {
  var e=new RdcMaintenanceEvidence();
  try{
   int current=CountNamed(RegistryHive.CurrentUser,RegistryView.Default);
   e.DuplicateRegistration=current>1;
   int system64=CountNamed(RegistryHive.LocalMachine,RegistryView.Registry64);
   int system32=CountNamed(RegistryHive.LocalMachine,RegistryView.Registry32);
   e.MachineConflict=system64>0||system32>0;
   using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallPath,false)){
    e.Registered=key!=null;
    if(key!=null){
     e.DisplayName=Convert.ToString(key.GetValue("DisplayName",""));
     e.Publisher=Convert.ToString(key.GetValue("Publisher",""));
     e.RegistryVersion=Convert.ToString(key.GetValue("DisplayVersion",""));
     e.InstallRoot=Convert.ToString(key.GetValue("InstallLocation",""));
     if(!String.IsNullOrWhiteSpace(e.InstallRoot)){
      string root=Path.GetFullPath(e.InstallRoot);
      string volume=Path.GetPathRoot(root);
      e.UntrustedInstallRoot=String.IsNullOrWhiteSpace(volume)||
       root.StartsWith(@"\\",StringComparison.Ordinal)||
       String.Equals(root.TrimEnd(Path.DirectorySeparatorChar),
        volume.TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase)||
       new DriveInfo(volume).DriveType!=DriveType.Fixed;
      e.DirectoryReparse=!CheckPath(root,false);
      string file=Path.Combine(root,"version.txt");
      e.EntryPresent=File.Exists(file);
      e.GuiPresent=File.Exists(Path.Combine(root,"remote-window.ps1"))||
       File.Exists(Path.Combine(root,"RDC Relay.exe"));
      e.UpdaterPresent=File.Exists(Path.Combine(root,"update.ps1"))||
       File.Exists(Path.Combine(root,"release-install.json"));
      if(e.EntryPresent)e.DiskVersion=File.ReadAllText(file).Trim();
     }
    }
   }
   if(!e.Registered){
    // Another uninstall key may use the same DisplayName. Never create
    // a second registered copy just because our historical key is absent.
    if(current>0)e.DuplicateRegistration=true;
    string legacy=DefaultLegacyRoot();
    string pilotRoot=Path.Combine(
      Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
      "RDCRelayOwnerPilot","1.6.0-RC1");
    e.OrphanedFiles=File.Exists(Path.Combine(legacy,"version.txt"))||
     File.Exists(Path.Combine(legacy,"remote-window.ps1"))||
     Directory.Exists(Path.Combine(pilotRoot,"releases"))||
     Directory.Exists(Path.Combine(pilotRoot,"app"));
   }
   InspectKnownShortcuts(e);
  }catch(Exception ex){
   // The category is sufficient. Never log raw registry paths or exception
   // contents, which can expose the user's profile name.
   e.DiscoveryError=ex.GetType().Name;
  }
  return e;
 }
}
