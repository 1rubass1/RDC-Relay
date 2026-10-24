# P3A negative cleanup tests: only freshly owned test Host/GUI and fake files.
$ErrorActionPreference='Stop'
$ps=Join-Path $PSHOME 'powershell.exe'
$state=Join-Path $PSScriptRoot 'RunState'
$marker=Join-Path $state 'active-demo.json'
. (Join-Path $PSScriptRoot 'P3-Ownership.ps1')

$pass=0;$fail=0;$run=$null;$original=$null;$foreign=$null;$sentinel=$null
function Check([bool]$v,[string]$name){
 if(-not $v){throw ('FAIL '+$name)}
 $script:pass++;Write-Output ('PASS '+$name)
}
function CallCleanup([string]$Name,[string]$Root=''){
 $argsList=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $Name))
 if($Root){$argsList+=@('-FixtureRoot',$Root)}
 $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot $Name)+'"'
 if($Root){$arguments+=' -FixtureRoot "'+$Root+'"'}
 $p=Start-Process -FilePath $ps -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
 try{return [pscustomobject]@{Exit=$p.ExitCode;Output='(separate process; observed exit code)'}}finally{$p.Dispose()}
}
function AssertStillOwn([string]$label,[byte[]]$baseline){
 Check ([IO.File]::Exists($marker)) ($label+' marker retained')
 Check ([IO.Directory]::Exists($run.Root)) ($label+' own fixture retained')
 $now=[IO.File]::ReadAllBytes($marker)
 Check ([Convert]::ToBase64String($now) -ceq [Convert]::ToBase64String($baseline)) ($label+' marker bytes unchanged')
}
try{
 if([IO.File]::Exists($marker)){throw 'Preexisting active-demo marker: not running destructive test'}
 $r=@(& (Join-Path $PSScriptRoot 'Start-Demo.ps1'))
 if(-not [IO.File]::Exists($marker)){throw ('Fresh P3 launch did not create a marker: '+($r -join ' '))}
 $run=Get-P3BoundRun $state
 $original=[IO.File]::ReadAllBytes($marker)
 $originalJson=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
 $root=$run.Root
 $ownPid=[int]$originalJson.HostPID
 $hostProcess=[Diagnostics.Process]::GetProcessById($ownPid)
 Check (-not $hostProcess.HasExited -and $hostProcess.StartTime.ToUniversalTime().Ticks -eq [long]$originalJson.HostStartTicks) 'real owned Host alive before refusal'
 $bad=CallCleanup 'Check-And-Cleanup.ps1'
 Check ($bad.Exit -ne 0) 'F1 cleanup refuses live own Host/GUI with nonzero exit'
 AssertStillOwn 'F1 LIVE' $original
 $hostProcess.Refresh()
 Check (-not $hostProcess.HasExited) 'F1 cleanup did not kill own Host'
 $authPath=Join-Path $root 'controller-auth.json'
 $auth=[P1Wire]::Decode([IO.File]::ReadAllText($authPath,[Text.Encoding]::UTF8))
 $identity=([string]$auth.hostPid)+'|'+([string]$auth.hostTicks)+'|'+([string]$auth.hostSession)
 $request=[P1Wire]::Request('TEST_USER_FINISH',[string]$auth.nonce,[string]$auth.hostGeneration,0,$null,[long]1)
 $res=[P1Wire]::Decode([P1Wire]::Call([string]$auth.pipe,$identity,$request,1200))
 Check ($res.type -eq 'SNAPSHOT') 'owned Host accepted cooperative GUI close and exit'
 Check ($hostProcess.WaitForExit(10000)) 'owned Host stopped cooperatively'
 $hostProcess.Dispose()

 # Marker, identity and destination are independently revalidated by both helpers.
 $testCases=@(
  [pscustomobject]@{Label='F2 wrong run proof';Field='RunProof';Value=([guid]::NewGuid().ToString('N'))},
  [pscustomobject]@{Label='F2 stale Host PID';Field='HostPID';Value=999999},
  [pscustomobject]@{Label='F2 stale Host birth ticks';Field='HostStartTicks';Value=1},
  [pscustomobject]@{Label='F2 wrong run identifier';Field='RunId';Value=([guid]::NewGuid().ToString('N'))}
 )
 foreach($tc in $testCases){
  try{
   $m=$originalJson.PSObject.Copy()
   $m.($tc.Field)=$tc.Value
   [IO.File]::WriteAllText($marker,($m|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($true)))
   $bad=CallCleanup 'Check-And-Cleanup.ps1'
   Check ($bad.Exit -ne 0) ($tc.Label+' cleanup refuses')
   Check ([IO.Directory]::Exists($root)) ($tc.Label+' fixture remains')
  }finally{[IO.File]::WriteAllBytes($marker,$original)}
 }
 # A forged marker+owner pair must not overcome the independently
 # Host-created, private rendezvous process birth evidence.
 $ownerFile=Join-Path $root 'p3-owner.json'
 $ownerBytes=[IO.File]::ReadAllBytes($ownerFile)
 try{
  $changedMarker=$originalJson.PSObject.Copy()
  $changedOwner=Get-Content -LiteralPath $ownerFile -Raw -Encoding UTF8|ConvertFrom-Json
  $wrongTicks=[long]$originalJson.HostStartTicks+1
  $changedMarker.HostStartTicks=$wrongTicks
  $changedOwner.HostStartTicks=$wrongTicks
  [IO.File]::WriteAllText($marker,($changedMarker|ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding($true)))
  [IO.File]::WriteAllText($ownerFile,($changedOwner|ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding($true)))
  $denied=CallCleanup 'Check-And-Cleanup.ps1'
  Check ($denied.Exit -ne 0 -and [IO.Directory]::Exists($root)) 'F2 forged matching marker/owner cannot override Host birth proof'
 }finally{
  [IO.File]::WriteAllBytes($marker,$original)
  [IO.File]::WriteAllBytes($ownerFile,$ownerBytes)
 }
 $foreign=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P3-'+[guid]::NewGuid().ToString('N'))
 [void](New-Item -ItemType Directory -Path $foreign -ErrorAction Stop)
 $sentinel=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P3A-outside-'+[guid]::NewGuid().ToString('N')+'.txt')
 [IO.File]::WriteAllText($sentinel,'DO-NOT-CHANGE-P3A')
 $sentinelHash=(Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
 [IO.File]::WriteAllText((Join-Path $foreign 'sentinel.txt'),'FOREIGN')
 $bad=CallCleanup 'Remove-Fixture.ps1' $foreign
 Check ($bad.Exit -ne 0 -and [IO.File]::Exists((Join-Path $foreign 'sentinel.txt'))) 'F2 standalone refuses unrelated direct GUID folder'
 $nested=Join-Path $root ('RDC-P3-'+[guid]::NewGuid().ToString('N'))
 [void](New-Item -ItemType Directory -Path $nested -ErrorAction Stop)
 try{
  $bad=CallCleanup 'Remove-Fixture.ps1' $nested
  Check ($bad.Exit -ne 0 -and [IO.Directory]::Exists($nested)) 'F2 standalone refuses nested GUID folder'
  $bad=CallCleanup 'Check-And-Cleanup.ps1'
  Check ($bad.Exit -ne 0 -and [IO.Directory]::Exists($root)) 'F2 cleanup refuses unexpected nested entry'
 }finally{if([IO.Directory]::Exists($nested)){[IO.Directory]::Delete($nested,$false)}}
 $m=$originalJson.PSObject.Copy()
 $m.Root=$foreign
 try{
  [IO.File]::WriteAllText($marker,($m|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($true)))
  $bad=CallCleanup 'Check-And-Cleanup.ps1'
  Check ($bad.Exit -ne 0 -and [IO.Directory]::Exists($root) -and [IO.Directory]::Exists($foreign)) 'F2 marker substitution cannot delete unrelated directory'
 }finally{[IO.File]::WriteAllBytes($marker,$original)}
 Check ((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -ceq $sentinelHash) 'outside sentinel preserved byte-for-byte'
 $static=Join-Path $root 'Host.ps1'
 $originalStatic=[IO.File]::ReadAllBytes($static)
 try{
  [IO.File]::AppendAllText($static,[Environment]::NewLine+'# P3A owned tamper probe')
  $bad=CallCleanup 'Check-And-Cleanup.ps1'
  Check ($bad.Exit -ne 0) 'F2 cleanup refuses modified static fixture file'
  Check ([IO.Directory]::Exists($root)) 'F2 modified fixture is not deleted'
 }finally{[IO.File]::WriteAllBytes($static,$originalStatic)}
 $clean=CallCleanup 'Check-And-Cleanup.ps1'
 Check ($clean.Exit -eq 0) 'positive complete owner cleanup exits zero'
 Check (-not [IO.Directory]::Exists($root) -and -not [IO.File]::Exists($marker)) 'own fixture and marker absent after cleanup'
 $noMarker=CallCleanup 'Check-And-Cleanup.ps1'
 Check ($noMarker.Exit -ne 0) 'F1 missing provenance marker cannot report cleanup success'
 Check (@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object{
   ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $root 'Host.ps1')+'"') -or
   ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $root 'Gui.ps1')+'"')
 }).Count -eq 0) 'zero exact-run Host/GUI process survivors'
}catch{
 $fail++
 Write-Output ('FAIL '+$_.Exception.Message)
}finally{
 if($foreign -and [IO.Directory]::Exists($foreign)){
  # Remove ONLY a newly created and verified test foreign sentinel fixture.
  $f=Join-Path $foreign 'sentinel.txt'
  if([IO.File]::Exists($f) -and ([IO.File]::ReadAllText($f) -ceq 'FOREIGN')){
   [IO.File]::Delete($f)
   [IO.Directory]::Delete($foreign,$false)
  }else{Write-Output ('NOT CLEAN test-created foreign folder: '+$foreign);$fail++}
 }
 if($sentinel -and [IO.File]::Exists($sentinel)){
  if(([IO.File]::ReadAllText($sentinel) -ceq 'DO-NOT-CHANGE-P3A')){[IO.File]::Delete($sentinel)}
  else{Write-Output ('NOT CLEAN outside sentinel: '+$sentinel);$fail++}
 }
 if($run -and [IO.Directory]::Exists($run.Root)){Write-Output ('NOT CLEAN own run fixture preserved: '+$run.Root);$fail++}
}
Write-Output ('P3A_CLEANUP_TOTAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
