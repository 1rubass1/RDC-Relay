# G98: isolated mixed RichEdit font contract, with no Host/GUI launch or Remote.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$yes,[string]$name){
 if($yes){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
try {
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'product WinPS script parses'
 Check ($source.Contains("$"+'script:ownerTextFontFamily='+"'Consolas'") -and
  $source.Contains("$"+'script:ownerEmojiFontFamily='+"'Segoe UI Emoji'") -and
  $source.Contains('$script:ownerEmojiEnabled=[bool]$OwnerGui')) 'Consolas body and Owner-only emoji overlay preset'
 Check ($source.Contains('$headerLog.Font = New-Object Drawing.Font($script:ownerTextFontFamily,9)') -and
  $source.Contains('$log.Font = New-Object Drawing.Font($script:ownerTextFontFamily,10)')) 'both controls retain 9/10pt fixed-width font'
 Check ($source.Contains('$emojiFont=New-Object Drawing.Font($script:ownerEmojiFontFamily,10)') -and
  $source.Contains('$linePitch=[Math]::Max($linePitch,$emojiPitch)') -and
  $source.Contains('return [Math]::Max(0,(8*$linePitch)+17-$baselineHeight)')) 'Owner journal sizes to tallest inline emoji'
 Check ($source.Contains('if($OwnerGui){Apply-OwnerEmojiFont $headerLog}') -and
  $source.Contains('if($OwnerGui){Apply-OwnerEmojiFont $log}')) 'overlay applied after colorization to both panes'
 $def=$ast.Find({param($n)
   $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
   $n.Name -ceq 'Apply-OwnerEmojiFont'
  },$true)
 if(-not $def){throw 'MISSING_PRODUCTION_GLYPH_HELPER'}
 . ([scriptblock]::Create($def.Extent.Text))
 $script:ownerEmojiFontFamily='Segoe UI Emoji'
 $script:ownerEmojiEnabled=$true
 foreach($size in @(9,10)){
  $box=New-Object Windows.Forms.RichTextBox
  $font=New-Object Drawing.Font('Consolas',$size)
  try{
   $box.Font=$font
   $box.Size=New-Object Drawing.Size(950,260)
   $box.WordWrap=$false;$box.ReadOnly=$true
   [void]$box.Handle
   $block=[char]0x2588
   $bar=[char]0x2502
   $emoji=[char]::ConvertFromUtf32(0x1F527)
   $rocket=[char]::ConvertFromUtf32(0x1F680)
   $arrow=[char]0x27A1
   $stop=[char]0x23F9
   $sample=([string]$block)*20 + [char]10 + '000007 '+$bar+' '+$emoji+' Starting' + [char]10 +
    $rocket+' Next' + [char]10 + $arrow+' Return to ChatGPT' + [char]10 + $stop+' Click Stop'
   $box.Text=$sample
   $box.Select($sample.IndexOf($emoji),$emoji.Length)
   $box.SelectionColor=[Drawing.Color]::Orange
   Apply-OwnerEmojiFont $box
   Check ($box.Text -ceq $sample -and $box.Rtf -match 'Consolas' -and
    $box.Rtf -match 'Segoe UI Emoji') ('mixed RTF preserves text and both font families '+$size+'pt')
   foreach($pair in @(
    @([string]$block,'Consolas'),@([string]$bar,'Consolas'),@('Next','Consolas'),
    @('Return to ChatGPT','Consolas'),@($emoji,'Segoe UI Emoji'),
    @($rocket,'Segoe UI Emoji'),@([string]$arrow,'Segoe UI Emoji'),
    @([string]$stop,'Segoe UI Emoji')
   )){
    $idx=$sample.IndexOf([string]$pair[0],[StringComparison]::Ordinal)
    if($idx -lt 0){throw 'FIXTURE_NOT_FOUND'}
    $box.Select($idx,([string]$pair[0]).Length)
    Check ($null -ne $box.SelectionFont -and
      $box.SelectionFont.FontFamily.Name -ceq [string]$pair[1] -and
      [Math]::Abs($box.SelectionFont.Size-$size) -lt 0.3) ('glyph '+[string]$pair[1]+' '+$size+'pt '+$idx)
   }
   $box.Select($sample.IndexOf($emoji),$emoji.Length)
   Check ($box.SelectionColor.ToArgb() -eq ([Drawing.Color]::Orange).ToArgb()) ('glyph color retained '+$size+'pt')
   $script:ownerEmojiEnabled=$false
   $box.Select(0,$box.TextLength)
   $box.SelectionFont=$font
   Apply-OwnerEmojiFont $box
   $box.Select($sample.IndexOf($emoji),$emoji.Length)
   Check ($box.SelectionFont.FontFamily.Name -ceq 'Consolas') ('disabled Owner overlay preserves legacy '+$size+'pt')
   $script:ownerEmojiEnabled=$true
  }finally{$box.Dispose();$font.Dispose()}
 }
}catch{
 $fail++;Write-Output ('FAIL unexpected '+$_.Exception.GetType().Name+' '+$_.Exception.Message)
}
Write-Output ('RC1_OWNER_EMOJI_FONT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0