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
Check ($source.Contains('$activityPaneMinHeightPreferred=$paneMinHeightPreferred+$(if($OwnerGui){$activityLineHeight}else{0})') -and
 $source.Contains('$preferredMinimumHeight = 78 + 38 + $paneMinHeightPreferred + $activityPaneMinHeightPreferred + 7 + 48') -and
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
$lineFont=New-Object Drawing.Font('Consolas',10)
try{
 $line=[Windows.Forms.TextRenderer]::MeasureText(
  'Ag',$lineFont,(New-Object Drawing.Size(1000,1000)),
  ([Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine)
 ).Height
}finally{$lineFont.Dispose()}
$OwnerGui=$true
$paneMinHeightPreferred=125
$activityLineHeight=$line
$activityPaneMinHeightPreferred=$paneMinHeightPreferred+$activityLineHeight
$contentHost=New-Object Windows.Forms.TableLayoutPanel
$contentHost.Size=New-Object Drawing.Size(800,440)
$contentHost.RowCount=2
[void]$contentHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$contentHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$activityPaneMinHeightPreferred)))
$headerVScroll=New-Object Windows.Forms.Panel
try{
 Check ($line -ge 15 -and $line -le 35 -and
  $activityPaneMinHeightPreferred -eq 125+$line) 'minimum adds one real measured Consolas line'
 Check ((Get-EffectivePaneMinHeight) -eq $activityPaneMinHeightPreferred) 'normal-size effective Owner minimum is one line larger'
 Check ((Get-ClampedActivityPaneHeight -9999) -eq $activityPaneMinHeightPreferred) 'dragging divider above limit cannot shrink activity'
 Set-ActivityPaneHeight -9999
 Check ([Math]::Abs($contentHost.RowStyles[1].Height-$activityPaneMinHeightPreferred) -lt 0.1) 'actual pane setter refuses undersized request'
 $upperMin=$paneMinHeightPreferred
 Check ((Get-ClampedActivityPaneHeight 99999) -le ($contentHost.ClientSize.Height-$upperMin)) 'maximum activity height preserves original header minimum'
 $smallSize=$contentHost.Size
 $contentHost.Height=200
 $smallMin=Get-EffectivePaneMinHeight
 Check ($smallMin -ge 48 -and $smallMin -le 100 -and
  (Get-ClampedActivityPaneHeight 99999) -ge $smallMin) 'limited-display fallback remains bounded and usable'
 $contentHost.Size=$smallSize
 $OwnerGui=$false
 $activityPaneMinHeightPreferred=$paneMinHeightPreferred
 Check ((Get-EffectivePaneMinHeight) -eq 125 -and (Get-ClampedActivityPaneHeight -9999) -eq 125) 'legacy non-Owner retains 125px baseline'
}finally{$headerVScroll.Dispose();$contentHost.Dispose()}
Write-Output ('RC1_ACTIVITY_MINIMUM_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
