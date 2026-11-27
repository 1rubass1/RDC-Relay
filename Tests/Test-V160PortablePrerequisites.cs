// Offline fixture: invokes only read-only policy and route selection.
// No installer, browser, network, Host, registry or live Node execution.
using System;
using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;
#if OLD_NODE_FIXTURE
[assembly:AssemblyFileVersion("22.11.0.0")]
#else
[assembly:AssemblyFileVersion("22.12.0.0")]
#endif
public static class TestV160PortablePrerequisites {
 static int pass;
 static void Check(bool yes,string label){
  if(!yes)throw new Exception("FAIL "+label);
  Console.WriteLine("PASS "+label);pass++;
 }
 static string State(params string[] roots){return RdcNodePrerequisite.ClassifyNodePrerequisite(roots);}
 static string Bin(string dir){return Path.Combine(dir,"node_modules","npm","bin");}
 static void Fixture(string dir,string image){
  Directory.CreateDirectory(dir);
  File.Copy(image,Path.Combine(dir,"node.exe"),false);
  File.WriteAllText(Path.Combine(dir,"npm.cmd"),"DO NOT EXECUTE");
  File.WriteAllText(Path.Combine(dir,"npx.cmd"),"DO NOT EXECUTE");
  Directory.CreateDirectory(Bin(dir));
  File.WriteAllText(Path.Combine(Bin(dir),"npm-cli.js"),"DO NOT EXECUTE");
  File.WriteAllText(Path.Combine(Bin(dir),"npx-cli.js"),"DO NOT EXECUTE");
 }
 static void Clean(string dir){
  foreach(string file in new[]{Path.Combine(dir,"node.exe"),Path.Combine(dir,"npm.cmd"),
   Path.Combine(dir,"npx.cmd"),Path.Combine(Bin(dir),"npm-cli.js"),Path.Combine(Bin(dir),"npx-cli.js")}){
   if(File.Exists(file)){if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)throw new IOException("FIXTURE_LINK");File.Delete(file);}
  }
  foreach(string child in new[]{Path.Combine(dir,"node.exe"),Bin(dir),Path.Combine(dir,"node_modules","npm"),Path.Combine(dir,"node_modules"),dir})
   if(Directory.Exists(child)){
    if((File.GetAttributes(child)&FileAttributes.ReparsePoint)!=0)throw new IOException("FIXTURE_LINK");
    if(Directory.GetFileSystemEntries(child).Length==0)Directory.Delete(child,false);
   }
 }
 public static int Main(string[] args){
  if(args.Length!=1)throw new ArgumentException("OLD_FIXTURE_REQUIRED");
  string root=Path.Combine(Path.GetTempPath(),"RDC-V160-PORTABLE-FIXTURE-"+Guid.NewGuid().ToString("N"));
  string one=Path.Combine(root,"first"),two=Path.Combine(root,"second");
  try{
   Check(RdcRc1CandidateLauncher.RequiresPortablePreflight(new string[0],false),"Explorer double-click requests prerequisite check");
   Check(!RdcRc1CandidateLauncher.RequiresPortablePreflight(new string[0],true),"installed source does not prompt");
   Check(!RdcRc1CandidateLauncher.RequiresPortablePreflight(new[]{"--full"},false)&&
    !RdcRc1CandidateLauncher.RequiresPortablePreflight(new[]{"--background"},false)&&
    !RdcRc1CandidateLauncher.RequiresPortablePreflight(new[]{"--startup-dispatch"},false),"scripted and background launch do not install");
   Check(!RdcRc1CandidateLauncher.RequiresPortablePreflight(null,false),"unknown intent denied");
   Check(RdcNodePrerequisite.SupportedNodeVersion(22,12)&&!RdcNodePrerequisite.SupportedNodeVersion(22,11),"Node version boundary");
   Directory.CreateDirectory(root);
   Check(State(one,two)=="MISSING","absent standard roots");
   Directory.CreateDirectory(one);Directory.CreateDirectory(two);
   Check(State(one,two)=="MISSING","empty roots");
   Check(State((string[])null)=="UNKNOWN"&&State(new string[0])=="UNKNOWN","missing inspection inputs fail closed");
   Check(State(one+"\0")=="UNKNOWN","invalid path not mistaken for absent runtime");
   Directory.CreateDirectory(Path.Combine(one,"node.exe"));
   Check(State(one,two)=="UNKNOWN","directory in executable position cannot authorize install");
   Directory.Delete(Path.Combine(one,"node.exe"),false);
   Directory.CreateDirectory(Bin(one));File.WriteAllText(Path.Combine(Bin(one),"npm-cli.js"),"DO NOT EXECUTE");
   Check(State(one,two)=="INCOMPLETE","orphan npm CLI detected");
   File.WriteAllText(Path.Combine(one,"npx.cmd"),"DO NOT EXECUTE");
   Check(State(one,two)=="INCOMPLETE","orphan npx shim detected");
   Fixture(two,Assembly.GetExecutingAssembly().Location);
   Check(State(two)=="READY","complete supported fixture reused");
   Check(State(one,two)=="INCOMPLETE","broken earlier shim blocks fallback as Host does");
   Clean(one);Directory.CreateDirectory(one);
   Check(State(one,two)=="READY","absent earlier shim permits later supported runtime");
   Fixture(one,args[0]);
   Check(State(one,two)=="EXISTING_UNSUPPORTED","old complete first runtime blocks automatic replacement");
   Check(RdcRc1CandidateSetup.ClassifyNodePrerequisite(new[]{one,two})==State(one,two),"Setup uses same read-only policy");
   Check(RdcRc1CandidateSetup.SupportedNodeVersion(22,12)==RdcNodePrerequisite.SupportedNodeVersion(22,12),"Setup delegates supported version");
   Check(RdcNodePrerequisite.NodeMsiUrl=="https://nodejs.org/dist/v24.22.3/node-v24.22.3-x64.msi"&&
    RdcNodePrerequisite.NodeMsiSha256=="4A1AB5BDEC5434BAE58EFAE6C3E5077A011F6F1E76D2B47B7B10AF043F7DB545","existing approved exact MSI URL and hash retained");
   Console.WriteLine("RDC_V160_PORTABLE_PREREQ_PASS="+pass);return 0;
  }catch(Exception e){Console.WriteLine(e.GetType().Name+": "+e.Message);return 1;}
  finally{
   if(!Regex.IsMatch(Path.GetFileName(root),@"\ARDC-V160-PORTABLE-FIXTURE-[a-f0-9]{32}\z"))throw new IOException("FIXTURE_SCOPE");
   Clean(one);Clean(two);
   if(Directory.Exists(root)&&Directory.GetFileSystemEntries(root).Length==0)Directory.Delete(root,false);
  }
 }
}
