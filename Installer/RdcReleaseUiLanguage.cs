// RDC Relay 1.6 future release Setup: self-contained display-only localization.
// Independent of Source/lang on disk, credentials, Remote and Setup transactions.
// Standalone C# catalog is generated from Source/lang at build/review time.
using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

internal static class RdcReleaseUiLanguage {
 internal const string Russian="ru-RU", English="en-US";
 static readonly UTF8Encoding StrictUtf8=new UTF8Encoding(false,true);
 static bool Supported(string locale){return locale==Russian||locale==English;}
 // Pure, testable choice. Fresh install on non-Russian Windows suggests English.
 // Existing users without an explicit stored choice keep Russian.
 internal static string Suggested(string uiCulture,bool existing){
  if(existing)return Russian;
  return String.IsNullOrWhiteSpace(uiCulture)||
    uiCulture.StartsWith("ru",StringComparison.OrdinalIgnoreCase)?Russian:English;
 }
 internal static string PreferencePath {
  get{return Path.Combine(Environment.GetFolderPath(
   Environment.SpecialFolder.LocalApplicationData),"RDCRelay","ui-language.json");}
 }
 static string ReadExplicitPreference(string path,out bool present) {
  present=false;
  try{
   if(String.IsNullOrWhiteSpace(path)||!File.Exists(path))return null;
   present=true;
   var f=new FileInfo(path);
   if(f.Length<1||f.Length>128||(f.Attributes&FileAttributes.ReparsePoint)!=0)return null;
   string directory=Path.GetDirectoryName(Path.GetFullPath(path));
   if(String.IsNullOrWhiteSpace(directory)||
      (File.GetAttributes(directory)&FileAttributes.ReparsePoint)!=0)return null;
   string text=StrictUtf8.GetString(File.ReadAllBytes(path));
   // The exact bounded schema produced by RdcUiLanguage.SetPreference:
   // {"version":1,"locale":"ru-RU"} or en-US; never execute JSON or code.
   Match m=Regex.Match(text,
    @"\A\s*\{\s*""version""\s*:\s*1\s*,\s*""locale""\s*:\s*""(ru-RU|en-US)""\s*\}\s*\z",
    RegexOptions.CultureInvariant);
   return m.Success?m.Groups[1].Value:null;
  }catch{present=true;return null;}
 }
 internal static string Resolve(bool existing){
  return Resolve(existing,null,null);
 }
 // Override parameters are for disposable tests, not user-writable UI data.
 internal static string Resolve(bool existing,string preferencePath,string uiCulture){
  string full=preferencePath??PreferencePath;
  bool present;
  string selected=ReadExplicitPreference(full,out present);
  if(Supported(selected))return selected;
  if(present)return Russian;  // malformed/corrupt explicit data fails safe
  string system=uiCulture??CultureInfo.CurrentUICulture.Name;
  return Suggested(system,existing);
 }
 internal static string Text(string locale,string key,string russianFallback){
  IDictionary<string,string> dict=locale==English?
   RdcReleaseUiCatalog.English:RdcReleaseUiCatalog.Russian;
  string value;
  return dict.TryGetValue(key,out value)&&!String.IsNullOrEmpty(value)
    ?value:russianFallback;
 }
 static string Version(string value){
  return value!=null &&
   Regex.IsMatch(value,@"\A[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}\z")
     ?value:"?";
 }
 internal static string Format(string locale,string key,string russianFallback,
   string version,string installedVersion,string targetVersion){
  // Only three explicit numeric version arguments may enter display templates.
  string template=Text(locale,key,russianFallback);
  return template.Replace("{version}",Version(version)).
    Replace("{installedVersion}",Version(installedVersion)).
    Replace("{targetVersion}",Version(targetVersion));
 }
}
