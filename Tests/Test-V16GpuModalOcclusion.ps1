# Owner-only test of the real WPF GPU divider against nested WinForms modal dialogs.
# Off-screen disposable windows; never starts a Host, GUI executable or Remote.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,WindowsFormsIntegration,PresentationCore,PresentationFramework,WindowsBase,System.Xaml
$r=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $r 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$anchor=$source.IndexOf('public sealed class RdcDividerGlowEffect : ShaderEffect {',[StringComparison]::Ordinal)
$open=$source.LastIndexOf("Add-Type -TypeDefinition @'",$anchor,[StringComparison]::Ordinal)
$begin=$source.IndexOf([char]10,$open)+1
$end=$source.IndexOf("'@ -ReferencedAssemblies @(",$anchor,[StringComparison]::Ordinal)
if($open -lt 0 -or $begin -le $open -or $end -le $begin){throw 'GPU_CSHARP_PRODUCTION_SOURCE_MISSING'}
$cs=$source.Substring($begin,$end-$begin)
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System','System.Core','System.Drawing','System.Windows.Forms','WindowsBase','PresentationCore','PresentationFramework','WindowsFormsIntegration','System.Xaml')
$pass=0;$fail=0
function Check([bool]$condition,[string]$label){
 if($condition){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($cs.Contains('Application.EnterThreadModal+=ThreadModalEntered;') -and
 $cs.Contains('Application.LeaveThreadModal+=ThreadModalLeft;') -and
 $cs.Contains('ClosePopup();') -and
 $cs.Contains('if (OwnerHasModalDialog()) return true;')) 'actual production WPF host hooks modal loops, guards visibility and closes owned native popup'
$sourceFolder=Join-Path $r 'Source'
$paths=@('divider-caustic.ps','divider-particles.ps','divider-caustic-detail.ps','divider-particles-core.ps')|ForEach-Object{Join-Path $sourceFolder $_}
foreach($p in $paths){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw 'REQUIRED_SHADER_UNAVAILABLE'}}
$owner=New-Object Windows.Forms.Form
$owner.Name='rc1-test-main'
$owner.ShowInTaskbar=$false
$owner.StartPosition=[Windows.Forms.FormStartPosition]::Manual
$owner.Location=[Drawing.Point]::new(-9000,-9000)
$owner.ClientSize=[Drawing.Size]::new(720,270)
$gpu=New-Object RdcGpuDividerHost -ArgumentList $paths
$gpu.Dock=[Windows.Forms.DockStyle]::Fill
[void]$owner.Controls.Add($gpu)
$script:outerSeen=$false;$script:nestedSeen=$false
$script:outerStillBlocked=$false
$script:modalSeenCount=0
try{
 $owner.Show()
 [Windows.Forms.Application]::DoEvents()
 Check ($gpu.IsHandleCreated -and $gpu.ParticlePopupOpenForTest -and
  -not $gpu.RenderingPaused -and $gpu.ModalDepthForTest -eq 0) 'real GPU popup begins open and animated in the isolated main window'
 for($cycle=1;$cycle -le 3;$cycle++){
  $help=New-Object Windows.Forms.Form
  $help.Name='rc1-test-help'
  $help.ShowInTaskbar=$false
  $help.StartPosition=[Windows.Forms.FormStartPosition]::Manual
  $help.Location=[Drawing.Point]::new(-9000,-9000)
  $help.ClientSize=[Drawing.Size]::new(440,190)
  $journal=New-Object Windows.Forms.Form
  $journal.Name='rc1-test-journal'
  $journal.ShowInTaskbar=$false
  $journal.StartPosition=[Windows.Forms.FormStartPosition]::Manual
  $journal.Location=[Drawing.Point]::new(-9000,-9000)
  $journal.ClientSize=[Drawing.Size]::new(430,180)
  try{
   $journal.Add_Shown({
    # WinForms EnterThreadModal fires for the outermost thread-level loop;
    # nested ShowDialog can reuse that loop without incrementing the event.
    $script:nestedSeen=($gpu.ModalDepthForTest -ge 1 -and
      $gpu.RenderingPaused -and -not $gpu.ParticlePopupOpenForTest)
    $script:modalSeenCount++
    # Forbid a forced resume while a modal is still open.
    $gpu.SimulateVisibilityPauseForTest($false)
    $script:nestedSeen=$script:nestedSeen -and $gpu.RenderingPaused -and
      -not $gpu.ParticlePopupOpenForTest
    [void]$journal.BeginInvoke([Action]{ $journal.Close() })
   })
   $help.Add_Shown({
    $script:outerSeen=($gpu.ModalDepthForTest -eq 1 -and
      $gpu.RenderingPaused -and -not $gpu.ParticlePopupOpenForTest)
    $script:modalSeenCount++
    [void]$help.BeginInvoke([Action]{
     [void]$journal.ShowDialog($help)
     $script:outerStillBlocked=($gpu.ModalDepthForTest -ge 1 -and
       $gpu.RenderingPaused -and -not $gpu.ParticlePopupOpenForTest)
     $help.Close()
    })
   })
   [void]$help.ShowDialog($owner)
   [Windows.Forms.Application]::DoEvents()
   Check ($script:outerSeen -and $script:nestedSeen -and
    $script:outerStillBlocked) ('cycle '+$cycle+': WPF native popup physically closed for Help and nested Journal, even after forced resume')
   Check ($gpu.ModalDepthForTest -eq 0) ('cycle '+$cycle+': nested modal depth returns to zero after both dialogs close')
   # Explicit state refresh must now be permitted; no stale modal state.
   $gpu.SimulateVisibilityPauseForTest($false)
   [Windows.Forms.Application]::DoEvents()
   Check (-not $gpu.RenderingPaused -and $gpu.ParticlePopupOpenForTest) ('cycle '+$cycle+': GPU popup safely reopens after all modal windows close')
  }finally{$journal.Dispose();$help.Dispose()}
 }
 Check ($script:modalSeenCount -eq 6) 'three real Help/Journal nested modal cycles completed on the WinForms UI thread'
}finally{
 $owner.Close();$owner.Dispose()
 [Windows.Forms.Application]::DoEvents()
}
Write-Output ('RC1_GPU_MODAL_LAYERING_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0