# Pure WinForms bitmap test of the Owner GPU-less divider Paint event.
# No Remote, Host, installed app, window activation or state mutation.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$value,[string]$label){
 if($value){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($source.Contains('if($OwnerGui -and $gpuDividerAvailable)')) 'Owner-only hardware preflight present'
Check ($source.Contains('[System.Windows.Media.RenderCapability]::Tier -shr 16') -and
 $source.Contains('if($tier -lt 2)') -and
 $source.Contains('$gpuDividerAvailable=$false')) 'Tier 0/1 disables layered WPF popup before construction'
Check ($source.Contains('$script:ownerGpuDividerFallbackReason') -and
 $source.Contains("'WPF_TIER_UNAVAILABLE'")) 'GPU query errors fall back without crashing GUI'
Check ($source.Contains('if ($gpuDividerAvailable) {') -and
 $source.Contains('$headerDivider.Controls.Add($gpuDivider)')) 'GPU Tier 2+ retains original shader path'
$begin=$source.IndexOf('$headerDivider.Add_Paint({',[StringComparison]::Ordinal)
$end=$source.IndexOf([char]10+'})',$begin,[StringComparison]::Ordinal)
if($begin -lt 0 -or $end -le $begin){throw 'RDC_SOFTWARE_DIVIDER_PAINT_SOURCE_MISSING'}
$eventScript=$source.Substring($begin,$end-$begin+3)
$script:headerDivider=New-Object Windows.Forms.Panel
$script:headerDivider.Size=[Drawing.Size]::new(420,7)
$script:headerDivider.BackColor=[Drawing.Color]::FromArgb(18,20,23)
$script:OwnerGui=$true
$script:gpuDivider=$null
try{
 Invoke-Expression $eventScript
 $bitmap=New-Object Drawing.Bitmap(420,7)
 try{
  $script:headerDivider.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,420,7))
  $left=$bitmap.GetPixel(5,3)
  $right=$bitmap.GetPixel(412,3)
  $top=$bitmap.GetPixel(210,0)
  Check ($left.R -gt $left.B -and $left.R -gt 100) 'left fallback rail paints orange'
  Check ($right.B -gt $right.R - 20 -and $right.B -gt 100) 'right fallback rail paints purple'
  Check ($top.R -lt 220 -and $top.B -gt 30) 'top border remains dark purple'
  $white=$false
  for($x=0;$x -lt $bitmap.Width;$x+=7){
   for($y=0;$y -lt $bitmap.Height;$y++){
    $c=$bitmap.GetPixel($x,$y)
    if($c.R -gt 248 -and $c.G -gt 248 -and $c.B -gt 248){$white=$true;break}
   }
  }
  Check (-not $white) 'software divider never renders opaque white stripe'
 }finally{$bitmap.Dispose()}
 $script:OwnerGui=$false
 $legacy=New-Object Drawing.Bitmap(420,7)
 try{
  $script:headerDivider.DrawToBitmap($legacy,[Drawing.Rectangle]::new(0,0,420,7))
  $p=$legacy.GetPixel(5,3)
  Check ($p.R -lt 85 -and $p.G -lt 85) 'legacy divider retains original dark rendering'
 }finally{$legacy.Dispose()}
}finally{$script:headerDivider.Dispose()}
Check ($source.Contains('$headerDivider.Cursor = [Windows.Forms.Cursors]::SizeNS') -and
 $source.Contains('$headerDivider.Add_MouseDown')) 'divider remains draggable in fallback'
Check ($source.Contains('$headerDivider.Controls.Remove($gpuDivider);$gpuDivider.Dispose()') -and
 $source.Contains('$headerDivider.Invalidate()')) 'failed WPF initialization detaches any partial popup before native repaint'
Write-Output ('RC1_GPU_SOFTWARE_FALLBACK_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
