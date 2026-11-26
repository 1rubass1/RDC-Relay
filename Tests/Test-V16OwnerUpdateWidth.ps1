# G123 standalone, fake-only layout and measured-width regression without a synthetic preview.
# Exercises actual production update renderer with a fixed Help cell.
# Never starts Host/Remote, installs, reads network, or touches clipboard.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$form=New-Object Windows.Forms.Form
$form.Font=[Drawing.Font]::new('Segoe UI',10)
$form.BackColor=[Drawing.Color]::FromArgb(29,32,36)
$form.Size=[Drawing.Size]::new(1150,145)
$form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
$form.Location=[Drawing.Point]::new(-12000,-12000)
$bottom=New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock='Bottom';$bottom.Height=38
$bottom.BackColor=$form.BackColor
$bottom.Padding=[Windows.Forms.Padding]::new(12,7,7,6)
$bottom.ColumnCount=3;$bottom.RowCount=1
[void]$bottom.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,25))
[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,110))
[void]$bottom.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,25))
$hintHost=New-Object Windows.Forms.FlowLayoutPanel
$hintHost.Dock='Fill'
$hintHost.Margin=[Windows.Forms.Padding]::new(0)
[void]$bottom.Controls.Add($hintHost,1,0)
$helpButton=New-Object Windows.Forms.Button
$helpButton.Size=[Drawing.Size]::new(24,24)
$helpButton.Margin=[Windows.Forms.Padding]::new(1,0,0,0)
$helpButton.Anchor=[Windows.Forms.AnchorStyles]::None
[void]$bottom.Controls.Add($helpButton,2,0)
[void]$form.Controls.Add($bottom)
$hint=New-Object Windows.Forms.Label;$hint.Text='';$hint.Font=$form.Font
$tip=New-Object Windows.Forms.ToolTip
$appVersion='1.6.0 RC1'
$OwnerGui=$true;$SelfTest=$false;$Preview=$false
$script:ownerUpdateDemoMode=$true
$script:enableUpdateNotice=$true
$script:initializing=$false
$script:remoteOperation=$false
$script:updateInstallRequested=$false
$script:rdcNoticePreviewTimer=$null
$pass=0;$fail=0
function Check([bool]$yes,[string]$msg){
 if($yes){$script:pass++;Write-Output ('PASS '+$msg)}
 else{$script:fail++;Write-Output ('FAIL '+$msg)}
}
function TextWidth([string]$text,[Drawing.Font]$font){
 return [Windows.Forms.TextRenderer]::MeasureText($text,$font,
  [Drawing.Size]::new(10000,25),
  ([Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::VerticalCenter)).Width
}
. (Join-Path $root 'Source\update-notice.ps1')
try{
 $form.Show();$form.PerformLayout();$bottom.PerformLayout()
 $helpX=$helpButton.Left
 $rightGap=$bottom.ClientSize.Width-$helpButton.Right
 $normalIdle=0;$longIdle=0;$normalFull=0;$longFull=0
 $samples=@(
  @{Installed='1.6.0 RC1';Offered='1.6.0 RC2'},
  @{Installed='1.6.0 RC123456';Offered='1.6.0 RC1234567'},
  @{Installed='12.345.678 RC123456';Offered='12.345.678 RC1234567'},
  @{Installed='1.6.0 RC1';Offered='123.456.789 RC123456789012345'},
  @{Installed='123.456.789 RC123456789012345';Offered='1.6.0 RC2'}
 )
 $boundsField=[RdcUpdateNoticeStrip].GetField('buttonBounds',[Reflection.BindingFlags]'Instance,NonPublic')
 for($i=0;$i -lt $samples.Count;$i++){
  $installed=[string]$samples[$i].Installed
  $offered=[string]$samples[$i].Offered
  $appVersion=$installed
  $script:rdcNoticeControl.SetIdle($installed,'')
  $base=$script:rdcNoticeControl.IdleWidth
  $oldW=TextWidth ('v'+$installed) $script:rdcNoticeControl.Font
  $expectedBase=[Math]::Max(115,$oldW+12)
  $bottom.ColumnStyles[1].Width=$base
  $bottom.PerformLayout()
  Check ($base -eq $expectedBase -and $script:rdcNoticeControl.Right -lt $helpX) ('measured idle width #'+$i)
  Show-RdcUpdateNotice $offered
  $atStart=$script:rdcNoticeControl.SuggestedWidth
  Start-Sleep -Milliseconds 65
  $intermediate=$script:rdcNoticeControl.SuggestedWidth
  $newFont=[Drawing.Font]::new('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
  try {$buttonW=[Math]::Max(84,(TextWidth ('v'+$offered) $newFont)+22)}
  finally {$newFont.Dispose()}
  $expectedFull=[Math]::Max($base+180,6+$oldW+7+19+7+$buttonW+6)
  $script:rdcNoticeControl.FinishAnimationForTest()
  $full=$script:rdcNoticeControl.SuggestedWidth
  $bottom.ColumnStyles[1].Width=$full
  $bottom.PerformLayout()
  $bmp=[Drawing.Bitmap]::new($script:rdcNoticeControl.Width,25)
  try{
   $script:rdcNoticeControl.DrawToBitmap($bmp,
    [Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height))
   $bounds=[Drawing.Rectangle]$boundsField.GetValue($script:rdcNoticeControl)
   $gold=0
   for($y=0;$y -lt 25;$y+=2){
    for($x=0;$x -lt $bmp.Width;$x+=2){
     $p=$bmp.GetPixel($x,$y)
     if($p.R -gt 160 -and $p.G -gt 110 -and $p.B -lt 170){$gold++}
    }
   }
   Check ($full -eq $expectedFull -and $atStart -ge $base -and
     $atStart -le $intermediate -and $intermediate -le $full) ('monotone animation & measured expanded width #'+$i)
   # Paint uses TextRenderer.MeasureText(Graphics,...): the no-Graphics
   # overload may be 8px more conservative, so compare the exact overload.
   $paintFont=[Drawing.Font]::new('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
   $paintGraphics=[Drawing.Graphics]::FromImage($bmp)
   try{
    $flags=[Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::VerticalCenter
    $paintButtonW=[Math]::Max(84,[Windows.Forms.TextRenderer]::MeasureText($paintGraphics,('v'+$offered),$paintFont,[Drawing.Size]::new(10000,25),$flags).Width+22)
   }finally{$paintGraphics.Dispose();$paintFont.Dispose()}
   Check ($bounds.Left -ge ($oldW+25) -and $bounds.Width -eq $paintButtonW -and
     $bounds.Right -le ($full-6) -and $gold -gt 10) ('both version texts and button fit painted frame #'+$i)
   Check ($helpButton.Left -eq $helpX -and $rightGap -eq 7 -and
     $script:rdcNoticeControl.Right -lt $helpButton.Left) ('Help button remains fixed and separate #'+$i)
  }finally{$bmp.Dispose()}
  if($i -eq 0){$normalIdle=$base;$normalFull=$full}
  if($i -eq 2){$longIdle=$base;$longFull=$full}
  Hide-RdcUpdateNotice
  Check ($bottom.ColumnStyles[1].Width -eq $base -and
    -not $script:rdcNoticeControl.IsActive) ('reset uses measured idle width #'+$i)
 }
 Check ($normalIdle -eq 115 -and $normalFull -eq 295 -and
    $longIdle -gt 115 -and $longFull -gt 295) 'accepted normal geometry preserved, long labels expand'
 # Production Owner never invokes synthetic preview or disables stable polling.
 $productionGui=[IO.File]::ReadAllText((Join-Path $root 'Source/remote-window.ps1'),[Text.Encoding]::UTF8)
 $productionNotice=[IO.File]::ReadAllText((Join-Path $root 'Source/update-notice.ps1'),[Text.Encoding]::UTF8)
 $buildSource=[IO.File]::ReadAllText((Join-Path $root 'Scripts/build-rc1-full.ps1'),[Text.Encoding]::UTF8)
 Check (-not $productionGui.Contains('ownerUpdateLoopProbe') -and
        -not $productionGui.Contains('updateAnimationLoopTest') -and
        -not $productionGui.Contains('$form.Add_Shown({Start-RdcUpdateNoticePreview') -and
        -not $productionNotice.Contains('Invoke-RdcUpdateLoopVisualTick') -and
        -not $buildSource.Contains('updateAnimationLoopTest')) 'no synthetic cyclic demo in Owner GUI or packaged marker'
 Check ($productionNotice.Contains('https://api.github.com/repos/Rubo-Facility/RDC-Relay/git/ref/heads/stable') -and
        $productionNotice.Contains('function Update-RdcUpdateNoticePolling') -and
        $productionGui.Contains('if($script:ownerUpdateDemoMode){$script:enableUpdateNotice=$true}')) 'genuine stable-only update notice route retained'
 Check (-not $script:rdcNoticeControl.ButtonReady -and
        $script:rdcNoticeControl.VisualPreviewOnly -and
        -not $script:updateInstallRequested) 'fake-only test cannot initiate installation'
}finally{
 if($script:rdcNoticeControl){Dispose-RdcUpdateNotice}
 $tip.Dispose();$form.Close();$form.Dispose()
}
Write-Output ('RC1_OWNER_UPDATE_WIDTH_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
