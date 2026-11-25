# Actual production raw log functions against disposable files. No real log or viewer.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source\remote-window.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'RAW_LOG_PARSE_FAILED'}
foreach($name in @('Get-RdcOwnerRawLogPath','Copy-RdcOwnerRawLogSnapshot')){
 $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
 if(-not $fn){throw ('PRODUCTION_RAW_LOG_FUNCTION_MISSING_'+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){if($ok){$script:pass++;Write-Output ('PASS '+$label)}else{$script:fail++;Write-Output ('FAIL '+$label)}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RawLogTest-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try{
 $run=Join-Path $temp ('run-'+[Guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($run)
 $OwnerGui=$true;$script:ownerManagedMode=$true;$script:ownerRawLogRunRoot=$run
 Check ($null -eq (Get-RdcOwnerRawLogPath)) 'no Remote log before process start'
 $foreign=Join-Path $run 'remote-foreign.log'
 [IO.File]::WriteAllText($foreign,'FOREIGN')
 $logout=Join-Path $run ('logout-'+[Guid]::NewGuid().ToString('N')+'.log')
 [IO.File]::WriteAllText($logout,'LOGOUT_PRIVATE')
 Check ($null -eq (Get-RdcOwnerRawLogPath)) 'foreign and logout files are not eligible Remote logs'
 $older=Join-Path $run ('remote-'+[Guid]::NewGuid().ToString('N')+'.log')
 $newer=Join-Path $run ('remote-'+[Guid]::NewGuid().ToString('N')+'.log')
 [IO.File]::WriteAllText($older,'OLDER')
 [IO.File]::SetCreationTimeUtc($older,[DateTime]::UtcNow.AddMinutes(-5))
 $bytes=[byte[]]@(27,91,51,49,109,0,255,10,13,120,0,42)
 [IO.File]::WriteAllBytes($newer,$bytes)
 Check ((Get-RdcOwnerRawLogPath) -ceq $newer) 'latest current Host Remote log chosen, not arbitrary file'
 $copy=Join-Path $temp 'copy.log'
 $stream=[IO.File]::Open($newer,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{Copy-RdcOwnerRawLogSnapshot $newer $copy}finally{$stream.Dispose()}
 Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($copy)) -ceq [Convert]::ToBase64String($bytes)) 'raw copy preserves every byte including ANSI and invalid UTF8'
 [IO.File]::AppendAllText($copy,'USER_EDIT')
 Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($newer)) -ceq [Convert]::ToBase64String($bytes)) 'editing copy cannot mutate Host source log'
 $denied=$false;try{Copy-RdcOwnerRawLogSnapshot $newer $copy}catch{$denied=$true}
 Check $denied 'copy never overwrites existing destination'
 $script:ownerManagedMode=$false
 Check ($null -eq (Get-RdcOwnerRawLogPath)) 'observed/fake mode cannot read an unowned log'
 $script:ownerManagedMode=$true;$OwnerGui=$false
 Check ($null -eq (Get-RdcOwnerRawLogPath)) 'legacy renderer does not gain owner log route'
 $OwnerGui=$true;$script:ownerRawLogRunRoot=$temp
 Check ($null -eq (Get-RdcOwnerRawLogPath)) 'unverified run-directory name rejected'
 # Real session layout: the authenticated run sits beside immutable releases.
 $pilot=Join-Path $temp 'RDCRelayOwnerPilot'
 $run2=Join-Path (Join-Path $pilot '1.6.0-RC1') ('run-'+[Guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($run2)
 $script:ownerRawLogRunRoot=$run2
 $logs=Join-Path $pilot 'Logs'
 $cur=Join-Path $logs 'CurrentSession';$prev=Join-Path $logs 'PreviousSession'
 [void][IO.Directory]::CreateDirectory($cur);[void][IO.Directory]::CreateDirectory($prev)
 $cid='RDC-LOG-SESSION-V1:'+[Guid]::NewGuid().ToString('N')
 $pidMarker='RDC-LOG-SESSION-V1:'+[Guid]::NewGuid().ToString('N')
 [IO.File]::WriteAllText((Join-Path $cur '.rdc-session-v1'),$cid)
 [IO.File]::WriteAllText((Join-Path $prev '.rdc-session-v1'),$pidMarker)
 [IO.File]::WriteAllText((Join-Path $prev '.rdc-accepted-v1'),$pidMarker)
 $c1=Join-Path $cur '2026-11-24_part-001.log';$c2=Join-Path $cur '2026-11-24_part-002.log'
 $p1=Join-Path $prev '2026-11-23_part-001.log'
 [IO.File]::WriteAllText($c1,'CURRENT1');[IO.File]::SetCreationTimeUtc($c1,[DateTime]::UtcNow.AddMinutes(-5))
 [IO.File]::WriteAllBytes($c2,$bytes);[IO.File]::WriteAllText($p1,'PREVIOUS')
 [IO.File]::WriteAllText((Join-Path $cur 'foreign.log'),'FOREIGN')
 $all=@(Get-RdcOwnerRawLogPath -All)
 Check ($all.Count -eq 3 -and $all[0] -ceq $c2 -and $all -ccontains $p1) 'rotated viewer lists current and previous owned parts, latest current first'
 $partCopy=Join-Path $temp 'part-copy.log'
 Copy-RdcOwnerRawLogSnapshot $c2 $partCopy
 Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($partCopy)) -ceq [Convert]::ToBase64String($bytes)) 'rotated part copied byte-exact'
 [IO.File]::Delete($c1);[IO.File]::Delete($c2)
 Check ((Get-RdcOwnerRawLogPath) -ceq $p1) 'previous available when current has no log parts'
 $source=[IO.File]::ReadAllText($src)
 $owner=[IO.File]::ReadAllText((Join-Path $root 'Source\rc1-owner-gui.ps1'))
 Check ($owner.IndexOf('$script:ownerRawLogRunRoot=$run') -gt $owner.IndexOf("RC1_OWNER_SNAPSHOT_MISMATCH") -and
  $source.Contains('Open-RdcOwnerRawLog ($sender.FindForm())') -and $source.Contains('Copy-RdcOwnerRawLogSnapshot $source $copy')) 'real button uses authenticated run and snapshot; no auto-open'
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
Write-Output ('RDC_OWNER_RAW_LOG_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
