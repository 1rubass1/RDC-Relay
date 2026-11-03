# Product managed-process OS test: disposable fake cmd child inside a new private Job.
# Never creates or stops @wonderwhy-er/desktop-commander, stable GUI or Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-OWNED-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$fake=Join-Path $root 'npx.cmd'
$log=Join-Path $root 'fake.log'
$pass=0;$fail=0;$owner=$null
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
try{
 [IO.File]::WriteAllText($fake,"@echo off`r`nping.exe -n 45 127.0.0.1 > NUL`r`n")
 Add-Type -Path (Join-Path $repo 'Source\RdcOwnerManagedProcess.cs')
 $owner=New-Object RdcOwnerManagedProcess
 $blocked=$false
 try{$owner.Start($fake,'--logout',$root,$log)}catch{$blocked=$true}
 Check $blocked 'OWNED reject unexpected Remote/credential arguments'
 $blocked=$false
 try{$owner.Start((Join-Path $env:WINDIR 'System32\cmd.exe'),
  '--yes @wonderwhy-er/desktop-commander@0.2.52 remote',$root,$log)}catch{$blocked=$true}
 Check $blocked 'OWNED reject unapproved executable identity'
 $owner.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote',$root,$log)
 Start-Sleep -Milliseconds 600
 Check ($owner.Pid -gt 0 -and $owner.Running) 'OWNED kernel Job includes live disposable process'
 $blocked=$false
 try{$owner.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote',$root,$log)}catch{$blocked=$true}
 Check $blocked 'OWNED deny duplicate second spawn'
 Check ($owner.StopOwnedOnly(10000) -and -not $owner.Running) 'OWNED stop drains verified private Job'
 $blocked=$false
 try{[void]$owner.StopOwnedOnly(0)}catch{$blocked=$true}
 Check $blocked 'OWNED invalid stop timeout rejected'
}catch{$fail++;Write-Output ('FAIL OWNED exception '+$_.Exception.Message)}
finally{
 $safe=$true
 if($owner){
  try{$safe=-not $owner.Running} catch{$safe=$false}
  $owner.Dispose()
 }
 try{
  if(-not $safe){throw 'OWNED_JOB_SURVIVOR_RETAIN_TEMP'}
  if([IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92) -or
   [IO.Path]::GetFileName($root) -cnotmatch '^RDC-RC1-OWNED-[a-f0-9]{32}$'){throw 'OWNED_TEMP_SCOPE_REFUSED'}
  foreach($item in @(Get-ChildItem -LiteralPath $root -Force)){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      @('npx.cmd','fake.log') -cnotcontains $item.Name){throw 'OWNED_TEMP_UNKNOWN_CONTENT'}
  }
  [IO.Directory]::Delete($root,$true)
  Check (-not [IO.Directory]::Exists($root)) 'OWNED temporary fake tree removed'
 }catch{$fail++;Write-Output ('FAIL OWNED cleanup retained '+$root+' '+$_.Exception.Message)}
}
Write-Output ('RC1_OWNED_JOB_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
