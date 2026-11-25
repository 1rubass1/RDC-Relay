# G7 planned-only future trial actor. Not Desktop Commander Remote.
# Never used without separately approved and pre-reviewed dummy-tree OS gate.
param([Parameter(Mandatory=$true)][ValidateSet('Root','Child')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$configPath=Join-Path $Root 'trial.json'
if(-not [IO.File]::Exists($configPath)){throw 'DUMMY_NO_PRIVATE_CONFIG'}
$cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
if($cfg.kind -cne 'RC1_G7_DUMMY_ONLY' -or $cfg.runId -cnotmatch '^[a-f0-9]{32}$' -or
 $cfg.root -cne $Root -or $cfg.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'DUMMY_CONFIG_INVALID'}
$expected=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-DUMMY-'+$cfg.runId)))
if(-not [string]::Equals($Root,$expected,[StringComparison]::OrdinalIgnoreCase)){throw 'DUMMY_ROOT_WRONG'}
$me=[Diagnostics.Process]::GetCurrentProcess()
$readyPath=Join-Path $Root (($Mode.ToLowerInvariant())+'-ready.json')
$ready=@{pid=$PID;utcTicks=$me.StartTime.ToUniversalTime().Ticks;session=$me.SessionId;
 mode=$Mode;runId=$cfg.runId}
if($Mode -ceq 'Root'){
 $executable=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$executable;$psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true;$psi.WorkingDirectory=$Root
 $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
  (Join-Path $Root 'actor.ps1')+'" -Mode Child -Root "'+$Root+'"'
 $child=[Diagnostics.Process]::Start($psi)
 if(-not $child){throw 'DUMMY_CHILD_START_FAILURE'}
 $ready.childPid=$child.Id
}
$bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $ready -Compress))
$fs=[IO.FileStream]::new($readyPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
$timer=[Diagnostics.Stopwatch]::StartNew()
$stopPath=Join-Path $Root ('stop-'+$Mode.ToLowerInvariant()+'.txt')
while($timer.Elapsed.TotalSeconds -lt 30){
 if([IO.File]::Exists($stopPath)){
  $text=[IO.File]::ReadAllText($stopPath,[Text.Encoding]::UTF8)
  if($text -cne [string]$cfg.nonce){throw 'DUMMY_STOP_NONCE_MISMATCH'}
  exit 0
 }
 Start-Sleep -Milliseconds 100
}
# Bounded self-exit on absent controller; no force kill, no logout.
exit 42
