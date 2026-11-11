# G118: approved app/shortcut/installer v04 icon, no tray status icon changes.
# Reads only source/assets/manifest and optionally compiled private EXEs.
param(
 [string]$SetupPath='',
 [string]$LauncherPath=''
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$repo=Split-Path -Parent $PSScriptRoot
$expectedSha='6421F60D00030F21F958B81118B36ACCF08155CE2A887EEEB329B60044A06FA8'
$sizes=@(16,20,24,30,32,36,40,48,60,64,72,80,96,120,128,144,192,256)
$pass=0;$fail=0
function Check([bool]$yes,[string]$label){
 if($yes){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$asset=Join-Path $repo 'Assets\RDCRelay.ico'
$runtime=Join-Path $repo 'Source\RDCRelay.ico'
Check ([IO.File]::Exists($asset) -and (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash -ceq $expectedSha) 'approved design 04 asset hash exact'
Check ([IO.File]::Exists($runtime) -and (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash -ceq $expectedSha) 'actual GUI and shortcut runtime icon hash exact'
$bytes=[IO.File]::ReadAllBytes($runtime)
$valid=$bytes.Length -gt 300 -and [BitConverter]::ToUInt16($bytes,0) -eq 0 -and
 [BitConverter]::ToUInt16($bytes,2) -eq 1 -and [BitConverter]::ToUInt16($bytes,4) -eq $sizes.Count
if($valid){
 $last=6+16*$sizes.Count
 for($i=0;$i -lt $sizes.Count;$i++){
  $off=6+16*$i
  $width=[int]$bytes[$off];if($width -eq 0){$width=256}
  $height=[int]$bytes[$off+1];if($height -eq 0){$height=256}
  $length=[BitConverter]::ToUInt32($bytes,$off+8)
  $position=[BitConverter]::ToUInt32($bytes,$off+12)
  if($width -ne $sizes[$i] -or $height -ne $sizes[$i] -or
   $length -lt 8 -or $position -lt $last -or
   ([long]$position+[long]$length) -gt $bytes.Length){$valid=$false;break}
  if($bytes[$position] -ne 137 -or $bytes[$position+1] -ne 80 -or
   $bytes[$position+2] -ne 78 -or $bytes[$position+3] -ne 71){$valid=$false;break}
  $last=[long]$position+[long]$length
 }
}
Check $valid 'ICO is an intact Windows icon with exactly 18 approved PNG frames'
$manifest=Get-Content -LiteralPath (Join-Path $repo 'Source\update-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$entry=@($manifest.files|Where-Object{$_.name -ceq 'RDCRelay.ico'})
Check ($entry.Count -eq 1 -and $entry[0].sha256 -ceq $expectedSha) 'stable update manifest tracks new icon and cannot install mismatched artwork'
$builder=[IO.File]::ReadAllText((Join-Path $repo 'Scripts\build-rc1-full.ps1'),[Text.Encoding]::UTF8)
$release=[IO.File]::ReadAllText((Join-Path $repo 'Scripts\build-release.ps1'),[Text.Encoding]::UTF8)
$gui=[IO.File]::ReadAllText((Join-Path $repo 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$upgrader=[IO.File]::ReadAllText((Join-Path $repo 'Installer\Rc1ManualUpgrade.cs'),[Text.Encoding]::UTF8)
$compilerIconArg="('/win32icon:'+(Join-Path "+'$payload'+ " 'RDCRelay.ico'))"
Check (@([regex]::Matches($builder,[regex]::Escape($compilerIconArg))).Count -eq 2) 'private RC1 compiler embeds exactly one approved native icon in Setup EXE and Launcher EXE'
Check ($builder.Contains('RC1_APPROVED_APP_ICON_V04_MISMATCH') -and
 $release.Contains('RDC_RELEASE_APPROVED_APP_ICON_V04_MISMATCH') -and
 -not $release.Contains("& (Join-Path "+'$assetsDir'+ " 'build-icon.ps1')")) 'both builders reject mismatches and release builder no longer regenerates old icon'
Check ($upgrader.Contains('SetShortcut(newLink,"IconLocation",Path.Combine(release,"Source","RDCRelay.ico")+",0")') -and
 $gui.Contains('$form.Icon = New-Object Drawing.Icon($iconPath)')) 'Owner shortcut and GUI already use same runtime ICO'
Check ($builder.Contains("'RDCRelay.ico'") -and
 $builder.Contains('owner-source-manifest.json')) 'private manifest still hashes app icon in the exact payload'
function Test-PeIcon([string]$path,[string]$name){
 if(-not [IO.File]::Exists($path)){Check $false ($name+' EXE exists');return}
 $icon=$null;$frameStream=$null;$actualBmp=$null;$refBmp=$null
 try{
  # GDI+ Icon.ToBitmap() on PNG-backed .ico can use a legacy/masked
  # rendering path. Compare the Windows-extracted PE icon instead against
  # the exact 32x32 PNG frame embedded inside the owner-approved ICO.
  $frameOffset=6+4*16
  $frameLength=[BitConverter]::ToUInt32($bytes,$frameOffset+8)
  $frameStart=[BitConverter]::ToUInt32($bytes,$frameOffset+12)
  $frameBytes=New-Object byte[] $frameLength
  [Array]::Copy($bytes,[long]$frameStart,$frameBytes,0,[long]$frameLength)
  $frameStream=New-Object IO.MemoryStream(,$frameBytes)
  $refBmp=New-Object Drawing.Bitmap($frameStream)
  $icon=[Drawing.Icon]::ExtractAssociatedIcon($path)
  $actualBmp=$icon.ToBitmap()
  $same=$actualBmp.Width -eq 32 -and $actualBmp.Height -eq 32 -and
   $refBmp.Width -eq 32 -and $refBmp.Height -eq 32
  $nonTransparent=0
  if($same){
   for($y=0;$y -lt 32;$y++){
    for($x=0;$x -lt 32;$x++){
     $a=$actualBmp.GetPixel($x,$y).ToArgb()
     $b=$refBmp.GetPixel($x,$y).ToArgb()
     if($a -ne $b){$same=$false;break}
     if($actualBmp.GetPixel($x,$y).A -ne 0){$nonTransparent++}
    }
    if(-not $same){break}
   }
  }
  Check ($same -and $nonTransparent -gt 20) ($name+' Win32 native PE icon pixel-exact to v04 32px PNG frame')
 }catch{Check $false ($name+' native PE icon check failed: '+$_.Exception.Message)}
 finally{
  if($refBmp){$refBmp.Dispose()}
  if($actualBmp){$actualBmp.Dispose()}
  if($frameStream){$frameStream.Dispose()}
  if($icon){$icon.Dispose()}
 }
}
if($SetupPath){Test-PeIcon ([IO.Path]::GetFullPath($SetupPath)) 'Setup'}
if($LauncherPath){Test-PeIcon ([IO.Path]::GetFullPath($LauncherPath)) 'Launcher'}
Write-Output ('RC1_APP_ICON_V04_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0