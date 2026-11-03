# Exact, one-time disposable U1 transaction negative controls; never touches
# actual installed RC1, legacy 1.5.18, backups, Remote or OS Host/GUI.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'Scripts\rc1-private-upgrade-transaction.ps1')
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-U1-'+[Guid]::NewGuid().ToString('N'))
function New-FixturePayload([string]$dir,[string]$tag){
 [void][IO.Directory]::CreateDirectory($dir)
 $rows=@()
 foreach($member in $script:Rc1UpgRequired){
  $file=Join-Path $dir ($member.Replace('/','\'))
  $parent=[IO.Path]::GetDirectoryName($file)
  if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
  $value=if($member -eq 'Source/rc1-candidate.json'){
   @{
    candidate='1.6.0 RC1';installable=$true;publishable=$false;
    autoUpdateEnabled=$false;observerMode='OBSERVED_READ_ONLY_RC1';
    remoteStopEnabled=$false;remoteLaunchEnabled=$false;accountMutationEnabled=$false
   }|ConvertTo-Json -Compress
  }else{('U1_DISPOSABLE_ONLY_'+$tag+'_'+$member)}
  [IO.File]::WriteAllText($file,[string]$value,(New-Object Text.UTF8Encoding($false)))
  $rows+=@{name=$member;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
 }
 $manifest=@{candidate='1.6.0 RC1';observerMode='OBSERVED_READ_ONLY_RC1';
  installable=$true;publishable=$false;files=$rows}|ConvertTo-Json -Depth 8
 [IO.File]::WriteAllText((Join-Path $dir 'owner-source-manifest.json'),$manifest,
  (New-Object Text.UTF8Encoding($false)))
 return (Assert-Rc1UpgPayload $dir)
}
try{
 [void][IO.Directory]::CreateDirectory($testRoot)
 [IO.File]::WriteAllText((Join-Path $testRoot 'u1-run-sentinel.txt'),
  [IO.Path]::GetFileName($testRoot),[Text.Encoding]::ASCII)
 for($i=1;$i -le 5;$i++){
  $folder=Join-Path $testRoot ('case-'+$i)
  [void][IO.Directory]::CreateDirectory($folder)
  $app=Join-Path $folder 'app'
  $backup=Join-Path $folder ('app-backup-'+[Guid]::NewGuid().ToString('N'))
  $oldSha=New-FixturePayload $backup 'old'
  $newSha=''
  if($i -gt 1){$newSha=New-FixturePayload $app 'new'}
  else{$newSha=('A'*64)}
  if($i -eq 1){
   $result=Invoke-Rc1UpgRecover $app $backup $oldSha $newSha $false
   Check ($result.Status -ceq 'RESTORED_VERIFIED_PREVIOUS_RC1') 'U1 Setup fail before app publish restores old'
   Check ((Assert-Rc1UpgPayload $app $oldSha) -ceq $oldSha -and
    (Assert-Rc1UpgPayload $backup $oldSha) -ceq $oldSha) 'U1 pre-Setup backup preserved and rechecked'
  }elseif($i -eq 2 -or $i -eq 3){
   $result=Invoke-Rc1UpgRecover $app $backup $oldSha $newSha $true
   Check ($result.Status -ceq 'RESTORED_VERIFIED_PREVIOUS_RC1' -and
    [IO.Directory]::Exists($result.FailedApp)) ('U1 '+$(if($i -eq 2){'Launcher failure'}else{'Host absent'})+' archives candidate')
   Check ((Assert-Rc1UpgPayload $app $oldSha) -ceq $oldSha -and
    (Assert-Rc1UpgPayload $backup $oldSha) -ceq $oldSha -and
    (Assert-Rc1UpgPayload $result.FailedApp $newSha) -ceq $newSha) 'U1 prior, backup, failed candidate separately hash-attested'
  }elseif($i -eq 4){
   # Unverifiable post-Setup bytes: never move, delete, or overwrite.
   [IO.File]::WriteAllText((Join-Path $app 'Source\remote-window.ps1'),
    'FOREIGN_REPLACED_BYTES',[Text.Encoding]::UTF8)
   $denied=$false;try{
    [void](Invoke-Rc1UpgRecover $app $backup $oldSha $newSha $true)
   }catch{$denied=$true}
   Check $denied 'U1 foreign/tampered new app fails closed'
   Check ([IO.File]::ReadAllText((Join-Path $app 'Source\remote-window.ps1')) -ceq
    'FOREIGN_REPLACED_BYTES' -and [IO.Directory]::Exists($backup)) 'U1 foreign bytes and previous backup untouched'
  }else{
   $denied=$false;try{
    [void](Invoke-Rc1UpgRecover $app $backup $oldSha $newSha $true @('synthetic-active-owned-Host'))
   }catch{$denied=$true}
   Check $denied 'U1 active new candidate refuses replacement'
   Check ([IO.Directory]::Exists($app) -and [IO.Directory]::Exists($backup) -and
    (Assert-Rc1UpgPayload $app $newSha) -ceq $newSha) 'U1 active candidate and backup preserved'
  }
 }
}catch{$fail++;Write-Output ('FAIL U1 exception '+$_.Exception.Message)}
finally{
 # A newly created exact direct-TEMP GUID root with own sentinel, no reparse
 # elements and only this script's case names is the only deletion target.
 try{
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  if([IO.Path]::GetDirectoryName($testRoot) -cne $temp -or
     [IO.Path]::GetFileName($testRoot) -cnotmatch '^RDC-RC1-U1-[a-f0-9]{32}$' -or
     [IO.File]::ReadAllText((Join-Path $testRoot 'u1-run-sentinel.txt')) -cne
      [IO.Path]::GetFileName($testRoot)){throw 'U1_CLEANUP_SCOPE_DENIED'}
  foreach($entry in @(Get-ChildItem -LiteralPath $testRoot -Force -Recurse)){
   if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'U1_CLEANUP_REPARSE_DENIED'}
  }
  [IO.Directory]::Delete($testRoot,$true)
  Check (-not [IO.Directory]::Exists($testRoot)) 'U1 one-time fixture removed'
 }catch{$fail++;Write-Output ('FAIL U1 root remains NOT CLEAN '+$testRoot)}
}
Write-Output ('RC1_U1_DISPOSABLE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
