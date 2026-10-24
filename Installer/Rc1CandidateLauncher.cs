// Side-by-side RC1 Owner Portable/Setup launcher. New product entry point.
// Compile with RDC_RC1_BLOCKED until approved Host/GUI and OS process tests.
using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Web.Script.Serialization;
using System.Collections.Generic;
internal static class RdcRc1CandidateLauncher {
 static int Main(string[] args) {
#if RDC_RC1_BLOCKED
  Console.Error.WriteLine("RC1_OWNER_LAUNCHER_BLOCKED_PENDING_OWNER_GO");
  return 42;
#else
  try{
   if(args.Length!=1 || args[0]!="--owner-approved-fake-only" ||
      Environment.GetEnvironmentVariable("RDC_RC1_OWNER_G1_GO")!="YES")
     throw new InvalidOperationException("RC1_OWNER_GO_REQUIRED");
   string root=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
   string source=Path.Combine(root,"Source");
   string marker=Path.Combine(source,"rc1-candidate.json");
   if(!File.Exists(marker))throw new InvalidOperationException("RC1_NO_MARKER");
   string content=File.ReadAllText(marker,Encoding.UTF8);
   var values=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(content);
   if((string)values["candidate"]!="1.6.0 RC1" ||
      !Convert.ToBoolean(values["installable"]) ||
      Convert.ToBoolean(values["liveRemoteEnabled"]))
     throw new InvalidOperationException("RC1_NOT_VERIFIED_FOR_FAKE_ONLY_LAUNCH");
   foreach(string name in new []{"rc1-tray-host.ps1","rc1-owner-gui.ps1","remote-window.ps1",
       "RdcOwnerRuntime.cs","RdcOwnerWire.cs","RdcOwnerTicketStore.cs",
       "RdcOwnerRemoteState.cs","RdcOwnerProcess.cs"}) {
    string file=Path.Combine(source,name);
    if(!File.Exists(file)||(File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RC1_MISSING_OR_LINKED_SOURCE:"+name);
   }
   string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
     @"WindowsPowerShell\v1.0\powershell.exe");
   var psi=new ProcessStartInfo(ps,
     "-NoProfile -NonInteractive -STA -File \""+
     Path.Combine(source,"rc1-tray-host.ps1")+"\" -FakeOnly");
   psi.UseShellExecute=false;
   psi.WorkingDirectory=source;
   using(var child=Process.Start(psi)){
    if(child==null)throw new InvalidOperationException("RC1_HOST_START_FAILED");
   }
   return 0;
  }catch(Exception e){
   Console.Error.WriteLine("RC1_OWNER_LAUNCH_REFUSED:"+e.GetType().Name);
   return 42;
  }
#endif
 }
}
