// RDC Relay 1.6.0 RC1 branch-only product Tray Host.
// Executes ONLY with an explicit fake-only boot gate. It never launches or
// adopts Desktop Commander Remote and never calls taskkill or Stop-Process.
// The actual existing remote-window.ps1 supplies the separate GUI renderer.
using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;

public sealed class RdcOwnerRuntime : IDisposable {
 readonly object gate=new object();
 readonly string sourceRoot, guiScript, stateRoot, ticketFile, instance, generation, trialRoot;
 readonly string pipeName, logonSid;
 readonly RdcOwnerTicketStore ticketStore;
 readonly int trialExitSeconds;
 readonly Stopwatch trialClock=new Stopwatch();
 bool trialFailGuiStartOnce=false;
 int trialReopensRemaining=0;
 readonly RdcOwnerRemoteState remoteSupervisor=new RdcOwnerRemoteState();
 bool runRootCreated=false;
 readonly int hostPid, hostSession; readonly long hostBorn;
 readonly Mutex singleton;
 readonly ApplicationContext context=new ApplicationContext();
 readonly NotifyIcon tray=new NotifyIcon();
 readonly System.Windows.Forms.Timer pulse=new System.Windows.Forms.Timer();
 readonly RdcOwnerServer server;
 readonly List<Dictionary<string,object>> events=new List<Dictionary<string,object>>();
 readonly HashSet<string> requestIds=new HashSet<string>(StringComparer.Ordinal);
 readonly Queue<string> requestOrder=new Queue<string>();
 readonly HashSet<int> trialSnapshotClients=new HashSet<int>();
 readonly HashSet<int> trialEventClients=new HashSet<int>();
 Process gui;
 System.Threading.Tasks.Task<string> guiErrorTask;
 int childPid=0,childSession=0,guiStarts=0,guiFailures=0,closeGeneration=0;
 long childBorn=0,sequence=0,lastRequestSequence=0;
 string nonce="",guiState="NONE",lastGuiError="";
 bool disposed=false,guiAuthenticated=false,exitRequested=false;
 readonly string fakeRemoteSession=Guid.NewGuid().ToString("N");
 public string Generation { get {return generation;} }
 public string Status { get {lock(gate){return guiState;}} }
 public string LastGuiError {get{lock(gate){return lastGuiError;}}}
 public RdcOwnerRuntime(string root,bool fakeOnly):this(root,fakeOnly,null,false,0,false){}
 public RdcOwnerRuntime(string root,bool fakeOnly,string isolatedTrialRoot):this(root,fakeOnly,isolatedTrialRoot,false,30,false){}
 public RdcOwnerRuntime(string root,bool fakeOnly,string isolatedTrialRoot,bool failOnce,int exitSeconds,bool reopenOnce):
  this(root,fakeOnly,isolatedTrialRoot,failOnce,exitSeconds,reopenOnce?1:0){}
 public RdcOwnerRuntime(string root,bool fakeOnly,string isolatedTrialRoot,bool failOnce,int exitSeconds,int reopenCount):
  this(root,fakeOnly,isolatedTrialRoot,failOnce,exitSeconds,reopenCount,false){}
 public RdcOwnerRuntime(string root,bool fakeOnly,string isolatedTrialRoot,bool failOnce,int exitSeconds,int reopenCount,bool failConstructorAfterServerStart) {
  if(!fakeOnly)throw new InvalidOperationException("RC1_REMOTE_NOT_AUTHORIZED");
  trialRoot=ValidateTrialRoot(isolatedTrialRoot);
  if(trialRoot==null && (failOnce||exitSeconds!=0||reopenCount!=0||failConstructorAfterServerStart))throw new InvalidOperationException("RC1_TRIAL_OPTIONS_WITHOUT_ROOT");
  if(trialRoot!=null && (exitSeconds<15||exitSeconds>120))throw new InvalidOperationException("RC1_TRIAL_BOUNDED_DURATION");
  if(reopenCount<0||reopenCount>10)throw new InvalidOperationException("RC1_TRIAL_REOPEN_BOUNDS");
  trialExitSeconds=exitSeconds;trialFailGuiStartOnce=failOnce;trialReopensRemaining=reopenCount;
  sourceRoot=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
  guiScript=Path.GetFullPath(Path.Combine(sourceRoot,"remote-window.ps1"));
  if(Path.GetDirectoryName(guiScript)!=sourceRoot || !File.Exists(guiScript) ||
     !File.Exists(Path.Combine(sourceRoot,"RdcOwnerWire.cs")) ||
     !File.Exists(Path.Combine(sourceRoot,"RdcOwnerRuntime.cs")))throw new InvalidOperationException("RC1_SOURCE_ROOT");
  CheckPath(guiScript);
  logonSid=RdcOwnerWire.LogonSid();
  byte[] key=new System.Security.Cryptography.SHA256Managed().ComputeHash(
    Encoding.UTF8.GetBytes(sourceRoot.ToLowerInvariant()+"|"+logonSid));
  string mutexKey=BitConverter.ToString(key).Replace("-","").Substring(0,32);
  bool created=false;
  singleton=new Mutex(true,@"Local\RdcRelayRC1Owner-"+mutexKey,out created);
  if(!created){singleton.Dispose();throw new InvalidOperationException("RC1_HOST_ALREADY_RUNNING_NO_KILL");}
  try{
   instance=Guid.NewGuid().ToString("N");
   generation=Guid.NewGuid().ToString("N");
   pipeName="rdc-rc1-gui-"+instance;
   hostPid=Process.GetCurrentProcess().Id;
   hostBorn=RdcOwnerWire.Born(hostPid);
   hostSession=RdcOwnerWire.Session(hostPid);
   string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
   if(String.IsNullOrEmpty(local))throw new InvalidOperationException("NO_OWNER_LOCALAPPDATA");
   string pilotRoot=trialRoot==null?Path.Combine(local,"RDCRelayOwnerPilot","1.6.0-RC1"):
     Path.Combine(trialRoot,"owner-state");
   CheckParents(pilotRoot);
   stateRoot=Path.Combine(pilotRoot,"run-"+instance);
   if(Directory.Exists(stateRoot) || File.Exists(stateRoot))throw new InvalidOperationException("RUN_COLLISION");
   DirectorySecurity acl=new DirectorySecurity();
   acl.SetAccessRuleProtection(true,false);
   acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(logonSid),
     FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,
     PropagationFlags.None,AccessControlType.Allow));
   Directory.CreateDirectory(pilotRoot);
   Directory.CreateDirectory(stateRoot,acl);
   runRootCreated=true;
   CheckPath(stateRoot);
   ticketStore=new RdcOwnerTicketStore(stateRoot,generation,logonSid);
   ticketFile=ticketStore.PathName;
   server=new RdcOwnerServer(pipeName,Dispatch);
   server.Start();
   if(trialRoot!=null && failConstructorAfterServerStart)
    throw new IOException("RC1_TRIAL_INJECTED_CONSTRUCTOR_FAILURE");
   tray.Icon=SystemIcons.Information; // deliberately not installed v1.5.18 icon
   tray.Text="RDC Relay 1.6 RC1 | FAKE Remote";
   tray.Visible=true;
   var menu=new ContextMenuStrip();
   var open=new ToolStripMenuItem("Открыть RDC Relay");
   open.Click+=(s,e)=>OpenGui();
   var status=new ToolStripMenuItem("Статус: RC1 — Remote не подключён");
   status.Enabled=false;
   var exit=new ToolStripMenuItem("Завершить RDC Relay…");
   exit.Click+=(s,e)=>{
    if(MessageBox.Show("Завершить только данный RC1 Host и его собственный GUI? "+
       "Настоящий Remote в этом режиме никогда не запускается.",
       "RDC Relay 1.6.0 RC1 — только FAKE",
       MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
    lock(gate){
     if(exitRequested)return;
     exitRequested=true;closeGeneration++;Append("host","fake-only graceful exit requested");
    }
   };
   menu.Items.Add(open);menu.Items.Add(status);menu.Items.Add(new ToolStripSeparator());menu.Items.Add(exit);
   tray.ContextMenuStrip=menu;
   tray.DoubleClick+=(s,e)=>OpenGui();
   pulse.Interval=250;
   pulse.Tick+=(s,e)=>{
    lock(gate){
     RefreshGui();
     if(trialRoot!=null){
      if(!exitRequested && trialReopensRemaining>0 && guiStarts>0 && gui==null && guiState=="NONE"){
       trialReopensRemaining--;OpenGui();
      }
      if(!exitRequested && trialClock.Elapsed.TotalSeconds>=trialExitSeconds){
       exitRequested=true;closeGeneration++;Append("host","bounded disposable trial exit requested");
      }
     }
     // GUI is asked via closeGeneration; no process kill or orphan.
     // An unverified ticket/child is NOT a clean full exit.
     if(exitRequested && gui==null && guiState=="NONE")context.ExitThread();
    }
   };
   if(trialRoot!=null)trialClock.Start();
   pulse.Start();
   remoteSupervisor.AddSyntheticLogLine("RDC Relay 1.6 RC1: Remote disabled until owner OS trial approval.");
   Append("host","RC1 fake-only owner startup");
  }catch{
   // Fail-closed unwind of partly created host-owned resources.
   try{pulse.Stop();pulse.Dispose();}catch{}
   try{tray.Visible=false;tray.Dispose();}catch{}
   bool ipcClean=true;
   try{if(server!=null)server.Dispose();}catch{ipcClean=false;}
   bool ownTicketClean=true;
   try{if(ticketStore!=null)ownTicketClean=ticketStore.RevokeOnlyOwned();}catch{ownTicketClean=false;}
   bool cleaned=ownTicketClean && RemoveEmptyOwnedRunRoot();
   try{singleton.ReleaseMutex();}catch{}
   singleton.Dispose();
   if(!cleaned || !ipcClean)throw new InvalidOperationException("RC1_CONSTRUCTOR_NOT_CLEAN_IPC_OR_RUN_ROOT");
   throw;
  }
 }
 static string ValidateTrialRoot(string candidate){
  if(String.IsNullOrEmpty(candidate))return null;
  string full=Path.GetFullPath(candidate).TrimEnd(Path.DirectorySeparatorChar);
  string temp=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
  if(!String.Equals(Path.GetDirectoryName(full),temp,StringComparison.OrdinalIgnoreCase) ||
     !System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(full),@"^RDC-RC1-OS-[a-f0-9]{32}$") ||
     !Directory.Exists(full))throw new InvalidOperationException("RC1_TRIAL_ROOT_BOUNDARY");
  CheckPath(full);
  return full;
 }
 static void CheckParents(string path){
  string cursor=Path.GetFullPath(path);
  while(!String.IsNullOrEmpty(cursor)){
   if(File.Exists(cursor)||Directory.Exists(cursor)){
    if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RC1_REPARSE_PARENT");
   }
   string p=Path.GetDirectoryName(cursor);
   if(String.IsNullOrEmpty(p)||p==cursor)break;
   cursor=p;
  }
 }
 static void CheckPath(string path) {
  CheckParents(path);
 }
 string TicketPayload(){
  return RdcOwnerWire.Json.Serialize(new Dictionary<string,object>{
    {"pipe",pipeName},{"nonce",nonce},{"hostPid",hostPid},{"hostTicks",hostBorn},
    {"hostSession",hostSession},{"hostGeneration",generation},
    {"remoteMode","FAKE_ONLY_RC1"},{"protocol",1}});
 }
 bool RemoveEmptyOwnedRunRoot(){
  if(!runRootCreated)return String.IsNullOrEmpty(stateRoot) || !Directory.Exists(stateRoot);
  try{
   if(String.IsNullOrEmpty(stateRoot) || instance==null ||
      Path.GetFileName(stateRoot)!="run-"+instance)return false;
   CheckPath(stateRoot);
   if(!Directory.Exists(stateRoot))return true;
   if(Directory.GetFileSystemEntries(stateRoot).Length!=0)return false;
   Directory.Delete(stateRoot,false);
   return !Directory.Exists(stateRoot);
  }catch{return false;}
 }
 void Append(string src,string message){
  sequence++;
  if(message==null)message="";
  if(message.Length>120)message=message.Substring(0,120);
  events.Add(new Dictionary<string,object>{{"sequence",sequence},{"source",src},{"text",message}});
  remoteSupervisor.NoteHostEvent(src+": "+message);
  if(events.Count>128)events.RemoveAt(0);
 }
 void RefreshGui(){
  if(gui==null)return;
  try{
   if(!gui.HasExited)return;
  }catch{guiState="UNVERIFIED";Append("gui","identity probe failed");return;}
  if(trialRoot!=null && guiErrorTask!=null){
   try{if(!guiErrorTask.IsCompleted){Console.WriteLine("RC1_TRIAL_GUI_STDERR_PENDING");}
    else {string detail=guiErrorTask.GetAwaiter().GetResult();
    if(!String.IsNullOrWhiteSpace(detail)){
     detail=detail.Replace('\r',' ').Replace('\n',' ');
     Console.WriteLine("RC1_TRIAL_GUI_STDERR="+detail.Substring(0,Math.Min(detail.Length,900)));
    }
    }
   }catch{Console.WriteLine("RC1_TRIAL_GUI_STDERR_UNAVAILABLE");}
  }
  guiErrorTask=null;
  gui.Dispose();gui=null;childPid=0;childBorn=0;childSession=0;guiAuthenticated=false;
  nonce="";lastRequestSequence=0;requestIds.Clear();requestOrder.Clear();
  if(!ticketStore.RevokeOnlyOwned()){
   guiState="UNVERIFIED";Append("gui","ticket ownership unverified; relaunch denied");return;
  }
  guiState="NONE";Append("gui","process exited");
 }
 public void OpenGui(){
  lock(gate){
   if(disposed||exitRequested || guiState=="UNVERIFIED")return;
   RefreshGui();
   if(gui!=null){
    try{
     if(gui.MainWindowHandle!=IntPtr.Zero){
      RdcOwnerActivate.ShowWindow(gui.MainWindowHandle,9);
      RdcOwnerActivate.SetForegroundWindow(gui.MainWindowHandle);
     }
    }catch{}
    return; // no duplicate or no-HWND force stop
   }
   try{
    CheckPath(guiScript);
    CheckPath(stateRoot);
    nonce=Guid.NewGuid().ToString("N");
    string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
      @"WindowsPowerShell\v1.0\powershell.exe");
    // Process-scoped execution policy only; never changes Windows policy or registry.
    string args="-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \""+guiScript+"\" -OwnerGui -OwnerTicketPath \""+ticketFile+"\"";
    if(trialRoot!=null)args+=" -OwnerTrialRoot \""+trialRoot+"\"";
    var info=new ProcessStartInfo(ps,args);
    info.WorkingDirectory=sourceRoot;
    info.UseShellExecute=false;
    info.CreateNoWindow=true;
    if(trialRoot!=null)info.RedirectStandardError=true;
    gui=(Process)ticketStore.CreateThen(TicketPayload(),()=>{
     if(trialRoot!=null && trialFailGuiStartOnce){
      trialFailGuiStartOnce=false;
      throw new IOException("RC1_TRIAL_INJECTED_GUI_START_FAILURE");
     }
     return Process.Start(info);
    });
    if(gui==null)throw new InvalidOperationException("RC1_GUI_START_FAILED");
    if(trialRoot!=null)guiErrorTask=gui.StandardError.ReadToEndAsync();
    childPid=gui.Id;childBorn=gui.StartTime.ToUniversalTime().Ticks;childSession=gui.SessionId;
    guiStarts++;guiState="SPAWNING";guiAuthenticated=false;Append("gui","spawned");
   }catch(Exception startError){
    lastGuiError=startError.GetType().Name+": "+startError.Message;
    if(lastGuiError.Length>180)lastGuiError=lastGuiError.Substring(0,180);
    guiFailures++;guiState="NONE";Append("gui","launch failed");
    if(gui==null){
     childPid=0;childBorn=0;childSession=0;nonce="";
     if(ticketStore!=null){
      bool cleared=!ticketStore.HasOwnedTicket || ticketStore.RevokeOnlyOwned();
      if(!cleared || File.Exists(ticketFile) || Directory.Exists(ticketFile)){
       guiState="UNVERIFIED";Append("gui","ticket ownership unverified; relaunch denied");
      }
     }
    }
    else {guiState="UNVERIFIED";Append("gui","started process identity incomplete");}
    // Fail closed: a potentially running child retains its handle and blocks
    // relaunch; do NOT kill it or clear its record after an identity failure.
   }
  }
 }
 Dictionary<string,object> Snapshot(){
  var observed=remoteSupervisor.Snapshot();
  return new Dictionary<string,object>{
   {"hostPid",hostPid},{"hostGeneration",generation},{"hostTicks",hostBorn},
   {"remoteMode","FAKE_ONLY_RC1"},{"remoteId",remoteSupervisor.SessionId},
   {"remote",observed},{"remoteConnected",false},{"account","DEMO: disabled"},
   {"logTail",observed["tail"]},{"logCursor",observed["logCursor"]},
   {"logStreamEpoch",observed["logStreamEpoch"]},
   {"guiPid",childPid},{"guiState",guiState},{"guiStarts",guiStarts},
   {"guiFailures",guiFailures},{"closeGeneration",closeGeneration},{"lastEventSeq",sequence},
   {"revision",sequence},{"remoteRevision",observed["revision"]},{"isActualRemote",false}
  };
 }
 string Answer(string type,string requestId,object payload){
  return RdcOwnerWire.Json.Serialize(new {type=type,protocol=1,requestId=requestId,payload=payload});
 }
 string Error(string requestId,string code){
  return RdcOwnerWire.Json.Serialize(new {type="ERROR",protocol=1,requestId=requestId,code=code});
 }
 string Dispatch(Dictionary<string,object> request,int osPid,int osSession) {
  lock(gate){
   RefreshGui();
   string requestId=RdcOwnerWire.String(request,"requestId");
   if(String.IsNullOrEmpty(requestId)||requestId.Length>64)return Error("","INVALID_REQUEST_ID");
   string verb=RdcOwnerWire.String(request,"type");
   if(RdcOwnerWire.Number(request,"protocol")!=1)return Error(requestId,"PROTOCOL_MISMATCH");
   if(!String.Equals(RdcOwnerWire.String(request,"hostGeneration"),generation,StringComparison.Ordinal))
    return Error(requestId,"STALE_HOST");
   if(childPid<1||gui==null||osPid!=childPid||osSession!=childSession ||
      RdcOwnerWire.Born(childPid)!=childBorn)
    return Error(requestId,"GUI_OS_IDENTITY");
   if(!String.Equals(RdcOwnerWire.String(request,"nonce"),nonce,StringComparison.Ordinal))
    return Error(requestId,"GUI_NONCE");
   long reqSeq=RdcOwnerWire.Number(request,"requestSequence");
   if(reqSeq<=0||reqSeq<=lastRequestSequence||reqSeq==long.MaxValue ||
      requestIds.Contains(requestId))
    return Error(requestId,"REPLAY");
   lastRequestSequence=reqSeq;requestIds.Add(requestId);requestOrder.Enqueue(requestId);
   while(requestOrder.Count>128)requestIds.Remove(requestOrder.Dequeue());
   if(verb=="HELLO"){
    if(RdcOwnerWire.String(request,"guiBuild")!="1.6.0 RC1")
     return Error(requestId,"INCOMPATIBLE_GUI");
    guiAuthenticated=true;guiState="CONNECTED";Append("gui","authenticated");
    return Answer("WELCOME",requestId,Snapshot());
   }
   if(!guiAuthenticated)return Error(requestId,"HELLO_REQUIRED");
   if(verb=="GET_SNAPSHOT"){
    if(trialRoot!=null)trialSnapshotClients.Add(osPid);
    return Answer("SNAPSHOT",requestId,Snapshot());
   }
   if(verb=="GET_EVENTS"){
    if(trialRoot!=null)trialEventClients.Add(osPid);
    long after=RdcOwnerWire.Number(request,"afterSequence");
    if(after<0||after>sequence)return Error(requestId,"INVALID_CURSOR");
    bool gap=events.Count>0 && after<Convert.ToInt64(events[0]["sequence"])-1;
    var batch=new List<Dictionary<string,object>>();
    if(!gap)foreach(var item in events){
     if(Convert.ToInt64(item["sequence"])>after)batch.Add(item);
     if(batch.Count>=64)break;
    }
    bool more=batch.Count>0 && Convert.ToInt64(batch[batch.Count-1]["sequence"])<sequence;
    return Answer("EVENT_BATCH",requestId,new {
     hostGeneration=generation,lastEventSeq=sequence,gap=gap,moreAvailable=more,
     events=batch});
   }
   if(verb=="DETACH"){
    guiAuthenticated=false;guiState="DETACHED";Append("gui","detached");
    return Answer("ACK",requestId,new {detached=true});
   }
   return Error(requestId,"VERB_DENIED");
  }
 }
 public void Run(){Application.Run(context);}
 public void Dispose(){
  lock(gate){
   if(disposed)return;
   disposed=true;
   pulse.Stop();pulse.Dispose();tray.Visible=false;tray.Dispose();
   bool ipcClean=true,filesClean=false,guiClean=(gui==null);
   try{if(server!=null)server.Dispose();}catch{ipcClean=false;}
   if(gui!=null)gui.Dispose(); // no force kill or unverified child stop
   if(guiClean && ticketStore!=null){
    filesClean=ticketStore.RevokeOnlyOwned() && RemoveEmptyOwnedRunRoot();
   }
   try{singleton.ReleaseMutex();}catch{}
   singleton.Dispose();
   if(trialRoot!=null){
    Console.WriteLine("RC1_TRIAL_IPC_SNAPSHOT_GUI_COUNT="+
     trialSnapshotClients.Count+" EVENT_GUI_COUNT="+trialEventClients.Count);
    Console.WriteLine("RC1_TRIAL_IPC_REJECTED="+server.Rejected+
     " TIMEOUTS="+server.Timeouts+" PEAK_ACTIVE="+server.PeakActive);
   }
   if(!ipcClean || !filesClean || !guiClean)
    throw new InvalidOperationException("RC1_OWNER_SHUTDOWN_NOT_CLEAN");
  }
 }
}
public static class RdcOwnerActivate {
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool ShowWindow(IntPtr h,int command);
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool SetForegroundWindow(IntPtr h);
}
