# Persistent session publication, failure preservation and crash recovery.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $repo 'Source\RdcOwnerLogParts.cs')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-LOG-SESSIONS-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$store=$null;$sink=$null;$pass=0
function Check([bool]$ok,[string]$name){if(-not $ok){throw ('FAIL '+$name)};$script:pass++;Write-Output ('PASS '+$name)}
function Begin-Data([byte[]]$data,[bool]$accept){
 $script:sink=$script:store.Begin()
 $script:sink.Write($data,0,$data.Length)
 if($accept){$script:store.Accept()}
 $script:sink.Dispose();$script:sink=$null
}
function Read-Parts([string]$path){
 $a=New-Object IO.MemoryStream
 try{foreach($f in @(Get-ChildItem -LiteralPath $path -File -Filter '*.log'|Sort-Object Name)){$b=[IO.File]::ReadAllBytes($f.FullName);$a.Write($b,0,$b.Length)};[Convert]::ToBase64String($a.ToArray())}finally{$a.Dispose()}
}
function Reopen(){
 $script:store.Dispose()
 $script:store=New-Object RdcOwnerLogSessions -ArgumentList $root
 $script:store.Recover()
}
try{
 $store=New-Object RdcOwnerLogSessions -ArgumentList $root
 $store.Recover()
 $c=$store.CurrentPath;$p=$store.PreviousPath;$r=Join-Path $root 'RetiredSession';$failed=$store.FailedPath
 $denied=$false
 try{$other=New-Object RdcOwnerLogSessions -ArgumentList $root;$other.Dispose()}catch{$denied=$true}
 Check $denied 'exclusive per-user session lease'
 Begin-Data ([byte[]](1,2,3)) $true
 Check ((Test-Path -LiteralPath $c) -and -not (Test-Path -LiteralPath $p)) 'current created without shifting previous'
 $store.FinalizeCurrent()
 Check ((Read-Parts $p) -ceq 'AQID' -and -not (Test-Path -LiteralPath $c)) 'accepted completed current becomes previous'
 Begin-Data ([byte[]](4,5)) $false
 $store.FinalizeCurrent()
 Check ((Read-Parts $p) -ceq 'AQID' -and -not (Test-Path -LiteralPath $c)) 'failed launch leaves previous byte-exact'
 $firstFailed=[IO.File]::ReadAllBytes($failed)
 Check (([Text.Encoding]::UTF8.GetString($firstFailed)).Contains('raw_included_bytes=2 raw_truncated=no') -and $firstFailed[-2] -eq 4 -and $firstFailed[-1] -eq 5) 'failed report includes original bytes'
 Begin-Data ([byte[]](6,7)) $false
 Reopen
 Check ((Read-Parts $p) -ceq 'AQID' -and -not (Test-Path -LiteralPath $c)) 'interrupted unaccepted session leaves previous'
 $recoveredFailed=[IO.File]::ReadAllBytes($failed)
 Check (([Text.Encoding]::UTF8.GetString($recoveredFailed)).Contains('completion=unknown') -and $recoveredFailed[-2] -eq 6 -and $recoveredFailed[-1] -eq 7) 'recovery replaces only failed report, unknown completion explicit'
 Begin-Data ([byte[]](8,9)) $true
 Reopen
 Check ((Read-Parts $p) -ceq 'CAk=' -and -not (Test-Path -LiteralPath $c)) 'accepted interrupted session recovered as previous'
 Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($failed)) -ceq [Convert]::ToBase64String($recoveredFailed)) 'accepted session preserves failed report'
 Begin-Data ([byte[]](10,11)) $true
 $store.Dispose()
 [IO.Directory]::Move($p,$r)
 $store=New-Object RdcOwnerLogSessions -ArgumentList $root
 $store.Recover()
 Check ((Read-Parts $p) -ceq 'Cgs=' -and -not (Test-Path -LiteralPath $r)) 'recovery after first publication rename'
 Begin-Data ([byte[]](12,13)) $true
 $store.Dispose()
 [IO.Directory]::Move($p,$r)
 [IO.Directory]::Move($c,$p)
 $store=New-Object RdcOwnerLogSessions -ArgumentList $root
 $store.Recover()
 Check ((Read-Parts $p) -ceq 'DA0=' -and -not (Test-Path -LiteralPath $r)) 'recovery after second publication rename'
 Begin-Data ([byte[]](14,15)) $true
 $foreign=Join-Path $p 'foreign.txt'
 [IO.File]::WriteAllText($foreign,'leave me')
 $denied=$false
 try{$store.FinalizeCurrent()}catch{$denied=$true}
 Check ($denied -and (Test-Path -LiteralPath $foreign) -and (Read-Parts $p) -ceq 'DA0=' -and (Read-Parts $c) -ceq 'Dg8=') 'unknown file prevents any publication or deletion'
 [IO.File]::Delete($foreign)
 $store.FinalizeCurrent()
 Check ((Read-Parts $p) -ceq 'Dg8=') 'publication retried after removing fixture-owned obstruction'
}finally{
 if($sink){$sink.Dispose()}
 if($store){$store.Dispose()}
 if([IO.Path]::GetFileName($root) -cnotmatch '^RDC-LOG-SESSIONS-[a-f0-9]{32}$' -or [IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)){throw 'SESSION_TEST_CLEANUP_SCOPE'}
 foreach($e in Get-ChildItem -LiteralPath $root -Force){
  if($e.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'SESSION_TEST_CLEANUP_REPARSE'}
  if($e.PSIsContainer){
   if(@('CurrentSession','PreviousSession','RetiredSession') -cnotcontains $e.Name){throw 'SESSION_TEST_CLEANUP_UNKNOWN'}
   foreach($f in Get-ChildItem -LiteralPath $e.FullName -Force){
    if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($f.Name -cnotmatch '^(\.rdc-(session|accepted)-v1|\d{4}-\d{2}-\d{2}_part-\d+\.log|foreign\.txt)$')){throw 'SESSION_TEST_CLEANUP_UNKNOWN'}
   }
  }elseif(@('.rdc-session-lock-v1','Last unsuccessful sessions.log') -cnotcontains $e.Name){throw 'SESSION_TEST_CLEANUP_UNKNOWN'}
 }
 [IO.Directory]::Delete($root,$true)
}
Write-Output ('RDC_LOG_SESSIONS_PASS='+$pass)
