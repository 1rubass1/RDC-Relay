// ARCH-016-P1 fake-only state authority and disposable WinForms Tray Host.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using System.Drawing;
using System.Web.Script.Serialization;
public sealed class P1Core : IDisposable {
  readonly object sync=new object();
  readonly string root, guiFile, instance, ctlFile;
  readonly bool interactiveDemo;
  int trayActivations=0;
  readonly int controllerPid,controllerSession;
  readonly long controllerTicks;
  readonly string gen=Guid.NewGuid().ToString("N"),remote=Guid.NewGuid().ToString("N"),hostId=Guid.NewGuid().ToString("N");
  readonly string ctlNonce=Guid.NewGuid().ToString("N");
  readonly int replayLimit;
  readonly bool failAclForTests,failGuiTicketForTests;
  long lastCtlSeq=0,lastGuiSeq=0;
  int ctlEpoch=0,guiEpoch=0;
  readonly List<Dictionary<string,object>> events=new List<Dictionary<string,object>>();
  readonly HashSet<string> seenCtl=new HashSet<string>(),seenGui=new HashSet<string>();
  readonly ApplicationContext context=new ApplicationContext();
  readonly NotifyIcon icon=new NotifyIcon();
  readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
  P1Server guiServer,ctlServer;
  Process child;
  int guiPid=0,guiSession=0,guiStarts=0,guiCloses=0,guiFailures=0,guiConnected=0,revision=1,seq=0,tick=0,closeGen=0;
  long guiTicks=0;
  string guiNonce="",guiVersion="",state="NONE";
  bool stopRequested=false,drop=false,needSnapshot=false,suspendEvents=false;
  int guiGapReports=0,guiResyncSnapshots=0;
  Mutex onlyHost;
  public P1Core(string dir,string gui,string id,int parentPid,long parentTicks)
    : this(dir,gui,id,parentPid,parentTicks,8192,false,false,false) {}
  public P1Core(string dir,string gui,string id,int parentPid,long parentTicks,int epochLimit,bool simulateAclFailure,bool showInteractiveTray)
    : this(dir,gui,id,parentPid,parentTicks,epochLimit,simulateAclFailure,showInteractiveTray,false) {}
  public P1Core(string dir,string gui,string id,int parentPid,long parentTicks,int epochLimit,bool simulateAclFailure,bool showInteractiveTray,bool failTicketBeforeWrite) {
    interactiveDemo=showInteractiveTray;
    if(epochLimit<4||epochLimit>8192)throw new ArgumentOutOfRangeException("epochLimit");
    replayLimit=epochLimit;failAclForTests=simulateAclFailure;failGuiTicketForTests=failTicketBeforeWrite;
    root=CanonicalDirectory(dir);
    guiFile=Path.GetFullPath(gui);
    instance=id;controllerPid=parentPid;controllerTicks=parentTicks;controllerSession=P1Wire.Session(parentPid);
    ctlFile=Path.Combine(root,"controller-auth.json");
    if(!System.Text.RegularExpressions.Regex.IsMatch(id,@"^[0-9a-f]{32}$")||!IsSafeFixturePath(root,guiFile))
      throw new InvalidOperationException("DISPOSABLE_ROOT_ONLY");
    bool created;
    onlyHost=new Mutex(true,@"Local\rdc-p2-host-"+id,out created);
    if(!created)throw new InvalidOperationException("HOST_ALREADY_RUNNING");
  }
  static string CanonicalDirectory(string path){
    string full=Path.GetFullPath(path);
    string volume=Path.GetPathRoot(full);
    return full.Length>volume.Length?full.TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar):full;
  }
  static bool IsSameOrChildPath(string parent,string candidate){
    string p=CanonicalDirectory(parent);
    string c=Path.GetFullPath(candidate);
    if(String.Equals(p,c,StringComparison.OrdinalIgnoreCase))return true;
    string prefix=p.EndsWith(Path.DirectorySeparatorChar.ToString(),StringComparison.Ordinal)?p:p+Path.DirectorySeparatorChar;
    return c.StartsWith(prefix,StringComparison.OrdinalIgnoreCase);
  }
  static bool HasReparsePointInPath(string path,bool allowMissingLeaf){
    string current=Path.GetFullPath(path);
    string volume=Path.GetPathRoot(current);
    bool leaf=true;
    while(!String.IsNullOrEmpty(current)){
      try{
        if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)return true;
      }catch{
        if(!(leaf&&allowMissingLeaf))return true;
        string parent=Path.GetDirectoryName(current);
        if(String.IsNullOrEmpty(parent)||!Directory.Exists(parent))return true;
        string name=Path.GetFileName(current);
        string[] entries;
        try{entries=Directory.GetFileSystemEntries(parent);}catch{return true;}
        foreach(string entry in entries){
          if(String.Equals(Path.GetFileName(entry),name,StringComparison.OrdinalIgnoreCase))return true;
        }
      }
      if(String.Equals(current,volume,StringComparison.OrdinalIgnoreCase))break;
      string next=Path.GetDirectoryName(current);
      if(String.IsNullOrEmpty(next)||String.Equals(next,current,StringComparison.OrdinalIgnoreCase))return true;
      current=next;leaf=false;
    }
    return false;
  }
  static bool IsSafeFixtureRoot(string dir){
    try{
      string full=CanonicalDirectory(dir);
      string temp=CanonicalDirectory(Path.GetTempPath());
      if(!Directory.Exists(full))return false;
      if(!String.Equals(Path.GetDirectoryName(full),temp,StringComparison.OrdinalIgnoreCase))return false;
      if(!System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(full),@"^RDC-P2-[0-9a-f]{32}$"))return false;
      return !HasReparsePointInPath(full,false);
    }catch{return false;}
  }
  static bool IsSafeFixturePath(string dir,string gui){
    try{
      string fullRoot=CanonicalDirectory(dir);
      string fullGui=Path.GetFullPath(gui);
      if(!IsSafeFixtureRoot(fullRoot))return false;
      if(!String.Equals(fullGui,Path.Combine(fullRoot,"Gui.ps1"),StringComparison.OrdinalIgnoreCase))return false;
      if(!File.Exists(fullGui)||(File.GetAttributes(fullGui)&FileAttributes.Directory)!=0)return false;
      return !HasReparsePointInPath(fullGui,false);
    }catch{return false;}
  }
  static bool IsSafeFixtureChildPath(string dir,string path,string expectedName,bool allowMissingLeaf){
    try{
      string fullRoot=CanonicalDirectory(dir);
      string fullPath=Path.GetFullPath(path);
      if(!IsSafeFixtureRoot(fullRoot))return false;
      if(!String.Equals(Path.GetDirectoryName(fullPath),fullRoot,StringComparison.OrdinalIgnoreCase))return false;
      if(!String.Equals(Path.GetFileName(fullPath),expectedName,StringComparison.OrdinalIgnoreCase))return false;
      return !HasReparsePointInPath(fullPath,allowMissingLeaf);
    }catch{return false;}
  }
  static bool ContainsReparsePoint(string dir,string path){
    return ContainsReparsePoint(dir,path,false);
  }
  static bool ContainsReparsePoint(string dir,string path,bool allowMissingLeaf){
    try{
      string fullRoot=CanonicalDirectory(dir);
      string fullPath=Path.GetFullPath(path);
      if(!IsSafeFixtureRoot(fullRoot)||!IsSameOrChildPath(fullRoot,fullPath))return true;
      return HasReparsePointInPath(fullPath,allowMissingLeaf);
    }catch{return true;}
  }
  void PrivateFile(string path,string json){
    string name=Path.GetFileName(path);
    if((name!="controller-auth.json"&&name!="gui-ticket.json")||
       !IsSafeFixturePath(root,guiFile)||
       !IsSafeFixtureChildPath(root,path,name,true))
      throw new UnauthorizedAccessException("UNSAFE_FIXTURE_FILE");
    // ACL is built and validated BEFORE opening/creating the file. Windows
    // FileStream(CreateNew,...,FileSecurity) applies the DACL at creation.
    // Never write secrets to an inherited-ACL file then attempt to tighten.
    FileSecurity acl=new FileSecurity();acl.SetAccessRuleProtection(true,false);
    var sid=new SecurityIdentifier(P1Wire.LogonSid());
    acl.AddAccessRule(new FileSystemAccessRule(sid,FileSystemRights.FullControl,AccessControlType.Allow));
    acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid,null),FileSystemRights.Read,AccessControlType.Deny));
    if(failAclForTests)throw new UnauthorizedAccessException("SIMULATED_ACL_BEFORE_CREATE");
    string temp=Path.GetFullPath(path+"."+Guid.NewGuid().ToString("N")+".secured");
    try{
      if(!IsSafeFixturePath(root,guiFile)||
         !IsSafeFixtureChildPath(root,path,name,true)||
         !IsSafeFixtureChildPath(root,temp,Path.GetFileName(temp),true))
        throw new UnauthorizedAccessException("UNSAFE_FIXTURE_FILE");
      byte[] raw=new System.Text.UTF8Encoding(false,true).GetBytes(json);
      using(FileStream stream=new FileStream(temp,FileMode.CreateNew,FileSystemRights.Write,
           FileShare.None,4096,FileOptions.WriteThrough,acl)){
        stream.Write(raw,0,raw.Length);stream.Flush(true);
      }
      if(!IsSafeFixtureChildPath(root,temp,Path.GetFileName(temp),false)||
         !IsSafeFixtureChildPath(root,path,name,true))
        throw new UnauthorizedAccessException("UNSAFE_FIXTURE_FILE");
      if(File.Exists(path)){
        // Atomic swap to an already-private file; do not transiently expose
        // the new nonce via an inherited-ACL path.
        File.Replace(temp,path,null);
      }else{
        File.Move(temp,path);
      }
    }finally{
      // Never follow a redirected root while cleaning a temporary path.
      try{if(!ContainsReparsePoint(root,temp,true)&&File.Exists(temp))File.Delete(temp);}catch{}
    }
  }
  Dictionary<string,object> Snapshot() {
    return new Dictionary<string,object> {
      {"ok",true},{"protocol",1},{"hostPid",Process.GetCurrentProcess().Id},{"hostGeneration",gen},{"hostId",hostId},
      {"remoteId",remote},{"fake",true},{"remote",new Dictionary<string,object>{
        {"fake",true},{"ownership","unknown"},{"processAlive","unknown"},{"transportReady","unknown"},
        {"authState","unknown"},{"toolActivity","idle"},{"fault",null}}},
      {"tick",tick},{"revision",revision},{"lastEventSeq",seq},{"guiPid",guiPid},
      {"guiBuild",guiVersion},{"guiStarts",guiStarts},{"guiCloses",guiCloses},
      {"guiFailures",guiFailures},{"guiConnected",guiConnected==1},{"guiState",state},
      {"closeGeneration",closeGen},{"eventCount",events.Count},
      {"guiWorkerActive",guiServer==null?0:guiServer.Active},{"guiWorkerPeak",guiServer==null?0:guiServer.PeakActive},{"guiRejected",guiServer==null?0:guiServer.Rejected},
      {"ctlTimeouts",ctlServer==null?0:ctlServer.Timeouts},{"lastEventTextLen",events.Count>0?((string)events[events.Count-1]["text"]).Length:0},
      {"trayVisible",interactiveDemo},{"trayActivations",trayActivations},
      {"guiTimeouts",guiServer==null?0:guiServer.Timeouts},{"guiGapReports",guiGapReports},{"guiResyncSnapshots",guiResyncSnapshots},
      {"replayLimit",replayLimit},{"controllerEpoch",ctlEpoch},{"guiEpoch",guiEpoch},{"controllerLastSeq",lastCtlSeq},{"guiLastSeq",lastGuiSeq}
    };
  }
  static string Err(string code,string id){
    return P1Wire.Json.Serialize(new {type="ERROR",protocol=1,requestId=id,code=code});
  }
  string Ok(string type,string requestId,object body){
    return P1Wire.Json.Serialize(new {type=type,protocol=1,requestId=requestId,payload=body});
  }
  void Event(string source,string message) {
    seq++;revision++;
    events.Add(new Dictionary<string,object>{{"sequence",seq},{"source",source},{"text",message.Length>100?message.Substring(0,100):message},{"utc",DateTime.UtcNow.ToString("o")}});
    if(events.Count>256)events.RemoveAt(0);
  }
  void RefreshChild(){
    if(child!=null&&child.HasExited){
      if(guiConnected==0&&state=="SPAWNING")guiFailures++;
      guiCloses++;
      child.Dispose();child=null;guiPid=0;guiTicks=0;guiNonce="";guiConnected=0;guiVersion="";state="NONE";
      lastGuiSeq=0;guiEpoch=0;seenGui.Clear();
      Event("gui","exited");
    }
  }
  void ClearGuiLaunchState(){
    guiPid=0;guiTicks=0;guiSession=0;guiConnected=0;guiNonce="";guiVersion="";state="NONE";
    lastGuiSeq=0;guiEpoch=0;seenGui.Clear();
  }
  void Open() {
    RefreshChild();
    if(child!=null)return;
    // Validate the exact direct-child fixture and every path component before
    // ticket creation, then repeat immediately before starting the GUI process.
    if(!IsSafeFixturePath(root,guiFile)){
      guiFailures++;ClearGuiLaunchState();Event("gui","unsafe-path-refused");return;
    }
    string ticket=Path.Combine(root,"gui-ticket.json");
    guiNonce=Guid.NewGuid().ToString("N");
    var identity=new Dictionary<string,object>{{"pipe","rdc-p2-gui-"+instance},
      {"hostPid",Process.GetCurrentProcess().Id},{"hostTicks",P1Wire.Born(Process.GetCurrentProcess().Id)},
      {"hostSession",P1Wire.Session(Process.GetCurrentProcess().Id)},{"hostGeneration",gen},{"nonce",guiNonce}};
    bool ticketCreated=false;
    try{
      if(!IsSafeFixturePath(root,guiFile)||
         !IsSafeFixtureChildPath(root,ticket,"gui-ticket.json",true))
        throw new UnauthorizedAccessException("UNSAFE_FIXTURE_PATH");
      // Test-only fault is injected before serialization, temp-file creation,
      // ACL/file creation, or any ticket bytes are written.
      if(failGuiTicketForTests)
        throw new UnauthorizedAccessException("SIMULATED_GUI_TICKET_CREATE_FAILURE");
      PrivateFile(ticket,P1Wire.Json.Serialize(identity));
      ticketCreated=true;
    }catch{
      // Ticket creation failures are a controlled state transition. The
      // exception and nonce are never logged or propagated to tray/IPC callers.
      guiFailures++;ClearGuiLaunchState();Event("gui","launch-failed");return;
    }
    Process started=null;
    try{
      if(!IsSafeFixturePath(root,guiFile)||
         !IsSafeFixtureChildPath(root,ticket,"gui-ticket.json",false))
        throw new UnauthorizedAccessException("UNSAFE_FIXTURE_PATH");
      ProcessStartInfo psi=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"),
        "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \""+guiFile+"\" -TicketPath \""+ticket+"\""+(interactiveDemo?"":" -TestMode"));
      psi.UseShellExecute=false;psi.CreateNoWindow=true;
      started=Process.Start(psi);
      if(started==null)throw new InvalidOperationException("GUI_START");
      child=started;
      guiPid=child.Id;guiTicks=child.StartTime.ToUniversalTime().Ticks;guiSession=child.SessionId;
      guiStarts++;state="SPAWNING";Event("gui","spawned");
    }catch{
      guiFailures++;
      if(started==null){
        child=null;ClearGuiLaunchState();
        if(ticketCreated){
          try{if(!ContainsReparsePoint(root,ticket,false)&&File.Exists(ticket))File.Delete(ticket);}catch{}
        }
      }else{
        // If process creation succeeded but later metadata retrieval failed,
        // retain ownership rather than losing a live child reference.
        child=started;
        try{guiPid=started.Id;guiTicks=started.StartTime.ToUniversalTime().Ticks;guiSession=started.SessionId;}catch{guiPid=started.Id;}
        state="SPAWNING";
      }
      Event("gui","launch-failed");
    }
  }
  bool Registered(int pid,int session){
    if(pid==0||pid!=guiPid||session!=guiSession||child==null||child.HasExited)return false;
    try{return P1Wire.Born(pid)==guiTicks;}catch{return false;}
  }
  bool Controller(int pid,int session){
    if(pid!=controllerPid||session!=controllerSession)return false;
    try{return P1Wire.Born(pid)==controllerTicks;}catch{return false;}
  }
  string Dispatch(Dictionary<string,object> req,int pid,int session,bool control){
    lock(sync){
      RefreshChild();
      string verb=P1Wire.String(req,"type"),id=P1Wire.String(req,"requestId");
      if(P1Wire.Number(req,"protocol")!=1)return Err("VERSION",id);
      if(id.Length!=32||!System.Text.RegularExpressions.Regex.IsMatch(id,"^[a-f0-9]{32}$"))return Err("REQUEST_ID",id);
      if(control){
        if(!Controller(pid,session)||P1Wire.String(req,"nonce")!=ctlNonce)return Err("UNAUTHORIZED",id);
      }else{
        if(!Registered(pid,session)||P1Wire.String(req,"nonce")!=guiNonce)return Err("UNAUTHORIZED",id);
      }
      if(P1Wire.String(req,"hostGeneration")!=gen)return Err("STALE_GENERATION",id);
      // Sequence is monotonic per verified OS client. Epoch = floor((seq-1)/N).
      // An old-epoch request is ALWAYS rejected by lastSeq, even after the
      // bounded per-epoch requestId ledger rotates. A reused requestId with a
      // freshly forged sequence fails the requestId/sequence binding.
      long sequence=P1Wire.Number(req,"requestSequence");
      long prior=control?lastCtlSeq:lastGuiSeq;
      if(sequence<=prior)return Err("REPLAY",id);
      if(sequence<=0||sequence==long.MaxValue||sequence-prior>1000000)return Err("INVALID_SEQUENCE",id);
      if(id.Substring(0,16)!=sequence.ToString("x16"))return Err("REQUEST_ID_SEQUENCE",id);
      int epoch=checked((int)((sequence-1)/replayLimit));
      HashSet<string> ledger=control?seenCtl:seenGui;
      int priorEpoch=control?ctlEpoch:guiEpoch;
      if(epoch<priorEpoch)return Err("STALE_EPOCH",id);
      if(epoch>priorEpoch){ledger.Clear();if(control)ctlEpoch=epoch;else guiEpoch=epoch;}
      if(!ledger.Add(id))return Err("REPLAY",id);
      if(control)lastCtlSeq=sequence;else lastGuiSeq=sequence;
      if(control){
        if(verb=="TEST_STATE")return Ok("SNAPSHOT",id,Snapshot());
        if(verb=="TEST_LAST_EVENT"){
          object last=events.Count>0?(object)events[events.Count-1]:null;
          return Ok("EVENT",id,last);
        }
        if(verb=="TEST_OPEN"){Open();return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_TRAY_DOUBLE_CLICK"){TrayOpen();return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_CLOSE"){closeGen++;return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_EVENT"){Event("fixture","synthetic");return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_LARGE_EVENT"){Event("fixture",new string('X',200000));return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_END"){
          if(guiPid!=0)return Err("GUI_STILL_ALIVE",id);
          stopRequested=true;return Ok("ACK",id,Snapshot());
        }
        if(verb=="TEST_DROP"){drop=true;return Ok("ACK",id,Snapshot());}
        if(verb=="TEST_BLOCK_EVENTS"){suspendEvents=true;return Ok("ACK",id,Snapshot());}
        if(verb=="TEST_UNBLOCK_EVENTS"){suspendEvents=false;return Ok("ACK",id,Snapshot());}
        return Err("NOT_ALLOWED",id);
      }
      if(verb=="HELLO"){
        if(!System.Text.RegularExpressions.Regex.IsMatch(P1Wire.String(req,"guiBuild"),@"^[A-Za-z0-9_-]{1,24}$"))return Err("INVALID_BUILD",id);
        if(guiConnected==1)return Err("DUPLICATE",id);
        guiConnected=1;guiVersion=P1Wire.String(req,"guiBuild");
        state="ATTACHED";Event("gui","attached");
        return Ok("WELCOME",id,Snapshot());
      }
      if(guiConnected!=1)return Err("NEED_HELLO",id);
      if(verb=="GET_SNAPSHOT"){
        if(drop){drop=false;throw new IOException("TEST_DROP_REPLY");}
        if(needSnapshot){guiResyncSnapshots++;needSnapshot=false;}
        return Ok("SNAPSHOT",id,Snapshot());
      }
      if(verb=="GET_EVENTS"){
        if(suspendEvents)return Err("TEMP_UNAVAILABLE",id);
        long after=P1Wire.Number(req,"afterSequence",0);
        if(after<0)return Err("SEQUENCE",id);
        bool gap=events.Count>0&&after<Convert.ToInt64(events[0]["sequence"])-1;
        if(gap){guiGapReports++;needSnapshot=true;}
        var batch=new List<Dictionary<string,object>>();
        foreach(var e in events){if(Convert.ToInt64(e["sequence"])>after&&batch.Count<128)batch.Add(e);}
        return Ok("EVENT_BATCH",id,new {hostGeneration=gen,revision=revision,lastEventSeq=seq,
          gap=gap,moreAvailable=batch.Count>0&&Convert.ToInt64(batch[batch.Count-1]["sequence"])<seq,events=batch});
      }
      if(verb=="DETACH"){guiConnected=0;state="CLOSING";return Ok("ACK",id,Snapshot());}
      return Err("NOT_ALLOWED",id);
    }
  }
  string Gui(Dictionary<string,object> msg,int pid,int session){return Dispatch(msg,pid,session,false);}
  string Control(Dictionary<string,object> msg,int pid,int session){return Dispatch(msg,pid,session,true);}
  void TrayOpen(){
    trayActivations++;RefreshChild();
    if(child!=null&&interactiveDemo){
      icon.BalloonTipTitle="RDC P2 SANDBOX";
      icon.BalloonTipText="Demo GUI is already open. No duplicate was started.";
      icon.ShowBalloonTip(1200);
    }
    Open();
  }
  public void Run() {
    PrivateFile(ctlFile,P1Wire.Json.Serialize(new Dictionary<string,object>{
      {"pipe","rdc-p2-ctl-"+instance},{"hostPid",Process.GetCurrentProcess().Id},
      {"hostTicks",P1Wire.Born(Process.GetCurrentProcess().Id)},
      {"hostSession",P1Wire.Session(Process.GetCurrentProcess().Id)},
      {"hostGeneration",gen},{"nonce",ctlNonce}}));
    guiServer=new P1Server("rdc-p2-gui-"+instance,Gui);
    ctlServer=new P1Server("rdc-p2-ctl-"+instance,Control);
    guiServer.Start();ctlServer.Start();
    icon.Icon=SystemIcons.Information;
    icon.Text="RDC Relay P2 SANDBOX - fake Remote";
    var menu=new ContextMenuStrip();
    var launch=new ToolStripMenuItem("Open demo GUI");
    launch.Click+=(s,e)=>{lock(sync){TrayOpen();}};
    menu.Items.Add(launch);
    var info=new ToolStripMenuItem("Fake Remote / no real connection");
    info.Enabled=false;menu.Items.Add(info);
    var exit=new ToolStripMenuItem("Stop P2 test Host (close GUI first)");
    exit.Click+=(s,e)=>{lock(sync){
      RefreshChild();
      if(child==null)stopRequested=true;
      else if(interactiveDemo){
        icon.BalloonTipTitle="P2 test Host remains active";
        icon.BalloonTipText="Close the demo GUI with X before stopping its test Host.";
        icon.ShowBalloonTip(1200);
      }
    }};
    menu.Items.Add(exit);
    icon.ContextMenuStrip=menu;
    icon.Visible=interactiveDemo;
    icon.DoubleClick+=(s,e)=>{lock(sync){TrayOpen();}};
    timer.Interval=75;
    timer.Tick+=(s,e)=>{
      lock(sync){
        tick++;if(tick%4==0)Event("fake-heartbeat","tick");
        RefreshChild();
        if(stopRequested)context.ExitThread();
      }
    };
    timer.Start();
    if(interactiveDemo){lock(sync){TrayOpen();}}
    Application.Run(context);
  }
  public void Dispose(){
    timer.Stop();timer.Dispose();icon.Visible=false;if(icon.ContextMenuStrip!=null)icon.ContextMenuStrip.Dispose();icon.Dispose();
    if(guiServer!=null)guiServer.Dispose();if(ctlServer!=null)ctlServer.Dispose();
    if(child!=null){child.Dispose();} // no force close, fixture proves zero child before test End
    if(onlyHost!=null){onlyHost.ReleaseMutex();onlyHost.Dispose();}
    context.Dispose();
  }
}
