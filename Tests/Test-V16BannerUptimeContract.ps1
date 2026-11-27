# Isolated original renderer and uptime contract.
$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'))
$view=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'))
$runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'))
$child=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerManagedProcess.cs'))
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'rc1-owner-gui.ps1'),[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){if($ok){$script:pass++;Write-Output ('PASS '+$label)}else{$script:fail++;Write-Output ('FAIL '+$label)}}
Check ($errors.Count -eq 0) 'Owner GUI parses'
Check ($view.Contains('Color-HeaderSemantics $headerLog $headerLog.TextLength') -and $view.Contains('StyleStartupBanner(')) 'original rich-text coloring retained'
Check ($child.Contains('public long BornUtcTicks {get{return born;}}')) 'verified Remote OS birth provided'
Check ($runtime.Contains('managedBornUtcTicks=child.BornUtcTicks') -and $runtime.Contains('"remoteBornUtcTicks"')) 'Remote birth sent by Host'
Check ($gui.Contains('{0:00}:{1:00}:{2:00}') -and $gui.Contains('$script:ownerRemoteBornTicks')) 'original uptime footer restored'
Check (-not $gui.Contains("'Управление: Host-owned Job'")) 'obsolete footer text removed'
Check ($runtime.Contains('AcceptManagedBannerArt(cleanLine)') -and $runtime.Contains('"remoteStartupArt"') -and $gui.Contains('$snapshot.remoteStartupArt')) 'safe original startup art in authenticated snapshot'
Check ($gui.Contains("owner.fallback.label.user") -and $gui.Contains("owner.fallback.label.deviceName") -and $gui.Contains("owner.fallback.label.deviceId") -and $view.Contains("User:\s*(.+)") -and $view.Contains("Device Name:\s*(.+)") -and $view.Contains("Device ID:\s*(.+)")) 'localized identity labels and original semantic value coloring apply'
# The original six-row pseudographic DESKTOP (left) / COMMANDER (right)
# banner is the only reversed palette. Test the exact production RichEdit
# painter, not a reimplementation of its 61-character split.
Check ([regex]::IsMatch($view,'(?s)\[void\]\$headerLog\.StyleStartupBanner\(\s*\$accentOrange,\s*\[Drawing\.Color\]::FromArgb\(123,95,162\)\s*\)')) 'main window passes orange left and purple right to the real banner painter'
$start=$view.IndexOf('public class RdcLogBox : RichTextBox {',[StringComparison]::Ordinal)
$end=$view.IndexOf("'@ -ReferencedAssemblies",$start,[StringComparison]::Ordinal)
Check ($start -ge 0 -and $end -gt $start) 'exact production RichEdit style source is available for color verification'
if($start -ge 0 -and $end -gt $start){
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 $cs='using System;using System.IO;using System.Text;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;using System.Runtime.InteropServices;using System.Diagnostics;'+
   [Environment]::NewLine+$view.Substring($start,$end-$start)
 Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
 $probe=New-Object RdcLogBox
 try {
  $probe.ForeColor=[Drawing.Color]::Gainsboro
  $line=('D'*61)+('C'*12)
  $sourceText=(($line+[Environment]::NewLine)*6)+'Remote Connection'
  $probe.Text=$sourceText
  $orange=[Drawing.Color]::FromArgb(191,118,67)
  $purple=[Drawing.Color]::FromArgb(123,95,162)
  Check ($probe.StyleStartupBanner($orange,$purple)) 'six-row banner recognizes the real startup marker'
  $probe.Select(0,1)
  Check ($probe.SelectionColor.ToArgb() -eq $orange.ToArgb()) 'DESKTOP first 61 columns render orange'
  $probe.Select(61,1)
  Check ($probe.SelectionColor.ToArgb() -eq $purple.ToArgb()) 'COMMANDER remaining columns render purple'
  $probe.Select(60,2)
  Check (($probe.Text -replace '\r','') -ceq ($sourceText -replace '\r','') -and
   $probe.TextLength -gt 6*73) 'color change preserves six-row pseudographic text and spacing'
 }finally{$probe.Dispose()}
}
Write-Output ('RC1_BANNER_UPTIME_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
