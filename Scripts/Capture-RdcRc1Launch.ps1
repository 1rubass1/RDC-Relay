# RDC Relay 1.6 RC1 privacy-restricted startup logger.
# Passive by default. Optional P explicitly launches the validated RC1 launcher.
param([switch]$SelfTest,[ValidateRange(1,60)][int]$MaxMinutes=20,[ValidateRange(0,30)][int]$DryRunSeconds=0)
$ErrorActionPreference='Stop'
$id=[guid]::NewGuid().ToString('N')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-Diagnostic-'+$id)
$desk=if($SelfTest -or $DryRunSeconds -gt 0){[IO.Path]::GetTempPath()}else{[Environment]::GetFolderPath('Desktop')}
$zip=Join-Path $desk ('RDC-RC1-Diagnostics-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,8)+'.zip')
$script:events=Join-Path $root 'timeline.jsonl'
$script:enc=New-Object Text.UTF8Encoding($false)
$script:tracked=@{}
$script:subIds=@()
$script:probe=$null
$script:probeReads=$null
$script:started=[datetime]::UtcNow
$script:failed=$false
$mutex=$null
$owned=$false
function Record([string]$kind,[hashtable]$item){
 $item['utc']=[datetime]::UtcNow.ToString('o')
 $item['kind']=$kind
 $line=ConvertTo-Json -InputObject $item -Depth 5 -Compress
 [IO.File]::AppendAllText($script:events,$line+[char]10,$script:enc)
}
function Classify([string]$name,[string]$line){
 if($name -match '(?i)^(RC1 Pilot Setup|RDC-Relay-1\.6\.0-RC1.*Setup)\.exe$'){return 'RC1_SETUP'}
 if($name -ieq 'RC1 Pilot Launcher.exe'){return 'RC1_LAUNCHER'}
 if($name -ieq 'RDC.Relay.Setup.v1.5.18.exe'){return 'STABLE_SETUP'}
 if($name -in @('powershell.exe','pwsh.exe')){
  if($line -match '(?i)-File\s+"?[^"]*rc1-tray-host\.ps1'){return 'RC1_HOST'}
  if($line -match '(?i)-File\s+"?[^"]*remote-window\.ps1' -and $line -match '(?i)-OwnerGui'){return 'RC1_GUI'}
  if($line -match '(?i)-File\s+"?[^"]*RemoteDesktopCommanderLauncher\remote-window\.ps1'){return 'STABLE_GUI'}
 }
 if($name -ieq 'cmd.exe' -and $line -match '(?i)@wonderwhy-er/desktop-commander@0\.2\.52\s+remote'){return 'REMOTE_LAUNCHER'}
 if($name -ieq 'node.exe' -and $line -match '(?i)desktop-commander'){return 'REMOTE_NODE'}
 return ''
}
function PollProcesses {
 try{$all=@(Get-CimInstance Win32_Process -ErrorAction Stop)}
 catch{Record 'poll_error' @{category=$_.Exception.GetType().Name};return}
 $now=@{}
 foreach($p in $all){
  $role=Classify ([string]$p.Name) ([string]$p.CommandLine)
  if(-not $role){continue}
  $born=''
  try{$born=([datetime]$p.CreationDate).ToUniversalTime().ToString('o')}catch{}
  $key=[string]$p.ProcessId+'|'+$born
  $now[$key]=@{role=$role;pid=[int]$p.ProcessId;parent=[int]$p.ParentProcessId;born=$born}
  if(-not $script:tracked.ContainsKey($key)){Record 'process_detected' $now[$key].Clone()}
  if($role -eq 'RC1_GUI'){
   try{
    $g=Get-Process -Id ([int]$p.ProcessId) -ErrorAction Stop
    $now[$key]['hasWindow']=$g.MainWindowHandle -ne [IntPtr]::Zero
    $now[$key]['responding']=$g.Responding
    if(-not $script:tracked.ContainsKey($key) -or
       $script:tracked[$key]['hasWindow'] -ne $now[$key]['hasWindow'] -or
       $script:tracked[$key]['responding'] -ne $now[$key]['responding']){
      Record 'gui_window_state' $now[$key].Clone()
    }
   }catch{}
  }
 }
 foreach($key in @($script:tracked.Keys)){
  if(-not $now.ContainsKey($key)){Record 'process_missing' $script:tracked[$key].Clone()}
 }
 $script:tracked=$now
}
function DrainTrace {
 foreach($source in $script:subIds){
  foreach($evt in @(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue)){
   try{
    $data=$evt.SourceEventArgs.NewEvent
    $name=[string]$data.ProcessName
    if($name -match '(?i)^(RC1 Pilot Launcher|RC1 Pilot Setup|RDC-Relay-1\.6\.0-RC1.*Setup|RDC\.Relay\.Setup\.v1\.5\.18)\.exe$' -or
       $name -match '(?i)^(powershell|pwsh|cmd|node)\.exe$'){
     $row=@{processName=$name;pid=[int]$data.ProcessID}
     if($data.PSObject.Properties['ParentProcessID']){$row.parent=[int]$data.ParentProcessID}
     if($data.PSObject.Properties['ExitStatus']){$row.exitStatus=[uint32]$data.ExitStatus}
     Record $(if($source -match 'Start'){'os_process_start'}else{'os_process_stop'}) $row
    }
   }catch{Record 'event_parse_error' @{category=$_.Exception.GetType().Name}}
   finally{Remove-Event -EventIdentifier $evt.EventIdentifier -ErrorAction SilentlyContinue}
  }
 }
}
function ValidateLauncher {
 $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDC Relay.lnk'
 if(-not [IO.File]::Exists($lnk)){throw 'SHORTCUT_MISSING'}
 $w=New-Object -ComObject WScript.Shell
 $s=$null
 try{
  $s=$w.CreateShortcut($lnk)
  $target=[IO.Path]::GetFullPath([string]$s.TargetPath)
  $args=([string]$s.Arguments).Trim()
 }finally{
  if($s){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($s)}
  if($w){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($w)}
 }
 $prefix=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'RDCRelayOwnerPilot\1.6.0-RC1\releases'))+[IO.Path]::DirectorySeparatorChar
 $release=[IO.Path]::GetDirectoryName($target)
 if(-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($release) -notmatch '^rc1-[a-f0-9]{24,32}$' -or
    [IO.Path]::GetFileName($target) -cne 'RC1 Pilot Launcher.exe' -or
    $args -cne '--full' -or -not [IO.File]::Exists($target)){throw 'NOT_A_RC1_SHORTCUT'}
 foreach($path in @($release,$target)){
  if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'REPARSE_REFUSED'}
 }
 return $target
}
function StartProbe {
 if($script:probe){Record 'probe_refused' @{reason='ALREADY_RUNNING'};return}
 try{
  $target=ValidateLauncher
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$target;$psi.Arguments='--full';$psi.WorkingDirectory=[IO.Path]::GetDirectoryName($target)
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardError=$true;$psi.RedirectStandardOutput=$true
  $script:probe=[Diagnostics.Process]::Start($psi)
  $script:probeReads=@($script:probe.StandardError.ReadToEndAsync(),$script:probe.StandardOutput.ReadToEndAsync())
  Record 'user_requested_launcher_probe' @{pid=$script:probe.Id;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
  Write-Host 'Direct Launcher probe started (user requested).' -ForegroundColor Cyan
 }catch{
  Record 'probe_refused' @{reason=$_.Exception.Message -replace '[^A-Z0-9_]','_'}
  Write-Host 'Probe refused: Desktop shortcut is not a verified RC1 launcher.' -ForegroundColor Yellow
 }
}
function PollProbe {
 if(-not $script:probe -or -not $script:probe.HasExited){return}
 $code=$script:probe.ExitCode
 $stderr=if($script:probeReads[0].IsCompleted){[string]$script:probeReads[0].GetAwaiter().GetResult()}else{''}
 $stdout=if($script:probeReads[1].IsCompleted){[string]$script:probeReads[1].GetAwaiter().GetResult()}else{''}
 $codes=@([regex]::Matches($stdout+[char]10+$stderr,'RC1_[A-Z0-9_]{3,100}')|ForEach-Object{$_.Value}|Select-Object -Unique)
 Record 'probe_result' @{exitCode=$code;safeCodes=$codes;stderrLength=$stderr.Length;stdoutLength=$stdout.Length}
 Write-Host ('Direct Launcher exit '+$code+'; codes: '+($codes -join ', ')) -ForegroundColor Cyan
 $script:probe.Dispose();$script:probe=$null;$script:probeReads=$null
}
function CaptureWindowsEvents {
 try{
  $count=0
  foreach($evt in @(Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$script:started.AddSeconds(-3)} -MaxEvents 300 -ErrorAction Stop)){
   if($evt.ProviderName -notin @('Application Error','.NET Runtime','Windows Error Reporting','Application Hang')){continue}
   # Raw event messages/properties can contain private user paths or credentials: do NOT include.
   Record 'application_event' @{provider=$evt.ProviderName;eventId=$evt.Id;recordId=$evt.RecordId;occurred=$evt.TimeCreated.ToUniversalTime().ToString('o')}
   $count++
  }
  Record 'events_summary' @{count=$count;maxScanned=300}
 }catch{Record 'events_unavailable' @{category=$_.Exception.GetType().Name}}
}
try{
 [void][IO.Directory]::CreateDirectory($root)
 if(-not $SelfTest){
  $mutex=New-Object Threading.Mutex($false,'Local\RdcRelayRC1Diagnostics')
  $owned=$mutex.WaitOne(0)
  if(-not $owned){throw 'ALREADY_RUNNING'}
 }
 Record 'capture_started' @{version='RC1-DIAG-1';selfTest=[bool]$SelfTest;maxMinutes=$MaxMinutes;ps=$PSVersionTable.PSVersion.ToString()}
 if(-not $SelfTest){
  foreach($type in @('Start','Stop')){
   $sid='RDC_RC1_DIAG_'+$type+'_'+$id
   try{
    [void](Register-WmiEvent -Query ('SELECT * FROM Win32_Process'+$type+'Trace') -SourceIdentifier $sid -ErrorAction Stop)
    $script:subIds+=$sid
   }catch{Record 'trace_unavailable' @{source=$type;category=$_.Exception.GetType().Name}}
  }
 }
 Write-Host 'RDC Relay 1.6 RC1 DIAGNOSTIC LOGGER' -ForegroundColor Green
 Write-Host 'Leave this window open; install RC1 and try opening it as usual.'
 Write-Host 'Press S to finish/save ZIP. Optional: P = direct Launcher probe; F = failed GUI; W = visible GUI.'
 Write-Host ('Automatic save after '+$MaxMinutes+' minutes. Never stops Remote or changes the installation.')
 $deadline=if($DryRunSeconds -gt 0){$script:started.AddSeconds($DryRunSeconds)}else{$script:started.AddMinutes($MaxMinutes)}
 do{
  PollProcesses
  DrainTrace
  PollProbe
  if($SelfTest){Record 'self_test' @{outcome='PASS'};break}
  if($DryRunSeconds -gt 0){Start-Sleep -Milliseconds 500;continue}
  try{
   if([Console]::KeyAvailable){
    $key=[Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
    switch($key){
     'S' {Record 'user_marker' @{marker='FINISH'};$deadline=[datetime]::UtcNow}
     'F' {Record 'user_marker' @{marker='GUI_FAILED'};Write-Host 'Marked: failed to open.'}
     'W' {Record 'user_marker' @{marker='GUI_VISIBLE'};Write-Host 'Marked: window visible.'}
     'P' {StartProbe}
    }
   }
  }catch{Record 'console_unavailable' @{category=$_.Exception.GetType().Name};$deadline=[datetime]::UtcNow}
  Start-Sleep -Milliseconds 700
 }while([datetime]::UtcNow -lt $deadline)
}catch{
 $script:failed=$true
 if([IO.Directory]::Exists($root)){Record 'capture_error' @{category=$_.Exception.GetType().Name}}
}finally{
 try{
  PollProcesses
  DrainTrace
  PollProbe
  if($script:probe){Record 'probe_unfinished' @{pid=$script:probe.Id};$script:probe.Dispose()}
  if(-not $SelfTest){CaptureWindowsEvents}
  $readme='RDC Relay RC1 sanitized capture'+[Environment]::NewLine+
   'UTC start: '+$script:started.ToString('o')+[Environment]::NewLine+
   'Captured: process roles/PID/parent/birth, GUI handle/response, process lifecycle, Windows error event IDs, optional Launcher exit code.'+[Environment]::NewLine+
   'NOT captured: raw command lines, Remote logs, credentials, device IDs, event messages, stdout/stderr raw text.'+[Environment]::NewLine+
   'Polling can miss short-lived processes; OS process trace is best-effort.'+[Environment]::NewLine
  [IO.File]::WriteAllText((Join-Path $root 'README.txt'),$readme,$script:enc)
  foreach($sid in $script:subIds){Unregister-Event -SourceIdentifier $sid -ErrorAction SilentlyContinue}
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($root,$zip)
  if(-not [IO.File]::Exists($zip) -or ([IO.FileInfo]$zip).Length -lt 150){throw 'ZIP_INVALID'}
  Write-Host ('REPORT: '+$zip) -ForegroundColor Green
  if($SelfTest -or $DryRunSeconds -gt 0){
   $z=[IO.Compression.ZipFile]::OpenRead($zip)
   try{if(@($z.Entries).Count -lt 2){throw 'ZIP_EMPTY'}}finally{$z.Dispose()}
   [IO.File]::Delete($zip)
   Write-Output $(if($SelfTest){'DIAG_SELFTEST_PASS=TRUE'}else{'DIAG_DRYRUN_PASS=TRUE'})
  }
  $items=@([IO.Directory]::GetFiles($root))
  if(@([IO.Directory]::GetDirectories($root)).Count -eq 0 -and
     @($items|Where-Object{[IO.Path]::GetFileName($_) -notin @('README.txt','timeline.jsonl')}).Count -eq 0){
   foreach($f in $items){[IO.File]::Delete($f)}
   [IO.Directory]::Delete($root,$false)
  }
 }catch{
  $script:failed=$true
  Write-Host ('REPORT_FAILED: '+$_.Exception.GetType().Name+'; temporary data retained.') -ForegroundColor Red
 }
 if($owned -and $mutex){try{$mutex.ReleaseMutex()}catch{}}
 if($mutex){$mutex.Dispose()}
}
if($script:failed){exit 1}
exit 0
