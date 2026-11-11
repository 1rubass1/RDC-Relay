# Isolated RC1 footer/activity minimum-height regression; no actual client is launched.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$ok,[string]$msg){
 if($ok){$script:pass++;Write-Output ('PASS '+$msg)}
 else{$script:fail++;Write-Output ('FAIL '+$msg)}
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'full GUI parses after pane adjustment'
Check ($source.Contains('$activityRowReserve=if($OwnerGui){Get-Rc1ActivityRowReserve $paneMinHeightPreferred}else{0}') -and
 $source.Contains('$activityPaneMinHeightPreferred=$paneMinHeightPreferred+$activityRowReserve') -and
 $source.Contains('$preferredMinimumHeight = 78 + 38 + $headerPaneMinHeightPreferred + $activityPaneMinHeightPreferred + 7 + 48') -and
 $source.Contains('if($OwnerGui){') -and
 $source.Contains('$windowFrameHeight=[Math]::Max(0,$form.Height-$form.ClientSize.Height)') -and
 $source.Contains('$minimumWindowHeight=[Math]::Min($windowHeight,78+38+7+2+$windowFrameHeight)') -and
 $source.Contains('$headerPaneMinHeightPreferred=if($OwnerGui){Get-Rc1HeaderBannerMinimum}else{$paneMinHeightPreferred}') -and
 $source.Contains('$activityDefaultHeight = $activityPaneMinHeightPreferred') -and
 $source.Contains('Set-ActivityPaneHeight (Get-EffectivePaneMinHeight)')) 'Owner bottom-edge minimum removes fixed one-line slack while keeping normal pane baseline'
$funcNames=@('Get-Rc1CompressedActivityHeight','Get-EffectivePaneMinHeight',
 'Get-ClampedActivityPaneHeight','Set-ActivityPaneHeight')
foreach($name in $funcNames){
 $def=$ast.Find({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name
 },$true)
 if(-not $def){throw 'Missing production function '+$name}
 . ([scriptblock]::Create($def.Extent.Text))
}
$headerMeasureDef=$ast.Find({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -ceq 'Get-Rc1HeaderBannerMinimum'
},$true)
if(-not $headerMeasureDef){throw 'Missing production six-row header banner calculator'}
. ([scriptblock]::Create($headerMeasureDef.Extent.Text))
$measureDef=$ast.Find({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -ceq 'Get-Rc1ActivityRowReserve'
},$true)
if(-not $measureDef){throw 'Missing production RichEdit row-reserve calculator'}
. ([scriptblock]::Create($measureDef.Extent.Text))
$probe=New-Object Windows.Forms.RichTextBox
$script:ownerTextFontFamily='Consolas'
$script:ownerEmojiFontFamily='Segoe UI Emoji'
$script:ownerEmojiEnabled=$true
$font=New-Object Drawing.Font($script:ownerTextFontFamily,10)
try {
 $probe.Font=$font
 $probe.BorderStyle=[Windows.Forms.BorderStyle]::None
 $probe.WordWrap=$false
 $probe.Text="Ag`nAg"
 [void]$probe.Handle
 $line=$probe.GetPositionFromCharIndex(3).Y-$probe.GetPositionFromCharIndex(0).Y
}finally{$probe.Dispose();$font.Dispose()}
$OwnerGui=$true
$paneMinHeightPreferred=125
$headerPaneMinHeightPreferred=Get-Rc1HeaderBannerMinimum
$activityRowReserve=Get-Rc1ActivityRowReserve $paneMinHeightPreferred
$activityPaneMinHeightPreferred=$paneMinHeightPreferred+$activityRowReserve
$contentHost=New-Object Windows.Forms.TableLayoutPanel
$contentHost.Size=New-Object Drawing.Size(800,440)
$contentHost.RowCount=2
[void]$contentHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$contentHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$activityPaneMinHeightPreferred)))
$headerVScroll=New-Object Windows.Forms.Panel
try{
 $ownerPitch=[int]$script:ownerJournalLinePitch
 $newBottomGap=($activityPaneMinHeightPreferred-17)-(8*$ownerPitch)
 Check ($line -ge 12 -and $line -le 35 -and
  $ownerPitch -ge $line -and $ownerPitch -le 35 -and
  $activityRowReserve -ge 1 -and
  $newBottomGap -eq 0 -and $activityPaneMinHeightPreferred -eq (8*$ownerPitch+17)) 'Owner minimum fits six events plus top and bottom blank rows after font change'
 Check ((($paneMinHeightPreferred-17+$activityRowReserve) % $ownerPitch) -eq 0) 'inner viewport aligns to text line pitch without double-counting existing space'
 Check (($line -ne 15 -or $ownerPitch -ne 15) -or ($activityRowReserve -eq 12 -and $activityPaneMinHeightPreferred -eq 137)) 'STARMER mixed glyphs use actual compact 15px row pitch, six events at 137px'
 $headerProbe=New-Object Windows.Forms.RichTextBox
 $headerFont=New-Object Drawing.Font($script:ownerTextFontFamily,9)
 try {
  $headerProbe.Font=$headerFont
  $headerProbe.WordWrap=$false
  $headerProbe.BorderStyle=[Windows.Forms.BorderStyle]::None
  $headerProbe.Text="Ag`nAg"
  [void]$headerProbe.Handle
  $headerPitch=$headerProbe.GetPositionFromCharIndex(3).Y-$headerProbe.GetPositionFromCharIndex(0).Y
  $expectedHeader=6*$headerPitch+7+2
  Check ($headerPaneMinHeightPreferred -eq $expectedHeader -and
   $headerPaneMinHeightPreferred -lt 125 -and
   $headerPaneMinHeightPreferred -ge 64) 'Owner header minimum fits six measured banner rows and divider'
  Check (($headerPitch -ne 14) -or ($headerPaneMinHeightPreferred -eq 93)) 'STARMER Consolas 9pt logo minimum restored to 93px'
  # Match the real Owner header: wrapped RichEdit, no native scrollbars,
  # wide text host and a separate external vertical scroll control.
  $headerProbe.WordWrap=$true
  $headerProbe.ScrollBars=[Windows.Forms.RichTextBoxScrollBars]::None
  $headerProbe.Width=800
  $headerProbe.Height=$headerPaneMinHeightPreferred-7
  $headerProbe.Text=[string]::Join("`n",@('Desktop Commander','Line 2','Line 3','Line 4','Line 5','Line 6'))
  $lastIndex=$headerProbe.Text.LastIndexOf('Line 6',[StringComparison]::Ordinal)
  $lastY=$headerProbe.GetPositionFromCharIndex($lastIndex).Y
  Check ($lastY+$headerPitch -le $headerProbe.ClientSize.Height) 'six-line Desktop Commander banner fully fits visible header viewport'
 }finally {$headerProbe.Dispose();$headerFont.Dispose()}
 Check ((Get-EffectivePaneMinHeight) -eq $activityPaneMinHeightPreferred) 'normal-size effective Owner minimum is corrected'
 Check ((Get-ClampedActivityPaneHeight -9999) -eq $activityPaneMinHeightPreferred) 'dragging divider above limit cannot shrink activity'
 Set-ActivityPaneHeight -9999
 Check ([Math]::Abs($contentHost.RowStyles[1].Height-$activityPaneMinHeightPreferred) -lt 0.1) 'actual pane setter refuses undersized request'
 $upperMin=$headerPaneMinHeightPreferred
 Check ((Get-ClampedActivityPaneHeight 99999) -eq ($contentHost.ClientSize.Height-$upperMin)) 'maximizing activity leaves only six-row upper banner'
 Set-ActivityPaneHeight 99999
 Check ([Math]::Abs(($contentHost.ClientSize.Height-$contentHost.RowStyles[1].Height)-$upperMin) -lt 0.1) 'actual divider setter respects new smaller header minimum'
 Check ($headerPaneMinHeightPreferred -lt 125 -and
  $activityPaneMinHeightPreferred -eq (8*$ownerPitch+17)) 'Owner pane clamp follows mixed glyph metrics'
 $legacyMinimumHeight=78+38+$headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred+7+48
 Check (($headerPitch -ne 14 -or $ownerPitch -ne 15) -or ($legacyMinimumHeight -eq 401)) 'historical artificial window floor was 401px on the STARMER fonts'
 $fakeForm=New-Object Windows.Forms.Form
 try {
  $fakeForm.Size=[Drawing.Size]::new(800,900)
  $frameHeight=[Math]::Max(0,$fakeForm.Height-$fakeForm.ClientSize.Height)
  $ownerMinimumHeight=78+38+7+2+$frameHeight
  Check ($ownerMinimumHeight -lt $legacyMinimumHeight-100 -and
   $ownerMinimumHeight -ge 78+38+7+2) 'Owner window bottom edge can now travel well below the historical 401px floor without overlap'
 }finally{$fakeForm.Dispose()}
 $minPaneHeight=$headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred
 $contentHost.Height=$minPaneHeight
 Check ((Get-EffectivePaneMinHeight) -eq $activityPaneMinHeightPreferred -and
  (Get-ClampedActivityPaneHeight -9999) -eq $activityPaneMinHeightPreferred -and
  (Get-ClampedActivityPaneHeight 99999) -eq $activityPaneMinHeightPreferred) 'at the preferred minimum both panes retain complete approved header/journal rows'

 Check ($source.Contains('Set-ActivityPaneHeight (Get-Rc1CompressedActivityHeight $contentHost.ClientSize.Height)') -and
  $source.Contains('# Small-screen initial launch must use the same proportional fit')) 'small-screen first launch initializes both panes proportionally rather than collapsing journal to one pixel'
 $resizeHandlers=@($ast.FindAll({param($node)
   $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
   $node.Extent.Text.Contains('Get-Rc1CompressedActivityHeight $contentHost.ClientSize.Height') -and
   $node.Extent.Text.Contains('Set-ActivityPaneHeight $contentHost.RowStyles[1].Height')
 },$true))
 Check ($resizeHandlers.Count -eq 1) 'production content resize uses adaptive pane compression rather than keeping absolute bottom height'
 if($resizeHandlers.Count -ne 1){throw 'MISSING_PRODUCTION_OWNER_WINDOW_RESIZE_HANDLER'}
 $resize=& ([scriptblock]::Create($resizeHandlers[0].Extent.Text))
 $contentHost.Add_Resize($resize)
 $shrinking=$true;$lastLower=$activityPaneMinHeightPreferred+1;$lastUpper=$headerPaneMinHeightPreferred+1
 foreach($height in @(($minPaneHeight-1),($minPaneHeight-15),200,180,150,100,70,32,16,9)){
  $contentHost.Height=$height
  $actual=[int][Math]::Round($contentHost.RowStyles[1].Height)
  $expected=Get-Rc1CompressedActivityHeight $contentHost.ClientSize.Height
  $upper=$contentHost.ClientSize.Height-$actual
  if($actual -ne $expected -or $actual -lt 1 -or $upper -lt 8 -or
   $actual -gt $lastLower -or $upper -gt $lastUpper){
   $shrinking=$false
  }
  $lastLower=$actual;$lastUpper=$upper
 }
 Check $shrinking 'bottom-edge resize continuously collapses both panes to 1px lower / 8px upper including 7px divider without one-row slack'
 Check ($contentHost.ClientSize.Height -eq 9 -and
  [int]$contentHost.RowStyles[1].Height -eq 1 -and
  ($contentHost.ClientSize.Height-[int]$contentHost.RowStyles[1].Height) -eq 8) 'at physical floor both text panes consume every available pixel, divider remains inside 8px header'
 $contentHost.Height=100
 $manual=Get-ClampedActivityPaneHeight 35
 Set-ActivityPaneHeight 35
 Check ([int]$manual -eq 35 -and [int]$contentHost.RowStyles[1].Height -eq 35) 'central splitter retains manual movement when window is compact'
 $smallMin=Get-EffectivePaneMinHeight
 Check ($smallMin -eq 1 -and
  (Get-ClampedActivityPaneHeight -9999) -eq 1 -and
  (Get-ClampedActivityPaneHeight 99999) -eq 92) 'compact drag limits are physical 1px lower viewport and 7px separator plus 1px upper'
 $contentHost.Height=440

 # Drive an actual hidden WinForms Form by its bottom edge. Confirm the
 # docked top/footer and two-pane layout consume the whole shrinking client
 # area and the former 401px floor no longer traps a spare text row.
 $originalHost=$contentHost
 $fixture=New-Object Windows.Forms.Form
 try{
  $fixture.Size=New-Object Drawing.Size(800,700)
  $frame=[Math]::Max(0,$fixture.Height-$fixture.ClientSize.Height)
  $minimumHeight=78+38+7+2+$frame
  $fixture.MinimumSize=New-Object Drawing.Size(800,$minimumHeight)
  $fixture.FormBorderStyle=[Windows.Forms.FormBorderStyle]::Sizable
  $topBar=New-Object Windows.Forms.Panel
  $topBar.Dock=[Windows.Forms.DockStyle]::Top
  $topBar.Height=78
  $bottomBar=New-Object Windows.Forms.Panel
  $bottomBar.Dock=[Windows.Forms.DockStyle]::Bottom
  $bottomBar.Height=38
  $fixtureHost=New-Object Windows.Forms.TableLayoutPanel
  $fixtureHost.Dock=[Windows.Forms.DockStyle]::Fill
  $fixtureHost.RowCount=2
  [void]$fixtureHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
  [void]$fixtureHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$activityPaneMinHeightPreferred)))
  $contentHost=$fixtureHost
  $contentHost.Add_Resize($resize)
  $fixture.Controls.Add($fixtureHost)
  $fixture.Controls.Add($bottomBar)
  $fixture.Controls.Add($topBar)
  $fixture.PerformLayout()
  $fit=$true
  foreach($outerHeight in @(520,430,401,385,350,320,300,250,210,185,$minimumHeight)){
   $fixture.Height=$outerHeight
   $fixture.PerformLayout()
   $available=$fixtureHost.ClientSize.Height
   $lower=[int][Math]::Round($fixtureHost.RowStyles[1].Height)
   $upper=$available-$lower
   $needed=$fixture.ClientSize.Height-78-38
   if([Math]::Abs($available-$needed) -gt 1 -or $lower -lt 1 -or $upper -lt 8){
    $fit=$false
   }
   if($available -lt ($headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred) -and
      $lower -ne (Get-Rc1CompressedActivityHeight $available)){
    $fit=$false
   }
  }
  Check $fit 'real hidden main window bottom resize packs docked panes and divider to the exact available height without one-line dead zone'
  Check ($fixture.MinimumSize.Height -eq $minimumHeight -and
   $fixture.Height -eq $minimumHeight -and
   $fixtureHost.ClientSize.Height -le 12) 'actual window reaches chrome plus 7px divider and 1px per text panel at minimum'
 }finally{
  $contentHost=$originalHost
  $fixture.Dispose()
 }
 $OwnerGui=$false
 $headerPaneMinHeightPreferred=$paneMinHeightPreferred
 $activityPaneMinHeightPreferred=$paneMinHeightPreferred
 Check ((Get-EffectivePaneMinHeight) -eq 125 -and (Get-ClampedActivityPaneHeight -9999) -eq 125 -and
  (Get-ClampedActivityPaneHeight 99999) -eq ($contentHost.ClientSize.Height-125)) 'legacy non-Owner retains 125px limits for both panes'
}finally{$headerVScroll.Dispose();$contentHost.Dispose()}
Write-Output ('RC1_ACTIVITY_MINIMUM_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
