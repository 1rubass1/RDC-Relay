$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$raw=[IO.File]::ReadAllText((Join-Path $root 'Source/remote-window.ps1'))
$a=$raw.IndexOf('public sealed class RdcOwnerWordmark : Control {')
$b=$raw.IndexOf('public class RdcBufferedPanel : Panel {',$a)
if($a -lt 0 -or $b -le $a){throw 'CLASS_BOUNDARY'}
Add-Type -ReferencedAssemblies System.Drawing,System.Windows.Forms -TypeDefinition ('using System;using System.IO;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;'+$raw.Substring($a,$b-$a))
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$resources=[regex]::Matches($raw.Substring($a,$b-$a),'"([A-Za-z0-9+/=]{100,})"')
Check ($resources.Count -eq 5) 'five embedded DPI assets'
$idx=0
foreach($dpi in @(96,120,144,168,192)){
 $path=Join-Path $root ('Assets/Wordmark/rdc-wordmark-'+$dpi+'.png')
 Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq $resources[$idx].Groups[1].Value) ('exact resource '+$dpi)
 $idx++
 foreach($w in @(260,480,800,1100,1800)){
  $h=[RdcOwnerWordmark]::PreferredRowHeight($w,300,$dpi)
  $r=[RdcOwnerWordmark]::ImageBounds($w,$h,$dpi)
  Check ($r.Width -gt 0 -and $r.Height -gt 0 -and $r.Right -le $w -and $r.Bottom -le $h -and [Math]::Abs($r.Height-$r.Width*74.0/997) -le 1) ('bounded aspect DPI '+$dpi+' width '+$w)
 }
}
$control=New-Object RdcOwnerWordmark
try{
 $control.BackColor=[Drawing.Color]::FromArgb(18,20,23)
 $control.Size=[Drawing.Size]::new(800,80)
 $bitmap=New-Object Drawing.Bitmap 800,80
 try{
  $control.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,800,80))
  $orange=0;$purple=0;$white=0
  for($y=0;$y -lt 80;$y+=2){for($x=0;$x -lt 800;$x+=2){
   $c=$bitmap.GetPixel($x,$y)
   if($x -lt 320 -and $c.R -gt 150 -and $c.G -lt 150 -and $c.B -lt 100){$orange++}
   if($x -gt 360 -and $c.B -gt 100 -and $c.R -gt 80 -and $c.R -lt 170 -and $c.G -lt 120){$purple++}
   if($c.R -gt 190 -and $c.G -gt 190 -and $c.B -gt 190){$white++}
  }}
  Check ($orange -gt 100 -and $purple -gt 100 -and $white -gt 100) 'actual GDI paint retains correct colors and white cap'
 }finally{$bitmap.Dispose()}
}finally{$control.Dispose()}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$t,[ref]$e)
Check ($e.Count -eq 0) 'production GUI AST'
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Remove-Rc1OwnerWordmarkArt'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$art=[string][char]0x2588*30
$sample=($art+[Environment]::NewLine)*6+'Remote Connection'+[Environment]::NewLine+'Device ready:'
Check ((Remove-Rc1OwnerWordmarkArt $sample) -ceq ('Remote Connection'+[Environment]::NewLine+'Device ready:')) 'only startup art removed'
Check ((Remove-Rc1OwnerWordmarkArt 'ordinary status') -ceq 'ordinary status') 'ordinary text unchanged'
Check ((Remove-Rc1OwnerWordmarkArt $art) -ceq '') 'partial art suppressed'
Check ($raw.Contains('$headerDisplay=Remove-Rc1OwnerWordmarkArt $headerDisplay') -and $raw.Contains("if (-not "+'$OwnerGui'+" -and "+'$headerDisplay'+" -like '*Remote Connection*')")) 'Owner path no longer paints text logo'
'RDC_WORDMARK_PASS='+$pass
