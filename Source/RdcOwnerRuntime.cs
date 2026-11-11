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

// Host-local, bounded correlation of pinned Remote call IDs. Only the
// generated ordinal, allowlisted tool and safe basename reach GUI IPC.
public sealed class RdcOwnerToolJournal {
 sealed class Entry {public long Number;public string Tool,Target;public bool Ambiguous;}
 readonly Dictionary<string,Entry> pending=new Dictionary<string,Entry>(StringComparer.Ordinal);
 readonly List<string> order=new List<string>();
 long nextNumber=0;
 static readonly string[] known={"start_process","read_process_output","interact_with_process",
  "read_file","read_multiple_files","list_directory","get_file_info",
  "list_processes","start_search","get_more_search_results","stop_search",
  "get_config","write_file","edit_block","create_directory","move_file"};
 static readonly System.Text.RegularExpressions.Regex start=
  new System.Text.RegularExpressions.Regex(
   @"\A🔧 Received tool call (?<id>[A-Za-z0-9_-]{1,100}):\s*(?<tool>[a-z][a-z0-9_]{1,39})(?:\s+(?<args>.*))?\z");
 static readonly System.Text.RegularExpressions.Regex end=
  new System.Text.RegularExpressions.Regex(
   @"\A[✅❌] Tool call (?<id>[A-Za-z0-9_-]{1,100}) (?:completed|failed):");
 static readonly System.Text.RegularExpressions.Regex param=
  new System.Text.RegularExpressions.Regex(
   @"(?<!\\)""(?<key>file_path|path|directory|command)""\s*:\s*""(?<value>(?:\\.|[^""\\]){1,260})""");
 public void Reset(){pending.Clear();order.Clear();nextNumber=0;}
 static string SafeTarget(string tool,string args){
  if(args==null||args.Length>8192)return "";
  foreach(System.Text.RegularExpressions.Match m in param.Matches(args)){
   string key=m.Groups["key"].Value;
   string value=m.Groups["value"].Value.Replace("\\\\","\\").Replace("\\/","/");
   if(tool=="start_process" && key=="command"){
    var command=System.Text.RegularExpressions.Regex.Match(value,
     @"\A\s*(?:&\s*)?['""]?(?<exe>powershell(?:\.exe)?|pwsh(?:\.exe)?|cmd(?:\.exe)?|git(?:\.exe)?|python(?:\.exe)?|py(?:\.exe)?|node(?:\.exe)?|npm(?:\.cmd)?|npx(?:\.cmd)?|dotnet(?:\.exe)?|java(?:\.exe)?|cmake(?:\.exe)?)(?=\s|['""]|$)",
     System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    if(command.Success){
     string exe=command.Groups["exe"].Value.ToLowerInvariant();
     if(exe.StartsWith("powershell")||exe.StartsWith("pwsh"))return "PowerShell";
     if(exe.StartsWith("cmd"))return "CMD";
     if(exe.StartsWith("git"))return "Git";
     if(exe.StartsWith("python")||exe.StartsWith("py."))return "Python";
     if(exe.StartsWith("node"))return "Node.js";
     if(exe.StartsWith("npm"))return "npm";
     if(exe.StartsWith("npx"))return "npx";
     if(exe.StartsWith("dotnet"))return ".NET";
     if(exe.StartsWith("java"))return "Java";
     if(exe.StartsWith("cmake"))return "CMake";
    }
    return "";
   }
   if(key=="command")continue;
   int slash=value.LastIndexOfAny(new char[]{'\\','/'});
   string name=value.Substring(slash+1);
   if(name.Length<1||name.Length>64||name[0]=='.'||name.IndexOf('@')>=0)continue;
   if(System.Text.RegularExpressions.Regex.IsMatch(name,@"(?i)(secret|password|token|credential|private.key)"))continue;
   if(System.Text.RegularExpressions.Regex.IsMatch(name,@"\A[\p{L}\p{Nd}_ .()\-]{1,64}\z") &&
      !System.Text.RegularExpressions.Regex.IsMatch(name,@"\A[. ]+\z"))
    return name;
  }
  return "";
 }
 public string Format(string raw,string marker){
  if(marker.StartsWith("Remote tool started",StringComparison.Ordinal)){
   if(raw==null||raw.Length>8192)return marker;
   var m=start.Match(raw);
   if(!m.Success)return marker;
   string id=m.Groups["id"].Value,tool=m.Groups["tool"].Value;
   if(Array.IndexOf(known,tool)<0)return marker;
   if(pending.ContainsKey(id))return ""; // duplicate start, not new work
   while(pending.Count>=64 && order.Count>0){pending.Remove(order[0]);order.RemoveAt(0);}
   bool ambiguous=false;
   foreach(var item in pending.Values){if(item.Tool==tool){item.Ambiguous=true;ambiguous=true;}}
   var entry=new Entry{Number=++nextNumber,Tool=tool,Target=SafeTarget(tool,m.Groups["args"].Value),Ambiguous=ambiguous};
   pending[id]=entry;order.Add(id);
   return "Remote tool started|"+entry.Number+"|"+entry.Tool+"|"+entry.Target;
  }
  if(marker.StartsWith("Remote tool completed",StringComparison.Ordinal)||
     marker.StartsWith("Remote tool failed",StringComparison.Ordinal)){
   if(raw==null||raw.Length>8192)return marker;
   var m=end.Match(raw);
   if(!m.Success)return marker;
   string token=m.Groups["id"].Value;
   Entry entry;
   bool exactId=pending.TryGetValue(token,out entry);
   // The pinned Remote 0.2.52 completion marker normally names the tool,
   // not the request UUID from Received tool call. Pair by tool only when
   // there is exactly one unambiguous outstanding call of that type.
   if(!exactId && Array.IndexOf(known,token)>=0){
    int count=0;string oldest=null;
    foreach(string id in order){Entry candidate;
     if(pending.TryGetValue(id,out candidate) && candidate.Tool==token){
      count++;if(oldest==null){oldest=id;entry=candidate;}
     }
    }
    if(oldest!=null){
     pending.Remove(oldest);order.Remove(oldest);
     if(count!=1 || entry.Ambiguous)
      return marker+": "+token;
    }else return marker+": "+token;
   }else if(!exactId)return marker;
   else{pending.Remove(token);order.Remove(token);}
   return (marker.StartsWith("Remote tool completed",StringComparison.Ordinal)?
    "Remote tool completed|":"Remote tool failed|")+entry.Number+"|"+entry.Tool+"|"+entry.Target;
  }
  return marker;
 }
}
// One grace interval for both tray activation and the asynchronous startup probe.
// A second OpenGui request during warm-up must never trigger an early warning.
public static class RdcOwnerGuiStartupNotice {
 public const int GraceSeconds=8;
 public static bool IsDue(DateTime spawnedUtc,DateTime nowUtc,bool alreadyWarned,bool ownedWindowPresent){
  return !alreadyWarned && !ownedWindowPresent && spawnedUtc!=DateTime.MinValue &&
   (nowUtc-spawnedUtc).TotalSeconds>=GraceSeconds;
 }
}
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
 readonly RdcOwnerToolJournal toolJournal=new RdcOwnerToolJournal();
 bool observedMode=false,managedMode=false,reopenAfterModeChange=false,autoStartPending=false;
 DateTime nextAutoStartUtc=DateTime.MinValue;
 // Owner GUI focus is advisory: Windows may refuse activation from the tray.
 // Limit diagnostics and balloon hints; never restart an unverified child.
 DateTime guiSpawnUtc=DateTime.MinValue,lastGuiNoticeUtc=DateTime.MinValue;
 bool guiWindowWarned=false;
 RdcOwnerManagedProcess managedProcess=null;
 // Logout is a separate, bounded private Job; never execute in the GUI or
 // borrow the running Remote's process tree or credential files.
 RdcOwnerManagedProcess accountLogoutProcess=null;
 DateTime accountLogoutDeadlineUtc=DateTime.MinValue;
 bool accountSwitchFaultLatched=false;
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
 // Animation cadence is independent from 250ms Host health/IPC polling.
 readonly System.Windows.Forms.Timer trayFrameTimer=new System.Windows.Forms.Timer();
 RdcOwnerTrayVisual trayVisual;
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
 // Only a ready Remote launched into THIS Host's private Job can select
 // the quota OAuth account. External/observed/fake identity never triggers login.
 public string ActiveManagedAccount {
  get {
   lock(gate){
    if(!managedMode||observedMode||trialRoot!=null||managedState!="Ready"||
       managedProcess==null||!managedProcess.Running)return "";
    return System.Text.RegularExpressions.Regex.IsMatch(managedAccount??"",
      @"\A[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9.\-]{1,120}\.[A-Za-z]{2,20}\z")?
      managedAccount:"";
   }
  }
 }
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
   tray.Icon=SystemIcons.Information; // fallback only for incomplete fake-only fixtures
   tray.Text="RDC Relay 1.6 RC1 | FAKE Remote";
   trayVisual=RdcOwnerTrayVisual.Load(sourceRoot,tray);
   if(trayVisual!=null)trayVisual.Update(remoteSupervisor.Snapshot());
   else Append("host","tray artwork missing in isolated fixture; fallback icon");
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
     if(accountLogoutProcess!=null){
      MessageBox.Show("Смена аккаунта ещё выполняется. Дождитесь результата.",
       "RDC Relay",MessageBoxButtons.OK,MessageBoxIcon.Warning);
      return;
     }
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
   trayFrameTimer.Interval=40; // 160ms color fades at 4 ticks; cached frames
   trayFrameTimer.Tick+=(s,e)=>{
    lock(gate){
     if(disposed||trayVisual==null)return;
     try{trayVisual.Advance();}
     catch(Exception problem){
      Append("host","tray icon render failed: "+problem.GetType().Name);
      trayFrameTimer.Stop();
      tray.Icon=SystemIcons.Information;
      trayVisual.Dispose();trayVisual=null;
     }
    }
   };
   trayFrameTimer.Start();
   pulse.Interval=250;
   pulse.Tick+=(s,e)=>{
    lock(gate){
     RefreshGui();
     // Cooperative same-logon Setup handoff. The Host itself authorizes its
     // idle exit, never accepting PID/name-based termination from Setup.
     if(idleUpgradeSignal!=null && idleUpgradeSignal.WaitOne(0) && !exitRequested){
      try{
       if(managedMode && !observedMode && accountLogoutProcess==null &&
          !accountSwitchFaultLatched &&
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
      if(accountLogoutProcess!=null && !accountSwitchFaultLatched)AdvanceManagedAccountSwitch();
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
     // Host state snapshots are sampled at 250ms; the 40ms timer only
     // advances an already-selected cached icon, without allocating snapshots.
     if(trayVisual!=null){
      try{trayVisual.Update(remoteSupervisor.Snapshot());}
      catch(Exception problem){
       Append("host","tray state render failed: "+problem.GetType().Name);
       trayFrameTimer.Stop();
       tray.Icon=SystemIcons.Information;
       trayVisual.Dispose();trayVisual=null;
      }
     }
    }
   };
   if(trialRoot!=null)trialClock.Start();
   pulse.Start();
   remoteSupervisor.AddSyntheticLogLine("RDC Relay 1.6 RC1: Remote disabled until owner OS trial approval.");
   Append("host","RC1 fake-only owner startup");
  }catch{
   // Fail-closed unwind of partly created host-owned resources.
   try{pulse.Stop();pulse.Dispose();}catch{}
   try{trayFrameTimer.Stop();trayFrameTimer.Dispose();}catch{}
   try{if(reopenSignal!=null)reopenSignal.Dispose();}catch{}
   try{if(idleUpgradeSignal!=null)idleUpgradeSignal.Dispose();}catch{}
   try{if(guiReadySignal!=null)guiReadySignal.Dispose();}catch{}
   try{tray.Visible=false;tray.Dispose();}catch{}
   try{if(trayVisual!=null)trayVisual.Dispose();}catch{}
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
  if(accountLogoutProcess!=null && accountLogoutProcess.Running)return false;
  foreach(string path in managedLogs){
   try{
    if(Path.GetDirectoryName(path)!=stateRoot ||
       !System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(path),
        @"^(?:remote|logout)-[0-9a-f]{32}\.log$",System.Text.RegularExpressions.RegexOptions.CultureInvariant))
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
 void NotifyGuiOpenIssue(string code,string message){
  DateTime now=DateTime.UtcNow;
  if((now-lastGuiNoticeUtc).TotalSeconds<8)return;
  lastGuiNoticeUtc=now;
  Append("gui",code);
  try{
   tray.BalloonTipTitle="RDC Relay";
   tray.BalloonTipText=message;
   tray.BalloonTipIcon=ToolTipIcon.Info;
   tray.ShowBalloonTip(3000);
  }catch{} // notification availability is not Remote authority
 }
 void RefreshGui(){
  if(gui==null)return;
  try{
   if(!gui.HasExited){
    // A live process without a window can no longer be reported as
    // successfully opened forever. Do not kill it or launch a duplicate.
    if(!guiWindowWarned && guiSpawnUtc!=DateTime.MinValue &&
       (DateTime.UtcNow-guiSpawnUtc).TotalSeconds>=RdcOwnerGuiStartupNotice.GraceSeconds){
     gui.Refresh();
     bool hasOwnedWindow=RdcOwnerActivate.FindOwnedWindow(childPid)!=IntPtr.Zero;
     if(RdcOwnerGuiStartupNotice.IsDue(guiSpawnUtc,DateTime.UtcNow,guiWindowWarned,hasOwnedWindow))
      NotifyGuiOpenIssue("window not ready",
       "Окно RDC Relay пока не появилось. Повторите открытие через трей; Remote не затронут.");
     guiWindowWarned=true; // one check per GUI generation, even if already visible
    }
    return;
   }
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
  guiSpawnUtc=DateTime.MinValue;guiWindowWarned=false;
  nonce="";lastRequestSequence=0;requestIds.Clear();requestOrder.Clear();
  if(!ticketStore.RevokeOnlyOwned()){
   guiState="UNVERIFIED";Append("gui","ticket ownership unverified; relaunch denied");return;
  }
  guiState="NONE";Append("gui","process exited");
 }
 public void OpenGui(){
  lock(gate){
   if(disposed||exitRequested)return;
   if(guiState=="UNVERIFIED"){
    NotifyGuiOpenIssue("open denied: unverified",
      "Окно RDC Relay не удалось проверить. Remote продолжает работу; проверьте журнал.");
    return;
   }
   RefreshGui();
   if(guiState=="UNVERIFIED"){
    NotifyGuiOpenIssue("open denied: unverified",
      "Окно RDC Relay не удалось проверить. Remote продолжает работу; проверьте журнал.");
    return;
   }
   if(gui!=null){
    try{
     // Refresh the cached MainWindowHandle after an asynchronous GUI launch.
     // Only our recorded PID, session and birth time may be activated.
     gui.Refresh();
     if(gui.Id!=childPid || gui.SessionId!=childSession ||
        gui.StartTime.ToUniversalTime().Ticks!=childBorn){
      guiState="UNVERIFIED";
      NotifyGuiOpenIssue("open denied: child identity mismatch",
        "Невозможно подтвердить окно RDC Relay. Remote не затронут.");
      return;
     }
     IntPtr target=gui.MainWindowHandle;
     if(target==IntPtr.Zero)target=RdcOwnerActivate.FindOwnedWindow(childPid);
     string result=RdcOwnerActivate.OpenOwned(target,childPid);
     if(result=="ATTENTION"){
      NotifyGuiOpenIssue("foreground denied",
       "Окно RDC Relay уже открыто. Выберите его через Alt+Tab или панель задач.");
     }else if(result=="NO_WINDOW"){
      // Window creation is asynchronous. A tray or launcher retry during the
      // first eight seconds is not a failed GUI open and needs no balloon.
      if(RdcOwnerGuiStartupNotice.IsDue(guiSpawnUtc,DateTime.UtcNow,guiWindowWarned,false)){
       guiWindowWarned=true;
       NotifyGuiOpenIssue("open pending: no window",
        "Окно RDC Relay ещё не появилось. Попробуйте открыть его через трей ещё раз.");
      }
     }else if(result=="NOT_OWNED"){
      guiState="UNVERIFIED";
      NotifyGuiOpenIssue("open denied: unverified window",
       "Невозможно подтвердить окно RDC Relay. Remote не затронут.");
     }
    }catch(Exception problem){
     NotifyGuiOpenIssue("open failed: "+problem.GetType().Name,
      "Не удалось вывести окно RDC Relay. Remote продолжает работу.");
    }
    return; // verified live child: never launch a second GUI
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
    guiStarts++;guiState="SPAWNING";guiAuthenticated=false;
    guiSpawnUtc=DateTime.UtcNow;guiWindowWarned=false;
    Append("gui","spawned");
   }catch(Exception startError){
    lastGuiError=startError.GetType().Name+": "+startError.Message;
    if(lastGuiError.Length>180)lastGuiError=lastGuiError.Substring(0,180);
    guiFailures++;guiState="NONE";Append("gui","launch failed");
    NotifyGuiOpenIssue("GUI launch failed: "+startError.GetType().Name,
     "RDC Relay не смог открыть окно. Remote не затронут; проверьте журнал Host.");
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
   if(disposed||exitRequested||observedMode||!managedMode||accountLogoutProcess!=null||
      accountSwitchFaultLatched||!guiAuthenticated||guiState!="CONNECTED"||reopenAfterModeChange)return false;
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
  if(!managedMode||observedMode||exitRequested||accountLogoutProcess!=null)
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
   accountSwitchFaultLatched=false;
   toolJournal.Reset();
   managedLogFragment="";managedAccount="";managedDeviceName="";managedDeviceId="";
   managedBornUtcTicks=child.BornUtcTicks;managedBannerArt.Clear();managedBannerScanned=0;
   managedStartupHeader.Clear();managedStartupComplete=false;managedStartupScanned=0;
   managedState="Connecting";managedDetail="Starting pinned Desktop Commander Remote";
   remoteSupervisor.ManagedStatus(child.Pid,true,managedState,managedDetail);
   autoStartPending=false;
   Append("remote","new Host-owned Remote launched in verified private Job");
  }catch{child.Dispose();throw;}
 }
 // Only Host-owned Remote can be switched. The old Job must be fully
 // drained before official logout: never revoke a borrowed/adopted session.
 // Running logout gets its own private Job and the Host stays alive.
 void BeginManagedAccountSwitch(){
  if(disposed||exitRequested||observedMode||!managedMode||trialRoot!=null||
     accountLogoutProcess!=null||accountSwitchFaultLatched||
     managedProcess==null||!managedProcess.Running||managedState!="Ready")
   throw new InvalidOperationException("RC1_ACCOUNT_SWITCH_NOT_OWNED_READY");
  string npx=ResolvePinnedNpx();
  if(AnotherLegacyShell())
   throw new InvalidOperationException("RC1_ACCOUNT_SWITCH_LEGACY_SHELL");
  bool stopped=false;
  try{
   StopManagedRemote();
   stopped=true;
   // The shared local device authorization must not be revoked if ANY other
   // Remote or legacy GUI remains. Failure leaves this owned Remote stopped.
   if(AnotherDesktopCommanderRemote()||AnotherLegacyShell())
    throw new InvalidOperationException("RC1_ACCOUNT_SWITCH_EXTERNAL_REMOTE");
   string file=Path.Combine(stateRoot,"logout-"+Guid.NewGuid().ToString("N")+".log");
   CheckPath(file);
   managedLogs.Add(file); // account for a partially created private log too
   var worker=new RdcOwnerManagedProcess();
   try{
    worker.Start(npx,"--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout",sourceRoot,file);
    accountLogoutProcess=worker;
   }catch{worker.Dispose();throw;}
   accountLogoutDeadlineUtc=DateTime.UtcNow.AddSeconds(60);
   managedState="AuthPending";managedDetail="Official device logout in progress";
   remoteSupervisor.ManagedStatus(0,false,managedState,managedDetail);
   Append("remote","owner confirmed account change; private logout Job started");
  }catch(Exception failure){
   if(stopped){
    accountSwitchFaultLatched=true;autoStartPending=false;
    managedState="Fault";managedDetail="Account switch refused; owned Remote remains stopped";
    remoteSupervisor.ManagedStatus(0,false,managedState,managedDetail);
    Append("remote","account change did not start: "+failure.GetType().Name);
   }
   throw;
  }
 }
 void AdvanceManagedAccountSwitch(){
  if(accountLogoutProcess==null||accountSwitchFaultLatched)return;
  bool logoutConfirmed=false;
  try{
   int code;
   if(accountLogoutProcess.TryGetCompletedExitCode(out code)){
    accountLogoutProcess.Dispose();accountLogoutProcess=null;
    if(code!=0)throw new InvalidOperationException("RC1_ACCOUNT_LOGOUT_NONZERO_EXIT");
    logoutConfirmed=true;
    Append("remote","official logout succeeded; starting new browser pairing");
    StartManagedRemote();
    Append("remote","fresh Host-owned Remote started after confirmed logout");
    return;
   }
   if(DateTime.UtcNow<accountLogoutDeadlineUtc)return;
   if(!accountLogoutProcess.StopOwnedOnly(10000))
    throw new TimeoutException("RC1_ACCOUNT_LOGOUT_JOB_SURVIVORS");
   accountLogoutProcess.Dispose();accountLogoutProcess=null;
   throw new TimeoutException("RC1_ACCOUNT_LOGOUT_TIMEOUT");
  }catch(Exception failure){
   // Stop only this newly-created logout Job; never kill by PID/name.
   // If ownership cannot be verified, retain the handle and deny actions.
   if(accountLogoutProcess!=null){
    try{
     if(accountLogoutProcess.StopOwnedOnly(10000)){
      accountLogoutProcess.Dispose();accountLogoutProcess=null;
     }
    }catch{}
   }
   accountSwitchFaultLatched=true;autoStartPending=false;
   managedState="Fault";
   managedDetail=logoutConfirmed?"Authorization revoked; Remote restart failed":
     "Logout not confirmed; Remote remains stopped";
   remoteSupervisor.ManagedStatus(0,false,managedState,managedDetail);
   Append("remote","account switch failed: "+failure.GetType().Name);
  }
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
 // A successful Remote MCP tool call proves current end-to-end reachability.
 // A local stdio restart marker alone must not keep the UI in Reconnecting
 // indefinitely when the Remote continues processing authenticated calls.
 // Never infer Ready merely from a running process or an incomplete call.
 static bool ToolCompletionConfirmsReady(string marker,string currentState){
  if(!marker.StartsWith("Remote tool completed",StringComparison.Ordinal))return false;
  return currentState=="Reconnecting"||currentState=="Fault"||
   currentState=="Connecting"||currentState=="AuthPending";
 }
 void RefreshManagedRemote(){
  if(accountLogoutProcess!=null||accountSwitchFaultLatched)return;
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
    if(stream.Length<managedLogOffset){managedLogOffset=0;managedLogFragment="";toolJournal.Reset();}
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
    // Process every bounded log-chunk marker, including concurrent calls.
    // The store keeps only the last 64 sanitized entries for the GUI.
    for(int i=0;i<lines.Length;i++){
     string cleanLine=lines[i].TrimEnd('\r');
     AcceptManagedBannerArt(cleanLine);
     AcceptManagedIdentityLine(cleanLine);
     AcceptManagedStartupLine(cleanLine);
     string next;
     string marker=SafeRemoteMarker(cleanLine,out next);
     if(marker=="")continue;
     if(marker.StartsWith("Remote tool ",StringComparison.Ordinal))
      marker=toolJournal.Format(cleanLine,marker);
     if(marker=="")continue;
     // Preserve the sanitized tool completion journal entry, while using
     // that same confirmed success to recover stale connection state.
     if(next=="" && ToolCompletionConfirmsReady(marker,managedState))
      next="Ready";
     remoteSupervisor.AddSyntheticLogLine(marker);
     if(next!=""){
      managedState=next;
      managedDetail=(marker.StartsWith("Remote tool completed",StringComparison.Ordinal) && next=="Ready")
       ?"Successful Remote tool call confirmed connectivity":marker;
      remoteSupervisor.ManagedStatus(managedProcess.Pid,true,next,managedDetail);
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
   toolJournal.Reset();observedMode=true;
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
   toolJournal.Reset();
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
 // Only invoked by the verified read-only observer, within Host process.
 // Raw lines are immediately reduced to fixed categories, safe basename and
 // a local ordinal. The remote call ID and original args never enter IPC.
 public void ObservedToolLine(string raw){
  lock(gate){
   if(disposed||!observedMode)return;
   string next;
   string category=SafeRemoteMarker(raw??"",out next);
   if(!category.StartsWith("Remote tool ",StringComparison.Ordinal))return;
   string safe=toolJournal.Format(raw,category);
   if(safe=="")return;
   remoteSupervisor.AddObservedMarker(safe);
   Append("remote","sanitized observed tool event");
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
     {"deviceManagementLink",observedMode||managedMode},{"deviceVerificationLink",false},
     {"sanitizedJournal",true},{"about",true},
     {"startRemote",managedMode && accountLogoutProcess==null && (managedProcess==null||!managedProcess.Running)},
     {"stopRemote",managedMode && accountLogoutProcess==null && managedProcess!=null&&managedProcess.Running},
     {"reconnectRemote",managedMode && accountLogoutProcess==null && managedProcess!=null&&managedProcess.Running},
     {"switchAccount",managedMode && !observedMode && trialRoot==null &&
       accountLogoutProcess==null && !accountSwitchFaultLatched &&
       managedProcess!=null && managedProcess.Running && managedState=="Ready"},
     {"update",false},{"fullExit",managedMode && accountLogoutProcess==null},
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
    // RC1 device verification happens in the official browser authorization flow;
    // no separate manual verification route is offered.
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
    if(accountLogoutProcess!=null)return Error(requestId,"ACCOUNT_CHANGE_IN_PROGRESS");
    if(action=="UPDATE")return Error(requestId,"REMOTE_ACTION_NOT_SAFELY_IMPLEMENTED");
    try{
     if(action=="SWITCH_ACCOUNT")BeginManagedAccountSwitch();
     else if(action=="START")StartManagedRemote();
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
   pulse.Stop();pulse.Dispose();
   trayFrameTimer.Stop();trayFrameTimer.Dispose();
   tray.Visible=false;tray.Dispose();
   if(trayVisual!=null){trayVisual.Dispose();trayVisual=null;}
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
   if(accountLogoutProcess!=null)accountLogoutProcess.Dispose();
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
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool IsWindow(IntPtr h);
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool IsWindowVisible(IntPtr h);
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool IsIconic(IntPtr h);
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern IntPtr GetForegroundWindow();
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [System.Runtime.InteropServices.DllImport("user32.dll",CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
 public static extern int GetWindowText(IntPtr h,System.Text.StringBuilder text,int count);
 public delegate bool EnumWindowCallback(IntPtr h,IntPtr data);
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool EnumWindows(EnumWindowCallback callback,IntPtr data);
 // Process.MainWindowHandle is zero for a legitimate hidden WinForms form.
 // Find the exact owned top-level RDC Relay window; never enumerate by name
 // alone or activate another process's window.
 public static IntPtr FindOwnedWindow(int expectedPid) {
  if(expectedPid<=0)return IntPtr.Zero;
  IntPtr result=IntPtr.Zero;
  EnumWindows(delegate(IntPtr h,IntPtr data){
   uint pid=0;
   if(GetWindowThreadProcessId(h,out pid)==0||pid!=(uint)expectedPid)return true;
   var title=new System.Text.StringBuilder(160);
   GetWindowText(h,title,title.Capacity);
   // A modal About/Journal window must not be mistaken for the main GUI.
   // Owner GUI changes its caption after authenticated HELLO.
   // Accept only the release-specific top-level main window, never the
   // versionless About/Journal modal or another titled window in the PID.
   if(!title.ToString().StartsWith("RDC Relay 1.6.0 RC1",StringComparison.Ordinal))return true;
   result=h;return false;
  },IntPtr.Zero);
  return result;
 }
 [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
 public struct FlashInfo {
  public uint cbSize;public IntPtr hwnd;public uint dwFlags,dwCount,dwTimeout;
 }
 [System.Runtime.InteropServices.DllImport("user32.dll")]
 public static extern bool FlashWindowEx(ref FlashInfo info);
 public static string OpenOwned(IntPtr handle,int expectedPid) {
  if(handle==IntPtr.Zero || !IsWindow(handle))return "NO_WINDOW";
  uint windowPid=0;
  if(GetWindowThreadProcessId(handle,out windowPid)==0 ||
     windowPid!=(uint)expectedPid)return "NOT_OWNED";
  // Restore only when minimized/hidden. An already visible GUI is not
  // forcibly repositioned or made topmost, especially over fullscreen apps.
  if(IsIconic(handle)||!IsWindowVisible(handle))ShowWindow(handle,9);
  bool accepted=SetForegroundWindow(handle);
  IntPtr foreground=GetForegroundWindow();
  uint foregroundPid=0;
  if(foreground!=IntPtr.Zero)GetWindowThreadProcessId(foreground,out foregroundPid);
  if(accepted && (foreground==handle||foregroundPid==(uint)expectedPid))
   return "VISIBLE";
  if(foreground==handle||foregroundPid==(uint)expectedPid)return "VISIBLE";
  // Win32 foreground lock can deny the call. Signal taskbar attention instead
  // of injecting Alt, forcing TopMost, retrying forever or killing the GUI.
  var flash=new FlashInfo{cbSize=(uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(FlashInfo)),
   hwnd=handle,dwFlags=2,dwCount=3,dwTimeout=0}; // FLASHW_TRAY, bounded
  FlashWindowEx(ref flash);
  return "ATTENTION";
 }
}

// Multi-size PNG-backed Windows icons derived only from the owner-approved tray
// 04 package. One cached Icon per frame: no Bitmap or HICON allocation on ticks.
public sealed class RdcOwnerTrayVisual : IDisposable {
 readonly NotifyIcon tray;
 readonly Dictionary<string,Icon> icons=new Dictionary<string,Icon>(StringComparer.Ordinal);
 readonly List<MemoryStream> streams=new List<MemoryStream>();
 readonly Stopwatch phase=Stopwatch.StartNew();
 DateTime nextMotionQueryUtc=DateTime.MinValue;
 bool animate=true,disposed=false;
 string semantic="",shownFrame="",shownTip="";
 const int WorkPulseMs=1800, SwapMs=800;
 static readonly string[] keys={
  "offline","connecting-a","connecting-b","auth-a","auth-b","ready","fault",
  "work-00","work-01","work-02","work-03","work-04","work-05",
  "work-06","work-07","work-08","work-09",
  "connecting-ab-25","connecting-ab-50","connecting-ab-75",
  "connecting-ba-25","connecting-ba-50","connecting-ba-75",
  "auth-ab-25","auth-ab-50","auth-ab-75",
  "auth-ba-25","auth-ba-50","auth-ba-75"
 };
 [System.Runtime.InteropServices.DllImport("user32.dll",CharSet=System.Runtime.InteropServices.CharSet.Auto)]
 static extern bool SystemParametersInfo(uint action,uint param,out bool enabled,uint flags);
 static bool MotionEnabled(){
  bool enabled=false;
  // SPI_GETCLIENTAREAANIMATION. Fall back to a static icon if unavailable.
  return SystemParametersInfo(0x1042,0,out enabled,0) && enabled;
 }
 public static RdcOwnerTrayVisual Load(string sourceRoot,NotifyIcon target) {
  string path=Path.Combine(sourceRoot,"RdcTrayV04.bin");
  if(!File.Exists(path))return null; // legacy/incomplete fake-only fixtures
  if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)
   throw new InvalidDataException("RC1_TRAY_REPARSE_DENIED");
  return new RdcOwnerTrayVisual(path,target);
 }
 RdcOwnerTrayVisual(string path,NotifyIcon target) {
  if(target==null)throw new ArgumentNullException("target");
  tray=target;
  try{
   var info=new FileInfo(path);
   if(info.Length<100||info.Length>4194304)throw new InvalidDataException("RC1_TRAY_BUNDLE_SIZE");
   // Attest the owner's approved v04 binary before handing icons to Win32.
   const string approvedSha="607D271A09983A407F3E8CC8560A93DC59385C18DCEC08ECA1740318C2B1AD59";
   using(var hashStream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)){
    var hasher=new System.Security.Cryptography.SHA256Managed();
    string actual=BitConverter.ToString(hasher.ComputeHash(hashStream)).Replace("-","");
    if(actual!=approvedSha)throw new InvalidDataException("RC1_TRAY_APPROVED_SHA_MISMATCH");
   }
   using(var reader=new BinaryReader(new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))){
    if(Encoding.ASCII.GetString(reader.ReadBytes(8))!="RDCTRAY4"||
       reader.ReadUInt16()!=1||reader.ReadByte()!=keys.Length)
     throw new InvalidDataException("RC1_TRAY_BUNDLE_HEADER");
    for(int i=0;i<keys.Length;i++){
     int nameLength=reader.ReadByte();
     if(nameLength<1||nameLength>40)throw new InvalidDataException("RC1_TRAY_NAME_LENGTH");
     string name=Encoding.ASCII.GetString(reader.ReadBytes(nameLength));
     if(name!=keys[i])throw new InvalidDataException("RC1_TRAY_ASSET_ORDER");
     int size=reader.ReadInt32();
     if(size<100||size>1048576)throw new InvalidDataException("RC1_TRAY_ICON_BYTES");
     byte[] ico=reader.ReadBytes(size);
     if(ico.Length!=size||ico[0]!=0||ico[1]!=0||ico[2]!=1||ico[3]!=0||
        ico[4]!=8||ico[5]!=0)throw new InvalidDataException("RC1_TRAY_ICON_FORMAT");
     var backing=new MemoryStream(ico,false);
     streams.Add(backing);
     // Use the actual Windows notification-area small-icon metric (16px
     // at 100%, commonly 20/24px at higher DPI), not a default 32px HICON.
     icons.Add(name,new Icon(backing,SystemInformation.SmallIconSize));
    }
    if(reader.BaseStream.Position!=reader.BaseStream.Length)
     throw new InvalidDataException("RC1_TRAY_BUNDLE_EXTRA_BYTES");
   }
   animate=MotionEnabled();
   nextMotionQueryUtc=DateTime.UtcNow.AddSeconds(5);
  }catch{Dispose();throw;}
 }
 public static string Semantic(string connection,string activity) {
  // Source is the authoritative sanitized Remote supervisor snapshot.
  // Fault and disconnected override any stale tool activity.
  if(connection=="Fault")return "fault";
  if(connection=="Connecting"||connection=="Reconnecting")return "connecting";
  if(connection=="AuthPending")return "auth";
  if(connection=="Ready")return activity=="working"?"working":"ready";
  return "offline";
 }
 static string SwapFrame(string prefix,bool motion,long elapsedMs){
  if(!motion)return prefix+"-a";
  // Mirrors preview CSS: 1.6s cycle, color interpolation at 40-50%
  // and 90-100% (160ms), sampled at 40ms from cached 25/50/75% ICOs.
  long position=elapsedMs%(2*SwapMs);
  if(position<680)return prefix+"-a";
  if(position<720)return prefix+"-ab-25";
  if(position<760)return prefix+"-ab-50";
  if(position<800)return prefix+"-ab-75";
  if(position<1480)return prefix+"-b";
  if(position<1520)return prefix+"-ba-25";
  if(position<1560)return prefix+"-ba-50";
  return prefix+"-ba-75";
 }
 public static string Frame(string state,bool motion,long elapsedMs) {
  if(state=="connecting"||state=="auth")return SwapFrame(state,motion,elapsedMs);
  if(state=="working"){
   if(!motion)return "work-09";
   // CSS 0/100%=100%, midpoint=45%, ease-in-out. Cached levels
   // approximate the preview easing without constructing a new icon.
   double position=(elapsedMs%WorkPulseMs)/900.0;
   if(position>1.0)position=2.0-position;
   double eased=(1.0-Math.Cos(Math.PI*position))/2.0;
   int index=Math.Max(0,Math.Min(9,(int)Math.Round(9.0*(1.0-eased))));
   return "work-"+index.ToString("D2");
  }
  if(state=="ready"||state=="fault")return state;
  return "offline";
 }
 static string ShortStatus(string state){
  switch(state){
   case "connecting":return "Подключение";
   case "auth":return "Авторизация";
   case "ready":return "Готов к работе";
   case "working":return "Выполнение";
   case "fault":return "Ошибка соединения";
   default:return "Отключён";
  }
 }
 public void Update(Dictionary<string,object> snapshot){
  if(disposed||snapshot==null)return;
  string connection=snapshot.ContainsKey("state")?
   Convert.ToString(snapshot["state"]):"Disconnected";
  string activity=snapshot.ContainsKey("toolActivity")?
   Convert.ToString(snapshot["toolActivity"]):"idle";
  string next=Semantic(connection,activity);
  if(next!=semantic){semantic=next;phase.Restart();}
  Advance();
  // No rapid text/tooltip churn while drawing animated frames.
  bool fake=snapshot.ContainsKey("fake")&&Convert.ToBoolean(snapshot["fake"]);
  string tip="RDC Relay RC1 | "+(fake?"Тест | ":"")+ShortStatus(semantic);
  if(tip!=shownTip){
   tray.Text=tip.Length<=63?tip:tip.Substring(0,63);
   shownTip=tip;
  }
 }
 public void Advance(){
  if(disposed || String.IsNullOrEmpty(semantic))return;
  if(DateTime.UtcNow>=nextMotionQueryUtc){
   bool nextMotion=MotionEnabled();
   if(nextMotion!=animate){animate=nextMotion;phase.Restart();}
   nextMotionQueryUtc=DateTime.UtcNow.AddSeconds(5);
  }
  string frame=Frame(semantic,animate,phase.ElapsedMilliseconds);
  if(frame!=shownFrame){
   Icon icon;
   if(!icons.TryGetValue(frame,out icon))throw new InvalidDataException("RC1_TRAY_FRAME_MISSING");
   tray.Icon=icon;
   shownFrame=frame;
  }
 }
 public void Dispose(){
  if(disposed)return;
  disposed=true;
  foreach(var icon in icons.Values)try{icon.Dispose();}catch{}
  icons.Clear();
  foreach(var stream in streams)try{stream.Dispose();}catch{}
  streams.Clear();
 }
}
