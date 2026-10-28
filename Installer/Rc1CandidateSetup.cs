// Private RDC Relay 1.6.0 RC1 Setup. The repository's blocked-marker
// compiler path stays inert; only an exact-manifest owner-pilot package
// embeds the read-only payload for standalone user-confirmed manual upgrades.
// No Setup path is permitted to control the existing Desktop Commander Remote.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Reflection;
using System.Diagnostics;
using System.Web.Script.Serialization;

internal static class RdcRc1CandidateSetup {
 static readonly string[] Required=new string[]{
  "Source/remote-window.ps1","Source/rc1-tray-host.ps1","Source/rc1-owner-gui.ps1",
  "Source/rc1-remote-observer.ps1",
  "Source/RdcOwnerWire.cs","Source/RdcOwnerRuntime.cs","Source/RdcOwnerProcess.cs",
  "Source/RdcOwnerTicketStore.cs","Source/RdcOwnerRemoteState.cs",
  "Source/RdcOwnerManagedProcess.cs",
  "Source/rc1-candidate.json","Source/RDCRelay.ico",
  "Source/divider-caustic.ps","Source/divider-caustic-detail.ps",
  "Source/divider-particles.ps","Source/divider-particles-core.ps",
  "Source/update-notice.ps1","Source/update.ps1","RdcOwnerRuntime.dll",
  "RC1 Pilot Launcher.exe"
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
 static void ValidateSource(string root){
  PathSafe(root);
  if(!File.Exists(Path.Combine(root,"owner-source-manifest.json")))
   throw new InvalidOperationException("RC1_MANIFEST_ABSENT");
  var manifest=ReadJson(Path.Combine(root,"owner-source-manifest.json"));
  if((string)manifest["candidate"]!="1.6.0 RC1")throw new InvalidOperationException("RC1_BAD_CANDIDATE");
  var candidate=ReadJson(Path.Combine(root,"Source","rc1-candidate.json"));
  // The repository Source marker stays blocked; only a newly staged, hashed
  // owner-pilot payload explicitly enables the read-only observation mode.
  if(!Convert.ToBoolean(candidate["installable"]) ||
     !Convert.ToBoolean(candidate["liveRemoteEnabled"]) ||
     Convert.ToBoolean(candidate["publishable"]) ||
     Convert.ToBoolean(candidate["autoUpdateEnabled"]) ||
     (string)candidate["ownerMode"]!="FULL_HOST_GUI_RC1")
   throw new InvalidOperationException("RC1_NOT_ISOLATED_FULL_CANDIDATE");
  var listed=new List<string>();
  var rows=(System.Collections.ArrayList)manifest["files"];
  foreach(Dictionary<string,object> item in rows)
    listed.Add((string)item["name"]);
  if(listed.Count!=Required.Length || listed.Count!=listed.Distinct(StringComparer.Ordinal).Count())
   throw new InvalidOperationException("RC1_MANIFEST_NOT_EXACT_UNIQUE_SET");
  foreach(string required in Required){
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
 static void StartPrivateFull(string release){
  // Open only our pinned read-only GUI launcher. The launcher returns after
  // spawning the private Host; never wait for or signal persistent descendants.
  string launcher=Path.Combine(release,"RC1 Pilot Launcher.exe");
  PathSafe(launcher);
  if(!File.Exists(launcher))throw new InvalidOperationException("RC1_AUTOLAUNCH_MISSING");
  var start=new ProcessStartInfo(launcher,"--full");
  start.UseShellExecute=false;
  start.CreateNoWindow=true;
  start.WorkingDirectory=release;
  using(Process child=Process.Start(start)){
   if(child==null)throw new InvalidOperationException("RC1_AUTOLAUNCH_START_REFUSED");
   if(!child.WaitForExit(18000))throw new InvalidOperationException("RC1_AUTOLAUNCH_TIMEOUT");
   if(child.ExitCode!=0)throw new InvalidOperationException("RC1_AUTOLAUNCH_LAUNCHER_FAILED");
  }
 }
 static int Main(string[] args){
#if RDC_RC1_BLOCKED
  // Build and inspect only; this file intentionally cannot install today.
  Console.Error.WriteLine("RC1_OWNER_SETUP_BLOCKED_NEEDS_OS_TRIAL_AND_G1_GO");
  return 42;
#else
  string extracted=null;
  try{
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
   // A user launching downloaded Setup.exe by double click opts in through
   // a visible RC1-specific prompt. Never silently switch the daily shortcut.
   if(manualUpgrade&&args.Length==0){
    var answer=System.Windows.Forms.MessageBox.Show(
     "Установить RDC Relay 1.6.0 RC1 как основную оболочку?" + Environment.NewLine + Environment.NewLine +
     "Старые файлы будут сохранены. Существующий Remote не будет прерван. "+
     "При существующей сессии действует режим Adopted (без управления); "+
     "новый Remote, созданный Host, поддерживает запуск, остановку и переподключение. "+
     "Смена аккаунта пока недоступна.",
     "RDC Relay 1.6.0 RC1 — ручное обновление",
     System.Windows.Forms.MessageBoxButtons.YesNo,System.Windows.Forms.MessageBoxIcon.Warning);
    if(answer!=System.Windows.Forms.DialogResult.Yes)return 1;
   }
   string source=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
   if(manualUpgrade){extracted=ExtractEmbeddedCandidate();source=extracted;}
   ValidateSource(source);
   string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
   if(String.IsNullOrEmpty(local))throw new InvalidOperationException("RC1_NO_APPDATA");
   if(manualUpgrade){
    string release=RdcRc1ManualUpgrade.Prepare(source,local,Required);
    string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    string result=RdcRc1ManualUpgrade.ActivateDesktop(release,local,desktop);
    Console.WriteLine("RC1_MANUAL_RELEASE="+release);
    Console.WriteLine("RC1_MANUAL_PRIMARY_SHORTCUT="+result);
    Console.WriteLine("RC1_MANUAL_REMOTE_NOT_TOUCHED=TRUE");
    // Only a known legacy stable->RC1 transition (or first install) permits
    // eager Host/GUI launch. A prior RC1 may have a running Host from another
    // release root; do not create a second Host without a verified handoff.
    // Exact previous RC1 Host mutex was locked through the shortcut handoff.
    // Launch is safe for a fully stopped predecessor as well as stable->RC1.
    bool autoOpen=result=="CREATED"||result=="SWITCHED_STABLE"||result=="SWITCHED_RC1"||result=="ALREADY_ACTIVE";
    bool launchFailed=false;
    if(autoOpen){
     try{
      StartPrivateFull(release);
      Console.WriteLine("RC1_AUTOLAUNCH_LAUNCHER_EXIT_ZERO");
     }catch(Exception launchError){
      launchFailed=true;
      Console.Error.WriteLine("RC1_AUTOLAUNCH_FAILED:"+launchError.GetType().Name);
     }
    }else Console.WriteLine("RC1_AUTOLAUNCH_DEFERRED_OLD_RC1_HOST_UNKNOWN");
    if(args.Length==0){
     string notice=launchFailed?
      "Новые файлы и основной ярлык подготовлены, но автоматический запуск не удался."+
      Environment.NewLine+"Попробуйте ярлык RDC Relay. Если окно не появится, сообщите об ошибке.":
      (autoOpen?
       "Новая оболочка RDC Relay 1.6.0 RC1 запускается. Если окно не появилось, используйте основной ярлык.":
       "Новая RC1 подготовлена. Автоматический запуск отложен: прежний RC1 Host может ещё работать."+
       Environment.NewLine+"Штатно завершите прежний RC1 Host перед запуском нового ярлыка.");
     System.Windows.Forms.MessageBox.Show(
      notice+Environment.NewLine+Environment.NewLine+
      "Настоящий Remote не остановлен. Не закрывайте старую v1.5.18 через X ради установки.",
      "RDC Relay 1.6.0 RC1",
      System.Windows.Forms.MessageBoxButtons.OK,
      launchFailed?System.Windows.Forms.MessageBoxIcon.Warning:System.Windows.Forms.MessageBoxIcon.Information);
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
    "Не удалось установить RDC Relay 1.6.0 RC1."+Environment.NewLine+Environment.NewLine+
    e.Message+Environment.NewLine+"Старые версии и Remote не отключались этим Setup.",
    "RDC Relay 1.6.0 RC1",System.Windows.Forms.MessageBoxButtons.OK,
    System.Windows.Forms.MessageBoxIcon.Error);
   return 42;
  }finally{
   if(extracted!=null){
    try{CleanExactExtraction(extracted);}
    catch(Exception cleanup){Console.Error.WriteLine("RC1_SETUP_EXTRACTION_RETAINED:"+extracted+":"+cleanup.GetType().Name);}
   }
  }
#endif
 }
}
