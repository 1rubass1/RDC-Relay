# Product-source RC1 Host/GUI inspection without starting any OS process tree.
# No GUI, Remote, Named Pipe listener, filesystem cleanup or installer execution.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$pass=0;$fail=0
function Check([bool]$ok,[string]$why){
 if($ok){$script:pass++;Write-Output ('PASS '+$why)}
 else{$script:fail++;Write-Output ('FAIL '+$why)}
}
try{
 foreach($n in @('remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1')){
  $tokens=$null;$err=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $src $n),[ref]$tokens,[ref]$err)
  Check ($err.Count -eq 0) ('WinPS 5.1 parser '+$n)
 }
 $gui=Get-Content -LiteralPath (Join-Path $src 'remote-window.ps1') -Raw -Encoding UTF8
 $owner=Get-Content -LiteralPath (Join-Path $src 'rc1-owner-gui.ps1') -Raw -Encoding UTF8
 $hostScript=Get-Content -LiteralPath (Join-Path $src 'rc1-tray-host.ps1') -Raw -Encoding UTF8
 $runtime=Get-Content -LiteralPath (Join-Path $src 'RdcOwnerRuntime.cs') -Raw -Encoding UTF8
 $wire=Get-Content -LiteralPath (Join-Path $src 'RdcOwnerWire.cs') -Raw -Encoding UTF8
 $observer=Get-Content -LiteralPath (Join-Path $src 'rc1-remote-observer.ps1') -Raw -Encoding UTF8
 Check ($gui.Contains('if ($OwnerGui) {') -and $gui.Contains("Start-RdcOwnerGui") -and
        $gui.Contains('$Preview=$true')) 'owner GUI reuses original complete WinForms source and suppresses legacy startup'
 Check ($gui.Contains('if (-not $SelfTest -and -not $OwnerGui)') -and
        $gui.Contains('$script:enableUpdateNotice = -not $OwnerGui')) 'owner GUI bypasses legacy destructive singleton and update'
 Check ($owner.Contains('[Windows.Forms.Application]::Run($form)') -and
        $owner.Contains('$finish.Enabled=$script:ownerManagedMode') -and
        $owner.Contains('$accountButton.Enabled=$true') -and
        $owner.Contains('$reconnectItem.Enabled=$false')) 'X exits GUI; Adopted read-only and Managed capabilities separated'
 Check ($runtime.Contains('NotifyIcon') -and $runtime.Contains('StartGui') -eq $false -and
        $runtime.Contains('public void OpenGui()')) 'persistent tray owns separate GUI process creation'
 Check ($hostScript.Contains('[void]$owner.TryAutoStartManagedRemote()') -and
        $runtime.Contains('public bool TryAutoStartManagedRemote()') -and
        $runtime.Contains('AnotherDesktopCommanderRemote()') -and
        $runtime.Contains('AnotherLegacyShell()')) 'full Host autostart requires absence of legacy GUI and external Remote'
 Check ($observer.Contains('MissingSinceTicks') -and
        $observer.Contains('FromSeconds(5)') -and
        $observer.Contains('CanPromoteObservedRemote') -and
        $runtime.Contains('PromoteObservedRemoteToManaged()') -and
        $runtime.Contains('reopenAfterModeChange')) 'lost Adopted identity needs five-second external absence before managed GUI handoff'
 Check ($runtime.Contains('remoteSupervisor.PromoteObservedToManaged()') -and
        $runtime.Contains('closeGeneration++; // old read-only GUI') -and
        $hostScript.Contains('if($observer.HandoffComplete)')) 'handoff rotates GUI generation before first Host-owned Remote autostart'
 Check ($runtime.Contains('gui.MainWindowHandle') -and
        -not [regex]::IsMatch($runtime,'(?m)^\s*(?:Stop-Process|taskkill|gui\.Kill\()')) 'GUI duplicate path has no HWND forced termination'
 $observer=Get-Content -LiteralPath (Join-Path $src 'rc1-remote-observer.ps1') -Raw -Encoding UTF8
 $observerErrors=$null;$observerTokens=$null
 [void][Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $src 'rc1-remote-observer.ps1'),[ref]$observerTokens,[ref]$observerErrors)
 Check ($runtime.Contains('if(!fakeOnly)throw') -and $hostScript.Contains('RC1_SELECT_EXACTLY_ONE_MODE') -and
        $hostScript.Contains('ObserveExisting') -and $observer.Contains('Get-Rc1ObservedRemoteIdentity') -and
        $observer.Contains('@wonderwhy-er/desktop-commander@0.2.52') -and
        $observerErrors.Count -eq 0 -and
        -not [regex]::IsMatch($observer,'(?im)^[^#\r\n]*(?:Stop-Process|taskkill|remote --logout)')) 'read-only existing Remote observer has explicit gate and no stop route'
 Check ($runtime.Contains('GetNamedPipe') -eq $false -and
        $wire.Contains('GetNamedPipeClientProcessId') -and $wire.Contains('GetNamedPipeServerProcessId')) 'IPC checks OS-observed peer on both sides'
 Check ($wire.Contains('TokenLogonSid') -and $wire.Contains('WellKnownSidType.NetworkSid') -and
        $wire.Contains('MaxRequest=8192') -and $wire.Contains('MaxResponse=65536')) 'bounded frames and logon SID ACL'
 Check ($runtime.Contains('RdcOwnerWire.Born(childPid)!=childBorn') -and
        $runtime.Contains('requestIds.Contains(requestId)') -and $runtime.Contains('PROTOCOL_MISMATCH')) 'peer birth/replay/protocol checks'
 Check ($runtime.Contains('if(verb=="GET_SNAPSHOT")') -and $runtime.Contains('if(verb=="GET_EVENTS")') -and
        $runtime.Contains('if(verb=="OPEN_EXTERNAL")') -and $runtime.Contains('if(verb=="REMOTE_ACTION")') -and
        $runtime.Contains('ADOPTED_REMOTE_READ_ONLY') -and $runtime.Contains('if(verb=="DETACH")') -and
        $runtime.Contains('return Error(requestId,"VERB_DENIED")')) 'authenticated IPC allowlist: Adopted denied; Managed actions require confirmed GUI'
 Check ($runtime.Contains('events.Count>128') -and $runtime.Contains('events.Count>0 && after<') -and
        $owner.Contains('if([bool]$eventData.gap)')) 'bounded monotonic ring and lost-event recovery'
 Check ($runtime.Contains('INCOMPATIBLE_GUI') -and
        $owner.Contains('RC1_OWNER_HELLO_REJECTED')) 'incompatible GUI build refused'
 $ticketSource=Get-Content -LiteralPath (Join-Path $src 'RdcOwnerTicketStore.cs') -Raw -Encoding UTF8
 Check ($ticketSource.Contains('FileMode.CreateNew') -and $ticketSource.Contains('FileSecurity') -and
        $ticketSource.Contains('RevokeOnlyOwned') -and
        $runtime.Contains('RdcOwnerTicketStore')) 'private ticket ACL before bytes, owned-only retry cleanup'
 Check ($runtime.Contains('Process.Start(info)') -and $runtime.Contains('sourceRoot') -and
        $runtime.Contains('remote-window.ps1')) 'Host uses current original GUI source, not a new demo window'
 Check ($runtime.Contains('exitRequested=true;closeGeneration++') -and
        $runtime.Contains('if(exitRequested && gui==null && guiState=="NONE")context.ExitThread();') -and
        $runtime.Contains('if(!fakeOnly)throw')) 'Exit waits for GUI process; managed job requires verified stop before completion'
 # C# compiler never executes the generated DLL, WinForms or any process.
 $compiler=@((Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'),
             (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'))|Where-Object{[IO.File]::Exists($_)}|Select-Object -First 1
 if(-not $compiler){throw 'Windows .NET Framework compiler missing'}
 $dll=Join-Path $root 'dist\v1.6.0-RC1-BLOCKED-PREFLIGHT\RdcOwnerRuntime.STATIC_TEST.dll'
 if([IO.File]::Exists($dll)){throw 'Unrecognized previous DLL; refuse overwrite'}
 try{
  & $compiler /nologo /target:library ('/out:'+$dll) /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll (Join-Path $src 'RdcOwnerWire.cs') (Join-Path $src 'RdcOwnerProcess.cs') (Join-Path $src 'RdcOwnerTicketStore.cs') (Join-Path $src 'RdcOwnerRemoteState.cs') (Join-Path $src 'RdcOwnerManagedProcess.cs') (Join-Path $src 'RdcOwnerRuntime.cs')
  Check ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($dll)) 'real product Host+IPC source compiled into .NET Framework DLL'
 }finally{if([IO.File]::Exists($dll)){[IO.File]::Delete($dll)}}
}catch{$fail++;Write-Output ('FAIL unexpected '+$_.Exception.Message)}
Write-Output ('RC1_PRODUCT_SOURCE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
