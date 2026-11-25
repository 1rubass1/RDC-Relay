// Pure synthetic Windows file-system tests for the non-activating release stage.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

public static class RdcReleaseDurableStageAssertions {
 static int count;
 static void Check(bool yes,string message) {
  if(!yes)throw new IOException("RDC_STAGE_TEST_ASSERT:"+message);
  count++;
 }
 static void Refuses(Action action,string message) {
  bool failed=false;
  try{action();}catch(IOException){failed=true;}
  Check(failed,message);
 }
 static string Hash(string path) {
  using(var sha=SHA256.Create())
  using(var f=File.OpenRead(path))
   return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant();
 }
 static string NewDir(string parent,string name) {
  string dir=Path.Combine(parent,name);
  Directory.CreateDirectory(dir);
  return dir;
 }
 static List<RdcReleaseStageMember> Example(string source) {
  var rows=new List<RdcReleaseStageMember>();
  foreach(string name in new[]{
   "Source/rc1-tray-host.ps1","Source/rc1-owner-gui.ps1",
   "RdcOwnerRuntime.dll","RDCRelay.exe"
  }) {
   string file=Path.Combine(source,name.Replace('/',Path.DirectorySeparatorChar));
   Directory.CreateDirectory(Path.GetDirectoryName(file));
   File.WriteAllText(file,"Synthetic payload: "+name+"\n",Encoding.UTF8);
   rows.Add(new RdcReleaseStageMember(name,Hash(file),new FileInfo(file).Length));
  }
  return rows;
 }
 static void JournalCorruption(string store) {
  string releases=Path.Combine(store,"releases");
  string[] slots=Directory.GetFiles(releases,".rdc-stage-journal-*");
  Check(slots.Length==2,"dual durable journal slots exist");
  string first=slots[0];
  File.WriteAllText(first,"untrusted-payload");
 }
 public static string Run(string testRoot) {
  count=0;
  if(!Path.IsPathRooted(testRoot))throw new ArgumentException("ABSOLUTE_TEST_ROOT_REQUIRED");
  string source=NewDir(testRoot,"fixture-source");
  var rows=Example(source);
  string store=NewDir(testRoot,"success-store");
  var prepared=RdcReleaseDurableStage.Prepare(source,store,rows);
  Check(prepared.State=="READY"&&Directory.Exists(prepared.ReleasePath),"stage prepared");
  Check(Path.GetFileName(prepared.ReleasePath)=="release-"+prepared.PlanHash.Substring(0,24),
   "content-addressed immutable release path");
  Check(File.Exists(Path.Combine(prepared.ReleasePath,"RdcOwnerRuntime.dll")),
   "real Host runtime member staged");
  Check(File.Exists(Path.Combine(prepared.ReleasePath,"Source","rc1-owner-gui.ps1")),
   "separate Owner GUI member staged");
  Check(File.Exists(Path.Combine(prepared.ReleasePath,".rdc-stage-plan")),
   "durable manifest ledger present");
  var repeat=RdcReleaseDurableStage.Prepare(source,store,rows);
  Check(repeat.ReleasePath==prepared.ReleasePath&&repeat.PlanHash==prepared.PlanHash,
   "retry of identical release is idempotent");
  Check(RdcReleaseDurableStage.Recover(store,rows).State=="READY",
   "recovery of fully prepared release is read-only");
  Check(!Directory.Exists(Path.Combine(store,"Source"))&&
   !File.Exists(Path.Combine(store,"RDC Relay.lnk")),
   "staging cannot activate install or shortcuts");

  // Prepare a later release side by side. Old immutable bytes are preserved.
  string changed=Path.Combine(source,"Source","rc1-owner-gui.ps1");
  byte[] originalBytes=File.ReadAllBytes(changed);
  File.AppendAllText(changed,"new release candidate");
  var nextRows=new List<RdcReleaseStageMember>();
  foreach(var member in rows) {
   if(member.Name=="Source/rc1-owner-gui.ps1")
    nextRows.Add(new RdcReleaseStageMember(member.Name,Hash(changed),new FileInfo(changed).Length));
   else nextRows.Add(member);
  }
  var next=RdcReleaseDurableStage.Prepare(source,store,nextRows);
  Check(next.ReleasePath!=prepared.ReleasePath&&Directory.Exists(prepared.ReleasePath),
   "next candidate is prepared side by side rather than replacing old release");
  Check(RdcReleaseDurableStage.Recover(store,nextRows).State=="READY",
   "latest release has its own verified recovery journal");
  Check(Hash(Path.Combine(prepared.ReleasePath,"Source","rc1-owner-gui.ps1"))==
   rows.Single(x=>x.Name=="Source/rc1-owner-gui.ps1").Sha256,
   "original release payload remains byte-identical for future rollback");
  Refuses(()=>RdcReleaseDurableStage.Recover(store,rows),
   "old manifest cannot authorize latest recovery journal");
  File.WriteAllBytes(changed,originalBytes);
  Check(Hash(changed)==rows.Single(x=>x.Name=="Source/rc1-owner-gui.ps1").Sha256,
   "candidate fixture restored before further failure injection");

  string beforeMove=NewDir(testRoot,"failure-before-move");
  Refuses(()=>RdcReleaseDurableStage.PrepareWithFault(source,beforeMove,rows,"before-move"),
   "controlled crash immediately before move");
  var recoveredBefore=RdcReleaseDurableStage.Recover(beforeMove,rows);
  Check(recoveredBefore.State=="RECOVERED"&&Directory.Exists(recoveredBefore.ReleasePath),
   "recovery verifies full staged set before completing the rename");
  Check(RdcReleaseDurableStage.Recover(beforeMove,rows).State=="READY",
   "recovery is idempotent");

  string afterMove=NewDir(testRoot,"failure-after-move");
  Refuses(()=>RdcReleaseDurableStage.PrepareWithFault(source,afterMove,rows,"after-move"),
   "controlled crash after directory rename");
  var recoveredAfter=RdcReleaseDurableStage.Recover(afterMove,rows);
  Check(recoveredAfter.State=="RECOVERED"&&Directory.Exists(recoveredAfter.ReleasePath),
   "after-move recovery recognizes verified already-renamed release");

  string afterCopy=NewDir(testRoot,"failure-after-copy");
  Refuses(()=>RdcReleaseDurableStage.PrepareWithFault(source,afterCopy,rows,"after-copy"),
   "controlled crash before MOVING journal phase");
  Check(RdcReleaseDurableStage.Recover(afterCopy,rows).State=="INCOMPLETE",
   "incomplete staged content is never silently activated");
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,afterCopy,rows),
   "an unfinished transaction prevents next install");
  Check(Directory.GetDirectories(Path.Combine(afterCopy,"releases"),".staging-*").Length==1,
   "failed staged directory is retained for forensic recovery, not deleted");
  Check(RdcReleaseDurableStage.AbandonIncomplete(afterCopy,rows).State=="ABORTED",
   "explicit fail-closed abandon records failed transaction");
  Check(Directory.GetDirectories(Path.Combine(afterCopy,"releases"),".aborted-*").Length==1,
   "aborted stage is quarantined intact, never silently deleted");
  Check(RdcReleaseDurableStage.Recover(afterCopy,rows).State=="ABORTED",
   "abandoned stage never activates on next launch");
  Check(RdcReleaseDurableStage.Prepare(source,afterCopy,rows).State=="READY",
   "a complete retry is possible after explicit inert-stage quarantine");

  string justBegin=NewDir(testRoot,"failure-after-begin");
  Refuses(()=>RdcReleaseDurableStage.PrepareWithFault(source,justBegin,rows,"after-begin"),
   "durable journal records BEGIN before copying");
  Check(RdcReleaseDurableStage.Recover(justBegin,rows).State=="INCOMPLETE",
   "BEGIN-only transaction is not treated as complete");
  Check(RdcReleaseDurableStage.AbandonIncomplete(justBegin,rows).State=="ABORTED",
   "safe journal-only abort does not require any staged source files");
  Check(RdcReleaseDurableStage.Prepare(source,justBegin,rows).State=="READY",
   "retry after an empty aborted stage completes safely");
  Refuses(()=>RdcReleaseDurableStage.AbandonIncomplete(store,nextRows),
   "published ready state cannot be abandoned through test recovery");

  string unexpected=NewDir(testRoot,"extra-file-store");
  File.WriteAllText(Path.Combine(source,"unexpected-secrets.json"),"PRIVATE");
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,unexpected,rows),
   "unexpected or secret source file fails exact allowlist");
  File.Delete(Path.Combine(source,"unexpected-secrets.json"));

  string mismatched=NewDir(testRoot,"mismatched-store");
  string hostFile=Path.Combine(source,"RdcOwnerRuntime.dll");
  File.AppendAllText(hostFile,"changed after hashing");
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,mismatched,rows),
   "hash mismatch refused before any stage is published");
  File.Delete(hostFile);
  File.WriteAllText(hostFile,"Synthetic payload: RdcOwnerRuntime.dll\n",Encoding.UTF8);
  Check(Hash(hostFile)==rows.Single(x=>x.Name=="RdcOwnerRuntime.dll").Sha256,
   "source fixture restored to exact original bytes");

  var traversal=new List<RdcReleaseStageMember>(rows);
  traversal[0]=new RdcReleaseStageMember("../malicious.ps1",rows[0].Sha256,rows[0].Length);
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,NewDir(testRoot,"traversal-store"),traversal),
   "member path traversal refused");

  var duplicate=new List<RdcReleaseStageMember>(rows);
  duplicate.Add(new RdcReleaseStageMember("rdcownerruntime.dll",rows[2].Sha256,rows[2].Length));
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,NewDir(testRoot,"collision-store"),duplicate),
   "case-insensitive collisions refused");

  var oldGui=new List<RdcReleaseStageMember>(rows.Where(x=>x.Name!="Source/rc1-owner-gui.ps1"));
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,NewDir(testRoot,"legacy-gui-store"),oldGui),
   "cannot stage legacy-only GUI without separate Owner GUI");

  var privatePilot=new List<RdcReleaseStageMember>(rows);
  privatePilot.Add(new RdcReleaseStageMember("Source/rc1-candidate.json",rows[1].Sha256,rows[1].Length));
  Refuses(()=>RdcReleaseDurableStage.Prepare(source,
   NewDir(testRoot,"private-pilot-marker-store"),privatePilot),
   "private RC1 candidate marker cannot enter a public release plan");

  string corrupt=NewDir(testRoot,"corrupt-journal-store");
  var ok=RdcReleaseDurableStage.Prepare(source,corrupt,rows);
  JournalCorruption(corrupt);
  Refuses(()=>RdcReleaseDurableStage.Recover(corrupt,rows),
   "corrupt journal fails closed instead of attempting automatic repair");

  string tampered=NewDir(testRoot,"tampered-prepared-store");
  var done=RdcReleaseDurableStage.Prepare(source,tampered,rows);
  File.AppendAllText(Path.Combine(done.ReleasePath,"Source","rc1-tray-host.ps1"),"malicious");
  Refuses(()=>RdcReleaseDurableStage.Recover(tampered,rows),
   "tampered immutable release bytes are rejected");

  var wrong=new List<RdcReleaseStageMember>(rows);
  wrong[0]=new RdcReleaseStageMember(rows[0].Name,Hash(hostFile),rows[0].Length);
  Refuses(()=>RdcReleaseDurableStage.Recover(store,wrong),
   "recovery refuses a manifest different from the durable journal");

  string competing=NewDir(testRoot,"exclusive-lock-store");
  RdcReleaseDurableStage.Prepare(source,competing,rows);
  string lockFile=Path.Combine(competing,"releases",".rdc-stage-lock");
  using(var acquired=new FileStream(lockFile,FileMode.Open,FileAccess.ReadWrite,FileShare.None)) {
   Refuses(()=>RdcReleaseDurableStage.Prepare(source,competing,rows),
    "parallel stage preparation cannot obtain exclusive lock");
  }
  Check(!File.Exists(Path.Combine(store,"RDC Relay.lnk")),
   "no actions outside synthetic release stores");
  return "RDC_RELEASE_DURABLE_STAGE_PASS="+count+" FAIL=0";
 }
}
