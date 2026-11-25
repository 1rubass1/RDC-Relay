# Isolated byte sink tests. No real log, account, Host, Remote or OS state.
$ErrorActionPreference='Stop'
$r=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $r 'Source\RdcOwnerLogParts.cs')
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-LogParts-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Session([string]$name){
 $p=Join-Path $root $name
 [void][IO.Directory]::CreateDirectory($p)
 return $p
}
function ReadPart([string]$file){
 # Active raw log is opened for write. Readers must share that write
 # access, exactly as the production snapshot copier does.
 $stream=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try{
  $memory=New-Object IO.MemoryStream
  try{$stream.CopyTo($memory);return ,$memory.ToArray()}finally{$memory.Dispose()}
 }finally{$stream.Dispose()}
}
$script:clock=[DateTime]::new(2026,11,23,23,59,59)
$now=[Func[DateTime]]{return $script:clock}
try{
 Check ([RdcOwnerLogParts]::PartBytes -eq 10485760 -and [RdcOwnerLogParts]::SessionBytes -eq 536870912) 'approved production limits are 10 MiB and 512 MiB'
 $dir=Session 'rotation'
 $sink=New-Object RdcOwnerLogParts -ArgumentList @($dir,4,[long]32,$now)
 try{
  $bytes=[byte[]]@(0,27,255,0xD0,0xB0,10,13,42,9)
  $sink.Write($bytes,0,$bytes.Length);$sink.Flush()
  $names=@($sink.RetainedPaths|ForEach-Object{[IO.Path]::GetFileName($_)})
  Check (($names -join ',') -ceq '2026-11-23_part-001.log,2026-11-23_part-002.log,2026-11-23_part-003.log') 'one input chunk splits into numbered parts'
  $joined=New-Object 'System.Collections.Generic.List[byte]'
  foreach($f in $sink.RetainedPaths){$joined.AddRange([byte[]](ReadPart $f))}
  Check ([Convert]::ToBase64String($joined.ToArray()) -ceq [Convert]::ToBase64String($bytes)) 'concatenation is byte-exact including UTF-8 split and ANSI/NUL'
  Check (@($sink.RetainedPaths|Where-Object{(Get-Item -LiteralPath $_).Length -gt 4}).Count -eq 0) 'no part exceeds cap'
  $script:clock=$script:clock.AddSeconds(2)
  $sink.Write([byte[]]@(12,13),0,2);$sink.Flush()
  Check ([IO.Path]::GetFileName($sink.RetainedPaths[-1]) -ceq '2026-11-24_part-001.log') 'local midnight starts new day at part-001'
  $script:clock=$script:clock.AddDays(-1)
  $sink.Write([byte[]]@(99),0,1);$sink.Flush()
  Check ([IO.Path]::GetFileName($sink.RetainedPaths[-1]) -ceq '2026-11-23_part-004.log') 'clock rollback never overwrites prior date parts'
  Check ($sink.RetainedBytes -eq 12) 'exact retained byte accounting'
 }finally{$sink.Dispose()}
 Check (@(Get-ChildItem -LiteralPath $dir -File).Count -eq 5) 'closing sink leaves all retained parts on disk'
 $refused=$false
 try{$bad=New-Object RdcOwnerLogParts -ArgumentList @($dir,4,[long]32,$now);$bad.Dispose()}catch{$refused=$true}
 Check $refused 'nonempty session cannot be silently reopened or overwritten'
 $dir=Session 'retention'
 $sink=New-Object RdcOwnerLogParts -ArgumentList @($dir,4,[long]10,$now)
 try{
  $payload=[byte[]](0..18)
  $sink.Write($payload,0,$payload.Length);$sink.Flush()
  $remaining=New-Object 'System.Collections.Generic.List[byte]'
  foreach($f in $sink.RetainedPaths){$remaining.AddRange([byte[]](ReadPart $f))}
  Check ($sink.RetainedBytes -le 10 -and $sink.RetainedBytes -eq $remaining.Count) 'non-divisible retention cap enforced'
  $tail=[byte[]]$payload[($payload.Length-$remaining.Count)..($payload.Length-1)]
  Check ([Convert]::ToBase64String($remaining.ToArray()) -ceq [Convert]::ToBase64String($tail)) 'pruning preserves exact newest contiguous byte suffix'
  Check (-not [IO.File]::Exists((Join-Path $dir '2026-11-23_part-001.log'))) 'oldest completed part pruned first'
  Check (@(Get-ChildItem -LiteralPath $dir -File).Count -eq $sink.RetainedPaths.Count) 'retained index agrees with disk'
 }finally{$sink.Dispose()}
 $dir=Session 'no-overwrite'
 $sink=New-Object RdcOwnerLogParts -ArgumentList @($dir,4,[long]16,$now)
 try{
  $sink.Write([byte[]]@(1,2,3,4),0,4)
  $foreign=Join-Path $dir '2026-11-23_part-002.log'
  [IO.File]::WriteAllText($foreign,'FOREIGN')
  $refused=$false
  try{$sink.Write([byte[]]@(5),0,1)}catch{$refused=$true}
  Check ($refused -and [IO.File]::ReadAllText($foreign) -ceq 'FOREIGN') 'existing part collision fails without overwriting'
  $refused=$false
  try{$sink.Write([byte[]]@(6),0,1)}catch{$refused=$true}
  Check $refused 'faulted writer cannot continue with inconsistent state'
 }finally{$sink.Dispose()}
}finally{[IO.Directory]::Delete($root,$true)}
Write-Output ('RDC_RAW_LOG_PARTS_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
