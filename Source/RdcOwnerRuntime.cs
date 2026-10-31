// RDC Relay 1.6.0 RC1 branch-only product Tray Host.
// Host can observe existing Remote read-only or start a NEW managed Remote
// inside its own kernel Job. Never adopts stop rights for preexisting Remote.
// The complete original remote-window.ps1 is the replaceable GUI renderer.
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
using System.Management;

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
 bool observedMode=false,managedMode=false,reopenAfterModeChange=false,autoStartPending=false;
 DateTime nextAutoStartUtc=DateTime.MinValue;
 RdcOwnerManagedProcess managedProcess=null;
 readonly List<string> managedLogs=new List<string>();
 string managedLogPath="",managedLogFragment="",managedState="Disconnected",managedDetail="";
 string managedAccount="",managedDeviceName="",managedDeviceId="";
 long managedBornUtcTicks=0;
 readonly List<string> managedBannerArt=new List<string>();
 readonly List<string> managedStartupHeader=new List<string>();
 bool managedStartupComplete=false;
 int managedStartupScanned=0;
 int managedBannerScanned=0;
 long managedLogOffset=0;
 ToolStripMenuItem trayStatusItem,trayExitItem;
 bool runRootCreated=false;
 readonly int hostPid, hostSession; readonly long hostBorn;
 readonly Mutex singleton;
 readonly EventWaitHandle reopenSignal;
 readonly EventWaitHandle idleUpgradeSignal;
 readonly EventWaitHandle guiReadySignal;
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
   // Only same-logon local callers can ask this Host to reopen its GUI.
   // This event has no Remote/action authority and is scoped to this release.
   var eventAcl=new EventWaitHandleSecurity();
   eventAcl.SetAccessRuleProtection(true,false);
   eventAcl.AddAccessRule(new EventWaitHandleAccessRule(new SecurityIdentifier(logonSid),
     EventWaitHandleRights.FullControl,AccessControlType.Allow));
   byte[] activationHash=new System.Security.Cryptography.SHA256Managed().ComputeHash(
     Encoding.UTF8.GetBytes(sourceRoot.ToLowerInvariant()));
   string activationName=@"Local\RdcRelayRC1Open-"+BitConverter.ToString(activationHash).Replace("-","").Substring(0,32);
   bool eventCreated;
   reopenSignal=new EventWaitHandle(false,EventResetMode.AutoReset,activationName,out eventCreated,eventAcl);
   idleUpgradeSignal=new EventWaitHandle(false,EventResetMode.AutoReset,
     @"Local\RdcRelayRC1IdleUpgrade-"+mutexKey,out eventCreated,eventAcl);
   string readyName=@"Local\RdcRelayRC1GuiReady-"+BitConverter.ToString(activationHash).Replace("-","").Substring(0,32);
   guiReadySignal=new EventWaitHandle(false,EventResetMode.ManualReset,readyName,out eventCreated,eventAcl);
   guiReadySignal.Reset();
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
   trayStatusItem=new ToolStripMenuItem("Статус: RC1 — Remote не подключён");
   trayStatusItem.Enabled=false;
   trayExitItem=new ToolStripMenuItem("Завершить RDC Relay…");
   trayExitItem.Click+=(s,e)=>{
    string question=observedMode?
     "Закрыть только RC1 Host и его GUI? Существующий Desktop Commander Remote продолжит работу.":
     managedMode?
     "Полностью завершить RDC Relay? Только Remote, запущенный этим Host, будет остановлен; чужие процессы не затрагиваются.":
     "Завершить только тестовый RC1 Host и его собственный GUI?";
    if(MessageBox.Show(question,
       "RDC Relay 1.6.0 RC1",MessageBoxButtons.YesNo,
       MessageBoxIcon.Question)!=DialogResult.Yes)return;
    lock(gate){
     if(exitRequested)return;
     if(managedMode && managedProcess!=null && managedProcess.Running){
      try{
       if(!managedProcess.StopOwnedOnly(10000)){
        MessageBox.Show("Remote ещё работает; полное завершение заблокировано.","RDC Relay",MessageBoxButtons.OK,MessageBoxIcon.Warning);
        return;
       }
       remoteSupervisor.ManagedStatus(0,false,"Disconnected","Host-owned Remote exited");
      }catch(Exception error){
       MessageBox.Show("Невозможно безопасно остановить управляемый Remote: "+error.GetType().Name,
        "RDC Relay",MessageBoxButtons.OK,MessageBoxIcon.Error);
       return;
      }
     }
     exitRequested=true;closeGeneration++;
     Append("host",observedMode?"observer detach requested":managedMode?"managed full exit requested":"fake-only graceful exit requested");
    }
   };
   menu.Items.Add(open);menu.Items.Add(trayStatusItem);menu.Items.Add(new ToolStripSeparator());menu.Items.Add(trayExitItem);
   tray.ContextMenuStrip=menu;
   tray.DoubleClick+=(s,e)=>OpenGui();
   pulse.Interval=250;
   pulse.Tick+=(s,e)=>{
    lock(gate){
     RefreshGui();
     // Cooperative same-logon Setup handoff. The Host itself authorizes its
     // idle exit, never accepting PID/name-based termination from Setup.
     if(idleUpgradeSignal!=null && idleUpgradeSignal.WaitOne(0) && !exitRequested){
      try{
       if(managedMode && !observedMode &&
          (managedProcess==null || !managedProcess.Running) &&
          !AnotherDesktopCommanderRemote() && !AnotherLegacyShell()){
        autoStartPending=false;exitRequested=true;closeGeneration++;
        Append("host","verified idle Host accepted cooperative RC1 upgrade");
       }else Append("host","idle upgrade refused: Remote or legacy shell active");
      }catch{Append("host","idle upgrade refused: OS identity scan unavailable");}
     }
     if(reopenAfterModeChange && gui==null && guiState=="NONE" && !exitRequested){
      reopenAfterModeChange=false;OpenGui();
     }
     if(managedMode){
      RefreshManagedRemote();
      if(autoStartPending && guiAuthenticated && guiState=="CONNECTED" &&
       !reopenAfterModeChange && DateTime.UtcNow>=nextAutoStartUtc)
       TryAutoStartManagedRemote();
     }
     if(reopenSignal!=null && reopenSignal.WaitOne(0) && !exitRequested){
      Append("host","verified local GUI activation requested");
      OpenGui();
     }
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
   try{if(reopenSignal!=null)reopenSignal.Dispose();}catch{}
   try{if(idleUpgradeSignal!=null)idleUpgradeSignal.Dispose();}catch{}
   try{if(guiReadySignal!=null)guiReadySignal.Dispose();}catch{}
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
    {"remoteMode",observedMode?"OBSERVED_READ_ONLY_RC1":managedMode?"MANAGED_OWNER_RC1":"FAKE_ONLY_RC1"},{"protocol",1}});
 }
 bool RemoveOwnedManagedLogs(){
  if(!managedMode)return true;
  if(managedProcess!=null && managedProcess.Running)return false;
  foreach(string path in managedLogs){
   try{
    if(Path.GetDirectoryName(path)!=stateRoot ||
       !System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(path),
        @"^remote-[0-9a-f]{32}\.log$",System.Text.RegularExpressions.RegexOptions.CultureInvariant))
     return false;
    CheckPath(path);
    if(File.Exists(path))File.Delete(path);
   }catch{return false;}
  }
  return true;
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
  if((trialRoot!=null || observedMode || managedMode) && guiErrorTask!=null){
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
  if(guiReadySignal!=null)guiReadySignal.Reset();
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
    if(guiReadySignal!=null)guiReadySignal.Reset();
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
    if(trialRoot!=null || observedMode || managedMode)info.RedirectStandardError=true;
    gui=(Process)ticketStore.CreateThen(TicketPayload(),()=>{
     if(trialRoot!=null && trialFailGuiStartOnce){
      trialFailGuiStartOnce=false;
      throw new IOException("RC1_TRIAL_INJECTED_GUI_START_FAILURE");
     }
     return Process.Start(info);
    });
    if(gui==null)throw new InvalidOperationException("RC1_GUI_START_FAILED");
    if(trialRoot!=null || observedMode || managedMode)guiErrorTask=gui.StandardError.ReadToEndAsync();
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
 // Product mode: actions are available ONLY for a newly spawned process
 // in the private kernel Job of this exact Host. Legacy Remote remains Adopted.
 public void EnableManagedRemote(){
  lock(gate){
   if(disposed||trialRoot!=null||observedMode||managedMode||gui!=null)
    throw new InvalidOperationException("RC1_MANAGED_MODE_BOUNDARY");
   managedMode=true;remoteSupervisor.EnableManaged();
   autoStartPending=true;nextAutoStartUtc=DateTime.MinValue;
   tray.Text="RDC Relay 1.6.0 RC1 | Host";
   trayStatusItem.Text="Remote: готов к управляемому запуску";
   Append("remote","managed ownership mode enabled");
  }
 }
 // Automatic launch is one-shot at full Host boot or after a verified
 // transition away from an EXTERNAL Remote; failure preserves the GUI.
 public bool TryAutoStartManagedRemote(){
  lock(gate){
   if(disposed||exitRequested||observedMode||!managedMode||
      !guiAuthenticated||guiState!="CONNECTED"||reopenAfterModeChange)return false;
   if(managedProcess!=null&&managedProcess.Running){autoStartPending=false;return true;}
   try{StartManagedRemote();autoStartPending=false;return true;}
   catch(Exception problem){
    string code=problem.Message??"";
    bool external=(code=="RC1_EXISTING_REMOTE_ADOPTED_NO_DUPLICATE"||
      code=="RC1_LEGACY_GUI_STILL_ACTIVE"||code=="RC1_EXTERNAL_REMOTE_SCAN_UNAVAILABLE"||
      code=="RC1_LEGACY_SHELL_SCAN_UNAVAILABLE");
    // Only a verified external blocker may be retried after a bounded delay.
    // A genuine launch failure remains visible until an explicit user retry.
    autoStartPending=external;
    nextAutoStartUtc=DateTime.UtcNow.AddSeconds(5);
    string reason=external?
     "Waiting for the previous Remote and shell to exit; no duplicate launched":
     "Remote startup failed; inspect Host status and retry manually";
    remoteSupervisor.ManagedStatus(0,false,external?"Disconnected":"Fault",reason);
    Append("remote","automatic start refused: "+problem.GetType().Name);
    return false;
   }
  }
 }
 // A missing observer PID is insufficient for promotion. Check BOTH any
 // genuine Remote launcher AND any other original GUI: either could restart
 // Remote. Unknown WMI state is fail-closed and keeps Adopted read-only.
 public bool CanPromoteObservedRemote(){
  lock(gate){
   if(disposed||!observedMode||managedMode||trialRoot!=null||exitRequested)return false;
   try{return !AnotherDesktopCommanderRemote()&&!AnotherLegacyShell();}
   catch{return false;}
  }
 }
 public bool PromoteObservedRemoteToManaged(){
  lock(gate){
   if(!CanPromoteObservedRemote())return false;
   // Recheck immediately before changing modes; never import old PID.
   if(AnotherDesktopCommanderRemote()||AnotherLegacyShell())return false;
   remoteSupervisor.PromoteObservedToManaged();
   observedMode=false;managedMode=true;reopenAfterModeChange=true;
   autoStartPending=true;nextAutoStartUtc=DateTime.MinValue;
   closeGeneration++; // old read-only GUI must exit before new ticket/GUI
   tray.Text="RDC Relay 1.6.0 RC1 | Host";
   trayStatusItem.Text="Remote: переход к управляемому запуску";
   trayExitItem.Text="Завершить RDC Relay…";
   Append("remote","verified external Remote and GUI gone; new Job-only session permitted");
   return true;
  }
 }
 static string ResolvePinnedNpx(){
  string[] candidates=new string[]{
   Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"nodejs","npx.cmd"),
   Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"npm","npx.cmd"),
   Path.Combine(Environment.GetEnvironmentVariable("ProgramFiles(x86)")??@"C:\Program Files (x86)","nodejs","npx.cmd")
  };
  foreach(string file in candidates){
   CheckPath(file);
   if(File.Exists(file))return file;
  }
  throw new FileNotFoundException("RC1_PINNED_NPX_MISSING");
 }
 bool AnotherLegacyShell(){
  try{
   using(var search=new ManagementObjectSearcher(
    "SELECT CommandLine FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'")){
    using(ManagementObjectCollection rows=search.Get()){
     foreach(ManagementBaseObject row in rows){
      string line=Convert.ToString(row["CommandLine"])??"";
      if(line.IndexOf("remote-window.ps1",StringComparison.OrdinalIgnoreCase)>=0 &&
         line.IndexOf(guiScript,StringComparison.OrdinalIgnoreCase)<0)return true;
     }
    }
   }
   return false;
  }catch{throw new InvalidOperationException("RC1_LEGACY_SHELL_SCAN_UNAVAILABLE");}
 }
 static bool AnotherDesktopCommanderRemote(){
  try{
   using(var search=new ManagementObjectSearcher(
    "SELECT CommandLine FROM Win32_Process WHERE Name='cmd.exe' OR Name='node.exe'")){
    using(ManagementObjectCollection rows=search.Get()){
     foreach(ManagementBaseObject row in rows){
      string line=Convert.ToString(row["CommandLine"])??"";
      if(line.IndexOf("desktop-commander",StringComparison.OrdinalIgnoreCase)>=0 &&
        System.Text.RegularExpressions.Regex.IsMatch(line,@"\bremote\b",
         System.Text.RegularExpressions.RegexOptions.IgnoreCase))return true;
     }
    }
   }
   return false;
  }catch{throw new InvalidOperationException("RC1_EXTERNAL_REMOTE_SCAN_UNAVAILABLE");}
 }
 void StartManagedRemote(){
  if(!managedMode||observedMode||exitRequested)
   throw new InvalidOperationException("RC1_NOT_MANAGED");
  if(managedProcess!=null && managedProcess.Running)
   throw new InvalidOperationException("RC1_OWNED_REMOTE_ALREADY_RUNNING");
  if(AnotherLegacyShell())
   throw new InvalidOperationException("RC1_LEGACY_GUI_STILL_ACTIVE");
  if(AnotherDesktopCommanderRemote())
   throw new InvalidOperationException("RC1_EXISTING_REMOTE_ADOPTED_NO_DUPLICATE");
  string npx=ResolvePinnedNpx();
  var child=new RdcOwnerManagedProcess();
  string file=Path.Combine(stateRoot,"remote-"+Guid.NewGuid().ToString("N")+".log");
  CheckPath(file);
  try{
   child.Start(npx,"--yes @wonderwhy-er/desktop-commander@0.2.52 remote",sourceRoot,file);
   if(managedProcess!=null)managedProcess.Dispose();
   managedProcess=child;managedLogPath=file;managedLogs.Add(file);managedLogOffset=0;
   managedLogFragment="";managedAccount="";managedDeviceName="";managedDeviceId="";
   managedBornUtcTicks=child.BornUtcTicks;managedBannerArt.Clear();managedBannerScanned=0;
   managedStartupHeader.Clear();managedStartupComplete=false;managedStartupScanned=0;
   managedState="Connecting";managedDetail="Starting pinned Desktop Commander Remote";
   remoteSupervisor.ManagedStatus(child.Pid,true,managedState,managedDetail);
   autoStartPending=false;
   Append("remote","new Host-owned Remote launched in verified private Job");
  }catch{child.Dispose();throw;}
 }
 void StopManagedRemote(){
  if(!managedMode||managedProcess==null || !managedProcess.HasStarted)
   throw new InvalidOperationException("RC1_NO_MANAGED_REMOTE");
  if(!managedProcess.StopOwnedOnly(10000))
   throw new InvalidOperationException("RC1_OWNED_REMOTE_SURVIVORS");
  autoStartPending=false;
  managedAccount="";managedDeviceName="";managedDeviceId="";managedBornUtcTicks=0;
  managedBannerArt.Clear();managedBannerScanned=0;
   managedStartupHeader.Clear();managedStartupComplete=false;managedStartupScanned=0;
  managedState="Disconnected";managedDetail="Host-owned Remote stopped";
  remoteSupervisor.ManagedStatus(0,false,managedState,managedDetail);
  Append("remote","all members of the private owned Job exited");
 }
 // Permit only the pinned Remote's visible introductory output. No tool calls,
 // arbitrary stdout, filesystem paths, endpoints, credentials or diagnostics.
 // Preserve the real Unicode line prefixes/box art so the unchanged 1.5.18
 // RdcLogBox colorizer can style the original header in exactly the same way.
 static bool TrySafeStartupLine(string raw,out string visible) {
  visible="";
  if(raw==null||raw.Length>260)return false;
  string line=System.Text.RegularExpressions.Regex.Replace(raw,
   @"\x1B\[[0-?]*[ -/]*[@-~]","").TrimEnd('\r');
  // UTF-16 surrogate pairs are valid emoji; only refuse stray surrogates.
  if(line.Length>220 || System.Text.RegularExpressions.Regex.IsMatch(line,
   @"[\p{Cc}]|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])"))
   return false;
  if(line.Length==0){visible="";return true;}
  if(line.Length>=8 && System.Text.RegularExpressions.Regex.IsMatch(line,
    @"\A[ \t\u2500-\u259F\u00A0/\\_|.]+\z")){
   visible=line;return true;
  }
  string field,value;
  if(TrySafeIdentityLine(line,out field,out value)){visible=line;return true;}
  // Fixed instructions, lifecycle markers and command syntax; never accept
  // arbitrary suffixes or commands returned by untrusted Remote output.
  const string staticLabels=@"Remote Connection|Starting MCP Device\.\.\.|Connected to Desktop Commander MCP|Connected to Remote MCP|Session restored|Channel subscribed|Device marked as online|Device ready:|Desktop Commander Remote is connected|Next|Commands|Return to ChatGPT or Claude and continue your conversation\.|Keep this Terminal running\. You can minimize it\.|Press Ctrl\+C to disconnect\.|Run these in a new Terminal, or after disconnecting\.|Help:\s+npx @wonderwhy-er/desktop-commander@latest remote --help|Log out:\s+npx @wonderwhy-er/desktop-commander@latest remote --logout";
  var match=System.Text.RegularExpressions.Regex.Match(line,
   @"\A(?<dec>(?:[ \t\p{S}\p{P}\u200D\uFE0F]|[\uD800-\uDBFF][\uDC00-\uDFFF]){0,18})(?<label>"+
   staticLabels+@")\z",System.Text.RegularExpressions.RegexOptions.IgnoreCase);
  if(match.Success){visible=line;return true;}
  if(System.Text.RegularExpressions.Regex.IsMatch(line,
   @"\A\[DEBUG\] Verbose mode:\s+(true|false)\z",
   System.Text.RegularExpressions.RegexOptions.IgnoreCase)){visible=line;return true;}
  // Original banner prints a local executable path and Remote endpoint.
  // Keep exact visible lifecycle wording, but not those private path values.
  string[] dynamicSteps={
   "Connecting to Local Desktop Commander MCP using:",
   "Connecting to Remote MCP",
   "Found persisted session for device",
   "Presence tracked (device "
  };
  foreach(string label in dynamicSteps){
   int pos=line.IndexOf(label,StringComparison.OrdinalIgnoreCase);
   if(pos<0 || pos>18)continue;
   string prefix=line.Substring(0,pos);
   if(!System.Text.RegularExpressions.Regex.IsMatch(prefix,
    @"\A(?:[ \t\p{S}\p{P}\u200D\uFE0F]|[\uD800-\uDBFF][\uDC00-\uDFFF]){0,18}\z"))continue;
   if(label=="Found persisted session for device"||label=="Presence tracked (device "){
    var uuid=System.Text.RegularExpressions.Regex.Match(line.Substring(pos+label.Length),
     @"\A\s*[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}(?:\)|\s+visible as online\))?\s*\z");
    if(!uuid.Success)continue;
    if(label=="Found persisted session for device")
     visible=prefix+"Found persisted session for device "+uuid.Value.Trim();
    else visible=prefix+"Presence tracked (device "+uuid.Value.Trim();
   } else visible=prefix+label.TrimEnd(':');
   return true;
  }
  // This is a display-only device/status line, not a Remote control input.
  match=System.Text.RegularExpressions.Regex.Match(line,
   @"\A[ \t]{1,10}(Device:\s*|Status:\s*)([^\r\n]{1,80})\z");
  if(match.Success){
   string data=match.Groups[2].Value.Trim();
   if(match.Groups[1].Value.StartsWith("Status:",StringComparison.Ordinal) &&
      (data=="Online"||data=="Offline")){visible=line;return true;}
   if(match.Groups[1].Value.StartsWith("Device:",StringComparison.Ordinal) &&
     System.Text.RegularExpressions.Regex.IsMatch(data,@"\A[\p{L}\p{Nd} _().\-]{1,80}\z")){
    visible=line;return true;
   }
  }
  return false;
 }
 // During device re-verification the upstream terminal can print long runs
 // of empty progress rows. Keep the first separator but do not spend the
 // finite header/scan budget on duplicate blank rows. Nonblank artwork and
 // all allowlisted wording remain byte-for-byte unchanged.
 static bool ShouldKeepStartupLine(IList<string> accepted,string line){
  if(!String.IsNullOrWhiteSpace(line))return true;
  return accepted.Count>0 && !String.IsNullOrWhiteSpace(accepted[accepted.Count-1]);
 }
 void AcceptManagedStartupLine(string raw){
  if(managedStartupComplete || managedStartupHeader.Count>=54)return;
  if(raw.IndexOf("Received tool call",StringComparison.OrdinalIgnoreCase)>=0 ||
     raw.IndexOf("Tool call ",StringComparison.OrdinalIgnoreCase)>=0){
   managedStartupComplete=true;return;
  }
  if(managedStartupScanned>=90)return;
  string line;
  if(!TrySafeStartupLine(raw,out line)){
   managedStartupScanned++;return;
  }
  if(!ShouldKeepStartupLine(managedStartupHeader,line))return;
  // A single visual separator counts; an arbitrary number of extra blank
  // progress rows cannot prevent later Next/Commands lines from appearing.
  managedStartupScanned++;
  if(String.IsNullOrWhiteSpace(line))line="";
  if(String.Join("\n",managedStartupHeader.ToArray()).Length+line.Length>8192){
   managedStartupComplete=true;return;
  }
  managedStartupHeader.Add(line);
  remoteSupervisor.NoteHostEvent("Safe pinned Remote startup header updated");
 }
 void AcceptManagedBannerArt(string raw){
  if(managedBannerScanned++>=12 || managedBannerArt.Count>=7)return;
  string line=System.Text.RegularExpressions.Regex.Replace(raw,
   @"\x1B\[[0-?]*[ -/]*[@-~]","").TrimEnd('\r');
  if(line.Length<10 || line.Length>180)return;
  // Colored original banner is graphic-only; reject text and identifiers.
  if(!System.Text.RegularExpressions.Regex.IsMatch(line,
   @"\A[\s\u2500-\u259F\u00A0/\\_|.]+\z"))return;
  managedBannerArt.Add(line);
  remoteSupervisor.NoteHostEvent("Safe startup art updated");
 }
 static bool TrySafeIdentityLine(string raw,out string label,out string value){
  label="";value="";
  if(String.IsNullOrEmpty(raw))return false;
  // The pinned Remote's private startup log has a structured '- User:',
  // '- Device Name:' and '- Device ID:' header. Never export raw lines.
  string line=System.Text.RegularExpressions.Regex.Replace(raw,
   @"\x1B\[[0-?]*[ -/]*[@-~]","").TrimEnd('\r','\n');
  var match=System.Text.RegularExpressions.Regex.Match(line,
   @"^\s*-\s*(User|Device Name|Device ID):\s*([^\r\n]{1,180})\s*$",
   System.Text.RegularExpressions.RegexOptions.IgnoreCase);
  if(!match.Success)return false;
  string field=match.Groups[1].Value.ToLowerInvariant();
  string data=match.Groups[2].Value.Trim();
  if(field=="user" &&
    System.Text.RegularExpressions.Regex.IsMatch(data,
      @"\A[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9.\-]{1,120}\.[A-Za-z]{2,20}\z")){
   label="user";value=data;return true;
  }
  if(field=="device name" && data.Length<=80 &&
    System.Text.RegularExpressions.Regex.IsMatch(data,@"\A[\p{L}\p{Nd} _().\-]{1,80}\z")){
   label="deviceName";value=data;return true;
  }
  if(field=="device id" && System.Text.RegularExpressions.Regex.IsMatch(data,
    @"\A[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z")){
   label="deviceId";value=data;return true;
  }
  return false;
 }
 void AcceptManagedIdentityLine(string line){
  string field,value;
  if(!TrySafeIdentityLine(line,out field,out value))return;
  bool changed=false;
  if(field=="user" && managedAccount!=value){managedAccount=value;changed=true;}
  else if(field=="deviceName" && managedDeviceName!=value){managedDeviceName=value;changed=true;}
  else if(field=="deviceId" && managedDeviceId!=value){managedDeviceId=value;changed=true;}
  if(changed)remoteSupervisor.NoteHostEvent("Owned Remote identity metadata received: "+field);
 }
 static string SafeRemoteMarker(string line,out string next){
  next="";
  if(line.IndexOf("Desktop Commander Remote is connected",StringComparison.OrdinalIgnoreCase)>=0||
     line.IndexOf("Presence tracked (device ",StringComparison.OrdinalIgnoreCase)>=0){
   next="Ready";return "Remote connected";
  }
  if(line.IndexOf("Authenticating with Remote MCP server",StringComparison.OrdinalIgnoreCase)>=0||
     line.IndexOf("waiting for authentication",StringComparison.OrdinalIgnoreCase)>=0){
   next="AuthPending";return "Authentication pending";
  }
  if(line.IndexOf("Channel error:",StringComparison.OrdinalIgnoreCase)>=0||
     line.IndexOf("Device marked as offline",StringComparison.OrdinalIgnoreCase)>=0){
   next="Fault";return "Remote channel unavailable";
  }
  if(line.IndexOf("Local Desktop Commander MCP went away",StringComparison.OrdinalIgnoreCase)>=0){
   next="Reconnecting";return "Local MCP recovering";
  }
  if(line.IndexOf("Device startup failed:",StringComparison.OrdinalIgnoreCase)>=0){
   next="Fault";return "Remote start failed";
  }
  // Exact top-level pinned Remote tool markers only. Never forward raw
  // arguments, tool output, request IDs, private paths or user data.
  if(line.StartsWith("🔧 Received tool call ",StringComparison.Ordinal) &&
     line.Length>"🔧 Received tool call ".Length){
   // Only a known public tool identifier may be displayed. In particular,
   // request ids, JSON arguments, stdout and file paths stay in the private log.
   var name=System.Text.RegularExpressions.Regex.Match(line,
    @"\A🔧 Received tool call [A-Za-z0-9_-]{1,100}:\s*(?<tool>[a-z][a-z0-9_]{1,39})(?=\s|$)");
   if(name.Success){
    string tool=name.Groups["tool"].Value;
    string[] known={"start_process","read_process_output","interact_with_process",
     "read_file","read_multiple_files","list_directory","get_file_info",
     "list_processes","start_search","get_more_search_results","stop_search",
     "get_config","write_file","edit_block","create_directory","move_file"};
    if(Array.IndexOf(known,tool)>=0)return "Remote tool started: "+tool;
   }
   return "Remote tool started";
  }
  if(line.StartsWith("✅ Tool call ",StringComparison.Ordinal) &&
     line.IndexOf(" completed:",StringComparison.Ordinal)>0)
   return "Remote tool completed";
  if(line.StartsWith("❌ Tool call ",StringComparison.Ordinal) &&
     line.IndexOf(" failed:",StringComparison.Ordinal)>0)
   return "Remote tool failed";
  return "";
 }
 void RefreshManagedRemote(){
  if(!managedMode||managedProcess==null||!managedProcess.HasStarted)return;
  if(!managedProcess.Running){
   if(managedState!="Disconnected"){
    managedAccount="";managedDeviceName="";managedDeviceId="";managedBornUtcTicks=0;
    managedBannerArt.Clear();managedBannerScanned=0;
   managedStartupHeader.Clear();managedStartupComplete=false;managedStartupScanned=0;
    managedState="Disconnected";managedDetail="Host-owned Remote process exited";
    remoteSupervisor.ManagedStatus(0,false,managedState,managedDetail);
    Append("remote","owned Job no longer running");
   }
   return;
  }
  if(String.IsNullOrEmpty(managedLogPath)||!File.Exists(managedLogPath))return;
  try{
   CheckPath(managedLogPath);
   using(var stream=new FileStream(managedLogPath,FileMode.Open,FileAccess.Read,
     FileShare.ReadWrite|FileShare.Delete)){
    if(stream.Length<managedLogOffset){managedLogOffset=0;managedLogFragment="";}
    long count=Math.Min(32768,stream.Length-managedLogOffset);
    if(count<=0)return;
    stream.Seek(managedLogOffset,SeekOrigin.Begin);
    byte[] buffer=new byte[(int)count];
    int read=stream.Read(buffer,0,buffer.Length);
    managedLogOffset+=read;
    string joined=managedLogFragment+Encoding.UTF8.GetString(buffer,0,read);
    int end=joined.LastIndexOf('\n');
    if(end<0){managedLogFragment=joined.Length<=2048?joined:"";return;}
    managedLogFragment=joined.Substring(end+1);
    string[] lines=joined.Substring(0,end).Split('\n');
    int start=Math.Max(0,lines.Length-100),emitted=0;
    for(int i=0;i<lines.Length;i++){
     string cleanLine=lines[i].TrimEnd('\r');
     AcceptManagedBannerArt(cleanLine);
     AcceptManagedIdentityLine(cleanLine);
     AcceptManagedStartupLine(cleanLine);
     if(i<start)continue; // Only journal markers are bounded to the tail.
     string next;
     string marker=SafeRemoteMarker(cleanLine,out next);
     if(marker=="")continue;
     if(emitted++<24)remoteSupervisor.AddSyntheticLogLine(marker);
     if(next!=""){
      managedState=next;managedDetail=marker;
      remoteSupervisor.ManagedStatus(managedProcess.Pid,true,next,marker);
     }
    }
   }
  }catch(Exception error){Append("remote","managed journal unavailable: "+error.GetType().Name);}
 }
 // Read-only attachment to a preexisting legacy launcher. The caller must
 // validate original cmd.exe commandline/log path and OS PID/birth/session.
 // This grants no process ownership; RC1 never controls the adopted Remote.
 public void EnableObservedRemote(int pid){
  lock(gate){
   if(disposed||gui!=null||observedMode||trialRoot!=null || pid<=0)
    throw new InvalidOperationException("RC1_OBSERVER_MODE_BOUNDARY");
   remoteSupervisor.AttachObservedReadOnly(pid);
   observedMode=true;
   tray.Text="RDC Relay 1.6 RC1 | наблюдение";
   trayStatusItem.Text="Remote: существующая сессия (Adopted)";
   trayExitItem.Text="Закрыть RC1 (Remote останется)";
   Append("remote","read-only existing Remote observer attached");
  }
 }
 public void RetargetObservedRemote(int pid){
  lock(gate){
   if(disposed||!observedMode||pid<=0)throw new InvalidOperationException("RC1_NOT_OBSERVING");
   remoteSupervisor.RetargetObservedReadOnly(pid);
   Append("remote","observed launcher replaced (read-only)");
  }
 }
 public void UpdateObservedRemote(bool alive,string state,string detail){
  lock(gate){
   if(disposed||!observedMode)return;
   string before=(string)remoteSupervisor.Snapshot()["state"];
   remoteSupervisor.UpdateObservedReadOnly(alive,state,detail);
   if(before!=state)Append("remote","observed state: "+state);
  }
 }
 public void ObservedMarker(string marker){
  lock(gate){
   if(disposed||!observedMode)return;
   remoteSupervisor.AddObservedMarker(marker);
   Append("remote",marker);
  }
 }
 // Bounded observer test exit: detach RC1 GUI/Host, never signal Remote.
 public void RequestObservedDetach(){
  lock(gate){
   if(disposed||!observedMode||exitRequested)return;
   exitRequested=true;closeGeneration++;
   Append("host","observer-only test detach requested");
  }
 }
 Dictionary<string,object> Snapshot(){
  var observed=remoteSupervisor.Snapshot();
  return new Dictionary<string,object>{
   {"hostPid",hostPid},{"hostGeneration",generation},{"hostTicks",hostBorn},
   {"remoteMode",observedMode?"OBSERVED_READ_ONLY_RC1":managedMode?"MANAGED_OWNER_RC1":"FAKE_ONLY_RC1"},{"remoteId",remoteSupervisor.SessionId},
   {"remote",observed},{"remoteConnected",(managedMode||observedMode) && (string)observed["state"]=="Ready"},
   {"account",observedMode?"Existing Remote / read-only":managedMode?"RC1 Host-owned Remote":"DEMO: disabled"},
   {"remoteBornUtcTicks",managedMode?managedBornUtcTicks:0L},
   {"remoteStartupArt",managedMode?String.Join("\n",managedBannerArt.ToArray()):""},
   {"remoteStartupHeader",managedMode?String.Join("\n",managedStartupHeader.ToArray()):""},
   {"remoteIdentity",new Dictionary<string,object>{
    {"user",managedMode?managedAccount:""},{"deviceName",managedMode?managedDeviceName:""},
    {"deviceId",managedMode?managedDeviceId:""}
   }},
   {"logTail",observed["tail"]},{"logCursor",observed["logCursor"]},
   {"logStreamEpoch",observed["logStreamEpoch"]},
   {"guiPid",childPid},{"guiState",guiState},{"guiStarts",guiStarts},
   {"guiFailures",guiFailures},{"closeGeneration",closeGeneration},{"lastEventSeq",sequence},
   {"revision",sequence},{"remoteRevision",observed["revision"]},{"isActualRemote",observedMode||managedMode},
   {"capabilities",new Dictionary<string,object>{
     {"deviceManagementLink",observedMode||managedMode},{"deviceVerificationLink",observedMode||managedMode},
     {"sanitizedJournal",true},{"about",true},
     {"startRemote",managedMode && (managedProcess==null||!managedProcess.Running)},
     {"stopRemote",managedMode && managedProcess!=null&&managedProcess.Running},
     {"reconnectRemote",managedMode && managedProcess!=null&&managedProcess.Running},
     {"switchAccount",false},{"update",false},{"fullExit",managedMode},
     {"reason",observedMode?"ADOPTED_REMOTE_READ_ONLY":managedMode?"KERNEL_JOB_OWNED_ONLY":"NO_OWNED_REMOTE"}
   }}
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
    if(guiReadySignal!=null)guiReadySignal.Set();
    return Answer("WELCOME",requestId,Snapshot());
   }
   if(!guiAuthenticated)return Error(requestId,"HELLO_REQUIRED");
   if(verb=="GET_SNAPSHOT"){
    if(trialRoot!=null || observedMode)trialSnapshotClients.Add(osPid);
    return Answer("SNAPSHOT",requestId,Snapshot());
   }
   if(verb=="GET_EVENTS"){
    if(trialRoot!=null || observedMode)trialEventClients.Add(osPid);
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
   if(verb=="OPEN_EXTERNAL"){
    // GUI has no authority to synthesize a destination URL. Exact harmless
    // official device pages only, with Host-side observed-mode permission.
    if(!observedMode&&!managedMode)return Error(requestId,"NO_ACTUAL_REMOTE_FOR_NAVIGATION");
    string destination=RdcOwnerWire.String(request,"navigation");
    if(destination=="DEVICE_MANAGEMENT")return Answer("NAVIGATION",requestId,new {
     route=destination,url="https://mcp.desktopcommander.app/"});
    if(destination=="DEVICE_VERIFICATION")return Answer("NAVIGATION",requestId,new {
     route=destination,url="https://mcp.desktopcommander.app/device/verify"});
    return Error(requestId,"NAVIGATION_NOT_ALLOWLISTED");
   }
   if(verb=="REMOTE_ACTION"){
    string action=RdcOwnerWire.String(request,"action");
    if(action!="START" && action!="STOP" && action!="RECONNECT" &&
       action!="SWITCH_ACCOUNT" && action!="UPDATE" && action!="FULL_EXIT")
     return Error(requestId,"REMOTE_ACTION_UNKNOWN");
    if(observedMode)return Error(requestId,"ADOPTED_REMOTE_READ_ONLY");
    if(!managedMode)return Error(requestId,"REMOTE_OWNER_NOT_VERIFIED");
    // Only the authenticated active GUI's explicit click, not a background
    // snapshot or tray discovery, can authorize a managed Remote action.
    if(RdcOwnerWire.String(request,"userConfirmed")!="YES")
     return Error(requestId,"REMOTE_ACTION_USER_CONFIRMATION_REQUIRED");
    if(action=="SWITCH_ACCOUNT"||action=="UPDATE")
     return Error(requestId,"REMOTE_ACTION_NOT_SAFELY_IMPLEMENTED");
    try{
     if(action=="START")StartManagedRemote();
     else if(action=="STOP")StopManagedRemote();
     else if(action=="RECONNECT"){
      StopManagedRemote();
      StartManagedRemote();
     }else if(action=="FULL_EXIT"){
      if(managedProcess!=null&&managedProcess.Running)StopManagedRemote();
      exitRequested=true;closeGeneration++;
     }
     return Answer("ACK",requestId,new {action=action,success=true});
    }catch(Exception problem){
     Append("remote","managed action denied: "+problem.GetType().Name);
     return Error(requestId,"MANAGED_"+problem.GetType().Name.ToUpperInvariant());
    }
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
   if(reopenSignal!=null)reopenSignal.Dispose();
   if(idleUpgradeSignal!=null)idleUpgradeSignal.Dispose();
   if(guiReadySignal!=null)guiReadySignal.Dispose();
   bool ipcClean=true,filesClean=false,guiClean=(gui==null);
   try{if(server!=null)server.Dispose();}catch{ipcClean=false;}
   if(gui!=null)gui.Dispose(); // no force kill or unverified child stop
   if(guiClean && ticketStore!=null){
    filesClean=RemoveOwnedManagedLogs() && ticketStore.RevokeOnlyOwned() && RemoveEmptyOwnedRunRoot();
   }
   if(managedProcess!=null)managedProcess.Dispose();
   try{singleton.ReleaseMutex();}catch{}
   singleton.Dispose();
   if(trialRoot!=null){
    Console.WriteLine("RC1_TRIAL_IPC_SNAPSHOT_GUI_COUNT="+
     trialSnapshotClients.Count+" EVENT_GUI_COUNT="+trialEventClients.Count);
    Console.WriteLine("RC1_TRIAL_IPC_REJECTED="+server.Rejected+
     " TIMEOUTS="+server.Timeouts+" PEAK_ACTIVE="+server.PeakActive);
   }
   if(observedMode){
    Console.WriteLine("RC1_OBSERVER_GUI_STARTS="+guiStarts+" FAILURES="+guiFailures+
     " SNAPSHOT_GUI_COUNT="+trialSnapshotClients.Count+
     " EVENT_GUI_COUNT="+trialEventClients.Count);
    if(guiFailures>0)Console.WriteLine("RC1_OBSERVER_LAST_GUI_ERROR="+lastGuiError);
    Console.WriteLine("RC1_OBSERVER_DETACHED_ONLY=TRUE");
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
