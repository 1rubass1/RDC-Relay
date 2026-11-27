# Synthetic fixture: no real Node/npm/Remote, no registry or machine PATH edits.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-P7-PATH-'+[Guid]::NewGuid().ToString('N')+' '+[char]0x0416)
$runtime=Join-Path $root 'runtime'
$cwd=Join-Path $root 'cwd'
$fake=Join-Path $runtime 'npx.cmd'
$helper=Join-Path $runtime 'rdc-path-fixture.cmd'
$log=Join-Path $root 'logout.log'
$oldPath=$env:PATH
$oldSentinel=$env:RDC_P7_PATH_SENTINEL
$owner=$null;$pass=0
function Check([bool]$ok,[string]$name){if(!$ok){throw ('FAIL '+$name)};$script:pass++;'PASS '+$name}
try{
 [void][IO.Directory]::CreateDirectory($runtime)
 [void][IO.Directory]::CreateDirectory($cwd)
 [IO.File]::WriteAllLines($helper,[string[]]@('@echo off','echo FIXTURE_FOUND','exit /b 0'),[Text.Encoding]::ASCII)
 [IO.File]::WriteAllLines($fake,[string[]]@('@echo off','if not "%RDC_P7_PATH_SENTINEL%"=="fixture" exit /b 91','call rdc-path-fixture.cmd','if errorlevel 1 exit /b 92','ping.exe -n 2 127.0.0.1 >nul','exit /b 0'),[Text.Encoding]::ASCII)
 Add-Type -Path (Join-Path $repo 'Source\RdcOwnerManagedProcess.cs')
 $env:PATH=[Environment]::SystemDirectory
 $env:RDC_P7_PATH_SENTINEL='fixture'
 $before=$env:PATH
 Check (-not (Get-Command rdc-path-fixture.cmd -ErrorAction SilentlyContinue)) 'parent cannot resolve fixture helper'
 $owner=New-Object RdcOwnerManagedProcess
 $owner.StartCaptured($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote',$cwd)
 $buf=New-Object byte[] 4096;$output=New-Object IO.MemoryStream;$watch=[Diagnostics.Stopwatch]::StartNew();$eof=$false;$done=$false;$code=0
 while($watch.ElapsedMilliseconds -lt 10000){
  if(!$eof){$n=$owner.ReadCaptured($buf,[ref]$eof);if($n){$output.Write($buf,0,$n)}}
  $done=$owner.TryGetCompletedExitCode([ref]$code)
  if($eof -and $done){break}
  Start-Sleep -Milliseconds 20
 }
 Check ($done -and $eof -and $code -eq 0 -and [Text.Encoding]::ASCII.GetString($output.ToArray()).Contains('FIXTURE_FOUND')) 'captured launch resolves helper from selected runtime and preserves inherited sentinel'
 Check ($env:PATH -ceq $before) 'captured launch does not change parent PATH'
 $output.Dispose();$owner.Dispose();$owner=$null
 $owner=New-Object RdcOwnerManagedProcess
 $owner.Start($fake,'--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout',$cwd,$log)
 $watch.Restart();$done=$false;$code=0
 while($watch.ElapsedMilliseconds -lt 10000){$done=$owner.TryGetCompletedExitCode([ref]$code);if($done){break};Start-Sleep -Milliseconds 20}
 Check ($done -and $code -eq 0 -and [IO.File]::ReadAllText($log).Contains('FIXTURE_FOUND')) 'logout route resolves same helper'
 Check ($env:PATH -ceq $before) 'logout does not change parent PATH'
}finally{
 $env:PATH=$oldPath;$env:RDC_P7_PATH_SENTINEL=$oldSentinel
 if($owner){if($owner.HasStarted -and $owner.Running -and !$owner.StopOwnedOnly(10000)){throw 'FIXTURE_JOB_STILL_RUNNING'};$owner.Dispose()}
 foreach($f in @($fake,$helper,$log)){if([IO.File]::Exists($f)){[IO.File]::Delete($f)}}
 foreach($dir in @($runtime,$cwd,$root)){if([IO.Directory]::Exists($dir) -and [IO.Directory]::GetFileSystemEntries($dir).Length -eq 0){[IO.Directory]::Delete($dir,$false)}}
}
'RDC_P7_CHILD_PATH_PASS='+$pass
