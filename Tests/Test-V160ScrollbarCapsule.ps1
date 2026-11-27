$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$raw=[IO.File]::ReadAllText((Join-Path $root 'Source/remote-window.ps1'))
$anchor=$raw.IndexOf('public class RdcOverlayScrollBar : Control {')
$a=$raw.LastIndexOf("Add-Type -TypeDefinition @'",$anchor)+("Add-Type -TypeDefinition @'").Length
$b=$raw.IndexOf("'@ -ReferencedAssemblies",$anchor)
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing,System.Windows.Forms -TypeDefinition $raw.Substring($a,$b-$a)
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$geometry=[RdcOverlayScrollBar].GetMethod('Geometry',$flags)
$round=[RdcOverlayScrollBar].GetMethod('Rounded',$flags)
$pass=0
function Check([bool]$ok,[string]$msg){if(!$ok){throw ('FAIL '+$msg)};$script:pass++;'PASS '+$msg}
$s=New-Object RdcOverlayScrollBar
try{
 $s.Vertical=$true
 $script:position=0
 $s.VerticalMetricsProvider=[Func[int[]]]{return ,([int[]]@(10000,30,$script:position,9970))}
 foreach($w in @(13,17,21,25,34)){
  foreach($h in @(8,16,32,44,60,90,300)){
   $s.Size=[Drawing.Size]::new($w,$h)
   $v=[object[]]@([Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty)
   $script:position=0
   $geometry.Invoke($s,$v)
   $track=$v[2];$thumb=$v[3]
   Check ($thumb.Width -eq $thumb.Height -and $track.Contains($thumb) -and $track.Bottom -le $h -and $track.Right -le $w) ('circle within vertical track '+$w+'x'+$h)
   $script:position=9970
   $geometry.Invoke($s,$v)
   Check ($v[3].Bottom -eq $v[2].Bottom) 'end offset maps to track end'
  }
 }
 foreach($size in @(8,13,17,21)){
  foreach($r in @([Drawing.Rectangle]::new(0,0,$size,$size),[Drawing.Rectangle]::new(0,0,$size,$size*3),[Drawing.Rectangle]::new(0,0,$size*3,$size))){
   $p=$round.Invoke($s,@($r,[single]($size/2.0)))
   try{
    Check ($p.IsVisible([single]($r.Width/2.0),[single]($r.Height/2.0)) -and !$p.IsVisible([single]0.1,[single]0.1) -and !$p.IsVisible([single]($r.Right-0.1),[single]($r.Bottom-0.1))) ('rounded path center and corners '+$r.Width+'x'+$r.Height)
   }finally{$p.Dispose()}
  }
 }
 $s.Size=[Drawing.Size]::new(17,60);$script:position=0
 $v=[object[]]@([Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty)
 $geometry.Invoke($s,$v);$t=$v[3]
 $bmp=New-Object Drawing.Bitmap 17,60
 try{
  $s.DrawToBitmap($bmp,[Drawing.Rectangle]::new(0,0,17,60))
  $center=$bmp.GetPixel($t.Left+[int][Math]::Floor($t.Width/2),$t.Top+[int][Math]::Floor($t.Height/2))
  $corner=$bmp.GetPixel($t.Left,$t.Top)
  Check ($center.ToArgb() -eq [Drawing.Color]::FromArgb(191,118,67).ToArgb() -and $corner.ToArgb() -ne $center.ToArgb()) 'actual paint orange circle with non-orange corner'
 }finally{$bmp.Dispose()}
 $s.VerticalMetricsProvider=$null;$s.Vertical=$false
 foreach($w in @(8,17,32,44,60,300)){
  $s.Size=[Drawing.Size]::new($w,17);$geometry.Invoke($s,$v)
  Check ($v[3].Width -ge $v[3].Height -and $v[2].Contains($v[3])) ('horizontal track bounds '+$w)
 }
 $s.Vertical=$true;$s.DecorativeFullTrack=$true;$s.Size=[Drawing.Size]::new(17,60);$geometry.Invoke($s,$v)
 Check ($v[2] -eq $v[3]) 'decorative full track retained'
}finally{$s.Dispose()}
'RDC_SCROLLBAR_CAPSULE_PASS='+$pass
