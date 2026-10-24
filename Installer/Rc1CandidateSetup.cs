// Private RDC Relay 1.6.0 RC1 side-by-side Setup route. Never compiled
// runnable in G0/G1: RDC_RC1_BLOCKED makes Main return 42 before any I/O.
// A future separate reviewed build + owner G1 gate must change marker/flag.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

internal static class RdcRc1CandidateSetup {
 static readonly string[] Required=new string[]{
  "Source/remote-window.ps1","Source/rc1-tray-host.ps1","Source/rc1-owner-gui.ps1",
  "Source/RdcOwnerWire.cs","Source/RdcOwnerRuntime.cs","Source/RdcOwnerProcess.cs",
  "Source/RdcOwnerTicketStore.cs","Source/RdcOwnerRemoteState.cs",
  "Source/rc1-candidate.json","Source/RDCRelay.ico",
  "Source/divider-caustic.ps","Source/divider-caustic-detail.ps",
  "Source/divider-particles.ps","Source/divider-particles-core.ps",
  "Source/update-notice.ps1","Source/update.ps1","RdcOwnerRuntime.dll"
 };
 static void PathSafe(string path){
  string full=Path.GetFullPath(path),p=full;
  while(!String.IsNullOrEmpty(p)){
   if(File.Exists(p)||Directory.Exists(p)){
    if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
      throw new InvalidOperationException("RC1_REPARSE_REFUSED");
   }
   string parent=Path.GetDirectoryName(p);
   if(String.IsNullOrEmpty(parent)||parent==p)break;p=parent;
  }
 }
 static Dictionary<string,object> ReadJson(string file){
  return new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(file,Encoding.UTF8));
 }
 static string Hash(string file){
  using(var sha=SHA256.Create())
  using(var input=File.OpenRead(file))
   return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","");
 }
 static void ValidateSource(string root){
  PathSafe(root);
  if(!File.Exists(Path.Combine(root,"owner-source-manifest.json")))
   throw new InvalidOperationException("RC1_MANIFEST_ABSENT");
  var manifest=ReadJson(Path.Combine(root,"owner-source-manifest.json"));
  if((string)manifest["candidate"]!="1.6.0 RC1")throw new InvalidOperationException("RC1_BAD_CANDIDATE");
  var candidate=ReadJson(Path.Combine(root,"Source","rc1-candidate.json"));
  // This guard is intentionally false in current topic branch. No installer
  // runnable before changed, independently reviewed install transaction gate.
  if(!Convert.ToBoolean(candidate["installable"]))
   throw new InvalidOperationException("RC1_INSTALL_NOT_OWNER_AUTHORIZED");
  var listed=new List<string>();
  var rows=(System.Collections.ArrayList)manifest["files"];
  foreach(Dictionary<string,object> item in rows)
    listed.Add((string)item["name"]);
  if(listed.Count!=Required.Length || listed.Count!=listed.Distinct(StringComparer.Ordinal).Count())
   throw new InvalidOperationException("RC1_MANIFEST_NOT_EXACT_UNIQUE_SET");
  foreach(string required in Required){
   if(listed.Count(x=>String.Equals(x,required,StringComparison.Ordinal))!=1)
    throw new InvalidOperationException("RC1_MISSING_PAYLOAD:"+required);
   string file=Path.Combine(root,required.Replace('/',Path.DirectorySeparatorChar));
   PathSafe(file);
   if(!File.Exists(file))throw new InvalidOperationException("RC1_PAYLOAD_ABSENT:"+required);
   foreach(Dictionary<string,object> row in rows){
    if((string)row["name"]!=required)continue;
    if(!String.Equals(Hash(file),(string)row["sha256"],StringComparison.Ordinal))
      throw new InvalidOperationException("RC1_PAYLOAD_HASH:"+required);
   }
  }
 }
 static int Main(string[] args){
#if RDC_RC1_BLOCKED
  // Build and inspect only; this file intentionally cannot install today.
  Console.Error.WriteLine("RC1_OWNER_SETUP_BLOCKED_NEEDS_OS_TRIAL_AND_G1_GO");
  return 42;
#else
  try{
   if(args.Length!=1 || args[0]!="--owner-approved-side-by-side" ||
      Environment.GetEnvironmentVariable("RDC_RC1_OWNER_G1_GO")!="YES")
    throw new InvalidOperationException("RC1_EXPLICIT_G1_GO_REQUIRED");
   string source=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
   ValidateSource(source);
   string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
   if(String.IsNullOrEmpty(local))throw new InvalidOperationException("RC1_NO_APPDATA");
   string root=Path.Combine(local,"RDCRelayOwnerPilot","1.6.0-RC1");
   string app=Path.Combine(root,"app");
   PathSafe(root);PathSafe(app);
   // Never overwrite the installed 1.5.18 nor a previous RC1 candidate.
   if(Directory.Exists(app)||File.Exists(app))throw new InvalidOperationException("RC1_TARGET_EXISTS");
   Directory.CreateDirectory(root);
   string staging=Path.Combine(root,".new-"+Guid.NewGuid().ToString("N"));
   Directory.CreateDirectory(staging);
   bool published=false;
   try{
    foreach(string member in Required){
     string to=Path.Combine(staging,member.Replace('/',Path.DirectorySeparatorChar));
     Directory.CreateDirectory(Path.GetDirectoryName(to));
     File.Copy(Path.Combine(source,member.Replace('/',Path.DirectorySeparatorChar)),to,false);
     if(Hash(to)!=Hash(Path.Combine(source,member.Replace('/',Path.DirectorySeparatorChar))))
      throw new InvalidOperationException("RC1_COPY_HASH_FAIL");
    }
    File.Copy(Path.Combine(source,"owner-source-manifest.json"),Path.Combine(staging,"owner-source-manifest.json"),false);
    PathSafe(app);
    Directory.Move(staging,app);
    published=true;
   }finally{
    // On ambiguous failure NEVER recurse-delete a tree. Leave it recorded
    // for a reviewed cleanup, not uncontrolled removal of foreign files.
    if(!published && Directory.Exists(staging))
     Console.Error.WriteLine("RC1_NOT_CLEAN_STAGING:"+staging);
   }
   Console.WriteLine("RC1_PRIVATE_SIDE_BY_SIDE_STAGED:"+app);
   return 0;
  }catch(Exception e){
   Console.Error.WriteLine("RC1_INSTALL_DENIED:"+e.GetType().Name);
   return 42;
  }
#endif
 }
}
