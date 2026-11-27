// Standalone synthetic file fixture. No Host, Remote, network, registry or PS scripts.
using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Text.RegularExpressions;

public static class TestV161FailedSessionReport {
 static int pass;
 static void Check(bool condition,string label){
  if(!condition)throw new Exception("FAIL "+label);
  Console.WriteLine("PASS "+label);pass++;
 }
 static bool Same(byte[] a,byte[] b){return a.SequenceEqual(b);}
 static byte[] Read(string path){return File.ReadAllBytes(path);}
 static string Text(string path){return Encoding.UTF8.GetString(Read(path));}
 static void Begin(RdcOwnerLogSessions store,byte[] data,bool accepted){
  using(var sink=store.Begin()){
   if(data.Length>0)sink.Write(data,0,data.Length);
   if(accepted)store.Accept();
  }
 }
 static byte[] Raw(string path){
  byte[] data=Read(path),delimiter=Encoding.ASCII.GetBytes("--- RAW BYTES ---\n");
  for(int i=0;i<=data.Length-delimiter.Length;i++){
   bool match=true;
   for(int j=0;j<delimiter.Length;j++)if(data[i+j]!=delimiter[j]){match=false;break;}
   if(match)return data.Skip(i+delimiter.Length).ToArray();
  }
  throw new Exception("REPORT_DELIMITER");
 }
 static bool Refused(Action action){
  try{action();return false;}catch(IOException){return true;}
 }
 static void Cleanup(string root){
  if(!Directory.Exists(root))return;
  if(!Regex.IsMatch(Path.GetFileName(root),@"\ARDC-V161-FAILREPORT-[0-9a-f]{32}\z")||
     !String.Equals(Path.GetDirectoryName(root),Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase))
   throw new Exception("FIXTURE_ROOT_BOUNDARY");
  foreach(string entry in Directory.GetFileSystemEntries(root)){
   var attrs=File.GetAttributes(entry);
   string name=Path.GetFileName(entry);
   if((attrs&FileAttributes.ReparsePoint)!=0)throw new Exception("FIXTURE_REPARSE");
   if((attrs&FileAttributes.Directory)!=0){
    if(name!="CurrentSession"&&name!="PreviousSession"&&name!="RetiredSession")throw new Exception("FIXTURE_FOREIGN_DIR");
    foreach(string child in Directory.GetFileSystemEntries(entry)){
     var a=File.GetAttributes(child);
     if((a&(FileAttributes.Directory|FileAttributes.ReparsePoint))!=0||
        !Regex.IsMatch(Path.GetFileName(child),@"\A(\.rdc-(session|accepted|unexpected)-v1|\.rdc-failed-report-v1\.tmp|\d{4}-\d{2}-\d{2}_part-\d+\.log)\z"))
      throw new Exception("FIXTURE_FOREIGN_MEMBER");
     File.Delete(child);
    }
    Directory.Delete(entry,false);
   }else{
    if(name!="Last unsuccessful sessions.log"&&name!=".rdc-session-lock-v1")throw new Exception("FIXTURE_FOREIGN_FILE");
    File.Delete(entry);
   }
  }
  Directory.Delete(root,false);
 }
 public static int Main(){
  string root=Path.Combine(Path.GetTempPath(),"RDC-V161-FAILREPORT-"+Guid.NewGuid().ToString("N"));
  try{
   string failed,previous,current;
   byte[] original,first;
   using(var store=new RdcOwnerLogSessions(root)){
    store.Recover();failed=store.FailedPath;previous=store.PreviousPath;current=store.CurrentPath;
    Begin(store,new byte[]{1,2,3},true);store.FinalizeCurrent();
    string good=Directory.GetFiles(previous,"*.log").Single();original=Read(good);
    Begin(store,new byte[0],false);
    store.FinalizeCurrentWithDiagnostics(new RdcOwnerFailedSessionInfo{
      CmdExit=23,StopRequested=false,BytesRead=0,BytesWriteAcknowledged=0,RetainedBytes=0,
      ParserPending=0,CleanEof=true,ReadFault=false,StorageFault=false,ParserFault=false});
    Check(File.Exists(failed)&&Path.GetDirectoryName(failed)==root&&!Directory.Exists(current),"one flat report without extra directory");
    Check(Text(failed).Contains("cmd_exit=23 stop_requested=no")&&Text(failed).Contains("raw_included_bytes=0 raw_truncated=no")&&Raw(failed).Length==0,"silent nonzero exit still has diagnostic header");
    Check(Same(original,Read(good)),"successful previous remains byte-exact");
    first=Read(failed);
    Begin(store,new byte[]{0,255,13,10,4},false);
    using(var locked=new FileStream(failed,FileMode.Open,FileAccess.Read,FileShare.Read)){
     Check(Refused(()=>store.FinalizeCurrent()),"locked destination prevents replacement");
     Check(Same(first,Read(failed))&&Directory.Exists(current),"old report and pending current survive failed publication");
    }
    store.FinalizeCurrent();
    Check(Same(Raw(failed),new byte[]{0,255,13,10,4}),"retry replaces report with original binary bytes");
    Check(RdcOwnerLogSessions.FailedRawLimit==1024*1024,"owner-approved 1 MiB raw limit");
    byte[] big=new byte[RdcOwnerLogSessions.FailedRawLimit+31];
    for(int i=0;i<big.Length;i++)big[i]=(byte)(i%251);
    Begin(store,big,false);store.FinalizeCurrent();
    Check(Text(failed).Contains("raw_truncated=yes")&&Same(Raw(failed),big.Skip(31).ToArray()),"raw tail bounded and truncation explicit");
    first=Read(failed);
    Begin(store,new byte[]{8,9},true);store.FinalizeCurrent();
    Check(Same(first,Read(failed)),"successful completion leaves failure report unchanged");
    Begin(store,new byte[]{6,7},false);
   }
   using(var store=new RdcOwnerLogSessions(root)){
    store.Recover();
    Check(Text(failed).Contains("completion=unknown")&&Same(Raw(failed),new byte[]{6,7}),"interrupted unaccepted current recovered with unknown completion");
    first=Read(failed);
    // Model interruption after atomic publication but before deletion.
    Directory.CreateDirectory(current);
    string id=Text(failed).Split('\n')[0].Substring("RDC-LAST-UNSUCCESSFUL-V1:".Length);
    File.WriteAllText(Path.Combine(current,".rdc-session-v1"),"RDC-LOG-SESSION-V1:"+id,Encoding.ASCII);
    File.WriteAllBytes(Path.Combine(current,"2026-11-26_part-001.log"),new byte[]{99});
    store.Recover();
    Check(Same(first,Read(failed))&&!Directory.Exists(current),"published identity prevents regeneration from partially cleaned current");
    // Deliberate foreign collision in the reserved output name.
    File.WriteAllText(failed,"foreign",Encoding.ASCII);
    Begin(store,new byte[]{11},false);
    Check(Refused(()=>store.FinalizeCurrent())&&Text(failed)=="foreign"&&Directory.Exists(current),"foreign destination never overwritten");
    File.Delete(failed);store.FinalizeCurrent();
    Check(Same(Raw(failed),new byte[]{11}),"retry succeeds when fixture obstruction removed");
    var knownGood=Read(Directory.GetFiles(previous,"*.log").Single());
    store.RecordPreflightFailure(RdcOwnerPreflightFailure.RuntimeUnavailable,new[]{
     "runtime ProgramFiles: node=missing npm=missing npx=missing",
     "runtime ProgramFiles: npm-cli=missing npx-cli=missing",
     "runtime AppDataNpm: node=unsupported(22.11.0.0) npm=present npx=present",
     "runtime AppDataNpm: npm-cli=present npx-cli=missing",
     "runtime ProgramFilesX86: check_unknown",
     "runtime ProgramFiles: node=private_path npm=present npx=present"
    });
    string preflight=Text(failed);
    Check(preflight.Contains("completion=preflight_failed")&&preflight.Contains("preflight_reason=runtime_unavailable")&&
     preflight.Contains("cmd_exit=unknown stop_requested=unknown")&&Raw(failed).Length==0,"preflight report without creating a process or raw output");
    Check(preflight.Contains("node=missing npm=missing npx=missing")&&preflight.Contains("node=unsupported(22.11.0.0)")&&
     preflight.Contains("npx-cli=missing")&&preflight.Contains("ProgramFilesX86: check_unknown"),"missing incompatible and unknown components explicit");
    Check(!preflight.Contains("private_path")&&Same(knownGood,Read(Directory.GetFiles(previous,"*.log").Single())),"reject arbitrary diagnostic text and preserve previous");
    store.RecordPreflightFailure(RdcOwnerPreflightFailure.InspectionFailed,null);
    Check(Text(failed).Contains("preflight_reason=inspection_failed")&&Text(failed).Contains("prerequisite_observations=unknown"),"inspection failure distinct from missing components");
    Check(Directory.GetDirectories(root).Select(Path.GetFileName).SequenceEqual(new[]{"PreviousSession"}),"no failed session directory left");
    var beforeReady=new RdcOwnerFailedSessionInfo{CmdExit=0,StopRequested=false};
    Check(RdcOwnerCompletionDiagnostics.Classify(false,beforeReady)=="exit_before_ready","zero exit without Ready or Stop remains unsuccessful");
    Check(RdcOwnerCompletionDiagnostics.Classify(true,beforeReady)=="unexpected_after_ready","zero exit after Ready without Stop is unexpected");
    Check(RdcOwnerCompletionDiagnostics.Classify(false,new RdcOwnerFailedSessionInfo{CmdExit=0,StopRequested=true,AuthPendingObserved=true})=="authorization_stop_requested","stop during observed authorization distinguished");
    Check(RdcOwnerCompletionDiagnostics.Classify(false,new RdcOwnerFailedSessionInfo{CmdExit=0,StopRequested=true})=="startup_stop_requested","stop before Ready without authorization evidence distinguished");
    Check(RdcOwnerCompletionDiagnostics.Classify(true,new RdcOwnerFailedSessionInfo{CmdExit=0,StopRequested=true})=="stop_requested_after_ready","requested Stop after Ready distinguished");
    Check(RdcOwnerCompletionDiagnostics.Classify(true,new RdcOwnerFailedSessionInfo{StopRequested=false})=="unknown","unverified completion remains unknown");
    var goodBeforeUnexpected=Read(Directory.GetFiles(previous,"*.log").Single());
    Begin(store,new byte[]{44,45},true);
    store.FinalizeCurrentWithDiagnostics(beforeReady);
    Check(Text(failed).Contains("completion_kind=unexpected_after_ready")&&Text(failed).Contains("accepted_session=yes")&&Same(Raw(failed),new byte[]{44,45}),"unexpected accepted session retained as failed report");
    Check(Same(goodBeforeUnexpected,Read(Directory.GetFiles(previous,"*.log").Single())),"unexpected after Ready does not replace last successful session");
    var lastUnexpected=Read(failed);
    Begin(store,new byte[]{46,47},true);
    store.FinalizeCurrentWithDiagnostics(new RdcOwnerFailedSessionInfo{CmdExit=0,StopRequested=true});
    Check(Same(lastUnexpected,Read(failed))&&Same(Read(Directory.GetFiles(previous,"*.log").Single()),new byte[]{46,47}),"requested Stop retains normal successful rotation");
    Begin(store,new byte[]{48,49},true);
    using(var locked=new FileStream(failed,FileMode.Open,FileAccess.Read,FileShare.Read)){
     Check(Refused(()=>store.FinalizeCurrentWithDiagnostics(beforeReady)),"unexpected report blocked safely by locked destination");
     Check(File.Exists(Path.Combine(current,".rdc-unexpected-v1"))&&Same(lastUnexpected,Read(failed)),"unexpected decision durable before publication");
    }
    // Leave the transaction incomplete, as if Host exited after recording it.
   }
   using(var store=new RdcOwnerLogSessions(root)){
    store.Recover();
    Check(Text(failed).Contains("completion_kind=unexpected_after_ready")&&Text(failed).Contains("cmd_exit=unknown")&&Same(Raw(failed),new byte[]{48,49}),"recovery retains unexpected category without inventing lost exit code");
    Check(Same(Read(Directory.GetFiles(previous,"*.log").Single()),new byte[]{46,47}),"recovery does not overwrite successful previous");
    // Model interruption after publication and accepted marker removal.
    Directory.CreateDirectory(current);
    string id=Text(failed).Split('\n')[0].Substring("RDC-LAST-UNSUCCESSFUL-V1:".Length);
    File.WriteAllText(Path.Combine(current,".rdc-session-v1"),"RDC-LOG-SESSION-V1:"+id,Encoding.ASCII);
    File.WriteAllText(Path.Combine(current,".rdc-unexpected-v1"),"RDC-LOG-SESSION-V1:"+id,Encoding.ASCII);
    var saved=Read(failed);store.Recover();
    Check(Same(saved,Read(failed))&&!Directory.Exists(current),"partial cleanup after unexpected publication is idempotent");
   }
   var summary=RdcOwnerLogSessions.AttemptDiagnostics("completed",true,new RdcOwnerFailedSessionInfo{
    CmdExit=0,StopRequested=false,BytesRead=0,PrerequisiteObservations=new[]{
     "runtime ProgramFiles: node=missing npm=missing npx=missing",
     "runtime AppDataNpm: node=secret_path npm=present npx=present"}});
   Check(summary.Contains("completion_kind=unexpected_after_ready")&&summary.Contains("cmd_exit=0")&&
    summary.Contains("capture_read=0")&&summary.Contains("write_ack=unknown"),"snapshot distinguishes known zero from unknown");
   Check(summary.Contains("runtime ProgramFiles: node=missing npm=missing npx=missing")&&
    !String.Join("\n",summary).Contains("secret_path")&&summary.Length<=22&&summary.All(x=>x.Length<=120),
    "snapshot contains only bounded allowlisted metadata");
   Check(RdcOwnerLogSessions.AttemptDiagnostics("startup_observation",false,null).Contains("completion_kind=unknown"),
    "startup observation cannot claim completion");
   Console.WriteLine("RDC_V161_FAILED_REPORT_PASS="+pass);
   return 0;
  }catch(Exception e){Console.WriteLine(e.GetType().Name+": "+e.Message);return 1;}
  finally{Cleanup(root);}
 }
}
