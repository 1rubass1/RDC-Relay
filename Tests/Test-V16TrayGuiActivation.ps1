# RC1 G122: isolated Owner GUI activation contract; never launches Host or Remote.
# Windows PowerShell 5.1 STA; creates ONLY a hidden test Form with a synthetic title.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$path=Join-Path $root 'Source\RdcOwnerRuntime.cs'
$src=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
Check ($src.Contains('gui.Refresh();') -and
 $src.Contains('gui.StartTime.ToUniversalTime().Ticks!=childBorn') -and
 $src.Contains('gui.SessionId!=childSession') -and
 $src.Contains('gui.Id!=childPid')) 'Host checks owned GUI identity and refreshes HWND before reuse'
Check ($src.Contains('FindOwnedWindow(childPid)') -and
 $src.Contains('OpenOwned(target,childPid)') -and
 $src.Contains('if(gui!=null)') -and
 $src.Contains('return; // verified live child: never launch a second GUI')) 'live window rediscovery cannot create second GUI'
Check ($src.Contains('foreground denied') -and
 $src.Contains('NotifyGuiOpenIssue') -and
 $src.Contains('tray.ShowBalloonTip(3000)') -and
 $src.Contains('FlashWindowEx(ref flash)')) 'activation denial yields bounded taskbar and tray attention'
Check (-not $src.Contains('AttachThreadInput') -and
 -not $src.Contains('keybd_event') -and
 -not $src.Contains('SWP_TOPMOST') -and
 -not $src.Contains('SendKeys.Send')) 'no foreground theft, synthetic input, or persistent TopMost'
Check ($src.Contains('guiWindowWarned=true; // one check per GUI generation') -and
 $src.Contains('TotalSeconds>=RdcOwnerGuiStartupNotice.GraceSeconds') -and
 $src.Contains('if(RdcOwnerGuiStartupNotice.IsDue(guiSpawnUtc,DateTime.UtcNow,guiWindowWarned,false))') -and
 $src.Contains('if(RdcOwnerGuiStartupNotice.IsDue(guiSpawnUtc,DateTime.UtcNow,guiWindowWarned,hasOwnedWindow))') -and
 $src.Contains('TotalSeconds<8')) 'both startup probe and tray retry share an eight-second one-shot no-window warning gate'
$noticeStart=$src.IndexOf('public static class RdcOwnerGuiStartupNotice {',[StringComparison]::Ordinal)
$noticeEnd=$src.IndexOf('public sealed class RdcOwnerRuntime : IDisposable {',$noticeStart,[StringComparison]::Ordinal)
if($noticeStart -lt 0 -or $noticeEnd -le $noticeStart){throw 'GUI_STARTUP_NOTICE_HELPER_MISSING'}
$noticeCode="using System;"+[Environment]::NewLine+$src.Substring($noticeStart,$noticeEnd-$noticeStart)
Add-Type -TypeDefinition $noticeCode
$now=[DateTime]::UtcNow
Check ([RdcOwnerGuiStartupNotice]::GraceSeconds -eq 8 -and
 -not [RdcOwnerGuiStartupNotice]::IsDue($now,$now,$false,$false) -and
 -not [RdcOwnerGuiStartupNotice]::IsDue($now,$now.AddMilliseconds(7999),$false,$false)) 'no premature warning on initial spawn or repeated tray click before 8 seconds'
Check ([RdcOwnerGuiStartupNotice]::IsDue($now,$now.AddSeconds(8),$false,$false) -and
 [RdcOwnerGuiStartupNotice]::IsDue($now,$now.AddSeconds(12),$false,$false)) 'missing HWND after 8 seconds qualifies for warning'
Check (-not [RdcOwnerGuiStartupNotice]::IsDue($now,$now.AddSeconds(8),$true,$false) -and
 -not [RdcOwnerGuiStartupNotice]::IsDue($now,$now.AddSeconds(8),$false,$true) -and
 -not [RdcOwnerGuiStartupNotice]::IsDue([DateTime]::MinValue,$now,$false,$false)) 'one-shot and visible/unknown GUI state never trigger false warning'
Check ($src.Contains('OpenGui();') -and
 $src.Contains('tray.DoubleClick+=(s,e)=>OpenGui();') -and
 $src.Contains('open.Click+=(s,e)=>OpenGui();') -and
 $src.Contains('reopenSignal.WaitOne(0)')) 'tray menu, tray double-click and launcher event retain common OpenGui route'
$start=$src.LastIndexOf('public static class RdcOwnerActivate {',[StringComparison]::Ordinal)
if($start -lt 0){throw 'ACTIVATION_HELPER_MISSING'}
$end=$src.IndexOf('// Multi-size PNG-backed Windows icons',$start,[StringComparison]::Ordinal)
if($end -lt $start){throw 'G122_ACTIVATION_HELPER_END_MISSING'}
$code="using System;"+[Environment]::NewLine+$src.Substring($start,$end-$start)
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Windows.Forms,System.Drawing
Check ([RdcOwnerActivate]::OpenOwned([IntPtr]::Zero,$PID) -ceq 'NO_WINDOW') 'null HWND returns no-window status without side effects'
$fake=New-Object Windows.Forms.Form
$other=New-Object Windows.Forms.Form
try{
 $fake.Text='RDC Relay 1.6.0 RC1 — Fake only test'
 $other.Text='Unrelated helper window'
 $fake.ShowInTaskbar=$false
 $other.ShowInTaskbar=$false
 $fakeHandle=$fake.Handle
 $otherHandle=$other.Handle
 Check ($fakeHandle -ne [IntPtr]::Zero -and $otherHandle -ne [IntPtr]::Zero) 'hidden isolated WinForms test handles created'
 $found=[RdcOwnerActivate]::FindOwnedWindow($PID)
 Check ($found -eq $fakeHandle) 'hidden RDC Relay window is found by verified owning PID and title prefix'
 Check ([RdcOwnerActivate]::OpenOwned($fakeHandle,($PID+17777)) -ceq 'NOT_OWNED') 'correct window cannot activate under spoofed GUI PID'
 Check ([RdcOwnerActivate]::FindOwnedWindow(($PID+17777)) -eq [IntPtr]::Zero) 'wrong PID does not allow title-only window adoption'
 $fake.Text='RDC Relay 1.6.0 RC1 — управляемый Host/GUI'
 Check ([RdcOwnerActivate]::FindOwnedWindow($PID) -eq $fakeHandle) 'real managed-mode Owner GUI title is recognized even while its WinForms window is hidden'
 $fake.Text='RDC Relay — справка'
 Check ([RdcOwnerActivate]::FindOwnedWindow($PID) -eq [IntPtr]::Zero) 'same-process About dialog cannot be mistaken for the main GUI'
 $fake.Text='Unrelated helper window renamed'
 Check ([RdcOwnerActivate]::FindOwnedWindow($PID) -eq [IntPtr]::Zero) 'name-mismatched helper windows are never treated as main GUI'
}finally{
 $other.Dispose()
 $fake.Dispose()
}
Write-Output ('RC1_GUI_ACTIVATION_CONTRACT_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0