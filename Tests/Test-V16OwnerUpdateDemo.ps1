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
 -not $source.Contains("$"+'form.Add_Shown({ Start-RdcUpdateNoticePreview '+"'1.6.0 RC2' })") -and
 $source.Contains('The Owner timer checks the published stable') -and
 $source.Contains('if($OwnerGui)')) 'Owner GUI starts idle and NEVER announces synthetic RC2 on Shown'
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
 $boundsField=[RdcUpdateNoticeStrip].GetField('buttonBounds',[Reflection.BindingFlags]'Instance,NonPublic')
 $ownerBounds=[Drawing.Rectangle]$boundsField.GetValue($script:rdcNoticeControl)
 Check ($ownerBounds.Y -eq 1 -and $ownerBounds.Height -eq 22 -and
  $ownerBounds.Bottom -eq 23) 'Owner update button extends 1px upward; bottom edge unchanged'
 Check ($noticeSource.Contains('Rectangle textBounds=new Rectangle(buttonX,Math.Max(2,(Height-21)/2),buttonWidth,21);') -and
  $noticeSource.Contains('textBounds.Height+1) : textBounds;') -and
  $noticeSource.Contains('g.DrawString(newText,buttonFont,ink,(RectangleF)textBounds,centered);')) 'Update caption remains at unchanged 21px text rectangle and font'
 $legacyNotice=New-Object RdcUpdateNoticeStrip
 $legacyBitmap=$null
 try{
  $legacyNotice.CompactOwner=$false
  $legacyNotice.VisualPreviewOnly=$true
  $legacyNotice.Size=New-Object Drawing.Size(590,25)
  $legacyNotice.Font=$form.Font
  $legacyNotice.Begin('1.6.0 RC1','1.6.0 RC2','Synthetic preview')
  $legacyNotice.FinishAnimationForTest()
  $legacyBitmap=New-Object Drawing.Bitmap(590,25)
  $legacyNotice.DrawToBitmap($legacyBitmap,(New-Object Drawing.Rectangle(0,0,590,25)))
  $legacyBounds=[Drawing.Rectangle]$boundsField.GetValue($legacyNotice)
  Check ($legacyBounds.Y -eq 2 -and $legacyBounds.Height -eq 21) 'Legacy update button unchanged at 2px top and 21px height'
 }finally{
  if($legacyBitmap){$legacyBitmap.Dispose()}
  $legacyNotice.Dispose()
 }
 Check (-not $script:rdcNoticeControl.ButtonReady -and
  $script:rdcNoticeControl.AccessibleRole -eq [Windows.Forms.AccessibleRole]::StaticText -and
  -not $script:rdcNoticeControl.TabStop) 'fake update is inaccessible as an interactive install control'
 Hide-RdcUpdateNotice
 Check ($bottom.ColumnStyles[1].Width -eq 115 -and
  -not $script:rdcNoticeControl.IsActive) 'manual reset remains available without changing geometry'
 # The Owner RC1 demo is shown ONCE at GUI Shown. Test its real timer
 # handler by invoking WinForms OnTick without a message pump or Remote.
 $script:rdcNoticePreviewShown=$false
 Start-RdcUpdateNoticePreview '1.6.0 RC2'
 $previewTimer=$script:rdcNoticePreviewTimer
 Check ($previewTimer -and $previewTimer.Enabled -and
  -not $script:rdcNoticePreviewShown) 'one-shot preview schedules a single delayed reveal'
 $script:rdcNoticePreviewNextAt=(Get-Date).AddSeconds(-1)
 $tickMethod=[Windows.Forms.Timer].GetMethod('OnTick',
  [Reflection.BindingFlags]'Instance,NonPublic')
 [void]$tickMethod.Invoke($previewTimer,@([EventArgs]::Empty))
 Check ($script:rdcNoticePreviewShown -and
  -not $script:rdcNoticePreviewTimer -and
  $script:rdcNoticeActive) 'first preview tick shows update and disposes replay timer'
 $activeVersion=$script:rdcNoticeControl.OfferedVersion
 Start-RdcUpdateNoticePreview '1.6.0 RC3'
 Check (-not $script:rdcNoticePreviewTimer -and
  $script:rdcNoticeControl.OfferedVersion -ceq $activeVersion) 'repeat calls cannot restart animation or alter offered version'
 Check ($noticeSource.Contains('if ($script:rdcNoticePreviewShown -or $script:rdcNoticePreviewTimer) { return }') -and
  -not $noticeSource.Contains('$now.AddSeconds(5.8)') -and
  -not $noticeSource.Contains('$now.AddSeconds(1.4)')) 'old automatic hide-and-replay schedule removed'
}finally{
 if($script:rdcNoticeControl){Dispose-RdcUpdateNotice}
 if($active){$active.Dispose()}
 if($idle){$idle.Dispose()}
 $tip.Dispose();$form.Dispose()
}
Write-Output ('RC1_OWNER_UPDATE_DEMO_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
