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
Check ([RdcOwnerTrayVisual]::Semantic('Ready','working') -eq 'working' -and
 [RdcOwnerTrayVisual]::Semantic('Ready','hold') -eq 'ready' -and
 [RdcOwnerTrayVisual]::Semantic('Ready','idle') -eq 'ready') 'working animation only for Ready+working; idle and hold are static'
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
