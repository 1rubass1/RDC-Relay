# Existing isolated AST/compile/fake-only regression inventory. Never starts RC1 Host/GUI or Remote.
$ErrorActionPreference='Stop'
$names=@(
 'Test-V16TicketRecovery.ps1','Test-V16OwnerRemoteState.ps1',
 'Test-V16OwnerBoundaryStatic.ps1','Test-V16ProductHostGuiSource.ps1',
 'Test-V16OwnerAddType.ps1','Test-V16OwnerStagePackage.ps1',
 'Test-V16OwnerContract.ps1','Test-V16BuildIsolation.ps1',
 'Test-V16PackageManifestNegative.ps1',
 'Test-RemoteCharacterization.ps1','Test-RemoteLineClassifier.ps1',
 'Test-ProcessOwnershipCharacterization.ps1','Test-WindowLifecycleCharacterization.ps1',
 'Test-UiLifecycle.ps1','Test-UpdateNoticeClick.ps1',
 'Test-UpdateNoticeVersionRefresh.ps1','Test-NpxRecovery.ps1')
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pass=0;$fail=0
foreach($name in $names){
 $file=Join-Path $PSScriptRoot $name
 if(-not [IO.File]::Exists($file)){Write-Output ('FAIL '+$name+' MISSING');$fail++;continue}
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$exe
 $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$file+'"'
 $psi.WorkingDirectory=$PSScriptRoot
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($psi)
 $outTask=$p.StandardOutput.ReadToEndAsync()
 $errTask=$p.StandardError.ReadToEndAsync()
 if(-not $p.WaitForExit(120000)){
  Write-Output ('NOT CHECKED '+$name+' TIMEOUT PID='+$p.Id+' NO FORCE STOP')
  $fail++;$p.Dispose();break
 }
 $out=$outTask.GetAwaiter().GetResult()
 $err=$errTask.GetAwaiter().GetResult()
 if($p.ExitCode -eq 0){
  $pass++;Write-Output ('PASS '+$name+' EXIT=0')
 }else{
  $fail++;Write-Output ('FAIL '+$name+' EXIT='+$p.ExitCode)
  if($out.Length -gt 350){$out=$out.Substring($out.Length-350)}
  if($err.Length -gt 350){$err=$err.Substring($err.Length-350)}
  Write-Output ('STDOUT '+$out+' STDERR '+$err)
 }
 $p.Dispose()
}
Write-Output ('RC1_SAFE_REGRESSION_PASS='+$pass+' FAIL='+$fail+' TOTAL='+$names.Count)
if($fail){exit 1}
exit 0
