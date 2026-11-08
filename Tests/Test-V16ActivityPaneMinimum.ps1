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
 $source.Contains('$headerPaneMinHeightPreferred=if($OwnerGui){Get-Rc1HeaderBannerMinimum}else{$paneMinHeightPreferred}') -and
 $source.Contains('$activityDefaultHeight = $activityPaneMinHeightPreferred') -and
 $source.Contains('Set-ActivityPaneHeight (Get-EffectivePaneMinHeight)')) 'Owner minimum, default and minimum window height all increase consistently'
$funcNames=@('Get-EffectivePaneMinHeight','Get-ClampedActivityPaneHeight','Set-ActivityPaneHeight')
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
$script:ownerTextFontFamily='Segoe UI Emoji'
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
 $oldVisibleHeight=$paneMinHeightPreferred-17
 $oldFullRows=[Math]::Floor($oldVisibleHeight/$line)
 $newBottomGap=($activityPaneMinHeightPreferred-17)-(8*$line)
 Check ($line -ge 12 -and $line -le 35 -and
  $activityRowReserve -ge 1 -and
  $newBottomGap -eq 0 -and $activityPaneMinHeightPreferred -eq (8*$line+17)) 'Owner minimum fits six events plus top and bottom blank rows after font change'
 Check ((($paneMinHeightPreferred-17+$activityRowReserve) % $line) -eq 0) 'inner viewport aligns to text line pitch without double-counting existing space'
 Check (($line -ne 17) -or ($activityRowReserve -eq 28 -and $activityPaneMinHeightPreferred -eq 153)) 'STARMER Emoji 10pt line pitch 17px gives six visible events at 153px'
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
  Check (($headerPitch -ne 16) -or ($headerPaneMinHeightPreferred -eq 105)) 'STARMER Emoji 9pt collapsed header minimum is 105px'
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
  $activityPaneMinHeightPreferred -eq (8*$line+17)) 'Owner pane clamp follows changed Emoji font metrics'
 $minWindowHeight=78+38+$headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred+7+48
 Check (($headerPitch -ne 16 -or $line -ne 17) -or ($minWindowHeight -eq 429)) 'full Owner window minimum accounts for Emoji line spacing'
 $minPaneHeight=$headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred
 $contentHost.Height=$minPaneHeight
 Check ((Get-EffectivePaneMinHeight) -eq $activityPaneMinHeightPreferred -and
  (Get-ClampedActivityPaneHeight -9999) -eq $activityPaneMinHeightPreferred -and
  (Get-ClampedActivityPaneHeight 99999) -eq $activityPaneMinHeightPreferred) 'fully collapsed window fits exactly six-row header and six-event lower pane'
 $contentHost.Height=440
 $smallSize=$contentHost.Size
 $contentHost.Height=200
 $smallMin=Get-EffectivePaneMinHeight
 Check ($smallMin -ge 48 -and $smallMin -le 120 -and
  (Get-ClampedActivityPaneHeight 99999) -ge $smallMin -and
  (Get-ClampedActivityPaneHeight 99999) -le ($contentHost.ClientSize.Height-48)) 'limited-display fallback remains bounded and usable'
 $contentHost.Size=$smallSize
 $OwnerGui=$false
 $headerPaneMinHeightPreferred=$paneMinHeightPreferred
 $activityPaneMinHeightPreferred=$paneMinHeightPreferred
 Check ((Get-EffectivePaneMinHeight) -eq 125 -and (Get-ClampedActivityPaneHeight -9999) -eq 125 -and
  (Get-ClampedActivityPaneHeight 99999) -eq ($contentHost.ClientSize.Height-125)) 'legacy non-Owner retains 125px limits for both panes'
}finally{$headerVScroll.Dispose();$contentHost.Dispose()}
Write-Output ('RC1_ACTIVITY_MINIMUM_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
