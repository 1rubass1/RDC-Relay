# Production-source owner safety seam; fake records only, no real OS process queries.
param([switch]$InjectFailure)
$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\RdcOwnerProcess.cs'
$pass=0;$fail=0
function Check([bool]$ok,[string]$message){
 if($ok){$script:pass++;Write-Output ('PASS '+$message)}
 else{$script:fail++;Write-Output ('FAIL '+$message)}
}
try {
 Add-Type -Path $src -ErrorAction Stop
 $kind=[RdcRelay.Owner.Ownership]::Owned
 $runId=[guid]::NewGuid().ToString('N')
 $root='C:\Rdc-RC1-Local-Pilot'
 $exe=Join-Path $root 'remote-standin.exe'
 $a=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,$exe,$root,$runId,$kind)
 $b=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,$exe,$root,$runId,$kind)
 $eval=[RdcRelay.Owner.ProcessOwnership]
 Check ($eval::SameVerifiedProcess($a,$b)) 'owned exact PID/birth/session/parent/path/run match'
 Check ($eval::Evaluate($kind,$a,$b,$false,$true).ToString() -eq 'RefuseNoApproval') 'no owner OS trial GO fails closed'
 Check ($eval::Evaluate($kind,$a,$b,$true,$false).ToString() -eq 'RefuseNoApproval') 'no user confirmation fails closed'
 Check ($eval::Evaluate($kind,$a,$b,$true,$true).ToString() -eq 'EligibleForCooperativeStop') 'only verified+approved+confirmed is eligible (not executing)'
 Check ($eval::Evaluate([RdcRelay.Owner.Ownership]::Unknown,$a,$b,$true,$true).ToString() -eq 'RefuseUnknown') 'unknown process refused'
 Check ($eval::Evaluate([RdcRelay.Owner.Ownership]::Adopted,$a,$b,$true,$true).ToString() -eq 'RefuseAdopted') 'adopted process refused'
 $bad=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000001,8,2001,$exe,$root,$runId,$kind)
 Check (-not $eval::SameVerifiedProcess($a,$bad)) 'PID reuse with changed birth denied'
 $bad=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,9,2001,$exe,$root,$runId,$kind)
 Check (-not $eval::SameVerifiedProcess($a,$bad)) 'different Windows session denied'
 $bad=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2222,$exe,$root,$runId,$kind)
 Check (-not $eval::SameVerifiedProcess($a,$bad)) 'different launcher/parent denied'
 $bad=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,$exe,$root,[guid]::NewGuid().ToString('N'),$kind)
 Check (-not $eval::SameVerifiedProcess($a,$bad)) 'different owner epoch denied'
 $bad=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,'C:\Other\remote-standin.exe',$root,$runId,$kind)
 Check (-not $eval::SameVerifiedProcess($a,$bad)) 'different executable path denied'
 $bad=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,$exe,'C:\Other',$runId,$kind)
 Check (-not $eval::SameVerifiedProcess($a,$bad)) 'different install root denied'
 $invalid=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,$exe,$root,'BAD',$kind)
 Check (-not $eval::SameVerifiedProcess($invalid,$b)) 'invalid epoch denied'
 $outside=New-Object RdcRelay.Owner.ProcessEvidence(3001,639284000000000000,8,2001,'C:\Rdc-RC1-Local-Pilot-Other\remote.exe',$root,$runId,$kind)
 Check (-not $eval::SameVerifiedProcess($outside,$outside)) 'prefix-sibling executable denied'
 $blocked=$false
 try{$eval::StopNotImplemented()}catch{$blocked=$_.Exception.Message -match 'RC1_STOP_BLOCKED'}
 Check $blocked 'production StopNotImplemented refuses execution'
 $journal=New-Object RdcRelay.Owner.BoundedEventJournal(2)
 [void]$journal.Append('a');[void]$journal.Append('b');[void]$journal.Append('c')
 $at=[long]0;$list=$journal.Snapshot([ref]$at)
 Check ($at -eq 3 -and $list.Length -eq 2 -and $list[0] -eq 'b' -and $list[1] -eq 'c') 'bounded journal evicts oldest and reports revision'
 Check ($journal.Append(('Z'*2500)) -eq 4) 'long messages are safely bounded and sequence continues'
 if($InjectFailure){Check $false 'intentional failure must return nonzero'}
} catch {
 $fail++
 Write-Output ('FAIL runner exception '+$_.Exception.Message)
}
Write-Output ('V16_OWNER_CONTRACT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
