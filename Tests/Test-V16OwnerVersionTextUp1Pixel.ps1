# Exact real-renderer A/B regression: the only difference is a 1px Y
# offset for the Owner RC1 installed-version glyphs.
# Fake-only WinForms, off-screen; no real Host, Remote, installer, network.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'Source\update-notice.ps1'),[Text.Encoding]::UTF8)
$startMarker="Add-Type -TypeDefinition @'"
$start=$source.IndexOf($startMarker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'RENDERER_SOURCE_MISSING'}
$start+=$startMarker.Length
$stop=$source.IndexOf("'@ -ReferencedAssemblies",$start,[StringComparison]::Ordinal)
if($stop -lt 0){throw 'RENDERER_SOURCE_END_MISSING'}
$baselineCode=$source.Substring($start,$stop-$start)
$up='new Rectangle(versionX,y-(compactOwner ? 1 : 0),oldWidth,Height),muted,tf);'
$original='new Rectangle(versionX,y,oldWidth,Height),muted,tf);'
if($baselineCode.Split([string[]]@($up),[StringSplitOptions]::None).Count -ne 2){throw 'VERSION_Y_OFFSET_ANCHOR_NOT_UNIQUE'}
$baselineCode=$baselineCode.Replace($up,$original).Replace('RdcUpdateNoticeStrip','RdcUpdateNoticeStripBaseline')
Add-Type -TypeDefinition $baselineCode -ReferencedAssemblies @('System','System.Core','System.Drawing','System.Windows.Forms')
$form=New-Object Windows.Forms.Form
$form.Font=[Drawing.Font]::new('Segoe UI',10)
$form.BackColor=[Drawing.Color]::FromArgb(29,32,36)
$form.Size=[Drawing.Size]::new(1150,170)
$form.Location=[Drawing.Point]::new(-12000,-12000)
$form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
$bottom=New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock='Bottom';$bottom.Height=38;$bottom.BackColor=$form.BackColor
$bottom.Padding=[Windows.Forms.Padding]::new(12,7,7,6)
$bottom.ColumnCount=3;$bottom.RowCount=1
[void]$bottom.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,25))
[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,115))
[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,25))
$hintHost=New-Object Windows.Forms.FlowLayoutPanel;$hintHost.Dock='Fill';$hintHost.Margin=[Windows.Forms.Padding]::new(0)
[void]$bottom.Controls.Add($hintHost,1,0)
$help=New-Object Windows.Forms.Button;$help.Size=[Drawing.Size]::new(24,24)
$help.Margin=[Windows.Forms.Padding]::new(1,0,0,0);$help.Anchor=[Windows.Forms.AnchorStyles]::None
[void]$bottom.Controls.Add($help,2,0);[void]$form.Controls.Add($bottom)
$hint=New-Object Windows.Forms.Label;$hint.Font=$form.Font;$hint.Text=''
$tip=New-Object Windows.Forms.ToolTip
$appVersion='1.6.0 RC1';$OwnerGui=$true;$SelfTest=$false;$Preview=$false
$script:ownerUpdateDemoMode=$true;$script:enableUpdateNotice=$true
$script:initializing=$false;$script:remoteOperation=$false;$script:updateInstallRequested=$false
$pass=0;$fail=0
function Check([bool]$yes,[string]$msg){
 if($yes){$script:pass++;Write-Output ('PASS '+$msg)}
 else{$script:fail++;Write-Output ('FAIL '+$msg)}
}
. (Join-Path $root 'Source\update-notice.ps1')
$base=New-Object RdcUpdateNoticeStripBaseline
$base.Font=$script:rdcNoticeControl.Font
$base.BackColor=$script:rdcNoticeControl.BackColor
$base.ForeColor=$script:rdcNoticeControl.ForeColor
$base.CompactOwner=$true;$base.VisualPreviewOnly=$true
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$watchField=[RdcUpdateNoticeStripBaseline].GetField('watch',$flags)
$realWatchField=[RdcUpdateNoticeStrip].GetField('watch',$flags)
$watch=[Diagnostics.Stopwatch]::new()
$watchField.SetValue($base,$watch)
$realWatchField.SetValue($script:rdcNoticeControl,$watch)
$buttonFieldNew=[RdcUpdateNoticeStrip].GetField('buttonBounds',$flags)
$buttonFieldOld=[RdcUpdateNoticeStripBaseline].GetField('buttonBounds',$flags)
function Snapshot([int]$w){
 $strip=$script:rdcNoticeControl
 $bottom.ColumnStyles[1].Width=$w
 $bottom.PerformLayout()
 $strip.Size=[Drawing.Size]::new($w,25)
 $base.Size=[Drawing.Size]::new($w,25)
 if($strip.Width -ne $w -or $base.Width -ne $w){throw ('RENDER_SURFACE_WIDTH_MISMATCH active='+$strip.Width+' baseline='+$base.Width+' target='+$w)}
 $current=[Drawing.Bitmap]::new($w,25)
 $previous=[Drawing.Bitmap]::new($w,25)
 $rect=[Drawing.Rectangle]::new(0,0,$w,25)
 $strip.DrawToBitmap($current,$rect)
 $base.DrawToBitmap($previous,$rect)
 return @{Actual=$current;Prior=$previous}
}
function Assert-FrameMatch([string]$label,[string]$installed,[string]$offered,[bool]$active,[bool]$legacy){
 $strip=$script:rdcNoticeControl
 $w=$strip.SuggestedWidth
 $otherW=$base.SuggestedWidth
 Check ($w -eq $otherW -and $strip.IdleWidth -eq $base.IdleWidth -and
   $strip.ExpandedWidth -eq $base.ExpandedWidth) ($label+' widths and timing same')
 $images=Snapshot $w
 try{
  $a=$images.Actual;$b=$images.Prior
  $paintFont=$strip.Font
  $measure=[Drawing.Graphics]::FromImage($a)
  try{
   $tf=[Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::VerticalCenter
   $oldWidth=[Windows.Forms.TextRenderer]::MeasureText($measure,('v'+$installed),$paintFont,[Drawing.Size]::new(10000,25),$tf).Width
   $btnFont=[Drawing.Font]::new('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
   try{$btnWidth=[Math]::Max(84,[Windows.Forms.TextRenderer]::MeasureText($measure,('v'+$offered),$btnFont,[Drawing.Size]::new(10000,25),$tf).Width+22)}
   finally{$btnFont.Dispose()}
  }finally{$measure.Dispose()}
  $startX=$w-6-$oldWidth
  $endX=$w-6-$btnWidth-7-19-7-$oldWidth
  $time=if([bool]([RdcUpdateNoticeStrip].GetField('forceFinish',$flags).GetValue($strip))){1.0}else{$watch.Elapsed.TotalSeconds}
  $move=1.0-[Math]::Pow((1.0-[Math]::Min(1.0,[Math]::Max(0.0,$time/0.30))),3.0)
  if(-not $active){$move=0.0}
  $versionX=$startX-[int][Math]::Round(($startX-$endX)*$move)
  $allowedLeft=$versionX-2
  $allowedRight=$versionX+$oldWidth+2
  $outsideDiff=0;$insideDiff=0;$shifted=0;$colored=0;$allDiff=0
  for($y=0;$y -lt 25;$y++){
   for($x=0;$x -lt $w;$x++){
    $now=$a.GetPixel($x,$y).ToArgb()
    $was=$b.GetPixel($x,$y).ToArgb()
    if($now -ne $was){
      $allDiff++
      if($x -ge $allowedLeft -and $x -le $allowedRight){$insideDiff++}else{$outsideDiff++}
    }
    if(-not $legacy -and $x -ge $allowedLeft -and $x -le $allowedRight -and
      $y -gt 1 -and $y -lt 23){
      if($was -ne $strip.BackColor.ToArgb() -and
        $was -eq ([Drawing.Color]::Silver.ToArgb())){
        $colored++
        if($now -eq $b.GetPixel($x,$y+1).ToArgb()){$shifted++}
      }
    }
   }
  }
  $boundsNew=[Drawing.Rectangle]$buttonFieldNew.GetValue($strip)
  $boundsOld=[Drawing.Rectangle]$buttonFieldOld.GetValue($base)
  Check ($boundsNew.Equals($boundsOld) -and $outsideDiff -eq 0) ($label+' arrow/button/control pixels unchanged outside version X (diff='+$outsideDiff+')')
  if($legacy){
   Check ($allDiff -eq 0) ($label+' legacy framebuffer entirely unchanged')
  }else{
   Check ($insideDiff -gt 20 -and $colored -gt 10 -and $shifted -ge [int]($colored*0.98)) ($label+' only installed-version glyphs move up 1px (shift='+$shifted+'/'+$colored+', diff='+$insideDiff+')')
  }
 }finally{$images.Actual.Dispose();$images.Prior.Dispose()}
}
try{
 $form.Show();$bottom.PerformLayout()
 foreach($pair in @(
  @{Old='1.6.0 RC1';New='1.6.0 RC2'},
  @{Old='1.6.0 RC123456';New='1.6.0 RC1234567'},
  @{Old='123.456.789 RC123456789012345';New='1.6.0 RC2'}
 )){
  $installed=[string]$pair.Old;$offered=[string]$pair.New
  $script:rdcNoticeControl.CompactOwner=$true;$base.CompactOwner=$true
  $script:rdcNoticeControl.SetIdle($installed,'');$base.SetIdle($installed,'')
  Assert-FrameMatch ('Owner idle '+$installed) $installed '' $false $false
  $script:rdcNoticeControl.Begin($installed,$offered,'')
  $base.Begin($installed,$offered,'')
  Start-Sleep -Milliseconds 140
  $watch.Stop()
  Assert-FrameMatch ('Owner moving '+$installed) $installed $offered $true $false
  $script:rdcNoticeControl.FinishAnimationForTest()
  $base.FinishAnimationForTest()
  Assert-FrameMatch ('Owner expanded '+$installed) $installed $offered $true $false
 }
 $installed='1.5.18';$offered='1.5.19'
 $script:rdcNoticeControl.CompactOwner=$false;$base.CompactOwner=$false
 $script:rdcNoticeControl.SetIdle($installed,'Close exits the window with its Remote process.')
 $base.SetIdle($installed,'Close exits the window with its Remote process.')
 Assert-FrameMatch 'Legacy idle' $installed '' $false $true
 $script:rdcNoticeControl.Begin($installed,$offered,'Close exits the window with its Remote process.')
 $base.Begin($installed,$offered,'Close exits the window with its Remote process.')
 $script:rdcNoticeControl.FinishAnimationForTest()
 $base.FinishAnimationForTest()
 Assert-FrameMatch 'Legacy expanded' $installed $offered $true $true
}finally{
 $base.Dispose()
 Dispose-RdcUpdateNotice
 $tip.Dispose();$form.Close();$form.Dispose()
}
Write-Output ('RC1_VERSION_TEXT_UP1_PIXEL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
