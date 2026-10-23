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
  readonly int controllerPid,controllerSession;
  readonly long controllerTicks;
  readonly string gen=Guid.NewGuid().ToString("N"),remote=Guid.NewGuid().ToString("N"),hostId=Guid.NewGuid().ToString("N");
  readonly string ctlNonce=Guid.NewGuid().ToString("N");
  readonly List<Dictionary<string,object>> events=new List<Dictionary<string,object>>();
  readonly HashSet<string> seen=new HashSet<string>();
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
  public P1Core(string dir,string gui,string id,int parentPid,long parentTicks) {
    root=Path.GetFullPath(dir).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
    guiFile=Path.GetFullPath(gui);
    instance=id;controllerPid=parentPid;controllerTicks=parentTicks;controllerSession=P1Wire.Session(parentPid);
    ctlFile=Path.Combine(root,"controller-auth.json");
    if(!System.Text.RegularExpressions.Regex.IsMatch(id,@"^[0-9a-f]{32}$")||
       !Path.GetFileName(root.TrimEnd(Path.DirectorySeparatorChar)).StartsWith("RDC-P1-",StringComparison.Ordinal)||
       !guiFile.StartsWith(root,StringComparison.OrdinalIgnoreCase)||!File.Exists(guiFile)||ContainsReparsePoint(root,guiFile))
      throw new InvalidOperationException("DISPOSABLE_ROOT_ONLY");
    bool created;
    onlyHost=new Mutex(true,@"Local\rdc-p1-host-"+id,out created);
    if(!created)throw new InvalidOperationException("HOST_ALREADY_RUNNING");
  }
  static bool ContainsReparsePoint(string root,string file){
    // Refuse junctions/symlinks anywhere on the disposable GUI path.
    string part=Path.GetFullPath(file);
    while(part.StartsWith(root,StringComparison.OrdinalIgnoreCase)){
      if((File.GetAttributes(part)&FileAttributes.ReparsePoint)!=0)return true;
      string parent=Path.GetDirectoryName(part);
      if(parent==null||parent==part)break;
      part=parent;
    }
    return false;
  }
  static void PrivateFile(string path,string json){
    File.WriteAllText(path,json,new System.Text.UTF8Encoding(false));
    FileSecurity acl=new FileSecurity();acl.SetAccessRuleProtection(true,false);
    var sid=new SecurityIdentifier(P1Wire.LogonSid());
    acl.AddAccessRule(new FileSystemAccessRule(sid,FileSystemRights.FullControl,AccessControlType.Allow));
    acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid,null),FileSystemRights.Read,AccessControlType.Deny));
    File.SetAccessControl(path,acl);
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
      {"guiWorkerActive",guiServer==null?0:guiServer.Active},{"guiRejected",guiServer==null?0:guiServer.Rejected},
      {"guiTimeouts",guiServer==null?0:guiServer.Timeouts},{"guiGapReports",guiGapReports},{"guiResyncSnapshots",guiResyncSnapshots}
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
      Event("gui","exited");
    }
  }
  void Open() {
    RefreshChild();
    if(child!=null)return;
    // Revalidate the disposable GUI path on EACH launch, not just Host boot.
    if(!File.Exists(guiFile)||!guiFile.StartsWith(root,StringComparison.OrdinalIgnoreCase)||
       ContainsReparsePoint(root,guiFile)){
      guiFailures++;Event("gui","unsafe-path-refused");return;
    }
    var ticket=Path.Combine(root,"gui-ticket.json");
    guiNonce=Guid.NewGuid().ToString("N");
    var identity=new Dictionary<string,object>{{"pipe","rdc-p1-gui-"+instance},
      {"hostPid",Process.GetCurrentProcess().Id},{"hostTicks",P1Wire.Born(Process.GetCurrentProcess().Id)},
      {"hostSession",P1Wire.Session(Process.GetCurrentProcess().Id)},{"hostGeneration",gen},{"nonce",guiNonce}};
    PrivateFile(ticket,P1Wire.Json.Serialize(identity));
    ProcessStartInfo psi=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"),
      "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \""+guiFile+"\" -TicketPath \""+ticket+"\" -TestMode");
    psi.UseShellExecute=false;psi.CreateNoWindow=true;
    try{
      child=Process.Start(psi);if(child==null)throw new InvalidOperationException("GUI_START");
      guiPid=child.Id;guiTicks=child.StartTime.ToUniversalTime().Ticks;guiSession=child.SessionId;
      guiStarts++;state="SPAWNING";Event("gui","spawned");
    }catch{guiFailures++;guiPid=0;state="NONE";Event("gui","launch-failed");}
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
      if(seen.Contains(id))return Err("REPLAY",id);
      // Fail closed if the bounded replay ledger is exhausted; never clear it
      // and silently authorize a previously seen requestId in this generation.
      if(seen.Count>=8192)return Err("REKEY_REQUIRED",id);
      seen.Add(id);
      if(control){
        if(verb=="TEST_STATE")return Ok("SNAPSHOT",id,Snapshot());
        if(verb=="TEST_OPEN"){Open();return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_CLOSE"){closeGen++;return Ok("SNAPSHOT",id,Snapshot());}
        if(verb=="TEST_EVENT"){Event("fixture","synthetic");return Ok("SNAPSHOT",id,Snapshot());}
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
  public void Run() {
    PrivateFile(ctlFile,P1Wire.Json.Serialize(new Dictionary<string,object>{
      {"pipe","rdc-p1-ctl-"+instance},{"hostPid",Process.GetCurrentProcess().Id},
      {"hostTicks",P1Wire.Born(Process.GetCurrentProcess().Id)},
      {"hostSession",P1Wire.Session(Process.GetCurrentProcess().Id)},
      {"hostGeneration",gen},{"nonce",ctlNonce}}));
    guiServer=new P1Server("rdc-p1-gui-"+instance,Gui);
    ctlServer=new P1Server("rdc-p1-ctl-"+instance,Control);
    guiServer.Start();ctlServer.Start();
    icon.Icon=SystemIcons.Application;icon.Text="RDC P1 fake-only IPC Host";icon.Visible=false;
    icon.DoubleClick+=(s,e)=>{lock(sync){Open();}};
    timer.Interval=75;
    timer.Tick+=(s,e)=>{
      lock(sync){
        tick++;if(tick%4==0)Event("fake-heartbeat","tick");
        RefreshChild();
        if(stopRequested)context.ExitThread();
      }
    };
    timer.Start();Application.Run(context);
  }
  public void Dispose(){
    timer.Stop();timer.Dispose();icon.Visible=false;icon.Dispose();
    if(guiServer!=null)guiServer.Dispose();if(ctlServer!=null)ctlServer.Dispose();
    if(child!=null){child.Dispose();} // no force close, fixture proves zero child before test End
    if(onlyHost!=null){onlyHost.ReleaseMutex();onlyHost.Dispose();}
    context.Dispose();
  }
}
