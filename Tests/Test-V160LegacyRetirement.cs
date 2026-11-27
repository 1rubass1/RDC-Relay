using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using Microsoft.Win32;
internal static class TestV160LegacyRetirement {
 static int count;
 static void Check(bool ok,string name){if(!ok)throw new Exception(name);count++;Console.WriteLine("PASS "+name);}
 static void Refuse(Action a,string code,string name){try{a();}catch(IOException e){Check(e.Message==code,name);return;}throw new Exception("Not refused: "+name);}
 static void Main(){
  string root=Path.Combine(Path.GetTempPath(),"RDC-legacy-test-"+Guid.NewGuid().ToString("N"));
  string reg=@"Software\RDC-Legacy-Test-"+Guid.NewGuid().ToString("N");
  try{
   string[] req={"Source/version.txt","RDC Relay.exe"};
   var old=req.Concat(new[]{"Source/update.ps1"}).ToList();
   string bad="RC1_MANIFEST_NOT_EXACT_UNIQUE_SET", refused="V16_LEGACY_OR_UNKNOWN_INSTALL_REFUSED";
   Check(RdcV16MetadataTransaction.InstalledPayloadMembers(req,req.ToList(),"1.6.0").Length==2,"new manifest");
   Check(RdcV16MetadataTransaction.InstalledPayloadMembers(req,old,"1.6.0").Length==3,"original installed 1.6.0 manifest");
   Refuse(()=>RdcV16MetadataTransaction.InstalledPayloadMembers(req,old,"1.6.1"),bad,"future legacy updater");
   Refuse(()=>RdcV16MetadataTransaction.InstalledPayloadMembers(req,new List<string>{req[0],req[0]},"1.6.0"),bad,"duplicate member");
   Refuse(()=>RdcV16MetadataTransaction.InstalledPayloadMembers(req,new List<string>{req[0],"foreign"},"1.6.0"),bad,"unknown member");
   string src=Path.Combine(root,"Source"),desk=Path.Combine(root,"desktop"),menu=Path.Combine(root,"menu"),j=Path.Combine(root,"journal.json"),m=Path.Combine(root,"maintenance.exe");
   foreach(var d in new[]{src,desk,menu})Directory.CreateDirectory(d);
   File.WriteAllText(Path.Combine(src,"version.txt"),"1.6.0");File.WriteAllText(m,"fixture");
   string u=Path.Combine(src,"update.ps1");
   RdcV16MetadataTransaction.AssertNewPayloadNoRetiredUpdater(root);Check(true,"new payload no updater");
   File.WriteAllText(u,"fixture");Refuse(()=>RdcV16MetadataTransaction.AssertNewPayloadNoRetiredUpdater(root),"V16_RETIRED_UPDATER_IN_CANDIDATE","new payload refuses updater");
   File.Delete(u);Directory.CreateDirectory(u);Refuse(()=>RdcV16MetadataTransaction.AssertNewPayloadNoRetiredUpdater(root),"V16_RETIRED_UPDATER_IN_CANDIDATE","new payload refuses updater directory");Directory.Delete(u);
   using(var parent=Registry.CurrentUser.CreateSubKey(reg)){
    byte[] bytes={1,2,3};
    Action prepare=()=>RdcV16MetadataTransaction.PrepareActivation(parent,desk,menu,root,m,j,bytes,bytes,true);
    using(var k=parent.CreateSubKey("RDC Relay"))k.SetValue("DisplayVersion","1.5.18");
    Refuse(prepare,refused,"legacy registry refusal");Check(!File.Exists(j),"no journal on registry refusal");
    using(var k=parent.OpenSubKey("RDC Relay"))Check((string)k.GetValue("DisplayVersion")=="1.5.18","legacy registry preserved");
    parent.DeleteSubKeyTree("RDC Relay");
    foreach(var dir in new[]{desk,menu}){
     string path=Path.Combine(dir,"RDC Relay.lnk");File.WriteAllText(path,"foreign");
     Refuse(prepare,refused,"foreign link refusal "+Path.GetFileName(dir));
     Check(!File.Exists(j)&&File.ReadAllText(path)=="foreign","foreign link preserved "+Path.GetFileName(dir));File.Delete(path);
    }
    prepare();Check(File.Exists(j),"clean preparation");Check(parent.OpenSubKey("RDC Relay")==null,"preparation does not register");
   }
  }finally{Registry.CurrentUser.DeleteSubKeyTree(reg,false);if(Directory.Exists(root))Directory.Delete(root,true);}
  Console.WriteLine("PASS total "+count);
 }
}