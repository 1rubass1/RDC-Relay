// RDC Relay 1.6.0: source-review package contract, NOT a Setup trust root.
// Candidate metadata is unauthenticated. Future signed Setup must EMBED a
// separate trusted manifest before authorizing the durable staging API.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

internal static class RdcReleaseReviewPackage {
 internal const string Kind="FULL_HOST_GUI_SOURCE_REVIEW_ONLY";
 internal const string Version="1.6.0";
 internal static readonly string[] Required={
  "Source/remote-window.ps1","Source/rc1-tray-host.ps1",
  "Source/rc1-owner-gui.ps1","Source/rc1-remote-observer.ps1",
  "Source/rc1-quota-client.ps1","Source/RdcOwnerWire.cs",
  "Source/RdcOwnerRuntime.cs","Source/RdcOwnerProcess.cs",
  "Source/RdcOwnerTicketStore.cs","Source/RdcOwnerRemoteState.cs",
  "Source/RdcOwnerManagedProcess.cs","Source/RdcOwnerLogParts.cs","Source/RdcOwnerStartup.cs","Source/RdcUiLanguage.cs",
  "Source/lang/ru-RU.json","Source/lang/en-US.json",
  "Source/RDCRelay.ico","Source/RdcTrayV04.bin",
  "Source/divider-caustic.ps","Source/divider-caustic-detail.ps",
  "Source/divider-particles.ps","Source/divider-particles-core.ps",
  "Source/update-notice.ps1","Source/update.ps1",
  "Source/version.txt","Source/release-review.json","RdcOwnerRuntime.dll"
 };
 static readonly Regex Digest=new Regex(@"\A[0-9a-fA-F]{64}\z",RegexOptions.CultureInvariant);
 static readonly HashSet<string> Expected=new HashSet<string>(Required,StringComparer.Ordinal);
 static void CheckSafe(string path) {
  string p=Path.GetFullPath(path);
  while(!String.IsNullOrEmpty(p)){
   if(File.Exists(p)||Directory.Exists(p)){
    if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
     throw new IOException("RDC_REVIEW_REPARSE_REFUSED");
   }
   string parent=Path.GetDirectoryName(p);
   if(String.IsNullOrEmpty(parent)||parent==p)break;
   p=parent;
  }
 }
 static string Sha(string path) {
  using(var sha=SHA256.Create())
  using(var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))
   return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant();
 }
 static object Need(Dictionary<string,object> record,string key) {
  object item;
  if(record==null||!record.TryGetValue(key,out item))
   throw new IOException("RDC_REVIEW_MISSING_FIELD:"+key);
  return item;
 }
 static bool False(Dictionary<string,object> model,string key) {
  object raw=Need(model,key);
  return raw is bool && !(bool)raw;
 }
 // No SearchOption.AllDirectories, which can follow links before we reject.
 static IEnumerable<string> SafeFiles(string root) {
  var dirs=new Stack<string>();dirs.Push(root);
  int count=0;
  while(dirs.Count>0){
   string dir=dirs.Pop();
   CheckSafe(dir);
   if(++count>256)throw new IOException("RDC_REVIEW_DIR_LIMIT");
   foreach(string item in Directory.EnumerateFileSystemEntries(dir)){
    FileAttributes attr=File.GetAttributes(item);
    if((attr&FileAttributes.ReparsePoint)!=0)
     throw new IOException("RDC_REVIEW_SYMLINK_REFUSED");
    if((attr&FileAttributes.Directory)!=0)dirs.Push(item);
    else yield return item;
   }
  }
 }
 internal static List<RdcReleaseStageMember> Validate(string packageRoot){
  if(String.IsNullOrWhiteSpace(packageRoot)||!Path.IsPathRooted(packageRoot))
   throw new IOException("RDC_REVIEW_ABSOLUTE_ROOT_REQUIRED");
  string root=Path.GetFullPath(packageRoot).TrimEnd(Path.DirectorySeparatorChar);
  CheckSafe(root);
  if(!Directory.Exists(root))throw new IOException("RDC_REVIEW_ROOT_MISSING");
  string manifest=Path.Combine(root,"review-manifest.json");
  CheckSafe(manifest);
  var info=new FileInfo(manifest);
  if(!info.Exists||info.Length<100||info.Length>16384)
   throw new IOException("RDC_REVIEW_MANIFEST_SIZE");
  var json=new UTF8Encoding(false,true).GetString(File.ReadAllBytes(manifest));
  var serializer=new JavaScriptSerializer();
  serializer.MaxJsonLength=16384;
  var value=serializer.Deserialize<Dictionary<string,object>>(json);
  if(value==null||value.Count!=8||Convert.ToString(Need(value,"schema"))!="1"||
     !String.Equals(Need(value,"kind") as string,Kind,StringComparison.Ordinal)||
     !String.Equals(Need(value,"version") as string,Version,StringComparison.Ordinal)||
     !String.Equals(Need(value,"publisher") as string,"RUBASS",StringComparison.Ordinal)||
     !False(value,"installable")||!False(value,"publishable")||!False(value,"launchEnabled"))
   throw new IOException("RDC_REVIEW_NOT_INERT_FULL_HOST_PACKAGE");
  var records=Need(value,"files") as ArrayList;
  if(records==null||records.Count!=Required.Length)
   throw new IOException("RDC_REVIEW_MEMBER_COUNT");
  var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  var result=new List<RdcReleaseStageMember>();
  foreach(object item in records) {
   var row=item as Dictionary<string,object>;
   if(row==null||row.Count!=3)throw new IOException("RDC_REVIEW_BAD_ROW");
   string name=Need(row,"name") as string;
   string hash=Need(row,"sha256") as string;
   long size;
   if(name==null||!Expected.Contains(name)||!seen.Add(name)||
      hash==null||!Digest.IsMatch(hash)||
      !Int64.TryParse(Convert.ToString(Need(row,"bytes"),
        System.Globalization.CultureInfo.InvariantCulture),out size)||
      size<=0||size>100L*1024*1024)
    throw new IOException("RDC_REVIEW_ROW_REJECTED");
   string file=Path.Combine(root,"payload",name.Replace('/',Path.DirectorySeparatorChar));
   CheckSafe(file);
   if(!File.Exists(file)||new FileInfo(file).Length!=size||
      !String.Equals(Sha(file),hash,StringComparison.OrdinalIgnoreCase))
    throw new IOException("RDC_REVIEW_PAYLOAD_HASH_REFUSED");
   result.Add(new RdcReleaseStageMember(name,hash,size));
  }
  if(seen.Count!=Expected.Count)throw new IOException("RDC_REVIEW_MISSING_REQUIRED_MEMBER");
  // Source/version.txt is generated for the 1.6 review package, never
  // copied from the legacy 1.5.18 checkout.
  string versionFile=Path.Combine(root,"payload","Source","version.txt");
  if(File.ReadAllText(versionFile,new UTF8Encoding(false,true)).Trim()!="1.6.0")
   throw new IOException("RDC_REVIEW_VERSION_FILE_MISMATCH");
  string markerPath=Path.Combine(root,"payload","Source","release-review.json");
  CheckSafe(markerPath);
  if(new FileInfo(markerPath).Length>512)
   throw new IOException("RDC_REVIEW_MARKER_TOO_LARGE");
  var marker=serializer.Deserialize<Dictionary<string,object>>(
   File.ReadAllText(markerPath,new UTF8Encoding(false,true)));
  if(marker==null||marker.Count!=4||
     !String.Equals(Need(marker,"kind") as string,Kind,StringComparison.Ordinal)||
     !String.Equals(Need(marker,"version") as string,Version,StringComparison.Ordinal)||
     !False(marker,"installable")||!False(marker,"launchEnabled"))
   throw new IOException("RDC_REVIEW_MARKER_NOT_INERT");
  // Defense in depth: the review archive's four dangerous entrypoints
  // must fail before reaching any Remote, OAuth, GUI or updater action,
  // even when the marker is manually deleted after extraction.
  foreach(string script in new[]{"remote-window.ps1","rc1-tray-host.ps1",
                                  "rc1-quota-client.ps1","update.ps1"}) {
   string location=Path.Combine(root,"payload","Source",script);
   CheckSafe(location);
   bool blocked=false;
   using(var reader=new StreamReader(location,new UTF8Encoding(false,true))) {
    for(int i=0;i<25&&!reader.EndOfStream;i++) {
     string line=reader.ReadLine();
     if(line.Trim()=="throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'"){
      blocked=true;break;
     }
    }
   }
   if(!blocked)throw new IOException("RDC_REVIEW_UNGUARDED_ENTRYPOINT");
  }
  var actual=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  foreach(string file in SafeFiles(root)){
   string relative=file.Substring(root.Length+1).Replace('\\','/');
   if(!actual.Add(relative))throw new IOException("RDC_REVIEW_DUPLICATE_FILE");
  }
  var expected=new HashSet<string>(
   Required.Select(name=>"payload/"+name),StringComparer.OrdinalIgnoreCase);
  expected.Add("review-manifest.json");
  if(!expected.SetEquals(actual))throw new IOException("RDC_REVIEW_UNEXPECTED_FILE");
  return result;
 }
}
