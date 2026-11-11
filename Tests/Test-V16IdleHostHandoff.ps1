# Isolated cooperative event/mutex handoff; no real Host, GUI or Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$type=Add-Type -Path (Join-Path $repo 'Installer\Rc1ManualUpgrade.cs') -ReferencedAssemblies @('System.Management.dll') -PassThru |
 Where-Object Name -eq 'RdcRc1ManualUpgrade'|Select-Object -First 1
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$nameMethod=$type.GetMethod('OldHostMutexName',$flags)
$handoff=$type.GetMethod('TryIdleHostHandoff',$flags)
if(-not $nameMethod -or -not $handoff){throw 'HANDOFF_PRODUCT_METHOD_MISSING'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-IDLE-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$mutexName=[string]$nameMethod.Invoke($null,[object[]]@([string]$root))
$eventName=$mutexName.Replace('RdcRelayRC1Owner-','RdcRelayRC1IdleUpgrade-')
$pass=0;$fail=0;$job=$null;$client=$null
function Check([bool]$ok,[string]$label){if($ok){$script:pass++;Write-Output ('PASS '+$label)}else{$script:fail++;Write-Output ('FAIL '+$label)}}
try{
 $created=$false
 $client=New-Object Threading.Mutex($true,$mutexName,[ref]$created)
 Check $created 'disposable exact release mutex reserved'
 $r=[bool]$handoff.Invoke($null,[object[]]@([string]$root,$client.PSObject.BaseObject))
 Check (-not $r) 'missing old Host endpoint returns unsupported without terminating any process'
 $client.ReleaseMutex();$client.Dispose();$client=$null
 $job=Start-Job -ArgumentList $mutexName,$eventName -ScriptBlock {
  param($nm,$en)
  $made=$false;$madeSignal=$false
  $mx=New-Object Threading.Mutex($true,$nm,[ref]$made)
  $evt=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,$en,[ref]$madeSignal)
  try{Write-Output 'READY';if(-not $evt.WaitOne(12000)){throw 'NOT_SIGNALED'};Write-Output 'COOPERATIVE_EXIT'}
  finally{$mx.ReleaseMutex();$mx.Dispose();$evt.Dispose()}
 }
 $started=$false
 for($i=0;$i -lt 60;$i++){
  if([string]::Join(' ',@(Receive-Job $job -Keep -ErrorAction SilentlyContinue)) -match 'READY'){$started=$true;break}
  Start-Sleep -Milliseconds 100
 }
 Check $started 'disposable old Host analog announced ready'
 $created=$false
 $client=New-Object Threading.Mutex($false,$mutexName,[ref]$created)
 Check (-not $created) 'candidate opens exact previously owned mutex'
 $result=[bool]$handoff.Invoke($null,[object[]]@([string]$root,$client.PSObject.BaseObject))
 Check $result 'cooperative signal acknowledged by actual mutex release'
 if($result){$client.ReleaseMutex()}
 Wait-Job $job -Timeout 5|Out-Null
 $lines=@(Receive-Job $job -ErrorAction SilentlyContinue)
 Check ([string]::Join(' ',$lines) -match 'COOPERATIVE_EXIT') 'disposable old Host analog acknowledged without force kill'
}finally{
 if($client){$client.Dispose()}
 if($job){if($job.State -eq 'Running'){Stop-Job $job};Remove-Job $job -Force}
 if([IO.Directory]::Exists($root) -and [IO.Path]::GetFileName($root) -cmatch '^RDC-RC1-IDLE-[a-f0-9]{32}$'){
  [IO.Directory]::Delete($root,$false)
 }
}
Write-Output ('RC1_IDLE_HANDOFF_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
