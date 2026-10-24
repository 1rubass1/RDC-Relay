// Product Host-owned Remote observation/store boundary for RDC Relay RC1.
// No process creation, WMI discovery, credential reads or process kill APIs.
// This class accepts preclassified observations; real OS acquisition is gated.
using System;
using System.Collections.Generic;
using System.IO;
using RdcRelay.Owner;

public sealed class RdcOwnerRemoteState {
 readonly object sync=new object();
 readonly string session=Guid.NewGuid().ToString("N");
 readonly Queue<string> tail=new Queue<string>();
 readonly Queue<string> diagnostics=new Queue<string>();
 readonly int maxTail=64;
 string state="Disconnected",status="Remote not connected (RC1 fake-only)";
 Ownership ownership=Ownership.Unknown;
 ProcessEvidence identity;
 long epoch=1,revision=1,cursor=0,missed=0;
 bool sourceIsReal=false,stopApproved=false;
 public string SessionId {get{return session;}}
 public void AcceptFakeObservation(string next,string detail){
  if(next!="Disconnected" && next!="Connecting" && next!="AuthPending" &&
     next!="Ready" && next!="Fault" && next!="Reconnecting")
   throw new ArgumentException("RC1_UNKNOWN_REMOTE_STATE");
  lock(sync){
   // Transition telemetry only. No process action or automatic retry here.
   state=next;status=detail??"";if(status.Length>160)status=status.Substring(0,160);
   revision++;
   AddDiagnostic("Fake state: "+state);
  }
 }
 public void ClassifyReadOnly(Ownership kind,ProcessEvidence expected,ProcessEvidence observed){
  lock(sync){
   if(kind==Ownership.Owned && !ProcessOwnership.SameVerifiedProcess(expected,observed)){
    ownership=Ownership.Unknown;identity=null;
   }else if(kind==Ownership.Owned){
    // Evidence is still synthetic or externally provided; do not grant stop.
    ownership=Ownership.Owned;identity=expected;
   }else if(kind==Ownership.Adopted){
    ownership=Ownership.Adopted;identity=null;
   }else{ownership=Ownership.Unknown;identity=null;}
   stopApproved=false;revision++;
   AddDiagnostic("Owner evidence classified: "+ownership.ToString());
  }
 }
 public bool CanStop(){
  // Disposable tree OS identity, cooperative shutdown and actual Remote
  // support are NOT authorized; even synthetic Owned evidence is non-destructive.
  lock(sync){return sourceIsReal && stopApproved && false;}
 }
 public void RequireSafeStop(){
  throw new InvalidOperationException("RC1_STOP_BLOCKED_PENDING_OS_CHILD_TREE_OWNER_GO");
 }
 public void AddSyntheticLogLine(string text){
  if(text==null)text="";
  text=text.Replace("\r"," ").Replace("\n"," ");
  if(text.Length>220)text=text.Substring(0,220);
  lock(sync){
   cursor++;revision++;
   if(tail.Count==maxTail)tail.Dequeue();
   tail.Enqueue(cursor.ToString("D6")+" | "+text);
  }
 }
 public int PumpReader(TextReader fakeReader,int maxLines){
  // Caller supplies an in-memory fake TextReader during G0; NEVER opens
  // user log paths or the real Remote stdout in this stage.
  if(fakeReader==null)throw new ArgumentNullException("fakeReader");
  if(maxLines<1||maxLines>128)throw new ArgumentOutOfRangeException("maxLines");
  int read=0;
  while(read<maxLines){
   string line=fakeReader.ReadLine();
   if(line==null)break;
   AddSyntheticLogLine(line);read++;
  }
  return read;
 }
 public void ResetFakeLogStream(){
  lock(sync){
   epoch++;cursor=0;revision++;tail.Clear();
   AddDiagnostic("Synthetic log stream rotated");
  }
 }
 void AddDiagnostic(string line){
  if(diagnostics.Count==32)diagnostics.Dequeue();
  diagnostics.Enqueue(line.Length>140?line.Substring(0,140):line);
 }
 public void NoteHostEvent(string message){
  lock(sync){revision++;AddDiagnostic(message??"");}
 }
 public Dictionary<string,object> Snapshot(){
  lock(sync){
   return new Dictionary<string,object>{
    {"sessionId",session},{"fake",true},{"isActualRemote",sourceIsReal},
    {"ownership",ownership.ToString()},{"processAlive","unknown"},
    {"transportReady",state=="Ready"?"FAKE_READY":"not_connected"},
    {"authState",state=="AuthPending"?"FAKE_AUTH":"unavailable"},
    {"toolActivity","idle"},{"state",state},{"status",status},
    {"logStreamEpoch",epoch},{"logCursor",cursor},{"missed",missed},
    {"tail",tail.ToArray()},{"diagnostics",diagnostics.ToArray()},
    {"revision",revision},{"canStop",false},{"canReconnect",false},
    {"canStart",false},{"canUpdate",false},{"canLogout",false}
   };
  }
 }
}
