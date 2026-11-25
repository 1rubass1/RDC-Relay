# Synthetic bounded reader and failure injection; no process or Remote launch.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $repo 'Source\RdcOwnerLogParts.cs')
Add-Type -TypeDefinition @'
using System;
public sealed class RdcLogPumpProbe {
 int offset;
 public int Read(byte[] buffer,out bool eof) {
  int n=Math.Min(5,40-offset);
  eof=n==0;
  for(int i=0;i<n;i++)buffer[i]=(byte)(offset+i);
  offset+=n;return n;
 }
 public int Invalid(byte[] buffer,out bool eof){eof=false;return buffer.Length+1;}
 public static DateTime Clock(){return new DateTime(2026,11,24);}
}
'@
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-LOG-PUMP-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$pass=0;$pump=$null
function Check([bool]$ok,[string]$name){if(-not $ok){throw ('FAIL '+$name)};$script:pass++;Write-Output ('PASS '+$name)}
function New-Sink([string]$dir){
 [void][IO.Directory]::CreateDirectory($dir)
 $clock=[Delegate]::CreateDelegate([Func[DateTime]],[RdcLogPumpProbe].GetMethod('Clock'))
 New-Object RdcOwnerLogParts -ArgumentList @($dir,8,[long]64,$clock)
}
function New-Reader([string]$method){
 [Delegate]::CreateDelegate([RdcOwnerLogReader],(New-Object RdcLogPumpProbe),$method)
}
try{
 $sink=New-Sink (Join-Path $root 'overflow')
 $pump=New-Object RdcOwnerLogPump -ArgumentList @((New-Reader Read),$sink,8)
 Check ($pump.WaitForCompletion(3000) -and $pump.CleanEof -and -not $pump.StorageFault -and -not $pump.ReadFault) 'parser overload does not prevent draining or retaining raw bytes'
 Check ($pump.ParserFault -and $pump.PendingBytes -eq 0 -and $pump.ReadPending((New-Object byte[] 8)) -eq 0) 'overload latches parser fault and refuses to continue after gap'
 $actual=New-Object IO.MemoryStream
 foreach($path in $pump.RetainedPaths){$bytes=[IO.File]::ReadAllBytes($path);$actual.Write($bytes,0,$bytes.Length)}
 Check ([Convert]::ToBase64String($actual.ToArray()) -ceq [Convert]::ToBase64String([byte[]](0..39))) 'all original bytes retained despite parser overflow'
 $actual.Dispose()
 $dir=Join-Path $root 'storage'
 $sink=New-Sink $dir
 $foreign=Join-Path $dir '2026-11-24_part-001.log'
 [IO.File]::WriteAllBytes($foreign,[byte[]](90,91))
 $pump=New-Object RdcOwnerLogPump -ArgumentList @((New-Reader Read),$sink,64)
 Check ($pump.WaitForCompletion(3000) -and $pump.CleanEof -and $pump.StorageFault -and -not $pump.ParserFault -and -not $pump.ReadFault) 'sink failure latches but still drains and supplies parser'
 $data=New-Object byte[] 40
 Check ($pump.ReadPending($data) -eq 40 -and [Convert]::ToBase64String($data) -ceq [Convert]::ToBase64String([byte[]](0..39))) 'parser receives original bytes after storage failure'
 Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($foreign)) -ceq 'Wls=') 'collision never overwrites existing file'
 $sink=New-Sink (Join-Path $root 'invalid')
 $pump=New-Object RdcOwnerLogPump -ArgumentList @((New-Reader Invalid),$sink,64)
 Check ($pump.WaitForCompletion(3000) -and $pump.ReadFault -and -not $pump.CleanEof) 'invalid reader contract is not misreported as EOF'
}finally{
 if($pump -and -not $pump.WaitForCompletion(3000)){throw 'PUMP_STILL_RUNNING_RETAIN_FIXTURE'}
 if([IO.Path]::GetFileName($root) -cnotmatch '^RDC-LOG-PUMP-[a-f0-9]{32}$' -or [IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)){throw 'PUMP_CLEANUP_SCOPE'}
 foreach($entry in Get-ChildItem -LiteralPath $root -Force){
  if(-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @('overflow','storage','invalid') -cnotcontains $entry.Name){throw 'PUMP_CLEANUP_UNKNOWN'}
  foreach($file in Get-ChildItem -LiteralPath $entry.FullName -Force){
   if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Name -cnotmatch '^2026-11-24_part-\d+\.log$'){throw 'PUMP_CLEANUP_UNKNOWN_PART'}
  }
 }
 [IO.Directory]::Delete($root,$true)
}
Write-Output ('RDC_LOG_PUMP_PASS='+$pass)
