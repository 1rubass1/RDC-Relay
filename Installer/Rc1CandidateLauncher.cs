// Side-by-side RC1 Owner Portable/Setup launcher. New product entry point.
// Compile with RDC_RC1_BLOCKED until approved Host/GUI and OS process tests.
using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using System.Threading;
internal static class RdcRc1CandidateLauncher {
 static bool SignalExistingGui(string eventName) {
  try {
   using(EventWaitHandle activation=EventWaitHandle.OpenExisting(eventName)) {
    if(!activation.Set())throw new InvalidOperationException("RC1_GUI_SIGNAL_FAILED");
    return true;
   }
  } catch(WaitHandleCannotBeOpenedException) {
   return false; // No live same-release Host advertises GUI activation.
  }
 }
 static bool WaitForGuiReady(string eventName,int timeout){
  try{
   using(EventWaitHandle ready=EventWaitHandle.OpenExisting(eventName))
    return ready.WaitOne(timeout);
  }catch(WaitHandleCannotBeOpenedException){return false;}
 }
 static string GuiEventName(string source) {
  string normalized=Path.GetFullPath(source).TrimEnd(Path.DirectorySeparatorChar).ToLowerInvariant();
  byte[] key=new System.Security.Cryptography.SHA256Managed().ComputeHash(
    Encoding.UTF8.GetBytes(normalized));
  return @"Local\RdcRelayRC1Open-"+BitConverter.ToString(key).Replace("-","").Substring(0,32);
 }
 static string GuiReadyEventName(string source){
  return GuiEventName(source).Replace("RdcRelayRC1Open-","RdcRelayRC1GuiReady-");
 }
 static string SafeFailureCode(Exception error) {
  string code=error.Message??"";
  if(System.Text.RegularExpressions.Regex.IsMatch(code,@"^RC1_[A-Z0-9_]{3,100}$"))
   return code;
  return error.GetType().Name;
 }
 static int Main(string[] args) {
#if RDC_RC1_BLOCKED
  Console.Error.WriteLine("RC1_OWNER_LAUNCHER_BLOCKED_PENDING_OWNER_GO");
  return 42;
#else
  try{
   if(args.Length!=1 || args[0]!="--full")
     throw new InvalidOperationException("RC1_FULL_MODE_EXPLICIT_REQUIRED");
   string root=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
   string source=Path.Combine(root,"Source");
   string marker=Path.Combine(source,"rc1-candidate.json");
   if(!File.Exists(marker))throw new InvalidOperationException("RC1_NO_MARKER");
   string content=File.ReadAllText(marker,Encoding.UTF8);
   var values=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(content);
   if((string)values["candidate"]!="1.6.0 RC1" ||
      !Convert.ToBoolean(values["installable"]) ||
      !Convert.ToBoolean(values["liveRemoteEnabled"]) ||
      Convert.ToBoolean(values["publishable"]) ||
      Convert.ToBoolean(values["autoUpdateEnabled"]) ||
      (string)values["ownerMode"]!="FULL_HOST_GUI_RC1")
     throw new InvalidOperationException("RC1_NOT_VERIFIED_FULL_CANDIDATE");
   foreach(string name in new []{"rc1-tray-host.ps1","rc1-owner-gui.ps1",
       "rc1-remote-observer.ps1","remote-window.ps1",
       "RdcOwnerRuntime.cs","RdcOwnerWire.cs","RdcOwnerTicketStore.cs",
       "RdcOwnerRemoteState.cs","RdcOwnerProcess.cs","RdcOwnerManagedProcess.cs"}) {
    string file=Path.Combine(source,name);
    if(!File.Exists(file)||(File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RC1_MISSING_OR_LINKED_SOURCE:"+name);
   }
   string guiEvent=GuiEventName(source),readyEvent=GuiReadyEventName(source);
   if(SignalExistingGui(guiEvent)){
    if(!WaitForGuiReady(readyEvent,10000))
     throw new InvalidOperationException("RC1_EXISTING_HOST_GUI_NOT_READY");
    Console.WriteLine("RC1_EXISTING_HOST_GUI_READY");
    return 0;
   }
   string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
     @"WindowsPowerShell\v1.0\powershell.exe");
   var psi=new ProcessStartInfo(ps,
     "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \""+
     Path.Combine(source,"rc1-tray-host.ps1")+"\" -Full");
   psi.UseShellExecute=false;
   psi.CreateNoWindow=true;
   psi.WorkingDirectory=source;
   using(var child=Process.Start(psi)){
    if(child==null)throw new InvalidOperationException("RC1_HOST_START_FAILED");
    // Never report success merely because PowerShell accepted a new process.
    // A dying Host (singleton conflict / compile error) must fail visibly.
    var clock=Stopwatch.StartNew();
    // A first cold PowerShell/WinForms compilation may take longer than a
    // subsequent tray reopen. Keep the check bounded and monitor Host death.
    while(clock.ElapsedMilliseconds<45000){
     if(child.HasExited)throw new InvalidOperationException("RC1_HOST_EARLY_EXIT_"+child.ExitCode);
     if(SignalExistingGui(guiEvent) && WaitForGuiReady(readyEvent,250)){
      Console.WriteLine("RC1_HOST_STARTED_AUTHENTICATED_GUI_READY");
      return 0;
     }
     Thread.Sleep(250);
    }
    throw new InvalidOperationException("RC1_HOST_NO_GUI_ACTIVATION_ENDPOINT");
   }
  }catch(Exception e){
   Console.Error.WriteLine("RC1_OWNER_LAUNCH_REFUSED:"+SafeFailureCode(e));
   return 42;
  }
#endif
 }
}
