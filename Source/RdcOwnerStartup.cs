// Native per-user startup registration for the installed RC1 only.
// Stable dispatcher resolves the primary installed shortcut on each boot.
// No StartupApproved modification: Windows retains its own enable/disable policy.
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Collections;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using Microsoft.Win32;

public static class RdcOwnerStartup {
 const string RunKey=@"Software\Microsoft\Windows\CurrentVersion\Run";
 const string ValueName="RDC Relay";
 const string DispatcherName="RDC Relay.exe";
 const string MarkerName=".startup-dispatch-v1";
 const string LauncherName="RC1 Pilot Launcher.exe";
 static readonly StringComparison Ignore=StringComparison.OrdinalIgnoreCase;
 static string LocalRoot {get{return Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);}}
 static string Pilot(string local){return Path.Combine(Path.GetFullPath(local),"RDCRelayOwnerPilot");}
 public static string DispatcherPath(string local){return Path.Combine(Pilot(local),DispatcherName);}
 static string MarkerPath(string local){return Path.Combine(Pilot(local),MarkerName);}
 static string Hash(string path){
  using(var sha=SHA256.Create())using(var file=File.OpenRead(path))
   return BitConverter.ToString(sha.ComputeHash(file)).Replace("-","").ToLowerInvariant();
 }
 static bool Same(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),Ignore);}
 static void Safe(string path){
  for(string p=Path.GetFullPath(path);!String.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)){
   if((File.Exists(p)||Directory.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
    throw new IOException("RC1_STARTUP_REPARSE_REFUSED");
  }
 }
 static bool Digest(string value){return value!=null&&Regex.IsMatch(value,@"\A[0-9a-f]{64}\z");}
 // The exact manifest hash is the immutable installed release directory ID.
 // A portable copy or a directory named app is intentionally not eligible.
 public static bool VerifiedRelease(string release,string local){
  try{
   release=Path.GetFullPath(release);Safe(release);
   string parent=Path.Combine(Pilot(local),"1.6.0-RC1","releases");
   if(!Same(Path.GetDirectoryName(release),parent))return false;
   string manifest=Path.Combine(release,"owner-source-manifest.json");
   string launcher=Path.Combine(release,LauncherName);
   Safe(manifest);Safe(launcher);
   if(!File.Exists(manifest)||!File.Exists(launcher)||new FileInfo(manifest).Length>131072)return false;
   if(Path.GetFileName(release)!="rc1-"+Hash(manifest).Substring(0,24))return false;
   var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(manifest,new UTF8Encoding(false,true)));
   if(Convert.ToString(data["candidate"])!="1.6.0 RC1"||Convert.ToString(data["kind"])!="PRIVATE_FULL_RC1"||
      Convert.ToString(data["ownerMode"])!="FULL_HOST_GUI_RC1"||!Convert.ToBoolean(data["installable"])||
      Convert.ToBoolean(data["publishable"]))return false;
   var rows=data["files"] as ArrayList;
   if(rows==null||rows.Count>128)return false;
   string expected=null;
   foreach(object raw in rows){
    var row=raw as Dictionary<string,object>;
    if(row==null)return false;
    if(Convert.ToString(row["name"])==LauncherName){
     if(expected!=null)return false;
     expected=Convert.ToString(row["sha256"]).ToLowerInvariant();
    }
   }
   return Digest(expected)&&Hash(launcher)==expected;
  }catch{return false;}
 }
 // Read the existing authoritative desktop handoff, not a new release pointer.
 // No arbitrary shortcut execution; target/arguments/path/hash must match.
 public static string ActiveRelease(){
  object shell=null,link=null;
  try{
   string local=LocalRoot;
   string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
   if(String.IsNullOrEmpty(local)||String.IsNullOrEmpty(desktop))return null;
   string path=Path.Combine(desktop,"RDC Relay.lnk");
   // Desktop may legitimately be redirected to OneDrive. Reject a linked
   // shortcut itself and independently verify the target's full local path.
   if(!File.Exists(path)||(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)return null;
   Type type=Type.GetTypeFromProgID("WScript.Shell");
   if(type==null)return null;
   shell=Activator.CreateInstance(type);
   link=type.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});
   string target=Convert.ToString(link.GetType().InvokeMember("TargetPath",BindingFlags.GetProperty,null,link,new object[0]));
   string args=Convert.ToString(link.GetType().InvokeMember("Arguments",BindingFlags.GetProperty,null,link,new object[0]));
   if(args.Trim()!="--full"||Path.GetFileName(target)!=LauncherName)return null;
   string release=Path.GetDirectoryName(Path.GetFullPath(target));
   return VerifiedRelease(release,local)?release:null;
  }catch{return null;}
  finally{
   if(link!=null)Marshal.FinalReleaseComObject(link);
   if(shell!=null)Marshal.FinalReleaseComObject(shell);
  }
 }
 public static bool IsActiveSource(string source){
  try{string active=ActiveRelease();return active!=null&&Same(source,Path.Combine(active,"Source"));}
  catch{return false;}
 }
 public static string Command(string local){return "\""+DispatcherPath(local)+"\" --startup-dispatch";}
 // Stable copy is published once; later releases use the same dispatcher.
 // The sidecar binds its bytes. Unknown/corrupt paths never overwritten.
 public static bool DispatcherOwned(string local){
  try{
   string exe=DispatcherPath(local),marker=MarkerPath(local);Safe(exe);Safe(marker);
   if(!File.Exists(exe)||!File.Exists(marker)||new FileInfo(marker).Length!=64)return false;
   string expected=File.ReadAllText(marker,Encoding.ASCII);
   return Digest(expected)&&Hash(exe)==expected;
  }catch{return false;}
 }
 public static void EnsureDispatcher(string release,string local){
  if(!VerifiedRelease(release,local))throw new IOException("RC1_STARTUP_INSTALL_REQUIRED");
  string exe=DispatcherPath(local),marker=MarkerPath(local);
  Safe(exe);Safe(marker);
  if(DispatcherOwned(local))return;
  string input=Path.Combine(release,LauncherName);
  if(Directory.Exists(exe)||Directory.Exists(marker)||File.Exists(marker)||
     (File.Exists(exe)&&Hash(exe)!=Hash(input)))
   throw new IOException("RC1_STARTUP_DISPATCHER_COLLISION");
  string id=Guid.NewGuid().ToString("N");
  string staged=exe+"."+id+".tmp",stagedMarker=marker+"."+id+".tmp";
  bool published=false,marked=false;
  try{
   string digest=Hash(input);
   if(!File.Exists(exe)){
    using(var src=File.OpenRead(input))
    using(var dst=new FileStream(staged,FileMode.CreateNew,FileAccess.Write,FileShare.None)){src.CopyTo(dst);dst.Flush(true);}
    if(Hash(staged)!=digest)throw new IOException("RC1_STARTUP_DISPATCHER_HASH");
   }
   using(var f=new FileStream(stagedMarker,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] bytes=Encoding.ASCII.GetBytes(digest);f.Write(bytes,0,bytes.Length);f.Flush(true);
   }
   if(File.Exists(staged)){File.Move(staged,exe);published=true;}
   if(Hash(exe)!=digest)throw new IOException("RC1_STARTUP_DISPATCHER_COLLISION");
   File.Move(stagedMarker,marker);marked=true;
   if(!DispatcherOwned(local))throw new IOException("RC1_STARTUP_DISPATCHER_HASH");
  }catch{
   // Only this attempt's exact files are eligible for rollback.
   if(published&&!marked&&File.Exists(exe)&&File.Exists(stagedMarker)&&
      Hash(exe)==File.ReadAllText(stagedMarker,Encoding.ASCII))File.Delete(exe);
   throw;
  }finally{
   if(File.Exists(staged))File.Delete(staged);
   if(File.Exists(stagedMarker))File.Delete(stagedMarker);
  }
 }
 // 0 absent / 1 owned registration / -1 foreign or unverified.
 // Test seam takes only a supplied disposable registry key, never HKCU Run.
 public static int RegistrationState(RegistryKey key,string local){
  if(key==null)return 0;
  object value=key.GetValue(ValueName,null,RegistryValueOptions.DoNotExpandEnvironmentNames);
  if(value==null)return 0;
  return value is string&&key.GetValueKind(ValueName)==RegistryValueKind.String&&
   String.Equals((string)value,Command(local),StringComparison.Ordinal)&&DispatcherOwned(local)?1:-1;
 }
 public static void SetRegistration(RegistryKey key,string local,bool enabled){
  if(key==null)throw new IOException("RC1_STARTUP_REGISTRY_UNAVAILABLE");
  int state=RegistrationState(key,local);
  if(state<0)throw new IOException("RC1_STARTUP_FOREIGN_REGISTRATION");
  if(enabled){
   if(!DispatcherOwned(local))throw new IOException("RC1_STARTUP_DISPATCHER_UNVERIFIED");
   if(state==0)key.SetValue(ValueName,Command(local),RegistryValueKind.String);
  }else if(state==1)key.DeleteValue(ValueName,false);
  if(RegistrationState(key,local)!=(enabled?1:0))throw new IOException("RC1_STARTUP_REGISTRATION_NOT_CONFIRMED");
 }
 public static int State(){
  try{using(var key=Registry.CurrentUser.OpenSubKey(RunKey,false))return RegistrationState(key,LocalRoot);}
  catch{return -1;}
 }
 public static void Set(string source,bool enabled){
  if(!IsActiveSource(source))throw new IOException("RC1_STARTUP_INSTALL_REQUIRED");
  string local=LocalRoot;
  if(enabled)EnsureDispatcher(Path.GetDirectoryName(source),local);
  using(var key=Registry.CurrentUser.CreateSubKey(RunKey)){SetRegistration(key,local,enabled);}
 }
 // Default policy is applied once by a positively identified first Setup,
 // after the verified primary shortcut exists and before launching any GUI.
 // Registry state is never reset during upgrade/repair or ordinary startup.
 public static void InitializeFreshRegistration(RegistryKey key,string release,string local){
  if(!VerifiedRelease(release,local))throw new IOException("RC1_STARTUP_INSTALL_REQUIRED");
  int state=RegistrationState(key,local);
  if(state<0)throw new IOException("RC1_STARTUP_FOREIGN_REGISTRATION");
  EnsureDispatcher(release,local);
  SetRegistration(key,local,true);
 }
 // Durable first-install intention is outside the pilot root so creating it
 // cannot turn a retry into an apparent pre-existing installation.
 static string FreshIntentPath(string local){return Path.Combine(Path.GetFullPath(local),"RDCRelayFirstInstall.pending");}
 public static bool FreshIntentExists(string local){
  string p=FreshIntentPath(local);Safe(p);
  if(Directory.Exists(p))throw new IOException("V16_FRESH_INTENT_COLLISION");
  return File.Exists(p);
 }
 static string FreshManifestDigest(string source){
  string p=Path.Combine(source,"owner-source-manifest.json");Safe(p);
  if(!File.Exists(p)||new FileInfo(p).Length>131072)throw new IOException("V16_FRESH_INTENT_MANIFEST");
  return Hash(p);
 }
 public static bool BeginFreshIntent(string source,string local,bool fresh){
  string p=FreshIntentPath(local);
  if(FreshIntentExists(local)){
   if(new FileInfo(p).Length!=64||File.ReadAllText(p,Encoding.ASCII)!=FreshManifestDigest(source))
    throw new IOException("V16_FRESH_INTENT_COLLISION");
   return true;
  }
  if(!fresh)return false;
  string expected=FreshManifestDigest(source),tmp=p+"."+Guid.NewGuid().ToString("N")+".tmp";
  try{
   using(var f=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] bytes=Encoding.ASCII.GetBytes(expected);f.Write(bytes,0,bytes.Length);f.Flush(true);
   }
   File.Move(tmp,p);
   return true;
  }finally{if(File.Exists(tmp))File.Delete(tmp);}
 }
 // The removal transaction archives only the marker belonging to its
 // verified release. The archive is kept with the removal journal.
 public static void ValidateFreshIntentRetirement(string release,string local,string archive){
  Safe(archive);
  if(File.Exists(archive)||Directory.Exists(archive))throw new IOException("V16_FRESH_INTENT_ARCHIVE_COLLISION");
  if(FreshIntentExists(local)&&!BeginFreshIntent(release,local,false))
   throw new IOException("V16_FRESH_INTENT_IDENTITY");
 }
 public static void RetireFreshIntent(string release,string local,string archive){
  ValidateFreshIntentRetirement(release,local,archive);
  if(FreshIntentExists(local))File.Move(FreshIntentPath(local),archive);
 }
 public static void RestoreRetiredFreshIntent(string release,string local,string archive){
  Safe(archive);
  if(Directory.Exists(archive))throw new IOException("V16_FRESH_INTENT_ARCHIVE_COLLISION");
  if(!File.Exists(archive))return;
  if(new FileInfo(archive).Length!=64||File.ReadAllText(archive,Encoding.ASCII)!=FreshManifestDigest(release))
   throw new IOException("V16_FRESH_INTENT_ARCHIVE_IDENTITY");
  if(FreshIntentExists(local))throw new IOException("V16_FRESH_INTENT_COLLISION");
  File.Move(archive,FreshIntentPath(local));
 }
 public static void FinishFreshIntent(string release,string local){
  if(!VerifiedRelease(release,local)||!FreshIntentExists(local)||
     !BeginFreshIntent(release,local,false)||!IsActiveSource(Path.Combine(release,"Source")))
   throw new IOException("V16_FRESH_INTENT_IDENTITY");
  using(var key=Registry.CurrentUser.CreateSubKey(RunKey)){
   InitializeFreshRegistration(key,release,local);
   key.Flush();
  }
  File.Delete(FreshIntentPath(local));
 }
 public static void InitializeFreshInstalled(string source){
  if(!IsActiveSource(source))throw new IOException("RC1_STARTUP_INSTALL_REQUIRED");
  string local=LocalRoot;
  using(var key=Registry.CurrentUser.CreateSubKey(RunKey)){
   InitializeFreshRegistration(key,Path.GetDirectoryName(source),local);
  }
 }
 public static bool CanDispatch(string executable){
  try{return Same(executable,DispatcherPath(LocalRoot))&&DispatcherOwned(LocalRoot)&&State()==1;}
  catch{return false;}
 }
}
