# Isolated GUI rendering test for RC1 built-in update animation demo.
# Never launches Remote, performs network access or installs an update.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Join-Path $PSScriptRoot '..\Source'
$form=New-Object Windows.Forms.Form
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.Width=980;$form.Height=160
$bottom=New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock='Bottom';$bottom.Height=38
$bottom.ColumnCount=2
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,115)))
$form.Controls.Add($bottom)
$hintHost=New-Object Windows.Forms.FlowLayoutPanel
$bottom.Controls.Add($hintHost,1,0)
$hint=New-Object Windows.Forms.Label
$hint.Text='';$hint.Font=$form.Font
$tip=New-Object Windows.Forms.ToolTip
$appVersion='1.6.0 RC1'
$Preview=$false
$SelfTest=$false
$script:ownerUpdateDemoMode=$true
$script:enableUpdateNotice=$true
$script:rdcNoticePreviewTimer=$null
$script:initializing=$false
$script:remoteOperation=$false
$script:updateInstallRequested=$false
$pass=0;$fail=0
function Check([bool]$v,[string]$reason){
 if($v){$script:pass++;Write-Output ('PASS '+$reason)}
 else{$script:fail++;Write-Output ('FAIL '+$reason)}
}
function NonBackgroundPixels([Drawing.Bitmap]$bmp){
 $count=0
 for($y=0;$y -lt $bmp.Height;$y++){
  for($x=0;$x -lt $bmp.Width;$x++){
   $pixel=$bmp.GetPixel($x,$y)
   if($pixel.R -gt 120 -and $pixel.G -gt 110){$count++}
  }
 }
 return $count
}
$source=[IO.File]::ReadAllText((Join-Path $root 'remote-window.ps1'),[Text.Encoding]::UTF8)
$noticeSource=[IO.File]::ReadAllText((Join-Path $root 'update-notice.ps1'),[Text.Encoding]::UTF8)
Check ($source.Contains('if($script:ownerUpdateDemoMode){$script:enableUpdateNotice=$true}') -and
 $source.Contains("$"+'form.Add_Shown({ Start-RdcUpdateNoticePreview '+"'1.6.0 RC2' })") -and
 $source.Contains('if($OwnerGui)')) 'RC1 Owner launches embedded animation after GUI is shown'
Check ($noticeSource.Contains('if ($SelfTest -or $Preview -or $script:ownerUpdateDemoMode -or') -and
 $noticeSource.Contains('if ($SelfTest -or $Preview -or $script:ownerUpdateDemoMode -or') -and
 $noticeSource.Contains('public bool ButtonReady { get { return !visualPreviewOnly') -and
 $noticeSource.Contains('AccessibleRole.StaticText')) 'demo forbids real install actions and is noninteractive'
. (Join-Path $root 'update-notice.ps1')
try{
 Check ($bottom.ColumnStyles[1].Width -eq 115 -and $script:rdcNoticeControl.CompactOwner -and
  $script:rdcNoticeControl.VisualPreviewOnly -and
  $noticeSource.Contains('Color muted=compactOwner ? Color.Silver : Color.FromArgb(128,128,128);') -and
  $script:rdcNoticeControl.ForeColor.ToArgb() -ne 0 -and
  -not $script:rdcNoticeControl.ButtonReady) 'Owner idle right column is compact, silver and does not offer a button'
 Check ($bottom.Controls.Contains($script:rdcNoticeControl) -and
  -not $bottom.Controls.Contains($hintHost) -and
  [Math]::Abs($script:rdcNoticeControl.Font.SizeInPoints-$form.Font.SizeInPoints) -lt 0.01) 'same parent footer replaces old version and inherits 10pt font'
 $idle=New-Object Drawing.Bitmap(115,25)
 $script:rdcNoticeControl.Width=115
 $script:rdcNoticeControl.Height=25
 $script:rdcNoticeControl.DrawToBitmap($idle,(New-Object Drawing.Rectangle(0,0,115,25)))
 $idlePixels=NonBackgroundPixels $idle
 Check ($idlePixels -gt 10) 'idle version is actually painted in 25px footer'
 Show-RdcUpdateNotice '1.6.0 RC2'
 $script:rdcNoticeControl.FinishAnimationForTest()
 $expanded=$script:rdcNoticeControl.SuggestedWidth
 $bottom.ColumnStyles[1].Width=$expanded
 $bottom.PerformLayout()
 $script:rdcNoticeControl.Width=$expanded
 $active=New-Object Drawing.Bitmap($expanded,25)
 $script:rdcNoticeControl.DrawToBitmap($active,(New-Object Drawing.Rectangle(0,0,$expanded,25)))
 $gold=0
 for($y=0;$y -lt $active.Height;$y++){
  for($x=0;$x -lt $active.Width;$x++){
   $pixel=$active.GetPixel($x,$y)
   if($pixel.R -gt 160 -and $pixel.G -gt 115 -and $pixel.B -lt 160){$gold++}
  }
 }
 Check ($expanded -eq 295 -and $script:rdcNoticeControl.IsActive -and
  $script:rdcNoticeControl.OfferedVersion -ceq '1.6.0 RC2') 'animation expands from 115 to 295 pixels with synthetic RC2'
 Check ($gold -gt 10 -and (NonBackgroundPixels $active) -gt $idlePixels) 'expanded frame visibly paints golden update button'
 Check (-not $script:rdcNoticeControl.ButtonReady -and
  $script:rdcNoticeControl.AccessibleRole -eq [Windows.Forms.AccessibleRole]::StaticText -and
  -not $script:rdcNoticeControl.TabStop) 'fake update is inaccessible as an interactive install control'
 Hide-RdcUpdateNotice
 Check ($bottom.ColumnStyles[1].Width -eq 115 -and
  -not $script:rdcNoticeControl.IsActive) 'animation returns to compact idle and can replay'
}finally{
 if($script:rdcNoticeControl){Dispose-RdcUpdateNotice}
 if($active){$active.Dispose()}
 if($idle){$idle.Dispose()}
 $tip.Dispose();$form.Dispose()
}
Write-Output ('RC1_OWNER_UPDATE_DEMO_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
