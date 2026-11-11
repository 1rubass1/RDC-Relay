# G111: real test-only Setup.exe compiled from the release source; install,
# upgrade, failure injection and updater mocks entirely within USER Temp.
# Public Setup build is unaffected; no user registry/shortcuts/Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'Source'
$stage=Join-Path ([IO.Path]::GetTempPath()) ('RDC-REL-SBX-'+[Guid]::NewGuid().ToString('N'))
$fail=0
try {
 [void][IO.Directory]::CreateDirectory($stage)
 $tempProject=Join-Path $stage 'isolated-project'
 $tempSource=Join-Path $tempProject 'Source'
 [void][IO.Directory]::CreateDirectory($tempSource)
 foreach($item in @('version.txt','update.ps1')){
  [IO.File]::Copy((Join-Path $source $item),(Join-Path $tempSource $item),$false)
 }
 if([IO.File]::Exists((Join-Path $tempSource 'rc1-candidate.json'))){
  throw 'PRIVATE_RELEASE_SANDBOX_CONTAINS_PILOT_MARKER'
 }
 $csc=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|
  Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
 if(-not $csc){throw 'NO_FRAMEWORK_COMPILER'}
 $exe=Join-Path $stage 'Release Private Test Setup.exe'
 $files=@(
  @('remote-window.ps1','RdcPayload.remote-window.ps1'),
  @('update-notice.ps1','RdcPayload.update-notice.ps1'),
  @('divider-caustic.ps','RdcPayload.divider-caustic.ps'),
  @('divider-caustic-detail.ps','RdcPayload.divider-caustic-detail.ps'),
  @('divider-particles.ps','RdcPayload.divider-particles.ps'),
  @('divider-particles-core.ps','RdcPayload.divider-particles-core.ps'),
  @('RDCRelay.ico','RdcPayload.RDCRelay.ico'),
  @('version.txt','RdcPayload.version.txt'),
  @('update.ps1','RdcPayload.update.ps1'),
  @('update-manifest.json','RdcPayload.update-manifest.json'),
  @('RDC Relay.cmd','RdcPayload.launch.cmd')
 )
 $compile=@('/nologo','/target:winexe','/define:RDC_INSTALLER_TEST',
  ('/out:'+$exe),'/reference:System.Windows.Forms.dll',
  (Join-Path $repo 'Installer\Setup.cs'),
  (Join-Path $repo 'Installer\RdcReleaseInstallState.cs'),
  (Join-Path $repo 'Installer\RdcReleaseMetadataSnapshot.cs'))
 foreach($file in $files){
  $compile+=('/resource:'+(Join-Path $source $file[0])+','+$file[1])
 }
 $buildOutput=@(& $csc @compile 2>&1)
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($exe)){
  throw ('PRIVATE_TEST_SETUP_COMPILE_FAILED '+($buildOutput -join ' '))
 }
 Write-Output 'PASS isolated test-only release Setup compiled, no public setup produced'
 $script=Join-Path $repo 'Tests\Test-Transactions.ps1'
 $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$powershell
 $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$script+
  '" -ProjectRoot "'+$tempProject+'" -SetupPath "'+$exe+'"'
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($psi)
 if($null -eq $p){throw 'TRANSACTION_TEST_PROCESS_NOT_STARTED'}
 try {
  $taskOut=$p.StandardOutput.ReadToEndAsync()
  $taskErr=$p.StandardError.ReadToEndAsync()
  if(-not $p.WaitForExit(120000)){
   throw ('TRANSACTION_SANDBOX_TIMEOUT PID='+$p.Id+' NO_FORCED_TERMINATION')
  }
  $stdout=$taskOut.GetAwaiter().GetResult()
  $stderr=$taskErr.GetAwaiter().GetResult()
  if($p.ExitCode -ne 0 -or $stdout -notmatch 'TRANSACTION TESTS PASSED'){
   throw ('TRANSACTION_SANDBOX_FAILED EXIT='+$p.ExitCode+
    ' OUTPUT='+$stdout.Substring([Math]::Max(0,$stdout.Length-1600))+
    ' ERROR='+$stderr.Substring([Math]::Max(0,$stderr.Length-900)))
  }
  Write-Output 'PASS real private Setup fresh install, partial-failure rollback and retry in temp'
  Write-Output 'PASS concurrent install mutex refusal and mock updater rollback/retry in temp'
 }finally{$p.Dispose()}
}catch{
 $fail++
 Write-Output ('FAIL '+$_.Exception.Message)
}finally{
 if([IO.Directory]::Exists($stage)) {
  $parent=[IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($stage)).TrimEnd([char]92)
  $expected=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  if($parent -cne $expected -or [IO.Path]::GetFileName($stage) -cnotmatch '^RDC-REL-SBX-[a-f0-9]{32}$') {
   $fail++;Write-Output 'NOT CLEAN SANDBOX_CLEANUP_SCOPE_REFUSED'
  }else{
   try{
    foreach($item in @(Get-ChildItem -LiteralPath $stage -Recurse -Force)){
     if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      throw 'SANDBOX_REPARSE_REFUSED'
     }
    }
    [IO.Directory]::Delete($stage,$true)
    Write-Output 'PASS disposable sandbox removed'
   }catch{$fail++;Write-Output ('NOT CLEAN '+$_.Exception.Message)}
  }
 }
}
Write-Output ('RC1_RELEASE_SETUP_SANDBOX_FAIL='+$fail)
if($fail){exit 1}
exit 0