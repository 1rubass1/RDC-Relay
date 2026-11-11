# G117: main-window floor is dictated by the complete text panes.
# Hidden WinForms only; no installed app, Host, Remote or registry access.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$repo=Split-Path -Parent $PSScriptRoot
$src=[IO.File]::ReadAllText((Join-Path $repo 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$tok=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($src,[ref]$tok,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
Check ($errors.Count -eq 0) 'GUI source parses'
Check ($src.Contains('$minimumWindowHeight=78+38+$headerPaneMinHeightPreferred+') -and
 $src.Contains('$activityPaneMinHeightPreferred+$windowFrameHeight') -and
 $src.Contains('$windowFrameHeight=[Math]::Max(0,$form.Height-$form.ClientSize.Height)')) 'Owner floor counts both pane minima and actual Windows frame'
Check (-not $src.Contains('function Get-Rc1CompressedActivityHeight') -and
 -not $src.Contains('78+38+7+2+$windowFrameHeight')) 'unsafe almost-zero-sized G116 pane collapse removed'
Check ($src.Contains('$minimumWindowHeight=[Math]::Min($windowHeight,$preferredMinimumHeight)') -and
 $src.Contains('Set-ActivityPaneHeight (Get-EffectivePaneMinHeight)')) 'legacy mode and Owner initial divider keep original behavior'
foreach($name in @('Get-Rc1HeaderBannerMinimum','Get-Rc1ActivityRowReserve',
 'Get-EffectivePaneMinHeight','Get-ClampedActivityPaneHeight','Set-ActivityPaneHeight')){
 $def=$ast.Find({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name
 },$true)
 if(-not $def){throw ('MISSING_PRODUCTION_FUNCTION '+$name)}
 . ([scriptblock]::Create($def.Extent.Text))
}
$OwnerGui=$true
$script:ownerTextFontFamily='Consolas'
$paneMinHeightPreferred=125
$headerPaneMinHeightPreferred=Get-Rc1HeaderBannerMinimum
$activityRowReserve=Get-Rc1ActivityRowReserve $paneMinHeightPreferred
$activityPaneMinHeightPreferred=$paneMinHeightPreferred+$activityRowReserve
$headerPitch=($headerPaneMinHeightPreferred-9)/6
$activityPitch=[int]$script:ownerJournalLinePitch
Check ($headerPitch -ge 10 -and $activityPitch -ge 10 -and
 $activityPaneMinHeightPreferred -eq 8*$activityPitch+17) 'real six-header-line and eight-journal-row text baselines preserved'
$form=New-Object Windows.Forms.Form
$headerVScroll=New-Object Windows.Forms.Panel
try{
 $form.Size=[Drawing.Size]::new(900,850)
 $form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::Sizable
 $form.Font=[Drawing.Font]::new('Segoe UI',10)
 $frame=[Math]::Max(0,$form.Height-$form.ClientSize.Height)
 $min=78+38+$headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred+$frame
 $form.MinimumSize=[Drawing.Size]::new($form.Width,$min)
 $top=New-Object Windows.Forms.Panel
 $top.Dock=[Windows.Forms.DockStyle]::Top
 $top.Height=78
 $bottom=New-Object Windows.Forms.Panel
 $bottom.Dock=[Windows.Forms.DockStyle]::Bottom
 $bottom.Height=38
 $contentHost=New-Object Windows.Forms.TableLayoutPanel
 $contentHost.Dock=[Windows.Forms.DockStyle]::Fill
 $contentHost.RowCount=2
 $contentHost.ColumnCount=1
 [void]$contentHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
 [void]$contentHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$activityPaneMinHeightPreferred))
 $topPane=New-Object Windows.Forms.TableLayoutPanel
 $topPane.Dock=[Windows.Forms.DockStyle]::Fill
 $topPane.Margin=[Windows.Forms.Padding]::new(0)
 $topPane.RowCount=2
 [void]$topPane.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
 [void]$topPane.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,7))
 $topText=New-Object Windows.Forms.RichTextBox
 $topText.Dock=[Windows.Forms.DockStyle]::Fill
 $topText.Margin=[Windows.Forms.Padding]::new(0)
 $topText.BorderStyle=[Windows.Forms.BorderStyle]::None
 $topText.Font=[Drawing.Font]::new('Consolas',9)
 $topText.WordWrap=$false
 $topText.Text=[string]::Join([char]10,@('One','Two','Three','Four','Five','Six'))
 $divider=New-Object Windows.Forms.Panel
 $divider.Dock=[Windows.Forms.DockStyle]::Fill
 $divider.Margin=[Windows.Forms.Padding]::new(0)
 $topPane.Controls.Add($topText,0,0)
 $topPane.Controls.Add($divider,0,1)
 $bottomPane=New-Object Windows.Forms.Panel
 $bottomPane.Dock=[Windows.Forms.DockStyle]::Fill
 $bottomPane.Margin=[Windows.Forms.Padding]::new(0)
 $bottomText=New-Object Windows.Forms.RichTextBox
 $bottomText.Dock=[Windows.Forms.DockStyle]::Fill
 $bottomText.BorderStyle=[Windows.Forms.BorderStyle]::None
 $bottomText.Font=[Drawing.Font]::new('Consolas',10)
 $scrollbar=New-Object Windows.Forms.Panel
 $scrollbar.Dock=[Windows.Forms.DockStyle]::Bottom
 $scrollbar.Height=17
 $bottomPane.Controls.Add($bottomText)
 $bottomPane.Controls.Add($scrollbar)
 $contentHost.Controls.Add($topPane,0,0)
 $contentHost.Controls.Add($bottomPane,0,1)
 $form.Controls.Add($contentHost)
 $form.Controls.Add($bottom)
 $form.Controls.Add($top)
 $resizeNode=@($ast.FindAll({param($n)
  $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
  $n.Extent.Text.Contains('Set-ActivityPaneHeight $contentHost.RowStyles[1].Height') -and
  -not $n.Extent.Text.Contains('Get-Rc1CompressedActivityHeight')
 },$true))|Select-Object -First 1
 Check ($null -ne $resizeNode) 'normal production pane resize callback found'
 if($null -ne $resizeNode){
  $resize=& ([scriptblock]::Create($resizeNode.Extent.Text))
  $contentHost.Add_Resize($resize)
 }
 $form.PerformLayout()
 $correct=$true
 foreach($requested in @(700,500,440,410,401,394,385,$min,($min-15),($min-100))){
  $form.Height=$requested
  $form.PerformLayout()
  $free=$contentHost.ClientSize.Height
  $lower=[int][Math]::Round($contentHost.RowStyles[1].Height)
  $upper=$free-$lower
  if($form.Height -lt $min -or $lower -lt $activityPaneMinHeightPreferred -or
   $upper -lt $headerPaneMinHeightPreferred -or
   $free -lt ($headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred)){
   $correct=$false
  }
 }
 Check $correct 'bottom-border resize never compresses either text panel below its complete minimum'
 $form.Height=$min
 $form.PerformLayout()
 $free=$contentHost.ClientSize.Height
 $lower=[int][Math]::Round($contentHost.RowStyles[1].Height)
 $upper=$free-$lower
 Check ($form.Height -eq $min -and
  $free -eq ($headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred) -and
  $lower -eq $activityPaneMinHeightPreferred -and
  $upper -eq $headerPaneMinHeightPreferred) 'window floor meets both text minima exactly, with zero surplus divider slack'
 Check ($divider.Height -eq 7 -and
  $topText.ClientSize.Height -ge 6*$headerPitch -and
  $bottomText.ClientSize.Height -ge 8*$activityPitch) 'all six header lines and eight journal slots fit with preserved 7px divider'
 $form.Height=$min-100
 Check ($form.Height -eq $min) 'WinForms rejects sizing below text minima'
 $oldFloor=78+38+$headerPaneMinHeightPreferred+$activityPaneMinHeightPreferred+7+48
 Check ($min -lt $oldFloor -and ($oldFloor-$min) -ge 8 -and
  ($oldFloor-$min) -le 55) 'removes only the historical artificial row, not the real pane floor'
}finally{$headerVScroll.Dispose();$form.Dispose()}
Write-Output ('RC1_OWNER_WINDOW_MINIMUM_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0