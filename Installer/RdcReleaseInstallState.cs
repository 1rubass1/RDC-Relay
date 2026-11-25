// Release-only installed-app detection. No registry writes or process actions.
// RC1 Owner Pilot intentionally uses a separate, non-registered test route.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Microsoft.Win32;

internal static class RdcReleaseInstallState {
 internal enum Kind { Fresh, Upgrade, Refuse }
 internal const string UninstallPath=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\RDC Relay";
 internal sealed class Decision {
  internal readonly Kind Mode;
  internal readonly string ExistingVersion;
  internal readonly string Reason;
  internal Decision(Kind mode,string version,string reason) {
   Mode=mode;ExistingVersion=version;Reason=reason;
  }
 }

 static bool IsVersion(string text) {
  return !String.IsNullOrEmpty(text)&&Regex.IsMatch(text,@"^\d+\.\d+\.\d+$");
 }
 // Pure policy can be tested with fake records. Unknown, incomplete, conflicting
 // states must never be silently treated as a clean installation.
 internal static Decision Evaluate(bool registered,string name,string publisher,
  string registryVersion,string registryRoot,string expectedRoot,
  string diskVersion,bool hasGui,bool hasUpdater,bool hasInstallFiles) {
  if(!registered) {
   if(hasInstallFiles)return new Decision(Kind.Refuse,"","UNREGISTERED_PAYLOAD");
   return new Decision(Kind.Fresh,"","NO_PREVIOUS_INSTALL");
  }
  if(!String.Equals(name,"RDC Relay",StringComparison.Ordinal)||
   !(String.Equals(publisher,"UMAS",StringComparison.Ordinal)||
     String.Equals(publisher,"RUBASS",StringComparison.Ordinal)))
    return new Decision(Kind.Refuse,"","UNKNOWN_PRODUCT");
  try {
   if(String.IsNullOrWhiteSpace(registryRoot)||
      !String.Equals(Path.GetFullPath(registryRoot).TrimEnd(Path.DirectorySeparatorChar),
       Path.GetFullPath(expectedRoot).TrimEnd(Path.DirectorySeparatorChar),
       StringComparison.OrdinalIgnoreCase))
    return new Decision(Kind.Refuse,"","INSTALL_ROOT_MISMATCH");
  }catch{return new Decision(Kind.Refuse,"","INVALID_INSTALL_ROOT");}
  if(!IsVersion(registryVersion)||!String.Equals(registryVersion,diskVersion,StringComparison.Ordinal))
   return new Decision(Kind.Refuse,"","REGISTRY_DISK_VERSION_MISMATCH");
  if(!hasGui||!hasUpdater)
   return new Decision(Kind.Refuse,"","INSTALLED_PAYLOAD_INCOMPLETE");
  return new Decision(Kind.Upgrade,registryVersion,"REGISTERED_INSTALL");
 }

 // Machine-wide installation is not this per-user Setup's property.
 // Refuse overlapping registrations rather than create a second ARP owner.
 static bool MachineRegistrationExists() {
  const string root=@"Software\Microsoft\Windows\CurrentVersion\Uninstall";
  foreach(RegistryView view in new[]{RegistryView.Registry64,RegistryView.Registry32}) {
   using(RegistryKey hive=RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,view))
   using(RegistryKey entries=hive.OpenSubKey(root,false)) {
    if(entries==null)continue;
    foreach(string name in entries.GetSubKeyNames()) {
     if(String.Equals(name,"RDC Relay",StringComparison.OrdinalIgnoreCase))return true;
     using(RegistryKey entry=entries.OpenSubKey(name,false)) {
      if(entry!=null&&String.Equals(Convert.ToString(entry.GetValue("DisplayName","")),
        "RDC Relay",StringComparison.OrdinalIgnoreCase))return true;
     }
    }
   }
  }
  return false;
 }
 // A shortcut is not proof that the product is installed, but a conflicting
 // target must never be silently hijacked by the stable release installer.
 static bool PrimaryShortcutIsKnownStable(string installRoot,out bool present) {
  present=false;
  Type shellType=Type.GetTypeFromProgID("WScript.Shell");
  if(shellType==null)throw new IOException("RDC_RELEASE_SHELL_UNAVAILABLE");
  object shell=null;
  try {
   foreach(Environment.SpecialFolder folder in new[]{
      Environment.SpecialFolder.DesktopDirectory,Environment.SpecialFolder.Programs}) {
    string location=Environment.GetFolderPath(folder);
    if(String.IsNullOrEmpty(location))throw new IOException("RDC_RELEASE_SHORTCUT_FOLDER_UNAVAILABLE");
    string path=Path.Combine(location,"RDC Relay.lnk");
    if(!File.Exists(path))continue;
    present=true;
    if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)return false;
    if(shell==null)shell=Activator.CreateInstance(shellType);
    object link=null;
    try {
     link=shell.GetType().InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,
      null,shell,new object[]{path});
     string target=Convert.ToString(link.GetType().InvokeMember("TargetPath",
      BindingFlags.GetProperty,null,link,new object[0]));
     string arguments=Convert.ToString(link.GetType().InvokeMember("Arguments",
      BindingFlags.GetProperty,null,link,new object[0])).Trim();
     string powershell=Path.Combine(Environment.SystemDirectory,
      "WindowsPowerShell","v1.0","powershell.exe");
     string script=Path.Combine(installRoot,"remote-window.ps1");
     string expected="-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+script+"\"";
     string older="-NoProfile -STA -ExecutionPolicy Bypass -File \""+script+"\"";
     if(!String.Equals(Path.GetFullPath(target),Path.GetFullPath(powershell),
         StringComparison.OrdinalIgnoreCase)||
       !(String.Equals(arguments,expected,StringComparison.OrdinalIgnoreCase)||
         String.Equals(arguments,older,StringComparison.OrdinalIgnoreCase)))
      return false;
    }finally{if(link!=null)Marshal.FinalReleaseComObject(link);}
   }
   return true;
  }finally{if(shell!=null)Marshal.FinalReleaseComObject(shell);}
 }

 internal static Decision Detect(string installRoot) {
  string marker=Path.Combine(installRoot,"version.txt");
  string gui=Path.Combine(installRoot,"remote-window.ps1");
  string updater=Path.Combine(installRoot,"update.ps1");
  bool hasFiles=File.Exists(marker)||File.Exists(gui)||File.Exists(updater)||
   File.Exists(Path.Combine(installRoot,"RDC Relay.cmd"));
  string diskVersion=File.Exists(marker)?File.ReadAllText(marker).Trim():"";
  if(MachineRegistrationExists())return new Decision(Kind.Refuse,"","MACHINE_REGISTRATION_CONFLICT");
  bool shortcutPresent;
  if(!PrimaryShortcutIsKnownStable(installRoot,out shortcutPresent))
   return new Decision(Kind.Refuse,"","FOREIGN_PRIMARY_SHORTCUT");
  using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallPath,false)) {
   if(key==null) {
    if(shortcutPresent)return new Decision(Kind.Refuse,"","ORPHAN_PRIMARY_SHORTCUT");
    return Evaluate(false,"","","","",installRoot,diskVersion,
     File.Exists(gui),File.Exists(updater),hasFiles);
   }
   return Evaluate(true,
    Convert.ToString(key.GetValue("DisplayName","")),
    Convert.ToString(key.GetValue("Publisher","")),
    Convert.ToString(key.GetValue("DisplayVersion","")),
    Convert.ToString(key.GetValue("InstallLocation","")),
    installRoot,diskVersion,File.Exists(gui),File.Exists(updater),hasFiles);
  }
 }

 internal static string Prompt(string targetVersion) {
  if(!IsVersion(targetVersion))throw new InvalidOperationException("RDC_RELEASE_TARGET_VERSION_INVALID");
  return "Установить RDC Relay "+targetVersion+" как основную оболочку?";
 }
}
