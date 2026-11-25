// RDC Relay 1.6: durable, non-activating full-Host payload preparation.
// This deliberately cannot publish ARP, shortcuts, launch a Host or touch Remote.
// Future public Setup must supply trusted embedded manifest hashes, run independent
// install/ownership preflight, and integrate a separately journaled publish phase.
using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

internal sealed class RdcReleaseStageMember {
 internal readonly string Name, Sha256;
 internal readonly long Length;
 internal RdcReleaseStageMember(string name,string sha256,long length) {
  Name=name;Sha256=sha256;Length=length;
 }
}

internal sealed class RdcReleaseStageResult {
 internal readonly string State, ReleasePath, PlanHash;
 internal RdcReleaseStageResult(string state,string path,string hash) {
  State=state;ReleasePath=path;PlanHash=hash;
 }
}

internal static class RdcReleaseDurableStage {
 const string Signature="RDC_FULL_HOST_STAGE_V1";
 const string Ledger=".rdc-stage-plan";
 const long MaxMember=100L*1024*1024,MaxTotal=250L*1024*1024;
 static readonly Regex Digest=new Regex(@"\A[0-9a-fA-F]{64}\z",RegexOptions.CultureInvariant);
 static readonly Regex Segment=new Regex(@"\A[A-Za-z0-9][A-Za-z0-9._ -]*\z",RegexOptions.CultureInvariant);
 static readonly Regex StageName=new Regex(@"\A\.staging-[0-9a-f]{12}-[0-9a-f]{32}\z",RegexOptions.CultureInvariant);
 static readonly Regex ReleaseName=new Regex(@"\Arelease-[0-9a-f]{24}\z",RegexOptions.CultureInvariant);
 internal sealed class State {
  internal long Generation;
  internal string Phase,Plan,Stage,Release;
 }
 static string Hash(byte[] bytes) {
  using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
 }
 static string HashFile(string path) {
  using(var sha=SHA256.Create())
  using(var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))
   return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant();
 }
 static string Absolute(string path) {
  if(String.IsNullOrWhiteSpace(path)||!Path.IsPathRooted(path))
   throw new IOException("RDC_STAGE_PATH_NOT_ABSOLUTE");
  string full=Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
  if(String.IsNullOrWhiteSpace(full)||full.Length<5)
   throw new IOException("RDC_STAGE_PATH_UNSAFE_ROOT");
  return full;
 }
 static void NoReparseAncestors(string path) {
  string cursor=Path.GetFullPath(path);
  while(!String.IsNullOrEmpty(cursor)) {
   if(Directory.Exists(cursor)||File.Exists(cursor)) {
    if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0)
     throw new IOException("RDC_STAGE_REPARSE_REFUSED");
   }
   string parent=Path.GetDirectoryName(cursor);
   if(String.IsNullOrEmpty(parent)||String.Equals(parent,cursor,StringComparison.OrdinalIgnoreCase))break;
   cursor=parent;
  }
 }
 static bool Under(string parent,string candidate) {
  return String.Equals(parent,candidate,StringComparison.OrdinalIgnoreCase)||
   candidate.StartsWith(parent+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
 }
 static string SafeMember(string name) {
  if(String.IsNullOrWhiteSpace(name)||name.Length>180||name.Contains("\\")||
     name.StartsWith("/",StringComparison.Ordinal)||name.EndsWith("/",StringComparison.Ordinal))
   throw new IOException("RDC_STAGE_INVALID_MEMBER");
  string[] parts=name.Split('/');
  foreach(string part in parts) {
   if(part.Length>80||!Segment.IsMatch(part)||part=="."||part==".."||
      part.EndsWith(".",StringComparison.Ordinal)||part.EndsWith(" ",StringComparison.Ordinal))
    throw new IOException("RDC_STAGE_MEMBER_ESCAPE");
   string baseName=part.Split('.')[0].ToUpperInvariant();
   if(new[]{"CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9",
    "LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"}.Contains(baseName))
     throw new IOException("RDC_STAGE_RESERVED_MEMBER");
  }
  if(name.EndsWith("/"+Ledger,StringComparison.OrdinalIgnoreCase)||
     String.Equals(name,Ledger,StringComparison.OrdinalIgnoreCase))
   throw new IOException("RDC_STAGE_RESERVED_LEDGER");
  return name;
 }
 static string OnDisk(string root,string name) {
  string full=Path.GetFullPath(Path.Combine(root,name.Replace('/',Path.DirectorySeparatorChar)));
  if(!Under(root,full)||String.Equals(root,full,StringComparison.OrdinalIgnoreCase))
   throw new IOException("RDC_STAGE_PATH_ESCAPE");
  return full;
 }
 static string Plan(IList<RdcReleaseStageMember> rows,out List<RdcReleaseStageMember> sorted) {
  if(rows==null||rows.Count<4||rows.Count>128)throw new IOException("RDC_STAGE_MEMBER_COUNT");
  sorted=rows.OrderBy(x=>x.Name,StringComparer.Ordinal).ToList();
  var distinct=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  long total=0;
  var text=new StringBuilder(Signature+"\n");
  foreach(var item in sorted) {
   if(item==null||!Digest.IsMatch(item.Sha256??"")||
      item.Length<0||item.Length>MaxMember)throw new IOException("RDC_STAGE_BAD_DIGEST_OR_SIZE");
   string name=SafeMember(item.Name);
   if(!distinct.Add(name))throw new IOException("RDC_STAGE_DUPLICATE_MEMBER");
   string[] parts=name.Split('/');
   for(int i=1;i<parts.Length;i++) {
    string parent=String.Join("/",parts.Take(i).ToArray());
    if(distinct.Contains(parent))throw new IOException("RDC_STAGE_FILE_DIRECTORY_COLLISION");
    paths.Add(parent);
   }
   if(paths.Contains(name))throw new IOException("RDC_STAGE_DIRECTORY_FILE_COLLISION");
   total+=item.Length;if(total>MaxTotal)throw new IOException("RDC_STAGE_TOO_LARGE");
   text.Append(name).Append("|").Append(item.Length).Append("|")
    .Append(item.Sha256.ToLowerInvariant()).Append("\n");
  }
  // Refuse accidentally repackaging the old single-window 1.5.x UI.
  foreach(string required in new[]{"Source/rc1-tray-host.ps1","Source/rc1-owner-gui.ps1",
   "RdcOwnerRuntime.dll"}) {
   if(!distinct.Contains(required))throw new IOException("RDC_STAGE_NOT_FULL_HOST_GUI");
  }
  if(distinct.Any(n=>n.Equals("Source/rc1-candidate.json",StringComparison.OrdinalIgnoreCase)))
   throw new IOException("RDC_STAGE_PRIVATE_RC1_MARKER_REFUSED");
  if(distinct.Any(n=>n.Equals("Source/release-review.json",StringComparison.OrdinalIgnoreCase)))
   throw new IOException("RDC_STAGE_REVIEW_MARKER_REFUSED");
  return text.ToString();
 }
 // Walk without SearchOption.AllDirectories: its recursion can traverse a
 // directory symlink *before* a post-hoc reparse check. Reject links first.
 static IEnumerable<string> SafeFiles(string root) {
  var pending=new Stack<string>();pending.Push(root);
  int visited=0;
  while(pending.Count!=0) {
   string dir=pending.Pop();NoReparseAncestors(dir);
   if(++visited>512)throw new IOException("RDC_STAGE_TOO_MANY_DIRECTORIES");
   foreach(string entry in Directory.EnumerateFileSystemEntries(dir)) {
    FileAttributes attr=File.GetAttributes(entry);
    if((attr&FileAttributes.ReparsePoint)!=0)
     throw new IOException("RDC_STAGE_REPARSE_MEMBER_REFUSED");
    if((attr&FileAttributes.Directory)!=0)pending.Push(entry);
    else yield return entry;
   }
  }
 }
 static void ExactSource(string source,List<RdcReleaseStageMember> rows) {
  var expected=new HashSet<string>(rows.Select(x=>x.Name),StringComparer.OrdinalIgnoreCase);
  foreach(string file in SafeFiles(source)) {
   string relative=file.Substring(source.Length+1).Replace('\\','/');
   if(!expected.Remove(relative))throw new IOException("RDC_STAGE_UNEXPECTED_OR_DUPLICATE_SOURCE");
  }
  if(expected.Count!=0)throw new IOException("RDC_STAGE_MISSING_SOURCE");
 }
 static void VerifyTree(string location,List<RdcReleaseStageMember> rows,string planText) {
  NoReparseAncestors(location);
  var expected=new HashSet<string>(rows.Select(x=>x.Name),StringComparer.OrdinalIgnoreCase);
  expected.Add(Ledger);
  foreach(string file in SafeFiles(location)) {
   string relative=file.Substring(location.Length+1).Replace('\\','/');
   if(!expected.Remove(relative))throw new IOException("RDC_STAGE_RELEASE_EXTRA_FILE");
  }
  if(expected.Count!=0)throw new IOException("RDC_STAGE_RELEASE_MEMBER_MISSING");
  foreach(var row in rows) {
   string file=OnDisk(location,row.Name);
   var info=new FileInfo(file);
   if(info.Length!=row.Length||!String.Equals(HashFile(file),row.Sha256,StringComparison.OrdinalIgnoreCase))
    throw new IOException("RDC_STAGE_RELEASE_HASH_MISMATCH");
  }
  if(File.ReadAllText(Path.Combine(location,Ledger),new UTF8Encoding(false,true))!=planText)
   throw new IOException("RDC_STAGE_LEDGER_MISMATCH");
 }
 static string JournalText(State s) {
  return Signature+"|"+s.Generation+"|"+s.Phase+"|"+s.Plan+"|"+s.Stage+"|"+s.Release;
 }
 static bool ValidJournal(string file,out State parsed) {
  parsed=null;
  try {
   NoReparseAncestors(file);
   var info=new FileInfo(file);
   if(!info.Exists)return false;
   if(info.Length<80||info.Length>350)throw new IOException("RDC_STAGE_JOURNAL_SIZE");
   string data=new UTF8Encoding(false,true).GetString(File.ReadAllBytes(file));
   string[] lines=data.Split(new[]{'\n'},StringSplitOptions.RemoveEmptyEntries);
   if(lines.Length!=2||Hash(Encoding.UTF8.GetBytes(lines[0]))!=lines[1])
    throw new IOException("RDC_STAGE_JOURNAL_INTEGRITY");
   string[] cols=lines[0].Split('|');
   long gen;
   if(cols.Length!=6||cols[0]!=Signature||!Int64.TryParse(cols[1],out gen)||
      gen<1||gen>1000000||!Digest.IsMatch(cols[3])||
      !StageName.IsMatch(cols[4])||!ReleaseName.IsMatch(cols[5])||
      (cols[2]!="WRITING"&&cols[2]!="MOVING"&&cols[2]!="READY"&&cols[2]!="ABORTED"))
    throw new IOException("RDC_STAGE_JOURNAL_SCHEMA");
   parsed=new State{Generation=gen,Phase=cols[2],Plan=cols[3],Stage=cols[4],Release=cols[5]};
   return true;
  }catch(FileNotFoundException){return false;}
 }
 static State ReadJournal(string releases) {
  State best=null;
  for(int i=0;i<2;i++) {
   string path=Path.Combine(releases,".rdc-stage-journal-"+i);
   State candidate;
   // Malformed existing journal is a hard refusal, never a fresh install.
   if(!ValidJournal(path,out candidate))continue;
   if(best==null||candidate.Generation>best.Generation)best=candidate;
   else if(candidate.Generation==best.Generation&&JournalText(candidate)!=JournalText(best))
    throw new IOException("RDC_STAGE_CONFLICTING_JOURNAL");
  }
  return best;
 }
 static void SaveJournal(string releases,State s) {
  string dest=Path.Combine(releases,".rdc-stage-journal-"+(s.Generation%2));
  string tmp=Path.Combine(releases,".rdc-stage-write-"+Guid.NewGuid().ToString("N"));
  string payload=JournalText(s);
  byte[] bytes=Encoding.UTF8.GetBytes(payload+"\n"+Hash(Encoding.UTF8.GetBytes(payload))+"\n");
  try {
   using(var stream=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
    stream.Write(bytes,0,bytes.Length);stream.Flush(true);
   }
   NoReparseAncestors(dest);
   if(File.Exists(dest))File.Replace(tmp,dest,null);
   else File.Move(tmp,dest);
  }finally{if(File.Exists(tmp))File.Delete(tmp);}
 }
 static void Next(string releases,State state,string phase) {
  state.Generation++;state.Phase=phase;SaveJournal(releases,state);
 }
 // An interrupted WRITING phase has never been published. Move only its
 // exact internal staging directory into an inert quarantine; retain all bytes.
 // This makes a future retry possible without risking an active release.
 internal static RdcReleaseStageResult AbandonIncomplete(string storeRoot,
  IList<RdcReleaseStageMember> rows) {
  string store=Absolute(storeRoot);
  if(!Directory.Exists(store))throw new IOException("RDC_STAGE_STORE_MISSING");
  NoReparseAncestors(store);
  List<RdcReleaseStageMember> ordered;
  string planText=Plan(rows,out ordered),hash=Hash(Encoding.UTF8.GetBytes(planText));
  string releases=Path.Combine(store,"releases");
  if(!Directory.Exists(releases))throw new IOException("RDC_STAGE_NO_JOURNAL");
  NoReparseAncestors(releases);
  string lockFile=Path.Combine(releases,".rdc-stage-lock");
  NoReparseAncestors(lockFile);
  using(var mutex=new FileStream(lockFile,FileMode.OpenOrCreate,
   FileAccess.ReadWrite,FileShare.None)) {
   State state=ReadJournal(releases);
   if(state==null||state.Plan!=hash||state.Phase!="WRITING")
    throw new IOException("RDC_STAGE_ABORT_NOT_AUTHORIZED");
   string stage=OnDisk(releases,state.Stage);
   string final=OnDisk(releases,state.Release);
   string quarantine=OnDisk(releases,
    ".aborted-"+state.Stage.Substring(".staging-".Length));
   if(Directory.Exists(final)||File.Exists(final)||
      File.Exists(stage)||File.Exists(quarantine))
    throw new IOException("RDC_STAGE_ABORT_AMBIGUOUS");
   if(Directory.Exists(stage)) {
    NoReparseAncestors(stage);
    if(Directory.Exists(quarantine))throw new IOException("RDC_STAGE_ABORT_COLLISION");
    Directory.Move(stage,quarantine);
   }else if(!Directory.Exists(quarantine)) {
    // after-begin failed before creating an actual staging directory
   }else NoReparseAncestors(quarantine);
   Next(releases,state,"ABORTED");
   return new RdcReleaseStageResult("ABORTED","",hash);
  }
 }
 static void CopyChecked(string src,string dst,RdcReleaseStageMember member) {
  // Repeat the path checks immediately before use; the initial traversal
  // alone would permit a source-path junction swap during long copies.
  NoReparseAncestors(src);
  NoReparseAncestors(dst);
  Directory.CreateDirectory(Path.GetDirectoryName(dst));
  NoReparseAncestors(Path.GetDirectoryName(dst));
  if(new FileInfo(src).Length!=member.Length||
    !String.Equals(HashFile(src),member.Sha256,StringComparison.OrdinalIgnoreCase))
   throw new IOException("RDC_STAGE_SOURCE_HASH_MISMATCH");
  using(var reader=new FileStream(src,FileMode.Open,FileAccess.Read,FileShare.Read))
  using(var writer=new FileStream(dst,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
   reader.CopyTo(writer);writer.Flush(true);
  }
  if(new FileInfo(dst).Length!=member.Length||
     !String.Equals(HashFile(dst),member.Sha256,StringComparison.OrdinalIgnoreCase))
   throw new IOException("RDC_STAGE_COPY_HASH_MISMATCH");
 }
 static void WriteLedger(string stage,string planText) {
  string path=Path.Combine(stage,Ledger);
  byte[] bytes=Encoding.UTF8.GetBytes(planText);
  using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
   f.Write(bytes,0,bytes.Length);f.Flush(true);
  }
 }
 // Production API has no fault-injection parameter and never publishes
 // ARP, shortcuts, new Host processes or external pointers.
 internal static RdcReleaseStageResult Prepare(string sourceRoot,string storeRoot,
  IList<RdcReleaseStageMember> rows) {
  return PrepareCore(sourceRoot,storeRoot,rows,null);
 }
#if RDC_INSTALLER_TEST
 // Compile-time test-only seam, omitted entirely from public release builds.
 internal static RdcReleaseStageResult PrepareWithFault(string sourceRoot,string storeRoot,
  IList<RdcReleaseStageMember> rows,string failAt) {
  return PrepareCore(sourceRoot,storeRoot,rows,failAt);
 }
#endif
 static RdcReleaseStageResult PrepareCore(string sourceRoot,string storeRoot,
  IList<RdcReleaseStageMember> rows,string failAt) {
  string source=Absolute(sourceRoot),store=Absolute(storeRoot);
  if(Under(source,store)||Under(store,source))throw new IOException("RDC_STAGE_SOURCE_STORE_OVERLAP");
  if(!Directory.Exists(source)||!Directory.Exists(store))throw new IOException("RDC_STAGE_ROOT_MISSING");
  NoReparseAncestors(source);NoReparseAncestors(store);
  List<RdcReleaseStageMember> ordered;
  string planText=Plan(rows,out ordered),hash=Hash(Encoding.UTF8.GetBytes(planText));
  string releases=Path.Combine(store,"releases");
  NoReparseAncestors(releases);
  Directory.CreateDirectory(releases);
  string lockFile=Path.Combine(releases,".rdc-stage-lock");
  NoReparseAncestors(lockFile);
  using(var mutex=new FileStream(lockFile,
   FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)) {
   State old=ReadJournal(releases);
   if(old!=null&&old.Phase!="READY"&&old.Phase!="ABORTED")
    throw new IOException("RDC_STAGE_PENDING_RECOVERY");
   if(old!=null&&old.Phase=="READY"&&old.Plan==hash) {
    string existing=OnDisk(releases,old.Release);
    VerifyTree(existing,ordered,planText);
    return new RdcReleaseStageResult("READY",existing,hash);
   }
   ExactSource(source,ordered);
   string release="release-"+hash.Substring(0,24);
   string final=OnDisk(releases,release);
   if(Directory.Exists(final)||File.Exists(final))
    throw new IOException("RDC_STAGE_DESTINATION_CONFLICT");
   string stageName=".staging-"+hash.Substring(0,12)+"-"+Guid.NewGuid().ToString("N");
   string stage=OnDisk(releases,stageName);
   var state=new State{Generation=old==null?1:old.Generation+1,
    Phase="WRITING",Plan=hash,Stage=stageName,Release=release};
   SaveJournal(releases,state);
#if RDC_INSTALLER_TEST
   if(failAt=="after-begin")throw new IOException("RDC_TEST_INJECTED_AFTER_BEGIN");
#endif
   Directory.CreateDirectory(stage);
   foreach(var member in ordered)CopyChecked(OnDisk(source,member.Name),OnDisk(stage,member.Name),member);
   WriteLedger(stage,planText);
   VerifyTree(stage,ordered,planText);
#if RDC_INSTALLER_TEST
   if(failAt=="after-copy")throw new IOException("RDC_TEST_INJECTED_AFTER_COPY");
#endif
   Next(releases,state,"MOVING");
#if RDC_INSTALLER_TEST
   if(failAt=="before-move")throw new IOException("RDC_TEST_INJECTED_BEFORE_MOVE");
#endif
   Directory.Move(stage,final);
#if RDC_INSTALLER_TEST
   if(failAt=="after-move")throw new IOException("RDC_TEST_INJECTED_AFTER_MOVE");
#endif
   Next(releases,state,"READY");
   return new RdcReleaseStageResult("READY",final,hash);
  }
 }
 // On reboot, complete only a hash-verified MOVING phase. WRITING is never
 // guessed complete. No automatic deletion of previous releases/orphan stages.
 internal static RdcReleaseStageResult Recover(string storeRoot,IList<RdcReleaseStageMember> rows) {
  string store=Absolute(storeRoot);
  if(!Directory.Exists(store))throw new IOException("RDC_STAGE_STORE_MISSING");
  NoReparseAncestors(store);
  List<RdcReleaseStageMember> ordered;
  string planText=Plan(rows,out ordered),hash=Hash(Encoding.UTF8.GetBytes(planText));
  string releases=Path.Combine(store,"releases");
  if(!Directory.Exists(releases))return new RdcReleaseStageResult("EMPTY","",hash);
  NoReparseAncestors(releases);
  string lockFile=Path.Combine(releases,".rdc-stage-lock");
  NoReparseAncestors(lockFile);
  using(var mutex=new FileStream(lockFile,
   FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)) {
   State old=ReadJournal(releases);
   if(old==null)return new RdcReleaseStageResult("EMPTY","",hash);
   if(old.Plan!=hash)throw new IOException("RDC_STAGE_RECOVERY_MANIFEST_MISMATCH");
   string final=OnDisk(releases,old.Release);
   string stage=OnDisk(releases,old.Stage);
   if(old.Phase=="WRITING")return new RdcReleaseStageResult("INCOMPLETE","",hash);
   if(old.Phase=="ABORTED") {
    if(Directory.Exists(stage)||Directory.Exists(final))
     throw new IOException("RDC_STAGE_ABORTED_STATE_CONFLICT");
    return new RdcReleaseStageResult("ABORTED","",hash);
   }
   if(old.Phase=="MOVING") {
    if(Directory.Exists(stage)&&!Directory.Exists(final)) {
     VerifyTree(stage,ordered,planText);
     Directory.Move(stage,final);
    }else if(Directory.Exists(stage)||!Directory.Exists(final))
     throw new IOException("RDC_STAGE_AMBIGUOUS_MOVE");
    VerifyTree(final,ordered,planText);
    Next(releases,old,"READY");
    return new RdcReleaseStageResult("RECOVERED",final,hash);
   }
   if(!Directory.Exists(final)||Directory.Exists(stage))
    throw new IOException("RDC_STAGE_READY_CONFLICT");
   VerifyTree(final,ordered,planText);
   return new RdcReleaseStageResult("READY",final,hash);
  }
 }
}
