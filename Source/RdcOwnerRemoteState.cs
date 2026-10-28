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
 bool sourceIsReal=false,stopApproved=false,observedAlive=false,managedMode=false;
 int observedPid=0;
 public string SessionId {get{return session;}}
 // A Managed Host starts disconnected. Only its private kernel Job adapter
 // may supply PID/state; the GUI and discovered processes never grant ownership.
 public void EnableManaged(){
  lock(sync){
   if(sourceIsReal)throw new InvalidOperationException("RC1_MANAGED_ALREADY_ATTACHED");
   sourceIsReal=true;managedMode=true;ownership=Ownership.Owned;
   observedPid=0;observedAlive=false;stopApproved=false;
   state="Disconnected";status="RC1 Host ready to start pinned Remote";
   epoch++;tail.Clear();cursor=0;revision++;AddDiagnostic("Managed mode initialized");
  }
 }
 // Promote only after the Host independently proves the old external process
 // and legacy GUI are both absent. This method does not grant ownership of
 // the observed PID: it clears it, so only a NEW Job process can be stopped.
 public void PromoteObservedToManaged(){
  lock(sync){
   if(!sourceIsReal||managedMode||ownership!=Ownership.Adopted||stopApproved)
    throw new InvalidOperationException("RC1_OBSERVER_PROMOTION_REFUSED");
   managedMode=true;ownership=Ownership.Owned;identity=null;
   observedPid=0;observedAlive=false;stopApproved=false;
   state="Disconnected";status="Previous Remote exited; RC1 Host preparing a new managed session";
   epoch++;tail.Clear();cursor=0;revision++;
   AddDiagnostic("Legacy session left; managed Host enabled");
  }
 }
 public void ManagedStatus(int pid,bool alive,string next,string detail){
  if(next!="Disconnected"&&next!="Connecting"&&next!="AuthPending"&&next!="Ready"&&
     next!="Fault"&&next!="Reconnecting")throw new ArgumentException("RC1_MANAGED_STATE");
  lock(sync){
   if(!managedMode||ownership!=Ownership.Owned)throw new InvalidOperationException("RC1_NOT_MANAGED");
   if(alive&&pid<=0)throw new InvalidOperationException("RC1_MANAGED_PID_MISSING");
   detail=(detail??"").Replace("\r"," ").Replace("\n"," ");
   if(detail.Length>160)detail=detail.Substring(0,160);
   if(observedPid==pid&&observedAlive==alive&&state==next&&status==detail)return;
   if(pid!=observedPid){epoch++;tail.Clear();cursor=0;}
   observedPid=pid;observedAlive=alive;stopApproved=alive;
   state=next;status=detail;revision++;
   AddDiagnostic("Managed state: "+next);
  }
 }
 // A preexisting pinned Desktop Commander launcher is OBSERVED, not owned.
 // No method in this store can grant stop/reconnect/logout authority.
 public void AttachObservedReadOnly(int pid) {
  if(pid<=0)throw new ArgumentOutOfRangeException("pid");
  lock(sync){
   if(sourceIsReal)throw new InvalidOperationException("RC1_OBSERVER_ALREADY_ATTACHED");
   sourceIsReal=true;stopApproved=false;observedPid=pid;observedAlive=true;
   ownership=Ownership.Adopted;identity=null;
   // Drop the constructor's fake-only banner before the first observed GUI log.
   epoch++;cursor=0;tail.Clear();
   state="Connecting";status="Existing Remote observed; awaiting channel evidence";
   revision++;AddDiagnostic("Existing Remote attached read-only");
  }
 }
 public void RetargetObservedReadOnly(int pid){
  if(pid<=0)throw new ArgumentOutOfRangeException("pid");
  lock(sync){
   if(!sourceIsReal||ownership!=Ownership.Adopted)throw new InvalidOperationException("RC1_NOT_OBSERVING");
   // Caller reverified exact pinned OS identity including PID and birth.
   // No ownership/stop authority is acquired when a launcher is replaced.
   observedPid=pid;observedAlive=true;stopApproved=false;identity=null;
   epoch++;cursor=0;tail.Clear();
   state="Connecting";status="Existing Remote launcher changed; observing read-only";
   revision++;AddDiagnostic("Observed launcher identity replaced");
  }
 }
 public void UpdateObservedReadOnly(bool alive,string next,string detail){
  if(next!="Disconnected" && next!="Connecting" && next!="AuthPending" &&
     next!="Ready" && next!="Fault" && next!="Reconnecting")
   throw new ArgumentException("RC1_OBSERVER_STATE");
  lock(sync){
   if(!sourceIsReal||ownership!=Ownership.Adopted)throw new InvalidOperationException("RC1_NOT_OBSERVING");
   detail=(detail??"").Replace("\r"," ").Replace("\n"," ");
   if(detail.Length>160)detail=detail.Substring(0,160);
   if(state==next && status==detail && observedAlive==alive)return;
   state=next;status=detail;observedAlive=alive;revision++;
   AddDiagnostic("Observed: "+next+" / alive="+alive.ToString());
  }
 }
 public void AddObservedMarker(string marker){
  if(marker!="Remote connected" && marker!="Authentication pending" &&
     marker!="Remote channel unavailable" && marker!="Remote start failed" &&
     marker!="Remote tool started" && marker!="Remote tool completed" &&
     marker!="Remote tool failed" && marker!="Local MCP recovering" &&
     marker!="Remote launcher replaced")
   throw new InvalidOperationException("RC1_OBSERVER_MARKER_DENIED");
  lock(sync){
   if(!sourceIsReal||ownership!=Ownership.Adopted)throw new InvalidOperationException("RC1_NOT_OBSERVING");
   cursor++;revision++;
   if(tail.Count==maxTail)tail.Dequeue();
   tail.Enqueue(cursor.ToString("D6")+" | "+marker);
  }
 }
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
  lock(sync){return managedMode && stopApproved && observedAlive;}
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
    {"sessionId",session},{"fake",!sourceIsReal},{"isActualRemote",sourceIsReal},
    {"ownership",ownership.ToString()},{"processAlive",sourceIsReal?(observedAlive?"observed_alive":"observed_exited"):"unknown"},
    {"processPid",sourceIsReal?observedPid:0},
    {"transportReady",state=="Ready"?(managedMode?"MANAGED_READY":sourceIsReal?"OBSERVED_READY":"FAKE_READY"):"not_connected"},
    {"authState",state=="AuthPending"?(managedMode?"MANAGED_AUTH":sourceIsReal?"OBSERVED_AUTH":"FAKE_AUTH"):"unavailable"},
    {"toolActivity","idle"},{"state",state},{"status",status},
    {"logStreamEpoch",epoch},{"logCursor",cursor},{"missed",missed},
    {"tail",tail.ToArray()},{"diagnostics",diagnostics.ToArray()},
    {"revision",revision},{"canStop",managedMode&&observedAlive},
    {"canReconnect",managedMode&&observedAlive},
    {"canStart",managedMode&&!observedAlive},{"canUpdate",false},{"canLogout",false}
   };
  }
 }
}
