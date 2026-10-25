# Shared G7 exact disposable RC1 fixture provenance and deletion.
# Threat model: accidental/foreign/stale selection. Same-logon malicious alteration
# of the user's own ACL-protected proof is NOT cryptographically prevented.
# No Remote, process kill, recursive deletion or historical TEMP cleanup.
$Rc1OsNames=@('remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerProcess.cs','rc1-candidate.json','RDCRelay.ico',
 'divider-caustic.ps','divider-caustic-detail.ps','divider-particles.ps',
 'divider-particles-core.ps','update-notice.ps1','update.ps1')
function Get-Rc1Paths([string]$runId) {
 if($runId -cnotmatch '^[a-f0-9]{32}$'){throw 'NOT_CLEAN_INVALID_RUN_ID'}
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
 return @{
  RunId=$runId;Temp=$temp;Root=(Join-Path $temp ('RDC-RC1-OS-'+$runId));
  Proof=(Join-Path $temp ('RDC-RC1-OS-PROOF-'+$runId));
  Sentinel=(Join-Path $temp ('RDC-RC1-OS-SENTINEL-'+$runId+'.txt'))
 }
}
function Assert-Rc1NoReparse([string]$path) {
 $cursor=[IO.Path]::GetFullPath($path)
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw ('NOT_CLEAN_REPARSE '+$cursor)
   }
  }
  $next=[IO.Path]::GetDirectoryName($cursor)
  if(-not $next -or $next -ceq $cursor){break}
  $cursor=$next
 }
}
function Assert-Rc1Names([string]$dir,[string[]]$expected) {
 if(-not [IO.Directory]::Exists($dir)){throw ('NOT_CLEAN_DIRECTORY_MISSING '+$dir)}
 $actual=@([IO.Directory]::GetFileSystemEntries($dir)|ForEach-Object{[IO.Path]::GetFileName($_)})
 if($actual.Count -ne $expected.Count){throw ('NOT_CLEAN_UNEXPECTED_ENTRY_COUNT '+$dir)}
 foreach($entry in $actual){if(-not ($expected -ccontains $entry)){throw ('NOT_CLEAN_UNKNOWN_ENTRY '+$entry)}}
}
function Get-Rc1Sha([byte[]]$bytes) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}
 finally{$sha.Dispose()}
}
function Write-Rc1NewJson([string]$path,[object]$value) {
 Assert-Rc1NoReparse (Split-Path -Parent $path)
 $json=ConvertTo-Json -InputObject $value -Depth 8 -Compress
 $bytes=[Text.Encoding]::UTF8.GetBytes($json)
 $fs=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}
 finally{$fs.Dispose()}
}
function New-Rc1AtCreation([string]$runId,[string]$project,[hashtable]$hashes,
 [byte[]]$sentinelBytes,[Security.AccessControl.DirectorySecurity]$acl) {
 $p=Get-Rc1Paths $runId
 foreach($path in @($p.Root,$p.Proof,$p.Sentinel)){Assert-Rc1NoReparse $path}
 if([IO.Directory]::Exists($p.Proof) -or [IO.File]::Exists($p.Proof)){throw 'NOT_CLEAN_PROOF_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($p.Proof,$acl)
 $exact=@{}
 foreach($name in $Rc1OsNames){
  if(-not $hashes.ContainsKey($name) -or [string]$hashes[$name] -cnotmatch '^[A-F0-9]{64}$'){
   throw ('NOT_CLEAN_SOURCE_SHA_MISSING '+$name)
  }
  $exact[$name]=[string]$hashes[$name]
 }
 if($hashes.Count -ne $Rc1OsNames.Count){throw 'NOT_CLEAN_SOURCE_LIST_NOT_EXACT'}
 $commit=(git -C $project rev-parse HEAD).Trim()
 if($LASTEXITCODE -ne 0 -or $commit -cnotmatch '^[0-9a-f]{40}$'){throw 'NOT_CLEAN_GIT_COMMIT_UNVERIFIED'}
 $epoch=[Guid]::NewGuid().ToString('N')
 $proof=@{
  Schema=1;RunId=$runId;Epoch=$epoch;Root=$p.Root;Sentinel=$p.Sentinel;
  SentinelHash=(Get-Rc1Sha $sentinelBytes);SourceCommit=$commit;Files=$exact;
  CreatedUtcTicks=[DateTime]::UtcNow.Ticks;HarnessPid=$PID;
  HarnessBirthUtcTicks=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
  HarnessSession=[Diagnostics.Process]::GetCurrentProcess().SessionId;
  UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 }
 Write-Rc1NewJson (Join-Path $p.Proof 'creation.json') $proof
 return $proof
}
function New-Rc1AtExit([string]$runId,[object]$creation,[object[]]$processRecords) {
 $p=Get-Rc1Paths $runId
 if($processRecords.Count -lt 2){throw 'NOT_CLEAN_MISSING_OS_PROCESS_PROVENANCE'}
 $end=@{
  Schema=1;RunId=$runId;Epoch=[string]$creation.Epoch;
  CapturedUtcTicks=[DateTime]::UtcNow.Ticks;
  Processes=@($processRecords)
 }
 Write-Rc1NewJson (Join-Path $p.Proof 'exit.json') $end
}
function Read-Rc1Attestation([string]$runId) {
 $p=Get-Rc1Paths $runId
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($p.Root),$p.Temp,[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals([IO.Path]::GetDirectoryName($p.Proof),$p.Temp,[StringComparison]::OrdinalIgnoreCase)){
  throw 'NOT_CLEAN_NOT_DIRECT_TEMP_CHILD'
 }
 foreach($item in @($p.Root,$p.Proof,$p.Sentinel)){Assert-Rc1NoReparse $item}
 # Additional progress files are accepted only after their complete hash-bound
 # chain and exact names are validated by Get-Rc1CleanupProgress.
 if(-not [IO.File]::Exists((Join-Path $p.Proof 'creation.json')) -or
    -not [IO.File]::Exists((Join-Path $p.Proof 'exit.json'))){
  throw 'NOT_CLEAN_BASE_PROOF_MISSING'
 }
 foreach($name in @('creation.json','exit.json')){
  Assert-Rc1NoReparse (Join-Path $p.Proof $name)
 }
 $birthPath=Join-Path $p.Proof 'creation.json';$endPath=Join-Path $p.Proof 'exit.json'
 $creation=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($birthPath,[Text.Encoding]::UTF8))
 $end=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($endPath,[Text.Encoding]::UTF8))
 if($creation.Schema -ne 1 -or $end.Schema -ne 1 -or $creation.RunId -cne $runId -or
    $end.RunId -cne $runId -or [string]$creation.Epoch -cnotmatch '^[a-f0-9]{32}$' -or
    $end.Epoch -cne $creation.Epoch -or $creation.SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
    $creation.UserSid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
    $creation.Root -cne $p.Root -or $creation.Sentinel -cne $p.Sentinel -or
    [long]$creation.CreatedUtcTicks -le 0 -or
    [long]$creation.HarnessBirthUtcTicks -gt [long]$creation.CreatedUtcTicks -or
    [int]$creation.HarnessPid -le 0 -or
    [long]$end.CapturedUtcTicks -lt [long]$creation.CreatedUtcTicks){
  throw 'NOT_CLEAN_CREATION_EXIT_BINDING'
 }
 $files=@($creation.Files.PSObject.Properties)
 if($files.Count -ne $Rc1OsNames.Count){throw 'NOT_CLEAN_FILE_PROOF_COUNT'}
 foreach($entry in $files){
  if(-not ($Rc1OsNames -ccontains $entry.Name) -or
   [string]$entry.Value -cnotmatch '^[A-F0-9]{64}$'){throw 'NOT_CLEAN_FILE_PROOF_NAME_OR_SHA'}
 }
 if(@($end.Processes).Count -lt 2){throw 'NOT_CLEAN_PROCESS_PROOF_MISSING'}
 $hostRecords=@($end.Processes|Where-Object{[string]$_.Kind -ceq 'Host'})
 $guis=@($end.Processes|Where-Object{[string]$_.Kind -ceq 'Gui'})
 if($hostRecords.Count -ne 1 -or $guis.Count -lt 1 -or
    $guis.Count -ne (@($end.Processes).Count-1)){throw 'NOT_CLEAN_PROCESS_TYPES'}
 $hp=$hostRecords[0]
 $native=[IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
 if([int]$hp.Pid -le 0 -or [long]$hp.BirthUtcTicks -lt [long]$creation.CreatedUtcTicks -or
    [int]$hp.ParentPid -ne [int]$creation.HarnessPid -or
    [int]$hp.SessionId -ne [int]$creation.HarnessSession -or
    -not [string]::Equals([string]$hp.Exe,$native,[StringComparison]::OrdinalIgnoreCase)){
   throw 'NOT_CLEAN_HOST_PROVENANCE'
 }
 $seen=New-Object 'System.Collections.Generic.HashSet[int]'
 [void]$seen.Add([int]$hp.Pid)
 foreach($g in $guis){
  if([int]$g.Pid -le 0 -or -not $seen.Add([int]$g.Pid) -or
     [long]$g.BirthUtcTicks -lt [long]$hp.BirthUtcTicks -or
     [int]$g.ParentPid -ne [int]$hp.Pid -or
     [int]$g.SessionId -ne [int]$hp.SessionId -or
     -not [string]::Equals([string]$g.Exe,$native,[StringComparison]::OrdinalIgnoreCase)){
    throw 'NOT_CLEAN_GUI_PROVENANCE'
  }
 }
 return @{Paths=$p;Creation=$creation;Exit=$end;
  CreationSha=(Get-Rc1Sha ([IO.File]::ReadAllBytes($birthPath)));
  ExitSha=(Get-Rc1Sha ([IO.File]::ReadAllBytes($endPath)))}
}
function Assert-Rc1MandatorySentinel([string]$runId,[byte[]]$expected,[object]$creation) {
 $p=Get-Rc1Paths $runId
 Assert-Rc1NoReparse $p.Sentinel
 if(-not [IO.File]::Exists($p.Sentinel)){throw 'OS_SENTINEL_MISSING'}
 $observed=[IO.File]::ReadAllBytes($p.Sentinel)
 if($observed.Length -ne $expected.Length){throw 'OS_SENTINEL_CHANGED'}
 for($j=0;$j -lt $observed.Length;$j++){
  if($observed[$j] -ne $expected[$j]){throw 'OS_SENTINEL_CHANGED'}
 }
 if(-not $creation -or $creation.RunId -cne $runId -or
    $creation.Root -cne $p.Root -or $creation.Sentinel -cne $p.Sentinel -or
    $creation.SentinelHash -cne (Get-Rc1Sha $observed)){
  throw 'OS_SENTINEL_RUN_PROVENANCE'
 }
}
# Resume journal: exact CreateNew intent-before-delete / done-after-delete pairs.
# A deleted file without matching intent remains NOT CLEAN; never retrofit old
# partial roots. Each fresh invocation revalidates every proof and source hash.
function Get-Rc1CleanupProgress([hashtable]$proof) {
 $p=$proof.Paths;$c=$proof.Creation
 Assert-Rc1NoReparse $p.Proof
 $allowed=New-Object 'System.Collections.Generic.List[string]'
 $allowed.Add('creation.json');$allowed.Add('exit.json')
 $completed=0;$pending=-1;$previous='START'
 for($index=0;$index -lt $Rc1OsNames.Count;$index++){
  $name=[string]$Rc1OsNames[$index]
  $intentName=('intent-{0:D2}.json' -f ($index+1))
  $doneName=('done-{0:D2}.json' -f ($index+1))
  $intent=Join-Path $p.Proof $intentName
  $done=Join-Path $p.Proof $doneName
  if(-not [IO.File]::Exists($intent)){
   if([IO.File]::Exists($done)){throw 'NOT_CLEAN_DONE_WITHOUT_INTENT'}
   break
  }
  Assert-Rc1NoReparse $intent
  $allowed.Add($intentName)
  $bytes=[IO.File]::ReadAllBytes($intent)
  $item=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($bytes))
  $hash=Get-Rc1Sha $bytes
  if($item.RunId -cne $p.RunId -or $item.Epoch -cne $c.Epoch -or
     $item.Index -ne $index -or $item.Name -cne $name -or
     $item.FileHash -cne [string]$c.Files.$name -or
     $item.PrevDoneHash -cne $previous){
    throw ('NOT_CLEAN_INTENT_BINDING_'+$index)
  }
  if(-not [IO.File]::Exists($done)){$pending=$index;break}
  Assert-Rc1NoReparse $done
  $allowed.Add($doneName)
  $doneBytes=[IO.File]::ReadAllBytes($done)
  $receipt=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($doneBytes))
  if($receipt.RunId -cne $p.RunId -or $receipt.Epoch -cne $c.Epoch -or
     $receipt.Index -ne $index -or $receipt.Name -cne $name -or
     $receipt.IntentSha -cne $hash){
    throw ('NOT_CLEAN_DONE_BINDING_'+$index)
  }
  $previous=Get-Rc1Sha $doneBytes
  $completed++
 }
 Assert-Rc1Names $p.Proof ($allowed.ToArray())
 $remaining=New-Object 'System.Collections.Generic.List[string]'
 for($i=$completed;$i -lt $Rc1OsNames.Count;$i++){
  $f=Join-Path (Join-Path $p.Root 'Source') $Rc1OsNames[$i]
  if($i -eq $pending -and -not [IO.File]::Exists($f)){
   continue # interrupted immediately AFTER exact deletion, BEFORE done record
  }
  $remaining.Add([string]$Rc1OsNames[$i])
 }
 return @{Completed=$completed;Pending=$pending;Previous=$previous;
  Remaining=$remaining.ToArray();JournalNames=$allowed.ToArray()}
}
function Assert-Rc1PidOverlap([int]$recordedPid,[long]$recordedBirth,
 [int]$observedPid,[long]$observedBirth,[string]$commandLine,[string]$root) {
 if($recordedPid -ne $observedPid){return}
 if($commandLine -and $commandLine.IndexOf($root,[StringComparison]::OrdinalIgnoreCase) -ge 0){
  throw ('NOT_CLEAN_PROCESS_REFERENCES_ROOT '+$observedPid)
 }
 if($recordedBirth -le 0 -or $observedBirth -le 0){
  throw ('NOT_CLEAN_PID_BIRTH_UNVERIFIED '+$observedPid)
 }
 if($recordedBirth -eq $observedBirth){
  throw ('NOT_CLEAN_VERIFIED_TEST_PROCESS_STILL_ALIVE '+$observedPid)
 }
 # Reused PID with OS-confirmed *different* birth is a separate process.
 # Treat it as foreign: do not send any signal, do not call Stop-Process.
}
function Assert-Rc1CleanupRound([hashtable]$proof,[string[]]$remaining){
 $p=$proof.Paths;$c=$proof.Creation
 foreach($item in @($p.Root,$p.Proof,$p.Sentinel)){Assert-Rc1NoReparse $item}
 foreach($name in @('creation.json','exit.json')){
  $f=Join-Path $p.Proof $name;Assert-Rc1NoReparse $f
  if(-not [IO.File]::Exists($f)){throw 'NOT_CLEAN_PROOF_DISAPPEARED'}
  $expected=if($name -ceq 'creation.json'){$proof.CreationSha}else{$proof.ExitSha}
  if((Get-Rc1Sha ([IO.File]::ReadAllBytes($f))) -cne $expected){throw 'NOT_CLEAN_PROOF_CHANGED'}
 }
 if(-not [IO.File]::Exists($p.Sentinel) -or
   (Get-Rc1Sha ([IO.File]::ReadAllBytes($p.Sentinel))) -cne [string]$c.SentinelHash){
   throw 'NOT_CLEAN_SENTINEL_MISSING_CHANGED_UNREADABLE'
 }
 Assert-Rc1Names $p.Root @('Source','owner-state')
 $src=Join-Path $p.Root 'Source';$state=Join-Path $p.Root 'owner-state'
 Assert-Rc1NoReparse $src;Assert-Rc1NoReparse $state
 Assert-Rc1Names $state @()
 Assert-Rc1Names $src $remaining
 foreach($name in $remaining){
  $f=Join-Path $src $name
  Assert-Rc1NoReparse $f
  if(-not [IO.File]::Exists($f) -or
   (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -cne [string]$c.Files.$name){
   throw ('NOT_CLEAN_SOURCE_HASH_CHANGED '+$name)
  }
 }
 # Read-only OS process inventory each time before any destructive boundary.
 $all=@(Get-CimInstance Win32_Process -ErrorAction Stop)
 foreach($row in $all){
  if($row.CommandLine -and $row.CommandLine.IndexOf($p.Root,[StringComparison]::OrdinalIgnoreCase) -ge 0){
   throw ('NOT_CLEAN_PROCESS_REFERENCES_ROOT '+$row.ProcessId)
  }
  foreach($known in $proof.Exit.Processes){
   if([int]$row.ProcessId -ne [int]$known.Pid){continue}
   # A PID alone does NOT confer ownership. A different OS birth belongs
   # to a distinct unrelated process and must never be killed or controlled.
   # If the enumerated PID disappeared, corroborate with a fresh CIM query.
   try{
    $running=[Diagnostics.Process]::GetProcessById([int]$row.ProcessId)
    $freshBorn=$running.StartTime.ToUniversalTime().Ticks
    $running.Dispose()
   }catch{
    $again=Get-CimInstance Win32_Process -Filter ('ProcessId='+$row.ProcessId) -ErrorAction Stop
    if(-not $again){continue}
    throw ('NOT_CLEAN_PID_BIRTH_UNREADABLE '+$row.ProcessId)
   }
   Assert-Rc1PidOverlap ([int]$known.Pid) ([long]$known.BirthUtcTicks) ([int]$row.ProcessId) $freshBorn ([string]$row.CommandLine) $p.Root
   # Verified DIFFERENT birth: unrelated process is left strictly untouched.
  }
 }
}
function Remove-Rc1AttestedFixture([string]$runId,[switch]$ValidateOnly,
 [ValidateRange(-1,16)][int]$InjectFailureAfterDeleted=-1){
 $proof=Read-Rc1Attestation $runId
 $progress=Get-Rc1CleanupProgress $proof
 Assert-Rc1CleanupRound $proof $progress.Remaining
 if($ValidateOnly){
  Write-Output ('PASS VERIFIED_ATTESTED_ONLY '+$runId+
   ' COMPLETED='+$progress.Completed+' PENDING='+$progress.Pending)
  return
 }
 $src=Join-Path $proof.Paths.Root 'Source'
 $iterations=0
 while($true){
  if($iterations++ -gt 40){throw 'NOT_CLEAN_JOURNAL_PROGRESS_LIMIT'}
  $progress=Get-Rc1CleanupProgress $proof
  Assert-Rc1CleanupRound $proof $progress.Remaining
  if($progress.Completed -eq $Rc1OsNames.Count -and $progress.Pending -eq -1){break}
  if($progress.Pending -eq -1){
   $index=$progress.Completed
   $name=[string]$Rc1OsNames[$index]
   $intentName=('intent-{0:D2}.json' -f ($index+1))
   Write-Rc1NewJson (Join-Path $proof.Paths.Proof $intentName) @{
    RunId=$runId;Epoch=[string]$proof.Creation.Epoch;Index=$index;
    Name=$name;FileHash=[string]$proof.Creation.Files.$name;
    PrevDoneHash=$progress.Previous
   }
   continue
  }
  $index=$progress.Pending
  $name=[string]$Rc1OsNames[$index]
  $file=Join-Path $src $name
  Assert-Rc1NoReparse $file
  if([IO.File]::Exists($file)){
   if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne
     [string]$proof.Creation.Files.$name){throw 'NOT_CLEAN_SOURCE_CHANGED_PREDELETE'}
   # The already-created hash-bound intent is durable BEFORE this delete.
   [IO.File]::Delete($file)
   if($InjectFailureAfterDeleted -eq ($index+1)){
    throw ('G7_INJECTED_INTERRUPTION_AFTER_DELETE_'+($index+1))
   }
  }
  # On resume, a missing file is permitted ONLY with its exact next intent.
  $intentName=('intent-{0:D2}.json' -f ($index+1))
  $intentPath=Join-Path $proof.Paths.Proof $intentName
  Assert-Rc1NoReparse $intentPath
  $intentSha=Get-Rc1Sha ([IO.File]::ReadAllBytes($intentPath))
  $doneName=('done-{0:D2}.json' -f ($index+1))
  Write-Rc1NewJson (Join-Path $proof.Paths.Proof $doneName) @{
   RunId=$runId;Epoch=[string]$proof.Creation.Epoch;
   Index=$index;Name=$name;IntentSha=$intentSha
  }
 }
 $progress=Get-Rc1CleanupProgress $proof
 Assert-Rc1CleanupRound $proof @()
 if($progress.Completed -ne $Rc1OsNames.Count -or $progress.Pending -ne -1){
  throw 'NOT_CLEAN_FINAL_JOURNAL_NOT_COMPLETE'
 }
 [IO.Directory]::Delete($src,$false)
 [IO.Directory]::Delete((Join-Path $proof.Paths.Root 'owner-state'),$false)
 if([IO.Directory]::GetFileSystemEntries($proof.Paths.Root).Length -ne 0){throw 'NOT_CLEAN_ROOT_NOT_EMPTY'}
 [IO.Directory]::Delete($proof.Paths.Root,$false)
 # Root has been removed; source deletion evidence remains in the protected
 # complete journal until after all proof bytes and sentinel are verified.
 Assert-Rc1NoReparse $proof.Paths.Sentinel
 Assert-Rc1NoReparse $proof.Paths.Proof
 if((Get-Rc1Sha ([IO.File]::ReadAllBytes($proof.Paths.Sentinel))) -cne
   [string]$proof.Creation.SentinelHash){throw 'NOT_CLEAN_SENTINEL_LAST_BOUNDARY'}
 $finalProgress=Get-Rc1CleanupProgress $proof
 if($finalProgress.Completed -ne $Rc1OsNames.Count -or $finalProgress.Pending -ne -1){
  throw 'NOT_CLEAN_FINAL_PROOF_PROGRESS_CHANGED'
 }
 if((Get-Rc1Sha ([IO.File]::ReadAllBytes((Join-Path $proof.Paths.Proof 'creation.json')))) -cne $proof.CreationSha -or
   (Get-Rc1Sha ([IO.File]::ReadAllBytes((Join-Path $proof.Paths.Proof 'exit.json')))) -cne $proof.ExitSha){
  throw 'NOT_CLEAN_FINAL_BASE_PROOF_CHANGED'
 }
 Assert-Rc1Names $proof.Paths.Proof $progress.JournalNames
 foreach($f in $progress.JournalNames){
  $path=Join-Path $proof.Paths.Proof $f
  Assert-Rc1NoReparse $path
  if(-not [IO.File]::Exists($path)){throw 'NOT_CLEAN_MISSING_PROOF_LAST_BOUNDARY'}
 }
 # Exact nonrecursive private proof teardown; an interruption leaves honest
 # NOT CLEAN evidence, never authorizes a guessed directory sweep.
 foreach($f in $progress.JournalNames){
  [IO.File]::Delete((Join-Path $proof.Paths.Proof $f))
 }
 [IO.Directory]::Delete($proof.Paths.Proof,$false)
 [IO.File]::Delete($proof.Paths.Sentinel)
 Write-Output ('PASS CLEANED_ATTESTED_ONLY '+$runId)
}
