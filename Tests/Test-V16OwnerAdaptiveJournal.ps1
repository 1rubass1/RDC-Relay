# Isolated adaptive Owner event journal regression (no Host/Remote/GUI launch).
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$root=Split-Path -Parent $PSScriptRoot
$path=Join-Path $root 'Source\remote-window.ps1'
$code=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'original Owner/legacy GUI parses'
foreach($name in @('Get-Rc1ActivityRowReserve','Get-Rc1JournalVisibleRowCapacity','Refresh-Rc1JournalOnResize','Add-CompletedEvent')){
 $def=$ast.Find({param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
 },$true)
 if(-not $def){throw ('MISSING_PRODUCTION_FUNCTION: '+$name)}
 . ([scriptblock]::Create($def.Extent.Text))
}
function Limit-UiEvent([string]$text){return $text}
$OwnerGui=$true
$script:ownerTextFontFamily='Consolas'
$script:ownerEmojiFontFamily='Segoe UI Emoji'
$script:ownerEmojiEnabled=$true
$script:ownerCompactJournal=$true
$script:eventBlocks=New-Object System.Collections.ArrayList
$script:ownerLastJournalCapacity=-1
$reserve=Get-Rc1ActivityRowReserve 125
$linePitch=[int]$script:ownerJournalLinePitch
$minOwner=125+$reserve
$log=[pscustomobject]@{IsDisposed=$false;ClientSize=(New-Object Drawing.Size(800,($minOwner-17)))}
Check ($minOwner -eq (8*$linePitch+17) -and $linePitch -eq 17) 'on STARMER mixed Consolas/Emoji, 153px minimum yields 17px safe pitch and six events'
Check ((Get-Rc1JournalVisibleRowCapacity) -eq 6) 'minimum fits exactly six event lines plus top and bottom row'
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17+3*$linePitch))
Check ((Get-Rc1JournalVisibleRowCapacity) -eq 9) 'three row-pitches of growth show three more entries'
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17+6*$linePitch))
Check ((Get-Rc1JournalVisibleRowCapacity) -eq 12) 'six row-pitches of growth show six more entries'
$log.ClientSize=New-Object Drawing.Size(800,5)
Check ((Get-Rc1JournalVisibleRowCapacity) -eq 1) 'transient tiny viewport has a bounded one-row fallback'
$log.ClientSize=New-Object Drawing.Size(800,3000)
Check ((Get-Rc1JournalVisibleRowCapacity) -eq 64) 'giant viewport is capped at retained 64 events'
foreach($n in 1..80){Add-CompletedEvent ('safe-entry-'+$n)}
Check ($script:eventBlocks.Count -eq 64 -and
 $script:eventBlocks[0] -ceq 'safe-entry-17' -and
 $script:eventBlocks[63] -ceq 'safe-entry-80') 'Owner retains 64 bounded sanitized events rather than discarding down to six'
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17))
$firstSix=@($script:eventBlocks | Select-Object -Last (Get-Rc1JournalVisibleRowCapacity))
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17+4*$linePitch))
$expanded=@($script:eventBlocks | Select-Object -Last (Get-Rc1JournalVisibleRowCapacity))
Check ($firstSix.Count -eq 6 -and $expanded.Count -eq 10 -and
 $expanded[0] -ceq 'safe-entry-71' -and $firstSix[0] -ceq 'safe-entry-75') 'expansion reveals older retained entries in chronological order'
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17))
Check ($script:eventBlocks.Count -eq 64 -and
 (Get-Rc1JournalVisibleRowCapacity) -eq 6) 'shrinking does not destroy retained history'
$script:renderTriggered=0
function Render-CompactLog {$script:renderTriggered++}
$script:ownerLastJournalCapacity=6
$script:uiInteracting=$false
$script:logRedrawFrozen=$false
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17+2*$linePitch))
Refresh-Rc1JournalOnResize
Check ($script:renderTriggered -eq 1) 'resize with changed row capacity triggers reconstruction'
$script:ownerLastJournalCapacity=8
Refresh-Rc1JournalOnResize
Check ($script:renderTriggered -eq 1) 'same capacity does not repeatedly rebuild RichEdit'
$log.ClientSize=New-Object Drawing.Size(800,($minOwner-17+3*$linePitch))
$script:uiInteracting=$true
Refresh-Rc1JournalOnResize
Check ($script:renderTriggered -eq 1) 'active drag postpones RichEdit rewrite until release'
$script:uiInteracting=$false
$script:logRedrawFrozen=$true
Refresh-Rc1JournalOnResize
Check ($script:renderTriggered -eq 1) 'redraw freeze also postpones rewrite'
$script:logRedrawFrozen=$false
Refresh-Rc1JournalOnResize
Check ($script:renderTriggered -eq 2) 'drag release updates capacity and journal'
Check ($code.Contains('if($script:ownerCompactJournal){Refresh-Rc1JournalOnResize}') -and
 $code.Contains('$visibleLimit=Get-Rc1JournalVisibleRowCapacity') -and
 $code.Contains('$visible = $visible[($visible.Count-$visibleLimit)..($visible.Count-1)]')) 'production footer resize hooks and render use dynamic row limit'
$OwnerGui=$false
$log.ClientSize=New-Object Drawing.Size(800,600)
$script:eventBlocks.Clear()
foreach($n in 1..20){Add-CompletedEvent ('legacy-'+$n)}
Check ((Get-Rc1JournalVisibleRowCapacity) -eq 6 -and
 $script:eventBlocks.Count -eq 6 -and $script:eventBlocks[0] -ceq 'legacy-15') 'legacy stable behavior remains exactly six rows/history'
Write-Output ('RC1_ADAPTIVE_JOURNAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
