# Product owner-mode invariant checks. AST/string inspection ONLY, not GUI runs.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$pass=0;$fail=0
function Check([bool]$ok,[string]$why){if($ok){$script:pass++;Write-Output ('PASS '+$why)}else{$script:fail++;Write-Output ('FAIL '+$why)}}
try{
 $file=Join-Path $src 'remote-window.ps1'
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'full original GUI AST parses on PowerShell 5.1'
 $danger=@('Open-Reader','Read-LiveLog','Find-ExistingRemote','Start-Remote','Stop-Remote','Begin-RemoteOperation','Update-RemoteOperation','Restart-Remote','Switch-RemoteAccount','Start-RuntimeInitialization','Refresh-Window')
 $defs=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
 $guarded=0
 foreach($name in $danger){
  $matches=@($defs|Where-Object{$_.Name -ceq $name})
  if($matches.Count -ne 1){Write-Output ('FAIL missing/duplicate function '+$name);$fail++;continue}
  $block=$matches[0].Body.Extent.Text
  $ok=$block -match '^\{\s*if\s*\(\s*\$OwnerGui\s*\)\s*\{' -and $block.Contains('RC1_OWNER_GUI_ACTION_BLOCKED')
  if($name -eq 'Refresh-Window'){$ok=$block -match '^\{\s*if\s*\(\s*\$OwnerGui\s*\)\s*\{\s*return\s*\}'}
  Check $ok ('guarded original action '+$name)
 }
 $owner=Get-Content -LiteralPath (Join-Path $src 'rc1-owner-gui.ps1') -Raw -Encoding UTF8
 Check ($owner.Contains('$finish.Enabled=$false;$accountButton.Enabled=$false')) 'owner-mode primary Remote actions disabled'
 Check ($owner.Contains('$remoteSnapshot=$snapshot.remote') -and $owner.Contains('RC1_REMOTE_MODE_MISMATCH') -and
        $owner.Contains('$remoteSnapshot.logStreamEpoch') -and $owner.Contains('$remoteSnapshot.logCursor') -and
        $owner.Contains('Add-CompletedEvent') -and $owner.Contains('Reset-CompactLogSession')) 'GUI rehydrates bounded Host snapshot in exact observer/fake mode'
 Check ($owner.Contains('RC1_LOG_CURSOR_REGRESSED') -and $owner.Contains('RC1_LOG_CURSOR_MISMATCH') -and
        $owner.Contains('RC1_INVALID_LOG_TAIL')) 'GUI rejects missing/out-of-order fake log lines'
 Check ($owner.Contains('$switchAccountItem') -and $owner.Contains('$reconnectItem') -and $owner.Contains('$openLogItem')) 'secondary account/reconnect/user-log actions disabled'
 $source=Get-Content -LiteralPath $file -Raw -Encoding UTF8
 Check ($source.Contains("X закрывает только текущий GUI-процесс") -and $source.Contains("настоящий Remote не подключён")) 'RC1 About states real X semantics and no Remote'
 Check ($source.Contains('if (-not $SelfTest -and -not $OwnerGui)') -and $source.Contains('$script:enableUpdateNotice = -not $OwnerGui')) 'legacy mutex and updater bypassed'
 $runtime=Get-Content -LiteralPath (Join-Path $src 'RdcOwnerRuntime.cs') -Raw -Encoding UTF8
 Check ($runtime.Contains('CreateThen(TicketPayload()') -and $runtime.Contains('ticketStore.RevokeOnlyOwned()')) 'ticket failure and clean close use same owned-token guard'
 Check ($runtime.Contains('RC1_CONSTRUCTOR_NOT_CLEAN_IPC_OR_RUN_ROOT') -and $runtime.Contains('server.Dispose()')) 'constructor reports incomplete IPC/temporary root teardown'
 Check ($runtime.Contains('if(exitRequested && gui==null && guiState=="NONE")')) 'fake Exit refuses uncertain GUI/ticket state'
 Check ($runtime.Contains('RC1_OWNER_SHUTDOWN_NOT_CLEAN') -and $runtime.Contains('RemoveEmptyOwnedRunRoot')) 'Host full disposal reports incomplete own files'
 $setup=Get-Content -LiteralPath (Join-Path $root 'Installer\Rc1CandidateSetup.cs') -Raw -Encoding UTF8
 $launcher=Get-Content -LiteralPath (Join-Path $root 'Installer\Rc1CandidateLauncher.cs') -Raw -Encoding UTF8
 Check ($setup.Contains('#if RDC_RC1_BLOCKED') -and $setup.Contains('return 42;') -and $setup.Contains('RDC_RC1_OWNER_G1_GO')) 'isolated candidate Setup gated before install'
 Check ($launcher.Contains('#if RDC_RC1_BLOCKED') -and $launcher.Contains('return 42;') -and
        $launcher.Contains('--observe-existing') -and $launcher.Contains('RC1_NOT_VERIFIED_READ_ONLY_OBSERVER')) 'private Launcher gated by exact read-only marker and explicit option'
 Check ($setup.Contains('RDCRelayOwnerPilot') -and $setup.Contains('RC1_TARGET_EXISTS') -and $setup.Contains('RC1_COPY_HASH_FAIL')) 'side-by-side target denies overwrite and verifies copied bytes'
 Check ($launcher.Contains('liveRemoteEnabled') -and $launcher.Contains('rc1-tray-host.ps1') -and
        $launcher.Contains('-ObserveExisting') -and -not $launcher.Contains(' -FakeOnly')) 'private launcher observes existing Remote without starting it'
}catch{$fail++;Write-Output ('FAIL unexpected '+$_.Exception.Message)}
Write-Output ('RC1_OWNER_BOUNDARY_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
