# G126: off-screen production WinForms header capsule geometry.
# Compares legacy drawing byte-for-byte with the G125 baseline.
# No Host, Remote, update installation, network, or active GUI.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$src=[IO.File]::ReadAllText((Join-Path $root 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
# Compare against the exact previous approved source commit, not a local
# adjacent worktree (which may later be pruned or renamed).
$priorLines=@(& git -C $root show 05bf30c:Source/remote-window.ps1)
if($LASTEXITCODE -ne 0 -or $priorLines.Count -lt 100){throw 'G125_BASELINE_GIT_READ_FAILED'}
$old=[string]::Join([Environment]::NewLine,$priorLines)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name) {
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseInput($src,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'product GUI still parses under WinPS 5.1'
$start='public class RdcStatusIndicator : Control {'
$end='public class RdcBufferedPanel : Panel {'
function Extract([string]$inputText){
 $a=$inputText.IndexOf($start,[StringComparison]::Ordinal)
 $b=$inputText.IndexOf($end,$a,[StringComparison]::Ordinal)
 if($a -lt 0 -or $b -le $a){throw 'INDICATOR_SOURCE_EXTRACTION_MISSING'}
 return $inputText.Substring($a,$b-$a)
}
$imports="using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Windows.Forms;"+[Environment]::NewLine
Add-Type -TypeDefinition ($imports+(Extract $src)) -ReferencedAssemblies @('System','System.Drawing','System.Windows.Forms')
Add-Type -TypeDefinition ($imports+(Extract $old).Replace('RdcStatusIndicator','RdcStatusIndicatorBaseline')) -ReferencedAssemblies @('System','System.Drawing','System.Windows.Forms')
$priorCapsule=(Extract $src).Replace('height = 39, radius = 6','height = 40, radius = 6').Replace('RdcStatusIndicator','RdcStatusIndicator40')
Add-Type -TypeDefinition ($imports+$priorCapsule) -ReferencedAssemblies @('System','System.Drawing','System.Windows.Forms')
foreach($color in @([Drawing.Color]::PaleGreen,[Drawing.Color]::Khaki,[Drawing.Color]::LightCoral,[Drawing.Color]::Gray)){
 $previous=New-Object RdcStatusIndicator40
 $current=New-Object RdcStatusIndicator
 $previous.Size=$current.Size=[Drawing.Size]::new(32,54)
 $previous.OwnerCapsule=$current.OwnerCapsule=$true
 $previous.BackColor=$current.BackColor=[Drawing.Color]::FromArgb(29,32,36)
 $previous.IndicatorColor=$current.IndicatorColor=$color
 $a=[Drawing.Bitmap]::new(32,54);$b=[Drawing.Bitmap]::new(32,54)
 try{
  $previous.DrawToBitmap($a,[Drawing.Rectangle]::new(0,0,32,54))
  $current.DrawToBitmap($b,[Drawing.Rectangle]::new(0,0,32,54))
  $upperDiff=0;$endDiff=0
  for($y=0;$y -lt 54;$y++){
   for($x=0;$x -lt 32;$x++){
    if($a.GetPixel($x,$y).ToArgb() -ne $b.GetPixel($x,$y).ToArgb()){
     if($y -lt 34){$upperDiff++}else{$endDiff++}
    }
   }
  }
  Check ($upperDiff -eq 0 -and $endDiff -gt 0) ('only lower end changes; top and highlight pixel exact '+$color.Name)
 }finally{$a.Dispose();$b.Dispose();$previous.Dispose();$current.Dispose()}
}
Check ($src.Contains('$statusDot.OwnerCapsule = [bool]$OwnerGui')) 'new capsule activated only for Owner GUI'
Check ($src.Contains('const int width = 13, height = 39, radius = 6;') -and
       $src.Contains('path.AddArc(capX,capY,d,d,180,90)')) 'capsule uses measured scrollbar thumb radius and geometry'
Check ($src.Contains('$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,38)))') -and
       $src.Contains('$top.Padding = if($OwnerGui){[Windows.Forms.Padding]::new(2,9,13,9)}else{') -and
       $src.Contains('[Windows.Forms.Padding]::new(16,9,16,9)') -and
       $src.Contains('$titleHost.Dock=[Windows.Forms.DockStyle]::Fill') -and
       $src.Contains('$top.SetRowSpan($statusDot,2)')) 'Owner-only left padding 2px, legacy 16px; header 38px column and row span preserved'
Check ($src.Contains('public int IdleWidth') -eq $false) 'update notice renderer remains in separate module'
foreach($color in @([Drawing.Color]::PaleGreen,[Drawing.Color]::Khaki,[Drawing.Color]::LightCoral)) {
 foreach($owner in @($false,$true)) {
  $form=New-Object Windows.Forms.Form
  $form.Font=New-Object Drawing.Font('Segoe UI',10)
  $form.Size=[Drawing.Size]::new(1074,500)
  $form.StartPosition='Manual'
  $form.Location=[Drawing.Point]::new(-12000,-12000)
  $form.BackColor=[Drawing.Color]::FromArgb(29,32,36)
  $form.ForeColor=[Drawing.Color]::Gainsboro
  $top=New-Object Windows.Forms.TableLayoutPanel
  $top.Dock='Top';$top.Height=78
  $top.Padding=if($owner){[Windows.Forms.Padding]::new(2,9,13,9)}else{[Windows.Forms.Padding]::new(16,9,16,9)}
  $top.ColumnCount=3;$top.RowCount=2
  [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,38))
  [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
  [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,$(if($owner){307}else{304})))
  [void]$top.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,32))
  [void]$top.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
  $dot=New-Object RdcStatusIndicator
  $dot.Dock='Fill';$dot.OwnerCapsule=$owner;$dot.IndicatorColor=$color
  $title=New-Object Windows.Forms.Label
  $title.Text='RDC Relay  —  Подключён'
  $title.AutoSize=$true;$title.TextAlign='MiddleLeft'
  $title.Margin=[Windows.Forms.Padding]::new(0,3,8,0)
  $title.Font=New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
  $titleHost=New-Object Windows.Forms.FlowLayoutPanel
  $titleHost.Dock='Fill';$titleHost.WrapContents=$false;$titleHost.Margin=[Windows.Forms.Padding]::new(0)
  $titleHost.Padding=[Windows.Forms.Padding]::new(0)
  [void]$titleHost.Controls.Add($title)
  $detail=New-Object Windows.Forms.Label
  $detail.Dock='Fill';$detail.TextAlign='MiddleLeft'
  $detail.ForeColor=[Drawing.Color]::Silver
  $detail.Text='Сессия под управлением Host; доступна работа с инструментами.'
  [void]$top.Controls.Add($dot,0,0);$top.SetRowSpan($dot,2)
  [void]$top.Controls.Add($titleHost,1,0);[void]$top.Controls.Add($detail,1,1)
  $actionCell=New-Object Windows.Forms.Panel
  $actionCell.Dock='Fill';$actionCell.Margin=[Windows.Forms.Padding]::new(0)
  [void]$top.Controls.Add($actionCell,2,0);$top.SetRowSpan($actionCell,2)
  [void]$form.Controls.Add($top)
  try{
   $form.Show();$top.PerformLayout();$titleHost.PerformLayout()
   $expectedDotX=if($owner){5}else{19}
   $expectedTitleX=if($owner){40}else{54}
   $expectedDetailX=if($owner){43}else{57}
   Check ($dot.Bounds -eq [Drawing.Rectangle]::new($expectedDotX,12,32,54) -and
     $titleHost.Left -eq $expectedTitleX -and $detail.Left -eq $expectedDetailX) ('capsule and both text lines move 1px right from G127 only for Owner='+$owner+' color='+$color.Name)
   Check ($actionCell.Left -eq ($top.ClientSize.Width-16-304) -and
      $actionCell.Width -eq $(if($owner){307}else{304}) -and $top.Height -eq 78 -and
      $top.Padding.Top -eq 9 -and $top.Padding.Bottom -eq 9) ('right action cell extends 3px for ambient shadow, left edge and vertical geometry fixed owner='+$owner+' color='+$color.Name)
   $bmp=[Drawing.Bitmap]::new($top.Width,$top.Height)
   try{
    $top.DrawToBitmap($bmp,[Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height))
    $inkTop=999;$inkBottom=-1;$firstLower=999;$lastUpper=-1
    for($y=9;$y -lt 69;$y++){
     $seen=0
     for($x=$detail.Left;$x -lt [Math]::Min($detail.Right,620);$x++){
      $c=$bmp.GetPixel($x,$y)
      if($c.R -gt 125 -and $c.G -gt 125 -and $c.B -gt 125){$seen++}
     }
     if($seen -gt 2){
      if($y -lt 41){$inkTop=[Math]::Min($inkTop,$y);$lastUpper=[Math]::Max($lastUpper,$y)}
      else{$firstLower=[Math]::Min($firstLower,$y);$inkBottom=[Math]::Max($inkBottom,$y)}
     }
    }
    Check ($inkTop -eq 20 -and $lastUpper -eq 35 -and $firstLower -eq 50 -and $inkBottom -eq 61) ('actual two-row ink geometry preserved owner='+$owner+' color='+$color.Name+' upper='+$inkTop+'..'+$lastUpper+' lower='+$firstLower+'..'+$inkBottom+' titleRect='+$title.Bounds+' detailRect='+$detail.Bounds)
    if($owner){
     $rim=if([Windows.Forms.SystemInformation]::HighContrast){$color}else{[Drawing.Color]::FromArgb([int][Math]::Truncate($color.R*0.70),[int][Math]::Truncate($color.G*0.70),[int][Math]::Truncate($color.B*0.70))}
     $minX=999;$maxX=-1;$minY=999;$maxY=-1
     for($y=12;$y -lt 67;$y++){
      for($x=$dot.Left;$x -lt $dot.Right;$x++){
       $pixel=$bmp.GetPixel($x,$y)
       if([Math]::Abs([int]$pixel.R-[int]$rim.R) -le 3 -and
         [Math]::Abs([int]$pixel.G-[int]$rim.G) -le 3 -and
         [Math]::Abs([int]$pixel.B-[int]$rim.B) -le 3){
        $minX=[Math]::Min($minX,$x);$maxX=[Math]::Max($maxX,$x)
        $minY=[Math]::Min($minY,$y);$maxY=[Math]::Max($maxY,$y)
       }
      }
     }
     Check ($minX -eq 15 -and $maxX -eq 26 -and
       $minY -eq 21 -and $maxY -eq ($inkBottom-3)) ('capsule top stays at first-line ink and bottom rises exactly 1px from the accepted Y=59 owner='+$owner+' color='+$color.Name+' bbox='+$minX+','+$minY+'..'+$maxX+','+$maxY)
     Check ($minX -eq (29-14) -and ($expectedTitleX-($maxX+1)) -eq 13 -and
       $dot.Width -eq 32 -and $top.ColumnStyles[0].Width -eq 38) ('left edge one pixel right to 15px from G127 14px, text gap remains 13px owner='+$owner+' color='+$color.Name)
    }else{
     $oldDot=New-Object RdcStatusIndicatorBaseline
     $newStandalone=New-Object RdcStatusIndicator
     try {
      $oldDot.Size=$dot.Size;$oldDot.IndicatorColor=$color
      $newStandalone.Size=$dot.Size;$newStandalone.IndicatorColor=$color
      $newStandalone.OwnerCapsule=$false
      $a=[Drawing.Bitmap]::new($dot.Width,$dot.Height)
      $b=[Drawing.Bitmap]::new($dot.Width,$dot.Height)
      try {
       $newStandalone.DrawToBitmap($a,[Drawing.Rectangle]::new(0,0,$dot.Width,$dot.Height))
       $oldDot.DrawToBitmap($b,[Drawing.Rectangle]::new(0,0,$dot.Width,$dot.Height))
       $diff=0
       for($y=0;$y -lt $dot.Height;$y++){
        for($x=0;$x -lt $dot.Width;$x++){
         if($a.GetPixel($x,$y).ToArgb() -ne $b.GetPixel($x,$y).ToArgb()){$diff++}
        }
       }
       Check ($diff -eq 0) ('legacy 18px circle pixel-identical owner='+$owner+' color='+$color.Name)
      }finally{$a.Dispose();$b.Dispose()}
     }finally{$oldDot.Dispose();$newStandalone.Dispose()}
    }
   }finally{$bmp.Dispose()}
  }finally{$form.Close();$form.Dispose()}
 }
}
Write-Output ('RC1_STATUS_CAPSULE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
