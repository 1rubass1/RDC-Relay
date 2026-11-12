# G122 owner-approved tray v04-final binary: 49 cached Win32 ICO frames.
# This test compiles source in TEMP and uses an invisible NotifyIcon only.
# It never starts installed Host, Remote, GUI, network, or live tray.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$repo=Split-Path -Parent $PSScriptRoot
$src=Join-Path $repo 'Source'
$kit=Join-Path $repo 'Assets\TrayV04Final'
$file=Join-Path $src 'RdcTrayV04.bin'
$expected='64A4009133FFB5B7CC89BD71D85B37BA2897EE5C7A715BC3C3C014625CEC3B23'
$names=@('disconnected','connecting-a','connecting-b','authorization-a',
 'authorization-b','ready','working-static','connection-error',
 'connecting-mix-25','connecting-mix-50','connecting-mix-75',
 'authorization-mix-25','authorization-mix-50','authorization-mix-75')+
 @(1..35|ForEach-Object{'working-{0:D2}' -f $_})
$sizes=@(16,20,24,32,40,48,64)
$pass=0;$fail=0
function Check([bool]$result,[string]$description){
 if($result){$script:pass++;Write-Output ('PASS '+$description)}
 else{$script:fail++;Write-Output ('FAIL '+$description)}
}
Check ([IO.File]::Exists($file) -and
 (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ceq $expected) 'approved tray 04-final binary attested SHA'
$manifestFile=Join-Path $kit 'manifest.json'
Check ((Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash -ceq
 '27DA99E8E1F8AFC9373AE28345EBB15CC12A90FB503EE7330F5CFF83BF2A733A') 'owner-approved kit manifest immutable'
$manifest=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8|ConvertFrom-Json
Check ($manifest.version -ceq '04-final' -and @($manifest.assets).Count -eq 49 -and
 $names.Count -eq 49 -and @($manifest.animations.working.sequence).Count -eq 36) '49 asset names and 36 working frames match approved manifest'
$bytes=[IO.File]::ReadAllBytes($file)
$stream=New-Object IO.MemoryStream(,$bytes)
$reader=New-Object IO.BinaryReader($stream,[Text.Encoding]::ASCII)
try{
 $magic=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(8))
 $version=$reader.ReadUInt16()
 $count=[int]$reader.ReadByte()
 Check ($magic -ceq 'RDCTRAY4' -and $version -eq 1 -and $count -eq 49) 'versioned single runtime bundle packs 49 frames'
 $allValid=$true
 for($j=0;$j -lt $names.Count;$j++){
  $nameLength=$reader.ReadByte()
  $name=[Text.Encoding]::ASCII.GetString($reader.ReadBytes($nameLength))
  $length=$reader.ReadInt32()
  $ico=$reader.ReadBytes($length)
  $asset=@($manifest.assets|Where-Object{$_.name -ceq $names[$j]})
  if($name -cne $names[$j] -or $length -ne $ico.Length -or
   $asset.Count -ne 1 -or
   [BitConverter]::ToUInt16($ico,0) -ne 0 -or
   [BitConverter]::ToUInt16($ico,2) -ne 1 -or
   [BitConverter]::ToUInt16($ico,4) -ne 7){$allValid=$false;break}
  $sourceBytes=[IO.File]::ReadAllBytes((Join-Path $kit $asset[0].ico))
  if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$ico,[byte[]]$sourceBytes)){
   $allValid=$false;break
  }
  $last=6+16*$sizes.Count
  for($k=0;$k -lt $sizes.Count;$k++){
   $offset=6+$k*16
   $width=[int]$ico[$offset];if($width -eq 0){$width=256}
   $height=[int]$ico[$offset+1];if($height -eq 0){$height=256}
   $len=[BitConverter]::ToUInt32($ico,$offset+8)
   $position=[BitConverter]::ToUInt32($ico,$offset+12)
   if($width -ne $sizes[$k] -or $height -ne $sizes[$k] -or
    $len -lt 50 -or $position -ne $last -or
    ([long]$position+[long]$len) -gt $ico.Length -or
    $ico[$position] -ne 137 -or $ico[$position+1] -ne 80){
    $allValid=$false;break
   }
   $last=[long]$position+[long]$len
  }
  if($last -ne $ico.Length -or -not $allValid){$allValid=$false;break}
 }
 Check ($allValid -and $reader.BaseStream.Position -eq $reader.BaseStream.Length) 'all 49 bundled ICOs byte-exact to kit, 7 PNG-backed 16-64px frames each'
}finally{$reader.Dispose();$stream.Dispose()}
$code=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
Check ($code.Contains('SHA256Managed') -and $code.Contains($expected) -and
 $code.Contains('RC1_TRAY_APPROVED_SHA_MISMATCH') -and
 $code.Contains('ico[4]!=7')) 'Host checks approved kit hash and 7-frame ICO header before Win32'
Check ($code.Contains('trayFrameTimer.Interval=40') -and
 $code.Contains('trayVisual.Update(remoteSupervisor.Snapshot())') -and
 $code.Contains('trayFrameTimer.Dispose()') -and
 $code.Contains('trayVisual.Dispose()')) 'Host uses cached 40ms drawing timer and disposes icon resources'
$dll=Join-Path $env:TEMP ('RdcG122FinalVisual-'+[Guid]::NewGuid().ToString('N')+'.dll')
$csc=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
 (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|
 Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
$inputs=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerRuntime.cs')|
 ForEach-Object{Join-Path $src $_}
& $csc /nologo /target:library ('/out:'+$dll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll $inputs
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){throw 'G122_TRAY_FINAL_CSHARP_COMPILE_FAILED'}
Add-Type -Path $dll
# All three animation families must finish their current complete cycles before
# a visual change, even to Fault/Disconnected. Authoritative Host and tooltip
# states update immediately; only decorative icon frames are deferred.
$green=[IO.File]::ReadAllBytes((Join-Path $kit 'ICO\connecting-a.ico'))
$ready=[IO.File]::ReadAllBytes((Join-Path $kit 'ICO\ready.ico'))
Check ([Linq.Enumerable]::SequenceEqual([byte[]]$green,[byte[]]$ready)) 'connecting green-bottom A and Ready icons are byte-identical'
$gate=New-Object RdcOwnerTrayPhaseGate
Check ($gate.Update('connecting',$true,0) -and $gate.Visible -eq 'connecting' -and
 $gate.WaitingUntilMs -eq -1) 'initial Connecting state is visible immediately'
Check (-not $gate.Update('ready',$true,720) -and $gate.Visible -eq 'connecting' -and
 $gate.Latest -eq 'ready' -and $gate.WaitingUntilMs -eq 1600) 'Ready at color-blend frame waits for full green-bottom 1600ms seam'
Check (-not $gate.Update('ready',$true,1400) -and $gate.WaitingUntilMs -eq 1600 -and
 -not $gate.Advance($true,1599) -and $gate.Visible -eq 'connecting') 'repeated Ready snapshots do not reset the deadline or cut the last fade'
Check ($gate.Advance($true,1600) -and $gate.Visible -eq 'ready' -and
 $gate.WaitingUntilMs -eq -1 -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1600) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('ready',$true,0) -eq 'ready') '40ms timer releases at exact pixel-identical A to Ready boundary'
$late=New-Object RdcOwnerTrayPhaseGate
[void]$late.Update('connecting',$true,0)
Check (-not $late.Update('ready',$true,1710) -and
 $late.WaitingUntilMs -eq 3200 -and
 -not $late.Advance($true,3199) -and $late.Advance($true,3200)) 'late Ready signal waits for end of current, not already-ended, cycle'
$auth=New-Object RdcOwnerTrayPhaseGate
[void]$auth.Update('connecting',$true,0)
Check (-not $auth.Update('auth',$true,760) -and
 $auth.WaitingUntilMs -eq 1600 -and $auth.Advance($true,1600) -and
 $auth.Visible -eq 'auth') 'Connecting to Authorization completes cycle before changing visual family'
Check (-not $auth.Update('ready',$true,920) -and
 $auth.WaitingUntilMs -eq 1600 -and $auth.Advance($true,1600) -and
 $auth.Visible -eq 'ready') 'Authorization to Ready also finishes full cycle'
$cancel=New-Object RdcOwnerTrayPhaseGate
[void]$cancel.Update('connecting',$true,0)
[void]$cancel.Update('ready',$true,900)
Check (-not $cancel.Update('connecting',$true,950) -and
 $cancel.WaitingUntilMs -eq -1 -and $cancel.Visible -eq 'connecting' -and
 -not $cancel.Advance($true,1600)) 'reverted Connecting cancels outdated pending Ready'
# Snapshot may change many times inside one cycle. No FIFO: at the boundary
# select the last, authoritative state, even when it becomes Fault or Offline.
[void]$cancel.Update('ready',$true,1800)
Check (-not $cancel.Update('fault',$true,1900) -and
 $cancel.WaitingUntilMs -eq 3200 -and $cancel.Latest -eq 'fault' -and
 $cancel.Visible -eq 'connecting') 'Fault updates latest immediately but does not cut connecting animation'
Check (-not $cancel.Update('offline',$true,2100) -and
 $cancel.Latest -eq 'offline' -and $cancel.WaitingUntilMs -eq 3200 -and
 -not $cancel.Advance($true,3199) -and $cancel.Advance($true,3200) -and
 $cancel.Visible -eq 'offline') 'latest Offline replaces superseded Ready/Fault at completed cycle seam'
Check ([RdcOwnerTrayPhaseGate]::CycleDurationMs('connecting') -eq 1600 -and
 [RdcOwnerTrayPhaseGate]::CycleDurationMs('auth') -eq 1600 -and
 [RdcOwnerTrayPhaseGate]::CycleDurationMs('working') -eq 1800 -and
 [RdcOwnerTrayPhaseGate]::CycleDurationMs('ready') -eq 0 -and
 [RdcOwnerTrayPhaseGate]::CycleDurationMs('fault') -eq 0 -and
 [RdcOwnerTrayPhaseGate]::CycleDurationMs('offline') -eq 0) 'all three approved animation cycles have exact durations, static states do not wait'
# Exhaustive animated source to every distinct semantic destination:
# no new event cuts a cycle halfway, regardless of operation order.
$states=@('connecting','auth','working','ready','fault','offline')
foreach($from in @('connecting','auth','working')){
 $period=[RdcOwnerTrayPhaseGate]::CycleDurationMs($from)
 foreach($to in ($states | Where-Object{$_ -ne $from})){
  $transition=New-Object RdcOwnerTrayPhaseGate
  $created=$transition.Update($from,$true,0)
  $held=-not $transition.Update($to,$true,40)
  $before=-not $transition.Advance($true,$period-1)
  $boundary=$transition.Advance($true,$period)
  Check ($created -and $held -and $before -and $boundary -and
   $transition.WaitingUntilMs -eq -1 -and
   $transition.Visible -eq $to -and $transition.Latest -eq $to) (
   $from+' completes '+$period+'ms cycle before '+$to)
 }
}
# Concrete incident: a short purple Working signal must produce a full
# purple 36-frame pulse before visually returning to green Ready.
$pulse=New-Object RdcOwnerTrayPhaseGate
Check ($pulse.Update('ready',$true,0) -and
 $pulse.Update('working',$true,0) -and $pulse.Visible -eq 'working') 'idle green Ready starts purple Working animation at frame zero'
Check (-not $pulse.Update('ready',$true,80) -and
 $pulse.Visible -eq 'working' -and $pulse.Latest -eq 'ready' -and
 $pulse.WaitingUntilMs -eq 1800) '80ms action does not truncate 1800ms purple Working animation'
Check (-not $pulse.Update('ready',$true,500) -and
 -not $pulse.Advance($true,1750) -and
 [RdcOwnerTrayVisual]::Frame('working',$true,1750) -eq 'working-35' -and
 -not $pulse.Advance($true,1799)) 'purple working frame 35 remains until full final 50ms ends'
Check ($pulse.Advance($true,1800) -and $pulse.Visible -eq 'ready' -and
 $pulse.WaitingUntilMs -eq -1) 'green Ready appears only at completed 36-frame Working boundary'
# If a tool is still executing at the end, start another full animation cycle.
$continuous=New-Object RdcOwnerTrayPhaseGate
[void]$continuous.Update('working',$true,0)
Check (-not $continuous.Update('working',$true,1500) -and
 -not $continuous.Advance($true,1800) -and
 $continuous.Visible -eq 'working' -and
 $continuous.WaitingUntilMs -eq -1) 'working still active at cycle seam continues next full pulse'
Check (-not $continuous.Update('ready',$true,1900) -and
 $continuous.WaitingUntilMs -eq 3600 -and
 -not $continuous.Advance($true,3599) -and
 $continuous.Advance($true,3600) -and $continuous.Visible -eq 'ready') 'after repeated Working loop, exit waits until next full 3600ms boundary'
# New signals do not restart a deadline; the latest one replaces any older
# pending target, not an obsolete queue of states.
$burst=New-Object RdcOwnerTrayPhaseGate
[void]$burst.Update('working',$true,0)
[void]$burst.Update('ready',$true,40)
[void]$burst.Update('auth',$true,300)
Check (-not $burst.Update('fault',$true,350) -and $burst.Latest -eq 'fault' -and
 $burst.WaitingUntilMs -eq 1800 -and
 -not $burst.Advance($true,1799) -and $burst.Advance($true,1800) -and
 $burst.Visible -eq 'fault') 'burst of purple Working/Ready/Auth/Fault signals releases latest only at 1800ms'
$static=New-Object RdcOwnerTrayPhaseGate
[void]$static.Update('fault',$true,0)
Check ($static.Update('connecting',$true,5) -and
 $static.Visible -eq 'connecting' -and $static.WaitingUntilMs -eq -1) 'static Fault starts Connecting animation immediately'
$cancelWork=New-Object RdcOwnerTrayPhaseGate
[void]$cancelWork.Update('working',$true,0)
[void]$cancelWork.Update('ready',$true,80)
Check (-not $cancelWork.Update('working',$true,110) -and
 $cancelWork.WaitingUntilMs -eq -1 -and
 -not $cancelWork.Advance($true,1800) -and
 $cancelWork.Visible -eq 'working') 'return to active Working during its pulse cancels obsolete Ready signal'
$reduced=New-Object RdcOwnerTrayPhaseGate
[void]$reduced.Update('connecting',$false,0)
Check ($reduced.Update('ready',$false,760) -and $reduced.Visible -eq 'ready') 'Windows reduced-motion mode switches to Ready without waiting'
[void]$reduced.Update('connecting',$true,900)
[void]$reduced.Update('ready',$true,940)
Check ($reduced.Advance($false,960) -and $reduced.Visible -eq 'ready') 'disabling animations releases a pending transition immediately'
Check ($code.Contains('phaseGate.Update(next,animate,phase.ElapsedMilliseconds)') -and
 $code.Contains('phaseGate.Advance(animate,phase.ElapsedMilliseconds)') -and
 $code.Contains('ShortStatus(next)')) 'production uses phase gate on both 250ms snapshots and 40ms frames, tooltip is immediate'
Check ([RdcOwnerTrayVisual]::Semantic('Ready','working') -eq 'working' -and
 [RdcOwnerTrayVisual]::Semantic('Ready','hold') -eq 'working' -and
 [RdcOwnerTrayVisual]::Semantic('Ready','idle') -eq 'ready') 'tray maps shared active and adaptive hold to purple Working, idle to green Ready'
Check ([RdcOwnerTrayVisual]::Semantic('Fault','working') -eq 'fault' -and
 [RdcOwnerTrayVisual]::Semantic('Disconnected','working') -eq 'offline' -and
 [RdcOwnerTrayVisual]::Semantic('AuthPending','working') -eq 'auth' -and
 [RdcOwnerTrayVisual]::Semantic('Connecting','idle') -eq 'connecting' -and
 [RdcOwnerTrayVisual]::Semantic('Reconnecting','working') -eq 'connecting') 'status precedence obeys manifest; auth/connection colors are not mixed'
Check ([RdcOwnerTrayVisual]::Frame('connecting',$true,0) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,680) -eq 'connecting-mix-25' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,720) -eq 'connecting-mix-50' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,760) -eq 'connecting-mix-75' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,800) -eq 'connecting-b' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1480) -eq 'connecting-mix-75' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1520) -eq 'connecting-mix-50' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1560) -eq 'connecting-mix-25' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1600) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('auth',$true,720) -eq 'authorization-mix-50') 'approved 1600ms connecting/authorization frames and reverse fades'
Check ([RdcOwnerTrayVisual]::Frame('working',$true,0) -eq 'working-static' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,50) -eq 'working-01' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,900) -eq 'working-18' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,1750) -eq 'working-35' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,1800) -eq 'working-static') '36-frame working loop tracks approved 1800ms/50ms schedule'
Check ([RdcOwnerTrayVisual]::Frame('connecting',$false,810) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('auth',$false,810) -eq 'authorization-a' -and
 [RdcOwnerTrayVisual]::Frame('working',$false,810) -eq 'working-static' -and
 [RdcOwnerTrayVisual]::Frame('offline',$true,0) -eq 'disconnected' -and
 [RdcOwnerTrayVisual]::Frame('fault',$true,0) -eq 'connection-error') 'reduced motion uses manifest fallbacks, offline/fault remain static'
$notify=New-Object Windows.Forms.NotifyIcon
$visual=$null
try{
 $visual=[RdcOwnerTrayVisual]::Load($src,$notify)
 Check ($null -ne $visual) '49 cached Win32 icons load into invisible real NotifyIcon'
 foreach($state in @('Disconnected','Connecting','AuthPending','Ready','Fault')){
  $values=New-Object 'System.Collections.Generic.Dictionary[string,object]'
  $values.Add('state',$state);$values.Add('toolActivity','idle');$values.Add('fake',$false)
  $visual.Update($values)
  Check ($null -ne $notify.Icon -and $notify.Icon.Size.Width -ge 16 -and
   $notify.Text.StartsWith('RDC Relay RC1 | ')) ('valid frame and stable tooltip: '+$state)
 }
 $live=New-Object 'System.Collections.Generic.Dictionary[string,object]'
 $live.Add('state','Ready');$live.Add('toolActivity','working');$live.Add('fake',$false)
 $visual.Update($live)
 Check ($notify.Text.Contains('Выполнение') -and $notify.Icon -ne $null) 'Ready+working selects activity pulse'
 $live['toolActivity']='hold'
 $visual.Update($live)
 Check ($notify.Text.Contains('Ожидание следующего вызова') -and $notify.Icon -ne $null) 'Ready+hold keeps purple animated semantic but tooltip admits no running-tool proof'
 $live['toolActivity']='idle'
 $visual.Update($live)
 Check ($notify.Text.Contains('Готов к работе') -and $notify.Icon -ne $null) 'Ready+idle restores accurate tooltip without waiting for animation'
 # Hold must not restart/cancel an already playing purple loop: its semantic
 # identity matches actual Working, even though tooltip explicitly differs.
 $holdGate=New-Object RdcOwnerTrayPhaseGate
 [void]$holdGate.Update('working',$true,0)
 Check (-not $holdGate.Update([RdcOwnerTrayVisual]::Semantic('Ready','hold'),$true,900) -and
  $holdGate.Visible -eq 'working' -and $holdGate.WaitingUntilMs -eq -1 -and
  -not $holdGate.Advance($true,1800)) 'Working to Hold preserves same animation phase, no new cycle or early green flash'
 Check (-not $holdGate.Update([RdcOwnerTrayVisual]::Semantic('Ready','idle'),$true,1900) -and
  $holdGate.WaitingUntilMs -eq 3600 -and
  -not $holdGate.Advance($true,3599) -and $holdGate.Advance($true,3600) -and
  $holdGate.Visible -eq 'ready') 'shared hold expiry changes to Ready after full last purple animation loop'
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RdcG122FinalGdi {
 [DllImport("user32.dll")] public static extern int GetGuiResources(IntPtr process,int flag);
}
'@
 $proc=[Diagnostics.Process]::GetCurrentProcess()
 $gdiBefore=[RdcG122FinalGdi]::GetGuiResources($proc.Handle,0)
 for($n=0;$n -lt 500;$n++){
  $live['state']=if(($n%2) -eq 0){'Ready'}else{'Fault'}
  $live['toolActivity']=if(($n%3) -eq 0){'working'}else{'idle'}
  $visual.Update($live)
  $visual.Advance()
 }
 $gdiAfter=[RdcG122FinalGdi]::GetGuiResources($proc.Handle,0)
 Check ($gdiBefore -ge 0 -and $gdiAfter-$gdiBefore -le 5) ('500 frames keep GDI count stable: '+$gdiBefore+' to '+$gdiAfter)
 $scratch=Join-Path $env:TEMP ('RDC-G122-FINAL-TAMPER-'+[Guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($scratch)
 try{
  $modified=New-Object byte[] $bytes.Length
  [Array]::Copy($bytes,$modified,$bytes.Length)
  $modified[90]=$modified[90] -bxor 1
  [IO.File]::WriteAllBytes((Join-Path $scratch 'RdcTrayV04.bin'),$modified)
  $denied=$false
  try{
   $untrusted=[RdcOwnerTrayVisual]::Load($scratch,$notify)
   if($untrusted){$untrusted.Dispose()}
  }catch [IO.InvalidDataException]{$denied=$_.Exception.Message -ceq 'RC1_TRAY_APPROVED_SHA_MISMATCH'}
  Check $denied 'modified bundle denied before icon is passed to Win32'
 }finally{
  [IO.File]::Delete((Join-Path $scratch 'RdcTrayV04.bin'))
  [IO.Directory]::Delete($scratch,$false)
 }
}finally{
 $notify.Visible=$false
 $notify.Dispose()
 if($visual){$visual.Dispose()}
 try{[IO.File]::Delete($dll)}catch{}
}
Write-Output ('RC1_TRAY_V04_FINAL_VISUAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
