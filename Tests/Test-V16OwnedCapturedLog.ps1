# Disposable synthetic npx.cmd; never invokes npm or actual Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-CAPTURE-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$fake=Join-Path $root 'npx.cmd'
$actor=Join-Path $root 'actor.ps1'
$parts=Join-Path $root 'parts'
[void][IO.Directory]::CreateDirectory($parts)
$owner=$null;$sink=$null;$pump=$null;$pass=0
function Check([bool]$ok,[string]$name){
 if(-not $ok){throw ('FAIL '+$name)}
 $script:pass++; Write-Output ('PASS '+$name)
}
try{
 Add-Type -Path @((Join-Path $repo 'Source\RdcOwnerManagedProcess.cs'),(Join-Path $repo 'Source\RdcOwnerLogParts.cs'))
 $runtime=[IO.File]::ReadAllText((Join-Path $repo 'Source\RdcOwnerRuntime.cs'))
 $start=$runtime.IndexOf('public sealed class RdcOwnerUtf8LogBuffer {',[StringComparison]::Ordinal)
 $end=$runtime.IndexOf('// Host-local, bounded correlation',$start,[StringComparison]::Ordinal)
 if($start -lt 0 -or $end -le $start){throw 'PARSER_SOURCE_BOUNDARY'}
 Add-Type -TypeDefinition ('using System; using System.Text; using System.Collections.Generic;'+$runtime.Substring($start,$end-$start))
 $actorText=@'
$ErrorActionPreference='Stop'
$out=[Console]::OpenStandardOutput()
$err=[Console]::OpenStandardError()
[byte[]]$a=0,255,27,91,51,50,109,240,159,140,144,13,10
[byte[]]$b=193,128,0,13,10
$out.Write($a,0,$a.Length);$out.Flush()
$err.Write($b,0,$b.Length);$err.Flush()
$bulk=New-Object byte[] 150000
for($i=0;$i -lt $bulk.Length;$i++){$bulk[$i]=[byte]($i%251)}
$out.Write($bulk,0,$bulk.Length);$out.Flush()
exit 0
'@
 [IO.File]::WriteAllText($actor,$actorText)
 $cmd='@echo off'+[Environment]::NewLine+'"'+(Join-Path $PSHOME 'powershell.exe')+'" -NoProfile -NonInteractive -File "'+$actor+'"'+[Environment]::NewLine
 [IO.File]::WriteAllText($fake,$cmd)
 $owner=New-Object RdcOwnerManagedProcess
 $clock=[Delegate]::CreateDelegate([Func[DateTime]],[DateTime].GetProperty('Now').GetGetMethod())
 $sink=New-Object RdcOwnerLogParts -ArgumentList @($parts,4096,[long]200000,$clock)
 $denied=$false
 try{$owner.StartCaptured($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout',$root)}catch{$denied=$true}
 Check $denied 'capture excludes logout'
 $owner.StartCaptured($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote',$root)
 Check ($owner.Pid -gt 0 -and $owner.HasStarted) 'captured child created under existing verified Job'
 $reader=[Delegate]::CreateDelegate([RdcOwnerLogReader],$owner,'ReadCaptured')
 $pump=New-Object RdcOwnerLogPump -ArgumentList @($reader,$sink)
 $sink=$null
 $watch=[Diagnostics.Stopwatch]::StartNew()
 Check ($pump.WaitForCompletion(15000) -and $pump.CleanEof -and -not $pump.ReadFault -and -not $pump.StorageFault) 'background worker drains to EOF without any Host timer or parser consumption'
 $parsed=New-Object 'System.Collections.Generic.List[string]'
 $parser=New-Object RdcOwnerUtf8LogBuffer
 $buf=New-Object byte[] 7;$seen=0
 while(($n=$pump.ReadPending($buf)) -gt 0){$seen+=$n;if($seen -gt 200000){throw 'CAPTURE_OUTPUT_LIMIT'};$parsed.AddRange([string[]]$parser.Feed($buf,0,$n))}
 Check (-not $pump.ParserFault -and $pump.PendingBytes -eq 0) 'bounded parser queue fully consumed in 7-byte chunks'
 $code=0
 while(-not $owner.TryGetCompletedExitCode([ref]$code) -and $watch.ElapsedMilliseconds -lt 15000){Start-Sleep -Milliseconds 10}
 Check (-not $owner.Running -and $code -eq 0) 'complete fake Job exits normally'
 $paths=$pump.RetainedPaths
 Check ($paths.Length -gt 1) 'captured stream split into multiple parts'
 $actual=New-Object IO.MemoryStream
 foreach($file in $paths){$bytes=[IO.File]::ReadAllBytes($file);Check ($bytes.Length -le 4096) 'part size cap';$actual.Write($bytes,0,$bytes.Length)}
 [byte[]]$prefix=0,255,27,91,51,50,109,240,159,140,144,13,10,193,128,0,13,10
 $expected=New-Object byte[] (150000+$prefix.Length)
 [Array]::Copy($prefix,$expected,$prefix.Length)
 for($i=0;$i -lt 150000;$i++){$expected[$i+$prefix.Length]=[byte]($i%251)}
 Check ($seen -eq $expected.Length -and [Convert]::ToBase64String($actual.ToArray()) -ceq [Convert]::ToBase64String($expected)) 'merged stdout/stderr exactly matches original bytes across parts'
 $reference=New-Object RdcOwnerUtf8LogBuffer
 $referenceLines=$reference.Feed($expected,0,$expected.Length)
 Check ($parsed.Count -eq $referenceLines.Length -and [string]::Join([char]0,$parsed.ToArray()) -ceq [string]::Join([char]0,$referenceLines)) 'actual Host UTF8 parser equivalent to contiguous original stream'
 $actual.Dispose()
}finally{
 if($sink){$sink.Dispose()}
 $safe=$true
 if($owner){
  if($owner.HasStarted -and $owner.Running){$safe=$owner.StopOwnedOnly(10000)}
  if($pump -and -not $pump.WaitForCompletion(3000)){$safe=$false}
  if($safe){$owner.Dispose()}
 }
 if(-not $safe){throw 'CAPTURE_JOB_SURVIVOR_RETAIN_TEMP'}
 if([IO.Path]::GetFileName($root) -cnotmatch '^RDC-RC1-CAPTURE-[a-f0-9]{32}$' -or [IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)){throw 'CAPTURE_CLEANUP_SCOPE'}
 foreach($entry in Get-ChildItem -LiteralPath $root -Force){
  if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @('parts','actor.ps1','npx.cmd') -cnotcontains $entry.Name){throw 'CAPTURE_CLEANUP_UNKNOWN'}
 }
 foreach($entry in Get-ChildItem -LiteralPath $parts -Force){
  if($entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $entry.Name -cnotmatch '^\d{4}-\d{2}-\d{2}_part-\d+\.log$'){throw 'CAPTURE_CLEANUP_UNKNOWN_PART'}
 }
 [IO.Directory]::Delete($root,$true)
}
Write-Output ('RC1_CAPTURE_PASS='+$pass)
