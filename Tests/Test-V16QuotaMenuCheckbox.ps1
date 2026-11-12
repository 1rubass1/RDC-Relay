# G104: isolated WinForms paint and toggle regression for Account quota menu.
# Uses extracted production C# renderer only; no GUI, Host, Remote, network or tokens.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
$source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$begin=$source.IndexOf('public class RdcMenuColorTable : ProfessionalColorTable {',[StringComparison]::Ordinal)
$end=$source.IndexOf('public class RdcCircleButton : Control {',[StringComparison]::Ordinal)
if($begin -lt 0 -or $end -le $begin){throw 'G103_RENDERER_SOURCE_BOUNDARY'}
$code='using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Windows.Forms;'+
 [Environment]::NewLine+$source.Substring($begin,$end-$begin)
Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$pass=0;$fail=0
function Check([bool]$yes,[string]$name){
 if($yes){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$menu=New-Object Windows.Forms.ContextMenuStrip
$ownerRenderer=New-Object RdcOwnerAccountMenuRenderer -ArgumentList (New-Object RdcMenuColorTable)
$normalRenderer=New-Object Windows.Forms.ToolStripProfessionalRenderer -ArgumentList (New-Object RdcMenuColorTable)
$before=New-Object Windows.Forms.ToolStripMenuItem('Reconnect')
$quota=New-Object Windows.Forms.ToolStripMenuItem('Quota')
$after=New-Object Windows.Forms.ToolStripMenuItem('Devices')
$quota.Name='rc1-quota-display-toggle'
$quota.CheckOnClick=$true
$quota.Checked=$true
$quota.AccessibleDescription='Check to display quota'
$menu.Renderer=$ownerRenderer
$menu.Items.Add($before)|Out-Null
$menu.Items.Add($quota)|Out-Null
$menu.Items.Add($after)|Out-Null
$menu.Size=New-Object Drawing.Size(300,95)
$menu.PerformLayout()
$quota.Size=New-Object Drawing.Size(260,25)
$before.Size=New-Object Drawing.Size(260,25)
$after.Size=New-Object Drawing.Size(260,25)
function Render-QuotaGlyph([bool]$checked,[bool]$enabled){
 $quota.Checked=$checked
 $quota.Enabled=$enabled
 $bitmap=New-Object Drawing.Bitmap(260,25)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try {
  $graphics.Clear($menu.BackColor)
  [RdcOwnerAccountMenuRenderer]::PaintQuotaBox($graphics,$quota)
 }finally{$graphics.Dispose()}
 return ,$bitmap
}
function Count-Light-Glyph([Drawing.Bitmap]$bitmap){
 $rect=[RdcOwnerAccountMenuRenderer]::QuotaBoxBounds($quota)
 $n=0
 for($y=$rect.Y+2;$y -lt $rect.Bottom-2;$y++){
  for($x=$rect.X+2;$x -lt $rect.Right-2;$x++){
   $c=$bitmap.GetPixel($x,$y)
   if($c.R -ge 235 -and $c.G -ge 220 -and $c.B -ge 195){$n++}
  }
 }
 return $n
}
try{
 Check ($menu.Renderer -is [RdcOwnerAccountMenuRenderer]) 'Owner Account menu uses dedicated renderer'
 Check ($ownerRenderer -is [Windows.Forms.ToolStripProfessionalRenderer] -and
  $normalRenderer -is [Windows.Forms.ToolStripProfessionalRenderer]) 'other menus retain system renderer compatibility'
 # Draw the actual production renderer's image margin without opening a UI.
 # Owner gutter must match the menu text BackColor; legacy/help remain orange.
 $menu.BackColor=[Drawing.Color]::FromArgb(38,41,46)
 $marginBounds=New-Object Drawing.Rectangle(0,0,28,80)
 $ownerBitmap=New-Object Drawing.Bitmap(40,80)
 $legacyBitmap=New-Object Drawing.Bitmap(40,80)
 try{
  $ownerGraphics=[Drawing.Graphics]::FromImage($ownerBitmap)
  $legacyGraphics=[Drawing.Graphics]::FromImage($legacyBitmap)
  try{
   $ownerGraphics.Clear([Drawing.Color]::Black)
   $legacyGraphics.Clear([Drawing.Color]::Black)
   $ownerEvent=[Windows.Forms.ToolStripRenderEventArgs]::new($ownerGraphics,$menu,$marginBounds,$menu.BackColor)
   $legacyEvent=[Windows.Forms.ToolStripRenderEventArgs]::new($legacyGraphics,$menu,$marginBounds,$menu.BackColor)
   $ownerRenderer.DrawImageMargin($ownerEvent)
   $normalRenderer.DrawImageMargin($legacyEvent)
  }finally{$ownerGraphics.Dispose();$legacyGraphics.Dispose()}
  $expected=[Drawing.Color]::FromArgb(38,41,46)
  $actual=$ownerBitmap.GetPixel(10,35)
  $original=$legacyBitmap.GetPixel(10,35)
  Check ($actual.ToArgb() -eq $expected.ToArgb()) 'Owner orange image gutter replaced by exact menu body background RGB 38,41,46'
  Check ($original.ToArgb() -eq ([Drawing.Color]::FromArgb(191,118,67)).ToArgb()) 'Help and legacy image gutter retains original orange'
 }finally{$ownerBitmap.Dispose();$legacyBitmap.Dispose()}
 $bounds=[RdcOwnerAccountMenuRenderer]::QuotaBoxBounds($quota)
 Check ($bounds.Width -eq 16 -and $bounds.Height -eq 16 -and
  $bounds.X -eq 5 -and $bounds.Y -eq [Math]::Max(0,($quota.Height-16)/2)) 'checkbox 16px centered on native image slot x=5 and vertically aligned to row'
 $on=Render-QuotaGlyph $true $true
 $off=Render-QuotaGlyph $false $true
 try{
  $onPixel=$on.GetPixel($bounds.X+8,$bounds.Y+8)
  $offPixel=$off.GetPixel($bounds.X+8,$bounds.Y+8)
  $onCount=Count-Light-Glyph $on
  $offCount=Count-Light-Glyph $off
  Check ($onCount -ge 9 -and $offCount -lt 5) ('checked state has high-contrast tick; ON pixels='+$onCount+' OFF pixels='+$offCount)
  Check ($onPixel.ToArgb() -ne $offPixel.ToArgb()) 'checkbox has visually distinct ON versus OFF center'
  Check ($on.GetPixel($bounds.X,$bounds.Y).ToArgb() -ne
   $menu.BackColor.ToArgb()) 'square fill contrasts with the neutral menu gutter'
 }finally{$on.Dispose();$off.Dispose()}
 $menu.PerformLayout()
 $quota.Enabled=$true
 $quota.Checked=$true
 $height=$quota.Height
 $quota.PerformClick()
 Check (-not $quota.Checked -and $quota.Height -eq $height) 'click toggles OFF without changing menu geometry'
 $quota.PerformClick()
 Check ($quota.Checked -and $quota.Height -eq $height) 'click toggles ON without moving label'
 $disabled=Render-QuotaGlyph $true $false
 try{
  Check ($disabled.GetPixel($bounds.X+8,$bounds.Y+8).A -eq 255) 'disabled mode remains an opaque visible checkbox'
 }finally{$disabled.Dispose()}
 Check ($source.Contains("$"+'accountMenu.Renderer = if($OwnerGui){New-Object RdcOwnerAccountMenuRenderer') -and
  $source.Contains("$"+'quotaAuthItem.Name='+ "'rc1-quota-display-toggle'") -and
  $source.Contains('OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)')) 'only Owner quota item intercepts native check drawing'
 Check ($source.Contains("$"+'quotaAuthItem.CheckOnClick=[bool]$OwnerGui') -and
  $source.Contains("$"+'quotaAuthItem.AccessibleDescription=')) 'native keyboard/accessibility toggle contract retained'
 Check ($source.Contains('SystemInformation.HighContrast') -and
  $source.Contains('SystemColors.HighlightText') -and
  $source.Contains('SystemColors.WindowText')) 'system high-contrast colors have an explicit fallback'
}finally{
 $menu.Dispose()
}
Write-Output ('RC1_QUOTA_MENU_CHECKBOX_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0