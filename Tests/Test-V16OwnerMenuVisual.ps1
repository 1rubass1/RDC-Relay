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
  $check=New-Object Windows.Forms.ToolStripMenuItem('Автообновление')
  $check.Name=if([object]::ReferenceEquals($menu,$account)){'rc1-auto-update-toggle'}else{'rc1-tray-auto-update-toggle'}
  $check.CheckOnClick=$true
  [void]$menu.Items.Add($check)
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
 Check ($rect.X -eq 2 -and $rect.Right -eq ($tray.Width-2) -and
  $rect.Width -eq ($tray.Width-4) -and $rect.Height -eq 1) 'full-width rule reaches x=2 and ends 2px from right without checkbox gutter'
 $lineBitmap=New-Object Drawing.Bitmap(248,130)
 $lineGraphics=[Drawing.Graphics]::FromImage($lineBitmap)
 try{
  $lineGraphics.Clear($tray.BackColor)
  $lineArgs=New-Object Windows.Forms.ToolStripSeparatorRenderEventArgs($lineGraphics,$sep,$false)
  $tray.Renderer.DrawSeparator($lineArgs)
  $leftPixel=$lineBitmap.GetPixel(2,$rect.Y)
  $rightPixel=$lineBitmap.GetPixel($rect.Right-1,$rect.Y)
  $marginPixel=$lineBitmap.GetPixel(1,$rect.Y)
  Check ($leftPixel.ToArgb() -ne $tray.BackColor.ToArgb() -and
   $rightPixel.ToArgb() -eq $leftPixel.ToArgb() -and
   $marginPixel.ToArgb() -eq $tray.BackColor.ToArgb()) 'real native separator painter produces a continuous full-width colored line'
 }finally{$lineGraphics.Dispose();$lineBitmap.Dispose()}
 # Directly exercise the real painter's check glyph with live checked-state.
 $paint=New-Object Drawing.Bitmap(240,32)
 $graphics=[Drawing.Graphics]::FromImage($paint)
 try{
  foreach($menu in @($account,$tray)){
   $check=$menu.Items[3]
   $check.Size=[Drawing.Size]::new(240,32)
   $check.Checked=$false
   $graphics.Clear([Drawing.Color]::FromArgb(38,41,46))
   [RdcOwnerAccountMenuRenderer]::PaintQuotaBox($graphics,$check)
   $off=$paint.GetPixel(14,16)
   $check.Checked=$true
   $graphics.Clear([Drawing.Color]::FromArgb(38,41,46))
   [RdcOwnerAccountMenuRenderer]::PaintQuotaBox($graphics,$check)
   $on=$paint.GetPixel(14,16)
   Check ($off.ToArgb() -ne $on.ToArgb()) ($(if([object]::ReferenceEquals($menu,$account)){'Account'}else{'Tray'})+' checkbox visibly changes with native Checked state')
  }
 }finally{$graphics.Dispose();$paint.Dispose()}
 Check ($guiText.Contains('[RdcOwnerAccountMenuRenderer]::ConfigureOwnerMenu($accountMenu)') -and
  $hostText.Contains('RdcOwnerAccountMenuRenderer.ConfigureOwnerMenu(Menu);') -and
  $hostText.Contains('Menu.Renderer=new RdcOwnerAccountMenuRenderer(new RdcMenuColorTable());')) 'actual two production menus both configure rounded region and professional renderer'
}finally{$account.Dispose();$tray.Dispose()}
Write-Output ('RC1_OWNER_MENU_VISUAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
