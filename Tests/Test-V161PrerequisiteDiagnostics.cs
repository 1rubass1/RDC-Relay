// Compiled synthetic fixtures only. Node/npm/npx are never executed.
using System;
using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;
#if LEGACY_NODE_FIXTURE
[assembly:AssemblyFileVersion("22.11.0.0")]
#else
[assembly:AssemblyFileVersion("22.12.0.0")]
#endif
public static class TestV161PrerequisiteDiagnostics {
 static int pass;
 static void Check(bool ok,string name){
  if(!ok)throw new Exception("FAIL "+name);
  Console.WriteLine("PASS "+name);pass++;
 }
 public static int Main(string[] args){
  if(args.Length!=1)throw new ArgumentException("LEGACY_FIXTURE_REQUIRED");
  string root=Path.Combine(Path.GetTempPath(),"RDC-V161-PREQ-CS-"+Guid.NewGuid().ToString("N"));
  string node=Path.Combine(root,"node.exe"),npm=Path.Combine(root,"npm.cmd"),npx=Path.Combine(root,"npx.cmd");
  string modules=Path.Combine(root,"node_modules"),package=Path.Combine(modules,"npm"),bin=Path.Combine(package,"bin");
  string npmCli=Path.Combine(bin,"npm-cli.js"),npxCli=Path.Combine(bin,"npx-cli.js");
  Action<string> allow=p=>{};
  Action<string> deny=p=>{throw new UnauthorizedAccessException();};
  try{
   Directory.CreateDirectory(root);
   var lines=RdcOwnerPrerequisiteDiagnostics.Observe(root,"ProgramFiles",allow);
   Check(lines[0]=="runtime ProgramFiles: node=missing npm=missing npx=missing","actual observer missing executables explicit");
   Check(lines[1]=="runtime ProgramFiles: npm-cli=missing npx-cli=missing","actual observer missing entrypoints explicit");
   Check(RdcOwnerPrerequisiteDiagnostics.FileState(node,deny)=="unknown","denied check does not mean missing");
   Directory.CreateDirectory(npx);
   Check(RdcOwnerPrerequisiteDiagnostics.FileState(npx,allow)=="not_file","directory not mistaken for executable");
   Directory.Delete(npx,false);
   File.Copy(args[0],node,false);
   Check(RdcOwnerPrerequisiteDiagnostics.NodeState(node,allow)=="unsupported(22.11.0.0)","unsupported Node metadata boundary");
   File.Delete(node);File.Copy(Assembly.GetExecutingAssembly().Location,node,false);
   Check(RdcOwnerPrerequisiteDiagnostics.NodeState(node,allow)=="present(22.12.0.0)","supported Node metadata boundary");
   File.WriteAllText(npm,"DO NOT EXECUTE");File.WriteAllText(npx,"DO NOT EXECUTE");
   Directory.CreateDirectory(bin);File.WriteAllText(npmCli,"DO NOT EXECUTE");
   lines=RdcOwnerPrerequisiteDiagnostics.Observe(root,"ProgramFiles",allow);
   Check(lines[0]=="runtime ProgramFiles: node=present(22.12.0.0) npm=present npx=present"&&
     lines[1]=="runtime ProgramFiles: npm-cli=present npx-cli=missing","partial runtime explicitly distinguished");
   Check(!String.Join(" ",lines).Contains(root)&&lines[0].Length<=120&&lines[1].Length<=120,"no private path in diagnostics");
   File.WriteAllText(npxCli,"DO NOT EXECUTE");
   Check(RdcOwnerPrerequisiteDiagnostics.Observe(root,"ProgramFiles",allow)[1]=="runtime ProgramFiles: npm-cli=present npx-cli=present","both entrypoints present");
   Console.WriteLine("RDC_V161_PREREQUISITE_CS_PASS="+pass);return 0;
  }catch(Exception e){Console.WriteLine(e.GetType().Name+": "+e.Message);return 1;}
  finally{
   if(!Regex.IsMatch(Path.GetFileName(root),@"\ARDC-V161-PREQ-CS-[0-9a-f]{32}\z"))throw new Exception("FIXTURE_SCOPE");
   foreach(string file in new[]{npmCli,npxCli,node,npm,npx})
    if(File.Exists(file)){if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)throw new Exception("FIXTURE_REPARSE");File.Delete(file);}
   foreach(string dir in new[]{npx,bin,package,modules,root})
    if(Directory.Exists(dir)){
     if((File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)throw new Exception("FIXTURE_REPARSE");
     if(Directory.GetFileSystemEntries(dir).Length==0)Directory.Delete(dir,false);
    }
  }
 }
}
