// A release migration must not race the stable 1.5.x GUI or updater.
// Use precisely their existing path-derived mutexes, without stopping
// either process. A disposable synthetic legacy root is used by tests.
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Security.Cryptography;

internal sealed class RdcReleaseLegacyMigrationLease : IDisposable {
 readonly Mutex window,payload;
 bool windowHeld,payloadHeld,disposed;
 internal static string Key(string root){
  string full=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
  using(var sha=SHA256.Create())
   return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(full.ToLowerInvariant()))).Replace("-","");
 }
 static bool Acquire(Mutex m){
  try{return m.WaitOne(0);}catch(AbandonedMutexException){return true;}
 }
 internal RdcReleaseLegacyMigrationLease(string legacyRoot){
  string key=Key(legacyRoot);
  window=new Mutex(false,@"Local\RemoteDesktopCommanderWindow-"+key);
  try{
   if(!Acquire(window))throw new IOException("RDC_V16_LEGACY_GUI_ACTIVE");
   windowHeld=true;
   payload=new Mutex(false,@"Local\RDCRelayPayload-"+key);
   if(!Acquire(payload))throw new IOException("RDC_V16_LEGACY_UPDATE_ACTIVE");
   payloadHeld=true;
  }catch{Dispose();throw;}
 }
 public void Dispose(){
  if(disposed)return;
  disposed=true;
  if(payload!=null){try{if(payloadHeld)payload.ReleaseMutex();}finally{payload.Dispose();}}
  if(window!=null){try{if(windowHeld)window.ReleaseMutex();}finally{window.Dispose();}}
 }
}