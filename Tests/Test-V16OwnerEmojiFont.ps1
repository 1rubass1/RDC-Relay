# G97: isolated WinForms RichEdit emoji-font preset and metric contract.
# Creates only disposable controls; no Host, GUI window, Remote or OAuth.
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
 [void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'product WinPS script parses'
 Check ($source.Contains("$"+'script:ownerTextFontFamily=if($OwnerGui){'+"'Segoe UI Emoji'"+'}else{'+"'Consolas'"+'}')) 'Owner defaults to Emoji; legacy remains Consolas'
 Check ($source.Contains('$headerLog.Font = New-Object Drawing.Font($script:ownerTextFontFamily,9)') -and
  $source.Contains('$log.Font = New-Object Drawing.Font($script:ownerTextFontFamily,10)')) 'both Owner RichEdit controls use same preset at original point sizes'
 Check ($source.Contains('New-Object Drawing.Font($script:ownerTextFontFamily,9)') -and
  $source.Contains('New-Object Drawing.Font($script:ownerTextFontFamily,10)') -and
  $source.Contains('return [Math]::Max(0,(8*$linePitch)+17-$baselineHeight)')) 'font metric probes and six-row journal limits use selected preset'
 foreach($size in @(9,10)){
  $box=New-Object Windows.Forms.RichTextBox
  $font=New-Object Drawing.Font('Segoe UI Emoji',$size)
  try{
   $box.Font=$font
   $box.Size=New-Object Drawing.Size(950,260)
   $box.WordWrap=$false;$box.ReadOnly=$true
   [void]$box.Handle
   Check ($box.Font.FontFamily.Name -ceq 'Segoe UI Emoji' -and
     [Math]::Abs($box.Font.Size-$size) -lt 0.1) ("available installed Emoji font at "+$size+"pt")
   $sample=(@(0x1F527,0x2705,0x274C,0x1F50C,0x23F3,0x1F310,0x1F4BE,0x1F44B) | ForEach-Object { [char]::ConvertFromUtf32($_) }) -join ' '
   $box.Text=$sample
   Check ($box.Text -ceq $sample -and $box.Rtf -match 'Segoe UI Emoji') ("RichEdit roundtrips Unicode and RTF font at "+$size+"pt")
   $box.Select(0,$box.TextLength)
   Check ($box.SelectionFont.FontFamily.Name -ceq 'Segoe UI Emoji') ("selected Unicode text retains Emoji character font at "+$size+"pt")
  }finally{$box.Dispose();$font.Dispose()}
 }
 # No use of pixel colors or layered glyphs: WinForms RichEdit color emoji
 # capability cannot be established from Text/RTF/SelectionFont alone.
}catch{
 $fail++;Write-Output ('FAIL unexpected '+$_.Exception.GetType().Name+' '+$_.Exception.Message)
}
Write-Output ('RC1_OWNER_EMOJI_FONT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0