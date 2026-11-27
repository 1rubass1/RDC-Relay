// Offline Windows fixture: real ShellLink COM and journaled metadata, no
// live Desktop, Programs, product registry, installed app or Remote access.
using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;

internal static class TestV16ShortcutStaging {
 static int pass;
 static void Check(bool ok,string name){
  if(!ok)throw new Exception("FAIL "+name);
  Console.WriteLine("PASS "+name);pass++;
 }
 static string MakeRelease(string root,string name){
  string r=Path.Combine(root,name),src=Path.Combine(r,"Source");
  Directory.CreateDirectory(src);
  File.WriteAllText(Path.Combine(src,"version.txt"),"1.6.0");
  File.WriteAllText(Path.Combine(src,"RDCRelay.ico"),"fixture");
  File.WriteAllBytes(Path.Combine(r,"RDC Relay.exe"),new byte[]{77,90,0});
  return r;
 }
 static bool Equal(string path,byte[] bytes){
  return File.Exists(path)&&File.ReadAllBytes(path).SequenceEqual(bytes);
 }
 static string Property(object link,string name){
  return Convert.ToString(link.GetType().InvokeMember(name,BindingFlags.GetProperty,null,link,new object[0]));
 }
 static void VerifyShortcut(string path,string release){
  object shell=null,link=null;
  try{
   shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
   link=shell.GetType().InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});
   Check(String.Equals(Property(link,"TargetPath"),Path.Combine(release,"RDC Relay.exe"),StringComparison.OrdinalIgnoreCase),"native shortcut target");
   Check(Property(link,"Arguments")=="--full","native shortcut arguments");
   Check(String.Equals(Property(link,"WorkingDirectory"),release,StringComparison.OrdinalIgnoreCase),"native shortcut working directory");
   Check(String.Equals(Property(link,"IconLocation").Replace(", ",","),Path.Combine(release,"Source","RDCRelay.ico")+",0",StringComparison.OrdinalIgnoreCase),"native shortcut icon");
   Check(Property(link,"Description")=="RDC Relay 1.6.0 RC1 (full Host/GUI candidate)","native shortcut description");
  }finally{if(link!=null)Marshal.FinalReleaseComObject(link);if(shell!=null)Marshal.FinalReleaseComObject(shell);}
 }
 [STAThread] static int Main(){
  string id=Guid.NewGuid().ToString("N"),root=Path.Combine(Path.GetTempPath(),"RDC-Shortcut-Test-"+id);
  string sub=@"Software\RDCRelayShortcutTest-"+id;
  bool created=false,registry=false;
  try{
   if(Directory.Exists(root)||File.Exists(root))throw new IOException("fixture collision");
   Directory.CreateDirectory(root);created=true;
   string desktop=Path.Combine(root,"Desktop"),programs=Path.Combine(root,"Programs");
   Directory.CreateDirectory(desktop);Directory.CreateDirectory(programs);
   string r1=MakeRelease(root,"release1"),r2=MakeRelease(root,"release2");
   string maintenance=Path.Combine(root,"Maintenance.exe");
   File.WriteAllBytes(maintenance,new byte[]{77,90,1});
   string foreign=Path.Combine(desktop,".rdc-rc1-foreign.lnk");
   byte[] foreignBytes={42,99};File.WriteAllBytes(foreign,foreignBytes);
   string dl=Path.Combine(desktop,"RDC Relay.lnk"),ml=Path.Combine(programs,"RDC Relay.lnk");
   string[] before=Directory.GetFiles(root,"*",SearchOption.AllDirectories).OrderBy(x=>x).ToArray();
   byte[] b1=RdcRc1ManualUpgrade.BuildShortcutBytes(r1,Path.Combine(r1,"RDC Relay.exe"));
   Check(b1.Length>76&&b1.Length<=65536&&BitConverter.ToInt32(b1,0)==76,"valid bounded ShellLink header");
   Check(before.SequenceEqual(Directory.GetFiles(root,"*",SearchOption.AllDirectories).OrderBy(x=>x)),"no staging files anywhere in fixture");
   byte[] abandoned=RdcRc1ManualUpgrade.BuildShortcutBytes(r1,Path.Combine(r1,"RDC Relay.exe"));
   Check(abandoned.Length>76&&!File.Exists(dl)&&!File.Exists(ml)&&Equal(foreign,foreignBytes),"discarded pre-publication stage leaves no files");
   bool refused=false;
   try{RdcRc1ManualUpgrade.BuildShortcutBytes(r1,Path.Combine(r1,"missing.exe"));}catch(IOException){refused=true;}
   Check(refused&&before.SequenceEqual(Directory.GetFiles(root,"*",SearchOption.AllDirectories).OrderBy(x=>x)),"missing launcher refused without files");
   using(var parent=Registry.CurrentUser.CreateSubKey(sub)){
    registry=true;
    string j1=Path.Combine(root,"first.pending");
    RdcV16MetadataTransaction.Prepare(parent,desktop,programs,r1,maintenance,j1,b1,b1);
    Check(!File.Exists(dl)&&!File.Exists(ml),"journal preparation leaves desktop and menu unchanged");
    RdcV16MetadataTransaction.Apply(parent,j1,desktop,programs);
    Check(Equal(dl,b1)&&Equal(ml,b1),"fresh publication uses exact in-memory bytes");
    VerifyShortcut(dl,r1);VerifyShortcut(ml,r1);
    string j2=Path.Combine(root,"upgrade.pending");
    byte[] b2=RdcRc1ManualUpgrade.BuildShortcutBytes(r2,Path.Combine(r2,"RDC Relay.exe"));
    RdcV16MetadataTransaction.Prepare(parent,desktop,programs,r2,maintenance,j2,b2,b2);
    Check(Equal(dl,b1)&&Equal(ml,b1),"same-version repair prepares without shortcut changes");
    File.WriteAllBytes(dl,b2); // model interruption after first published link
    RdcV16MetadataTransaction.RecoverRollback(parent,j2,desktop,programs);
    Check(Equal(dl,b1)&&Equal(ml,b1),"interrupted publication recovers exact previous links");
    RdcV16MetadataTransaction.Apply(parent,j2,desktop,programs);
    Check(Equal(dl,b2)&&Equal(ml,b2),"retry publishes both new shortcuts");
    VerifyShortcut(dl,r2);
    RdcV16MetadataTransaction.RecoverRollback(parent,j2,desktop,programs);
    Check(Equal(dl,b1)&&Equal(ml,b1),"explicit rollback restores previous shortcuts");
    RdcV16MetadataTransaction.RecoverRollback(parent,j1,desktop,programs);
    Check(!File.Exists(dl)&&!File.Exists(ml),"first install rollback removes only owned links");
    Check(Equal(foreign,foreignBytes)&&Directory.GetFiles(desktop).Length==1&&Directory.GetFiles(programs).Length==0,"foreign temporary-looking link untouched and no stage residue");
   }
   Console.WriteLine("RDC_SHORTCUT_STAGING_PASS="+pass+" FAIL=0");
   return 0;
  }catch(Exception e){Console.Error.WriteLine(e);return 1;}
  finally{
   if(registry)Registry.CurrentUser.DeleteSubKeyTree(sub,false);
   if(created){
    foreach(string f in Directory.GetFileSystemEntries(root))if((File.GetAttributes(f)&FileAttributes.ReparsePoint)!=0)throw new IOException("fixture cleanup reparse");
    Directory.Delete(root,true);
   }
  }
 }
}
