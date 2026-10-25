# G7 OS-04..10/16/24 future standalone disposable dummy-Remote tree.
# DO NOT EXECUTE before a new explicit owner GO and independent harness pre-gate.
# No @wonderwhy-er process, account files, product Remote, kill or logout.
param([switch]$Execute,[switch]$OwnerApprovedDummyTree,
 [string]$IndependentPreGate='')
$ErrorActionPreference='Stop'
if(-not $Execute -or -not $OwnerApprovedDummyTree -or
 $IndependentPreGate -cne 'REV-006A-G7-DUMMY-OS-PREGATE-PASS'){
 Write-Output 'NOT CHECKED: NEW DUMMY REMOTE TREE REQUIRES OWNER GO + INDEPENDENT PRE-GATE'
 exit 42
}
. (Join-Path $PSScriptRoot 'Rc1OsFixtureProof.ps1')
$runId=[Guid]::NewGuid().ToString('N')
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
$root=Join-Path $temp ('RDC-RC1-DUMMY-'+$runId)
$sentinel=Join-Path $temp ('RDC-RC1-DUMMY-SENTINEL-'+$runId+'.txt')
$nonce=[Guid]::NewGuid().ToString('N')
$sentinelBytes=[Text.Encoding]::UTF8.GetBytes(('RDC G7 dummy outside sentinel '+$runId))
$original=@{}
$rootProc=$null;$child=$null;$safe=$false;$pass=0;$fail=0
function Check([bool]$ok,[string]$text){
 if($ok){$script:pass++;Write-Output ('PASS '+$text)}
 else{$script:fail++;Write-Output ('FAIL '+$text)}
}
function WaitReady([string]$name,[int]$seconds){
 $path=Join-Path $root ($name+'-ready.json')
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while($watch.Elapsed.TotalSeconds -lt $seconds){
  if([IO.File]::Exists($path)){
   $row=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
   $expectedRole='Child'
   if($name -eq 'root'){$expectedRole='Root'}
   if($row.runId -cne $runId -or $row.mode -cne $expectedRole){throw 'DUMMY_READY_WRONG_EPOCH'}
   return $row
  }
  Start-Sleep -Milliseconds 100
 }
 throw ('DUMMY_READY_TIMEOUT_'+$name)
}
function GetVerified([int]$processId,[int]$parent){
 $p=[Diagnostics.Process]::GetProcessById($processId)
 $row=Get-CimInstance Win32_Process -Filter ('ProcessId='+$processId) -ErrorAction Stop
 $expected=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if(-not $row -or [int]$row.ParentProcessId -ne $parent -or
  -not $row.CommandLine -or
  $row.CommandLine.IndexOf((Join-Path $root 'actor.ps1'),[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
  $row.CommandLine.IndexOf(('-Root "'+$root+'"'),[StringComparison]::OrdinalIgnoreCase) -lt 0 -or
  -not [string]::Equals([IO.Path]::GetFullPath($p.MainModule.FileName),
   [IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase) -or
  $p.SessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId -or
  $p.StartTime.ToUniversalTime().Ticks -le 0){throw 'DUMMY_OS_IDENTITY_UNCONFIRMED'}
 return $p
}
try{
 foreach($p in @($temp,$root,$sentinel)){Assert-Rc1NoReparse $p}
 if([IO.Directory]::Exists($root) -or [IO.File]::Exists($sentinel)){throw 'DUMMY_GUID_COLLISION'}
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
  [Security.Principal.WindowsIdentity]::GetCurrent().User,
  [Security.AccessControl.FileSystemRights]::FullControl,
  ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
  [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 [void][IO.Directory]::CreateDirectory($root,$acl)
 [IO.File]::WriteAllBytes($sentinel,$sentinelBytes)
 $actor=Join-Path $PSScriptRoot 'Rc1DummyRemoteActor.ps1'
 $staged=Join-Path $root 'actor.ps1'
 Assert-Rc1NoReparse $actor
 [IO.File]::Copy($actor,$staged,$false)
 $original['actor.ps1']=(Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash
 $cfgPath=Join-Path $root 'trial.json'
 $cfg=@{kind='RC1_G7_DUMMY_ONLY';runId=$runId;nonce=$nonce;root=$root}
 $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $cfg -Compress))
 $f=[IO.FileStream]::new($cfgPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 $original['trial.json']=(Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash
 $native=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$native;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.WorkingDirectory=$root
 $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
   $staged+'" -Mode Root -Root "'+$root+'"'
 $rootProc=[Diagnostics.Process]::Start($psi)
 if(-not $rootProc){throw 'DUMMY_START_NULL'}
 $rootProc=GetVerified $rootProc.Id $PID
 $h=WaitReady 'root' 10
 Check ($h.pid -eq $rootProc.Id -and $h.utcTicks -eq $rootProc.StartTime.ToUniversalTime().Ticks) 'DUMMY recorded owned root identity'
 if($fail){throw 'DUMMY_HOST_NOT_VERIFIED'}
 $c=WaitReady 'child' 10
 $child=GetVerified ([int]$c.pid) $rootProc.Id
 Check ($c.utcTicks -eq $child.StartTime.ToUniversalTime().Ticks) 'DUMMY OS observed child ancestry and birth'
 if($fail){throw 'DUMMY_CHILD_NOT_VERIFIED'}
 # Fresh read-only parent/child/process executable verification before signal.
 [void](GetVerified $child.Id $rootProc.Id)
 [void](GetVerified $rootProc.Id $PID)
 $stopChild=Join-Path $root 'stop-child.txt'
 [IO.File]::WriteAllBytes($stopChild,[Text.Encoding]::UTF8.GetBytes($nonce))
 Check ($child.WaitForExit(7000)) 'DUMMY child cooperatively exited without kill'
 if($fail){throw 'DUMMY_CHILD_SURVIVED'}
 [void](GetVerified $rootProc.Id $PID)
 $stopHost=Join-Path $root 'stop-root.txt'
 [IO.File]::WriteAllBytes($stopHost,[Text.Encoding]::UTF8.GetBytes($nonce))
 Check ($rootProc.WaitForExit(7000)) 'DUMMY root cooperatively exited after child'
 if($fail){throw 'DUMMY_HOST_SURVIVED'}
 $safe=$true
}catch{
 $script:fail++;Write-Output ('NOT CLEAN DUMMY_EXCEPTION '+$_.Exception.Message)
}finally{
 # Both actors have a 30 s internal self-exit; allow grace, never force.
 foreach($p in @($child,$rootProc)){
  if($p){try{if(-not $p.HasExited){[void]$p.WaitForExit(35000)}}catch{}}
 }
 try{
  $survivors=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{
   $_.CommandLine -and $_.CommandLine.IndexOf($root,[StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  Check ($survivors.Count -eq 0) 'DUMMY independent zero owned root commandline survivors'
  if($survivors.Count){$safe=$false}
 }catch{$script:fail++;$safe=$false;Write-Output 'NOT CLEAN DUMMY_INVENTORY_UNAVAILABLE'}
 try{
  Assert-Rc1NoReparse $sentinel
  if(-not [IO.File]::Exists($sentinel) -or
    (Get-Rc1Sha ([IO.File]::ReadAllBytes($sentinel))) -cne (Get-Rc1Sha $sentinelBytes)){
   throw 'DUMMY_SENTINEL_MISSING_OR_CHANGED'
  }
  Check $true 'DUMMY outside sentinel unchanged'
 }catch{$script:fail++;$safe=$false;Write-Output ('NOT CLEAN '+$_.Exception.Message)}
 if($fail){$safe=$false}
 if($safe){
  try{
   Assert-Rc1NoReparse $root
   $files=@('actor.ps1','trial.json','root-ready.json','child-ready.json','stop-child.txt','stop-root.txt')
   Assert-Rc1Names $root $files
   foreach($name in $files){
    $f=Join-Path $root $name
    Assert-Rc1NoReparse $f
    if(-not [IO.File]::Exists($f)){throw 'DUMMY_SOURCE_MISSING'}
    if($original.ContainsKey($name) -and (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -cne $original[$name]){
     throw 'DUMMY_STAGED_SOURCE_CHANGED'
    }
   }
   foreach($name in $files){
    Assert-Rc1NoReparse $root;Assert-Rc1NoReparse (Join-Path $root $name)
    [IO.File]::Delete((Join-Path $root $name))
   }
   [IO.Directory]::Delete($root,$false)
   [IO.File]::Delete($sentinel)
   Write-Output 'DUMMY_DISPOSABLE_CLEAN=TRUE'
  }catch{$script:fail++;Write-Output ('NOT CLEAN DUMMY_CLEANUP_REFUSED '+$_.Exception.Message)}
 }else{Write-Output ('NOT CLEAN DUMMY_PRESERVED_ROOT '+$root)}
 foreach($p in @($child,$rootProc)){if($p){$p.Dispose()}}
}
Write-Output ('RC1_DUMMY_TREE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0