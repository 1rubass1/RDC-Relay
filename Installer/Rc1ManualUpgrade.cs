// Private RC1 manual setup: immutable versioned payload and reversible Desktop
// shell shortcut transition. NEVER sends commands to any Remote/Host process.
// Keep legacy v1.5.18 and prior private RC1 packages intact.
using System;
using System.IO;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

internal static class RdcRc1ManualUpgrade {
 [StructLayout(LayoutKind.Sequential)]
 struct FileAttributeTagInfo { public uint FileAttributes; public uint ReparseTag; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,
  uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int informationClass,
  out FileAttributeTagInfo info,uint size);
 [DllImport("advapi32.dll",SetLastError=true)]
 static extern bool GetTokenInformation(IntPtr token,int kind,byte[] buffer,int length,out int required);
 // RC1 Host uses SHA256(exact Source root | OS logon SID) for its singleton.
 // Setup must use precisely the same key; no guessed PID or process-name kill.
 static string OldHostMutexName(string oldRelease){
  string source=Path.GetFullPath(Path.Combine(oldRelease,"Source")).TrimEnd(Path.DirectorySeparatorChar);
  string sid;
  using(WindowsIdentity identity=WindowsIdentity.GetCurrent()){
   byte[] data=new byte[256];int count;
   if(!GetTokenInformation(identity.Token,28,data,data.Length,out count)||count<16)
    throw new UnauthorizedAccessException("RC1_MANUAL_LOGON_SID_UNAVAILABLE");
   GCHandle pin=GCHandle.Alloc(data,GCHandleType.Pinned);
   try{
    IntPtr ptr=Marshal.ReadIntPtr(pin.AddrOfPinnedObject(),8);
    if(ptr==IntPtr.Zero)throw new UnauthorizedAccessException("RC1_MANUAL_LOGON_SID_NULL");
    sid=new SecurityIdentifier(ptr).Value;
   }finally{pin.Free();}
  }
  using(var sha=SHA256.Create()){
   byte[] key=sha.ComputeHash(Encoding.UTF8.GetBytes(source.ToLowerInvariant()+"|"+sid));
   return @"Local\RdcRelayRC1Owner-"+BitConverter.ToString(key).Replace("-","").Substring(0,32);
  }
 }
 static bool IsWindowsDesktopCloudAncestor(string inspected,string requested) {
  // Only an OS-reported Desktop or its direct child may cross an OS Desktop
  // Cloud Files placeholder. Junctions and symbolic links still fail closed.
  string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
  if(String.IsNullOrEmpty(desktop))return false;
  desktop=Path.GetFullPath(desktop);
  bool inDesktop=String.Equals(requested,desktop,StringComparison.OrdinalIgnoreCase)||
    requested.StartsWith(desktop+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
  bool onDesktopChain=String.Equals(inspected,desktop,StringComparison.OrdinalIgnoreCase)||
    desktop.StartsWith(inspected+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
  if(!inDesktop||!onDesktopChain||!Directory.Exists(inspected))return false;
  using(SafeFileHandle handle=CreateFile(inspected,0,7,IntPtr.Zero,3,
    0x02000000u|0x00200000u,IntPtr.Zero)) {
   if(handle==null||handle.IsInvalid)return false;
   FileAttributeTagInfo info;
   if(!GetFileInformationByHandleEx(handle,9,out info,8))return false;
   // Windows Cloud Files (0x9000001A through 0x9000F01A);
   // do NOT accept junctions 0xA0000003 or symlinks 0xA000000C.
   return (info.ReparseTag & 0xFFFF0FFFu)==0x9000001Au;
  }
 }
 static void CheckPath(string path) {
  string full=Path.GetFullPath(path),current=full;
  while(!String.IsNullOrEmpty(current)) {
   if(File.Exists(current)||Directory.Exists(current)) {
    if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0 &&
       !IsWindowsDesktopCloudAncestor(current,full))
     throw new InvalidOperationException("RC1_MANUAL_REPARSE_REFUSED");
   }
   string parent=Path.GetDirectoryName(current);
   if(String.IsNullOrEmpty(parent)||parent==current)break;
   current=parent;
  }
 }
 static string Sha(string path) {
  using(var s=SHA256.Create())
  using(var stream=File.OpenRead(path))
   return BitConverter.ToString(s.ComputeHash(stream)).Replace("-","");
 }
 static string ReadShortcut(object shortcut,string property) {
  return Convert.ToString(shortcut.GetType().InvokeMember(property,
   BindingFlags.GetProperty,null,shortcut,new object[0]));
 }
 static void SetShortcut(object shortcut,string property,string value) {
  shortcut.GetType().InvokeMember(property,BindingFlags.SetProperty,
   null,shortcut,new object[]{value});
 }
 static object OpenShortcut(object shell,string path) {
  return shell.GetType().InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,
   null,shell,new object[]{path});
 }
 static void SaveShortcut(object shortcut) {
  shortcut.GetType().InvokeMember("Save",BindingFlags.InvokeMethod,
   null,shortcut,new object[0]);
 }
 // Copies only the verified candidate's exact manifest-listed payload.
 // Old installed app directories are never moved, removed or overwritten.
 internal static string Prepare(string source,string localRoot,string[] required) {
  source=Path.GetFullPath(source);
  localRoot=Path.GetFullPath(localRoot);
  CheckPath(source);CheckPath(localRoot);
  string manifest=Path.Combine(source,"owner-source-manifest.json");
  CheckPath(manifest);
  if(!File.Exists(manifest))throw new InvalidOperationException("RC1_MANUAL_MANIFEST_MISSING");
  string expectedManifest=Sha(manifest);
  string releases=Path.Combine(localRoot,"RDCRelayOwnerPilot","1.6.0-RC1","releases");
  CheckPath(releases);
  string destination=Path.Combine(releases,"rc1-"+expectedManifest.Substring(0,24).ToLowerInvariant());
  CheckPath(destination);
  var files=new List<string>(required);
  files.Add("owner-source-manifest.json");
  if(Directory.Exists(destination)) {
   CheckPath(Path.Combine(destination,"owner-source-manifest.json"));
   if(Sha(Path.Combine(destination,"owner-source-manifest.json"))!=expectedManifest)
    throw new InvalidOperationException("RC1_MANUAL_EXISTING_RELEASE_UNKNOWN");
   foreach(string name in files) {
    string input=Path.Combine(source,name.Replace('/',Path.DirectorySeparatorChar));
    string output=Path.Combine(destination,name.Replace('/',Path.DirectorySeparatorChar));
    CheckPath(input);CheckPath(output);
    if(!File.Exists(output)||Sha(input)!=Sha(output))
     throw new InvalidOperationException("RC1_MANUAL_EXISTING_RELEASE_NOT_IDENTICAL");
   }
   return destination;
  }
  Directory.CreateDirectory(releases);
  string stage=Path.Combine(releases,".stage-"+Guid.NewGuid().ToString("N"));
  if(Directory.Exists(stage)||File.Exists(stage))throw new IOException("RC1_MANUAL_STAGE_COLLISION");
  Directory.CreateDirectory(stage);
  bool published=false;
  try {
   foreach(string name in files) {
    string input=Path.Combine(source,name.Replace('/',Path.DirectorySeparatorChar));
    string output=Path.Combine(stage,name.Replace('/',Path.DirectorySeparatorChar));
    CheckPath(input);
    if(!File.Exists(input))throw new IOException("RC1_MANUAL_SOURCE_MISSING:"+name);
    Directory.CreateDirectory(Path.GetDirectoryName(output));
    File.Copy(input,output,false);
    if(Sha(input)!=Sha(output))throw new IOException("RC1_MANUAL_STAGED_HASH_MISMATCH:"+name);
   }
   CheckPath(destination);
   Directory.Move(stage,destination);
   published=true;
   return destination;
  }finally{
   // Never delete an uncertain partial stage; its absolute path is retained
   // for independent operator inspection and provenance verification.
   if(!published&&Directory.Exists(stage))
    Console.Error.WriteLine("RC1_MANUAL_STAGING_RETAINED:"+stage);
  }
 }
 // Switches the *main Desktop shortcut* only when its original target is the
 // known stable 1.5.18 shell or an already validated private RC1 launcher.
 // No process termination or adopted Remote lifecycle permission is implied.
 internal static string ActivateDesktop(string release,string localRoot,string desktop) {
  release=Path.GetFullPath(release);
  CheckPath(release);CheckPath(desktop);
  string launcher=Path.Combine(release,"RC1 Pilot Launcher.exe");
  if(!File.Exists(launcher))throw new InvalidOperationException("RC1_MANUAL_LAUNCHER_ABSENT");
  string legacy=Path.Combine(localRoot,"RemoteDesktopCommanderLauncher","remote-window.ps1");
  string legacyVersion=Path.Combine(localRoot,"RemoteDesktopCommanderLauncher","version.txt");
  CheckPath(legacy);CheckPath(legacyVersion);
  string desktopLink=Path.Combine(desktop,"RDC Relay.lnk");
  CheckPath(desktopLink);
  bool firstInstall=!File.Exists(desktopLink);
  bool switchedFromStable=false;
  Type shellType=Type.GetTypeFromProgID("WScript.Shell");
  if(shellType==null)throw new InvalidOperationException("RC1_MANUAL_NO_SHELL_LINK_COM");
  object shell=Activator.CreateInstance(shellType);
  object old=null,newLink=null;
  Mutex oldHostLock=null;
  bool oldHostLocked=false;
  try {
   if(!firstInstall){
    old=OpenShortcut(shell,desktopLink);
    string oldTarget=ReadShortcut(old,"TargetPath");
    string oldArgs=ReadShortcut(old,"Arguments");
    string powershell=Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe");
    string stableArgs="-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+legacy+"\"";
    string earlierStableArgs="-NoProfile -STA -ExecutionPolicy Bypass -File \""+legacy+"\"";
    bool isStable=File.Exists(legacy)&&File.Exists(legacyVersion)&&
      String.Equals(File.ReadAllText(legacyVersion).Trim(),"1.5.18",StringComparison.Ordinal)&&
      String.Equals(Path.GetFullPath(oldTarget),Path.GetFullPath(powershell),StringComparison.OrdinalIgnoreCase)&&
      (String.Equals(oldArgs.Trim(),stableArgs,StringComparison.OrdinalIgnoreCase)||
       String.Equals(oldArgs.Trim(),earlierStableArgs,StringComparison.OrdinalIgnoreCase));
    string oldFull=Path.GetFullPath(oldTarget);
    string oldDir=Path.GetDirectoryName(oldFull);
    string pilotRoot=Path.GetFullPath(Path.Combine(localRoot,"RDCRelayOwnerPilot","1.6.0-RC1"));
    string installedApp=Path.Combine(pilotRoot,"app");
    string releaseRoot=Path.Combine(pilotRoot,"releases")+Path.DirectorySeparatorChar;
    bool knownPilotDirectory=String.Equals(oldDir,installedApp,StringComparison.OrdinalIgnoreCase)||
      (oldDir.StartsWith(releaseRoot,StringComparison.OrdinalIgnoreCase)&&
       oldDir.Substring(releaseRoot.Length).StartsWith("rc1-",StringComparison.OrdinalIgnoreCase)&&
       oldDir.Substring(releaseRoot.Length).IndexOf(Path.DirectorySeparatorChar)<0);
    bool isOldRc1=String.Equals(Path.GetFileName(oldFull),"RC1 Pilot Launcher.exe",StringComparison.OrdinalIgnoreCase)&&
      knownPilotDirectory&&File.Exists(oldFull)&&
      (String.Equals(oldArgs.Trim(),"--observe-existing",StringComparison.Ordinal)||
       String.Equals(oldArgs.Trim(),"--full",StringComparison.Ordinal));
    if(!isStable&&!isOldRc1)
     throw new InvalidOperationException("RC1_MANUAL_UNKNOWN_OLD_SHORTCUT_REFUSED");
    switchedFromStable=isStable;
    if(String.Equals(Path.GetFullPath(oldTarget),Path.GetFullPath(launcher),StringComparison.OrdinalIgnoreCase)&&
        String.Equals(oldArgs.Trim(),"--full",StringComparison.Ordinal))
     return "ALREADY_ACTIVE";
    // Hold the old exact source-root/logon Host mutex across shortcut
    // replacement. A running Host (even an unidentified process with this
    // mutex) causes a refusal; no RC1 process receives a stop signal.
    if(isOldRc1){
     CheckPath(oldDir);
     bool acquired;
     oldHostLock=new Mutex(true,OldHostMutexName(oldDir),out acquired);
     if(!acquired)throw new InvalidOperationException("RC1_MANUAL_PREVIOUS_RC1_HOST_ACTIVE");
     oldHostLocked=true;
    }
   }
   string temporary=Path.Combine(desktop,".rdc-rc1-"+Guid.NewGuid().ToString("N")+".lnk");
   string backup=Path.Combine(Path.GetDirectoryName(release),
    "primary-shortcut-backup-"+Guid.NewGuid().ToString("N")+".lnk");
   CheckPath(temporary);CheckPath(backup);
   if(File.Exists(temporary)||File.Exists(backup))throw new IOException("RC1_MANUAL_SHORTCUT_COLLISION");
   newLink=OpenShortcut(shell,temporary);
   SetShortcut(newLink,"TargetPath",launcher);
   SetShortcut(newLink,"Arguments","--full");
   SetShortcut(newLink,"WorkingDirectory",release);
   SetShortcut(newLink,"IconLocation",Path.Combine(release,"Source","RDCRelay.ico")+",0");
   SetShortcut(newLink,"Description","RDC Relay 1.6.0 RC1 (full Host/GUI candidate)");
   SaveShortcut(newLink);
   Marshal.FinalReleaseComObject(newLink);newLink=null;
   if(!File.Exists(temporary))throw new IOException("RC1_MANUAL_NEW_SHORTCUT_MISSING");
   string candidateLinkHash=Sha(temporary);
   if(firstInstall){
    // Fresh install: no user's previous Desktop shortcut to replace.
    File.Move(temporary,desktopLink);
    if(Sha(desktopLink)!=candidateLinkHash)
     throw new IOException("RC1_MANUAL_LINK_PUBLICATION_MISMATCH");
    return "CREATED";
   }
   // Desktop may be redirected to OneDrive/a different volume. Preserve a
   // verified copy before same-volume atomic File.Replace (no cross-volume
   // backup argument to ReplaceFile). Never delete an older backup.
   File.Copy(desktopLink,backup,false);
   if(Sha(desktopLink)!=Sha(backup))
    throw new IOException("RC1_MANUAL_SHORTCUT_BACKUP_HASH_MISMATCH");
   CheckPath(desktopLink);CheckPath(temporary);
   File.Replace(temporary,desktopLink,null);
   if(Sha(desktopLink)!=candidateLinkHash)
    throw new IOException("RC1_MANUAL_LINK_PUBLICATION_MISMATCH");
   Console.WriteLine("RC1_MANUAL_PREVIOUS_SHORTCUT_BACKUP:"+backup);
   return switchedFromStable?"SWITCHED_STABLE":"SWITCHED_RC1";
  }finally{
   if(newLink!=null)Marshal.FinalReleaseComObject(newLink);
   if(old!=null)Marshal.FinalReleaseComObject(old);
   Marshal.FinalReleaseComObject(shell);
   if(oldHostLock!=null){
    if(oldHostLocked)oldHostLock.ReleaseMutex();
    oldHostLock.Dispose();
   }
  }
 }
}
