# G99: verify actual production RichEdit compact layout and Owner capacity.
# Offline/disposable: no Remote, installed GUI, Host, tokens or accounts touched.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=[IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$from=$src.IndexOf('public class RdcLogBox : RichTextBox {',[StringComparison]::Ordinal)
$end=$src.IndexOf('public class RdcScrollCorner : Control {',[StringComparison]::Ordinal)
if($from -lt 0 -or $end -lt $from){throw 'MISSING_PRODUCTION_RICHEDIT_CLASS'}
$code='using System; using System.Drawing; using System.Windows.Forms; using System.Runtime.InteropServices; using System.IO; using System.Text;' + [Environment]::NewLine+$src.Substring($from,$end-$from)
Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$ast=[Management.Automation.Language.Parser]::ParseInput($src,[ref]$null,[ref]$null)
foreach($name in @('Get-Rc1JournalVisibleRowCapacity','Apply-OwnerEmojiFont')){
 $function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
 if(-not $function){throw ('MISSING_PRODUCTION_FUNCTION '+$name)}
 . ([scriptblock]::Create($function.Extent.Text))
}
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$OwnerGui=$true
$script:ownerCompactJournal=$true
$script:ownerEmojiEnabled=$true
$script:ownerEmojiFontFamily='Segoe UI Emoji'
$script:ownerJournalLinePitch=15
$emoji=[char]::ConvertFromUtf32(0x1F527)
$font=New-Object Drawing.Font('Consolas',10)
try{
 foreach($variant in @('plain','allEmoji','alternating')){
  $box=New-Object RdcLogBox
  try{
   $box.Font=$font;$box.WordWrap=$false
   $box.ScrollBars=[Windows.Forms.RichTextBoxScrollBars]::None
   $box.BorderStyle=[Windows.Forms.BorderStyle]::None
   $box.Size=New-Object Drawing.Size(900,700)
   $rows=New-Object System.Collections.Generic.List[string]
   for($i=0;$i -lt 40;$i++){
    $symbol=if($variant -eq 'allEmoji' -or ($variant -eq 'alternating' -and $i%2 -eq 0)){$emoji}else{''}
    [void]$rows.Add(('0000{0:D2} ' -f $i)+([char]0x2502)+' '+$symbol+' Example line')
   }
   # Check the real fixed paragraph line spacing after applying inline emoji.
   $box.Text=[string]::Join([char]10,$rows)
   [void]$box.Handle
   $box.ApplyCompactLineSpacing()
   Apply-OwnerEmojiFont $box
   $box.SetViewPosition(0,0)
   $positions=New-Object System.Collections.Generic.List[int]
   $offset=0
   foreach($line in $rows){
    [void]$positions.Add($box.GetPositionFromCharIndex($offset).Y)
    $offset+=$line.Length+1
   }
   $deltas=New-Object System.Collections.Generic.List[int]
   for($i=1;$i -lt $positions.Count;$i++){[void]$deltas.Add($positions[$i]-$positions[$i-1])}
   $min=($deltas|Measure-Object -Minimum).Minimum
   $max=($deltas|Measure-Object -Maximum).Maximum
   Check ($min -eq 15 -and $max -eq 15 -and $deltas.Count -eq 39) ($variant+' 40 RichEdit rows advance by fixed 15px after inline font overlay')
   # RichEdit geometry is authoritative; a 17px-per-row estimate leaves
   # growing unused space. The actual display reserves exactly a top line,
   # then as many full event rows as fit, and a bottom line+subrow remainder.
   $heights=@(120,121,129,134,135,136,149,150,164,165,180,225,300,360)
   $allGood=$true
   $minBottom=999;$maxBottom=-1
   foreach($h in $heights){
    $box.Height=$h
    $log=$box
    $capacity=Get-Rc1JournalVisibleRowCapacity
    $expected=[Math]::Max(1,[Math]::Min(64,[Math]::Floor($box.ClientSize.Height/15)-2))
    if($capacity -ne $expected -or $capacity -gt $rows.Count){$allGood=$false;continue}
    $visible=@($rows|Select-Object -Last $capacity)
    $box.Text=[char]10+[string]::Join([char]10,$visible)
    $box.ApplyCompactLineSpacing()
    Apply-OwnerEmojiFont $box
    $box.SetViewPosition(0,0)
    $lastIndex=$box.Text.LastIndexOf($visible[-1],[StringComparison]::Ordinal)
    $lastY=$box.GetPositionFromCharIndex($lastIndex).Y
    $bottom=$box.ClientSize.Height-($lastY+15)
    $minBottom=[Math]::Min($minBottom,$bottom)
    $maxBottom=[Math]::Max($maxBottom,$bottom)
    if($bottom -lt 10 -or $bottom -gt 30){$allGood=$false}
   }
   Check $allGood ($variant+' pane resize 120-360px maintains about one blank bottom row; min='+$minBottom+' max='+$maxBottom)
  }finally{$box.Dispose()}
 }
 $OwnerGui=$false
 $script:ownerEmojiEnabled=$false
 $log=[pscustomobject]@{IsDisposed=$false;ClientSize=(New-Object Drawing.Size(900,260))}
 Check ((Get-Rc1JournalVisibleRowCapacity) -eq 6) 'legacy mode capacity remains exactly six'
}finally{$font.Dispose()}
Write-Output ('RC1_OWNER_BOTTOM_GAP_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0