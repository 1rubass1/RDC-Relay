// Side-by-side RC1 Owner Portable/Setup launcher. New product entry point.
// Compile with RDC_RC1_BLOCKED until approved Host/GUI and OS process tests.
using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using System.Threading;
using System.Security.Cryptography;
using System.Collections;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
internal static class RdcRc1CandidateLauncher {
 static bool SignalExistingGui(string eventName) {
  try {
   using(EventWaitHandle activation=EventWaitHandle.OpenExisting(eventName)) {
    if(!activation.Set())throw new InvalidOperationException("RC1_GUI_SIGNAL_FAILED");
    return true;
   }
  } catch(WaitHandleCannotBeOpenedException) {
   return false; // No live same-release Host advertises GUI activation.
  }
 }
 static bool WaitForGuiReady(string eventName,int timeout){
  try{
   using(EventWaitHandle ready=EventWaitHandle.OpenExisting(eventName))
    return ready.WaitOne(timeout);
  }catch(WaitHandleCannotBeOpenedException){return false;}
 }
 static string GuiEventName(string source) {
  string normalized=Path.GetFullPath(source).TrimEnd(Path.DirectorySeparatorChar).ToLowerInvariant();
  byte[] key=new System.Security.Cryptography.SHA256Managed().ComputeHash(
    Encoding.UTF8.GetBytes(normalized));
  return @"Local\RdcRelayRC1Open-"+BitConverter.ToString(key).Replace("-","").Substring(0,32);
 }
 static string GuiReadyEventName(string source){
  return GuiEventName(source).Replace("RdcRelayRC1Open-","RdcRelayRC1GuiReady-");
 }
 static string SafeFailureCode(Exception error) {
  string code=error.Message??"";
  if(System.Text.RegularExpressions.Regex.IsMatch(code,@"^RC1_[A-Z0-9_]{3,100}$"))
   return code;
  return error.GetType().Name;
 }
 static string SafeHostExitCode(string raw,int exitCode){
  // A failed PowerShell Host can print private paths. Extract only one fixed
  // startup failure category from a bounded prefix and discard everything else.
  if(raw==null)raw="";
  if(raw.Length>4096)raw=raw.Substring(0,4096);
  var found=System.Text.RegularExpressions.Regex.Match(raw,
   @"\bRC1_INITIAL_GUI_(NONE|UNVERIFIED)\b");
  return found.Success?found.Value:"RC1_HOST_EARLY_EXIT_"+exitCode;
 }
 // Extracted Portable is a user-facing executable: Windows Explorer invokes
 // its Main with zero arguments. Setup's existing --full route remains valid.
 // Neither mode is allowed to bypass the private candidate or package checks.
 static bool FullLaunchRequested(string[] args){
  return args!=null && (args.Length==0 ||
    (args.Length==1 && String.Equals(args[0],"--full",StringComparison.Ordinal)));
 }
 // The product Host and Setup already reject untrusted path redirects.
 // This launcher must use the same narrow exception for the actual Windows
 // Desktop Cloud Files ancestor chain, never arbitrary OneDrive folders,
 // child Cloud placeholders, mount points, or symlinks.
 [StructLayout(LayoutKind.Sequential)]
 struct FileAttributeTagInfo {public uint FileAttributes;public uint ReparseTag;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,
   uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int infoClass,
   out FileAttributeTagInfo info,uint size);
 static bool IsWindowsDesktopCloudAncestor(string inspected,string requested){
  string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
  if(String.IsNullOrEmpty(desktop))return false;
  desktop=Path.GetFullPath(desktop).TrimEnd(Path.DirectorySeparatorChar);
  string full=Path.GetFullPath(requested);
  string parent=Path.GetFullPath(inspected);
  bool within=String.Equals(full,desktop,StringComparison.OrdinalIgnoreCase)||
   full.StartsWith(desktop+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
  bool ancestor=String.Equals(parent,desktop,StringComparison.OrdinalIgnoreCase)||
   desktop.StartsWith(parent.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,
    StringComparison.OrdinalIgnoreCase);
  if(!within||!ancestor||!Directory.Exists(parent))return false;
  using(SafeFileHandle handle=CreateFile(parent,0,7,IntPtr.Zero,3,
    0x02000000u|0x00200000u,IntPtr.Zero)){
   if(handle==null||handle.IsInvalid)return false;
   FileAttributeTagInfo info;
   if(!GetFileInformationByHandleEx(handle,9,out info,8))return false;
   return (info.ReparseTag & 0xFFFF0FFFu)==0x9000001Au;
  }
 }
 static void CheckPortablePath(string path){
  string full=Path.GetFullPath(path),cursor=full;
  while(!String.IsNullOrEmpty(cursor)){
   if(File.Exists(cursor)||Directory.Exists(cursor)){
    if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0 &&
       !IsWindowsDesktopCloudAncestor(cursor,full))
     throw new InvalidOperationException("RC1_PORTABLE_REPARSE_REFUSED");
   }
   string p=Path.GetDirectoryName(cursor);
   if(String.IsNullOrEmpty(p)||String.Equals(p,cursor,StringComparison.Ordinal))break;
   cursor=p;
  }
 }
 static readonly string[] PortableFiles=new[]{
  "Source/remote-window.ps1","Source/rc1-tray-host.ps1",
  "Source/rc1-owner-gui.ps1","Source/rc1-remote-observer.ps1",
  "Source/rc1-quota-client.ps1","Source/RdcOwnerWire.cs",
  "Source/RdcOwnerRuntime.cs","Source/RdcOwnerProcess.cs",
  "Source/RdcOwnerTicketStore.cs","Source/RdcOwnerRemoteState.cs",
  "Source/RdcOwnerManagedProcess.cs","Source/RdcOwnerLogParts.cs","Source/RdcOwnerStartup.cs","Source/RdcUiLanguage.cs",
  "Source/lang/ru-RU.json","Source/lang/en-US.json","Source/rc1-candidate.json",
  "Source/RDCRelay.ico","Source/RdcTrayV04.bin",
  "Source/divider-caustic.ps","Source/divider-caustic-detail.ps",
  "Source/divider-particles.ps","Source/divider-particles-core.ps",
  "Source/update-notice.ps1","Source/update.ps1",
  "RdcOwnerRuntime.dll","RC1 Pilot Launcher.exe"
 };
 static string HashFile(string path){
  using(var sha=SHA256.Create())
  using(var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)){
   return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","");
  }
 }
 // The same exact 27-member content/manifest contract is produced by
 // build-rc1-full.ps1 and independently verified by the standalone Setup.
 // This prevents a normal Explorer open from starting a partial extraction
 // or altered source. A manifest is an integrity manifest, not a signature.
 static void ValidatePortablePackage(string root){
  CheckPortablePath(root);
  CheckPortablePath(Path.Combine(root,"Source"));
  string manifestPath=Path.Combine(root,"owner-source-manifest.json");
  if(!File.Exists(manifestPath)||
     (File.GetAttributes(manifestPath)&FileAttributes.ReparsePoint)!=0)
   throw new InvalidOperationException("RC1_PORTABLE_MANIFEST_REQUIRED");
  var manifest=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(
   File.ReadAllText(manifestPath,new UTF8Encoding(false,true)));
  if(!String.Equals(Convert.ToString(manifest["candidate"]),"1.6.0 RC1",StringComparison.Ordinal)||
     !String.Equals(Convert.ToString(manifest["kind"]),"PRIVATE_FULL_RC1",StringComparison.Ordinal)||
     !String.Equals(Convert.ToString(manifest["ownerMode"]),"FULL_HOST_GUI_RC1",StringComparison.Ordinal)||
     !Convert.ToBoolean(manifest["installable"])||
     Convert.ToBoolean(manifest["publishable"]))
   throw new InvalidOperationException("RC1_PORTABLE_MANIFEST_MODE_REFUSED");
  var files=manifest["files"] as ArrayList;
  if(files==null||files.Count!=PortableFiles.Length)
   throw new InvalidOperationException("RC1_PORTABLE_MANIFEST_SIZE_REFUSED");
  var expected=new HashSet<string>(PortableFiles,StringComparer.Ordinal);
  foreach(object row in files){
   var record=row as Dictionary<string,object>;
   if(record==null||!record.ContainsKey("name")||!record.ContainsKey("sha256"))
    throw new InvalidOperationException("RC1_PORTABLE_MANIFEST_RECORD_REFUSED");
   string name=record["name"] as string,sha=record["sha256"] as string;
   if(String.IsNullOrEmpty(name)||!expected.Remove(name)||
      String.IsNullOrEmpty(sha)||
      !System.Text.RegularExpressions.Regex.IsMatch(sha,@"\A[A-Fa-f0-9]{64}\z"))
    throw new InvalidOperationException("RC1_PORTABLE_MANIFEST_ENTRY_REFUSED");
   // Name is matched to the fixed exact allowlist *before* resolving paths.
   string file=Path.Combine(root,name.Replace('/',Path.DirectorySeparatorChar));
   if(!File.Exists(file)||(File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)
    throw new InvalidOperationException("RC1_PORTABLE_FILE_ABSENT_OR_LINKED");
   if(!String.Equals(HashFile(file),sha,StringComparison.OrdinalIgnoreCase))
    throw new InvalidOperationException("RC1_PORTABLE_FILE_HASH_REFUSED");
  }
  if(expected.Count!=0)throw new InvalidOperationException("RC1_PORTABLE_MISSING_MEMBER");
 }
#if !RDC_RC1_BLOCKED
 static bool BackgroundRequested(string[] args){
  return args!=null&&args.Length==1&&args[0]=="--background";
 }
 static bool DispatchRequested(string[] args){
  return args!=null&&args.Length==1&&args[0]=="--startup-dispatch";
 }
 static bool HostReady(string source){
  try{using(var ready=EventWaitHandle.OpenExisting(GuiEventName(source).Replace("RdcRelayRC1Open-","RdcRelayRC1HostReady-")))return ready.WaitOne(0);}
  catch(WaitHandleCannotBeOpenedException){return false;}
 }
 static int DispatchStartup(){
  string self=System.Reflection.Assembly.GetExecutingAssembly().Location;
  if(!RdcOwnerStartup.CanDispatch(self))throw new InvalidOperationException("RC1_STARTUP_DISPATCH_REFUSED");
  string release=RdcOwnerStartup.ActiveRelease();
  if(release==null)throw new InvalidOperationException("RC1_STARTUP_INSTALL_REQUIRED");
  var start=new ProcessStartInfo(Path.Combine(release,"RC1 Pilot Launcher.exe"),"--background");
  start.UseShellExecute=false;start.CreateNoWindow=true;start.WorkingDirectory=release;
  using(var child=Process.Start(start)){
   if(child==null||!child.WaitForExit(50000))return 42;
   return child.ExitCode;
  }
 }
#endif
 [STAThread]
 static int Main(string[] args) {
#if RDC_RC1_BLOCKED
  Console.Error.WriteLine("RC1_OWNER_LAUNCHER_BLOCKED_PENDING_OWNER_GO");
  return 42;
#else
  try{
   if(DispatchRequested(args))return DispatchStartup();
   bool background=BackgroundRequested(args);
   if(!background&&!FullLaunchRequested(args))
     throw new InvalidOperationException("RC1_FULL_MODE_ARGUMENTS_REFUSED");
   string root=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
   string source=Path.Combine(root,"Source");
   CheckPortablePath(root);
   CheckPortablePath(source);
   string marker=Path.Combine(source,"rc1-candidate.json");
   if(!File.Exists(marker))throw new InvalidOperationException("RC1_NO_MARKER");
   string content=File.ReadAllText(marker,Encoding.UTF8);
   var values=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(content);
   if((string)values["candidate"]!="1.6.0 RC1" ||
      !Convert.ToBoolean(values["installable"]) ||
      !Convert.ToBoolean(values["liveRemoteEnabled"]) ||
      Convert.ToBoolean(values["publishable"]) ||
      Convert.ToBoolean(values["autoUpdateEnabled"]) ||
      (string)values["ownerMode"]!="FULL_HOST_GUI_RC1")
     throw new InvalidOperationException("RC1_NOT_VERIFIED_FULL_CANDIDATE");
   ValidatePortablePackage(root);
   if(background&&(!RdcOwnerStartup.IsActiveSource(source)||RdcOwnerStartup.State()!=1))
    throw new InvalidOperationException("RC1_STARTUP_INSTALL_REQUIRED");
   foreach(string name in new []{"rc1-tray-host.ps1","rc1-owner-gui.ps1",
       "rc1-remote-observer.ps1","rc1-quota-client.ps1","remote-window.ps1",
       "RdcOwnerRuntime.cs","RdcOwnerWire.cs","RdcOwnerTicketStore.cs",
       "RdcOwnerRemoteState.cs","RdcOwnerProcess.cs","RdcOwnerManagedProcess.cs","RdcOwnerLogParts.cs","RdcOwnerStartup.cs","RdcUiLanguage.cs",
       "lang/ru-RU.json","lang/en-US.json","RdcTrayV04.bin"}) {
    string file=Path.Combine(source,name);
    if(!File.Exists(file)||(File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RC1_MISSING_OR_LINKED_SOURCE:"+name);
   }
   string guiEvent=GuiEventName(source),readyEvent=GuiReadyEventName(source);
   if(background&&HostReady(source))return 0;
   if(!background&&SignalExistingGui(guiEvent)){
    if(!WaitForGuiReady(readyEvent,10000))
     throw new InvalidOperationException("RC1_EXISTING_HOST_GUI_NOT_READY");
    Console.WriteLine("RC1_EXISTING_HOST_GUI_READY");
    return 0;
   }
   string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
     @"WindowsPowerShell\v1.0\powershell.exe");
   var psi=new ProcessStartInfo(ps,
     "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \""+
     Path.Combine(source,"rc1-tray-host.ps1")+"\" -Full"+(background?" -Background":""));
   psi.UseShellExecute=false;
   psi.CreateNoWindow=true;
   psi.RedirectStandardError=true;
   psi.WorkingDirectory=source;
   using(var child=Process.Start(psi)){
    if(child==null)throw new InvalidOperationException("RC1_HOST_START_FAILED");
    // Observe bounded host diagnostics without exposing a raw PowerShell
    // exception, path, ticket, credential, or log to the installer UI.
    var hostErrors=child.StandardError.ReadToEndAsync();
    // Never report success merely because PowerShell accepted a new process.
    // A dying Host (singleton conflict / compile error) must fail visibly.
    var clock=Stopwatch.StartNew();
    // A first cold PowerShell/WinForms compilation may take longer than a
    // subsequent tray reopen. Keep the check bounded and monitor Host death.
    while(clock.ElapsedMilliseconds<45000){
     if(child.HasExited){
      string raw=hostErrors.IsCompleted?hostErrors.GetAwaiter().GetResult():"";
      throw new InvalidOperationException(SafeHostExitCode(raw,child.ExitCode));
     }
     if(background&&HostReady(source))return 0;
     if(!background&&SignalExistingGui(guiEvent) && WaitForGuiReady(readyEvent,250)){
      Console.WriteLine("RC1_HOST_STARTED_AUTHENTICATED_GUI_READY");
      return 0;
     }
     Thread.Sleep(250);
    }
    throw new InvalidOperationException("RC1_HOST_NO_GUI_ACTIVATION_ENDPOINT");
   }
  }catch(Exception e){
   Console.Error.WriteLine("RC1_OWNER_LAUNCH_REFUSED:"+SafeFailureCode(e));
   return 42;
  }
#endif
 }
}
