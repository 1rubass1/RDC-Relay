// Qualification-only durable metadata transaction. The production executor
// must independently establish ownership and hold the install/Host leases.
using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using Microsoft.Win32;

internal static class RdcV16MetadataTransaction {
 public sealed class Entry {
  public string Name {get;set;}
  public string Kind {get;set;}
  public string Data {get;set;}
 }
 public sealed class Link {
  public string Path {get;set;}
  public string Before {get;set;}
  public string After {get;set;}
 }
 public sealed class Plan {
  public string Schema {get;set;}
  public string RegistryParent {get;set;}
  public bool HadKey {get;set;}
  public bool AfterKey {get;set;}
  public string RetiredPath {get;set;}
  public int? StartupBefore {get;set;}
  public List<Entry> Before {get;set;}
  public List<Entry> After {get;set;}
  public List<Link> Links {get;set;}
 }
 const string Product="RDC Relay",Schema="RDC_V16_METADATA_V2";
 static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=2097152,RecursionLimit=16};
 static string Hash(byte[] b){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(b)).Replace("-","");}
 static void Safe(string p){
  string full=Path.GetFullPath(p);
  string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
  bool desktopLink=!String.IsNullOrEmpty(desktop)&&String.Equals(full,Path.Combine(Path.GetFullPath(desktop),Product+".lnk"),StringComparison.OrdinalIgnoreCase);
  for(string path=full;!String.IsNullOrEmpty(path);path=Path.GetDirectoryName(path)){
   if((File.Exists(path)||Directory.Exists(path))&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0&&
      !(desktopLink&&RdcRc1ManualUpgrade.IsWindowsDesktopCloudAncestor(path,full)))
    throw new IOException("V16_METADATA_REPARSE");
  }
 }
 static string FileState(string path){
  Safe(path);
  if(Directory.Exists(path))throw new IOException("V16_METADATA_LINK_DIRECTORY");
  if(!File.Exists(path))return null;
  if(new FileInfo(path).Length>65536)throw new IOException("V16_METADATA_LINK_SIZE");
  return Convert.ToBase64String(File.ReadAllBytes(path));
 }
 static void WriteAtomic(string path,byte[] bytes){
  Safe(path);
  string tmp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
  try{
   using(var f=new FileStream(tmp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){f.Write(bytes,0,bytes.Length);f.Flush(true);}
   Safe(path);
   if(File.Exists(path))File.Replace(tmp,path,null);else File.Move(tmp,path);
  }finally{if(File.Exists(tmp))File.Delete(tmp);}
 }
 static List<Entry> Capture(RegistryKey parent,out bool exists){
  var result=new List<Entry>();
  using(var key=parent.OpenSubKey(Product,false)){
   exists=key!=null;if(!exists)return result;
   if(key.SubKeyCount!=0||key.ValueCount>64)throw new IOException("V16_METADATA_REGISTRY_SHAPE");
   foreach(string name in key.GetValueNames()){
    var kind=key.GetValueKind(name);
    object value=key.GetValue(name,null,RegistryValueOptions.DoNotExpandEnvironmentNames);
    if(kind!=RegistryValueKind.String&&kind!=RegistryValueKind.ExpandString&&kind!=RegistryValueKind.DWord)
     throw new IOException("V16_METADATA_REGISTRY_KIND");
    result.Add(new Entry{Name=name,Kind=kind.ToString(),Data=Convert.ToString(value,System.Globalization.CultureInfo.InvariantCulture)});
   }
  }
  return result.OrderBy(x=>x.Name,StringComparer.OrdinalIgnoreCase).ToList();
 }
 static bool Same(Entry a,Entry b){
  if(a==null||b==null)return a==b;
  return String.Equals(a.Name,b.Name,StringComparison.OrdinalIgnoreCase)&&a.Kind==b.Kind&&a.Data==b.Data;
 }
 static Entry Get(List<Entry> entries,string name){return entries.SingleOrDefault(x=>String.Equals(x.Name,name,StringComparison.OrdinalIgnoreCase));}
 static bool SameSet(List<Entry>a,List<Entry>b){return a.Count==b.Count&&a.All(x=>Same(x,Get(b,x.Name)));}
 internal static bool IsFullVersion(string version){
  Version v;
  return version!=null&&System.Text.RegularExpressions.Regex.IsMatch(version,@"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z")&&
   Version.TryParse(version,out v)&&v>=new Version(1,6,0);
 }
 internal static string ReleaseVersion(string release){
  string file=Path.Combine(release,"Source","version.txt");Safe(file);
  if(!File.Exists(file)||new FileInfo(file).Length>64)throw new IOException("V16_METADATA_VERSION_FILE");
  string v=File.ReadAllText(file,Encoding.UTF8).Trim();
  if(!IsFullVersion(v))throw new IOException("V16_METADATA_VERSION_FILE");
  return v;
 }
 static string BeforeVersion(Plan p){
  var row=Get(p.Before,"DisplayVersion");
  if(row==null||row.Kind!="String"||!IsFullVersion(row.Data))throw new IOException("V16_METADATA_VERSION_LEDGER");
  return row.Data;
 }
 static List<Entry> Desired(string version,string release,string maintenance){
  if(!IsFullVersion(version)||!Path.IsPathRooted(release)||!Path.IsPathRooted(maintenance))
   throw new IOException("V16_METADATA_IDENTITY");
  return new List<Entry>{
   new Entry{Name="DisplayName",Kind="String",Data=Product},
   new Entry{Name="Publisher",Kind="String",Data="RUBASS"},
   new Entry{Name="DisplayVersion",Kind="String",Data=version},
   new Entry{Name="InstallLocation",Kind="String",Data=Path.GetFullPath(release)},
   new Entry{Name="DisplayIcon",Kind="String",Data=Path.Combine(Path.GetFullPath(release),"Source","RDCRelay.ico")+",0"},
   new Entry{Name="UninstallString",Kind="String",Data="\""+Path.GetFullPath(maintenance)+"\" --uninstall"},
   new Entry{Name="NoModify",Kind="DWord",Data="1"},
   new Entry{Name="NoRepair",Kind="DWord",Data="1"}
  };
 }
 internal static Plan Prepare(RegistryKey parent,string desktop,string programs,string release,string maintenance,string journal,byte[] desktopLink,byte[] menuLink){
  // No production registry write is performed by Prepare.
  if(parent==null||desktopLink==null||menuLink==null||desktopLink.Length==0||menuLink.Length==0||
    desktopLink.Length>65536||menuLink.Length>65536)throw new IOException("V16_METADATA_INPUT");
  Safe(journal);Safe(release);Safe(maintenance);
  if(File.Exists(journal)||Directory.Exists(journal))throw new IOException("V16_METADATA_EXISTING_JOURNAL");
  if(!File.Exists(maintenance))throw new IOException("V16_METADATA_MAINTENANCE_MISSING");
  bool had;
  var prior=Capture(parent,out had);
  var plan=new Plan{Schema=Schema,RegistryParent=parent.Name,HadKey=had,AfterKey=true,Before=prior,After=Desired(ReleaseVersion(release),release,maintenance),Links=new List<Link>()};
  foreach(var item in new[]{new {Dir=desktop,Bytes=desktopLink},new {Dir=programs,Bytes=menuLink}}){
   string path=Path.Combine(Path.GetFullPath(item.Dir),Product+".lnk");
   if(!Directory.Exists(item.Dir))throw new IOException("V16_METADATA_LINK_FOLDER");
   if(plan.Links.Any(x=>String.Equals(x.Path,path,StringComparison.OrdinalIgnoreCase)))throw new IOException("V16_METADATA_DUPLICATE_LINK");
   plan.Links.Add(new Link{Path=path,Before=FileState(path),After=Convert.ToBase64String(item.Bytes)});
  }
  SavePlan(journal,plan);
  return plan;
 }
 static void SavePlan(string journal,Plan plan){
  string text=Json.Serialize(plan);
  byte[] bytes=Encoding.UTF8.GetBytes(text);
  WriteAtomic(journal,Encoding.UTF8.GetBytes(Hash(bytes)+"\n"+text));
 }
 // Prepare a removal only when ARP and both link bytes match the exact
 // expected installed identity. The caller must verify payload ownership
 // and acquire all process/installation exclusion leases first.
 internal static Plan PrepareRemoval(RegistryKey parent,string desktop,string programs,string release,string maintenance,string journal,byte[] desktopLink,byte[] menuLink){
  return PrepareRemovalRuntime(parent,desktop,programs,release,maintenance,journal,desktopLink,menuLink,null,null);
 }
 internal static Plan PrepareRemovalRuntime(RegistryKey parent,string desktop,string programs,string release,string maintenance,string journal,byte[] desktopLink,byte[] menuLink,string retired,int? startup){
  if(retired!=null){
   Safe(retired);
   if(!startup.HasValue||startup.Value<0||startup.Value>1||!ValidRetirement(release,retired)||
      File.Exists(retired)||Directory.Exists(retired))throw new IOException("V16_REMOVAL_RUNTIME_IDENTITY");
  }else if(startup.HasValue)throw new IOException("V16_REMOVAL_RUNTIME_IDENTITY");
  if(parent==null||desktopLink==null||menuLink==null)throw new IOException("V16_METADATA_INPUT");
  Safe(journal);Safe(release);Safe(maintenance);
  if(File.Exists(journal)||Directory.Exists(journal))throw new IOException("V16_METADATA_EXISTING_JOURNAL");
  bool had;
  var prior=Capture(parent,out had);
  if(!had||!SameSet(prior,Desired(ReleaseVersion(release),release,maintenance)))throw new IOException("V16_METADATA_UNINSTALL_IDENTITY");
  var plan=new Plan{Schema=Schema,RegistryParent=parent.Name,HadKey=true,AfterKey=false,RetiredPath=retired,StartupBefore=startup,Before=prior,After=new List<Entry>(),Links=new List<Link>()};
  foreach(var item in new[]{new {Dir=desktop,Bytes=desktopLink},new {Dir=programs,Bytes=menuLink}}){
   string path=Path.Combine(Path.GetFullPath(item.Dir),Product+".lnk");
   string before=FileState(path);
   if(before==null||before!=Convert.ToBase64String(item.Bytes)||plan.Links.Any(x=>String.Equals(x.Path,path,StringComparison.OrdinalIgnoreCase)))
    throw new IOException("V16_METADATA_UNINSTALL_LINK_IDENTITY");
   plan.Links.Add(new Link{Path=path,Before=before,After=null});
  }
  SavePlan(journal,plan);
  return plan;
 }
 static Plan Load(RegistryKey parent,string journal,string desktop,string programs){
  Safe(journal);
  if(!File.Exists(journal)||new FileInfo(journal).Length>2097152)throw new IOException("V16_METADATA_JOURNAL");
  string content=File.ReadAllText(journal,new UTF8Encoding(false,true));int sep=content.IndexOf('\n');
  if(sep!=64||Hash(Encoding.UTF8.GetBytes(content.Substring(sep+1)))!=content.Substring(0,sep))throw new IOException("V16_METADATA_JOURNAL_HASH");
  var p=Json.Deserialize<Plan>(content.Substring(sep+1));
  if(p==null||p.Schema!=Schema||p.RegistryParent!=parent.Name||p.Links==null||p.Links.Count!=2||p.Before==null||p.After==null)
   throw new IOException("V16_METADATA_JOURNAL_SCHEMA");
  var allowed=new HashSet<string>(new[]{Path.Combine(Path.GetFullPath(desktop),Product+".lnk"),Path.Combine(Path.GetFullPath(programs),Product+".lnk")},StringComparer.OrdinalIgnoreCase);
  foreach(var link in p.Links)if(!allowed.Remove(link.Path))throw new IOException("V16_METADATA_LINK_SCOPE");
  foreach(var list in new[]{p.Before,p.After}){
   if(list.Count>64||list.Select(x=>x.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=list.Count)throw new IOException("V16_METADATA_DUPLICATE");
   foreach(var row in list){
    if(row.Name==null||row.Data==null||row.Data.Length>32768||!(row.Kind=="String"||row.Kind=="ExpandString"||row.Kind=="DWord"))throw new IOException("V16_METADATA_ENTRY");
    if(row.Kind=="DWord"){int i;if(!Int32.TryParse(row.Data,out i))throw new IOException("V16_METADATA_DWORD");}
   }
  }
  return p;
 }
 static void CheckKnown(RegistryKey parent,Plan p){
  bool exists;
  var current=Capture(parent,out exists);
  foreach(string name in p.Before.Concat(p.After).Concat(current).Select(x=>x.Name).Distinct(StringComparer.OrdinalIgnoreCase)){
   var value=Get(current,name);
   if(!Same(value,Get(p.Before,name))&&!Same(value,Get(p.After,name)))throw new IOException("V16_METADATA_FOREIGN_REGISTRY_CHANGE");
  }
  foreach(var link in p.Links){
   var now=FileState(link.Path);
   if(now!=link.Before&&now!=link.After)throw new IOException("V16_METADATA_FOREIGN_LINK_CHANGE");
  }
 }
 static void SetRegistry(RegistryKey parent,List<Entry> wanted,bool exists){
  if(!exists){parent.DeleteSubKey(Product,false);return;}
  using(var key=parent.CreateSubKey(Product)){
   if(key.SubKeyCount!=0)throw new IOException("V16_METADATA_REGISTRY_SHAPE");
   foreach(string name in key.GetValueNames())if(Get(wanted,name)==null)key.DeleteValue(name,false);
   foreach(var row in wanted){
    var kind=(RegistryValueKind)Enum.Parse(typeof(RegistryValueKind),row.Kind);
    key.SetValue(row.Name,kind==RegistryValueKind.DWord?(object)Int32.Parse(row.Data):(object)row.Data,kind);
   }
   key.Flush();
  }
 }
 static void SetLinks(Plan p,bool after,int limit){
  for(int i=0;i<limit;i++){
   var link=p.Links[i];string value=after?link.After:link.Before;
   if(value==null){Safe(link.Path);if(File.Exists(link.Path))File.Delete(link.Path);}
   else WriteAtomic(link.Path,Convert.FromBase64String(value));
  }
 }
 static void Verify(RegistryKey parent,Plan p,bool after){
  bool exists;var current=Capture(parent,out exists);
  if(exists!=(after?p.AfterKey:p.HadKey)||!SameSet(current,after?p.After:p.Before))throw new IOException("V16_METADATA_REGISTRY_VERIFY");
  foreach(var link in p.Links)if(FileState(link.Path)!=(after?link.After:link.Before))throw new IOException("V16_METADATA_LINK_VERIFY");
 }
 // The journal is retained until the outer activation transaction commits.
 // Recovery accepts only exact pre/post values and refuses external changes.
 internal static void Apply(RegistryKey parent,string journal,string desktop,string programs){
  var p=Load(parent,journal,desktop,programs);
  CheckKnown(parent,p);
  try{SetLinks(p,true,p.Links.Count);SetRegistry(parent,p.After,p.AfterKey);Verify(parent,p,true);}
  catch{RecoverRollback(parent,journal,desktop,programs);throw;}
 }
 static bool ValidRetirement(string release,string retired){
  return Path.IsPathRooted(retired)&&Path.GetFullPath(retired)==retired&&
   retired.StartsWith(Path.GetFullPath(release)+".retired-",StringComparison.Ordinal)&&
   System.Text.RegularExpressions.Regex.IsMatch(retired.Substring(Path.GetFullPath(release).Length),@"\A\.retired-[0-9a-f]{32}\z");
 }
 internal static Plan ReadRemovalRecovery(RegistryKey parent,string journal,string desktop,string programs,string release,string maintenance){
  var p=ReadRecoveryPlan(parent,journal,desktop,programs);
  if(!p.HadKey||p.AfterKey||p.After.Count!=0||!SameSet(p.Before,Desired(BeforeVersion(p),release,maintenance))||
    p.Links.Any(x=>x.Before==null||x.After!=null)||p.RetiredPath==null||!ValidRetirement(release,p.RetiredPath)||
    !p.StartupBefore.HasValue||p.StartupBefore.Value<0||p.StartupBefore.Value>1)
   throw new IOException("V16_REMOVAL_RECOVERY_IDENTITY");
  return p;
 }
 internal static Plan ReadRecoveryPlan(RegistryKey parent,string journal,string desktop,string programs){
  var p=Load(parent,journal,desktop,programs);CheckKnown(parent,p);return p;
 }
 internal static bool IsCompletedRemoval(RegistryKey parent,string journal,string desktop,string programs,string release,string maintenance){
  var p=Load(parent,journal,desktop,programs);
  if(!p.HadKey||p.AfterKey||p.After.Count!=0||!SameSet(p.Before,Desired(BeforeVersion(p),release,maintenance))||
   p.Links.Any(x=>x.Before==null||x.After!=null))return false;
  Verify(parent,p,true);
  return true;
 }
 internal static void RecoverRollback(RegistryKey parent,string journal,string desktop,string programs){
  var p=Load(parent,journal,desktop,programs);CheckKnown(parent,p);
  SetRegistry(parent,p.Before,p.HadKey);SetLinks(p,false,p.Links.Count);Verify(parent,p,false);
 }
}
