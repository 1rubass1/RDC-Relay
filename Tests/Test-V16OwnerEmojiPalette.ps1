# G106: audit Owner-only semantic emoji palette with disposable RichEdit controls.
# No installation, Host, Remote, browser or network access.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$source=[IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$condition,[string]$name){
 if($condition){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Owner PowerShell source parses'
$from=$source.IndexOf('public class RdcLogBox : RichTextBox {',[StringComparison]::Ordinal)
$to=$source.IndexOf('public class RdcScrollCorner : Control {',[StringComparison]::Ordinal)
if($from -lt 0 -or $to -lt $from){throw 'G106_PRODUCT_RICHEDIT_BOUNDARY_MISSING'}
$code='using System; using System.Drawing; using System.Windows.Forms; using System.Runtime.InteropServices; using System.IO; using System.Text;' + [Environment]::NewLine + $source.Substring($from,$to-$from)
Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
foreach($name in @('Color-LogToken','Apply-OwnerEmojiFont')){
 $def=$ast.Find({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name
 },$true)
 if(-not $def){throw ('G106_MISSING_PRODUCT_FUNCTION '+$name)}
 . ([scriptblock]::Create($def.Extent.Text))
}
$paletteStart=$source.IndexOf('$accentOrange = [Drawing.Color]::FromArgb(191,118,67)',[StringComparison]::Ordinal)
$paletteEnd=$source.IndexOf('$infoHost = New-Object Windows.Forms.FlowLayoutPanel',$paletteStart,[StringComparison]::Ordinal)
if($paletteStart -lt 0 -or $paletteEnd -le $paletteStart){throw 'G106_PRODUCT_PALETTE_BOUNDARY'}
$palette=[scriptblock]::Create($source.Substring($paletteStart,$paletteEnd-$paletteStart))
$success=[char]::ConvertFromUtf32(0x2705)
$stop=[char]::ConvertFromUtf32(0x23F9)
$wave=[char]::ConvertFromUtf32(0x1F44B)
$wrench=[char]::ConvertFromUtf32(0x1F527)
$rocket=[char]::ConvertFromUtf32(0x1F680)
$failure=[char]::ConvertFromUtf32(0x274C)
$plug=[char]::ConvertFromUtf32(0x1F50C)
$hour=[char]::ConvertFromUtf32(0x23F3)
$webIcon=[char]::ConvertFromUtf32(0x1F310)
$storage=[char]::ConvertFromUtf32(0x1F4BE)
$paletteRefs=@(
 @('$headerLog',$success,'$accentSuccess'),
 @('$log',$success,'$accentSuccess'),
 @('$headerLog',$stop,'$accentStop'),
 @('$headerLog',$wave,'$accentGreeting'),
 @('$log',$wave,'$accentGreeting'),
 @('$log',$failure,'([Drawing.Color]::LightCoral)'),
 @('$headerLog',$plug,'$statusGreen'),
 @('$log',$plug,'$statusGreen'),
 @('$headerLog',$hour,'$accentWait'),
 @('$log',$hour,'$accentWait'),
 @('$headerLog',$webIcon,'$accentNetwork'),
 @('$log',$webIcon,'$accentNetwork'),
 @('$headerLog',$storage,'$accentStorage'),
 @('$log',$storage,'$accentStorage'),
 @('$headerLog',$wrench,'$accentOrange'),
 @('$log',$wrench,'$accentOrange'),
 @('$headerLog',$rocket,'$accentOrange'),
 @('$log',$rocket,'$accentOrange')
)
$allRefs=$true
foreach($ref in $paletteRefs){
 $line='Color-LogToken '+$ref[0]+" '"+$ref[1]+"' "+$ref[2]
 if(-not $source.Contains($line)){$allRefs=$false;Write-Output ('G106_MISSING_CALL '+$line)}
}
Check $allRefs 'both Owner panes map action/success/stop/pending/connectivity/storage/failure consistently'
Check ($source.Contains('$accentSuccess=if($OwnerGui){$statusGreen}else{$accentPurple}') -and
 $source.Contains('$accentStop=if($OwnerGui){[Drawing.Color]::LightCoral}else{$accentOrange}') -and
 $source.Contains('$accentGreeting=if($OwnerGui){[Drawing.Color]::Gainsboro}else{$accentPresence}')) 'semantic recolor is Owner-only; legacy remains byte-identical'
$script:ownerEmojiEnabled=$true
$script:ownerEmojiFontFamily='Segoe UI Emoji'
foreach($ownerMode in @($true,$false)){
 $OwnerGui=$ownerMode
 . $palette
 $isOwner=if($ownerMode){'owner'}else{'legacy'}
 Check ($accentSuccess.ToArgb() -eq $(if($ownerMode){$statusGreen.ToArgb()}else{$accentPurple.ToArgb()})) ($isOwner+' checkmark semantic success contract')
 Check ($accentStop.ToArgb() -eq $(if($ownerMode){([Drawing.Color]::LightCoral).ToArgb()}else{$accentOrange.ToArgb()})) ($isOwner+' stop danger/action contract')
 Check ($accentGreeting.ToArgb() -eq $(if($ownerMode){([Drawing.Color]::Gainsboro).ToArgb()}else{$accentPresence.ToArgb()})) ($isOwner+' greeting neutral/presence contract')
 if($ownerMode){
  Check ($accentSuccess.ToArgb() -ne $accentPurple.ToArgb() -and
   $accentSuccess.G -gt $accentSuccess.R -and
   $accentSuccess.G -gt $accentSuccess.B) 'green Owner success is distinct from purple branding'
 }
 $box=New-Object RdcLogBox
 $body=New-Object Drawing.Font('Consolas',10)
 try{
  $box.Font=$body;$box.Size=New-Object Drawing.Size(900,200)
  $box.WordWrap=$false
  [void]$box.Handle
  $cases=@(
    @($success,$accentSuccess),
    @($stop,$accentStop),
    @($wave,$accentGreeting),
    @($wrench,$accentOrange),
    @($rocket,$accentOrange),
    @($plug,$statusGreen),
    @($hour,$accentWait),
    @($webIcon,$accentNetwork),
    @($storage,$accentStorage),
    @($failure,([Drawing.Color]::LightCoral))
  )
  $builder=New-Object Text.StringBuilder
  foreach($item in $cases){[void]$builder.Append([string]$item[0]+' text | ')}
  $sample=$builder.ToString()
  $box.Text=$sample
  $box.Select(0,$box.TextLength)
  $box.SelectionColor=[Drawing.Color]::Gainsboro
  foreach($item in $cases){Color-LogToken $box ([string]$item[0]) ([Drawing.Color]$item[1])}
  Apply-OwnerEmojiFont $box
  $good=$true
  foreach($item in $cases){
   $glyph=[string]$item[0]
   $idx=$sample.IndexOf($glyph,[StringComparison]::Ordinal)
   $box.Select($idx,$glyph.Length)
   if($box.SelectionColor.ToArgb() -ne ([Drawing.Color]$item[1]).ToArgb()){$good=$false}
   if($box.SelectionFont.FontFamily.Name -cne 'Segoe UI Emoji'){$good=$false}
  }
  Check $good ($isOwner+' real RichEdit selections preserve all ten semantic colors and Emoji font')
  $textIndex=$sample.IndexOf('text',[StringComparison]::Ordinal)
  $box.Select($textIndex,4)
  Check ($box.SelectionColor.ToArgb() -eq ([Drawing.Color]::Gainsboro).ToArgb() -and
   $box.SelectionFont.FontFamily.Name -ceq 'Consolas') ($isOwner+' surrounding body text remains neutral monospaced')
 }finally{$box.Dispose();$body.Dispose()}
}
Write-Output ('RC1_OWNER_EMOJI_PALETTE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0