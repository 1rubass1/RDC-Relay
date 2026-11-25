// Private RDC Relay 1.6.0 Setup. The repository's blocked-marker
// compiler path stays inert; only an exact-manifest owner-pilot package
// embeds the full Host/GUI payload for user-confirmed manual upgrades.
// Setup never stops or takes ownership of an existing Desktop Commander Remote.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Reflection;
using System.Diagnostics;
using System.Web.Script.Serialization;
using Microsoft.Win32;

internal static class RdcRc1CandidateSetup {
 static readonly string[] Required=new string[]{
  "Source/remote-window.ps1","Source/rc1-tray-host.ps1","Source/rc1-owner-gui.ps1",
  "Source/rc1-remote-observer.ps1","Source/rc1-quota-client.ps1",
  "Source/RdcOwnerWire.cs","Source/RdcOwnerRuntime.cs","Source/RdcOwnerProcess.cs",
  "Source/RdcOwnerTicketStore.cs","Source/RdcOwnerRemoteState.cs",
  "Source/RdcOwnerManagedProcess.cs","Source/RdcOwnerLogParts.cs","Source/RdcOwnerStartup.cs","Source/RdcUiLanguage.cs",
  "Source/lang/ru-RU.json","Source/lang/en-US.json",
  "Source/rc1-candidate.json","Source/RDCRelay.ico","Source/RdcTrayV04.bin",
  "Source/divider-caustic.ps","Source/divider-caustic-detail.ps",
  "Source/divider-particles.ps","Source/divider-particles-core.ps",
  "Source/update-notice.ps1","Source/update.ps1","Source/version.txt","Source/THIRD_PARTY_NOTICES.txt","RdcOwnerRuntime.dll",
  "RDC Relay.exe"
 };
 static void PathSafe(string path){
  string full=Path.GetFullPath(path),p=full;
  while(!String.IsNullOrEmpty(p)){
   if(File.Exists(p)||Directory.Exists(p)){
    if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
      throw new InvalidOperationException("RC1_REPARSE_REFUSED");
   }
   string parent=Path.GetDirectoryName(p);
   if(String.IsNullOrEmpty(parent)||parent==p)break;p=parent;
  }
 }
 static Dictionary<string,object> ReadJson(string file){
  return new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(file,Encoding.UTF8));
 }
 static string Hash(string file){
  using(var sha=SHA256.Create())
  using(var input=File.OpenRead(file))
   return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","");
 }
 internal static void ValidateSource(string root){ValidateInstalledSource(root);if((string)ReadJson(Path.Combine(root,"owner-source-manifest.json"))["kind"]!="FULL_HOST_GUI_V16_PUBLIC")throw new InvalidOperationException("V16_PUBLIC_SETUP_KIND");if(RdcV16MetadataTransaction.ReleaseVersion(root)!="1.6.0")throw new InvalidOperationException("V16_SETUP_WRONG_VERSION");}
 internal static void ValidateInstalledSource(string root){
  PathSafe(root);
  if(!File.Exists(Path.Combine(root,"owner-source-manifest.json")))
   throw new InvalidOperationException("RC1_MANIFEST_ABSENT");
  var manifest=ReadJson(Path.Combine(root,"owner-source-manifest.json"));
  if(!RdcV16MetadataTransaction.IsFullVersion((string)manifest["candidate"])||((string)manifest["kind"]!="FULL_HOST_GUI_V16_PUBLIC"&&(string)manifest["kind"]!="FULL_HOST_GUI_V16_QUALIFICATION")||Convert.ToBoolean(manifest["publishable"])!=((string)manifest["kind"]=="FULL_HOST_GUI_V16_PUBLIC")||RdcV16MetadataTransaction.ReleaseVersion(root)!=(string)manifest["candidate"])throw new InvalidOperationException("RC1_BAD_CANDIDATE");
  var candidate=ReadJson(Path.Combine(root,"Source","rc1-candidate.json"));
  if(!String.Equals(Convert.ToString(candidate["candidate"]),
      Convert.ToString(manifest["candidate"]),StringComparison.Ordinal))
   throw new InvalidOperationException("RC1_MANIFEST_CANDIDATE_VERSION_MISMATCH");
  // The repository Source marker stays blocked; only a newly staged, hashed
  // owner-pilot payload explicitly enables the read-only observation mode.
  if(!Convert.ToBoolean(candidate["installable"]) ||
     !Convert.ToBoolean(candidate["liveRemoteEnabled"]) ||
     Convert.ToBoolean(candidate["publishable"])!=Convert.ToBoolean(manifest["publishable"]) ||
     Convert.ToBoolean(candidate["autoUpdateEnabled"]) ||
     (string)candidate["ownerMode"]!="FULL_HOST_GUI_RC1")
   throw new InvalidOperationException("RC1_NOT_ISOLATED_FULL_CANDIDATE");
  string[] validationRequired=(string)manifest["kind"]=="FULL_HOST_GUI_V16_PUBLIC"?Required:Required.Select(x=>x=="RDC Relay.exe"?"RC1 Pilot Launcher.exe":x).ToArray();
  var listed=new List<string>();
  var rows=(System.Collections.ArrayList)manifest["files"];
  foreach(Dictionary<string,object> item in rows)
    listed.Add((string)item["name"]);
  if(listed.Count!=validationRequired.Length || listed.Count!=listed.Distinct(StringComparer.Ordinal).Count())
   throw new InvalidOperationException("RC1_MANIFEST_NOT_EXACT_UNIQUE_SET");
  foreach(string required in validationRequired){
   if(listed.Count(x=>String.Equals(x,required,StringComparison.Ordinal))!=1)
    throw new InvalidOperationException("RC1_MISSING_PAYLOAD:"+required);
   string file=Path.Combine(root,required.Replace('/',Path.DirectorySeparatorChar));
   PathSafe(file);
   if(!File.Exists(file))throw new InvalidOperationException("RC1_PAYLOAD_ABSENT:"+required);
   foreach(Dictionary<string,object> row in rows){
    if((string)row["name"]!=required)continue;
    if(!String.Equals(Hash(file),(string)row["sha256"],StringComparison.Ordinal))
      throw new InvalidOperationException("RC1_PAYLOAD_HASH:"+required);
   }
  }
 }
 static string ExtractEmbeddedCandidate(){
  // Setup.exe is a complete downloadable installer. The 19 runtime items and
  // manifest are embedded by the private candidate builder, not read from the
  // folder where the user downloaded Setup.exe.
  string staging=Path.Combine(Path.GetTempPath(),"RDC-RC1-SETUP-"+Guid.NewGuid().ToString("N"));
  PathSafe(staging);
  Directory.CreateDirectory(staging);
  var asm=Assembly.GetExecutingAssembly();
  foreach(string name in Required.Concat(new[]{"owner-source-manifest.json"})){
   string resource="RdcPayload."+name.Replace('/','.');
   using(Stream data=asm.GetManifestResourceStream(resource)){
    if(data==null)throw new InvalidOperationException("RC1_SETUP_EMBEDDED_MISSING:"+name);
    string destination=Path.Combine(staging,name.Replace('/',Path.DirectorySeparatorChar));
    PathSafe(destination);
    Directory.CreateDirectory(Path.GetDirectoryName(destination));
    using(var output=new FileStream(destination,FileMode.CreateNew,FileAccess.Write,FileShare.None))
     data.CopyTo(output);
   }
  }
  return staging;
 }
 static void CleanExactExtraction(string staging){
  string leaf=Path.GetFileName(staging),prefix="RDC-RC1-SETUP-";
  Guid guid;
  if(!leaf.StartsWith(prefix,StringComparison.Ordinal)||
     !Guid.TryParseExact(leaf.Substring(prefix.Length),"N",out guid)||
     !String.Equals(Path.GetDirectoryName(Path.GetFullPath(staging)),
       Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar),
       StringComparison.OrdinalIgnoreCase))
   throw new InvalidOperationException("RC1_SETUP_CLEANUP_SCOPE_REFUSED");
  PathSafe(staging);
  var expected=new HashSet<string>(
   Required.Concat(new[]{"owner-source-manifest.json"}),StringComparer.OrdinalIgnoreCase);
  var actual=Directory.GetFiles(staging,"*",SearchOption.AllDirectories);
  if(actual.Length!=expected.Count)throw new InvalidOperationException("RC1_SETUP_CLEANUP_UNKNOWN_FILES");
  foreach(string path in actual){
   PathSafe(path);
   string relative=path.Substring(staging.Length+1).Replace('\\','/');
   if(!expected.Remove(relative))throw new InvalidOperationException("RC1_SETUP_CLEANUP_FOREIGN_FILE");
  }
  foreach(string path in actual)File.Delete(path);
  foreach(string dir in Directory.GetDirectories(staging,"*",SearchOption.AllDirectories)
    .OrderByDescending(x=>x.Length)){
   PathSafe(dir);Directory.Delete(dir,false);
  }
  Directory.Delete(staging,false);
 }
 // In the private Owner Pilot the stable Installed Apps registration is
 // deliberately retained for quick rollback. Read it as evidence of an
 // existing installation, but NEVER overwrite it during this pilot.
 // The Desktop shortcut is secondary evidence of a prior RC1 handoff.
 internal static bool HasPrimaryDesktopShortcut(string desktop){
  return RdcRc1ManualUpgrade.HasPrimaryDesktopShortcut(desktop);
 }
 internal static bool ValidateInstalledRegistration(string name,string publisher,
  string registryVersion,string registryRoot,string expectedRoot,
  string diskVersion,bool hasGui,bool hasUpdater){
  bool owner=String.Equals(name,"RDC Relay",StringComparison.Ordinal);
  bool knownPublisher=String.Equals(publisher,"UMAS",StringComparison.Ordinal)||
   String.Equals(publisher,"RUBASS",StringComparison.Ordinal);
  bool version=System.Text.RegularExpressions.Regex.IsMatch(registryVersion??"",
   @"^[0-9]+\.[0-9]+\.[0-9]+$");
  bool samePath=false;
  try{
   samePath=!String.IsNullOrWhiteSpace(registryRoot)&&
    String.Equals(Path.GetFullPath(registryRoot).TrimEnd(Path.DirectorySeparatorChar),
     Path.GetFullPath(expectedRoot).TrimEnd(Path.DirectorySeparatorChar),
     StringComparison.OrdinalIgnoreCase);
  }catch(ArgumentException){}catch(NotSupportedException){}
  if(!owner||!knownPublisher||!version||!samePath||
   !String.Equals(registryVersion,diskVersion,StringComparison.Ordinal)||
   !hasGui||!hasUpdater)
   throw new InvalidOperationException("RC1_REGISTERED_INSTALL_INCONSISTENT");
  return true;
 }
 internal static bool HasRegisteredStableInstallation(string localRoot){
  const string uninstall=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\RDC Relay";
  // This pilot can replace only a known per-user stable installation, not
  // an unverified machine-wide RDC Relay managed by an administrator.
  const string machineUninstall=@"Software\Microsoft\Windows\CurrentVersion\Uninstall";
  foreach(RegistryView view in new[]{RegistryView.Registry64,RegistryView.Registry32}){
   using(var hive=RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,view))
   using(var entries=hive.OpenSubKey(machineUninstall,false)){
    if(entries==null)continue;
    foreach(string entry in entries.GetSubKeyNames()){
     if(String.Equals(entry,"RDC Relay",StringComparison.OrdinalIgnoreCase))
      throw new InvalidOperationException("RC1_MACHINE_INSTALL_REFUSED");
     using(var key=entries.OpenSubKey(entry,false)){
      if(key!=null&&String.Equals(Convert.ToString(key.GetValue("DisplayName","")),
       "RDC Relay",StringComparison.OrdinalIgnoreCase))
       throw new InvalidOperationException("RC1_MACHINE_INSTALL_REFUSED");
     }
    }
   }
  }
  if(RdcV16IntegratedMaintenance.IsRegistered(localRoot))return true;
  string stable=Path.Combine(localRoot,"RemoteDesktopCommanderLauncher");
  string gui=Path.Combine(stable,"remote-window.ps1");
  string updater=Path.Combine(stable,"update.ps1");
  string versionFile=Path.Combine(stable,"version.txt");
  PathSafe(stable);
  using(var key=Registry.CurrentUser.OpenSubKey(uninstall,false)){
   if(key==null){
    // A leftover stable payload without an uninstall entry is not a
    // clean first install; leave it untouched and ask for review.
    if((File.Exists(gui)||File.Exists(updater)||File.Exists(versionFile))&&!RdcV16IntegratedMaintenance.HasRetainedRollback(localRoot))
     throw new InvalidOperationException("RC1_UNREGISTERED_STABLE_PAYLOAD_REFUSED");
    return false;
   }
   string diskVersion=File.Exists(versionFile)?
    File.ReadAllText(versionFile,Encoding.UTF8).Trim():"";
   return ValidateInstalledRegistration(
    Convert.ToString(key.GetValue("DisplayName","")),
    Convert.ToString(key.GetValue("Publisher","")),
    Convert.ToString(key.GetValue("DisplayVersion","")),
    Convert.ToString(key.GetValue("InstallLocation","")),
    stable,diskVersion,File.Exists(gui),File.Exists(updater));
  }
 }
 // Resolve the displayed version from the exact validated payload manifest,
 // not a second independently maintained literal in the confirmation text.
 internal static string ValidatedCandidateDisplayVersion(string source){
  var manifest=ReadJson(Path.Combine(source,"owner-source-manifest.json"));
  string version=Convert.ToString(manifest["candidate"]);
  if(String.IsNullOrEmpty(version)||
     !System.Text.RegularExpressions.Regex.IsMatch(version,@"^[0-9]+\.[0-9]+\.[0-9]+$"))
   throw new InvalidOperationException("RC1_DISPLAY_VERSION_INVALID");
  return version;
 }
 // Node is an external shared runtime, not a Relay-owned file. Only an
 // interactive, explicitly accepted prerequisite install can change it.
 // The pinned upstream release is the LTS major used by the vendor's
 // Windows launcher. Never run a downloaded script or resolve "latest".
 const string NodeMsiUrl="https://nodejs.org/dist/v24.22.3/node-v24.22.3-x64.msi";
 const string NodeMsiSha256="4A1AB5BDEC5434BAE58EFAE6C3E5077A011F6F1E76D2B47B7B10AF043F7DB545";
 internal static bool SupportedNodeVersion(int major,int minor){
  return major>22||(major==22&&minor>=12);
 }
 static string[] NodeRuntimeRoots(){
  return new[]{
   Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"nodejs"),
   Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"npm"),
   Path.Combine(Environment.GetEnvironmentVariable("ProgramFiles(x86)")??@"C:\Program Files (x86)","nodejs")
  }.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
 }
 // Same shim search order as the private Host. An already present but
 // incomplete/custom runtime is not permission to replace shared Node.
 internal static string ClassifyNodePrerequisite(string[] roots){
  bool foundAny=false;
  foreach(string root in roots){
   PathSafe(root);
   string shim=Path.Combine(root,"npx.cmd");
   string node=Path.Combine(root,"node.exe");
   string npm=Path.Combine(root,"npm.cmd");
   foreach(string file in new[]{shim,node,npm})PathSafe(file);
   if(File.Exists(shim)||File.Exists(node)||File.Exists(npm))foundAny=true;
   if(!File.Exists(shim))continue;
   string cli=Path.Combine(root,"node_modules","npm","bin","npx-cli.js");
   string npmCli=Path.Combine(root,"node_modules","npm","bin","npm-cli.js");
   PathSafe(cli);PathSafe(npmCli);
   if(!File.Exists(node)||!File.Exists(npm)||!File.Exists(cli)||!File.Exists(npmCli))
    return "EXISTING_UNSUPPORTED";
   var version=FileVersionInfo.GetVersionInfo(node);
   return SupportedNodeVersion(version.FileMajorPart,version.FileMinorPart)?
    "READY":"EXISTING_UNSUPPORTED";
  }
  return foundAny?"EXISTING_UNSUPPORTED":"MISSING";
 }
 static bool OtherNodeOnPath(){
  foreach(string entry in (Environment.GetEnvironmentVariable("PATH")??"").Split(';')){
   string dir=entry.Trim().Trim('"');
   // Never consult a relative/network PATH entry or execute PATH programs.
   if(dir.Length<3||dir[1]!=':'||dir[2]!='\\')continue;
   try{
    if(File.Exists(Path.Combine(dir,"node.exe"))||
       File.Exists(Path.Combine(dir,"npm.cmd"))||
       File.Exists(Path.Combine(dir,"npx.cmd")))return true;
   }catch{}
  }
  return false;
 }
 // A custom MSI installation may not be in PATH or the standard folders.
 // Read uninstall identities only; never install over an existing registered
 // Node runtime merely because its executable was moved or removed.
 static bool OtherNodeRegistered(){
  const string uninstall=@"Software\Microsoft\Windows\CurrentVersion\Uninstall";
  foreach(RegistryHive hive in new[]{RegistryHive.LocalMachine,RegistryHive.CurrentUser})
   foreach(RegistryView view in new[]{RegistryView.Registry64,RegistryView.Registry32})
    using(var baseKey=RegistryKey.OpenBaseKey(hive,view))
    using(var entries=baseKey.OpenSubKey(uninstall,false)){
     if(entries==null)continue;
     foreach(string name in entries.GetSubKeyNames())
      using(var key=entries.OpenSubKey(name,false)){
       if(key==null)continue;
       string display=Convert.ToString(key.GetValue("DisplayName",""));
       if(String.Equals(display,"Node.js",StringComparison.OrdinalIgnoreCase)||
          display.StartsWith("Node.js ",StringComparison.OrdinalIgnoreCase))return true;
      }
    }
  return false;
 }
 internal static bool NodeEnglish(bool existing){
  try{
   string pref=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "RDCRelay","ui-language.json");
   PathSafe(pref);
   if(File.Exists(pref)&&new FileInfo(pref).Length<=128){
    string value=File.ReadAllText(pref,Encoding.UTF8).Trim();
    if(value=="{\"version\":1,\"locale\":\"en-US\"}")return true;
    if(value=="{\"version\":1,\"locale\":\"ru-RU\"}")return false;
   }
  }catch{}
  return !existing && !System.Globalization.CultureInfo.CurrentUICulture.Name.StartsWith("ru",StringComparison.OrdinalIgnoreCase);
 }
 static void DownloadPinnedNode(string file,System.Threading.CancellationToken cancellation){
  // The standalone .NET Framework Setup must negotiate a modern TLS session.
  // The normal system certificate validation remains enabled.
  System.Net.ServicePointManager.SecurityProtocol=System.Net.SecurityProtocolType.Tls12;
  var request=(System.Net.HttpWebRequest)System.Net.WebRequest.Create(NodeMsiUrl);
  request.AllowAutoRedirect=false;
  request.Timeout=30000;request.ReadWriteTimeout=30000;
  const long limit=64L*1024*1024;
  using(cancellation.Register(()=>request.Abort()))
  using(var response=(System.Net.HttpWebResponse)request.GetResponse()){
   if(response.StatusCode!=System.Net.HttpStatusCode.OK||
      response.ContentLength>limit)
    throw new InvalidOperationException("RC1_NODE_DOWNLOAD_REFUSED");
   using(var input=response.GetResponseStream())
   using(var output=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] buffer=new byte[65536];long total=0;int count;
    while((count=input.Read(buffer,0,buffer.Length))>0){
     cancellation.ThrowIfCancellationRequested();
     total+=count;
     if(total>limit)throw new InvalidOperationException("RC1_NODE_DOWNLOAD_LIMIT");
     output.Write(buffer,0,count);
    }
   }
  }
  cancellation.ThrowIfCancellationRequested();
  if(!String.Equals(Hash(file),NodeMsiSha256,StringComparison.Ordinal))
   throw new InvalidOperationException("RC1_NODE_MSI_HASH_MISMATCH");
 }
 static void DownloadPinnedNodeWithProgress(string file,bool en){
  // The Setup is a WinExe, not a console. Keep a small cancellable progress
  // window responsive while downloading, with no extra confirmation at completion.
  using(var cancel=new System.Threading.CancellationTokenSource())
  using(var dialog=new System.Windows.Forms.Form())
  using(var timer=new System.Windows.Forms.Timer()){
   dialog.Text="RDC Relay";
   dialog.Width=440;dialog.Height=130;
   dialog.StartPosition=System.Windows.Forms.FormStartPosition.CenterScreen;
   dialog.FormBorderStyle=System.Windows.Forms.FormBorderStyle.FixedDialog;
   dialog.MaximizeBox=false;dialog.MinimizeBox=false;
   var label=new System.Windows.Forms.Label();
   label.Text=en?"Downloading Node.js 24 LTS...":"Загрузка Node.js 24 LTS...";
   label.Dock=System.Windows.Forms.DockStyle.Fill;
   var progress=new System.Windows.Forms.ProgressBar();
   progress.Style=System.Windows.Forms.ProgressBarStyle.Marquee;
   progress.MarqueeAnimationSpeed=30;
   progress.Height=20;progress.Dock=System.Windows.Forms.DockStyle.Bottom;
   dialog.Controls.Add(label);dialog.Controls.Add(progress);
   var task=System.Threading.Tasks.Task.Factory.StartNew(
    ()=>DownloadPinnedNode(file,cancel.Token),
    System.Threading.CancellationToken.None,System.Threading.Tasks.TaskCreationOptions.None,
    System.Threading.Tasks.TaskScheduler.Default);
   timer.Interval=100;
   timer.Tick+=delegate{
    if(task.IsCompleted){timer.Stop();dialog.Close();}
   };
   dialog.FormClosing+=delegate(object sender,System.Windows.Forms.FormClosingEventArgs e){
    if(!task.IsCompleted){
     e.Cancel=true;
     label.Text=en?"Cancelling download...":"Отмена загрузки...";
     cancel.Cancel();
    }
   };
   timer.Start();
   dialog.ShowDialog();
   timer.Stop();
   task.GetAwaiter().GetResult();
  }
 }
 static bool EnsureNodePrerequisite(bool existing){
  string[] roots=NodeRuntimeRoots();
  string state=ClassifyNodePrerequisite(roots);
  if(state=="READY")return true;
  bool en=NodeEnglish(existing);
  if(state!="MISSING"||OtherNodeOnPath()||OtherNodeRegistered()){
   System.Windows.Forms.MessageBox.Show(en?
    "An existing Node.js installation is incomplete, unsupported or outside the standard location. Repair it (Node.js 22.12 or newer, with npm/npx), then run Setup again. RDC Relay will not replace a shared runtime automatically.":
    "Обнаружена неполная, неподдерживаемая или нестандартная установка Node.js. Восстановите Node.js 22.12 или новее с npm/npx и повторите запуск Setup. RDC Relay не заменяет общую среду автоматически.",
    "RDC Relay",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
   return false;
  }
  string arch=Environment.GetEnvironmentVariable("PROCESSOR_ARCHITEW6432")??
   Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")??"";
  if(!Environment.Is64BitOperatingSystem||!String.Equals(arch,"AMD64",StringComparison.OrdinalIgnoreCase)){
   System.Windows.Forms.MessageBox.Show(en?
    "Automatic Node.js installation is available for x64 Windows only. Install a supported Node.js with npm/npx and run Setup again.":
    "Автоматическая установка Node.js пока доступна только для Windows x64. Установите поддерживаемый Node.js с npm/npx и повторите запуск Setup.",
    "RDC Relay",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
   return false;
  }
  var answer=System.Windows.Forms.MessageBox.Show(en?
   "Desktop Commander Remote requires Node.js and npm/npx. Download and install the official Node.js 24 LTS runtime now? Windows may request administrator approval.":
   "Desktop Commander Remote требует Node.js и npm/npx. Скачать и установить официальный Node.js 24 LTS? Windows может запросить разрешение администратора.",
   "RDC Relay",System.Windows.Forms.MessageBoxButtons.YesNo,
   System.Windows.Forms.MessageBoxIcon.Question,System.Windows.Forms.MessageBoxDefaultButton.Button2);
  if(answer!=System.Windows.Forms.DialogResult.Yes)return false;
  string temp=Path.Combine(Path.GetTempPath(),"RDC-NodePrerequisite-"+Guid.NewGuid().ToString("N"));
  PathSafe(temp);
  if(Directory.Exists(temp)||File.Exists(temp))throw new InvalidOperationException("RC1_NODE_TEMP_COLLISION");
  Directory.CreateDirectory(temp);
  string msi=Path.Combine(temp,"node-v24.22.3-x64.msi");
  try{
   Console.WriteLine("RC1_NODE_DOWNLOAD_START");
   DownloadPinnedNodeWithProgress(msi,en);
   // Recheck after the download, before asking Windows Installer to run.
   state=ClassifyNodePrerequisite(roots);
   if(state=="READY")return true;
   if(state!="MISSING"||OtherNodeOnPath()||OtherNodeRegistered())throw new InvalidOperationException("RC1_NODE_STATE_CHANGED");
   if(Hash(msi)!=NodeMsiSha256)throw new InvalidOperationException("RC1_NODE_MSI_HASH_MISMATCH");
   string msiexec=Path.Combine(Environment.SystemDirectory,"msiexec.exe");
   PathSafe(msiexec);
   var start=new ProcessStartInfo(msiexec,"/i \""+msi+"\" /passive /norestart");
   start.UseShellExecute=true;start.Verb="runas";start.WorkingDirectory=temp;
   Console.WriteLine("RC1_NODE_INSTALL_START");
   using(Process child=Process.Start(start)){
    if(child==null)throw new InvalidOperationException("RC1_NODE_MSI_NOT_STARTED");
    child.WaitForExit();
    Console.WriteLine("RC1_NODE_MSI_EXIT="+child.ExitCode);
    if(child.ExitCode==3010)throw new InvalidOperationException("RC1_NODE_RESTART_REQUIRED");
    if(child.ExitCode!=0)throw new InvalidOperationException("RC1_NODE_MSI_FAILED_"+child.ExitCode);
   }
   if(ClassifyNodePrerequisite(roots)!="READY")
    throw new InvalidOperationException("RC1_NODE_POSTINSTALL_NOT_READY");
   Console.WriteLine("RC1_NODE_PREREQUISITE_READY");
   return true;
  }finally{
   // Do not touch any shared Node installation or npm cache on failure.
   // Only clean this attempt's unique downloaded MSI and empty directory.
   try{PathSafe(temp);PathSafe(msi);if(File.Exists(msi))File.Delete(msi);
    if(Directory.Exists(temp)&&Directory.GetFileSystemEntries(temp).Length==0)Directory.Delete(temp,false);
   }catch{}
  }
 }
 static void StartPrivateFull(string release){
  // Open only our pinned read-only GUI launcher. The launcher returns after
  // spawning the private Host; never wait for or signal persistent descendants.
  string launcher=Path.Combine(release,"RDC Relay.exe");
  PathSafe(launcher);
  if(!File.Exists(launcher))throw new InvalidOperationException("RC1_AUTOLAUNCH_MISSING");
  var start=new ProcessStartInfo(launcher,"--full");
  start.UseShellExecute=false;
  start.CreateNoWindow=true;
  start.RedirectStandardError=true;
  start.RedirectStandardOutput=true;
  start.WorkingDirectory=release;
  using(Process child=Process.Start(start)){
   if(child==null)throw new InvalidOperationException("RC1_AUTOLAUNCH_START_REFUSED");
   // Read both streams asynchronously: a child cannot deadlock the Setup
   // on a full redirected pipe while the bounded startup check is active.
   var errors=child.StandardError.ReadToEndAsync();
   var output=child.StandardOutput.ReadToEndAsync();
   if(!child.WaitForExit(55000))throw new InvalidOperationException("RC1_AUTOLAUNCH_TIMEOUT");
   if(child.ExitCode!=0){
    string detail=errors.IsCompleted?errors.GetAwaiter().GetResult():"";
    var match=System.Text.RegularExpressions.Regex.Match(detail,
     @"RC1_OWNER_LAUNCH_REFUSED:(RC1_[A-Z0-9_]{3,100})");
    throw new InvalidOperationException(match.Success?
     match.Groups[1].Value:"RC1_AUTOLAUNCH_LAUNCHER_EXIT_"+child.ExitCode);
   }
   // The launcher exit code is authoritative. Its stdout is diagnostic only.
  }
 }
 [STAThread]
 static int Main(string[] args){
#if RDC_RC1_BLOCKED
  // Build and inspect only; this file intentionally cannot install today.
  Console.Error.WriteLine("RC1_OWNER_SETUP_BLOCKED_NEEDS_OS_TRIAL_AND_G1_GO");
  return 42;
#else
  string extracted=null; RdcReleaseLegacyMigrationLease legacyLease=null; IDisposable maintenanceLease=null;
  try{
   if(args.Length==1&&args[0]=="--uninstall")return RdcV16IntegratedMaintenance.RunRemoval(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),Required);
   bool privateSideBySide=args.Length==1 && args[0]=="--owner-approved-side-by-side";
   bool manualUpgrade=args.Length==0 ||
    (args.Length==1 && args[0]=="--owner-approved-manual-upgrade");
   if(!privateSideBySide&&!manualUpgrade)
    throw new InvalidOperationException("RC1_SETUP_UNKNOWN_MODE");
   // The existing scripted observer upgrade continues to require its
   // independently approved process+manifest transaction and owner gate.
   if((privateSideBySide||args.Length>0) &&
      Environment.GetEnvironmentVariable("RDC_RC1_OWNER_G1_GO")!="YES")
    throw new InvalidOperationException("RC1_EXPLICIT_G1_GO_REQUIRED");
   // Validate the embedded payload and read-only installed-app state
   // before offering an upgrade. Only the absence of both registration and
   // primary shortcut is a fresh Owner Pilot install. Actual shortcut
   // publication still fails closed for unknown or changed link targets.
   string source=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
   if(manualUpgrade){extracted=ExtractEmbeddedCandidate();source=extracted;}
   ValidateSource(source);
   string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
   if(String.IsNullOrEmpty(local))throw new InvalidOperationException("RC1_NO_APPDATA");
   if(manualUpgrade){
    maintenanceLease=RdcV16IntegratedMaintenance.Acquire(local);
    using(var recoveryLease=new RdcReleaseLegacyMigrationLease(Path.Combine(local,"RemoteDesktopCommanderLauncher"))){RdcV16IntegratedMaintenance.RecoverActivation(local);}
    string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    // Read-only ARP verification complements the Owner Pilot shortcut check.
    // Neither this probe nor the confirmation mutates the live stable app.
    RdcV16IntegratedMaintenance.AssertNoDowngrade(local,source);
    bool registered=HasRegisteredStableInstallation(local);
    bool priorShortcut=HasPrimaryDesktopShortcut(desktop);
    bool english=NodeEnglish(registered||priorShortcut);
#if RDC_RC1_FULL_SETUP
    // Missing Desktop link alone is not evidence of a new user. Preserve
    // all prior pilot preferences/Windows Startup choices on repair.
    string priorPilotRoot=Path.Combine(local,"RDCRelayOwnerPilot");
    PathSafe(priorPilotRoot);
    bool freshDefaults=args.Length==0&&!registered&&!priorShortcut&&
     !Directory.Exists(priorPilotRoot)&&!File.Exists(priorPilotRoot);
#endif
    if(args.Length==0 && (registered||priorShortcut)){
     string version=ValidatedCandidateDisplayVersion(source);
     var answer=System.Windows.Forms.MessageBox.Show(
      english?"Install RDC Relay "+version+" as the primary application?":"Установить RDC Relay "+version+" как основную оболочку?",
      english?"RDC Relay "+version+" - manual update":"RDC Relay "+version+" — ручное обновление",
      System.Windows.Forms.MessageBoxButtons.YesNo,
      System.Windows.Forms.MessageBoxIcon.Warning,
      System.Windows.Forms.MessageBoxDefaultButton.Button2);
     if(answer!=System.Windows.Forms.DialogResult.Yes)return 1;
    }
    // Interactive Setup owns prerequisite consent. Scripted pilot and
    // nonactivating staging keep their pre-existing no-install contract.
    if(registered){legacyLease=new RdcReleaseLegacyMigrationLease(Path.Combine(local,"RemoteDesktopCommanderLauncher")); if(!HasRegisteredStableInstallation(local))throw new IOException("RDC_V16_PREDECESSOR_CHANGED");}
    if(args.Length==0 && !EnsureNodePrerequisite(registered||priorShortcut))return 1;
    string release=RdcRc1ManualUpgrade.Prepare(source,local,Required);
    string result=RdcRc1ManualUpgrade.ActivateDesktop(release,local,desktop);
    if(legacyLease!=null){legacyLease.Dispose();legacyLease=null;}
    Console.WriteLine("RC1_MANUAL_RELEASE="+release);
    Console.WriteLine("RC1_MANUAL_PRIMARY_SHORTCUT="+result);
    Console.WriteLine("RC1_MANUAL_REMOTE_NOT_TOUCHED=TRUE");
    // Only a known legacy stable->RC1 transition (or first install) permits
    // eager Host/GUI launch. A prior RC1 may have a running Host from another
    // release root; do not create a second Host without a verified handoff.
    // Exact previous RC1 Host mutex was locked through the shortcut handoff.
    // Launch is safe for a fully stopped predecessor as well as stable->RC1.
    bool deferredOldHost=result=="SWITCHED_RC1_DEFERRED_OLD_HOST";
    bool autoOpen=result=="CREATED"||result=="SWITCHED_STABLE"||result=="SWITCHED_RC1"||result=="ALREADY_ACTIVE";
    if(deferredOldHost){
     Console.WriteLine("RC1_MANUAL_UPGRADE_STAGED_OLD_HOST_IDLE");
     // This is actionable: the old Host still owns its UI/mutex even though
     // no Remote was detected. Never try to spawn a second Host in Setup.
     if(args.Length==0)System.Windows.Forms.MessageBox.Show(
      english?
       "The new version is installed. Exit the previous RDC Relay from the tray, then open RDC Relay from the desktop. Setup did not stop any processes.":
       "Новая версия установлена. Завершите прежний RDC Relay через меню трея, затем откройте RDC Relay с рабочего стола. Установщик не останавливал процессы.",
      english?"RDC Relay 1.6.0 - action required":"RDC Relay 1.6.0 — требуется действие",
      System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
    }
    bool launchFailed=false;
    string launchCode="";
#if RDC_RC1_FULL_SETUP
    if(result=="SWITCHED_STABLE"||result=="CREATED")RdcOwnerAutoConnectPreference.InitializeDisabled(RdcOwnerAutoConnectPreference.CurrentPath);
    if(freshDefaults&&result=="CREATED"){
     try{
      // Explicitly opt out of Remote pairing before any GUI starts.
      // An existing preference is never overwritten by initialization.
      RdcOwnerAutoConnectPreference.InitializeDisabled(RdcOwnerAutoConnectPreference.CurrentPath);
      RdcOwnerStartup.InitializeFreshInstalled(Path.Combine(release,"Source"));
      Console.WriteLine("RC1_FRESH_STARTUP_DEFAULTS_INITIALIZED");
     }catch(Exception defaultError){
      // Activation already committed. Report this as an incomplete launch,
      // rather than starting a Host with an unverified fresh configuration.
      launchFailed=true;autoOpen=false;
      launchCode="RC1_FRESH_STARTUP_DEFAULTS_FAILED";
      Console.Error.WriteLine(launchCode+":"+defaultError.GetType().Name);
     }
    }
#endif
    if(autoOpen){
     try{
      StartPrivateFull(release);
      Console.WriteLine("RC1_AUTOLAUNCH_LAUNCHER_EXIT_ZERO");
     }catch(Exception launchError){
      launchFailed=true;
      string detail=launchError.Message??"";
      launchCode=System.Text.RegularExpressions.Regex.IsMatch(detail,@"^RC1_[A-Z0-9_]{3,100}$")?
       detail:launchError.GetType().Name;
      Console.Error.WriteLine("RC1_AUTOLAUNCH_FAILED:"+launchCode);
     }
    }else Console.WriteLine("RC1_AUTOLAUNCH_DEFERRED_OLD_RC1_HOST_UNKNOWN");
    // A successful install needs no second informational OK dialog.
    // Reserve UI alerts for an actual failure or an actionable deferred handoff.
    if(args.Length==0 && launchFailed){
     System.Windows.Forms.MessageBox.Show(
      (english?"Installed, but the window could not open.":"Установлено, но окно не открылось.")+
      Environment.NewLine+(english?"Error code: ":"Код ошибки: ")+launchCode+
      Environment.NewLine+(english?"Setup did not stop Remote.":"Remote установщик не останавливал."),
      "RDC Relay 1.6.0",
      System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
    }
    // Exit 44 distinguishes a published install from a failed GUI launch.
    return launchFailed?44:0;
   }
   string root=Path.Combine(local,"RDCRelayOwnerPilot","1.6.0-RC1");
   string app=Path.Combine(root,"app");
   PathSafe(root);PathSafe(app);
   // Never overwrite the installed 1.5.18 nor a previous RC1 candidate.
   if(Directory.Exists(app)||File.Exists(app))throw new InvalidOperationException("RC1_TARGET_EXISTS");
   Directory.CreateDirectory(root);
   string staging=Path.Combine(root,".new-"+Guid.NewGuid().ToString("N"));
   Directory.CreateDirectory(staging);
   bool published=false;
   try{
    foreach(string member in Required){
     string to=Path.Combine(staging,member.Replace('/',Path.DirectorySeparatorChar));
     Directory.CreateDirectory(Path.GetDirectoryName(to));
     File.Copy(Path.Combine(source,member.Replace('/',Path.DirectorySeparatorChar)),to,false);
     if(Hash(to)!=Hash(Path.Combine(source,member.Replace('/',Path.DirectorySeparatorChar))))
      throw new InvalidOperationException("RC1_COPY_HASH_FAIL");
    }
    File.Copy(Path.Combine(source,"owner-source-manifest.json"),Path.Combine(staging,"owner-source-manifest.json"),false);
    PathSafe(app);
    Directory.Move(staging,app);
    published=true;
   }finally{
    // On ambiguous failure NEVER recurse-delete a tree. Leave it recorded
    // for a reviewed cleanup, not uncontrolled removal of foreign files.
    if(!published && Directory.Exists(staging))
     Console.Error.WriteLine("RC1_NOT_CLEAN_STAGING:"+staging);
   }
   Console.WriteLine("RC1_PRIVATE_SIDE_BY_SIDE_STAGED:"+app);
   return 0;
  }catch(Exception e){
   Console.Error.WriteLine("RC1_INSTALL_DENIED:"+e.GetType().Name+":"+e.Message);
   if(args.Length==0)System.Windows.Forms.MessageBox.Show(
    (NodeEnglish(false)?"Could not install RDC Relay 1.6.0.":"Не удалось установить RDC Relay 1.6.0.")+Environment.NewLine+Environment.NewLine+
    e.Message+Environment.NewLine+(NodeEnglish(false)?"Setup did not stop previous versions or Remote.":"Старые версии и Remote не отключались этим Setup."),
    "RDC Relay 1.6.0",System.Windows.Forms.MessageBoxButtons.OK,
    System.Windows.Forms.MessageBoxIcon.Error);
   return 42;
  }finally{
   if(legacyLease!=null)legacyLease.Dispose();
   if(maintenanceLease!=null)maintenanceLease.Dispose();
   if(extracted!=null){
    try{CleanExactExtraction(extracted);}
    catch(Exception cleanup){Console.Error.WriteLine("RC1_SETUP_EXTRACTION_RETAINED:"+extracted+":"+cleanup.GetType().Name);}
   }
  }
#endif
 }
}
