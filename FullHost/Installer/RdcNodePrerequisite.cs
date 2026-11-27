// Shared Setup / Portable prerequisite workflow. No Remote or Relay installation actions.
using System;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;
internal static class RdcNodePrerequisite {
 // Strict local path observation; inaccessible is not evidence of absence.
 static FileAttributes? Attributes(string path){
  try{return File.GetAttributes(path);}
  catch(FileNotFoundException){return null;}
  catch(DirectoryNotFoundException){return null;}
 }
 static void PathSafe(string path){
  string full=Path.GetFullPath(path),p=full;
  while(!String.IsNullOrEmpty(p)){
   var attrs=Attributes(p);
   if(attrs.HasValue&&(attrs.Value&FileAttributes.ReparsePoint)!=0)
    throw new InvalidOperationException("RC1_REPARSE_REFUSED");
   string parent=Path.GetDirectoryName(p);
   if(String.IsNullOrEmpty(parent)||parent==p)break;p=parent;
  }
 }
 static bool PresentFile(string path){
  PathSafe(path);
  var attrs=Attributes(path);
  if(!attrs.HasValue)return false;
  if((attrs.Value&FileAttributes.Directory)!=0)throw new IOException("RC1_NODE_PATH_NOT_FILE");
  return true;
 }
 static string Hash(string file){
  using(var sha=SHA256.Create())
  using(var input=File.OpenRead(file))
   return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","");
 }
 // Node is an external shared runtime, not a Relay-owned file. Only an
 // interactive, explicitly accepted prerequisite install can change it.
 // The pinned upstream release is the LTS major used by the vendor's
 // Windows launcher. Never run a downloaded script or resolve "latest".
 internal const string NodeMsiUrl="https://nodejs.org/dist/v24.22.3/node-v24.22.3-x64.msi";
 internal const string NodeMsiSha256="4A1AB5BDEC5434BAE58EFAE6C3E5077A011F6F1E76D2B47B7B10AF043F7DB545";
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
  if(roots==null||roots.Length==0)return "UNKNOWN";
  bool foundAny=false;
  try{
   foreach(string root in roots){
    PathSafe(root);
    var attrs=Attributes(root);
    if(attrs.HasValue&&(attrs.Value&FileAttributes.Directory)==0)return "EXISTING_UNSUPPORTED";
    string shim=Path.Combine(root,"npx.cmd"),node=Path.Combine(root,"node.exe"),npm=Path.Combine(root,"npm.cmd");
    string cli=Path.Combine(root,"node_modules","npm","bin","npx-cli.js");
    string npmCli=Path.Combine(root,"node_modules","npm","bin","npm-cli.js");
    bool hasShim=PresentFile(shim),hasNode=PresentFile(node),hasNpm=PresentFile(npm);
    bool hasCli=PresentFile(cli),hasNpmCli=PresentFile(npmCli);
    if(hasShim||hasNode||hasNpm||hasCli||hasNpmCli)foundAny=true;
    if(!hasShim)continue;
    if(!hasNode||!hasNpm||!hasCli||!hasNpmCli)return "INCOMPLETE";
    var version=FileVersionInfo.GetVersionInfo(node);
    return SupportedNodeVersion(version.FileMajorPart,version.FileMinorPart)?"READY":"EXISTING_UNSUPPORTED";
   }
   return foundAny?"INCOMPLETE":"MISSING";
  }catch{return "UNKNOWN";}
 }
 static bool OtherNodeOnPath(){
  foreach(string entry in (Environment.GetEnvironmentVariable("PATH")??"").Split(';')){
   string dir=entry.Trim().Trim('"');
   // Never consult a relative/network PATH entry or execute PATH programs.
   if(dir.Length<3||dir[1]!=':'||dir[2]!='\\')continue;
   try{
    if(new DriveInfo(Path.GetPathRoot(dir)).DriveType!=DriveType.Fixed)continue;
    if(PresentFile(Path.Combine(dir,"node.exe"))||
       PresentFile(Path.Combine(dir,"npm.cmd"))||
       PresentFile(Path.Combine(dir,"npx.cmd")))return true;
   }catch{return true;}
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
   try{task.GetAwaiter().GetResult();}
   catch{if(cancel.IsCancellationRequested)throw new OperationCanceledException("RC1_NODE_DOWNLOAD_CANCELLED");throw;}
   if(cancel.IsCancellationRequested)throw new OperationCanceledException("RC1_NODE_DOWNLOAD_CANCELLED");
  }
 }
 internal static bool EnsureNodePrerequisite(bool existing,bool portable){
  using(var mutex=new System.Threading.Mutex(false,@"Local\RdcRelayNodePrerequisite-v1")){
   bool held=false;
   try{try{held=mutex.WaitOne(0);}catch(System.Threading.AbandonedMutexException){held=true;}
    if(!held)throw new InvalidOperationException("RC1_NODE_INSTALL_ALREADY_PENDING");
    return EnsureCore(existing,portable);
   }finally{if(held)mutex.ReleaseMutex();}
  }
 }
 [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
 struct SystemInfo {
  public ushort Architecture,Reserved;
  public uint PageSize;
  public IntPtr MinAddress,MaxAddress,ProcessorMask;
  public uint ProcessorCount,ProcessorType,AllocationGranularity;
  public ushort ProcessorLevel,ProcessorRevision;
 }
 [System.Runtime.InteropServices.DllImport("kernel32.dll")]
 static extern void GetNativeSystemInfo(out SystemInfo info);
 internal static bool NativeX64(){
  try{SystemInfo info;GetNativeSystemInfo(out info);return Environment.Is64BitOperatingSystem&&info.Architecture==9;}
  catch{return false;}
 }
 static bool EnsureCore(bool existing,bool portable){
  string[] roots=NodeRuntimeRoots();
  string state=ClassifyNodePrerequisite(roots);
  if(state=="READY")return true;
  bool en=NodeEnglish(existing);
  if(state=="UNKNOWN"){
   System.Windows.Forms.MessageBox.Show(en?
    "Node.js prerequisites could not be verified safely. Check access and the installation, then reopen RDC Relay. Nothing was installed.":
    "Не удалось безопасно проверить зависимости Node.js. Проверьте доступ и установку, затем повторите запуск RDC Relay. Установка не выполнялась.",
    "RDC Relay",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
   return false;
  }
  bool detectedElsewhere=false;
  if(state=="MISSING")detectedElsewhere=OtherNodeOnPath()||OtherNodeRegistered();
  if(state!="MISSING"||detectedElsewhere){
   System.Windows.Forms.MessageBox.Show(en?
    (state=="INCOMPLETE"?"Node.js installation is incomplete.":state=="EXISTING_UNSUPPORTED"?"Node.js installation is unsupported.":"Another Node.js installation may exist outside the supported locations.")+
     "\n\nRepair or install Node.js 22.12 or newer with npm/npx in a supported location, then reopen RDC Relay. RDC Relay will not replace a shared runtime automatically.":
    (state=="INCOMPLETE"?"Установка Node.js неполная.":state=="EXISTING_UNSUPPORTED"?"Обнаружена неподдерживаемая установка Node.js.":"Возможно, Node.js установлен вне поддерживаемых каталогов.")+
     "\n\nВосстановите или установите Node.js 22.12 или новее с npm/npx в поддерживаемом каталоге, затем снова откройте RDC Relay. Общая среда автоматически не заменяется.",
    "RDC Relay",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
   return false;
  }
  if(!NativeX64()){
   System.Windows.Forms.MessageBox.Show(en?
    "Automatic Node.js installation is available for x64 Windows only. Install a supported Node.js with npm/npx and reopen RDC Relay.":
    "Автоматическая установка Node.js пока доступна только для Windows x64. Установите поддерживаемый Node.js с npm/npx и повторите запуск RDC Relay.",
    "RDC Relay",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Warning);
   return false;
  }
  var answer=System.Windows.Forms.MessageBox.Show((portable?(en?"Portable needs a shared system runtime; this does not install RDC Relay.\n\n":"Portable требуется общая системная среда; RDC Relay при этом не устанавливается.\n\n"):"")+(en?
   "Desktop Commander Remote requires Node.js and npm/npx. Download and install the official Node.js 24 LTS runtime now? Windows may request administrator approval.":
   "Desktop Commander Remote требует Node.js и npm/npx. Скачать и установить официальный Node.js 24 LTS? Windows может запросить разрешение администратора."),
   "RDC Relay",System.Windows.Forms.MessageBoxButtons.YesNo,
   System.Windows.Forms.MessageBoxIcon.Question,System.Windows.Forms.MessageBoxDefaultButton.Button2);
  if(answer!=System.Windows.Forms.DialogResult.Yes)return false;
  string temp=Path.Combine(Path.GetTempPath(),"RDC-NodePrerequisite-"+Guid.NewGuid().ToString("N"));
  PathSafe(temp);
  if(Attributes(temp).HasValue)throw new InvalidOperationException("RC1_NODE_TEMP_COLLISION");
  Directory.CreateDirectory(temp);
  string msi=Path.Combine(temp,"node-v24.22.3-x64.msi");
  try{
   Console.WriteLine("RC1_NODE_DOWNLOAD_START");
   try{DownloadPinnedNodeWithProgress(msi,en);}
   catch(OperationCanceledException){Console.WriteLine("RC1_NODE_DOWNLOAD_CANCELLED");return false;}
   // Recheck after the download, before asking Windows Installer to run.
   state=ClassifyNodePrerequisite(roots);
   if(state=="READY")return true;
   if(state!="MISSING"||OtherNodeOnPath()||OtherNodeRegistered())throw new InvalidOperationException("RC1_NODE_STATE_CHANGED");
   PathSafe(msi);
   if(Hash(msi)!=NodeMsiSha256)throw new InvalidOperationException("RC1_NODE_MSI_HASH_MISMATCH");
   string msiexec=Path.Combine(Environment.SystemDirectory,"msiexec.exe");
   PathSafe(msiexec);
   var start=new ProcessStartInfo(msiexec,"/i \""+msi+"\" /passive /norestart");
   start.UseShellExecute=true;start.Verb="runas";start.WorkingDirectory=temp;
   Console.WriteLine("RC1_NODE_INSTALL_START");
   try{
    using(Process child=Process.Start(start)){
     if(child==null)throw new InvalidOperationException("RC1_NODE_MSI_NOT_STARTED");
     child.WaitForExit();
     Console.WriteLine("RC1_NODE_MSI_EXIT="+child.ExitCode);
     if(child.ExitCode==1602)return false; // user cancelled Windows Installer
     if(child.ExitCode==3010){
      System.Windows.Forms.MessageBox.Show(en?
       "Node.js requires a Windows restart. Restart Windows and reopen RDC Relay.":
       "Для завершения установки Node.js требуется перезагрузка Windows. Перезагрузите Windows и снова откройте RDC Relay.",
       "RDC Relay",System.Windows.Forms.MessageBoxButtons.OK,System.Windows.Forms.MessageBoxIcon.Information);
      return false;
     }
     if(child.ExitCode!=0)throw new InvalidOperationException("RC1_NODE_MSI_FAILED_"+child.ExitCode);
    }
   }catch(System.ComponentModel.Win32Exception denied){
    if(denied.NativeErrorCode==1223){Console.WriteLine("RC1_NODE_UAC_CANCELLED");return false;}
    throw;
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
}
