# Isolated header-depth trial using actual production paint classes.
# No Host, Remote, preferences, or product GUI.
param([string]$SourcePath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'),[string]$OutputRoot='',[switch]$Preview)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=[IO.File]::ReadAllText($SourcePath)
$a=$src.IndexOf('public enum RdcButtonGlyph {')
$b=$src.IndexOf('public class RdcBufferedPanel : Panel {',$a)
if($a -lt 0 -or $b -le $a){throw 'HEADER_DEPTH_SOURCE_MARKERS'}
Add-Type -TypeDefinition ('using System;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;'+[Environment]::NewLine+$src.Substring($a,$b-$a)) -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$script:pass=0;$script:fail=0
function Check([bool]$ok,[string]$name){if($ok){$script:pass++;Write-Output ('PASS '+$name)}else{$script:fail++;Write-Output ('FAIL '+$name)}}
function MakeHeader([bool]$trial){
 $f=New-Object Windows.Forms.Form
 $f.StartPosition='Manual';$f.Location=[Drawing.Point]::new(-12000,-12000)
 $f.ClientSize=[Drawing.Size]::new(1058,120)
 $f.BackColor=[Drawing.Color]::FromArgb(29,32,36);$f.ForeColor=[Drawing.Color]::Gainsboro
 $top=New-Object Windows.Forms.TableLayoutPanel
 $top.Dock='Top';$top.Height=78;$top.BackColor=$f.BackColor
 $top.Padding=if($trial){[Windows.Forms.Padding]::new(2,9,13,9)}else{[Windows.Forms.Padding]::new(2,9,16,9)}
 $top.ColumnCount=3;$top.RowCount=2
 [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,38))
 [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
 [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,$(if($trial){307}else{304})))
 [void]$top.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,32))
 [void]$top.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
 $dot=New-Object RdcStatusIndicator;$dot.OwnerCapsule=$true;$dot.Dock='Fill';$dot.IndicatorColor=[Drawing.Color]::PaleGreen
 $title=New-Object Windows.Forms.Label;$title.Text='RDC Relay';$title.Dock='Fill';$title.Font=[Drawing.Font]::new('Segoe UI',13,[Drawing.FontStyle]::Bold)
 $detail=New-Object Windows.Forms.Label;$detail.Text='Disconnected';$detail.Dock='Fill'
 $panel=if($trial){New-Object RdcHeaderActionPanel}else{New-Object Windows.Forms.FlowLayoutPanel}
 $panel.Dock='Fill';$panel.BackColor=$f.BackColor;$panel.FlowDirection='RightToLeft';$panel.WrapContents=$false;$panel.Margin=[Windows.Forms.Padding]::new(0)
 $panel.Padding=if($trial){[Windows.Forms.Padding]::new(0,12,3,12)}else{[Windows.Forms.Padding]::new(0,12,0,12)}
 $start=New-Object RdcRoundedButton;$start.Text='Start';$start.Glyph=[RdcButtonGlyph]::Play;$start.Size=[Drawing.Size]::new(120,36);$start.Margin=[Windows.Forms.Padding]::new(16,0,0,0)
 $account=New-Object RdcRoundedButton;$account.Text='Account';$account.ShowMenuChevron=$true;$account.Size=[Drawing.Size]::new(120,36);$account.Margin=[Windows.Forms.Padding]::new(0)
 $start.AmbientShadowRadius=if($trial){3}else{0}
 $account.AmbientShadowRadius=if($trial){3}else{0}
 foreach($button in @($start,$account)){$button.BackColor=$f.BackColor;[void]$panel.Controls.Add($button)}
 [void]$top.Controls.Add($dot,0,0);$top.SetRowSpan($dot,2)
 [void]$top.Controls.Add($title,1,0);[void]$top.Controls.Add($detail,1,1)
 [void]$top.Controls.Add($panel,2,0);$top.SetRowSpan($panel,2)
 [void]$f.Controls.Add($top);$f.Show();$top.PerformLayout();$panel.PerformLayout()
 [Windows.Forms.Application]::DoEvents()
 return @{Form=$f;Top=$top;Dot=$dot;Panel=$panel;Start=$start;Account=$account;Title=$title;Detail=$detail}
}
function Capture($h){
 $bmp=[Drawing.Bitmap]::new($h.Top.Width,$h.Top.Height)
 $h.Top.DrawToBitmap($bmp,[Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height))
 return ,$bmp
}
function GlobalBounds($h,$b){return [Drawing.Rectangle]::new($h.Panel.Left+$b.Left,$h.Panel.Top+$b.Top,$b.Width,$b.Height)}
if($Preview){
 $h=MakeHeader $true
 $h.Form.Text='RDC Relay - button depth preview (not connected)'
 $h.Form.StartPosition='Manual'
 $h.Form.Location=[Drawing.Point]::new(30,80)
 $h.Title.Text='RDC Relay - Waiting'
 $h.Detail.Text='Preview only. Both buttons use the accepted 3px fade.'
 $h.Start.Text='Stop';$h.Start.Glyph=[RdcButtonGlyph]::Stop
 $h.Form.ClientSize=[Drawing.Size]::new(1058,90)
 $h.Form.TopMost=$true
 try{while(-not $h.Form.IsDisposed -and $h.Form.Visible){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 80}}finally{$h.Form.Dispose()}
 return
}
$base=MakeHeader $false;$trial=MakeHeader $true
try{
 Check ($base.Dot.Bounds -eq $trial.Dot.Bounds -and $base.Title.Bounds -eq $trial.Title.Bounds -and $base.Detail.Bounds -eq $trial.Detail.Bounds -and $base.Panel.Left -eq $trial.Panel.Left) 'status, title, detail and action column start unchanged'
 foreach($key in @('Start','Account')){
  Check ((GlobalBounds $base $base[$key]) -eq (GlobalBounds $trial $trial[$key])) "$key retains exact 120x36 location and hit target"
 }
 $before=Capture $base;$after=Capture $trial
 try{
  foreach($key in @('Start','Account')){
   $r=GlobalBounds $trial $trial[$key]
   $cx=$r.Left+[int]($r.Width/2);$cy=$r.Top+[int]($r.Height/2)
   $bg=$trial.Form.BackColor
   $radius=3
   Check ($trial[$key].AmbientShadowRadius -eq $radius) "$key correct configured radius"
   $samples=@(
    @([Drawing.Point]::new($r.Left-1,$cy),[Drawing.Point]::new($r.Left-$radius+1,$cy),[Drawing.Point]::new($r.Left-$radius-1,$cy)),
    @([Drawing.Point]::new($r.Right,$cy),[Drawing.Point]::new($r.Right+$radius-2,$cy),[Drawing.Point]::new($r.Right+$radius,$cy)),
    @([Drawing.Point]::new($cx,$r.Top-1),[Drawing.Point]::new($cx,$r.Top-$radius+1),[Drawing.Point]::new($cx,$r.Top-$radius-1)),
    @([Drawing.Point]::new($cx,$r.Bottom),[Drawing.Point]::new($cx,$r.Bottom+$radius-2),[Drawing.Point]::new($cx,$r.Bottom+$radius))
   )
   $i=0
   foreach($points in $samples){
    $near=$after.GetPixel($points[0].X,$points[0].Y);$far=$after.GetPixel($points[1].X,$points[1].Y);$clear=$after.GetPixel($points[2].X,$points[2].Y)
    Write-Output "$key side $i shadow red=$($near.R),$($far.R),$($clear.R)"
     Check ($near.R -lt $far.R -and $far.R -lt $bg.R -and $clear.ToArgb() -eq $bg.ToArgb()) "$key side $i outward fading shadow"
    $i++
   }
   Check ($before.GetPixel($cx,$r.Top+8).ToArgb() -eq $after.GetPixel($cx,$r.Top+8).ToArgb()) "$key face color unchanged"
  }
  if($OutputRoot){$after.Save((Join-Path $OutputRoot 'header-depth-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}
 }finally{$before.Dispose();$after.Dispose()}
 foreach($color in @([Drawing.Color]::PaleGreen,[Drawing.Color]::Khaki,[Drawing.Color]::LightCoral,[Drawing.Color]::Gray)){
  $trial.Dot.IndicatorColor=$color
  $bmp=Capture $trial
  try{
   $x=$trial.Dot.Left+[int][Math]::Floor(($trial.Dot.Width-13)/2)
   $y=$trial.Dot.Top+[Math]::Min([Math]::Max(0,$trial.Dot.Height-40),8)
   $rim=$bmp.GetPixel($x+1,$y+20);$core=$bmp.GetPixel($x+6,$y+25);$shine=$bmp.GetPixel($x+5,$y+6)
   Check ($core.ToArgb() -eq $color.ToArgb() -and $rim.ToArgb() -ne $core.ToArgb() -and $rim.R -le $core.R -and $rim.G -le $core.G -and $rim.B -le $core.B) "$($color.Name) preserves core and darker internal rim"
   Check (($shine.R -gt $core.R -or $shine.G -gt $core.G -or $shine.B -gt $core.B)) "$($color.Name) has local highlight"
  }finally{$bmp.Dispose()}
 }
}finally{$base.Form.Close();$base.Form.Dispose();$trial.Form.Close();$trial.Form.Dispose()}
Write-Output ('RDC_HEADER_DEPTH_PASS='+$script:pass+' FAIL='+$script:fail)
if($script:fail){exit 1}
