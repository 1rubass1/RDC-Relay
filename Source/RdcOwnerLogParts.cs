// RDC Relay raw log byte sink. No Host/process/IPC access.
// The caller supplies a new, verified, empty owned session directory.
// Session publication and verified Job stream integration are separate.
using System;
using System.IO;
using System.Collections.Generic;
using System.Globalization;

public sealed class RdcOwnerLogParts : IDisposable {
 public const int PartBytes=10*1024*1024;
 public const long SessionBytes=512L*1024*1024;
 sealed class Part {
  internal string Path,Date;
  internal long Bytes;
 }
 readonly object gate=new object();
 readonly string root;
 readonly int partLimit;
 readonly long sessionLimit;
 readonly Func<DateTime> localClock;
 readonly List<Part> parts=new List<Part>();
 readonly Dictionary<string,int> lastPart=new Dictionary<string,int>(StringComparer.Ordinal);
 FileStream writer;
 Part active;
 long retained;
 bool disposed,faulted;
 public RdcOwnerLogParts(string directory):this(directory,PartBytes,SessionBytes,()=>DateTime.Now){}
 // Explicit test seam: no dependency on machine time or massive test files.
 public RdcOwnerLogParts(string directory,int partBytes,long sessionBytes,Func<DateTime> clock){
  if(String.IsNullOrWhiteSpace(directory)||!Path.IsPathRooted(directory)||
     partBytes<1||sessionBytes<partBytes||clock==null)
   throw new ArgumentException("RDC_LOG_PART_ARGUMENT");
  root=Path.GetFullPath(directory);
  Safe(root);
  if(!Directory.Exists(root)||Directory.GetFileSystemEntries(root).Length!=0)
   throw new IOException("RDC_LOG_SESSION_NOT_EMPTY");
  partLimit=partBytes;sessionLimit=sessionBytes;localClock=clock;
 }
 static void Safe(string path){
  for(string p=Path.GetFullPath(path);!String.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)){
   if((File.Exists(p)||Directory.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
    throw new IOException("RDC_LOG_REPARSE_REFUSED");
  }
 }
 void Ready(){
  if(disposed)throw new ObjectDisposedException("RdcOwnerLogParts");
  if(faulted)throw new IOException("RDC_LOG_SINK_FAULTED");
 }
 public long RetainedBytes {get{lock(gate){return retained;}}}
 public string[] RetainedPaths {
  get{lock(gate){return parts.ConvertAll(p=>p.Path).ToArray();}}
 }
 void Seal(){
  if(writer==null)return;
  var stream=writer;
  writer=null;active=null;
  try{stream.Flush(true);}finally{stream.Dispose();}
 }
 void Begin(string date){
  Safe(root);
  int n;
  if(!lastPart.TryGetValue(date,out n))n=0;
  n=checked(n+1);
  string path=Path.Combine(root,date+"_part-"+n.ToString("D3",CultureInfo.InvariantCulture)+".log");
  Safe(path);
  // Never overwrite or truncate an existing part, even on a clock rollback.
  writer=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read,65536);
  active=new Part{Path=path,Date=date,Bytes=0};
  lastPart[date]=n;
  parts.Add(active);
 }
 void MakeSpace(int incoming){
  // Chronological order is the writer's creation order, not the wall clock.
  // Never delete the active part or a path not created by this instance.
  while(retained>sessionLimit-incoming){
   if(parts.Count==0||Object.ReferenceEquals(parts[0],active))
    throw new IOException("RDC_LOG_RETENTION_NO_CLOSED_PART");
   Part oldest=parts[0];
   Safe(oldest.Path);
   var info=new FileInfo(oldest.Path);
   if(!info.Exists||info.Length!=oldest.Bytes)
    throw new IOException("RDC_LOG_PART_CHANGED");
   File.Delete(oldest.Path);
   if(File.Exists(oldest.Path))throw new IOException("RDC_LOG_PRUNE_FAILED");
   retained-=oldest.Bytes;
   parts.RemoveAt(0);
  }
 }
 public void Write(byte[] buffer,int offset,int count){
  if(buffer==null)throw new ArgumentNullException("buffer");
  if(offset<0||count<0||offset>buffer.Length-count)throw new ArgumentOutOfRangeException("count");
  lock(gate){
   Ready();
   try{
    while(count>0){
     string date=localClock().ToString("yyyy-MM-dd",CultureInfo.InvariantCulture);
     if(active!=null&&(active.Date!=date||active.Bytes==partLimit))Seal();
     if(active==null)Begin(date);
     int n=(int)Math.Min(count,partLimit-active.Bytes);
     MakeSpace(n);
     writer.Write(buffer,offset,n);
     active.Bytes+=n;retained+=n;offset+=n;count-=n;
    }
   }catch{faulted=true;try{Seal();}catch{}throw;}
  }
 }
 // Called by the future stream pump on a bounded periodic cadence and on
 // verified process termination. Flush(true) requests durable file contents.
 public void Flush(){
  lock(gate){
   Ready();
   try{if(writer!=null)writer.Flush(true);}
   catch{faulted=true;try{Seal();}catch{}throw;}
  }
 }
 public void Dispose(){
  lock(gate){
   if(disposed)return;
   disposed=true;
   Seal();
  }
 }
}

// Single-reader worker, independent of GUI/Host timer. Owns the sink after
// construction. Drain to EOF before disposing the captured process handle.
// The bounded parser handoff is fail-closed on overflow (never silently
// discard a gap and resume parsing). Storage failure does not stop draining.
// Session publication and Host/UI routing are separate integration steps.
public delegate int RdcOwnerLogReader(byte[] buffer,out bool eof);
public sealed class RdcOwnerLogPump {
 readonly object gate=new object();
 readonly RdcOwnerLogReader read;
 readonly RdcOwnerLogParts sink;
 readonly byte[] pending;
 readonly System.Threading.Thread worker;
 int head,count;
 long bytesRead,bytesWriteAcknowledged;
 bool cleanEof,complete,parserFault,storageFault,readFault,cancelRequested;
 public RdcOwnerLogPump(RdcOwnerLogReader reader,RdcOwnerLogParts destination):this(reader,destination,4*1024*1024){}
 public RdcOwnerLogPump(RdcOwnerLogReader reader,RdcOwnerLogParts destination,int parserCapacity){
  if(reader==null||destination==null||parserCapacity<1||parserCapacity>4*1024*1024)
   throw new ArgumentException("RDC_LOG_PUMP_ARGUMENT");
  read=reader;sink=destination;pending=new byte[parserCapacity];
  worker=new System.Threading.Thread(Drain);
  worker.IsBackground=true;worker.Name="RDC Relay raw log drain";
  worker.Start();
 }
 public bool Complete {get{lock(gate){return complete;}}}
 public bool CleanEof {get{lock(gate){return cleanEof;}}}
 public bool ParserFault {get{lock(gate){return parserFault;}}}
 public bool StorageFault {get{lock(gate){return storageFault;}}}
 public bool ReadFault {get{lock(gate){return readFault;}}}
 public int PendingBytes {get{lock(gate){return count;}}}
 // Total bytes returned by the reader versus complete successful sink.Write
 // calls. Not a guarantee of durable bytes; flush/partial writes can fail.
 public long BytesRead {get{lock(gate){return bytesRead;}}}
 public long BytesWriteAcknowledged {get{lock(gate){return bytesWriteAcknowledged;}}}
 public long RetainedBytes {get{return sink.RetainedBytes;}}
 static long AddSaturating(long current,int n){return current>Int64.MaxValue-n?Int64.MaxValue:current+n;}
 public string[] RetainedPaths {get{return sink.RetainedPaths;}}
 void Queue(byte[] data,int length){
  lock(gate){
   if(parserFault)return;
   if(length>pending.Length-count){
    parserFault=true;head=0;count=0;return;
   }
   int tail=(head+count)%pending.Length;
   int first=Math.Min(length,pending.Length-tail);
   Buffer.BlockCopy(data,0,pending,tail,first);
   if(first<length)Buffer.BlockCopy(data,first,pending,0,length-first);
   count+=length;
  }
 }
 public int ReadPending(byte[] destination){
  if(destination==null||destination.Length<1||destination.Length>65536)
   throw new ArgumentException("RDC_LOG_PUMP_BUFFER");
  lock(gate){
   if(parserFault)return 0;
   int n=Math.Min(destination.Length,count);
   int first=Math.Min(n,pending.Length-head);
   Buffer.BlockCopy(pending,head,destination,0,first);
   if(first<n)Buffer.BlockCopy(pending,0,destination,first,n-first);
   head=(head+n)%pending.Length;count-=n;
   return n;
  }
 }
 void StorageFailed(){lock(gate){storageFault=true;}}
 void Drain(){
  var buffer=new byte[32768];
  var cadence=System.Diagnostics.Stopwatch.StartNew();
  bool dirty=false;
  try{
   while(true){
    lock(gate){if(cancelRequested)break;}
    bool eof;
    int n=read(buffer,out eof);
    if(n<0||n>buffer.Length||(eof&&n!=0))throw new IOException("RDC_LOG_PUMP_READ_CONTRACT");
    if(n>0){
     lock(gate){bytesRead=AddSaturating(bytesRead,n);}
     if(!StorageFault){
      try{sink.Write(buffer,0,n);lock(gate){bytesWriteAcknowledged=AddSaturating(bytesWriteAcknowledged,n);}dirty=true;}catch{StorageFailed();}
     }
     Queue(buffer,n);
    }
    if(dirty&&!StorageFault&&(eof||cadence.ElapsedMilliseconds>=1000)){
     try{sink.Flush();dirty=false;cadence.Restart();}catch{StorageFailed();}
    }
    if(eof){lock(gate){cleanEof=true;}break;}
    if(n==0)System.Threading.Thread.Sleep(10);
   }
  }catch{
   lock(gate){readFault=true;}
  }finally{
   try{sink.Dispose();}catch{StorageFailed();}
   lock(gate){complete=true;}
  }
 }
 public void RequestStop(){lock(gate){cancelRequested=true;}}
 public bool WaitForCompletion(int timeoutMs){
  if(timeoutMs<0||timeoutMs>15000)throw new ArgumentOutOfRangeException("timeoutMs");
  return worker.Join(timeoutMs);
 }
}

// Persistent session ownership and same-volume publication. The caller
// must hold the private Job / prove that no external Remote is running
// before recovery, and must finish the pump before finalization.
// Fixed-category completion data only; never pass arbitrary exception text or identity.
public enum RdcOwnerPreflightFailure { None,RuntimeUnavailable,InspectionFailed }
public static class RdcOwnerCompletionDiagnostics {
 // Classification uses observations only, not a guess at the upstream cause.
 public static string Classify(bool accepted,RdcOwnerFailedSessionInfo info){
  if(info==null)return "unknown";
  if(info.PreflightFailure!=RdcOwnerPreflightFailure.None)return "preflight_failed";
  if(info.LaunchFailed)return "launch_failed";
  if(!info.CmdExit.HasValue||!info.StopRequested.HasValue)return "unknown";
  if(info.StopRequested.Value){
   if(accepted)return "stop_requested_after_ready";
   return info.AuthPendingObserved==true?"authorization_stop_requested":"startup_stop_requested";
  }
  return accepted?"unexpected_after_ready":"exit_before_ready";
 }
}
public sealed class RdcOwnerFailedSessionInfo {
 public int? CmdExit;
 public bool? StopRequested,AuthPendingObserved,CleanEof,ReadFault,StorageFault,ParserFault;
 public long? BytesRead,BytesWriteAcknowledged,RetainedBytes;
 public int? ParserPending;
 public bool LaunchFailed;
 public RdcOwnerPreflightFailure PreflightFailure;
 public string[] PrerequisiteObservations;
}
public sealed class RdcOwnerLogSessions : IDisposable {
 const string IdentityName=".rdc-session-v1";
 const string AcceptedName=".rdc-accepted-v1";
 const string UnexpectedName=".rdc-unexpected-v1";
 const string MarkerPrefix="RDC-LOG-SESSION-V1:";
 const int MaxEntries=10000;
 public const int FailedRawLimit=1024*1024;
 const int FailedHeaderLimit=3072;
 const string FailedName="Last unsuccessful sessions.log";
 const string FailedStageName=".rdc-failed-report-v1.tmp";
 const string FailedPrefix="RDC-LAST-UNSUCCESSFUL-V1:";
 readonly string root,current,previous,retired,failed;
 FileStream lease;
 bool disposed;
 string activeId;
 bool finalizing,finalizingAccepted,finalizingUnexpected;
 RdcOwnerFailedSessionInfo finalizingInfo;
 public string FailedPath {get{return failed;}}
 public string CurrentPath {get{return current;}}
 public string PreviousPath {get{return previous;}}
 public RdcOwnerLogSessions(string directory){
  if(String.IsNullOrWhiteSpace(directory)||!Path.IsPathRooted(directory))
   throw new ArgumentException("RDC_LOG_ROOT");
  root=Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar);
  if(String.IsNullOrEmpty(Path.GetDirectoryName(root)))throw new IOException("RDC_LOG_ROOT_BOUNDARY");
  Safe(root);Directory.CreateDirectory(root);Safe(root);
  current=Path.Combine(root,"CurrentSession");
  previous=Path.Combine(root,"PreviousSession");
  retired=Path.Combine(root,"RetiredSession");
  failed=Path.Combine(root,FailedName);
  string lockPath=Path.Combine(root,".rdc-session-lock-v1");
  Safe(lockPath);
  lease=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
 }
 static void Safe(string path){
  for(string p=Path.GetFullPath(path);!String.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)){
   if((File.Exists(p)||Directory.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
    throw new IOException("RDC_LOG_SESSION_REPARSE");
  }
 }
 void Ready(){
  if(disposed||lease==null)throw new ObjectDisposedException("RdcOwnerLogSessions");
  Safe(root);
 }
 static bool Present(string path){
  Safe(path);
  if(File.Exists(path))throw new IOException("RDC_LOG_SESSION_PATH_COLLISION");
  return Directory.Exists(path);
 }
 static string ReadMarker(string path){
  Safe(path);
  var info=new FileInfo(path);
  if(!info.Exists||info.Length!=MarkerPrefix.Length+32)
   throw new IOException("RDC_LOG_SESSION_MARKER");
  string value=File.ReadAllText(path,System.Text.Encoding.ASCII);
  if(!value.StartsWith(MarkerPrefix,StringComparison.Ordinal)||
    !System.Text.RegularExpressions.Regex.IsMatch(value.Substring(MarkerPrefix.Length),@"\A[0-9a-f]{32}\z"))
   throw new IOException("RDC_LOG_SESSION_MARKER");
  return value.Substring(MarkerPrefix.Length);
 }
 static void WriteMarker(string path,string id){
  Safe(path);
  byte[] bytes=System.Text.Encoding.ASCII.GetBytes(MarkerPrefix+id);
  using(var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read)){
   file.Write(bytes,0,bytes.Length);file.Flush(true);
  }
 }
 sealed class Session {
  internal string Id;
  internal bool Accepted,Unexpected,FailedStage;
  internal List<string> Files=new List<string>();
 }
 // No recursive deletion, wildcard cleanup, or following of unowned paths.
 // Validate the entire directory before moving or deleting any part.
 static Session Inspect(string path){
  if(!Present(path))return null;
  var result=new Session();
  result.Id=ReadMarker(Path.Combine(path,IdentityName));
  long total=0;int entries=0;
  foreach(string entry in Directory.EnumerateFileSystemEntries(path)){
   if(++entries>MaxEntries)throw new IOException("RDC_LOG_SESSION_ENTRY_LIMIT");
   Safe(entry);
   if(Directory.Exists(entry)||!File.Exists(entry))throw new IOException("RDC_LOG_SESSION_FOREIGN_ENTRY");
   string name=Path.GetFileName(entry);
   if(name==IdentityName)continue;
   if(name==FailedStageName){
    if(ReadFailedId(entry)!=result.Id)throw new IOException("RDC_FAILED_STAGE_ID");
    result.FailedStage=true;continue;
   }
   if(name==UnexpectedName){
    if(ReadMarker(entry)!=result.Id)throw new IOException("RDC_FAILED_UNEXPECTED_ID");
    result.Unexpected=true;continue;
   }
   if(name==AcceptedName){
    if(ReadMarker(entry)!=result.Id)throw new IOException("RDC_LOG_SESSION_ACCEPTED_MISMATCH");
    result.Accepted=true;continue;
   }
   if(!System.Text.RegularExpressions.Regex.IsMatch(name,@"\A\d{4}-\d{2}-\d{2}_part-[0-9]{3,10}\.log\z"))
    throw new IOException("RDC_LOG_SESSION_FOREIGN_ENTRY");
   long size=new FileInfo(entry).Length;
   if(size>RdcOwnerLogParts.PartBytes||size<0||total>RdcOwnerLogParts.SessionBytes-size)
    throw new IOException("RDC_LOG_SESSION_SIZE");
   total+=size;result.Files.Add(entry);
  }
  if(result.Accepted&&result.FailedStage&&!result.Unexpected)throw new IOException("RDC_FAILED_STAGE_ACCEPTED");
  return result;
 }
 static void DeleteOwned(string path,Session expected){
  if(expected==null)throw new IOException("RDC_LOG_SESSION_DELETE_PROOF");
  var actual=Inspect(path);
  if(actual==null||actual.Id!=expected.Id||actual.Accepted!=expected.Accepted||actual.Unexpected!=expected.Unexpected)
   throw new IOException("RDC_LOG_SESSION_DELETE_CHANGED");
  foreach(string file in actual.Files){Safe(file);File.Delete(file);}
  if(actual.FailedStage)File.Delete(Path.Combine(path,FailedStageName));
  if(actual.Accepted)File.Delete(Path.Combine(path,AcceptedName));
  if(actual.Unexpected)File.Delete(Path.Combine(path,UnexpectedName));
  File.Delete(Path.Combine(path,IdentityName));
  Directory.Delete(path,false);
 }
 static void MoveOwned(string from,string to,Session expected){
  var actual=Inspect(from);
  if(expected==null||actual==null||actual.Id!=expected.Id||actual.Accepted!=expected.Accepted||Present(to))
   throw new IOException("RDC_LOG_SESSION_MOVE_CHANGED");
  Directory.Move(from,to);
 }
 // A previous-to-retired rename followed by a current-to-previous rename
 // is recoverable by inspecting the durable IDs and accepted markers.
 // No new current is created while an incomplete transaction exists.
 public void Recover(){
  Ready();
  if(activeId!=null)throw new InvalidOperationException("RDC_LOG_SESSION_ACTIVE");
  RecoverCore(null);
 }
 static bool RemoveReservedEmpty(string path){
  if(!Present(path))return false;
  using(var entries=Directory.EnumerateFileSystemEntries(path).GetEnumerator()){
   if(entries.MoveNext())return false;
  }
  Directory.Delete(path,false);return true;
 }
 void RecoverCore(RdcOwnerFailedSessionInfo info){
  // An empty current may result from interruption before its first marker
  // or after removal of its last owned file. Never remove nonempty unknown data.
  RemoveReservedEmpty(current);
  var c=Inspect(current);var p=Inspect(previous);
  if(c==null&&p!=null&&p.Accepted)RemoveReservedEmpty(retired);
  var r=Inspect(retired);
  if((p!=null&&(!p.Accepted||p.Unexpected))||(r!=null&&r.Unexpected)||(r!=null&&!r.Accepted&&(c!=null||p==null||r.Files.Count!=0))||
    (c!=null&&p!=null&&c.Id==p.Id)||(c!=null&&r!=null&&c.Id==r.Id)||(p!=null&&r!=null&&p.Id==r.Id))
   throw new IOException("RDC_LOG_SESSION_STATE");
  if(r!=null){
   if(c!=null&&c.Accepted&&!c.Unexpected&&p==null){
    MoveOwned(current,previous,c);p=Inspect(previous);c=null;
   }else if(c!=null||p==null){
    // No destructive guess in an impossible or interrupted state.
    throw new IOException("RDC_LOG_SESSION_TRANSACTION_UNKNOWN");
   }
   DeleteOwned(retired,r);
  }
  if(c==null)return;
  if(c.Unexpected&&!c.Accepted&&ReadFailedId(failed)!=c.Id)
   throw new IOException("RDC_FAILED_UNEXPECTED_PROOF");
  if(!c.Accepted||c.Unexpected){PublishFailed(c,info);DeleteOwned(current,c);return;}
  Publish(c,p);
 }
 void Publish(Session c,Session p){
  if(!c.Accepted||c.Unexpected||Present(retired))throw new IOException("RDC_LOG_SESSION_PUBLISH_STATE");
  if(p!=null){
   if(!p.Accepted||p.Id==c.Id)throw new IOException("RDC_LOG_SESSION_PREVIOUS_STATE");
   MoveOwned(previous,retired,p);
  }
  MoveOwned(current,previous,c);
  if(p!=null)DeleteOwned(retired,p);
 }
 // A fixed owned header prevents replacing arbitrary user files at this name.
 // Missing is distinct from an inaccessible, malformed or reparse file.
 static string ReadFailedId(string path){
  Safe(path);
  FileAttributes attrs;
  try{attrs=File.GetAttributes(path);}
  catch(FileNotFoundException){return null;}
  catch(DirectoryNotFoundException){return null;}
  if((attrs&(FileAttributes.Directory|FileAttributes.ReparsePoint))!=0)
   throw new IOException("RDC_FAILED_REPORT_COLLISION");
  int len=FailedPrefix.Length+32+1;
  using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)){
   if(f.Length<len||f.Length>FailedRawLimit+FailedHeaderLimit)
    throw new IOException("RDC_FAILED_REPORT_SIZE");
   var bytes=new byte[len];int offset=0;
   while(offset<len){int n=f.Read(bytes,offset,len-offset);if(n==0)throw new IOException("RDC_FAILED_REPORT_HEADER");offset+=n;}
   string header=System.Text.Encoding.ASCII.GetString(bytes);
   if(!header.StartsWith(FailedPrefix,StringComparison.Ordinal)||header[len-1]!='\n')
    throw new IOException("RDC_FAILED_REPORT_HEADER");
   string id=header.Substring(FailedPrefix.Length,32);
   if(!System.Text.RegularExpressions.Regex.IsMatch(id,@"\A[0-9a-f]{32}\z"))
    throw new IOException("RDC_FAILED_REPORT_HEADER");
   return id;
  }
 }
 static string Number<T>(T? value) where T:struct,IFormattable {
  return value.HasValue?value.Value.ToString(null,CultureInfo.InvariantCulture):"unknown";
 }
 static string Flag(bool? value){return value.HasValue?(value.Value?"yes":"no"):"unknown";}
 static string PreflightReason(RdcOwnerPreflightFailure reason){
  switch(reason){
   case RdcOwnerPreflightFailure.RuntimeUnavailable:return "runtime_unavailable";
   case RdcOwnerPreflightFailure.InspectionFailed:return "inspection_failed";
   default:return "none";
  }
 }
 // The report contains only known location categories and file/version states.
 // In particular no paths, user names or arbitrary exception strings.
 static string PrerequisiteHeader(string[] observations){
  if(observations==null||observations.Length==0)return "prerequisite_observations=unknown\n";
  const string loc=@"runtime (ProgramFiles|AppDataNpm|ProgramFilesX86): ";
  const string file=@"(missing|unknown|not_file|present)";
  const string node=@"(missing|unknown|not_file|present\(version_unknown\)|(present|unsupported)\([0-9]{1,10}(\.[0-9]{1,10}){3}\))";
  string pattern=@"\A"+loc+@"(check_unknown|node="+node+" npm="+file+" npx="+file+"|npm-cli="+file+" npx-cli="+file+@")\z";
  string package=@"\A"+loc+@"npm_package=(missing|unknown|not_file|present\(version_unknown\)|present\([0-9]{1,9}(\.[0-9]{1,9}){2}\))\z";
  const string system=@"\A(windows_version=(unknown|[0-9]{1,10}(\.[0-9]{1,10}){2}) native_arch=(unknown|x86|x64|arm64|arm) host_bits=(32|64)|remote_requested=0\.2\.52 remote_actual_version=unknown|relay_version=[0-9]{1,9}(\.[0-9]{1,9}){2}( RC[1-9][0-9]*)? relay_mode=(installed|portable|unknown)|runtime_selected=(ProgramFiles|AppDataNpm|ProgramFilesX86))\z";
  var lines=new List<string>();
  for(int i=0;i<Math.Min(14,observations.Length);i++){
   string line=observations[i];
   if(line!=null&&line.Length<=120&&
      (System.Text.RegularExpressions.Regex.IsMatch(line,pattern)||
       System.Text.RegularExpressions.Regex.IsMatch(line,package)||
       System.Text.RegularExpressions.Regex.IsMatch(line,system)))lines.Add(line+"\n");
  }
  return lines.Count==0?"prerequisite_observations=unknown\n":String.Concat(lines);
 }
 // A separate bounded snapshot of typed metadata survives GUI detach/reopen.
 // No report file, raw output, private path or identity is read for IPC.
 public static string[] AttemptDiagnostics(string phase,bool accepted,RdcOwnerFailedSessionInfo info){
  if(phase!="startup_observation"&&phase!="completed"&&phase!="preflight_failed"&&phase!="launch_failed")
   throw new ArgumentException("RDC_ATTEMPT_PHASE");
  if(info==null)info=new RdcOwnerFailedSessionInfo();
  var lines=new List<string>{
   "attempt_phase="+phase,
   "completion_kind="+RdcOwnerCompletionDiagnostics.Classify(accepted,info),
   "preflight_reason="+PreflightReason(info.PreflightFailure),
   "cmd_exit="+Number(info.CmdExit),
   "stop_requested="+Flag(info.StopRequested),
   "accepted_session="+Flag(accepted),
   "auth_pending_observed="+Flag(info.AuthPendingObserved),
   "capture_read="+Number(info.BytesRead),
   "write_ack="+Number(info.BytesWriteAcknowledged),
   "retained="+Number(info.RetainedBytes),
   "parser_pending="+Number(info.ParserPending),
   "eof="+Flag(info.CleanEof),
   "read_fault="+Flag(info.ReadFault),
   "storage_fault="+Flag(info.StorageFault),
   "parser_fault="+Flag(info.ParserFault)
  };
  lines.AddRange(PrerequisiteHeader(info.PrerequisiteObservations).Split(new[]{'\n'},StringSplitOptions.RemoveEmptyEntries));
  return lines.ToArray();
 }
 void PublishFailed(Session c,RdcOwnerFailedSessionInfo info){
  // Retry after atomic rename must not replace the good report with a
  // partially deleted current session. Recovery has no proof of exit code.
  string prior=ReadFailedId(failed);
  if(prior==c.Id)return;
  string stage=Path.Combine(current,FailedStageName);
  if(c.FailedStage){if(ReadFailedId(stage)!=c.Id)throw new IOException("RDC_FAILED_STAGE_ID");File.Delete(stage);}
  if(info==null)info=new RdcOwnerFailedSessionInfo();
  // File-name order is deterministic, not guaranteed chronological after a
  // clock rollback. Preserve original bytes, not decoded or sanitized text.
  var files=new List<string>(c.Files);files.Sort(StringComparer.Ordinal);
  long total=0;foreach(string file in files){Safe(file);total+=new FileInfo(file).Length;}
  long skip=Math.Max(0,total-FailedRawLimit),remaining=Math.Min(total,FailedRawLimit);
  string header=FailedPrefix+c.Id+"\n"+
   "recorded_utc="+DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture)+"\n"+
   "outcome="+(c.Unexpected?"unexpected_after_ready":"not_accepted")+" (not proof of crash)\n"+
   "completion_kind="+(c.Unexpected?"unexpected_after_ready":RdcOwnerCompletionDiagnostics.Classify(c.Accepted,info))+"\n"+
   "accepted_session="+Flag(c.Accepted||c.Unexpected)+" auth_pending_observed="+Flag(info.AuthPendingObserved)+"\n"+
   "completion="+(info.PreflightFailure!=RdcOwnerPreflightFailure.None?"preflight_failed":info.LaunchFailed?"launch_failed":info.CmdExit.HasValue?"verified_cmd_root_exit":"unknown")+"\n"+
   "preflight_reason="+PreflightReason(info.PreflightFailure)+"\n"+
   PrerequisiteHeader(info.PrerequisiteObservations)+
   "cmd_exit="+Number(info.CmdExit)+" stop_requested="+Flag(info.StopRequested)+"\n"+
   "capture_read="+Number(info.BytesRead)+" write_ack="+Number(info.BytesWriteAcknowledged)+
   " retained="+Number(info.RetainedBytes)+" parser_pending="+Number(info.ParserPending)+"\n"+
   "eof="+Flag(info.CleanEof)+" read_fault="+Flag(info.ReadFault)+" storage_fault="+Flag(info.StorageFault)+
   " parser_fault="+Flag(info.ParserFault)+"\n"+
   "raw_retained_bytes="+total.ToString(CultureInfo.InvariantCulture)+
   " raw_included_bytes="+remaining.ToString(CultureInfo.InvariantCulture)+" raw_truncated="+(skip>0?"yes":"no")+"\n"+
   "raw_order=filename; private merged stdout/stderr; not for automatic export\n--- RAW BYTES ---\n";
  byte[] head=System.Text.Encoding.UTF8.GetBytes(header);
  if(head.Length>FailedHeaderLimit)throw new IOException("RDC_FAILED_HEADER_LIMIT");
  bool created=false;
  try{
   Safe(stage);
   using(var output=new FileStream(stage,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    created=true;output.Write(head,0,head.Length);
    var buffer=new byte[32768];
    foreach(string file in files){
     Safe(file);
     using(var input=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read)){
      long length=input.Length;
      if(skip>=length){skip-=length;continue;}
      input.Position=skip;skip=0;
      while(remaining>0){
       int want=(int)Math.Min(buffer.Length,remaining);
       int n=input.Read(buffer,0,want);if(n==0)break;
       output.Write(buffer,0,n);remaining-=n;
      }
     }
    }
    if(remaining!=0||skip!=0)throw new IOException("RDC_FAILED_CAPTURE_CHANGED");
    output.Flush(true);
   }
   // Same-volume atomic publication while the session lease is held.
   if(ReadFailedId(stage)!=c.Id||ReadFailedId(failed)!=prior)
    throw new IOException("RDC_FAILED_REPORT_CHANGED");
   if(prior==null)File.Move(stage,failed);
   else File.Replace(stage,failed,null);
   created=false;
  }finally{
   // Only this invocation's CreateNew file, never a wildcard cleanup.
   if(created){Safe(stage);if(File.Exists(stage))File.Delete(stage);}
  }
 }
 // Caller must already have passed the external/owned Remote exclusion gate
 // and hold no unfinished Host capture. No process or pipe is created here.
 public void RecordPreflightFailure(RdcOwnerPreflightFailure reason,string[] observations){
  if(reason!=RdcOwnerPreflightFailure.RuntimeUnavailable&&reason!=RdcOwnerPreflightFailure.InspectionFailed)
   throw new ArgumentException("RDC_PREFLIGHT_FAILURE_REASON");
  Recover();
  using(var sink=Begin()){}
  FinalizeCurrentWithDiagnostics(new RdcOwnerFailedSessionInfo{
   PreflightFailure=reason,PrerequisiteObservations=observations});
 }
 public RdcOwnerLogParts Begin(){
  Ready();
  if(activeId!=null||Present(current)||Present(retired))
   throw new IOException("RDC_LOG_SESSION_NOT_RECOVERED");
  var p=Inspect(previous);
  if(p!=null&&(!p.Accepted||p.Unexpected))throw new IOException("RDC_LOG_SESSION_PREVIOUS_STATE");
  Directory.CreateDirectory(current);
  Safe(current);
  // The sink requires an initially empty directory. Register its owner
  // before handing the sink to the worker; no part is written beforehand.
  var sink=new RdcOwnerLogParts(current);
  try{
   string id=Guid.NewGuid().ToString("N");
   WriteMarker(Path.Combine(current,IdentityName),id);
   activeId=id;return sink;
  }catch{sink.Dispose();throw;}
 }
 public void Accept(){
  Ready();
  if(activeId==null||finalizing)throw new InvalidOperationException("RDC_LOG_SESSION_NO_ACTIVE");
  if(ReadMarker(Path.Combine(current,IdentityName))!=activeId)
   throw new IOException("RDC_LOG_SESSION_ACTIVE_CHANGED");
  string path=Path.Combine(current,AcceptedName);
  if(File.Exists(path)){
   if(ReadMarker(path)!=activeId)throw new IOException("RDC_LOG_SESSION_ACCEPTED_MISMATCH");
   return;
  }
  WriteMarker(path,activeId);
 }
 public void FinalizeCurrent(){FinalizeCurrentWithDiagnostics(null);}
 public void FinalizeCurrentWithDiagnostics(RdcOwnerFailedSessionInfo info){
  Ready();
  if(activeId==null)throw new InvalidOperationException("RDC_LOG_SESSION_NO_ACTIVE");
  if(!finalizing){
   var c=Inspect(current);
   if(c==null||c.Id!=activeId)throw new IOException("RDC_LOG_SESSION_ACTIVE_CHANGED");
   // Persist the observed abnormal-after-Ready decision before modifying any
   // logs. On restart it remains distinct from an ordinary accepted session.
   if(c.Accepted&&!c.Unexpected&&RdcOwnerCompletionDiagnostics.Classify(true,info)=="unexpected_after_ready"){
    WriteMarker(Path.Combine(current,UnexpectedName),c.Id);c=Inspect(current);
   }
   finalizingAccepted=c.Accepted;finalizingUnexpected=c.Unexpected;finalizingInfo=info;finalizing=true;
  }else{
   // A retry must still refer to our exact session, either before the move
   // or already published. A failed-start cleanup may have removed current.
   RemoveReservedEmpty(current);
   var c=Inspect(current);var p=Inspect(previous);
   bool failedPublished=finalizingUnexpected&&ReadFailedId(failed)==activeId;
   if(c!=null&&(c.Id!=activeId||((c.Accepted!=finalizingAccepted||c.Unexpected!=finalizingUnexpected)&&!failedPublished)))
    throw new IOException("RDC_LOG_SESSION_ACTIVE_CHANGED");
   if(c==null&&finalizingAccepted&&!finalizingUnexpected&&(p==null||p.Id!=activeId||!p.Accepted))
    throw new IOException("RDC_LOG_SESSION_PUBLISH_PROOF");
   if(c==null&&(!finalizingAccepted||finalizingUnexpected)&&ReadFailedId(failed)!=activeId)
    throw new IOException("RDC_FAILED_REPORT_PUBLISH_PROOF");
  }
  RecoverCore(finalizingInfo);
  activeId=null;finalizing=false;finalizingAccepted=false;finalizingUnexpected=false;finalizingInfo=null;
 }
 // Release only the lease. Never infer process exit, delete a session, or
 // publish anything from Dispose; the next verified start can recover.
 public void Dispose(){
  if(disposed)return;
  disposed=true;
  if(lease!=null){lease.Dispose();lease=null;}
 }
}
