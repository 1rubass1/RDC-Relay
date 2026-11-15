# Review-only: exact shipped DLL, private dummy Job, synthetic log files.
# No RdcOwnerRuntime constructor, GUI, upstream Remote, network or credentials.
param([Parameter(Mandatory=$true)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
$package=[IO.Path]::GetFullPath($PackageDirectory)
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Web.Extensions
[void][Reflection.Assembly]::LoadFrom((Join-Path $package 'RdcOwnerRuntime.dll'))
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-REVIEW2-UTF8-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$utf8=New-Object Text.UTF8Encoding($false)
$fake=Join-Path $root 'npx.cmd';$log=Join-Path $root 'input.log'
[IO.File]::WriteAllText($fake,"@echo off`r`nping.exe -n 30 127.0.0.1 > NUL`r`n")
$job=New-Object RdcOwnerManagedProcess
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
function SetField($obj,$name,$value){$obj.GetType().GetField($name,$flags).SetValue($obj,$value)}
function NewReader {
 $runtime=[Runtime.Serialization.FormatterServices]::GetUninitializedObject([RdcOwnerRuntime])
 $state=New-Object RdcOwnerRemoteState
 $state.EnableManaged();$state.ManagedStatus($job.Pid,$true,'Ready','synthetic review fixture')
 SetField $runtime 'managedMode' $true
 SetField $runtime 'managedProcess' $job
 SetField $runtime 'managedState' 'Ready'
 SetField $runtime 'managedLogPath' $log
 SetField $runtime 'managedLogFragment' ''
 SetField $runtime 'managedLogOffset' ([long]0)
 SetField $runtime 'managedStartupComplete' $true
 SetField $runtime 'managedBannerScanned' 100
 SetField $runtime 'remoteSupervisor' $state
 SetField $runtime 'toolJournal' (New-Object RdcOwnerToolJournal)
 SetField $runtime 'events' (New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[string,object]]')
 SetField $runtime 'managedBannerArt' (New-Object 'System.Collections.Generic.List[string]')
 SetField $runtime 'managedStartupHeader' (New-Object 'System.Collections.Generic.List[string]')
 return [pscustomobject]@{Runtime=$runtime;State=$state}
}
$results=@();$clean=$false
try {
 $job.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote',$root,(Join-Path $root 'job.log'))
 if(-not $job.Running){throw 'Own dummy Job is not alive'}
 $start=[char]::ConvertFromUtf32(0x1F527)+' Received tool call review-1: read_file {}'+"`n"
 $finish=[string][char]0x2705+' Tool call read_file completed: ok'+"`n"
 $prefixBytes=$utf8.GetByteCount($start)
 $padding=('x'*(32767-$prefixBytes-1))+"`n"
 $cases=@(
  @{Name='intact-control';Text=$start+$finish;Events=2;Activity='hold';State='Ready'},
  @{Name='completion-UTF8-split-at-32768';Text=$start+$padding+$finish;Events=2;Activity='hold';State='Ready'},
  @{Name='start-UTF8-split-at-32768';Text=('x'*32766)+"`n"+$start+$finish;Events=2;Activity='hold';State='Ready'},
  @{Name='recognized-fault-control';Text="Channel error: synthetic`n";Events=1;Activity='idle';State='Fault'},
  @{Name='channel-closed';Text="Channel closed - socket=closed(-) ch=closed attempt=1`n";Events=1;Activity='idle';State='Fault'},
  @{Name='expired-session';Text="Remote session expired and could not be renewed.`n";Events=1;Activity='idle';State='Fault'},
  @{Name='unreachable-device';Text="Device registered, but NOT reachable`n";Events=1;Activity='idle';State='Fault'},
  @{Name='local-mcp-restart-failed';Text="Could not restart local Desktop Commander MCP: synthetic`n";Events=1;Activity='idle';State='Reconnecting'}
 )
 foreach($case in $cases){
  [IO.File]::WriteAllBytes($log,$utf8.GetBytes($case.Text))
  $fixture=NewReader
  $method=[RdcOwnerRuntime].GetMethod('RefreshManagedRemote',$flags)
  for($i=0;$i -lt 3;$i++){[void]$method.Invoke($fixture.Runtime,@())}
  $snap=$fixture.State.Snapshot()
  $row=[pscustomobject]@{case=$case.Name;expectedEvents=$case.Events;actualEvents=$snap['tail'].Length;expectedActivity=$case.Activity;actualActivity=$snap['toolActivity'];expectedState=$case.State;actualState=$snap['state'];tail=$snap['tail'];diagnostics=$snap['diagnostics']}
  $results+=$row;Write-Output ($row|ConvertTo-Json -Depth 6 -Compress)
 }
 $results|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'utf8-reader-results.json') -Encoding UTF8
} finally {
 try{$clean=$job.StopOwnedOnly(10000) -and -not $job.Running}finally{$job.Dispose()}
 Write-Output ('REVIEW_DUMMY_JOB_DRAINED='+$clean)
 if($clean){
  $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  if([IO.Path]::GetDirectoryName($root) -cne $parent -or [IO.Path]::GetFileName($root) -cnotmatch '^RDC-REVIEW2-UTF8-[a-f0-9]{32}$'){throw 'Cleanup scope refused'}
  $files=@(Get-ChildItem -LiteralPath $root -Force)
  foreach($file in $files){if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Name -cnotin @('npx.cmd','job.log','input.log')){throw 'Cleanup member refused'}}
  foreach($file in $files){[IO.File]::Delete($file.FullName)}
  [IO.Directory]::Delete($root,$false)
  Write-Output 'REVIEW_UTF8_FIXTURE_CLEAN=True'
 }
}

