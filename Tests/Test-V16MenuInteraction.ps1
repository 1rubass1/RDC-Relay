# Native WinForms popup fixture; no Host, Remote, or real preference writes.
param([string]$SourceRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'),[string]$OutputRoot='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=[IO.File]::ReadAllText((Join-Path $SourceRoot 'RdcOwnerRuntime.cs'))
$first=$src.IndexOf('// Mirror of the GUI renderer, unchanged')
$last=$src.IndexOf('public sealed class RdcOwnerRuntime : IDisposable {',$first)
if($first -lt 0 -or $last -le $first){throw 'MENU_SOURCE_MARKERS'}
$code='using System.Drawing; using System.Drawing.Drawing2D; using System.Windows.Forms;'+[Environment]::NewLine+[IO.File]::ReadAllText((Join-Path $SourceRoot 'RdcUiLanguage.cs'))+[Environment]::NewLine+$src.Substring($first,$last-$first)
Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class RdcPopupTestInput {
 [StructLayout(LayoutKind.Sequential)] struct Rect {public int l,t,r,b;}
 [DllImport("user32.dll",SetLastError=true)] static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
 public static System.Drawing.Rectangle ActualBounds(ToolStripDropDown menu){
  Rect r;if(!GetWindowRect(menu.Handle,out r))throw new System.ComponentModel.Win32Exception();
  return System.Drawing.Rectangle.FromLTRB(r.l,r.t,r.r,r.b);
 }
 [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 public static void Mouse(ToolStripDropDown menu,ToolStripItem item) {
  int x=item.Bounds.Left+item.Bounds.Width/2,y=item.Bounds.Top+item.Bounds.Height/2;
  IntPtr p=(IntPtr)((y<<16)|(x&65535));
  SendMessage(menu.Handle,0x200,IntPtr.Zero,p);
  SendMessage(menu.Handle,0x201,(IntPtr)1,p);
  SendMessage(menu.Handle,0x202,IntPtr.Zero,p);
 }
 public static void Key(ToolStripDropDown menu,ToolStripItem item,Keys key){
  item.Select();
  var method=typeof(ToolStripDropDown).GetMethod("ProcessDialogKey",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic);
  method.Invoke(menu,new object[]{key});
 }
}
'@ -ReferencedAssemblies @('System.dll','System.Windows.Forms.dll','System.Drawing.dll')
$script:pass=0;$script:fail=0
function Check([bool]$ok,[string]$name){if($ok){$script:pass++;Write-Output ('PASS '+$name)}else{$script:fail++;Write-Output ('FAIL '+$name)}}
$script:actions=New-Object 'System.Collections.Generic.List[string]'
$script:tray=$null
$callback=[Action[string]]{
 param($action)
 $script:actions.Add($action)
 if($action -eq 'LANGUAGE_EN'){$script:tray.ApplyLanguage('en-US',[RdcUiLanguage]::LoadResources($SourceRoot,'en-US'))}
 if($action -eq 'LANGUAGE_RU'){$script:tray.ApplyLanguage('ru-RU',[RdcUiLanguage]::LoadResources($SourceRoot,'ru-RU'))}
}
$form=New-Object Windows.Forms.Form
$form.Text='RDC isolated menu QA';$form.StartPosition='CenterScreen';$form.Size=New-Object Drawing.Size(600,460)
$script:tray=New-Object RdcOwnerTrayMenu -ArgumentList @($callback)
$account=New-Object RdcOwnerPaddedContextMenuStrip
$account.Renderer=New-Object RdcOwnerAccountMenuRenderer -ArgumentList @((New-Object RdcMenuColorTable))
[RdcOwnerAccountMenuRenderer]::ConfigureOwnerMenu($account)
$toggle=New-Object Windows.Forms.ToolStripMenuItem('Quota')
$toggle.Name='rc1-quota-display-toggle';$toggle.CheckOnClick=$true
$plain=New-Object Windows.Forms.ToolStripMenuItem('Ordinary')
[void]$account.Items.Add($toggle);[void]$account.Items.Add($plain)
function Pump { [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 60;[Windows.Forms.Application]::DoEvents() }
function ShowMenu($menu){if(!$menu.Visible){$menu.Show($form,(New-Object Drawing.Point(30,30)));Pump}}
function CloseMenu($menu){if($menu.Visible){$menu.Close();Pump}}
function SaveMenu($menu,$name){if($OutputRoot -and $menu.Visible){$bmp=New-Object Drawing.Bitmap($menu.Width,$menu.Height);try{$menu.DrawToBitmap($bmp,[Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height));$bmp.Save((Join-Path $OutputRoot $name))}finally{$bmp.Dispose()}}}
try{
 $form.Show();$form.Activate();Pump
 $tray.SetApplicationIcon((Join-Path $SourceRoot 'RDCRelay.ico'))
 $tray.Refresh($true,$false,$false,$false,$false,$false,$false,$false,$false)
 $tray.AutoStartItem.Enabled=$true
 $tray.ApplyLanguage('ru-RU',[RdcUiLanguage]::LoadResources($SourceRoot,'ru-RU'))
 ShowMenu $tray.Menu
 Check $tray.Menu.Visible 'native tray popup opens'
 Check ($null -ne $tray.OpenItem.Image -and $null -ne $tray.AutoStartItem.Image) 'both artwork images loaded'
 $a=[RdcOwnerAccountMenuRenderer]::QuotaBoxBounds($tray.OpenItem)
 $open=[RdcOwnerAccountMenuRenderer]::LeftArtworkBounds($tray.OpenItem)
 $help=[RdcOwnerAccountMenuRenderer]::LeftArtworkBounds($tray.HelpItem)
 $b=[RdcOwnerAccountMenuRenderer]::RightArtworkBounds($tray.AutoStartItem)
 Check ($open.Width -eq 19 -and $open.Height -eq 19 -and $open.Y -eq $a.Y -and $open.X -eq $a.X-1) 'RDC artwork grows 3px downward and about horizontal center'
 Check ($help.Width -eq 17 -and $help.Height -eq 17 -and $help.Y -eq $a.Y -and $help.X -eq $a.X) 'Help artwork grows 1px downward and inward'
 Check ($b.Width -eq 18 -and $b.Height -eq 18 -and $b.Y -eq $a.Y -and ($tray.AutoStartItem.Width-$b.Right) -eq $a.X-1) 'Windows artwork grows 2px downward around mirrored horizontal center'
 Check ($open.Bottom -le $tray.OpenItem.Height -and $help.Bottom -le $tray.HelpItem.Height -and $b.Bottom -le $tray.AutoStartItem.Height) 'enlarged artwork stays within the existing rows'
 SaveMenu $tray.Menu 'tray-menu-preview.png'
 foreach($item in @($tray.AutoStartItem,$tray.AutoUpdateItem,$tray.QuotaItem,$tray.AutoConnectItem)){
  ShowMenu $tray.Menu
  $before=$item.Checked;$count=$script:actions.Count
  [RdcPopupTestInput]::Mouse($tray.Menu,$item);Pump
  Check ($item.Checked -ne $before -and $script:actions.Count -eq $count+1) ('mouse toggles '+$item.Name+' exactly once')
  Check $tray.Menu.Visible ('mouse keeps '+$item.Name+' popup open')
 }
 ShowMenu $tray.Menu
 $before=$tray.AutoStartItem.Checked
 [RdcPopupTestInput]::Key($tray.Menu,$tray.AutoStartItem,[Windows.Forms.Keys]::Enter);Pump
 Check ($tray.AutoStartItem.Checked -ne $before -and $tray.Menu.Visible) 'keyboard Enter toggles and retains popup'
 ShowMenu $tray.Menu
 $tray.LanguageItem.ShowDropDown();Pump
 $sub=$tray.LanguageItem.DropDown
 $work=[Drawing.Rectangle]::new(0,0,1000,800)
 Check ([RdcOwnerTrayMenu]::LanguagePopupLocation([Drawing.Rectangle]::new(300,200,150,60),$work) -eq [Drawing.Point]::new(302,191)) 'language popup offset is +2,-9'
 Check ([RdcOwnerTrayMenu]::LanguagePopupLocation([Drawing.Rectangle]::new(850,0,150,60),$work) -eq [Drawing.Point]::new(850,0)) 'language popup stays inside work area'
 $row=[Drawing.Rectangle]::new($tray.Menu.PointToScreen($tray.LanguageItem.Bounds.Location),$tray.LanguageItem.Size)
 $actual=[RdcPopupTestInput]::ActualBounds($sub)
 $area=[Windows.Forms.Screen]::FromRectangle($row).WorkingArea
 $native=[Drawing.Rectangle]::new($row.Right,$row.Top,$actual.Width,$actual.Height)
 $expected=[RdcOwnerTrayMenu]::LanguagePopupLocation($native,$area)
 Write-Output ('ACTUAL_HWND='+$actual+' EXPECTED='+$expected+' PARENT='+$row)
 Check ($actual.Location -eq $expected) 'actual native language popup window moved +2,-9'
 function CheckLanguagePosition([string]$name){
  $row=[Drawing.Rectangle]::new($tray.Menu.PointToScreen($tray.LanguageItem.Bounds.Location),$tray.LanguageItem.Size)
  $actual=[RdcPopupTestInput]::ActualBounds($sub)
  $area=[Windows.Forms.Screen]::FromRectangle($row).WorkingArea
  $native=[Drawing.Rectangle]::new($row.Right,$row.Top,$actual.Width,$actual.Height)
  Check ($actual.Location -eq [RdcOwnerTrayMenu]::LanguagePopupLocation($native,$area)) $name
 }
 Check ($sub.Visible -and $sub.BackColor -eq $tray.Menu.BackColor -and $sub.ForeColor -eq $tray.Menu.ForeColor -and $sub.Renderer -eq $tray.Menu.Renderer -and $null -ne $sub.Region) 'language submenu shares theme and shape'
 SaveMenu $sub 'language-menu-preview.png'
 [RdcPopupTestInput]::Mouse($sub,$tray.LanguageEnglishItem);Pump
 Check ($tray.LanguageEnglishItem.Checked -and !$tray.LanguageRussianItem.Checked -and $tray.AutoStartItem.Text -eq 'Autostart') 'language click updates check and localized menu immediately'
 Check ($tray.Menu.Visible -and $sub.Visible) 'language click retains parent and submenu'
 CheckLanguagePosition 'actual offset survives EN relayout'
 if(!$tray.Menu.Visible){ShowMenu $tray.Menu}
 if(!$sub.Visible){$tray.LanguageItem.ShowDropDown();Pump}
 [RdcPopupTestInput]::Key($sub,$tray.LanguageRussianItem,[Windows.Forms.Keys]::Enter);Pump
 Check ($tray.LanguageRussianItem.Checked -and !$tray.LanguageEnglishItem.Checked -and $tray.Menu.Visible -and $sub.Visible) 'keyboard language selection retains both menus'
 CheckLanguagePosition 'actual offset survives RU relayout'
 CloseMenu $sub
 $tray.LanguageItem.ShowDropDown();Pump
 CheckLanguagePosition 'actual offset survives reopening without drift'
 CloseMenu $sub;CloseMenu $tray.Menu
 ShowMenu $tray.Menu
 [RdcPopupTestInput]::Mouse($tray.Menu,$tray.OpenItem);Pump
 Check (!$tray.Menu.Visible -and $script:actions[$script:actions.Count-1] -eq 'OPEN') 'ordinary command closes menu'
 ShowMenu $account
 [RdcPopupTestInput]::Mouse($account,$toggle);Pump
 Check ($account.Visible -and $toggle.Checked) 'GUI quota toggles without closing'
 [RdcPopupTestInput]::Key($account,$toggle,[Windows.Forms.Keys]::Enter);Pump
 Check ($account.Visible -and !$toggle.Checked) 'GUI quota Enter toggles without closing'
 $account.Close([Windows.Forms.ToolStripDropDownCloseReason]::AppClicked);Pump
 Check (!$account.Visible) 'outside click reason closes normally'
 ShowMenu $account
 [RdcPopupTestInput]::Mouse($account,$plain);Pump
 Check (!$account.Visible) 'GUI ordinary action closes'
 ShowMenu $account
 [RdcPopupTestInput]::Key($account,$toggle,[Windows.Forms.Keys]::Escape);Pump
 Check (!$account.Visible) 'Escape closes popup'
}finally{CloseMenu $account;CloseMenu $tray.Menu;$account.Dispose();$tray.Dispose();$form.Dispose()}
Write-Output ('RDC_MENU_INTERACTION_PASS='+$script:pass+' FAIL='+$script:fail)
if($script:fail){exit 1}
