# G7 pure injected owner-tree contract. No new process, no real Remote.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $project 'Source\RdcOwnerProcess.cs'))
$fake=@'
namespace RdcRelay.Owner {
 public sealed class G7FakeTree : IRemoteTreeObservation, IRemoteCooperativeStop {
  public System.Collections.Generic.Dictionary<int,ProcessEvidence> Now =
   new System.Collections.Generic.Dictionary<int,ProcessEvidence>();
  public System.Collections.Generic.List<int> Order =
   new System.Collections.Generic.List<int>();
  public bool UnrecordedChild, DenyRequest, DenyWait, SurviveAck, LateHostChild;
  public ProcessEvidence Read(int pid) {
   ProcessEvidence e;
   return Now.TryGetValue(pid, out e) ? e : null;
  }
  public int[] Children(int parent) {
   System.Collections.Generic.List<int> ids = new System.Collections.Generic.List<int>();
   foreach(ProcessEvidence e in Now.Values) if(e.ParentPid == parent) ids.Add(e.Pid);
   if(UnrecordedChild && parent == 502) ids.Add(599);
   return ids.ToArray();
  }
  public bool Request(ProcessEvidence e) {
   Order.Add(e.Pid);
   if(LateHostChild && e.Pid == 502) {
    Now.Add(504,new ProcessEvidence(504,10004,8,501,
     @"C:\G7FakeIsolatedOwner\bin\foreign.exe",@"C:\G7FakeIsolatedOwner",
     "d36d7b0562224280a911ee14ee342212",Ownership.Adopted));
   }
   return !DenyRequest;
  }
  public bool AwaitExit(ProcessEvidence e,int limit) {
   if(limit < 1 || limit > 5000 || DenyWait) return false;
   if(!SurviveAck) Now.Remove(e.Pid);
   return true;
  }
 }
}
'@
Add-Type -TypeDefinition ($source+[Environment]::NewLine+$fake) -ReferencedAssemblies @('System.Core.dll','System.dll') -ErrorAction Stop
$pass=0;$fail=0
function Check([bool]$condition,[string]$name){
 if($condition){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$epoch='d36d7b0562224280a911ee14ee342212'
$base='C:\G7FakeIsolatedOwner'
function Ev([int]$processId,[long]$birth,[int]$parent,[string]$file,[string]$kind='Owned'){
 return [RdcRelay.Owner.ProcessEvidence]::new($processId,$birth,8,$parent,
  (Join-Path $base ('bin\'+$file)),$base,$epoch,
  [Enum]::Parse([RdcRelay.Owner.Ownership],$kind))
}
$owner=Ev 501 10001 499 'host.exe'
$root=Ev 502 10002 501 'fake-remote.exe'
$leaf=Ev 503 10003 502 'dummy-child.exe'
function NewTree {
 $t=[RdcRelay.Owner.G7FakeTree]::new()
 $t.Now.Add(501,$owner);$t.Now.Add(502,$root);$t.Now.Add(503,$leaf)
 return $t
}
function Exec([RdcRelay.Owner.G7FakeTree]$tree,[object[]]$items,
 [bool]$fake=$true,[bool]$approval=$true,[bool]$fullExit=$false,[int]$timeout=5000) {
 $arr=[RdcRelay.Owner.ProcessEvidence[]]$items
 return [RdcRelay.Owner.RemoteTreeCooperativeExit]::ExecuteInjected(
  $owner,$arr,$tree,$tree,$fake,$approval,$fullExit,$timeout)
}
try {
 $t=NewTree;$r=Exec $t @($root,$leaf)
 Check ($r.IsClean -and $r.Requested -eq 2 -and ($t.Order -join ',') -ceq '503,502' -and
  $t.Now.ContainsKey(501)) 'G7 injected children then parent, Host persists'
 $t=NewTree;$r=Exec $t @($root,$leaf) $true $true $true
 Check ($r.IsClean -and $r.Requested -eq 3 -and ($t.Order -join ',') -ceq '503,502,501' -and
  $t.Now.Count -eq 0) 'G7 full injected Exit child then Remote then Host'
 $t=NewTree;$t.Now.Add(504,(Ev 504 10004 501 'foreign.exe' 'Adopted'))
 $r=Exec $t @($root,$leaf) $true $true $true
 Check ($r.Code.ToString() -ceq 'RefuseUnexpectedChild' -and -not $r.IsClean -and
  $t.Order.Count -eq 0 -and $t.Now.ContainsKey(504)) 'G7-R1 unknown direct Host child refuses full Exit before request'
 $t=NewTree;$t.LateHostChild=$true
 $r=Exec $t @($root,$leaf) $true $true $true
 Check ($r.Code.ToString() -ceq 'RefuseUnexpectedChild' -and -not $r.IsClean -and
  ($t.Order -join ',') -ceq '503,502' -and $t.Now.ContainsKey(501) -and
  $t.Now.ContainsKey(504)) 'G7-R1 late adopted Host child refuses Host request after Remote exit'
 $t=NewTree;$r=Exec $t @($root,$leaf) $false
 Check ($r.Code.ToString() -ceq 'RefuseMode' -and $t.Order.Count -eq 0) 'G7 production mode blocked'
 $t=NewTree;$r=Exec $t @($root,$leaf) $true $false
 Check ($r.Code.ToString() -ceq 'RefuseMode' -and $t.Order.Count -eq 0) 'G7 unapproved mode blocked'
 $t=NewTree;$r=Exec $t @((Ev 502 10002 501 'fake-remote.exe' 'Adopted'),$leaf)
 Check ($r.Code.ToString() -ceq 'RefuseOwnership' -and $t.Order.Count -eq 0) 'G7 Adopted never stopped'
 $t=NewTree;$r=Exec $t @((Ev 502 10002 501 'fake-remote.exe' 'Unknown'),$leaf)
 Check ($r.Code.ToString() -ceq 'RefuseOwnership' -and $t.Order.Count -eq 0) 'G7 Unknown never stopped'
 foreach($scenario in @(
  @{Name='PID birth reuse';Replacement=(Ev 502 99999 501 'fake-remote.exe')},
  @{Name='session mismatch';Replacement=[RdcRelay.Owner.ProcessEvidence]::new(502,10002,9,501,(Join-Path $base 'bin\fake-remote.exe'),$base,$epoch,[RdcRelay.Owner.Ownership]::Owned)},
  @{Name='wrong parent';Replacement=(Ev 502 10002 900 'fake-remote.exe')},
  @{Name='wrong executable';Replacement=(Ev 502 10002 501 'other.exe')},
  @{Name='wrong run epoch';Replacement=[RdcRelay.Owner.ProcessEvidence]::new(502,10002,8,501,(Join-Path $base 'bin\fake-remote.exe'),$base,'00000000000000000000000000000000',[RdcRelay.Owner.Ownership]::Owned)}
 )){
  $t=NewTree;$t.Now[502]=$scenario.Replacement
  $r=Exec $t @($root,$leaf)
  Check (-not $r.IsClean -and $t.Order.Count -eq 0) ('G7 pin refusal '+$scenario.Name)
 }
 $t=NewTree;$t.UnrecordedChild=$true;$r=Exec $t @($root,$leaf)
 Check ($r.Code.ToString() -ceq 'RefuseUnexpectedChild' -and $t.Order.Count -eq 0) 'G7 unrecorded descendant prevents stop'
 $t=NewTree;$t.DenyRequest=$true;$r=Exec $t @($root,$leaf)
 Check ($r.Code.ToString() -ceq 'RefuseTransport' -and -not $r.IsClean -and $r.Requested -eq 0) 'G7 cooperative request refusal not clean'
 $t=NewTree;$t.DenyWait=$true;$r=Exec $t @($root,$leaf)
 Check ($r.Code.ToString() -ceq 'Timeout' -and -not $r.IsClean -and $r.Requested -eq 1) 'G7 timeout leaves pending process, no force'
 $t=NewTree;$t.SurviveAck=$true;$r=Exec $t @($root,$leaf)
 Check ($r.Code.ToString() -ceq 'RefuseSurvivor' -and -not $r.IsClean -and $t.Now.ContainsKey(503)) 'G7 acknowledged-but-surviving child not clean'
 $t=NewTree;$r=Exec $t @($root,$leaf) $true $true $false 61000
 Check ($r.Code.ToString() -ceq 'RefuseMode' -and $t.Order.Count -eq 0) 'G7 deadline upper bound refuses'
}catch{
 $script:fail++;Write-Output ('FAIL G7_CONTRACT_EXCEPTION '+$_.Exception.Message)
}
Write-Output ('RC1_G7_TREE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
