# G119 — Account text centered independently of painted menu chevron.
# Production button C# extracted by AST. Isolated WinForms paint only.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'
$raw=[IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)
$tok=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tok,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$description) {
 if($ok){$script:pass++;Write-Output ('PASS '+$description)}
 else{$script:fail++;Write-Output ('FAIL '+$description)}
}
Check ($errors.Count -eq 0) 'production UI source parses'
$node=$ast.Find({param($n)
 $n -is [Management.Automation.Language.StringConstantExpressionAst] -and
 $n.Value.Contains('public class RdcRoundedButton') -and
 $n.Value.Contains('public class RdcCircleButton')
},$true)
if(-not $node){throw 'G119_ROUNDED_BUTTON_CSHARP_SOURCE_MISSING'}
Add-Type -TypeDefinition $node.Value -ReferencedAssemblies System.Windows.Forms,System.Drawing
Check ($raw.Contains("$accountButton.Text = 'Аккаунт'") -and
 $raw.Contains('$accountButton.ShowMenuChevron = $true') -and
 $raw.Contains("$accountButton.AccessibleName = 'Аккаунт, открыть меню'") -and
 -not $raw.Contains("$accountButton.Text = 'Аккаунт ▾'")) 'production Account text has no inline dropdown symbol and exposes accessible label'
Check ($raw.Contains('$accountMenu.Show($accountButton,(New-Object Drawing.Point(0,$accountButton.Height)))')) 'unchanged account menu opens below the same control'
Check ($raw.Contains("$finish.Glyph = [RdcButtonGlyph]::Stop") -and
 $raw.Contains("$finish.Text = 'Остановить'")) 'Stop button glyph and text remain unchanged'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
$paint=[RdcRoundedButton].GetMethod('OnPaint',$flags)
$bounds=[RdcRoundedButton].GetMethod('GetMenuChevronBounds',$flags)
if(-not $paint -or -not $bounds){throw 'G119_PAINT_METHOD_OR_CHEVRON_BOUNDS_MISSING'}
function Make-Button([string]$text,[bool]$chevron,[int]$width,[int]$height){
 $control=New-Object RdcRoundedButton
 $control.Text=$text
 $control.ShowMenuChevron=$chevron
 $control.Tone=[RdcButtonTone]::Neutral
 $control.Size=[Drawing.Size]::new($width,$height)
 $control.BackColor=[Drawing.Color]::FromArgb(29,32,36)
 return $control
}
function Paint-Button($control){
 $bitmap=New-Object Drawing.Bitmap($control.Width,$control.Height)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try {
  $graphics.Clear([Drawing.Color]::Magenta)
  $event=New-Object Windows.Forms.PaintEventArgs($graphics,$control.ClientRectangle)
  [void]$paint.Invoke($control,[object[]]@($event.PSObject.BaseObject))
 }finally{$graphics.Dispose()}
 return $bitmap
}
foreach($dimension in @(@(120,36),@(144,43))){
 $width=$dimension[0];$height=$dimension[1]
 $plain=Make-Button 'Аккаунт' $false $width $height
 $arrow=Make-Button 'Аккаунт' $true $width $height
 $blank=Make-Button '' $false $width $height
 try {
  $rect=[Drawing.Rectangle]$bounds.Invoke($arrow,@())
  $textWidth=[Windows.Forms.TextRenderer]::MeasureText(
   $arrow.Text,$arrow.Font,[Drawing.Size]::new([int]::MaxValue,$height),
   ([Windows.Forms.TextFormatFlags]::VerticalCenter -bor
    [Windows.Forms.TextFormatFlags]::SingleLine -bor
    [Windows.Forms.TextFormatFlags]::NoPadding)).Width
  Check ($rect.Left -ge (0.5*($width+$textWidth)+4) -and
   $rect.Right -le ($width-8) -and $rect.Height -eq 8) ('menu chevron does not overlap centered label at '+$width+'px')
  $onlyText=Paint-Button $plain
  $withArrow=Paint-Button $arrow
  $noText=Paint-Button $blank
  try {
   $leftSame=$true;$rightDiff=0;$minX=$width;$maxX=0;$textPixels=0
   for($y=0;$y -lt $height;$y++){
    for($x=0;$x -lt $width;$x++){
     $a=$onlyText.GetPixel($x,$y).ToArgb()
     $b=$withArrow.GetPixel($x,$y).ToArgb()
     if($x -lt $rect.Left -and $a -ne $b){$leftSame=$false}
     if($x -ge $rect.Left -and $a -ne $b){$rightDiff++}
     if($x -lt $rect.Left -and $a -ne $noText.GetPixel($x,$y).ToArgb()){
      $minX=[Math]::Min($minX,$x)
      $maxX=[Math]::Max($maxX,$x)
      $textPixels++
     }
    }
   }
   Check ($leftSame -and $rightDiff -gt 5 -and
    $rightDiff -lt 100) ('arrow-only pixels change right edge and never shift text at '+$width+'px')
   Check ($textPixels -gt 30 -and
    [Math]::Abs((($minX+$maxX)/2.0)-($width/2.0)) -le 3) ('visible Account letter pixel bounding box centered within 3px at '+$width+'px')
   $stop=Make-Button 'Остановить' $false $width $height
   try {
    $stop.Glyph=[RdcButtonGlyph]::Stop
    Check (-not $stop.ShowMenuChevron -and
     $stop.Glyph -eq [RdcButtonGlyph]::Stop) ('Stop icon branch remains independent at '+$width+'px')
   }finally{$stop.Dispose()}
  }finally{$onlyText.Dispose();$withArrow.Dispose();$noText.Dispose()}
 }finally{$plain.Dispose();$arrow.Dispose();$blank.Dispose()}
}
$click=Make-Button 'Аккаунт' $true 120 36
try {
 $click.Tag=0
 $listener=[EventHandler]{param($sender,$arguments)$sender.Tag=[int]$sender.Tag+1}
 $click.add_Click($listener)
 try{
  $keyDown=$click.GetType().GetMethod('OnKeyDown',$flags)
  $keyUp=$click.GetType().GetMethod('OnKeyUp',$flags)
  foreach($key in @([Windows.Forms.Keys]::Space,[Windows.Forms.Keys]::Enter)){
   [void]$keyDown.Invoke($click,[object[]]@([Windows.Forms.KeyEventArgs]::new($key)))
   [void]$keyUp.Invoke($click,[object[]]@([Windows.Forms.KeyEventArgs]::new($key)))
  }
  Check ($click.Tag -eq 2) 'keyboard Space/Enter still dispatch Account Click'
 }finally{$click.remove_Click($listener)}
}finally{$click.Dispose()}
Write-Output ('RC1_ACCOUNT_BUTTON_CENTER_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0