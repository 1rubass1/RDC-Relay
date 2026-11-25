# Exercise the genuine legacy migration exclusion against a synthetic root.
# The named mutexes include a random temporary path, never an installed root.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $repo 'Installer\RdcReleaseLegacyMigrationLease.cs') -ReferencedAssemblies System.dll
$type=([AppDomain]::CurrentDomain.GetAssemblies()|ForEach-Object{$_.GetType('RdcReleaseLegacyMigrationLease',$false)}|Where-Object{$_})[0]
$flags=[Reflection.BindingFlags]'Static,Instance,NonPublic,Public'
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-V16-LEASE-'+[Guid]::NewGuid().ToString('N'))
$expected=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-','')
$key=$type.GetMethod('Key',$flags).Invoke($null,[object[]]@([string]$root))
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
Check ($key -ceq $expected) 'exact stable mutex path hash'
# A separate CLR thread models an independent GUI/updater. All handles and
# waits are bounded and are scoped only to the random synthetic key.
Add-Type -TypeDefinition @"
using System;using System.Threading;
public sealed class RdcLegacyLeaseFixture : IDisposable {
 readonly Thread worker;readonly ManualResetEvent ready=new ManualResetEvent(false),done=new ManualResetEvent(false);
 public bool Held;
 public RdcLegacyLeaseFixture(string name){
  worker=new Thread(delegate(){
   using(var mutex=new Mutex(false,name)){
    Held=mutex.WaitOne(0);ready.Set();
    try{done.WaitOne(10000);}finally{if(Held)mutex.ReleaseMutex();}
   }
  });worker.IsBackground=true;worker.Start();
  if(!ready.WaitOne(2000))throw new Exception("FIXTURE_TIMEOUT");
 }
 public void Dispose(){done.Set();if(!worker.Join(3000))throw new Exception("FIXTURE_JOIN");ready.Dispose();done.Dispose();}
}
"@
function Take-Lease{[Activator]::CreateInstance($type,$flags,$null,[object[]]@([string]$root),$null)}
function Refused($reason){
 try{$l=Take-Lease;$l.Dispose();return $false}catch{
  $e=$_.Exception;while($e.InnerException){$e=$e.InnerException};return $e.Message -ceq $reason
 }
}
$fixture=New-Object RdcLegacyLeaseFixture ('Local\RemoteDesktopCommanderWindow-'+$key)
try{Check ($fixture.Held -and (Refused 'RDC_V16_LEGACY_GUI_ACTIVE')) 'active legacy GUI refuses migration'}finally{$fixture.Dispose()}
$fixture=New-Object RdcLegacyLeaseFixture ('Local\RDCRelayPayload-'+$key)
try{Check ($fixture.Held -and (Refused 'RDC_V16_LEGACY_UPDATE_ACTIVE')) 'active legacy updater refuses migration'
 $probe=New-Object RdcLegacyLeaseFixture ('Local\RemoteDesktopCommanderWindow-'+$key)
 try{Check $probe.Held 'failed payload acquisition releases GUI mutex'}finally{$probe.Dispose()}
}finally{$fixture.Dispose()}
$l=Take-Lease
try{
 foreach($prefix in @('Local\RemoteDesktopCommanderWindow-','Local\RDCRelayPayload-')){
  $probe=New-Object RdcLegacyLeaseFixture ($prefix+$key)
  try{Check (!$probe.Held) ('migration holds '+$prefix)}finally{$probe.Dispose()}
 }
}finally{$l.Dispose()}
foreach($prefix in @('Local\RemoteDesktopCommanderWindow-','Local\RDCRelayPayload-')){
 $probe=New-Object RdcLegacyLeaseFixture ($prefix+$key)
 try{Check $probe.Held ('completed migration releases '+$prefix)}finally{$probe.Dispose()}
}
'RDC_V16_LEGACY_LEASE_PASS='+$pass+' FAIL=0'