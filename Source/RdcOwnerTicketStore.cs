// Product RC1 own-ticket transaction. No process spawn. C# fixture tests supply
// a callback that throws; production supplies Process.Start itself.
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.RegularExpressions;

public sealed class RdcOwnerTicketStore {
 readonly string root, ticket, ownerSid;
 readonly string runGeneration;
 byte[] attestedBytes;
 long attestedBirth;
 public RdcOwnerTicketStore(string runRoot,string expectedRunGeneration,string logonSid){
  root=Path.GetFullPath(runRoot).TrimEnd(Path.DirectorySeparatorChar);
  ticket=Path.Combine(root,"gui-ticket.json");
  if(!Regex.IsMatch(Path.GetFileName(root),@"^run-[a-f0-9]{32}$") ||
     !Regex.IsMatch(expectedRunGeneration,@"^[a-f0-9]{32}$") ||
     Path.GetDirectoryName(ticket)!=root || !Directory.Exists(root))
   throw new InvalidOperationException("RC1_TICKET_BOUNDARY");
  ownerSid=logonSid;runGeneration=expectedRunGeneration;
  CheckPath(root);
 }
 public string PathName {get{return ticket;}}
 public bool HasOwnedTicket {get{return attestedBytes!=null;}}
 public static void CheckPath(string path){
  string p=Path.GetFullPath(path);
  while(!String.IsNullOrEmpty(p)){
   if(File.Exists(p)||Directory.Exists(p)){
    if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RC1_TICKET_REPARSE");
   }
   string parent=Path.GetDirectoryName(p);
   if(String.IsNullOrEmpty(parent)||parent==p)break;
   p=parent;
  }
 }
 public void Create(string json){
  if(attestedBytes!=null)throw new InvalidOperationException("RC1_TICKET_ALREADY_OWNED");
  CheckPath(root);CheckPath(ticket);
  if(File.Exists(ticket)||Directory.Exists(ticket))
   throw new InvalidOperationException("RC1_TICKET_EXISTS_FOREIGN_OR_UNVERIFIED");
  var map=RdcOwnerWire.Decode(json);
  string mode=RdcOwnerWire.String(map,"remoteMode");
  if(RdcOwnerWire.String(map,"hostGeneration")!=runGeneration ||
     (mode!="FAKE_ONLY_RC1" && mode!="OBSERVED_READ_ONLY_RC1") ||
     RdcOwnerWire.String(map,"nonce").Length!=32)
    throw new InvalidOperationException("RC1_TICKET_PAYLOAD_IDENTITY");
  var data=new UTF8Encoding(false,true).GetBytes(json);
  if(data.Length>2048)throw new InvalidDataException("RC1_TICKET_SIZE");
  var acl=new FileSecurity();acl.SetAccessRuleProtection(true,false);
  acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(ownerSid),FileSystemRights.FullControl,AccessControlType.Allow));
  acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid,null),FileSystemRights.Read,AccessControlType.Deny));
  using(var file=new FileStream(ticket,FileMode.CreateNew,FileSystemRights.Write,FileShare.None,4096,FileOptions.WriteThrough,acl)){
   try{file.Write(data,0,data.Length);file.Flush(true);}
   catch{
    // A partial-write leaves ambiguous bytes. Revoke is permitted only for
    // the separately attested complete file; do not delete this unknown leaf.
    throw;
   }
  }
  attestedBytes=data;
  attestedBirth=File.GetCreationTimeUtc(ticket).Ticks;
 }
 public bool RevokeOnlyOwned(){
  if(attestedBytes==null)return !File.Exists(ticket);
  try {
   CheckPath(root);CheckPath(ticket);
   if(Path.GetDirectoryName(Path.GetFullPath(ticket))!=root || !File.Exists(ticket))
    return false;
   var info=new FileInfo(ticket);
   if(info.Length!=attestedBytes.Length || info.CreationTimeUtc.Ticks!=attestedBirth)
    return false;
   var bytes=File.ReadAllBytes(ticket);
   if(bytes.Length!=attestedBytes.Length)return false;
   // Exact content / run generation/host identity must remain unchanged.
   int difference=0;for(int i=0;i<bytes.Length;i++)difference|=bytes[i]^attestedBytes[i];
   if(difference!=0)return false;
   File.Delete(ticket); // never removes a mismatched/reparse/foreign leaf
   if(File.Exists(ticket))return false;
   attestedBytes=null;attestedBirth=0;
   return true;
  }catch{return false;}
 }
 // Fake-only injection point: does not start a process unless the caller's
 // delegate does so. Under any failed Process.Start, the known-own ticket is
 // revoked or explicitly reported as uncertain; no blind retry/deletion.
 public object CreateThen(string json,Func<object> launch) {
  Create(json);
  try{
   object result=launch();
   if(result==null)throw new InvalidOperationException("RC1_GUI_START_NULL");
   return result;
  }catch{
   if(!RevokeOnlyOwned())throw new InvalidOperationException("RC1_LAUNCH_TICKET_UNVERIFIED");
   throw;
  }
 }
}
