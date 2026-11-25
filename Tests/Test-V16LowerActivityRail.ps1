# Owner G122: the compact lower main-pane vertical bar is decorative.
# Compile and paint actual production WinForms source; do not launch Remote.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$r=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $r 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$begin=$source.IndexOf('public class RdcBufferedPanel : Panel {',[StringComparison]::Ordinal)
$end=$source.IndexOf("'@ -ReferencedAssemblies",$begin,[StringComparison]::Ordinal)
if($begin -lt 0 -or $end -le $begin){throw 'LOWER_RAIL_PRODUCTION_SOURCE_MISSING'}
$cs='using System;using System.IO;using System.Text;using System.Diagnostics;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;using System.Runtime.InteropServices;'+[Environment]::NewLine+$source.Substring($begin,$end-$begin)
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Get-RailGeometry([RdcOverlayScrollBar]$rail) {
 $args=@([Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty,[Drawing.Rectangle]::Empty)
 $flags=[Reflection.BindingFlags]'NonPublic,Instance'
 $method=[RdcOverlayScrollBar].GetMethod('Geometry',$flags)
 [void]$method.Invoke($rail,$args)
 return ,$args
}
function Paint-Rail([Windows.Forms.Control]$control){
 $bmp=New-Object Drawing.Bitmap($control.Width,$control.Height)
 $g=[Drawing.Graphics]::FromImage($bmp)
 try{
  $g.Clear([Drawing.Color]::Magenta)
  $args=New-Object Windows.Forms.PaintEventArgs($g,$control.ClientRectangle)
  $paint=$control.GetType().GetMethod('OnPaint',[Reflection.BindingFlags]'Instance,NonPublic')
  [void]$paint.Invoke($control,[object[]]@($args.PSObject.BaseObject))
 }finally{$g.Dispose()}
 return ,$bmp
}
Check ($source.Contains('if($OwnerGui){$vScroll.DecorativeFullTrack = $true}') -and
 -not $source.Contains('$headerVScroll.DecorativeFullTrack = $true') -and
 -not $source.Contains('$journalVScroll.DecorativeFullTrack = $true')) 'only Owner lower main rail opts into decorative full-track mode'
Check ($cs.Contains('e.Graphics.FillPolygon(lowerArrows,down);') -and
 $cs.Contains('lowerRailDecorative = lower != null && lower.DecorativeFullTrack;') -and
 $cs.Contains('RdcOverlayScrollBar.TrackBackground')) 'divider preview keeps lower dark-gray arrow and real upper gray arrow through fade'
$owner=New-Object Windows.Forms.Form
$owner.ShowInTaskbar=$false
$owner.StartPosition=[Windows.Forms.FormStartPosition]::Manual
$owner.Location=[Drawing.Point]::new(-10000,-10000)
$owner.Size=[Drawing.Size]::new(700,330)
$text=New-Object RdcLogBox
$text.Location=[Drawing.Point]::new(12,12)
$text.Size=[Drawing.Size]::new(600,88)
$text.Font=[Drawing.Font]::new('Consolas',10)
$text.WordWrap=$false
$text.ScrollBars=[Windows.Forms.RichTextBoxScrollBars]::None
$lower=New-Object RdcOverlayScrollBar
$lower.Vertical=$true
$lower.DecorativeFullTrack=$true
$lower.Target=$text
$lower.Size=[Drawing.Size]::new(17,180)
$lower.Location=[Drawing.Point]::new(625,12)
$upper=New-Object RdcOverlayScrollBar
$upper.Vertical=$true
$upper.Target=$text
$upper.Size=[Drawing.Size]::new(17,180)
$upper.Location=[Drawing.Point]::new(650,12)
[void]$owner.Controls.Add($text)
[void]$owner.Controls.Add($lower)
[void]$owner.Controls.Add($upper)
$preview=New-Object RdcDividerDragPreview
$preview.Size=[Drawing.Size]::new(430,260)
try{
 $owner.Show()
 [Windows.Forms.Application]::DoEvents()
 $text.Text='one'+[Environment]::NewLine+'two'
 [Windows.Forms.Application]::DoEvents()
 $geoSmall=Get-RailGeometry $lower
 Check ($geoSmall[2].Equals($geoSmall[3]) -and $geoSmall[3].Height -eq 148) 'Owner lower capsule occupies full 16px-inset vertical track with two lines'
 $text.Text=(@(1..160|ForEach-Object{'Tool action '+$_}) -join [Environment]::NewLine)
 [Windows.Forms.Application]::DoEvents()
 $geoLarge=Get-RailGeometry $lower
 Check ($geoLarge[2].Equals($geoLarge[3]) -and
  $geoLarge[3].Height -eq $geoSmall[3].Height -and
  $geoLarge[3].Y -eq $geoSmall[3].Y) 'Owner lower thumb never shrinks or moves when compact text count grows'
 $lower.Height=235
 [Windows.Forms.Application]::DoEvents()
 $geoResized=Get-RailGeometry $lower
 Check ($geoResized[3].Equals($geoResized[2]) -and
  $geoResized[3].Height -eq 203) 'full-height gray rail scales with changing Owner activity pane geometry'
 $lower.Height=180
 $native=Get-RailGeometry $upper
 Check (-not $upper.DecorativeFullTrack -and
  $native[3].Height -lt $native[2].Height -and
  $upper.GetType() -eq $lower.GetType()) 'upper native bar still has proportional thumb and scroll semantics'
 $actualBefore=$text.GetViewPosition()
 $down=[RdcOverlayScrollBar].GetMethod('OnMouseDown',[Reflection.BindingFlags]'Instance,NonPublic')
 foreach($y in @(7,40,168)){
  $mouse=[Windows.Forms.MouseEventArgs]::new([Windows.Forms.MouseButtons]::Left,1,8,$y,0)
  [void]$down.Invoke($lower,[object[]]@($mouse))
 }
 $actualAfter=$text.GetViewPosition()
 Check (-not $lower.IsDragging -and
  $actualBefore.Y -eq $actualAfter.Y -and
  $actualBefore.X -eq $actualAfter.X) 'arrow, thumb and track clicks cannot scroll or capture in decorative mode'
 $visual=Paint-Rail $lower
 $standard=Paint-Rail $upper
 try{
  $bg=[Drawing.Color]::FromArgb(18,20,23).ToArgb()
  $arrowGray=[Drawing.Color]::FromArgb(112,115,120).ToArgb()
  $trackGray=[Drawing.Color]::FromArgb(50,52,56).ToArgb()
  Check ($visual.GetPixel(8,7).ToArgb() -eq $trackGray -and
   $visual.GetPixel(8,173).ToArgb() -eq $trackGray -and
   $standard.GetPixel(8,7).ToArgb() -eq $arrowGray -and
   $standard.GetPixel(8,173).ToArgb() -eq $arrowGray) 'inactive lower arrows exactly match its dark gray track, while genuine scrollbar arrows remain brighter'
  $regularOrange=[Drawing.Color]::FromArgb(191,118,67).ToArgb()
  Check ($visual.GetPixel(8,35).ToArgb() -eq $trackGray -and
   $visual.GetPixel(8,89).ToArgb() -eq $trackGray -and
   $visual.GetPixel(8,149).ToArgb() -eq $trackGray) 'experimental lower capsule matches regular scrollbar track gray along entire length'
  Check ($standard.GetPixel(8,35).ToArgb() -eq $regularOrange -and
   $standard.GetPixel(8,89).ToArgb() -eq $trackGray) 'ordinary upper scrollbar keeps orange thumb and identical gray background track'
 }finally{$visual.Dispose();$standard.Dispose()}
 $preview.CaptureFinalScrollbars($upper,$lower)
 $field=[RdcDividerDragPreview].GetField('lowerRailDecorative',[Reflection.BindingFlags]'Instance,NonPublic')
 Check ([bool]$field.GetValue($preview) -and $lower.DecorativeFullTrack -and
  -not $lower.IsDragging -and $upper.GetType() -eq $lower.GetType()) 'preview receives the lower-only decorative state from live scrollbar capture'
 $preview.UpdateDivider(100)
 $painted=Paint-Rail $preview
 try{
  $bottomY=$preview.Height-17
  $x=$preview.Width-9
  Check ($painted.GetPixel($x,$bottomY-7).ToArgb() -eq $trackGray -and
   $painted.GetPixel($x,7).ToArgb() -eq $arrowGray) 'during divider transition bottom arrow stays track-gray and upper arrow stays native lighter gray'
 }finally{$painted.Dispose()}
 $lower.DecorativeFullTrack=$false
 $preview.CaptureFinalScrollbars($upper,$lower)
 Check (-not [bool]$field.GetValue($preview) -and
  -not $lower.DecorativeFullTrack -and -not $standard.IsDisposed) 'non-decorative preview correctly reverts to normal arrow palette'
 $normal=Paint-Rail $preview
 try{
  Check ($normal.GetPixel($preview.Width-9,$preview.Height-17-7).ToArgb() -eq $arrowGray) 'legacy/non-owner drag preview retains the original lighter gray lower arrow'
 }finally{$normal.Dispose()}
}finally{
 $preview.Dispose()
 $owner.Close()
 $owner.Dispose()
}
Write-Output ('RC1_LOWER_ACTIVITY_RAIL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
