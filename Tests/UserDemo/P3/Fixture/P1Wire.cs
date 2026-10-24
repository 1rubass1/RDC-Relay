// ARCH-016-P1: fake-only, .NET Framework 4.x / Windows PowerShell 5.1.
// No production Remote commands. Server runs outside the WinForms message loop.
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Security.Principal;
using System.Security.AccessControl;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Web.Script.Serialization;

public static class P1Wire {
  public const int MaxRequest=8192, MaxResponse=65536, Timeout=1000;
  public static readonly JavaScriptSerializer Json=new JavaScriptSerializer(){MaxJsonLength=131072, RecursionLimit=16};
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetNamedPipeClientProcessId(SafePipeHandle handle,out uint id);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetNamedPipeClientSessionId(SafePipeHandle handle,out uint id);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetNamedPipeServerProcessId(SafePipeHandle handle,out uint id);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetNamedPipeServerSessionId(SafePipeHandle handle,out uint id);
  public static int PeerPid(PipeStream stream,bool server) {
    uint id;
    bool ok=server?GetNamedPipeClientProcessId(stream.SafePipeHandle,out id):GetNamedPipeServerProcessId(stream.SafePipeHandle,out id);
    if(!ok||id==0)throw new UnauthorizedAccessException("OS_PEER_PID");
    return checked((int)id);
  }
  public static int PeerSession(PipeStream stream,bool server) {
    uint id;
    bool ok=server?GetNamedPipeClientSessionId(stream.SafePipeHandle,out id):GetNamedPipeServerSessionId(stream.SafePipeHandle,out id);
    if(!ok)throw new UnauthorizedAccessException("OS_PEER_SESSION");
    return checked((int)id);
  }
  public static long Born(int pid){ using(Process p=Process.GetProcessById(pid)){return p.StartTime.ToUniversalTime().Ticks;}}
  public static int Session(int pid){using(Process p=Process.GetProcessById(pid)){return p.SessionId;}}
  [DllImport("advapi32.dll", SetLastError=true)]
  static extern bool GetTokenInformation(IntPtr token,int kind,byte[] data,int length,out int required);
  public static string LogonSid() {
    // TokenStatistics.AuthenticationId is the kernel logon LUID; use its
    // two DWORDs for S-1-5-5-X-Y instead of guessing the interactive session.
    using(WindowsIdentity identity=WindowsIdentity.GetCurrent()) {
      // TokenLogonSid (TOKEN_INFORMATION_CLASS 28) returns the actual logon
      // security principal, NOT TokenStatistics.AuthenticationId guessed as SID.
      byte[] info=new byte[256];int required=0;
      if(!GetTokenInformation(identity.Token,28,info,info.Length,out required)||required<16)
        throw new UnauthorizedAccessException("TOKEN_LOGON_SID_UNAVAILABLE");
      GCHandle pin=GCHandle.Alloc(info,GCHandleType.Pinned);
      try {
        IntPtr sid=Marshal.ReadIntPtr(pin.AddrOfPinnedObject(),8);
        if(sid==IntPtr.Zero)throw new UnauthorizedAccessException("TOKEN_LOGON_SID_NULL");
        return new SecurityIdentifier(sid).Value;
      } finally {pin.Free();}
    }
  }
  public static PipeSecurity Dacl() {
    PipeSecurity acl=new PipeSecurity();
    acl.SetAccessRuleProtection(true,false);
    SecurityIdentifier sid=new SecurityIdentifier(LogonSid());
    acl.AddAccessRule(new PipeAccessRule(sid,PipeAccessRights.FullControl,AccessControlType.Allow));
    acl.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid,null),PipeAccessRights.ReadWrite,AccessControlType.Deny));
    return acl;
  }
  static async Task<byte[]> ReadExact(PipeStream stream,int length,int timeout) {
    byte[] data=new byte[length];int at=0;var deadline=Stopwatch.StartNew();
    while(at<length) {
      int remaining=timeout-(int)deadline.ElapsedMilliseconds;
      if(remaining<=0)throw new TimeoutException("FRAME_TIMEOUT");
      Task<int> op=stream.ReadAsync(data,at,length-at);
      if(await Task.WhenAny(op,Task.Delay(remaining))!=op)throw new TimeoutException("FRAME_TIMEOUT");
      int n=await op;
      if(n<=0)throw new EndOfStreamException("FRAME_EOF");
      at+=n;
    }
    return data;
  }
  public static async Task<string> Read(PipeStream stream,int max,int timeout) {
    byte[] size=await ReadExact(stream,4,timeout);
    uint bytes=BitConverter.ToUInt32(size,0);
    if(bytes==0||bytes>max)throw new InvalidDataException("FRAME_SIZE");
    byte[] raw=await ReadExact(stream,(int)bytes,timeout);
    return new UTF8Encoding(false,true).GetString(raw);
  }
  public static async Task Write(PipeStream stream,string value,int max,int timeout) {
    byte[] data=new UTF8Encoding(false,true).GetBytes(value);
    if(data.Length==0||data.Length>max)throw new InvalidDataException("RESPONSE_SIZE");
    byte[] header=BitConverter.GetBytes((uint)data.Length);
    Task w=stream.WriteAsync(header,0,4);
    if(await Task.WhenAny(w,Task.Delay(timeout))!=w)throw new TimeoutException("WRITE_TIMEOUT");
    await w;
    w=stream.WriteAsync(data,0,data.Length);
    if(await Task.WhenAny(w,Task.Delay(timeout))!=w)throw new TimeoutException("WRITE_TIMEOUT");
    await w;
    await stream.FlushAsync();
  }
  public static Dictionary<string,object> Decode(string json) {
    object result=Json.DeserializeObject(json);
    Dictionary<string,object> map=result as Dictionary<string,object>;
    if(map==null)throw new InvalidDataException("JSON_OBJECT_REQUIRED");
    return map;
  }
  public static string String(Dictionary<string,object> d,string key){
    object x;return d.TryGetValue(key,out x)&&x is string?(string)x:"";
  }
  public static long Number(Dictionary<string,object> d,string key,long fallback=-1){
    object x;if(!d.TryGetValue(key,out x)||x==null)return fallback;
    try {return Convert.ToInt64(x);}catch{return fallback;}
  }
  public static string Request(string verb,string nonce,string generation,long after=0,string id=null,long sequence=0){
    string requestId=System.String.IsNullOrEmpty(id)?(sequence.ToString("x16")+Guid.NewGuid().ToString("N").Substring(0,16)):id;
    return Json.Serialize(new Dictionary<string,object>(){
      {"type",verb},{"protocol",1},{"requestId",requestId},{"requestSequence",sequence},
      {"nonce",nonce},{"hostGeneration",generation},{"afterSequence",after}
    });
  }
  public static Task<string> CallBackground(string pipe,string expectedPidAndTicks,string json,int timeout=1200){return Task.Run(()=>Call(pipe,expectedPidAndTicks,json,timeout));}
  public static string Call(string pipe,string expectedPidAndTicks,string json,int timeout=1200){
    string[] identity=expectedPidAndTicks.Split('|');
    int pid=int.Parse(identity[0]);long ticks=long.Parse(identity[1]);int session=int.Parse(identity[2]);
    using(NamedPipeClientStream client=new NamedPipeClientStream(".",pipe,PipeDirection.InOut,PipeOptions.Asynchronous)){
      client.Connect(timeout);
      if(PeerPid(client,false)!=pid||PeerSession(client,false)!=session||Born(pid)!=ticks)
        throw new UnauthorizedAccessException("HOST_OS_IDENTITY");
      Task t=Write(client,json,MaxRequest,timeout);
      if(!t.Wait(timeout+100))throw new TimeoutException("CLIENT_WRITE");
      Task<string> reply=Read(client,MaxResponse,timeout);
      if(!reply.Wait(timeout+100))throw new TimeoutException("CLIENT_READ");
      // Failure must not silently associate a stale/unrelated response.
      var sent=Decode(json);var received=Decode(reply.Result);
      if(String(sent,"requestId")!=String(received,"requestId"))throw new InvalidDataException("RESPONSE_ID_MISMATCH");
      return reply.Result;
    }
  }
}

public sealed class P1Server : IDisposable {
  readonly string name;
  readonly Func<Dictionary<string,object>,int,int,string> dispatch;
  readonly CancellationTokenSource stop=new CancellationTokenSource();
  readonly SemaphoreSlim slots=new SemaphoreSlim(2,2);
  readonly List<Task> listeners=new List<Task>();
  public int Active=0,Rejected=0,Timeouts=0,PeakActive=0;
  public P1Server(string pipe,Func<Dictionary<string,object>,int,int,string> handler){
    if(!System.Text.RegularExpressions.Regex.IsMatch(pipe,@"^rdc-p3-(gui|ctl)-[a-f0-9]{32}$"))throw new ArgumentException("prototype pipe prefix");
    name=pipe;dispatch=handler;
  }
  public void Start() {for(int i=0;i<2;i++)listeners.Add(AcceptLoop());}
  async Task AcceptLoop() {
    while(!stop.IsCancellationRequested) {
      NamedPipeServerStream p=null;
      try {
        await slots.WaitAsync(stop.Token);
        p=new NamedPipeServerStream(name,PipeDirection.InOut,2,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,4096,4096,P1Wire.Dacl());
        await p.WaitForConnectionAsync(stop.Token);
        var connected=p;p=null;
        Task acceptedTask=ServeOwned(connected);
      }catch(ObjectDisposedException){if(p!=null)p.Dispose();break;}
       catch(OperationCanceledException){if(p!=null)p.Dispose();break;}
       catch{Interlocked.Increment(ref Rejected);if(p!=null)p.Dispose();try{slots.Release();}catch{}}
    }
  }
  async Task ServeOwned(NamedPipeServerStream p) {try{await Serve(p);}finally{p.Dispose();try{slots.Release();}catch{}}}
  async Task Serve(NamedPipeServerStream p) {
    int current=Interlocked.Increment(ref Active);
    int previous;
    while((previous=PeakActive)<current && Interlocked.CompareExchange(ref PeakActive,current,previous)!=previous){}
    try {
      // Windows kernel-observed peer identity is checked BEFORE parsing JSON.
      int clientPid=P1Wire.PeerPid(p,true),clientSession=P1Wire.PeerSession(p,true);
      string input=await P1Wire.Read(p,P1Wire.MaxRequest,1200);
      Dictionary<string,object> map=P1Wire.Decode(input);
      string answer=dispatch(map,clientPid,clientSession);
      await P1Wire.Write(p,answer,P1Wire.MaxResponse,1000);
    }catch(TimeoutException){Interlocked.Increment(ref Timeouts);}
     catch{Interlocked.Increment(ref Rejected);}
    finally{Interlocked.Decrement(ref Active);}
  }
  public void Dispose(){stop.Cancel();stop.Dispose();slots.Dispose();}
}
