# Owner RC1 footer geometry: invoke the exact production button and footer
# construction spans inside an isolated, off-screen WinForms form.
# No actual GUI/Host/Remote, network access, installation, or user cursor input.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$src=[IO.File]::ReadAllText((Join-Path $root 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
function Span([string]$start,[string]$end){
 $at=$src.IndexOf($start,[StringComparison]::Ordinal)
 if($at -lt 0){throw ('START_MISSING '+$start)}
 $stop=$src.IndexOf($end,$at,[StringComparison]::Ordinal)
 if($stop -lt 0){throw ('END_MISSING '+$end)}
 return $src.Substring($at,$stop-$at)
}
$createButton=Span '$helpButton = New-Object Windows.Forms.Button' '$finish.TabIndex = 0'
$createFooter=Span '$bottom = New-Object Windows.Forms.TableLayoutPanel' '$accentOrange ='
$attachTitle=Span '[void]$titleHost.Controls.Add($title)' '$actions = New-Object Windows.Forms.FlowLayoutPanel'
$attachFooter=Span '$bottom.Controls.Add($infoHost,0,0)' '# Owner-only subtle, non-layout animation'
Check ($src.Contains('$bottom.Height = 38') -and
 $src.Contains('$bottom.Controls.Add($hintHost,1,0)') -and
 $src.Contains('$bottom.Controls.Add($helpButton,2,0)') -and
 $src.Contains('[Windows.Forms.Padding]::new(12,7,7,6)') -and
 $src.Contains('[Windows.Forms.Padding]::new(1,0,0,0)')) 'production geometry uses original 38px footer, adjacent notice and inset Help'
foreach($ownerMode in @($false,$true)){
 $OwnerGui=$ownerMode
 $form=New-Object Windows.Forms.Form
 $form.Font=New-Object Drawing.Font('Segoe UI',10)
 $form.BackColor=[Drawing.Color]::FromArgb(29,32,36)
 $form.Size=[Drawing.Size]::new(1074,150)
 $form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
 $form.Location=[Drawing.Point]::new(-12000,-12000)
 $titleHost=New-Object Windows.Forms.FlowLayoutPanel
 $title=New-Object Windows.Forms.Label
 $title.Text='RDC Relay'
 $finish=New-Object Windows.Forms.Button
 $accountButton=New-Object Windows.Forms.Button
 $infoHost=New-Object Windows.Forms.FlowLayoutPanel
 $hintHost=New-Object Windows.Forms.FlowLayoutPanel
 $hint=New-Object Windows.Forms.Label
 $hint.Font=$form.Font
 $hint.Text=''
 $tip=New-Object Windows.Forms.ToolTip
 $appVersion=if($OwnerGui){'1.6.0 RC1'}else{'1.5.18'}
 $SelfTest=$false
 $Preview=$false
 $script:ownerUpdateDemoMode=$OwnerGui
 $script:enableUpdateNotice=$OwnerGui
 $script:initializing=$false
 $script:remoteOperation=$false
 $script:rdcNoticePreviewTimer=$null
 try {
  . ([scriptblock]::Create($createButton))
  . ([scriptblock]::Create($createFooter))
  . ([scriptblock]::Create($attachTitle))
  . ([scriptblock]::Create($attachFooter))
  [void]$form.Controls.Add($bottom)
  $form.Show()
  $form.PerformLayout()
  $bottom.PerformLayout()
  if($OwnerGui){
   $helpPosition=$bottom.GetPositionFromControl($helpButton)
   Check ($bottom.Height -eq 38 -and $bottom.ColumnCount -eq 3 -and
    $bottom.ColumnStyles[2].Width -eq 25 -and
    $helpPosition.Column -eq 2 -and $helpPosition.Row -eq 0 -and
    -not $titleHost.Controls.Contains($helpButton)) 'Owner: Help moved from header into fixed far-right footer cell'
   Check ($helpButton.Size -eq [Drawing.Size]::new(24,24) -and
    $helpButton.Image.Size -eq [Drawing.Size]::new(22,22) -and
    $helpButton.ImageAlign -eq [Drawing.ContentAlignment]::MiddleCenter) 'Owner: ONLY button and question image shrink to fit existing bar'
   $above=$helpButton.Top
   $below=$bottom.ClientSize.Height-$helpButton.Bottom
   $right=$bottom.ClientSize.Width-$helpButton.Right
   Check ($above -eq 7 -and $below -eq 7 -and $right -eq 7) ('Owner: 7px above/below/right real layout (top='+$above+', bottom='+$below+', right='+$right+')')
   Check ($hintHost.Right -lt $helpButton.Left -and
    $bottom.GetPositionFromControl($hintHost).Column -eq 1 -and
    $bottom.GetPositionFromControl($infoHost).Column -eq 0) 'Owner: version host directly left of Help, information unchanged'
   $left=$helpButton.Left
   $rightBefore=$helpButton.Right
   . (Join-Path $root 'Source\update-notice.ps1')
   Check ($bottom.Controls.Contains($script:rdcNoticeControl) -and
    $bottom.Controls.Contains($helpButton) -and
    $script:rdcNoticeControl.Right -lt $helpButton.Left) 'Owner: real updater replaces adjacent version host without moving Help'
   Show-RdcUpdateNotice '1.6.0 RC2'
   $script:rdcNoticeControl.FinishAnimationForTest()
   $bottom.ColumnStyles[1].Width=$script:rdcNoticeControl.SuggestedWidth
   $bottom.PerformLayout()
   Check ($bottom.ColumnStyles[1].Width -eq 295 -and
    $helpButton.Left -eq $left -and $helpButton.Right -eq $rightBefore -and
    $script:rdcNoticeControl.Right -lt $helpButton.Left) 'Owner: expanded update button stays left of stationary Help'
   Check ($bottom.Height -eq 38 -and
    $bottom.ClientSize.Width-$helpButton.Right -eq 7) 'Owner: animated updater does not resize footer or change right inset'
   Dispose-RdcUpdateNotice
  }else{
   Check ($bottom.Height -eq 38 -and $bottom.ColumnCount -eq 2 -and
    $bottom.Padding.Right -eq 12 -and
    $titleHost.Controls.Contains($helpButton) -and
    $helpButton.Size -eq [Drawing.Size]::new(32,32) -and
    $bottom.GetControlFromPosition(1,0) -eq $hintHost) 'Legacy: title Help and two-column footer unchanged'
  }
 }finally{
  $img=$helpButton.Image
  $form.Close();$form.Dispose()
  if($img){$img.Dispose()}
  $titleHost.Dispose()
  $tip.Dispose()
 }
}
Write-Output ('RC1_HELP_FOOTER_GEOMETRY_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0