# Owner visual-contract checks for actual WinForms Tray and Account renderer.
# Compiles only the exact production style source; no Host, GUI, Remote or system popup starts.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$r=Split-Path -Parent $PSScriptRoot
$hostText=[IO.File]::ReadAllText((Join-Path $r 'Source\RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
$guiText=[IO.File]::ReadAllText((Join-Path $r 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$head='public class RdcMenuColorTable : ProfessionalColorTable {'
$tail='public class RdcCircleButton : Control {'
$from=$hostText.IndexOf($head,[StringComparison]::Ordinal)
$to=$hostText.IndexOf('// Native tray menu:',$from,[StringComparison]::Ordinal)
$gFrom=$guiText.IndexOf($head,[StringComparison]::Ordinal)
$gTo=$guiText.IndexOf($tail,$gFrom,[StringComparison]::Ordinal)
if($from -lt 0 -or $to -le $from -or $gFrom -lt 0 -or $gTo -le $gFrom){throw 'STYLE_MARKERS_MISSING'}
$hs=$hostText.Substring($from,$to-$from).Trim()
$gs=$guiText.Substring($gFrom,$gTo-$gFrom).Trim()
$pass=0;$fail=0
function Check([bool]$truth,[string]$name){
 if($truth){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
Check ($hs -ceq $gs) 'production Account and Tray renderer source is exactly identical'
Add-Type -TypeDefinition ('using System;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;'+[Environment]::NewLine+$hs) -ReferencedAssemblies @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll')
Check ([RdcOwnerAccountMenuRenderer]::CornerRadius -eq 6 -and
 $guiText.Contains('Rounded(r,6f)')) 'menu corner radius 6px exactly matches Account rounded button'
$colors=New-Object RdcMenuColorTable
$render=New-Object RdcOwnerAccountMenuRenderer -ArgumentList @($colors)
$account=New-Object Windows.Forms.ContextMenuStrip
$tray=New-Object Windows.Forms.ContextMenuStrip
try{
 foreach($menu in @($account,$tray)){
  $menu.Renderer=New-Object RdcOwnerAccountMenuRenderer -ArgumentList @((New-Object RdcMenuColorTable))
  [RdcOwnerAccountMenuRenderer]::ConfigureOwnerMenu($menu)
  $menu.Items.Add((New-Object Windows.Forms.ToolStripMenuItem('Сменить аккаунт'))) |Out-Null
  $menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator)) |Out-Null
  $menu.Items.Add((New-Object Windows.Forms.ToolStripMenuItem('Управление устройствами'))) |Out-Null
  foreach($spec in @(
   @('Выводить остаток вызовов','rc1-quota-display-toggle','rc1-tray-quota-toggle'),
   @('Автообновление','rc1-auto-update-toggle','rc1-tray-auto-update-toggle')
  )){
   $check=New-Object Windows.Forms.ToolStripMenuItem($spec[0])
   $check.Name=if([object]::ReferenceEquals($menu,$account)){$spec[1]}else{$spec[2]}
   $check.CheckOnClick=$true
   [void]$menu.Items.Add($check)
  }
  $menu.Size=[Drawing.Size]::new(248,116)
  [RdcOwnerAccountMenuRenderer]::ApplyRoundedRegion($menu)
 }
 Check ($account.BackColor.ToArgb() -eq [Drawing.Color]::FromArgb(38,41,46).ToArgb() -and
  $tray.BackColor.ToArgb() -eq $account.BackColor.ToArgb() -and
  $tray.ForeColor.ToArgb() -eq $account.ForeColor.ToArgb()) 'both popup backgrounds match Account charcoal and silver text'
 Check ($account.Renderer.GetType() -eq $tray.Renderer.GetType() -and
  $account.Renderer.GetType().Name -eq 'RdcOwnerAccountMenuRenderer') 'both native menus use the same professional renderer'
 Check ($account.Region.IsVisible(0,0) -eq $false -and
  $account.Region.IsVisible(9,9) -eq $true -and
  $tray.Region.IsVisible(0,0) -eq $false -and
  $tray.Region.IsVisible(9,9) -eq $true) 'native rounded Region clips actual top-left corner of both popups'
 Check ($account.Region.IsVisible(246,114) -eq $false -and
  $tray.Region.IsVisible(246,114) -eq $false) 'native rounded Region clips bottom-right corner of both popups'
 $sep=$tray.Items[1]
 $rect=[RdcOwnerAccountMenuRenderer]::SeparatorLineBounds($tray,$sep)
 Check ($rect.X -eq 0 -and $rect.Y -eq [int]($sep.Height/2) -and
  $rect.Width -eq $sep.Width -and $rect.Height -eq 1 -and
  ($sep.Bounds.X+$rect.X) -eq 2 -and
  ($sep.Bounds.X+$rect.Right) -eq ($tray.Width-2)) 'separator uses item-local graphics and spans menu x=2 through width-2'
 $lineBitmap=New-Object Drawing.Bitmap(248,130)
 $lineGraphics=[Drawing.Graphics]::FromImage($lineBitmap)
 try{
  $lineGraphics.Clear($tray.BackColor)
  $lineArgs=New-Object Windows.Forms.ToolStripSeparatorRenderEventArgs($lineGraphics,$sep,$false)
  $tray.Renderer.DrawSeparator($lineArgs)
  $leftPixel=$lineBitmap.GetPixel(0,$rect.Y)
  $rightPixel=$lineBitmap.GetPixel($rect.Right-1,$rect.Y)
  $marginPixel=$lineBitmap.GetPixel($rect.Right,$rect.Y)
  Check ($leftPixel.ToArgb() -ne $tray.BackColor.ToArgb() -and
   $rightPixel.ToArgb() -eq $leftPixel.ToArgb() -and
   $marginPixel.ToArgb() -eq $tray.BackColor.ToArgb()) 'real native separator painter produces a continuous full-width colored line'
  $expectedInk=if([Windows.Forms.SystemInformation]::HighContrast){
   [Drawing.SystemColors]::WindowText
  }else{[Drawing.Color]::FromArgb(188,195,207)}
  Check ($leftPixel.ToArgb() -eq $expectedInk.ToArgb() -and
   ([Windows.Forms.SystemInformation]::HighContrast -or
    ($leftPixel.R -ge 180 -and $leftPixel.G -ge 180 -and $leftPixel.B -ge 190))) 'separator is intentionally much lighter than old RGB(105,112,124), or respects High Contrast'
 }finally{$lineGraphics.Dispose();$lineBitmap.Dispose()}
 # Regression for the owner's screenshot: separately invoking DrawSeparator
 # used to PASS while the full popup clipped the separator entirely. These
 # assertions now capture the whole real WinForms ToolStrip paint pipeline.
 $selectionColors=New-Object 'System.Collections.Generic.List[int]'
 foreach($menu in @($account,$tray)){
  $menu.PerformLayout()
  $label=if([object]::ReferenceEquals($menu,$account)){'Account'}else{'Tray'}
  $sepItem=$menu.Items[1]
  $actualY=$sepItem.Bounds.Top+[int]($sepItem.Height/2)
  $expectedInk=if([Windows.Forms.SystemInformation]::HighContrast){
   [Drawing.SystemColors]::WindowText
  }else{[Drawing.Color]::FromArgb(188,195,207)}
  $bitmap=New-Object Drawing.Bitmap($menu.Width,$menu.Height)
  try{
   $menu.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
   $painted=0
   for($x=$sepItem.Bounds.Left;$x -lt $sepItem.Bounds.Right;$x++){
    if($bitmap.GetPixel($x,$actualY).ToArgb() -eq $expectedInk.ToArgb()){$painted++}
   }
   Check ($painted -eq $sepItem.Width -and $sepItem.Width -ge 100) (
    $label+' actual complete popup contains every full-width separator pixel, not clipped')
   # Check real checkbox drawing inside the complete popup, not just
   # PaintQuotaBox invoked on a free-standing un-clipped Graphics object.
   foreach($check in @($menu.Items[3],$menu.Items[4])){
    $check.Checked=$false
    $menu.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
    $rect=[RdcOwnerAccountMenuRenderer]::QuotaBoxBounds($check)
    $px=$check.Bounds.Left+$rect.X+9
    $py=$check.Bounds.Top+$rect.Y+9
    $off=$bitmap.GetPixel($px,$py)
    $check.Checked=$true
    $menu.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
    $on=$bitmap.GetPixel($px,$py)
    Check ($off.ToArgb() -ne $on.ToArgb()) (
     $label+' '+$check.Name+' visible checkmark survives complete popup painting')
   }
   $menu.Items[0].Select()
   $menu.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
   $selected=$bitmap.GetPixel(28,$menu.Items[0].Bounds.Top+[int]($menu.Items[0].Height/2))
   [void]$selectionColors.Add($selected.ToArgb())
   Check ([Windows.Forms.SystemInformation]::HighContrast -or
      ($selected.R -eq 65 -and $selected.G -eq 54 -and $selected.B -eq 86)) (
      $label+' selected row uses explicit purple compositing instead of system hover variant')
  }finally{$bitmap.Dispose()}
 }
 Check ($selectionColors.Count -eq 2 -and $selectionColors[0] -eq $selectionColors[1]) (
  'actual Account and tray selected-row pixels are identical')
 # Directly exercise the real painter's check glyph with live checked-state.
 $paint=New-Object Drawing.Bitmap(240,32)
 $graphics=[Drawing.Graphics]::FromImage($paint)
 try{
  foreach($menu in @($account,$tray)){
   $menu.PerformLayout()
   $menuName=if([object]::ReferenceEquals($menu,$account)){'Account'}else{'Tray'}
   # These WinForms rectangles are internal on ToolStripDropDownMenu;
   # inspect the actual framework geometry, not an assumed fixed gutter.
   $visibility=[Reflection.BindingFlags]'Instance,Public,NonPublic'
   $imageProperty=$menu.GetType().GetProperty('ImageRectangle',$visibility)
   $marginProperty=$menu.GetType().GetProperty('ImageMargin',$visibility)
   if($null -eq $imageProperty -or $null -eq $marginProperty){
    throw 'WINFORMS_IMAGE_MARGIN_GEOMETRY_UNAVAILABLE'
   }
   $nativeImageRect=$imageProperty.GetValue($menu,$null)
   $nativeGutter=$marginProperty.GetValue($menu,$null)
   foreach($check in @($menu.Items[3],$menu.Items[4])){
    $rect=[RdcOwnerAccountMenuRenderer]::QuotaBoxBounds($check)
    $kind=if($check.Text -eq 'Автообновление'){'Auto-update'}else{'Quota'}
    Check ($rect.X -eq $nativeImageRect.X+3 -and
     $rect.Width -eq $nativeImageRect.Width -and
     $rect.Right -le $nativeGutter.Right) (
      $menuName+' '+$kind+' checkbox is exactly 3px toward label and stays in icon gutter')
    Check ($rect.Height -eq 16 -and $rect.Y -ge 0 -and
     [Math]::Abs(($rect.Y+$rect.Height/2.0)-($check.Height/2.0)+1.0) -le 0.5) (
      $menuName+' '+$kind+' checkbox is exactly 1px above geometric row center')
    $check.Size=[Drawing.Size]::new(240,32)
    $center=[RdcOwnerAccountMenuRenderer]::QuotaBoxBounds($check)
    $check.Checked=$false
    $graphics.Clear([Drawing.Color]::FromArgb(38,41,46))
    [RdcOwnerAccountMenuRenderer]::PaintQuotaBox($graphics,$check)
    $off=$paint.GetPixel($center.X+9,$center.Y+9)
    $check.Checked=$true
    $graphics.Clear([Drawing.Color]::FromArgb(38,41,46))
    [RdcOwnerAccountMenuRenderer]::PaintQuotaBox($graphics,$check)
    $on=$paint.GetPixel($center.X+9,$center.Y+9)
    Check ($off.ToArgb() -ne $on.ToArgb()) (
     $menuName+' '+$kind+' checkbox painter follows actual Checked state')
   }
  }
 }finally{$graphics.Dispose();$paint.Dispose()}
 Check ($guiText.Contains('[RdcOwnerAccountMenuRenderer]::ConfigureOwnerMenu($accountMenu)') -and
  $hostText.Contains('RdcOwnerAccountMenuRenderer.ConfigureOwnerMenu(Menu);') -and
  $hostText.Contains('Menu.Renderer=new RdcOwnerAccountMenuRenderer(new RdcMenuColorTable());')) 'actual two production menus both configure rounded region and professional renderer'
}finally{$account.Dispose();$tray.Dispose()}
Write-Output ('RC1_OWNER_MENU_VISUAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
