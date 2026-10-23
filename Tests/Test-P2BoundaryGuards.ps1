# P2A-only negative tests. All roots/sentinels are newly created and GUID-scoped.
# Never inspect or clean historical RDC-P1-* or unknown-provenance RDC-P2-* directories.
$ErrorActionPreference='Stop'
$src=Join-Path $PSScriptRoot 'Prototypes\ARCH-016-P2'
$helper=Join-Path $PSScriptRoot 'Set-P2DemoBuild.ps1'
$psExe=Join-Path $PSHOME 'powershell.exe'
$temp=([IO.Path]::GetFullPath([IO.Path]::GetTempPath())).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
$script:pass=0;$script:fail=0;$script:notChecked=0
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $src 'P1Wire.cs'),(Join-Path $src 'P1Core.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll')

function Assert-P2([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Pass-P2([string]$Name){Write-Output ('PASS '+$Name);$script:pass++}
function Fail-P2([string]$Name,[string]$Message){Write-Output ('FAIL '+$Name+': '+$Message);$script:fail++}
function NotChecked-P2([string]$Name,[string]$Message){Write-Output ('NOT CHECKED '+$Name+': '+$Message);$script:notChecked++}
function Normalize-P2Directory([string]$Path){
  $full=[IO.Path]::GetFullPath($Path);$volume=[IO.Path]::GetPathRoot($full)
  if($full.Length -gt $volume.Length){$full=$full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))}
  return $full
}
function Test-P2NoReparse([string]$Path,[switch]$AllowMissingLeaf){
  try{
    $current=[IO.Path]::GetFullPath($Path);$volume=[IO.Path]::GetPathRoot($current);$leaf=$true
    while(-not [string]::IsNullOrEmpty($current)){
      try{$attributes=[IO.File]::GetAttributes($current);if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}}
      catch{
        if(-not ($leaf -and $AllowMissingLeaf)){return $false}
        $parent=[IO.Path]::GetDirectoryName($current)
        if(-not $parent -or -not [IO.Directory]::Exists($parent)){return $false}
        $name=[IO.Path]::GetFileName($current)
        foreach($entry in [IO.Directory]::GetFileSystemEntries($parent)){
          if([String]::Equals([IO.Path]::GetFileName($entry),$name,[StringComparison]::OrdinalIgnoreCase)){return $false}
        }
      }
      if([String]::Equals($current,$volume,[StringComparison]::OrdinalIgnoreCase)){break}
      $next=[IO.Path]::GetDirectoryName($current);if(-not $next -or $next -eq $current){return $false}
      $current=$next;$leaf=$false
    }
    return $true
  }catch{return $false}
}
function New-P2Fixture([string]$Id){
  $root=Join-Path $temp ('RDC-P2-'+$Id)
  if([IO.Directory]::Exists($root) -or [IO.File]::Exists($root)){throw 'GUID collision; refusing to reuse a fixture path'}
  [void][IO.Directory]::CreateDirectory($root)
  foreach($name in @('P1Core.cs','P1Wire.cs','Host.ps1','Gui.ps1')){
    Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $root $name) -ErrorAction Stop
  }
  return $root
}
function Remove-P2Fixture([string]$Root,[switch]$TargetDirectory){
  if(-not [IO.Directory]::Exists($Root)){return}
  $full=Normalize-P2Directory $Root
  if(-not [String]::Equals([IO.Path]::GetDirectoryName($full),$temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup refused: path is not a direct TEMP child'}
  if(-not (Test-P2NoReparse $full)){throw 'Cleanup refused: root/path contains a reparse point'}
  $leaf=[IO.Path]::GetFileName($full)
  if($TargetDirectory){
    if($leaf -cnotmatch '^RDC-P2-target-[0-9a-f]{32}$'){throw 'Cleanup refused: unexpected target fixture name'}
  }elseif($leaf -cnotmatch '^RDC-P2-[0-9a-f]{32}$'){throw 'Cleanup refused: unexpected fixture name'}
  foreach($entry in [IO.Directory]::GetFileSystemEntries($full)){
    $attr=[IO.File]::GetAttributes($entry)
    if(($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw ('Cleanup refused: reparse child remains '+[IO.Path]::GetFileName($entry))}
    if(($attr -band [IO.FileAttributes]::Directory) -ne 0){throw ('Cleanup refused: unexpected nested directory '+[IO.Path]::GetFileName($entry))}
  }
  [IO.Directory]::Delete($full,$true)
}
function Remove-P2Sentinel([string]$Path,[string]$ExpectedHash){
  if(-not [IO.File]::Exists($Path)){return}
  $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if($actual -ne $ExpectedHash){
    Write-Output ('NOT CLEAN: outside sentinel changed and was preserved: '+$Path)
    $script:fail++
    return
  }
  if(-not (Test-P2NoReparse $Path)){throw 'Sentinel cleanup refused: reparse point'}
  [IO.File]::Delete($Path)
}
function Start-P2Host([string]$Root,[string]$Id,[switch]$FailTicket){
  $hostFile=Join-Path $Root 'Host.ps1'
  $arguments='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$hostFile+'" -FixtureRoot "'+$Root+'" -Instance '+$Id+' -ControllerPid '+$PID+' -ControllerTicks '+[P1Wire]::Born($PID)+' -ReplayLimit 8'
  if($FailTicket){$arguments+=' -FailGuiTicketBeforeWrite'}
  $proc=Start-Process -FilePath $psExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
  $authPath=Join-Path $Root 'controller-auth.json';$watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not [IO.File]::Exists($authPath) -and $watch.ElapsedMilliseconds -lt 8000){
    $proc.Refresh();if($proc.HasExited){throw ('Host exited before controller rendezvous; exit '+$proc.ExitCode)}
    Start-Sleep -Milliseconds 100
  }
  if(-not [IO.File]::Exists($authPath)){throw 'Host rendezvous timed out'}
  $auth=[P1Wire]::Decode([IO.File]::ReadAllText($authPath,[Text.Encoding]::UTF8))
  $identity=([string]$auth.hostPid)+'|'+([string]$auth.hostTicks)+'|'+([string]$auth.hostSession)
  return [pscustomobject]@{Root=$Root;Id=$Id;Process=$proc;Auth=$auth;Identity=$identity;Seq=[long]0;Birth=$proc.StartTime.ToUniversalTime().Ticks}
}
function Send-P2Host($Context,[string]$Verb){
  $Context.Seq=[long]$Context.Seq+1
  $wire=[P1Wire]::Request($Verb,[string]$Context.Auth.nonce,[string]$Context.Auth.hostGeneration,0,$null,[long]$Context.Seq)
  return [P1Wire]::Decode([P1Wire]::Call([string]$Context.Auth.pipe,[string]$Context.Identity,$wire,1000))
}
function Wait-P2State($Context,[scriptblock]$Predicate,[int]$Deadline=8000){
  $watch=[Diagnostics.Stopwatch]::StartNew()
  do{
    $reply=Send-P2Host $Context 'TEST_STATE'
    if($reply.type -eq 'ERROR'){throw ('Host returned '+$reply.code)}
    if(& $Predicate $reply.payload){return $reply.payload}
    Start-Sleep -Milliseconds 100
  }while($watch.ElapsedMilliseconds -lt $Deadline)
  throw ('Host state timed out after '+$Deadline+'ms')
}
function Stop-P2Host($Context){
  if(-not $Context){return}
  $Context.Process.Refresh()
  if(-not $Context.Process.HasExited){
    $owned=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+$Context.Process.Id) -ErrorAction Stop)
    Assert-P2 ($owned.Count -eq 1 -and ([string]$owned[0].CommandLine).Contains(' -File "'+(Join-Path $Context.Root 'Host.ps1')+'"') -and
      ([string]$owned[0].CommandLine).Contains($Context.Root) -and $Context.Process.StartTime.ToUniversalTime().Ticks -eq $Context.Birth) 'Host identity could not be verified for cooperative cleanup'
    $state=Send-P2Host $Context 'TEST_STATE'
    if([int]$state.payload.guiPid -gt 0){
      [void](Send-P2Host $Context 'TEST_CLOSE')
      [void](Wait-P2State $Context {param($s) $s.guiPid -eq 0} 6000)
    }
    [void](Send-P2Host $Context 'TEST_END')
    Assert-P2 ($Context.Process.WaitForExit(8000)) 'Owned test Host did not exit cooperatively; no force kill used'
  }
  $Context.Process.Refresh()
  $remaining=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object{
    ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $Context.Root 'Host.ps1')+'"') -or
    ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $Context.Root 'Gui.ps1')+'"')
  })
  Assert-P2 ($remaining.Count -eq 0) ('Fixture process survivors: '+($remaining.ProcessId -join ','))
  $Context.Process.Dispose()
}
function Test-P2HelperRefusal([string]$Root,[string]$ExpectedText){
  try{& $helper -FixtureRoot $Root -Build B|Out-Null;return $false}
  catch{return $_.Exception.Message.Contains($ExpectedText)}
}

# 1. A junction at the fixture root must be rejected by both Host construction
# and the build helper. Only GUID-scoped directories created in this test are used.
$rootId=[guid]::NewGuid().ToString('N')
$alias=Join-Path $temp ('RDC-P2-'+$rootId)
$target=Join-Path $temp ('RDC-P2-target-'+$rootId)
$rootSentinel=Join-Path $temp ('RDC-P2-sentinel-root-'+$rootId+'.txt')
$junctionCreated=$false;$rootHost=$null;$targetGuiHash='';$rootSentinelHash=''
try{
  [void][IO.Directory]::CreateDirectory($target)
  foreach($name in @('P1Core.cs','P1Wire.cs','Host.ps1','Gui.ps1')){Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $target $name)}
  [IO.File]::WriteAllText($rootSentinel,'P2A root-junction outside sentinel '+$rootId)
  $rootSentinelHash=(Get-FileHash -LiteralPath $rootSentinel -Algorithm SHA256).Hash
  $targetGuiHash=(Get-FileHash -LiteralPath (Join-Path $target 'Gui.ps1') -Algorithm SHA256).Hash
  try{New-Item -ItemType Junction -Path $alias -Target $target -ErrorAction Stop|Out-Null;$junctionCreated=$true}
  catch{NotChecked-P2 'P2A-ROOT-JUNCTION' ('Windows refused a test-owned junction: '+$_.Exception.Message)}
  if($junctionCreated){
    $helperRejected=Test-P2HelperRefusal $alias 'reparse point in fixture root'
    Assert-P2 $helperRejected 'Build helper did not refuse the root junction before other checks'
    $hostArgs='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+(Join-Path $alias 'Host.ps1')+'" -FixtureRoot "'+$alias+'" -Instance '+$rootId+' -ControllerPid '+$PID+' -ControllerTicks '+[P1Wire]::Born($PID)+' -ReplayLimit 8'
    $rootHost=Start-Process -FilePath $psExe -ArgumentList $hostArgs -WindowStyle Hidden -PassThru
    Assert-P2 ($rootHost.WaitForExit(8000)) 'Host did not reject junction root within deadline; no force kill used'
    $rootHost.Refresh()
    Assert-P2 ($rootHost.ExitCode -eq 10) ('Host did not reject junction root; exit '+$rootHost.ExitCode)
    Assert-P2 (-not [IO.File]::Exists((Join-Path $target 'controller-auth.json')) -and -not [IO.File]::Exists((Join-Path $target 'gui-ticket.json'))) 'Host wrote a secret/rendezvous through a junction root'
    Assert-P2 ((Get-FileHash -LiteralPath (Join-Path $target 'Gui.ps1') -Algorithm SHA256).Hash -eq $targetGuiHash) 'Root junction test changed target GUI source'
    Pass-P2 'P2A-ROOT-JUNCTION-TARGET-GUI-UNCHANGED'
    Assert-P2 ((Get-FileHash -LiteralPath $rootSentinel -Algorithm SHA256).Hash -eq $rootSentinelHash) 'Root junction test changed outside sentinel'
    Pass-P2 'P2A-ROOT-JUNCTION-OUTSIDE-SENTINEL-UNCHANGED'
    $rootGui=Join-Path $alias 'Gui.ps1'
    $rootResidual=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object{
      ([string]$_.CommandLine).Contains(' -File "'+(Join-Path $alias 'Host.ps1')+'"') -or
      ([string]$_.CommandLine).Contains(' -File "'+$rootGui+'"')
    })
    Assert-P2 ($rootResidual.Count -eq 0) ('Root junction test left owned process(s): '+($rootResidual.ProcessId -join ','))
    Pass-P2 'P2A-ROOT-JUNCTION-HOST-AND-HELPER-REFUSAL'
  }
}catch{Fail-P2 'P2A-ROOT-JUNCTION' $_.Exception.Message}
finally{
  $rootCleanupAllowed=$true
  if($rootHost){
    $rootHost.Refresh()
    if(-not $rootHost.HasExited){$rootCleanupAllowed=$false;Fail-P2 'P2A-ROOT-JUNCTION-CLEANUP' 'Owned root test Host still active; fixture preserved'}
    else{$rootHost.Dispose()}
  }
  if($rootCleanupAllowed){
    if($junctionCreated){
      try{[IO.Directory]::Delete($alias,$false)}catch{Fail-P2 'P2A-ROOT-JUNCTION-LINK-CLEANUP' $_.Exception.Message}
    }
    if([IO.Directory]::Exists($alias)){Fail-P2 'P2A-ROOT-JUNCTION-CLEANUP' 'Junction alias remains; left in place for diagnosis';$rootCleanupAllowed=$false}
  }
  if($rootCleanupAllowed -and [IO.Directory]::Exists($target)){
    try{Remove-P2Fixture $target -TargetDirectory}catch{Fail-P2 'P2A-ROOT-TARGET-CLEANUP' $_.Exception.Message}
  }elseif(-not $rootCleanupAllowed){Write-Output ('NOT CLEAN root-junction fixture preserved: '+$alias+' -> '+$target)}
  if([IO.File]::Exists($rootSentinel)){
    try{Remove-P2Sentinel $rootSentinel $rootSentinelHash}catch{Fail-P2 'P2A-ROOT-SENTINEL-CLEANUP' $_.Exception.Message}
  }
}

# 2. A reparse-point Gui.ps1 must be rejected before the helper reads/writes it.
$fileId=[guid]::NewGuid().ToString('N');$fileRoot=$null;$guiLinkCreated=$false
$fileSentinel=Join-Path $temp ('RDC-P2-sentinel-gui-'+$fileId+'.txt');$fileSentinelHash=''
try{
  $fileRoot=New-P2Fixture $fileId
  [IO.File]::WriteAllBytes($fileSentinel,[IO.File]::ReadAllBytes((Join-Path $src 'Gui.ps1')))
  $fileSentinelHash=(Get-FileHash -LiteralPath $fileSentinel -Algorithm SHA256).Hash
  $guiPath=Join-Path $fileRoot 'Gui.ps1'
  [IO.File]::Delete($guiPath)
  try{New-Item -ItemType SymbolicLink -Path $guiPath -Target $fileSentinel -ErrorAction Stop|Out-Null;$guiLinkCreated=$true}
  catch{
    Copy-Item -LiteralPath (Join-Path $src 'Gui.ps1') -Destination $guiPath -ErrorAction Stop
    NotChecked-P2 'P2A-GUI-FILE-REPARSE' ('Windows refused a test-owned file symlink: '+$_.Exception.Message)
  }
  if($guiLinkCreated){
    $helperRejected=Test-P2HelperRefusal $fileRoot 'reparse point in Gui.ps1'
    Assert-P2 $helperRejected 'Build helper did not reject the Gui.ps1 link before source access'
    $hostRejected=$false
    try{[void][P1Core]::new($fileRoot,$guiPath,$fileId,$PID,[P1Wire]::Born($PID),8192,$false,$false,$false)}
    catch{$hostRejected=$_.Exception.Message.Contains('DISPOSABLE_ROOT_ONLY')}
    Assert-P2 $hostRejected 'P1Core accepted a reparse-point Gui.ps1'
    Assert-P2 ((Get-FileHash -LiteralPath $fileSentinel -Algorithm SHA256).Hash -eq $fileSentinelHash) 'Outside sentinel changed through Gui.ps1 link'
    Pass-P2 'P2A-GUI-FILE-REPARSE-HELPER-HOST-AND-SENTINEL'
  }
}catch{Fail-P2 'P2A-GUI-FILE-REPARSE' $_.Exception.Message}
finally{
  if($fileRoot -and [IO.Directory]::Exists($fileRoot)){
    $guiPath=Join-Path $fileRoot 'Gui.ps1'
    if([IO.File]::Exists($guiPath)){
      try{if(([IO.File]::GetAttributes($guiPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0){[IO.File]::Delete($guiPath)}}catch{}
    }
    if(-not [IO.File]::Exists($guiPath)){Copy-Item -LiteralPath (Join-Path $src 'Gui.ps1') -Destination $guiPath -ErrorAction SilentlyContinue}
    try{Remove-P2Fixture $fileRoot}catch{Fail-P2 'P2A-GUI-FILE-CLEANUP' $_.Exception.Message}
  }
  if([IO.File]::Exists($fileSentinel)){
    try{Remove-P2Sentinel $fileSentinel $fileSentinelHash}catch{Fail-P2 'P2A-GUI-SENTINEL-CLEANUP' $_.Exception.Message}
  }
}

# 3. Ticket creation fault is injected before any ticket/temp bytes. The Host
# must return a normal IPC snapshot, retain NONE state, and continue ticking.
$ticketId=[guid]::NewGuid().ToString('N');$ticketRoot=$null;$ticketHost=$null;$ticketClean=$false
try{
  $ticketRoot=New-P2Fixture $ticketId
  $ticketHost=Start-P2Host $ticketRoot $ticketId -FailTicket
  $before=Send-P2Host $ticketHost 'TEST_STATE'
  $opened=Send-P2Host $ticketHost 'TEST_OPEN'
  Assert-P2 ($opened.type -eq 'SNAPSHOT') 'Ticket fault escaped control IPC instead of returning a snapshot'
  $state=Send-P2Host $ticketHost 'TEST_STATE'
  Assert-P2 ($state.payload.hostPid -eq $before.payload.hostPid -and $state.payload.guiPid -eq 0 -and $state.payload.guiState -eq 'NONE') 'Ticket fault changed Host or GUI state'
  Assert-P2 ($state.payload.guiFailures -eq 1 -and $state.payload.guiStarts -eq 0) 'Ticket failure counter/start count incorrect'
  Assert-P2 ($state.payload.eventCount -gt $before.payload.eventCount -and $state.payload.lastEventTextLen -eq 13) 'Non-secret launch-failed event was not recorded'
  $last=Send-P2Host $ticketHost 'TEST_LAST_EVENT'
  Assert-P2 ($last.type -eq 'EVENT' -and $last.payload.source -eq 'gui' -and $last.payload.text -eq 'launch-failed') 'Last event is not the generic launch-failed event'
  Assert-P2 (-not $last.payload.text.Contains([string]$ticketHost.Auth.nonce)) 'Event exposed the ticket nonce'
  Assert-P2 (-not [IO.File]::Exists((Join-Path $ticketRoot 'gui-ticket.json'))) 'Ticket exists after pre-write fault injection'
  Assert-P2 (@([IO.Directory]::GetFiles($ticketRoot,'*.secured')).Count -eq 0) 'Unprotected/temporary ticket artifact remains'
  $guiFile=Join-Path $ticketRoot 'Gui.ps1'
  $live=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"|Where-Object{([string]$_.CommandLine).Contains(' -File "'+$guiFile+'"')})
  Assert-P2 ($live.Count -eq 0) 'GUI process started despite ticket creation failure'
  Start-Sleep -Milliseconds 350
  $responsive=Send-P2Host $ticketHost 'TEST_STATE'
  Assert-P2 ($responsive.payload.tick -gt $state.payload.tick -and $responsive.payload.hostPid -eq $before.payload.hostPid -and $responsive.payload.guiState -eq 'NONE') 'Host failed to remain responsive after ticket failure'
  Stop-P2Host $ticketHost;$ticketClean=$true
  Pass-P2 'P2A-TICKET-FAILURE-CONTROLLED-NO-SECRET-NO-GUI-HOST-RESPONSIVE'
}catch{Fail-P2 'P2A-TICKET-FAILURE' $_.Exception.Message}
finally{
  if($ticketHost -and -not $ticketClean){
    try{Stop-P2Host $ticketHost;$ticketClean=$true}catch{Fail-P2 'P2A-TICKET-CLEANUP' $_.Exception.Message}
  }
  if($ticketClean -and $ticketRoot -and [IO.Directory]::Exists($ticketRoot)){
    try{Remove-P2Fixture $ticketRoot}catch{Fail-P2 'P2A-TICKET-FIXTURE-CLEANUP' $_.Exception.Message}
  }elseif($ticketRoot -and [IO.Directory]::Exists($ticketRoot)){Write-Output ('NOT CLEAN ticket fixture preserved: '+$ticketRoot)}
}

# 4. A redirected gui-pulse.txt must never be followed by GUI timer writes.
$pulseId=[guid]::NewGuid().ToString('N');$pulseRoot=$null;$pulseHost=$null;$pulseClean=$false
$pulseSentinel=Join-Path $temp ('RDC-P2-sentinel-pulse-'+$pulseId+'.txt');$pulseSentinelHash='';$pulseLinkCreated=$false
try{
  $pulseRoot=New-P2Fixture $pulseId
  [IO.File]::WriteAllText($pulseSentinel,'P2A pulse outside sentinel '+$pulseId)
  $pulseSentinelHash=(Get-FileHash -LiteralPath $pulseSentinel -Algorithm SHA256).Hash
  $pulseHost=Start-P2Host $pulseRoot $pulseId
  [void](Send-P2Host $pulseHost 'TEST_OPEN')
  [void](Wait-P2State $pulseHost {param($s) $s.guiConnected -and $s.guiPid -gt 0} 8000)
  $pulse=Join-Path $pulseRoot 'gui-pulse.txt';$watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not [IO.File]::Exists($pulse) -and $watch.ElapsedMilliseconds -lt 3500){Start-Sleep -Milliseconds 100}
  Assert-P2 ([IO.File]::Exists($pulse)) 'Initial GUI pulse was not created inside the fixture'
  [void](Send-P2Host $pulseHost 'TEST_CLOSE')
  [void](Wait-P2State $pulseHost {param($s) $s.guiPid -eq 0} 6000)
  Assert-P2 (([IO.File]::GetAttributes($pulse) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Initial pulse unexpectedly reparse'
  [IO.File]::Delete($pulse)
  try{New-Item -ItemType SymbolicLink -Path $pulse -Target $pulseSentinel -ErrorAction Stop|Out-Null;$pulseLinkCreated=$true}
  catch{NotChecked-P2 'P2A-GUI-PULSE-REPARSE' ('Windows refused a test-owned pulse symlink: '+$_.Exception.Message)}
  if($pulseLinkCreated){
    $before=Send-P2Host $pulseHost 'TEST_STATE'
    [void](Send-P2Host $pulseHost 'TEST_OPEN')
    [void](Wait-P2State $pulseHost {param($s) $s.guiConnected -and $s.guiPid -gt 0} 8000)
    Start-Sleep -Milliseconds 950
    $after=Send-P2Host $pulseHost 'TEST_STATE'
    Assert-P2 ($after.payload.tick -gt $before.payload.tick) 'Host stalled during redirected pulse test'
    Assert-P2 ((Get-FileHash -LiteralPath $pulseSentinel -Algorithm SHA256).Hash -eq $pulseSentinelHash) 'GUI pulse write followed a link and changed outside sentinel'
    Assert-P2 (([IO.File]::GetAttributes($pulse) -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Pulse redirection fixture disappeared unexpectedly'
    Pass-P2 'P2A-GUI-PULSE-REDIRECT-BLOCKED-SENTINEL-UNCHANGED'
  }
}catch{Fail-P2 'P2A-GUI-PULSE-REDIRECT' $_.Exception.Message}
finally{
  if($pulseHost -and -not $pulseClean){
    try{Stop-P2Host $pulseHost;$pulseClean=$true}catch{Fail-P2 'P2A-PULSE-HOST-CLEANUP' $_.Exception.Message}
  }
  if($pulseRoot -and [IO.Directory]::Exists($pulseRoot)){
    if($pulseClean){
      $pulse=Join-Path $pulseRoot 'gui-pulse.txt'
      if([IO.File]::Exists($pulse)){
        try{if(([IO.File]::GetAttributes($pulse) -band [IO.FileAttributes]::ReparsePoint) -ne 0){[IO.File]::Delete($pulse)}}catch{}
      }
      try{Remove-P2Fixture $pulseRoot}catch{Fail-P2 'P2A-PULSE-FIXTURE-CLEANUP' $_.Exception.Message}
    }else{Write-Output ('NOT CLEAN pulse fixture preserved without altering files: '+$pulseRoot)}
  }
  if([IO.File]::Exists($pulseSentinel)){
    try{Remove-P2Sentinel $pulseSentinel $pulseSentinelHash}catch{Fail-P2 'P2A-PULSE-SENTINEL-CLEANUP' $_.Exception.Message}
  }
}

Write-Output ('TOTAL P2A BOUNDARY TESTS: PASS='+$script:pass+' FAIL='+$script:fail+' NOT_CHECKED='+$script:notChecked)
if($script:fail -gt 0){exit 1}
