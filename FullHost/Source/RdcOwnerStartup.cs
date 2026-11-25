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
 const string DispatcherName="RDC Relay Startup.exe";
 const string MarkerName=".startup-dispatch-v2";
  const string LauncherName="RDC Relay.exe";
 const string PriorLauncherName="RC1 Pilot Launcher.exe";
 public static string ReleaseLauncher(string release){
  string manifest=Path.Combine(release,"owner-source-manifest.json");Safe(manifest);
  var d=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(manifest,new UTF8Encoding(false,true)));
  return Convert.ToString(d["kind"])=="FULL_HOST_GUI_V16_PUBLIC"?LauncherName:PriorLauncherName;
 }
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
 static bool ValidNumericVersion(string text){
  Version v;
  return text!=null&&Regex.IsMatch(text,@"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z")&&Version.TryParse(text,out v)&&v>=new Version(1,6,0);
 }
 public static bool VerifiedRelease(string release,string local){
  try{
   release=Path.GetFullPath(release);Safe(release);
   string parent=Path.Combine(Pilot(local),"1.6.0-RC1","releases");
   if(!Same(Path.GetDirectoryName(release),parent))return false;
   string manifest=Path.Combine(release,"owner-source-manifest.json");
   string launcher=Path.Combine(release,ReleaseLauncher(release));
   Safe(manifest);Safe(launcher);
   if(!File.Exists(manifest)||!File.Exists(launcher)||new FileInfo(manifest).Length>131072)return false;
   if(Path.GetFileName(release)!="rc1-"+Hash(manifest).Substring(0,24))return false;
   var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(manifest,new UTF8Encoding(false,true)));
   if(!ValidNumericVersion(Convert.ToString(data["candidate"]))||(Convert.ToString(data["kind"])!="FULL_HOST_GUI_V16_PUBLIC"&&Convert.ToString(data["kind"])!="FULL_HOST_GUI_V16_QUALIFICATION")||
      Convert.ToString(data["ownerMode"])!="FULL_HOST_GUI_RC1"||!Convert.ToBoolean(data["installable"])||
      Convert.ToBoolean(data["publishable"])!=(Convert.ToString(data["kind"])=="FULL_HOST_GUI_V16_PUBLIC"))return false;
   var rows=data["files"] as ArrayList;
   if(rows==null||rows.Count>128)return false;
   string expected=null;
   foreach(object raw in rows){
    var row=raw as Dictionary<string,object>;
    if(row==null)return false;
    if(Convert.ToString(row["name"])==Path.GetFileName(launcher)){
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
   if(args.Trim()!="--full"||(Path.GetFileName(target)!=LauncherName&&Path.GetFileName(target)!=PriorLauncherName))return null;
   string release=Path.GetDirectoryName(Path.GetFullPath(target));
   return VerifiedRelease(release,local)&&Path.GetFileName(target)==ReleaseLauncher(release)?release:null;
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
  if(File.Exists(exe)||File.Exists(marker)||Directory.Exists(exe)||Directory.Exists(marker))
   throw new IOException("RC1_STARTUP_DISPATCHER_COLLISION");
  string input=Path.Combine(release,ReleaseLauncher(release));
  string id=Guid.NewGuid().ToString("N");
  string staged=exe+"."+id+".tmp",stagedMarker=marker+"."+id+".tmp";
  bool published=false,marked=false;
  try{
   File.Copy(input,staged,false);
   string digest=Hash(staged);
   if(digest!=Hash(input))throw new IOException("RC1_STARTUP_DISPATCHER_HASH");
   using(var f=new FileStream(stagedMarker,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] bytes=Encoding.ASCII.GetBytes(digest);f.Write(bytes,0,bytes.Length);f.Flush(true);
   }
   File.Move(staged,exe);published=true;
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
  if(key==null)return 0;
  object value=key.GetValue(ValueName,null,RegistryValueOptions.DoNotExpandEnvironmentNames);
  if(value==null)return 0;
  return value is string&&key.GetValueKind(ValueName)==RegistryValueKind.String&&
   ((String.Equals((string)value,Command(local),StringComparison.Ordinal)&&DispatcherOwned(local))||(String.Equals((string)value,PriorCommand(local),StringComparison.Ordinal)&&PriorDispatcherOwned(local)))?1:-1;
 }
 public static void SetRegistration(RegistryKey key,string local,bool enabled){
  if(key==null)throw new IOException("RC1_STARTUP_REGISTRY_UNAVAILABLE");
  int state=RegistrationState(key,local);
  if(state<0)throw new IOException("RC1_STARTUP_FOREIGN_REGISTRATION");
  if(enabled){
   if(!DispatcherOwned(local))throw new IOException("RC1_STARTUP_DISPATCHER_UNVERIFIED");
   if(state==0||!String.Equals(Convert.ToString(key.GetValue(ValueName,null)),Command(local),StringComparison.Ordinal))key.SetValue(ValueName,Command(local),RegistryValueKind.String);
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
 public static void InitializeFreshInstalled(string source){
  if(!IsActiveSource(source))throw new IOException("RC1_STARTUP_INSTALL_REQUIRED");
  string local=LocalRoot;
  using(var key=Registry.CurrentUser.CreateSubKey(RunKey)){
   InitializeFreshRegistration(key,Path.GetDirectoryName(source),local);
  }
 }
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
  try{return Same(executable,DispatcherPath(LocalRoot))&&DispatcherOwned(LocalRoot)&&State()==1;}
  catch{return false;}
 }
}
