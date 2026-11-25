// UI-only locale preference and bounded JSON resource reader.
// No Host / Remote control, provider parsing, or execution of localized text.
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Text.RegularExpressions;

// Shared launch preference, compiled in both Host and GUI. No process control.
public static class RdcOwnerAutoConnectPreference {
 public static string CurrentPath {get{return Path.Combine(Environment.GetFolderPath(
  Environment.SpecialFolder.LocalApplicationData),"RDCRelayOwnerPilot","auto-connect.preference");}}
 static void Safe(string path){
  for(string p=Path.GetFullPath(path);!String.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)){
   if((File.Exists(p)||Directory.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)
    throw new IOException("RDC_AUTO_CONNECT_REPARSE");
  }
 }
 public static bool Enabled(string path){
  try{
   if(String.IsNullOrWhiteSpace(path))return false;
   Safe(path);
   if(Directory.Exists(path))return false;
   if(!File.Exists(path))return true; // preserve existing manual Host startup behavior
   var info=new FileInfo(path);
   return info.Length==10&&File.ReadAllText(path,new UTF8Encoding(false,true))=="enabled-v1";
  }catch{return false;}
 }
 // Only a fresh installed Setup calls this. Never replace an existing
 // preference, including one written by another user-controlled UI.
 public static void InitializeDisabled(string path){
  string full=Path.GetFullPath(path);Safe(full);
  string dir=Path.GetDirectoryName(full);
  Directory.CreateDirectory(dir);Safe(full);
  if(File.Exists(full))return;
  if(Directory.Exists(full))throw new IOException("RDC_AUTO_CONNECT_PREFERENCE_COLLISION");
  string temp=Path.Combine(dir,"auto-connect-"+Guid.NewGuid().ToString("N")+".tmp");
  try{
   using(var stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] data=Encoding.UTF8.GetBytes("disabled-v1");
    stream.Write(data,0,data.Length);stream.Flush(true);
   }
   Safe(full);
   try{File.Move(temp,full);}
   catch(IOException){Safe(full);if(!File.Exists(full))throw;}
  }finally{if(File.Exists(temp))File.Delete(temp);}
 }
 public static void Set(string path,bool enabled){
  string full=Path.GetFullPath(path);
  Safe(full);
  string dir=Path.GetDirectoryName(full);
  Directory.CreateDirectory(dir);Safe(full);
  string temp=Path.Combine(dir,"auto-connect-"+Guid.NewGuid().ToString("N")+".tmp");
  try{
   using(var stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
    byte[] data=Encoding.UTF8.GetBytes(enabled?"enabled-v1":"disabled-v1");
    stream.Write(data,0,data.Length);stream.Flush(true);
   }
   Safe(full);
   if(File.Exists(full))File.Replace(temp,full,null);else File.Move(temp,full);
   if(Enabled(full)!=enabled)throw new IOException("RDC_AUTO_CONNECT_VERIFY");
  }finally{if(File.Exists(temp))File.Delete(temp);}
 }
}

public static class RdcUiLanguage {
 public const string Russian="ru-RU", English="en-US";
 static readonly UTF8Encoding StrictUtf8=new UTF8Encoding(false,true);
 public static string PreferencePath {
  get {return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "RDCRelay","ui-language.json");}
 }
 public static bool Supported(string locale){return locale==Russian||locale==English;}
 static Dictionary<string,object> ReadObject(string path,int limit){
  if(String.IsNullOrWhiteSpace(path)||!File.Exists(path))return null;
  var file=new FileInfo(path);
  if(file.Length<1||file.Length>limit||(file.Attributes&FileAttributes.ReparsePoint)!=0)return null;
  string json=StrictUtf8.GetString(File.ReadAllBytes(path));
  var serializer=new JavaScriptSerializer();
  serializer.MaxJsonLength=limit;
  return serializer.DeserializeObject(json) as Dictionary<string,object>;
 }
 public static string ReadPreference(string path){
  try {
   var data=ReadObject(path,128);
   if(data==null||data.Count!=2||!data.ContainsKey("version")||!data.ContainsKey("locale")||
      Convert.ToInt32(data["version"])!=1)return Russian;
   string selected=data["locale"] as string;
   return Supported(selected)?selected:Russian;
  }catch{return Russian;}
 }
 public static string Current {get{return ReadPreference(PreferencePath);}}
 public static void SetPreference(string path,string locale){
  if(!Supported(locale))throw new ArgumentException("RDC_UI_LOCALE_UNSUPPORTED");
  if(String.IsNullOrWhiteSpace(path))throw new ArgumentException("RDC_UI_LOCALE_PATH_REQUIRED");
  string full=Path.GetFullPath(path), dir=Path.GetDirectoryName(full);
  if(String.IsNullOrEmpty(dir))throw new InvalidOperationException("RDC_UI_LOCALE_PARENT_REQUIRED");
  if(Directory.Exists(dir)&&(File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)
   throw new InvalidOperationException("RDC_UI_LOCALE_DIRECTORY_REPARSE");
  if(File.Exists(full)&&(File.GetAttributes(full)&FileAttributes.ReparsePoint)!=0)
   throw new InvalidOperationException("RDC_UI_LOCALE_FILE_REPARSE");
  if(!Directory.Exists(dir))Directory.CreateDirectory(dir);
  if((File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)
   throw new InvalidOperationException("RDC_UI_LOCALE_DIRECTORY_REPARSE");
  string temp=Path.Combine(dir,"ui-language-"+Guid.NewGuid().ToString("N")+".tmp");
  string backup=Path.Combine(dir,"ui-language-"+Guid.NewGuid().ToString("N")+".bak");
  try{
   File.WriteAllText(temp,"{\"version\":1,\"locale\":\""+locale+"\"}",new UTF8Encoding(false));
   if(File.Exists(full)){
    if((File.GetAttributes(full)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RDC_UI_LOCALE_FILE_REPARSE");
    File.Replace(temp,full,backup);
   }else File.Move(temp,full);
   if(ReadPreference(full)!=locale)throw new IOException("RDC_UI_LOCALE_VERIFY_FAILED");
  }finally{
   if(File.Exists(temp))File.Delete(temp);
   if(File.Exists(backup))File.Delete(backup);
  }
 }
 public static Dictionary<string,string> LoadResources(string sourceRoot,string locale){
  var result=new Dictionary<string,string>(StringComparer.Ordinal);
  if(!Supported(locale)||String.IsNullOrWhiteSpace(sourceRoot))return result;
  try {
   string folder=Path.Combine(Path.GetFullPath(sourceRoot),"lang");
   if(!Directory.Exists(folder)||(File.GetAttributes(folder)&FileAttributes.ReparsePoint)!=0)return result;
   var data=ReadObject(Path.Combine(folder,locale+".json"),65536);
   if(data==null||data.Count!=4||!data.ContainsKey("schema")||
     !Object.Equals(data["schema"],"rdc-relay-i18n-v1")||
     !Object.Equals(data["status"],"INTEGRATION_TEST")||
     !Object.Equals(data["locale"],locale)||!data.ContainsKey("strings"))return result;
   var strings=data["strings"] as Dictionary<string,object>;
   if(strings==null||strings.Count<10||strings.Count>400)return result;
   foreach(var pair in strings){
    var value=pair.Value as string;
    if(!Regex.IsMatch(pair.Key,@"\A[a-z][a-zA-Z0-9]*(?:\.[a-zA-Z][a-zA-Z0-9]*)+\z")||
       String.IsNullOrEmpty(value)||value.Length>1000||
       Regex.IsMatch(value,@"[\x00-\x08\x0B\x0C\x0E-\x1F]"))
     return new Dictionary<string,string>(StringComparer.Ordinal);
    result.Add(pair.Key,value);
   }
  }catch{return new Dictionary<string,string>(StringComparer.Ordinal);}
  return result;
 }
 // Only known Host GUI notice reasons are localized. Error codes and diagnostic entries
 // remain unchanged; an unknown reason keeps the reviewed Russian fallback.
 public static string GuiNotice(string reason,string russianFallback,IDictionary<string,string> catalog){
  string key=null;
  switch(reason){
   case "window not ready":key="tray.notice.windowNotReady";break;
   case "open denied: unverified":key="tray.notice.windowUnverified";break;
   case "open denied: child identity mismatch":
   case "open denied: unverified window":
    key="tray.notice.windowIdentityMismatch";break;
   case "open pending: no window":key="tray.notice.windowPending";break;
  }
  if(key==null && reason!=null){
   if(reason.StartsWith("open failed: ",StringComparison.Ordinal))
    key="tray.notice.windowDisplayFailed";
   else if(reason.StartsWith("GUI launch failed: ",StringComparison.Ordinal))
    key="tray.notice.windowLaunchFailed";
  }
  return key==null?russianFallback:Text(catalog,key,russianFallback);
 }
 public static string Text(IDictionary<string,string> catalog,string key,string russianFallback){
  string value;
  return catalog!=null&&catalog.TryGetValue(key,out value)?value:russianFallback;
 }
}
