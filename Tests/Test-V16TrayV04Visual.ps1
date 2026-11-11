# G122: owner-approved tray v04 binary, semantic state, cached Win32 icons.
# Compiles source in TEMP, creates ONLY an invisible NotifyIcon. No Host/GUI/
# Remote process, production tray, installed app, network or registry changes.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$repo=Split-Path -Parent $PSScriptRoot
$src=Join-Path $repo 'Source'
$file=Join-Path $src 'RdcTrayV04.bin'
$expected='607D271A09983A407F3E8CC8560A93DC59385C18DCEC08ECA1740318C2B1AD59'
$names=@('offline','connecting-a','connecting-b','auth-a','auth-b','ready','fault')+
 (@(0..9)|ForEach-Object{'work-{0:D2}' -f $_})+
 @(foreach($state in @('connecting','auth')){
  foreach($direction in @('ab','ba')){
   foreach($percent in @(25,50,75)){"$state-$direction-$percent"}
  }
 })
$sizes=@(16,20,24,32,40,48,64,256)
$pass=0;$fail=0
function Check([bool]$result,[string]$description){
 if($result){$script:pass++;Write-Output ('PASS '+$description)}
 else{$script:fail++;Write-Output ('FAIL '+$description)}
}
Check ([IO.File]::Exists($file) -and
 (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ceq $expected) 'approved 04 binary source exact SHA-256'
$bytes=[IO.File]::ReadAllBytes($file)
$stream=New-Object IO.MemoryStream(,$bytes)
$reader=New-Object IO.BinaryReader($stream,[Text.Encoding]::ASCII)
try{
 $magic=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(8))
 $version=$reader.ReadUInt16()
 $count=[int]$reader.ReadByte()
 Check ($magic -ceq 'RDCTRAY4' -and $version -eq 1 -and $count -eq 29) 'versioned bundle contains 29 unique precomputed icon frames'
 $valid=$true
 for($j=0;$j -lt $names.Count;$j++){
  $nameLength=$reader.ReadByte()
  $name=[Text.Encoding]::ASCII.GetString($reader.ReadBytes($nameLength))
  $length=$reader.ReadInt32()
  $ico=$reader.ReadBytes($length)
  if($name -cne $names[$j] -or $length -ne $ico.Length -or
     [BitConverter]::ToUInt16($ico,0) -ne 0 -or
     [BitConverter]::ToUInt16($ico,2) -ne 1 -or
     [BitConverter]::ToUInt16($ico,4) -ne 8){$valid=$false;break}
  for($k=0;$k -lt $sizes.Count;$k++){
   $offset=6+$k*16
   $width=[int]$ico[$offset];if($width -eq 0){$width=256}
   $height=[int]$ico[$offset+1];if($height -eq 0){$height=256}
   $size=[BitConverter]::ToUInt32($ico,$offset+8)
   $position=[BitConverter]::ToUInt32($ico,$offset+12)
   if($width -ne $sizes[$k] -or $height -ne $sizes[$k] -or
      $size -lt 50 -or ($position+$size) -gt $ico.Length -or
      $ico[$position] -ne 137 -or $ico[$position+1] -ne 80){
    $valid=$false;break
   }
  }
  if(-not $valid){break}
 }
 Check ($valid -and $reader.BaseStream.Position -eq $reader.BaseStream.Length) 'all 29 ICO frames contain 8 intact PNG-backed 16–256px sizes, with no extra bytes'
}finally{$reader.Dispose();$stream.Dispose()}
$code=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
Check ($code.Contains('SHA256Managed') -and $code.Contains($expected) -and
 $code.Contains('RC1_TRAY_APPROVED_SHA_MISMATCH')) 'Host rejects altered/unapproved icon bundles'
Check ($code.Contains('trayFrameTimer.Interval=40') -and
 $code.Contains('trayVisual.Update(remoteSupervisor.Snapshot())') -and
 $code.Contains('trayFrameTimer.Dispose()') -and
 $code.Contains('trayVisual.Dispose()')) 'Host uses 40ms cached motion timer and reliably disposes resources'
Check (-not $code.Contains('tray.Icon=SystemIcons.Information; // deliberately not installed')) 'Host no longer uses the old placeholder icon in approved package'
$dll=Join-Path $env:TEMP ('RdcG122Visual-'+[Guid]::NewGuid().ToString('N')+'.dll')
$csc=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
 (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'))|
 Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
$inputs=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerRuntime.cs')|
 ForEach-Object{Join-Path $src $_}
& $csc /nologo /target:library ('/out:'+$dll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll $inputs
if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){throw 'G122_HOST_CSHARP_COMPILE_FAILED'}
Add-Type -Path $dll
Check ([RdcOwnerTrayVisual]::Semantic('Ready','working') -eq 'working' -and
 [RdcOwnerTrayVisual]::Semantic('Ready','hold') -eq 'ready' -and
 [RdcOwnerTrayVisual]::Semantic('Ready','idle') -eq 'ready') 'toolActivity working only; hold and idle show stable Ready'
Check ([RdcOwnerTrayVisual]::Semantic('Fault','working') -eq 'fault' -and
 [RdcOwnerTrayVisual]::Semantic('Disconnected','working') -eq 'offline' -and
 [RdcOwnerTrayVisual]::Semantic('AuthPending','working') -eq 'auth') 'link-state fault/disconnect/auth override stale tool activity'
Check ([RdcOwnerTrayVisual]::Semantic('Connecting','idle') -eq 'connecting' -and
 [RdcOwnerTrayVisual]::Semantic('Reconnecting','working') -eq 'connecting') 'connecting and reconnecting share approved orange-gray animation'
Check ([RdcOwnerTrayVisual]::Frame('connecting',$true,640) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,680) -eq 'connecting-ab-25' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,720) -eq 'connecting-ab-50' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,760) -eq 'connecting-ab-75' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,800) -eq 'connecting-b' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1480) -eq 'connecting-ba-25' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1520) -eq 'connecting-ba-50' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1560) -eq 'connecting-ba-75' -and
 [RdcOwnerTrayVisual]::Frame('connecting',$true,1600) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('auth',$true,720) -eq 'auth-ab-50') 'approved 160ms connecting/auth color fades and 800ms phase alternation'
Check ([RdcOwnerTrayVisual]::Frame('working',$true,0) -eq 'work-09' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,900) -eq 'work-00' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,1800) -eq 'work-09' -and
 [RdcOwnerTrayVisual]::Frame('working',$true,450) -eq
 [RdcOwnerTrayVisual]::Frame('working',$true,1350)) 'working center follows approved 100→45→100% eased 1800ms pulse'
Check ([RdcOwnerTrayVisual]::Frame('connecting',$false,810) -eq 'connecting-a' -and
 [RdcOwnerTrayVisual]::Frame('auth',$false,810) -eq 'auth-a' -and
 [RdcOwnerTrayVisual]::Frame('working',$false,810) -eq 'work-09') 'Windows reduced-motion mode uses stable approved frames'
$notify=New-Object Windows.Forms.NotifyIcon
$visual=$null
try {
 $visual=[RdcOwnerTrayVisual]::Load($src,$notify)
 Check ($null -ne $visual) 'approved ICO frames load into actual WinForms NotifyIcon'
 foreach($state in @('Disconnected','Connecting','AuthPending','Ready','Fault')){
  $values=New-Object 'System.Collections.Generic.Dictionary[string,object]'
  $values.Add('state',$state);$values.Add('toolActivity','idle');$values.Add('fake',$false)
  $visual.Update($values)
  Check ($null -ne $notify.Icon -and $notify.Icon.Size.Width -ge 16 -and
   $notify.Text.StartsWith('RDC Relay RC1 | ')) ('NotifyIcon uses valid icon and stable state tooltip: '+$state)
 }
 $live=New-Object 'System.Collections.Generic.Dictionary[string,object]'
 $live.Add('state','Ready');$live.Add('toolActivity','working');$live.Add('fake',$false)
 $visual.Update($live)
 Check ($notify.Text.Contains('Выполнение') -and $notify.Icon -ne $null) 'Ready+working selects actual animated frame and activity tooltip'
 # Exercise many cached Icon substitutions without making the test tray visible.
 # The OS GDI handle budget must not grow with frame count.
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RdcG122Gdi {
 [DllImport("user32.dll")] public static extern int GetGuiResources(IntPtr process,int flag);
}
'@
 $proc=[Diagnostics.Process]::GetCurrentProcess()
 $gdiBefore=[RdcG122Gdi]::GetGuiResources($proc.Handle,0)
 for($n=0;$n -lt 500;$n++){
  $live['state']=if(($n%2) -eq 0){'Ready'}else{'Fault'}
  $live['toolActivity']=if(($n%3) -eq 0){'working'}else{'idle'}
  $visual.Update($live)
  $visual.Advance()
 }
 $gdiAfter=[RdcG122Gdi]::GetGuiResources($proc.Handle,0)
 Check ($gdiBefore -ge 0 -and $gdiAfter-$gdiBefore -le 5) ('500 cached frame substitutions do not grow GDI object count: '+$gdiBefore+' to '+$gdiAfter)
 # A copied, altered bundle must be rejected before any icon reaches Win32.
 $scratch=Join-Path $env:TEMP ('RDC-G122-TRAY-TAMPER-'+[Guid]::NewGuid().ToString('N'))
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
  }catch [IO.InvalidDataException]{
   $denied=$_.Exception.Message -ceq 'RC1_TRAY_APPROVED_SHA_MISMATCH'
  }
  Check $denied 'tampered tray binary fails attestation before Win32 Icon loading'
 }finally{
  [IO.File]::Delete((Join-Path $scratch 'RdcTrayV04.bin'))
  [IO.Directory]::Delete($scratch,$false)
 }
}finally{
 $notify.Visible=$false
 $notify.Dispose()
 if($visual){$visual.Dispose()}
}
try{[IO.File]::Delete($dll)}catch{}
Write-Output ('RC1_TRAY_V04_VISUAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
