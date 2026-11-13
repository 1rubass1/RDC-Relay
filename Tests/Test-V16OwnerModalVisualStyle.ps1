# Real production owner-modal button / scroll grip pixel parity test.
# Uses isolated off-screen WinForms controls. No Remote, Host, browser or installer.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$r=Split-Path -Parent $PSScriptRoot
$path=Join-Path $r 'Source\remote-window.ps1'
. (Join-Path $PSScriptRoot 'Import-V16OwnerModalButtonType.ps1') -SourcePath $path
$source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$start=$source.IndexOf('public class RdcScrollCorner : Control {',[StringComparison]::Ordinal)
$end=$source.IndexOf('public class RdcOverlayScrollBar : Control {',$start,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -le $start){throw 'PRODUCTION_SCROLL_GRIP_NOT_FOUND'}
$cs='using System;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;using System.Diagnostics;'+
 [Environment]::NewLine+$source.Substring($start,$end-$start)
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
function Paint-Control([Windows.Forms.Control]$control) {
 $bmp=New-Object Drawing.Bitmap($control.Width,$control.Height)
 $graphics=[Drawing.Graphics]::FromImage($bmp)
 try{
  $graphics.Clear([Drawing.Color]::Magenta)
  $p=New-Object Windows.Forms.PaintEventArgs($graphics,$control.ClientRectangle)
  $flags=[Reflection.BindingFlags]'Instance,NonPublic'
  $paint=$control.GetType().GetMethod('OnPaint',$flags)
  if(-not $paint){throw 'PRODUCTION_PAINT_METHOD_MISSING'}
  [void]$paint.Invoke($control,[object[]]@($p.PSObject.BaseObject))
 }finally{$graphics.Dispose()}
 return ,$bmp
}
function Difference([Drawing.Bitmap]$a,[Drawing.Bitmap]$b){
 if($a.Width -ne $b.Width -or $a.Height -ne $b.Height){return -1}
 $different=0
 for($y=0;$y -lt $a.Height;$y++){
  for($x=0;$x -lt $a.Width;$x++){
   if($a.GetPixel($x,$y).ToArgb() -ne $b.GetPixel($x,$y).ToArgb()){$different++}
  }
 }
 return $different
}
$ownerScope=$source.Substring($source.IndexOf('function New-RdcOwnerStopDialog',[StringComparison]::Ordinal))
Check (([regex]::Matches($ownerScope,'New-Object RdcModalButton')).Count -eq 9 -and
 -not $ownerScope.Contains('New-Object Windows.Forms.Button')) 'all nine production Owner modal actions use the shared button type'
Check (([RdcModalButton].IsSubclassOf([Windows.Forms.Button])) -and
 [Windows.Forms.IButtonControl].IsAssignableFrom([RdcModalButton]) -and
 [RdcModalButton].GetMethod('PerformClick') -ne $null) 'modal buttons retain native WinForms dialog button semantics'
$main=New-Object RdcRoundedButton
$modal=New-Object RdcModalButton
try{
 foreach($b in @($main,$modal)){
  $b.Text='Close'
  $b.Size=[Drawing.Size]::new(152,36)
  $b.BackColor=[Drawing.Color]::FromArgb(29,32,36)
  $b.ForeColor=[Drawing.Color]::FromArgb(238,238,238)
 }
 Check ($modal.Font.Name -ceq $main.Font.Name -and
  $modal.Font.Size -eq $main.Font.Size -and
  $modal.Cursor -eq [Windows.Forms.Cursors]::Hand -and
  -not $modal.Image -and
  $modal.BackColor.ToArgb() -eq $main.BackColor.ToArgb()) 'both families have identical typography, background and no modal glyph'
 foreach($state in @('normal','hover','pressed','disabled')){
  if($state -eq 'hover'){
   foreach($b in @($main,$modal)){
    $enter=$b.GetType().GetMethod('OnMouseEnter',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$enter.Invoke($b,[object[]]@([EventArgs]::Empty))
   }
  }
  if($state -eq 'pressed'){
   foreach($b in @($main,$modal)){
    $down=$b.GetType().GetMethod('OnMouseDown',[Reflection.BindingFlags]'Instance,NonPublic')
    $mouse=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Left,1,10,10,0)
    [void]$down.Invoke($b,[object[]]@($mouse.PSObject.BaseObject))
   }
  }
  if($state -eq 'disabled'){
   $main.Enabled=$false
   $modal.Enabled=$false
  }
  $im=Paint-Control $main
  $io=Paint-Control $modal
  try{
   $diff=Difference $im $io
   Check ($diff -eq 0) ('modal button matches main chrome/text pixel-for-pixel in '+$state+' state (different='+$diff+')')
   Check ($io.GetPixel(0,0).ToArgb() -eq $modal.BackColor.ToArgb() -and
    $io.GetPixel(76,18).ToArgb() -ne $modal.BackColor.ToArgb()) ('modal background stays opaque with rounded 6px corners in '+$state)
  }finally{$im.Dispose();$io.Dispose()}
 }
}finally{$main.Dispose();$modal.Dispose()}
$mainGrip=New-Object RdcScrollCorner
$journalGrip=New-Object RdcJournalScrollGrip
try{
 foreach($g in @($mainGrip,$journalGrip)){$g.Size=[Drawing.Size]::new(17,17)}
 $a=Paint-Control $mainGrip
 $b=Paint-Control $journalGrip
 try{
  $diff=Difference $a $b
  Check ($diff -eq 0) ('journal grip reproduces all three main-window gold corner strokes exactly (different='+$diff+')')
  Check ($b.GetPixel(0,0).ToArgb() -eq [Drawing.Color]::FromArgb(18,20,23).ToArgb() -and
   $b.GetPixel(15,6).ToArgb() -ne [Drawing.Color]::FromArgb(18,20,23).ToArgb()) 'journal corner has visible gold diagonal instead of blank panel'
 }finally{$a.Dispose();$b.Dispose()}
 Check ($journalGrip.Cursor -eq [Windows.Forms.Cursors]::Default -and
  -not $journalGrip.TabStop -and -not ($journalGrip -is [RdcScrollCorner])) 'passive journal junction never impersonates the main activity splitter drag'
}finally{$mainGrip.Dispose();$journalGrip.Dispose()}
$dialog=New-Object Windows.Forms.Form
$dialog.Name='test-owner-button-dialog'
$dialog.ShowInTaskbar=$false
$dialog.StartPosition=[Windows.Forms.FormStartPosition]::Manual
$dialog.Location=[Drawing.Point]::new(-10000,-10000)
$cancel=New-Object RdcModalButton
$cancel.Name='safe-no'
$cancel.Text='No'
$cancel.DialogResult=[Windows.Forms.DialogResult]::No
$cancel.Size=[Drawing.Size]::new(96,34)
[void]$dialog.Controls.Add($cancel)
$dialog.AcceptButton=$cancel
$dialog.CancelButton=$cancel
$script:clicks=0
$cancel.Add_Click({$script:clicks++})
try{
 $dialog.Add_Shown({
  [void]$dialog.BeginInvoke([Action]{ $cancel.PerformClick() })
 })
 $result=$dialog.ShowDialog()
 Check ($result -eq [Windows.Forms.DialogResult]::No -and
  $script:clicks -eq 1) 'native modal PerformClick closes with safe No result exactly once'
}finally{$dialog.Dispose()}
Write-Output ('RC1_MODAL_BUTTON_VISUAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
