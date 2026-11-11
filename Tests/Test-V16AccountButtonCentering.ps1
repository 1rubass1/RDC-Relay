# G120: Account chevron + label centered together, exactly like Stop glyph.
# Compiles the production button and paints isolated WinForms bitmaps.
# Never starts Owner GUI, Host, Remote or installed application.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
$raw=[IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)
$tok=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tok,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label) {
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($errors.Count -eq 0) 'production GUI script parses'
$node=$ast.Find({param($n)
 $n -is [Management.Automation.Language.StringConstantExpressionAst] -and
 $n.Value.Contains('public class RdcRoundedButton') -and
 $n.Value.Contains('public class RdcCircleButton')
},$true)
if(-not $node){throw 'G120_PRODUCTION_ROUNDED_BUTTON_CODE_NOT_FOUND'}
Add-Type -TypeDefinition $node.Value -ReferencedAssemblies System.Windows.Forms,System.Drawing
Check ($raw.Contains("$accountButton.Text = 'Аккаунт'") -and
 $raw.Contains('$accountButton.ShowMenuChevron = $true') -and
 $raw.Contains("$accountButton.AccessibleName = 'Аккаунт, открыть меню'") -and
 -not $raw.Contains("$accountButton.Text = 'Аккаунт ▾'")) 'Account text and native left dropdown glyph configured separately'
Check ($raw.Contains('$accountMenu.Show($accountButton,(New-Object Drawing.Point(0,$accountButton.Height)))')) 'Account menu opening behavior unchanged'
Check ($raw.Contains("$finish.Glyph = [RdcButtonGlyph]::Stop") -and
 $raw.Contains("$finish.Text = 'Остановить'")) 'Stop content and glyph preserved'
Check ($raw.Contains('Rectangle iconRect = GetGroupIconBounds(textSize.Width)') -and
 $raw.Contains('DrawMenuChevron(e.Graphics,iconRect,content)') -and
 $raw.Contains('DrawGlyph(e.Graphics,iconRect,content)')) 'Account and Stop use exactly the same group bounds in actual paint code'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$paint=[RdcRoundedButton].GetMethod('OnPaint',$flags)
$groupBounds=[RdcRoundedButton].GetMethod('GetGroupIconBounds',$flags)
if(-not $paint -or -not $groupBounds){throw 'G120_PAINT_OR_GROUP_BOUNDS_MISSING'}
function Make-Button([string]$text,[bool]$chevron,[int]$width,[int]$height){
 $b=New-Object RdcRoundedButton
 $b.Text=$text
 $b.ShowMenuChevron=$chevron
 $b.Tone=[RdcButtonTone]::Neutral
 $b.Size=[Drawing.Size]::new($width,$height)
 $b.BackColor=[Drawing.Color]::FromArgb(29,32,36)
 return $b
}
function Paint-Button($button) {
 $bmp=New-Object Drawing.Bitmap($button.Width,$button.Height)
 $graphics=[Drawing.Graphics]::FromImage($bmp)
 try {
  $graphics.Clear([Drawing.Color]::Magenta)
  $event=New-Object Windows.Forms.PaintEventArgs($graphics,$button.ClientRectangle)
  [void]$paint.Invoke($button,[object[]]@($event.PSObject.BaseObject))
 }finally{$graphics.Dispose()}
 return $bmp
}
$sizeCases=@(@(120,36),@(144,43),@(160,48))
foreach($dim in $sizeCases){
 $width=[int]$dim[0];$height=[int]$dim[1]
 $account=Make-Button 'Аккаунт' $true $width $height
 $sameTextStop=Make-Button 'Аккаунт' $false $width $height
 $realStop=Make-Button 'Остановить' $false $width $height
 $plain=Make-Button 'Аккаунт' $false $width $height
 try{
  $sameTextStop.Glyph=[RdcButtonGlyph]::Stop
  $realStop.Glyph=[RdcButtonGlyph]::Stop
  $tflags=[Windows.Forms.TextFormatFlags]::VerticalCenter -bor
   [Windows.Forms.TextFormatFlags]::SingleLine -bor
   [Windows.Forms.TextFormatFlags]::NoPadding
  $tw=[Windows.Forms.TextRenderer]::MeasureText($account.Text,$account.Font,
   [Drawing.Size]::new([int]::MaxValue,$height),$tflags).Width
  $iconRect=[Drawing.Rectangle]$groupBounds.Invoke($account,[object[]]@([int]$tw))
  $groupWidth=12+7+$tw
  $expectedLeft=[Math]::Max(5,[int][Math]::Floor(($width-$groupWidth)/2))
  Check ($iconRect.Left -eq $expectedLeft -and $iconRect.Width -eq 12 -and
   $iconRect.Height -eq 12 -and
   [Math]::Abs(($iconRect.Left+$groupWidth/2.0)-($width/2.0)) -le 1) ('chevron + Account text have one centered group at '+$width+'px')
  $groupTextLeft=$iconRect.Right+7
  Check ($iconRect.Right -lt $groupTextLeft -and
   ($groupTextLeft+$tw) -le ($width-4) -and
   $iconRect.Left -ge 5) ('left chevron and Account text fit with Stop-like 7px gap at '+$width+'px')
  $accountBmp=Paint-Button $account
  $stopBmp=Paint-Button $sameTextStop
  $plainBmp=Paint-Button $plain
  try {
   $textDiff=0;$glyphDiff=0;$arrowInk=0;$textInk=0
   $inkMin=$width;$inkMax=-1
   for($y=0;$y -lt $height;$y++){
    for($x=0;$x -lt $width;$x++){
     $acct=$accountBmp.GetPixel($x,$y)
     $stop=$stopBmp.GetPixel($x,$y)
     # Account and Stop use literally the same painted text layout.
     if($x -ge $groupTextLeft -and $acct.ToArgb() -ne $stop.ToArgb()){$textDiff++}
     if($x -ge $iconRect.Left -and $x -lt $iconRect.Right -and
      $acct.ToArgb() -ne $stop.ToArgb()){$glyphDiff++}
     if($acct.R -gt 175 -and $acct.G -gt 175 -and $acct.B -gt 175) {
      $inkMin=[Math]::Min($inkMin,$x)
      $inkMax=[Math]::Max($inkMax,$x)
      if($x -ge $iconRect.Left -and $x -lt $iconRect.Right){$arrowInk++}
      if($x -ge $groupTextLeft){$textInk++}
     }
    }
   }
   Check ($textDiff -eq 0 -and $glyphDiff -gt 5) ('Account text pixels match Stop grouping, only icon changes at '+$width+'px')
   Check ($arrowInk -gt 4 -and $textInk -gt 20 -and
    $inkMin -lt $groupTextLeft -and $inkMax -ge $groupTextLeft) ('visible chevron on left of label, both readable at '+$width+'px')
   Check ([Math]::Abs((($inkMin+$inkMax)/2.0)-($width/2.0)) -le 5) ('actual painted full visual group approximately centered at '+$width+'px')
   $plainDiff=0
   for($y=0;$y -lt $height;$y++){for($x=0;$x -lt $width;$x++){
    if($x -ge $groupTextLeft -and
     $plainBmp.GetPixel($x,$y).ToArgb() -ne $accountBmp.GetPixel($x,$y).ToArgb()){$plainDiff++}
   }}
   Check ($plainDiff -gt 10) ('group-centered text differs from rejected label-only centering at '+$width+'px')
  }finally{$accountBmp.Dispose();$stopBmp.Dispose();$plainBmp.Dispose()}
  Check (-not $realStop.ShowMenuChevron -and
   $realStop.Glyph -eq [RdcButtonGlyph]::Stop -and
   $plain.Glyph -eq [RdcButtonGlyph]::None) ('Stop and plain button branches unchanged at '+$width+'px')
 }finally{$account.Dispose();$sameTextStop.Dispose();$realStop.Dispose();$plain.Dispose()}
}
$button=Make-Button 'Аккаунт' $true 120 36
try{
 $button.Tag=0
 $listener=[EventHandler]{param($sender,$arguments)$sender.Tag=[int]$sender.Tag+1}
 $button.add_Click($listener)
 try{
  $down=$button.GetType().GetMethod('OnKeyDown',$flags)
  $up=$button.GetType().GetMethod('OnKeyUp',$flags)
  foreach($key in @([Windows.Forms.Keys]::Space,[Windows.Forms.Keys]::Enter)){
   [void]$down.Invoke($button,[object[]]@([Windows.Forms.KeyEventArgs]::new($key)))
   [void]$up.Invoke($button,[object[]]@([Windows.Forms.KeyEventArgs]::new($key)))
  }
  Check ($button.Tag -eq 2) 'Account menu button retains Space/Enter keyboard activation'
 }finally{$button.remove_Click($listener)}
}finally{$button.Dispose()}
Write-Output ('RC1_ACCOUNT_BUTTON_GROUP_CENTER_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0