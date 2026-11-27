$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$raw=[IO.File]::ReadAllText((Join-Path $root 'Source/remote-window.ps1'))
$anchor=$raw.IndexOf('public sealed class RdcOwnerHeaderViewport : Panel {');$a=$raw.LastIndexOf("Add-Type -TypeDefinition @'",$anchor)+("Add-Type -TypeDefinition @'").Length
$b=$raw.IndexOf("'@ -ReferencedAssemblies",$a)
if($a -lt 0 -or $b -le $a){throw 'CLASS_BOUNDARY'}
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing,System.Windows.Forms -TypeDefinition $raw.Substring($a,$b-$a)
$pass=0
function Check([bool]$ok,[string]$name){if(!$ok){throw ('FAIL '+$name)};$script:pass++;'PASS '+$name}
$font=New-Object Drawing.Font('Consolas',9)
$log=New-Object RdcLogBox
$log.Font=$font;$log.WordWrap=$true;$log.ScrollBars='None';$log.BorderStyle='None';$log.Margin=[Windows.Forms.Padding]::new(3,5,3,3)
$log.Text=[string]::Join([Environment]::NewLine,@(1..40|ForEach-Object{"Line $_ "+('body '*35)}))
$banner=New-Object RdcOwnerWordmark
$viewport=New-Object RdcOwnerHeaderViewport($banner,$log)
$scroll=New-Object RdcOverlayScrollBar
$scroll.Vertical=$true;$scroll.Target=$log
$scroll.VerticalMetricsProvider=[Func[int[]]]{return ,$viewport.ScrollMetrics()}
$scroll.VerticalPositionSetter=[Action[int]]{param($value)$viewport.ScrollTo($value)}
$scroll.VerticalStepProvider=[Func[int]]{return $viewport.LineStep}
try{
 $viewport.Size=[Drawing.Size]::new(800,300);[void]$viewport.Handle;[void]$log.Handle;[void]$scroll.Handle
 $viewport.Reflow($true)
 Check ($viewport.BannerHeight -gt 0 -and $viewport.ContentHeight -gt 300) 'combined content extent'
 Check ($banner.Top -eq 0 -and $log.Top -eq ($banner.Height+$log.Margin.Top)) 'bitmap and text begin in same surface'
 $height=$viewport.BannerHeight
 $viewport.ScrollTo(25)
 Check ($banner.Top -eq -25 -and $log.Top -eq ($height-25+$log.Margin.Top)) 'pixel scroll moves both controls together'
 $viewport.ScrollTo($height)
 Check ($banner.Bottom -eq 0) 'banner scrolls completely out'
 $scroll.ScrollToEnd()
 Check ($viewport.ScrollOffset -eq $viewport.MaximumOffset -and $scroll.IsAtEnd) 'real scrollbar reaches combined content end'
 $viewport.ScrollTo(0)
 Check (-not $scroll.IsAtEnd) 'real scrollbar detects top'
 $viewport.ScrollWheel(-120)
 Check ($viewport.ScrollOffset -gt 0) 'wheel moves combined viewport'
 $viewport.Size=[Drawing.Size]::new(800,$height)
 Check ($viewport.ScrollOffset -eq 0 -and $banner.Bottom -eq $viewport.Height -and $log.Top -ge $viewport.Height) 'collapse leaves full banner and no visible text'
 $viewport.ScrollTo($height)
 Check ($banner.Bottom -eq 0) 'collapsed viewport remains scrollable'
 $viewport.Size=[Drawing.Size]::new(800,300)
 $viewport.ScrollTo([int]::MaxValue)
 Check ($viewport.ScrollOffset -eq $viewport.MaximumOffset) 'offset clamped after resize'
 $log.Text='short';$viewport.Reflow($true)
 Check ($viewport.ScrollOffset -eq 0 -and $viewport.MaximumOffset -eq 0) 'shortened header resets impossible scroll'
 foreach($dpi in @(96,120,144,168,192)){foreach($width in @(260,480,800,1100,1800)){
  $h=[RdcOwnerWordmark]::NaturalRowHeight($width,$dpi)
  $rect=[RdcOwnerWordmark]::ImageBounds($width,$h,$dpi)
  Check ($rect.Width -gt 0 -and [Math]::Abs($rect.Left-($width-$rect.Right)) -le 1 -and $rect.Bottom -le $h -and [Math]::Abs($rect.Height-$rect.Width*74.0/997) -le 1) ('symmetric banner '+$dpi+' '+$width)
 }}
}finally{$scroll.Dispose();$viewport.Dispose();$font.Dispose()}
'RDC_HEADER_VIEWPORT_PASS='+$pass
