// Stable release Setup rollback coverage for Installed Apps metadata and
// Desktop/Start Menu shortcuts. Snapshot prior to mutation; restore on error.
// Is deliberately separate from RC1 pilot's immutable-release shortcut route.
using System;
using System.IO;
using System.Collections.Generic;
using Microsoft.Win32;

internal sealed class RdcReleaseMetadataSnapshot {
 sealed class RegistryEntry {
  internal readonly object Value;
  internal readonly RegistryValueKind Kind;
  internal RegistryEntry(object value,RegistryValueKind kind){Value=value;Kind=kind;}
 }
 readonly Dictionary<string,byte[]> links=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
 readonly Dictionary<string,RegistryEntry> values=new Dictionary<string,RegistryEntry>(StringComparer.OrdinalIgnoreCase);
 readonly bool hadRegistryEntry;
 readonly bool watchShortcuts;
 readonly bool watchRegistry;
 bool restored;

 internal RdcReleaseMetadataSnapshot(bool includeShortcuts,bool includeRegistration)
  :this(includeShortcuts?Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory):null,
   includeShortcuts?Environment.GetFolderPath(Environment.SpecialFolder.Programs):null,
   includeRegistration) {}

 // Disposable-path seam for fake-only regression. Production calls the
 // OS-folder overload above; neither constructor launches any process.
 internal RdcReleaseMetadataSnapshot(string desktop,string programs,bool includeRegistration) {
  watchShortcuts=desktop!=null && programs!=null;
  watchRegistry=includeRegistration;
  if(watchShortcuts) {
   foreach(string dir in new[]{desktop,programs}) {
    if(String.IsNullOrEmpty(dir))throw new IOException("RDC_RELEASE_SHORTCUT_DIR_UNAVAILABLE");
    foreach(string name in new[]{"RDC Relay.lnk",
      "Remote Desktop Commander.lnk","CommanderRelay.lnk"}) {
     string file=Path.Combine(dir,name);
     if(Directory.Exists(file))throw new IOException("RDC_RELEASE_SHORTCUT_PATH_IS_DIRECTORY");
     if(File.Exists(file)) {
      if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)
       throw new IOException("RDC_RELEASE_SHORTCUT_REPARSE_REFUSED");
      links.Add(file,File.ReadAllBytes(file));
     }else links.Add(file,null);
    }
   }
  }
  if(watchRegistry) {
   using(RegistryKey key=Registry.CurrentUser.OpenSubKey(RdcReleaseInstallState.UninstallPath,false)) {
    hadRegistryEntry=key!=null;
    if(key!=null) {
     if(key.SubKeyCount!=0)throw new IOException("RDC_RELEASE_UNINSTALL_SUBKEYS_UNEXPECTED");
     foreach(string name in key.GetValueNames()) {
      RegistryValueKind kind=key.GetValueKind(name);
      values.Add(name,new RegistryEntry(key.GetValue(name,null,RegistryValueOptions.DoNotExpandEnvironmentNames),kind));
     }
    }
   }
  }
 }

 internal void Restore() {
  if(restored)return;
  List<string> errors=new List<string>();
  if(watchShortcuts) {
   foreach(var item in links) {
    try {
     string path=item.Key;
     if(Directory.Exists(path)||
        (File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0))
      throw new IOException("RDC_RELEASE_SHORTCUT_DESTINATION_CHANGED");
     if(item.Value==null) {
      if(File.Exists(path))File.Delete(path);
     }else {
      string temp=Path.Combine(Path.GetDirectoryName(path),
       ".rdc-shortcut-restore-"+Guid.NewGuid().ToString("N")+".tmp");
      try {
       File.WriteAllBytes(temp,item.Value);
       if(File.Exists(path))File.Replace(temp,path,null);
       else File.Move(temp,path);
      }finally{if(File.Exists(temp))File.Delete(temp);}
     }
    }catch(Exception e){errors.Add("SHORTCUT:"+e.GetType().Name);}
   }
  }
  if(watchRegistry) {
   try {
    if(hadRegistryEntry) {
     using(RegistryKey key=Registry.CurrentUser.CreateSubKey(RdcReleaseInstallState.UninstallPath)) {
      if(key==null||key.SubKeyCount!=0)throw new IOException("RDC_RELEASE_UNINSTALL_REGISTRY_CHANGED");
      foreach(string name in key.GetValueNames())
       if(!values.ContainsKey(name))key.DeleteValue(name,false);
      foreach(var item in values)key.SetValue(item.Key,item.Value.Value,item.Value.Kind);
     }
    }else {
     using(RegistryKey key=Registry.CurrentUser.OpenSubKey(RdcReleaseInstallState.UninstallPath,false)) {
      if(key!=null&&key.SubKeyCount!=0)throw new IOException("RDC_RELEASE_UNEXPECTED_UNINSTALL_SUBKEYS");
     }
     Registry.CurrentUser.DeleteSubKey(RdcReleaseInstallState.UninstallPath,false);
    }
   }catch(ArgumentException) {
    // A missing key is normal when nothing was originally installed.
    if(hadRegistryEntry)errors.Add("REGISTRY_MISSING");
   }catch(Exception e){errors.Add("REGISTRY:"+e.GetType().Name);}
  }
  if(errors.Count!=0)throw new IOException("RDC_RELEASE_METADATA_ROLLBACK_FAILED:"+String.Join(",",errors.ToArray()));
  restored=true;
 }
}
