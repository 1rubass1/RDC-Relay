# G7 negative controls: file-only fixtures; NO Host/GUI/Remote OS tree.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Rc1OsFixtureProof.ps1')
$project=Split-Path -Parent $PSScriptRoot
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Refuses([scriptblock]$body){
 try{& $body|Out-Null;return $false}catch{Write-Host ('TRACE_EXPECTED_REFUSAL '+$_.Exception.Message);return $true}
}
$objects=New-Object 'System.Collections.Generic.List[object]'
try{
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,
  [Security.AccessControl.FileSystemRights]::FullControl,
  ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
  [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 foreach($variant in @('legitimate','lookalike')){
  $id=[Guid]::NewGuid().ToString('N');$p=Get-Rc1Paths $id
  if([IO.Directory]::Exists($p.Root) -or [IO.Directory]::Exists($p.Proof) -or
   [IO.File]::Exists($p.Sentinel)){throw 'TEST_GUID_COLLISION'}
  [void][IO.Directory]::CreateDirectory($p.Root,$acl)
  $src=Join-Path $p.Root 'Source'
  [void][IO.Directory]::CreateDirectory($src)
  [void][IO.Directory]::CreateDirectory((Join-Path $p.Root 'owner-state'))
  $hashes=@{};$orig=@{}
  foreach($name in $Rc1OsNames){
   $bytes=[Text.Encoding]::UTF8.GetBytes(('G7 TEST OWN FILE '+$id+' '+$name))
   $f=Join-Path $src $name
   [IO.File]::WriteAllBytes($f,$bytes);$orig[$name]=$bytes;$hashes[$name]=Get-Rc1Sha $bytes
  }
  $sentinel=[Text.Encoding]::UTF8.GetBytes(('G7 TEST OUTSIDE SENTINEL '+$id))
  [IO.File]::WriteAllBytes($p.Sentinel,$sentinel)
  $objects.Add(@{Id=$id;Paths=$p;Original=$orig;Sentinel=$sentinel;Variant=$variant})
  if($variant -ceq 'legitimate'){
   $creation=New-Rc1AtCreation $id $project $hashes $sentinel $acl
   $hostBorn=[long]$creation.CreatedUtcTicks+10000
   $native=[IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
   $records=@(
    @{Kind='Host';Pid=1987654;BirthUtcTicks=$hostBorn;SessionId=$creation.HarnessSession;
      ParentPid=$creation.HarnessPid;Exe=$native},
    @{Kind='Gui';Pid=1987655;BirthUtcTicks=($hostBorn+10000);SessionId=$creation.HarnessSession;
      ParentPid=1987654;Exe=$native}
   )
   New-Rc1AtExit $id $creation $records
   Check (-not (Refuses {Assert-Rc1MandatorySentinel $id $sentinel $creation})) 'G7-F1 positive exact sentinel'
   Check (-not (Refuses {Remove-Rc1AttestedFixture $id -ValidateOnly})) 'G7-F2 positive attested read-only preflight'
   [IO.File]::Delete($p.Sentinel)
   Check (Refuses {Assert-Rc1MandatorySentinel $id $sentinel $creation}) 'G7-F1 missing sentinel mandatory refusal'
   Check (Refuses {Remove-Rc1AttestedFixture $id}) 'G7-F1 missing sentinel prevents cleanup'
   Check ([IO.Directory]::Exists($p.Root)) 'G7-F1 refused cleanup retains exact test root'
   [IO.File]::WriteAllBytes($p.Sentinel,[Text.Encoding]::UTF8.GetBytes('changed'))
   Check (Refuses {Assert-Rc1MandatorySentinel $id $sentinel $creation}) 'G7-F1 modified sentinel mandatory refusal'
   Check ([IO.Directory]::Exists($p.Root)) 'G7-F1 changed sentinel does not delete root'
   [IO.File]::WriteAllBytes($p.Sentinel,$sentinel)
   $changed=Join-Path $src 'update.ps1'
   [IO.File]::WriteAllBytes($changed,[Text.Encoding]::UTF8.GetBytes('TAMPER'))
   Check (Refuses {Remove-Rc1AttestedFixture $id}) 'G7-F2 changed source hash refuses delete'
   Check ([IO.Directory]::Exists($p.Root) -and [IO.File]::Exists($changed)) 'G7-F2 changed source preserves all files'
   [IO.File]::WriteAllBytes($changed,$orig['update.ps1'])
   $record=Join-Path $p.Proof 'exit.json'
   $originalRecord=[IO.File]::ReadAllBytes($record)
   [IO.File]::WriteAllBytes($record,[Text.Encoding]::UTF8.GetBytes('{"bad":"epoch"}'))
   Check (Refuses {Remove-Rc1AttestedFixture $id}) 'G7-F2 mismatched provenance refuses delete'
   Check ([IO.Directory]::Exists($p.Root)) 'G7-F2 invalid provenance preserves root'
   [IO.File]::WriteAllBytes($record,$originalRecord)
   $unexpected=Join-Path $src 'unexpected.txt'
   [IO.File]::WriteAllBytes($unexpected,[byte[]]@(1,2,3))
   Check (Refuses {Remove-Rc1AttestedFixture $id}) 'G7-F2 unexpected entry refuses delete'
   [IO.File]::Delete($unexpected)
   Check (-not (Refuses {Remove-Rc1AttestedFixture $id -ValidateOnly})) 'G7-F2 restored fixture valid only read-only'
  }else{
   Check (Refuses {Remove-Rc1AttestedFixture $id}) 'G7-F2 GUID-lookalike without independent attestation refused'
   Check ([IO.Directory]::Exists($p.Root) -and [IO.File]::Exists($p.Sentinel)) 'G7-F2 forged fixture and sentinel remain unchanged after refusal'
  }
 }
}catch{
 $script:fail++;Write-Output ('FAIL G7_PROOF_TEST_EXCEPTION '+$_.Exception.Message)
}finally{
 # Test creates only these two fresh GUID roots; cleanup is NOT by attacker-
 # supplied RunIds or the product failed-fixture helper. Exact own bytes only.
 foreach($item in $objects){
  $p=$item.Paths
  try{
   Assert-Rc1NoReparse $p.Root
   Assert-Rc1NoReparse $p.Sentinel
   $src=Join-Path $p.Root 'Source'
   Assert-Rc1Names $p.Root @('Source','owner-state')
   Assert-Rc1Names $src $Rc1OsNames
   Assert-Rc1Names (Join-Path $p.Root 'owner-state') @()
   foreach($name in $Rc1OsNames){
    $f=Join-Path $src $name
    if((Get-Rc1Sha ([IO.File]::ReadAllBytes($f))) -cne (Get-Rc1Sha $item.Original[$name])){throw 'TEST_OWN_FILE_TAMPERED'}
   }
   if((Get-Rc1Sha ([IO.File]::ReadAllBytes($p.Sentinel))) -cne (Get-Rc1Sha $item.Sentinel)){
    throw 'TEST_OWN_SENTINEL_TAMPERED'
   }
   foreach($name in $Rc1OsNames){[IO.File]::Delete((Join-Path $src $name))}
   [IO.Directory]::Delete($src,$false)
   [IO.Directory]::Delete((Join-Path $p.Root 'owner-state'),$false)
   [IO.Directory]::Delete($p.Root,$false)
   [IO.File]::Delete($p.Sentinel)
   if([IO.Directory]::Exists($p.Proof)){
    Assert-Rc1Names $p.Proof @('creation.json','exit.json')
    [IO.File]::Delete((Join-Path $p.Proof 'creation.json'))
    [IO.File]::Delete((Join-Path $p.Proof 'exit.json'))
    [IO.Directory]::Delete($p.Proof,$false)
   }
   Check $true ('G7 exact own negative fixture teardown '+$item.Variant)
  }catch{
   $script:fail++;Write-Output ('NOT CLEAN G7 negative fixture '+$item.Id+' '+$_.Exception.Message)
  }
 }
}
Write-Output ('RC1_G7_PROOF_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
