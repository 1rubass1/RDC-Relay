// Qualification-only integration of the real Setup with reversible shell metadata.
// Never removes shared Node, pairing, logs or the legacy rollback installation.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;
using System.Collections.Generic;

internal static class RdcV16IntegratedMaintenance {
 const string Parent=@"Software\Microsoft\Windows\CurrentVersion\Uninstall";
 const string Run=@"Software\Microsoft\Windows\CurrentVersion\Run";
 const string Product="RDC Relay",Launcher="RC1 Pilot Launcher.exe";
 static string Self {get{return Assembly.GetExecutingAssembly().Location;}}
 static string Store(string local){return Path.Combine(local,"RDCRelayOwnerPilot","1.6.0-RC1");}
 static string Maintenance(string local,string release){return Path.Combine(Store(local),"maintenance",Path.GetFileName(release),"RDC Relay Maintenance.exe");}
 static string Digest(string path){using(var sha=SHA256.Create())using(var f=File.OpenRead(path))return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","");}
 static bool Same(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static void Safe(string path){RdcRc1ManualUpgrade.CheckPath(path);}
 static string Programs(){return Environment.GetFolderPath(Environment.SpecialFolder.Programs);}
 static string Desktop(){return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);}
 static string Link(string dir){return Path.Combine(dir,Product+".lnk");}
 static string Command(string exe){return "\""+exe+"\" --uninstall";}
 internal static IDisposable Acquire(string local){
  string key=RdcReleaseLegacyMigrationLease.Key(local);
  var mutex=new Mutex(false,@"Local\RDCRelayV16Maintenance-"+key);
  bool held=false;
  try{try{held=mutex.WaitOne(0);}catch(AbandonedMutexException){held=true;}
   if(!held)throw new IOException("V16_MAINTENANCE_BUSY");
   return new Lease(mutex);
  }catch{mutex.Dispose();throw;}
 }
 sealed class Lease:IDisposable {
  Mutex mutex;
  internal Lease(Mutex m){mutex=m;}
  public void Dispose(){if(mutex!=null){mutex.ReleaseMutex();mutex.Dispose();mutex=null;}}
 }
 static string[] Shortcut(string path){
  Safe(path);
  if(!File.Exists(path))return null;
  object shell=null,link=null;
  try{
   shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
   link=RdcRc1ManualUpgrade.OpenShortcut(shell,path);
   return new[]{RdcRc1ManualUpgrade.ReadShortcut(link,"TargetPath"),RdcRc1ManualUpgrade.ReadShortcut(link,"Arguments")};
  }finally{if(link!=null)Marshal.FinalReleaseComObject(link);if(shell!=null)Marshal.FinalReleaseComObject(shell);}
 }
 static bool PointsTo(string[] link,string release){
  return link!=null&&Same(link[0],Path.Combine(release,Launcher))&&link[1].Trim()=="--full";
 }
 internal static void AssertFreshShellState(string desktop){
  foreach(string path in new[]{Link(desktop),Link(Programs())}){
   Safe(path);
   if(File.Exists(path)||Directory.Exists(path))throw new IOException("V16_LEGACY_OR_UNKNOWN_INSTALL_REFUSED");
  }
 }
 static string RegisteredRelease(string local){
  using(var key=Registry.CurrentUser.OpenSubKey(Parent+"\\"+Product,false)){
   if(key==null)return null;
   string version=Convert.ToString(key.GetValue("DisplayVersion",""));
   if(!RdcV16MetadataTransaction.IsFullVersion(version))return null;
   string release=Convert.ToString(key.GetValue("InstallLocation",""));
   if(String.IsNullOrEmpty(release)||!RdcOwnerStartup.VerifiedRelease(release,local)||
    Convert.ToString(key.GetValue("DisplayName",""))!=Product||Convert.ToString(key.GetValue("Publisher",""))!="RUBASS")
    throw new IOException("V16_REGISTERED_RELEASE_IDENTITY");
   RdcRc1CandidateSetup.ValidateInstalledSource(release);
   if(RdcV16MetadataTransaction.ReleaseVersion(release)!=version)throw new IOException("V16_REGISTERED_VERSION_MISMATCH");
   string maintenance=Maintenance(local,release);Safe(maintenance);
   if(!File.Exists(maintenance)||Convert.ToString(key.GetValue("UninstallString",""))!=Command(maintenance))
    throw new IOException("V16_REGISTERED_MAINTENANCE_IDENTITY");
   if(!PointsTo(Shortcut(Link(Desktop())),release)||!PointsTo(Shortcut(Link(Programs())),release))
    throw new IOException("V16_REGISTERED_SHORTCUT_IDENTITY");
   if(!File.Exists(maintenance+".sha256")||File.ReadAllText(maintenance+".sha256",Encoding.ASCII)!=Digest(maintenance))
    throw new IOException("V16_REGISTERED_MAINTENANCE_HASH");
   return release;
  }
 }
 internal static bool IsRegistered(string local){return RegisteredRelease(local)!=null;}
 internal static void AssertNoDowngrade(string local,string source){
  string prior=RegisteredRelease(local);
  if(prior!=null&&new Version(RdcV16MetadataTransaction.ReleaseVersion(prior))>new Version(RdcV16MetadataTransaction.ReleaseVersion(source)))
   throw new IOException("V16_DOWNGRADE_REFUSED");
 }
 // Retained legacy rollback files are not an installed application after
 // verified removal. Require the committed ledger and absent shell state.
 static bool CompletedRemoval(string local,string dir){
  Safe(dir);
  string leaf=Path.GetFileName(dir);
  if(!System.Text.RegularExpressions.Regex.IsMatch(leaf,@"\Arc1-[0-9a-f]{24}\z"))return false;
  string release=Path.Combine(Store(local),"releases",leaf);
  string exe=Maintenance(local,release),journal=Path.Combine(dir,"removal.committed");
  Safe(exe);Safe(exe+".sha256");Safe(journal);
  if(Directory.Exists(release)||File.Exists(release)||!File.Exists(journal)||
     !File.Exists(exe)||!File.Exists(exe+".sha256")||
     File.ReadAllText(exe+".sha256",Encoding.ASCII)!=Digest(exe)||
     File.Exists(Path.Combine(dir,"removal.pending"))||File.Exists(Path.Combine(dir,"activation.pending")))return false;
  using(var parent=Registry.CurrentUser.OpenSubKey(Parent,false)){
   return parent!=null&&RdcV16MetadataTransaction.IsCompletedRemoval(parent,journal,Desktop(),Programs(),release,exe);
  }
 }
 internal static bool HasRetainedRollback(string local){
  if(File.Exists(Link(Desktop()))||File.Exists(Link(Programs())))return false;
  string root=Path.Combine(Store(local),"maintenance");Safe(root);
  if(!Directory.Exists(root))return false;
  int count=0;
  foreach(string dir in Directory.GetDirectories(root)){
   if(++count>128)throw new IOException("V16_MAINTENANCE_LIMIT");
   if(CompletedRemoval(local,dir))return true;
  }
  return false;
 }
 // Called with maintenance and legacy leases held. Roll back a single
 // proven pending operation before reading installed registration.
 internal static void RecoverActivation(string local){
  string root=Path.Combine(Store(local),"maintenance");Safe(root);
  if(!Directory.Exists(root))return;
  string pending=null,release=null;bool removal=false;int count=0;
  foreach(string dir in Directory.GetDirectories(root)){
   if(++count>128)throw new IOException("V16_MAINTENANCE_LIMIT");
   Safe(dir);
   string a=Path.Combine(dir,"activation.pending"),r=Path.Combine(dir,"removal.pending");
   Safe(a);Safe(r);
   bool hasA=File.Exists(a),hasR=File.Exists(r);
   if(!hasA&&!hasR)continue;
   string leaf=Path.GetFileName(dir);
   if(pending!=null||(hasA&&hasR)||!System.Text.RegularExpressions.Regex.IsMatch(leaf,@"\Arc1-[0-9a-f]{24}\z")||
      (hasA&&File.Exists(Path.Combine(dir,"activation.committed")))||
      (hasR&&(!File.Exists(Path.Combine(dir,"activation.committed"))||File.Exists(Path.Combine(dir,"removal.committed")))))
    throw new IOException("V16_RECOVERY_AMBIGUOUS");
   release=Path.Combine(Store(local),"releases",leaf);
   removal=hasR;pending=hasR?r:a;
  }
  if(pending==null)return;
  if(!RdcRc1ManualUpgrade.NoPinnedRemoteVerified())throw new IOException("V16_RECOVERY_REMOTE_ACTIVE");
  string exe=Maintenance(local,release);Safe(exe);Safe(exe+".sha256");
  if(!File.Exists(exe)||!File.Exists(exe+".sha256")||File.ReadAllText(exe+".sha256",Encoding.ASCII)!=Digest(exe))
   throw new IOException("V16_RECOVERY_MAINTENANCE_HASH");
  if(!removal){
   if(!RdcOwnerStartup.VerifiedRelease(release,local))throw new IOException("V16_ACTIVATION_RECOVERY_UNVERIFIED");
   RdcRc1CandidateSetup.ValidateInstalledSource(release);
  }
  // Include every installed release: the previous active Host may still
  // exist even when a partial shortcut points at the new release.
  var locks=new List<Mutex>();
  try{
   string releases=Path.Combine(Store(local),"releases");Safe(releases);
   int n=0;
   var candidates=new HashSet<string>(Directory.GetDirectories(releases),StringComparer.OrdinalIgnoreCase);
   candidates.Add(release);
   string legacyPilot=Path.Combine(Store(local),"app");
   if(Directory.Exists(legacyPilot))candidates.Add(legacyPilot);
   foreach(string dir in candidates){
    if(++n>128)throw new IOException("V16_RECOVERY_RELEASE_LIMIT");
    Safe(dir);
    if(!Same(dir,legacyPilot)&&!System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(dir),@"\Arc1-[0-9a-f]{24}\z"))continue;
    var m=new Mutex(false,RdcRc1ManualUpgrade.OldHostMutexName(dir));
    bool held=false;
    try{try{held=m.WaitOne(0);}catch(AbandonedMutexException){held=true;}
     if(!held)throw new IOException("V16_RECOVERY_HOST_ACTIVE");
     locks.Add(m);
    }catch{m.Dispose();throw;}
   }
   if(!RdcRc1ManualUpgrade.NoPinnedRemoteVerified())throw new IOException("V16_RECOVERY_REMOTE_ACTIVE");
   using(var parent=Registry.CurrentUser.CreateSubKey(Parent)){
    if(removal){
     var rp=RdcV16MetadataTransaction.ReadRemovalRecovery(parent,pending,Desktop(),Programs(),release,exe);
     Safe(release);Safe(rp.RetiredPath);
     bool active=Directory.Exists(release),retired=Directory.Exists(rp.RetiredPath);
     if(active==retired||File.Exists(release)||File.Exists(rp.RetiredPath))throw new IOException("V16_REMOVAL_RECOVERY_PAYLOAD");
     string present=active?release:rp.RetiredPath;
     RdcRc1CandidateSetup.ValidateInstalledSource(present);
     if(rp.Before.Single(x=>x.Name=="DisplayVersion").Data!=RdcV16MetadataTransaction.ReleaseVersion(present))throw new IOException("V16_REMOVAL_RECOVERY_VERSION");
     if(Path.GetFileName(release)!="rc1-"+Digest(Path.Combine(present,"owner-source-manifest.json")).Substring(0,24).ToLowerInvariant())
      throw new IOException("V16_REMOVAL_RECOVERY_MANIFEST");
     using(var run=Registry.CurrentUser.CreateSubKey(Run)){
      int current=RdcOwnerStartup.RegistrationState(run,local);
      if(current<0||(rp.StartupBefore.Value==0&&current!=0))throw new IOException("V16_REMOVAL_RECOVERY_STARTUP");
      if(retired)Directory.Move(rp.RetiredPath,release);
      RdcOwnerStartup.RestoreRetiredFreshIntent(release,local,Path.Combine(Path.GetDirectoryName(pending),"fresh-intent.removed"));
      RdcV16MetadataTransaction.RecoverRollback(parent,pending,Desktop(),Programs());
      if(rp.StartupBefore.Value==1)RdcOwnerStartup.SetRegistration(run,local,true);
      if(RegisteredRelease(local)==null)throw new IOException("V16_REMOVAL_RECOVERY_VERIFY");
      File.Move(pending,pending+".rolledback-"+Guid.NewGuid().ToString("N"));
     }
     return;
    }
    var plan=RdcV16MetadataTransaction.ReadRecoveryPlan(parent,pending,Desktop(),Programs());
    if(!plan.AfterKey||!plan.After.Any(x=>x.Name=="InstallLocation"&&Same(x.Data,release))||
       !plan.After.Any(x=>x.Name=="UninstallString"&&x.Data==Command(Maintenance(local,release))))
     throw new IOException("V16_RECOVERY_LEDGER_IDENTITY");
    RdcV16MetadataTransaction.RecoverRollback(parent,pending,Desktop(),Programs());
    File.Move(pending,pending+".rolledback-"+Guid.NewGuid().ToString("N"));
   }
  }finally{foreach(var m in locks){m.ReleaseMutex();m.Dispose();}}
 }
 static void SaveMaintenance(string local,string release,string path){
  Safe(path);Safe(path+".sha256");
  Directory.CreateDirectory(Path.GetDirectoryName(path));
  string expected=Digest(Self);
  // A same-package reinstall may already have recreated the immutable
  // release. Preserve completed maintenance history in its own directory.
  string dir=Path.GetDirectoryName(path);
  string done=Path.Combine(dir,"removal.committed");
  if(File.Exists(done)){
   Safe(done);Safe(path);Safe(path+".sha256");
   if(!File.Exists(path)||!File.Exists(path+".sha256")||File.ReadAllText(path+".sha256",Encoding.ASCII)!=Digest(path)||
      File.Exists(Path.Combine(dir,"removal.pending"))||File.Exists(Path.Combine(dir,"activation.pending")))
     throw new IOException("V16_REINSTALL_MAINTENANCE_IDENTITY");
   using(var parent=Registry.CurrentUser.OpenSubKey(Parent,false)){
    if(parent==null||!RdcV16MetadataTransaction.IsCompletedRemoval(parent,done,Desktop(),Programs(),release,path))
     throw new IOException("V16_REINSTALL_LEDGER");
   }
   string archive=dir+".removed-"+Guid.NewGuid().ToString("N");Safe(archive);
   Directory.Move(dir,archive);
   Directory.CreateDirectory(dir);
  }
  PublishMaintenancePair(Self,path,expected);
 }
 // Publish only complete files. A missing marker can be recovered only
 // from exact bytes of this Setup; never replace a foreign file or marker.
 static void PublishMaintenancePair(string input,string path,string expected){
  string marker=path+".sha256";Safe(input);Safe(path);Safe(marker);
  if(Directory.Exists(path)||Directory.Exists(marker)||Digest(input)!=expected)
   throw new IOException("V16_MAINTENANCE_COLLISION");
  if(File.Exists(marker)){
   if(!File.Exists(path)||Digest(path)!=expected||new FileInfo(marker).Length!=64||File.ReadAllText(marker,Encoding.ASCII)!=expected)
    throw new IOException("V16_MAINTENANCE_COLLISION");
   return;
  }
  if(File.Exists(path)&&Digest(path)!=expected)throw new IOException("V16_MAINTENANCE_COLLISION");
  string id=Guid.NewGuid().ToString("N"),tmp=path+"."+id+".tmp",mt=marker+"."+id+".tmp";
  try{
   if(!File.Exists(path)){
    using(var src=File.OpenRead(input))
    using(var dst=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){src.CopyTo(dst);dst.Flush(true);}
    if(Digest(tmp)!=expected)throw new IOException("V16_MAINTENANCE_COPY_HASH");
    Safe(path);File.Move(tmp,path);
   }
   if(Digest(path)!=expected)throw new IOException("V16_MAINTENANCE_COLLISION");
   using(var f=new FileStream(mt,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] b=Encoding.ASCII.GetBytes(expected);f.Write(b,0,b.Length);f.Flush(true);
   }
   Safe(marker);File.Move(mt,marker);
  }finally{if(File.Exists(tmp))File.Delete(tmp);if(File.Exists(mt))File.Delete(mt);}
 }
 internal static void Publish(string release,string local,string desktop,byte[] link,bool deferred){
  if(deferred)throw new IOException("V16_OLD_HOST_NOT_STOPPED");
  if(link==null||link.Length==0||link.Length>65536)throw new IOException("V16_METADATA_INPUT");
  if(!RdcRc1ManualUpgrade.NoPinnedRemoteVerified())throw new IOException("V16_REMOTE_ACTIVE");
  RdcRc1CandidateSetup.ValidateInstalledSource(release);
  string prior=RegisteredRelease(local);
  string[] oldMenu=Shortcut(Link(Programs()));
  string[] oldDesktop=Shortcut(Link(desktop));
  // No legacy or unregistered shortcut can be overwritten by the new Setup.
  if((oldMenu!=null&&(prior==null||!PointsTo(oldMenu,prior)))||
     (oldDesktop!=null&&(prior==null||!PointsTo(oldDesktop,prior))))
   throw new IOException("V16_LEGACY_OR_UNKNOWN_INSTALL_REFUSED");
  string maintenance=Maintenance(local,release);SaveMaintenance(local,release,maintenance);
  string journal=Path.Combine(Path.GetDirectoryName(maintenance),"activation.pending");
  string committed=Path.Combine(Path.GetDirectoryName(maintenance),"activation.committed");
  Safe(journal);Safe(committed);
  if(File.Exists(committed))throw new IOException("V16_ALREADY_COMMITTED");

  using(var parent=Registry.CurrentUser.CreateSubKey(Parent)){
   RdcV16MetadataTransaction.PrepareActivation(parent,desktop,Programs(),release,maintenance,journal,link,link,prior==null);
   try{
    RdcV16MetadataTransaction.Apply(parent,journal,desktop,Programs());
    if(RegisteredRelease(local)==null)throw new IOException("V16_REGISTRATION_VERIFY");
    File.Move(journal,committed);
   }catch{
    RdcV16MetadataTransaction.RecoverRollback(parent,journal,desktop,Programs());
    throw;
   }
  }

 }
 static void Walk(string dir,List<string> files){
  Safe(dir);
  foreach(string p in Directory.GetFileSystemEntries(dir)){
   Safe(p);
   if(Directory.Exists(p))Walk(p,files);else files.Add(p);
   if(files.Count>128)throw new IOException("V16_UNINSTALL_UNEXPECTED_FILES");
  }
 }
 // Physical cleanup is confined to the exact just-retired package.
 static void DeleteRetired(string retired,string[] required){
  RdcRc1CandidateSetup.ValidateInstalledSource(retired);
  var expected=new HashSet<string>(required.Concat(new[]{"owner-source-manifest.json"}),StringComparer.OrdinalIgnoreCase);
  var files=new List<string>();Walk(retired,files);
  foreach(string f in files)if(!expected.Remove(f.Substring(retired.Length+1).Replace('\\','/')))throw new IOException("V16_CLEANUP_FOREIGN_FILE");
  if(expected.Count!=0)throw new IOException("V16_CLEANUP_INCOMPLETE");
  foreach(string f in files){Safe(f);File.Delete(f);}
  var dirs=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  foreach(string file in files){
   for(string p=Path.GetDirectoryName(file);!Same(p,retired);p=Path.GetDirectoryName(p))dirs.Add(p);
  }
  foreach(string dir in dirs.OrderByDescending(p=>p.Length)){Safe(dir);Directory.Delete(dir,false);}
  Safe(retired);Directory.Delete(retired,false);
 }
 internal static int RunRemoval(string local,string[] required){
  bool en=RdcRc1CandidateSetup.NodeEnglish(true);
  try{return Remove(local,required);}
  catch(Exception e){
   Console.Error.WriteLine("V16_UNINSTALL_REFUSED:"+e.Message);
   bool busy=e.Message=="V16_UNINSTALL_CLOSE_HOST_AND_REMOTE"||e.Message=="V16_REMOTE_ACTIVE";
   MessageBox.Show(busy?(en?"Stop Remote and exit RDC Relay from the system tray before uninstalling.":"Остановите Remote и завершите RDC Relay через системный трей перед удалением."):
    (en?"RDC Relay could not be removed. Error: ":"Не удалось удалить RDC Relay. Код ошибки: ")+e.Message,
    "RDC Relay",MessageBoxButtons.OK,MessageBoxIcon.Warning);
   return 42;
  }
 }
 internal static int Remove(string local,string[] required){
  using(Acquire(local)){
   string release=RegisteredRelease(local);
   if(release==null||!Same(Self,Maintenance(local,release)))throw new IOException("V16_UNINSTALL_WRONG_EXECUTABLE");
   using(var legacy=new RdcReleaseLegacyMigrationLease(Path.Combine(local,"RemoteDesktopCommanderLauncher")))
   using(var host=new Mutex(false,RdcRc1ManualUpgrade.OldHostMutexName(release))){
    bool held=false;
    try{
     try{held=host.WaitOne(0);}catch(AbandonedMutexException){held=true;}
     if(!held||!RdcRc1ManualUpgrade.NoPinnedRemoteVerified())throw new IOException("V16_UNINSTALL_CLOSE_HOST_AND_REMOTE");
     var expected=new HashSet<string>(required.Concat(new[]{"owner-source-manifest.json"}),StringComparer.OrdinalIgnoreCase);
     var files=new List<string>();Walk(release,files);
     foreach(string f in files)if(!expected.Remove(f.Substring(release.Length+1).Replace('\\','/')))throw new IOException("V16_UNINSTALL_FOREIGN_FILE");
     if(expected.Count!=0)throw new IOException("V16_UNINSTALL_INCOMPLETE_RELEASE");
     if(MessageBox.Show(RdcRc1CandidateSetup.NodeEnglish(true)?"Remove RDC Relay "+RdcV16MetadataTransaction.ReleaseVersion(release)+"? Settings and logs will be retained; unrelated files are not removed.":"Удалить RDC Relay "+RdcV16MetadataTransaction.ReleaseVersion(release)+"? Настройки и журналы будут сохранены; посторонние файлы не удаляются.","RDC Relay",MessageBoxButtons.YesNo,MessageBoxIcon.Question,MessageBoxDefaultButton.Button2)!=DialogResult.Yes)return 1;
     if(!RdcRc1ManualUpgrade.NoPinnedRemoteVerified())throw new IOException("V16_REMOTE_ACTIVE");
     string maintenance=Maintenance(local,release);
     string journal=Path.Combine(Path.GetDirectoryName(maintenance),"removal.pending");
     string committed=Path.Combine(Path.GetDirectoryName(maintenance),"removal.committed");
     string intentArchive=Path.Combine(Path.GetDirectoryName(maintenance),"fresh-intent.removed");
     RdcOwnerStartup.ValidateFreshIntentRetirement(release,local,intentArchive);
     Safe(committed);
     if(File.Exists(committed))throw new IOException("V16_UNINSTALL_ALREADY_COMMITTED");
     string retired=release+".retired-"+Guid.NewGuid().ToString("N");Safe(retired);
     using(var parent=Registry.CurrentUser.CreateSubKey(Parent))
     using(var run=Registry.CurrentUser.CreateSubKey(Run)){
      int startup=RdcOwnerStartup.RegistrationState(run,local);
      if(startup<0)throw new IOException("V16_UNINSTALL_FOREIGN_STARTUP");
      RdcV16MetadataTransaction.PrepareRemovalRuntime(parent,Desktop(),Programs(),release,maintenance,journal,File.ReadAllBytes(Link(Desktop())),File.ReadAllBytes(Link(Programs())),retired,startup);
      bool moved=false;
      try{
       RdcV16MetadataTransaction.Apply(parent,journal,Desktop(),Programs());
       if(startup==1)RdcOwnerStartup.SetRegistration(run,local,false);
       RdcOwnerStartup.RetireFreshIntent(release,local,intentArchive);
       Directory.Move(release,retired);moved=true;
       File.Move(journal,committed);
      }catch{
       if(moved)Directory.Move(retired,release);
       RdcOwnerStartup.RestoreRetiredFreshIntent(release,local,intentArchive);
       if(startup==1)RdcOwnerStartup.SetRegistration(run,local,true);
       RdcV16MetadataTransaction.RecoverRollback(parent,journal,Desktop(),Programs());
       throw;
      }
     }
     // Metadata is committed before physical cleanup. Preserve residual
     // files on cleanup failure; never recurse-delete arbitrary trees.
     try{DeleteRetired(retired,required);}
     catch(Exception cleanup){Console.Error.WriteLine("V16_RETIRED_CLEANUP_RETAINED:"+cleanup.GetType().Name);}
     return 0;
    }finally{if(held)host.ReleaseMutex();}
   }
  }
 }
}
