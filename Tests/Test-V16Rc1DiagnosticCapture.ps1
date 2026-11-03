# Isolated validation of the owner RC1 diagnostics logger. Never installs or runs Remote.
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path $PSScriptRoot -Parent) 'Scripts\Capture-RdcRc1Launch.ps1'
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pass=0;$fail=0
function Check([bool]$yes,[string]$label){
 if($yes){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
if(-not [IO.File]::Exists($path)){Write-Output 'FAIL DIAGNOSTIC_SOURCE_MISSING';exit 1}
$code=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
Check ($code.Contains('RC1_OWNER_LAUNCH_REFUSED') -eq $false) 'Observer does not impersonate product Launcher'
Check ($code.Contains('Stop-Process') -eq $false -and $code.Contains('taskkill') -eq $false) 'Logger has no process kill command'
Check ($code.Contains('ReadToEndAsync') -and $code.Contains('safeCodes')) 'Optional Launcher probe preserves bounded diagnostic codes'
Check ($code.Contains('Get-WinEvent') -and $code.Contains('Register-WmiEvent') -and $code.Contains('Win32_Process')) 'Both Windows events and process start trace available'
Check ($code.Contains('NOT captured: raw command lines')) 'Report declares privacy exclusions'
foreach($mode in @(@('-SelfTest','DIAG_SELFTEST_PASS=TRUE'),@('-DryRunSeconds','DIAG_DRYRUN_PASS=TRUE'))){
 $args=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$path,$mode[0])
 if($mode[0] -eq '-DryRunSeconds'){$args+='2'}
 $lines=@(& $exe @args 2>&1 | ForEach-Object { [string]$_ })
 $status=$LASTEXITCODE
 Check ($status -eq 0) ('Isolated '+$mode[0]+' exits 0')
 Check ([string]::Join(' ',$lines).Contains($mode[1])) ('Isolated '+$mode[0]+' yields verified ZIP')
}
Write-Output ('RC1_DIAGNOSTIC_TEST_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
