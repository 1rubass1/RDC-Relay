# Isolated RU/EN Owner activity and notification presentation.
# No Host, Remote, GUI window, browser, preferences or installed files are touched.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Source'
Add-Type -Path (Join-Path $source 'RdcUiLanguage.cs') -ReferencedAssemblies @(
 'System.dll','System.Core.dll','System.Web.Extensions.dll')
. (Join-Path $source 'rc1-owner-gui.ps1')
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$script:ownerUiTexts=$null
Check ((Format-Rc1JournalLine 7 'Remote tool completed|7|read_file|report.txt') -ceq
 '000007 │ ✅ Чтение файла → report.txt') 'missing locale data preserves exact legacy Russian journal'
$ru=[RdcUiLanguage]::LoadResources($source,'ru-RU')
$en=[RdcUiLanguage]::LoadResources($source,'en-US')
Check ($ru.Count -eq $en.Count -and $ru.Count -ge 135) 'both new resource catalogs load with all journal and notification keys'
$script:ownerUiTexts=$ru
Check ((Get-Rc1JournalUiText 'journal.ack.switchAccountAccepted' '') -ceq
 'Host принял смену аккаунта; ожидается штатный выход и новый вход.' -and
 (Get-Rc1JournalUiText 'journal.ack.actionConfirmed' '').Replace('{action}','START') -ceq
 'Host подтвердил выполнение: START') 'new Host ACK events use Russian display strings without changing machine action'
Check ((Format-Rc1JournalLine 8 'Remote tool completed|8|start_process|PowerShell') -ceq
 '000008 │ ✅ Запрос запуска программы → PowerShell') 'Russian completed start_process still means request only'
$script:ownerDetailedJournal=$null
Add-Rc1OwnerDetailedEvent 'Remote' (Format-Rc1JournalLine 9 'Remote connected')
$oldLine=[string]$script:ownerDetailedJournal[0]
Check ($oldLine.Contains('UTC / получено] [Remote]') -and $oldLine.EndsWith('🔌 Remote → подключён')) 'new Russian detailed entry stamped once with received time'
$script:ownerUiTexts=$en
Check ((Get-Rc1JournalUiText 'journal.ack.switchAccountAccepted' '') -ceq
 'Host accepted the account switch; waiting for the normal sign-out and new sign-in.' -and
 (Get-Rc1JournalUiText 'journal.ack.actionConfirmed' '').Replace('{action}','START') -ceq
 'Host confirmed the action: START') 'new Host ACK events use English copy and preserve invariant action token'
Check ((Get-Rc1ToolAction 'read_file') -ceq 'Read file' -and
 (Get-Rc1ToolAction 'read_multiple_files') -ceq 'Read files' -and
 (Get-Rc1ToolAction 'start_process') -ceq 'Start program') 'tool action names are English display labels'
Check ((Format-Rc1JournalLine 101 'Remote tool started|7|read_file|report.txt') -ceq
 '000007 │ 🔧 Read file → report.txt' -and
 (Format-Rc1JournalLine 102 'Remote tool completed|7|read_file|report.txt') -ceq
 '000007 │ ✅ Read file → report.txt') 'same verified operation ID and target preserved across English phases'
Check ((Format-Rc1JournalLine 8 'Remote tool completed|8|start_process|PowerShell') -ceq
 '000008 │ ✅ Program launch request → PowerShell') 'English completion does not assert OS process finished'
Check ((Format-Rc1JournalLine 200 'Remote tool completed: read_file') -ceq
 '000200 │ ✅ Read file → unspecified') 'ambiguous completion remains explicitly uncorrelated'
Check ((Format-Rc1JournalLine 13 'Remote tool started|12|read_file|RAW:PRIVATE') -ceq
 '000013 │ • Tool event → unspecified') 'invalid rich subject is never disclosed in translated journal'
Check ((Format-Rc1JournalLine 5 'Remote tool started|15|start_process|') -ceq
 '000015 │ 🔧 Start program → unspecified') 'empty subject gets localized neutral label'
Check ((Format-Rc1JournalLine 12 'Remote tool started|12|read_multiple_files|one.md (первый)') -ceq
 '000012 │ 🔧 Read files → one.md (первый)') 'sanitized target/source label is not silently rewritten'
Check ((Format-Rc1JournalLine 15 'Remote connected') -ceq
 '000015 │ 🔌 Remote → connected' -and
 (Format-Rc1JournalLine 16 'Authentication pending') -ceq
 '000016 │ ⏳ Authentication → pending') 'connection and authorization are localized by fixed event markers'
Check ((Format-Rc1JournalLine 17 'Local MCP recovering') -ceq
 '000017 │ ⏳ MCP → recovering' -and
 (Format-Rc1JournalLine 18 'Remote channel unavailable') -ceq
 '000018 │ ❌ Remote channel → unavailable') 'MCP recovery and channel errors are localized'
Check ((Format-Rc1JournalLine 19 'AN_UNKNOWN_SAFE_EVENT') -ceq
 '000019 │ • Event → AN_UNKNOWN_SAFE_EVENT') 'unknown sanitized events retain identity and are not parsed as code'
Add-Rc1OwnerDetailedEvent 'Remote' (Format-Rc1JournalLine 20 'Remote connected')
Check ($script:ownerDetailedJournal.Count -eq 2 -and
 $script:ownerDetailedJournal[0] -ceq $oldLine -and
 ([string]$script:ownerDetailedJournal[1]).Contains('UTC / received] [Remote]')) 'language switch does not rewrite historical journal entries'
Add-Rc1OwnerDetailedEvent 'Unknown' 'FORGED'
Add-Rc1OwnerDetailedEvent 'Remote' 'password=SECRET'
Check ($script:ownerDetailedJournal.Count -eq 2) 'untrusted origin and credential-like records still blocked'
$banner="⌨ Press Ctrl+C to disconnect."
$converted=Convert-Rc1OwnerStartupInstructions $banner
Check ($converted -ceq '⏹ Click Stop to disconnect Remote.' -and
 $banner -ceq '⌨ Press Ctrl+C to disconnect.') 'English banner displays safe Owner instruction without altering provider marker'
$script:ownerUiTexts=$ru
Check ((Convert-Rc1OwnerStartupInstructions $banner) -ceq
 '⏹ Нажмите «Остановить», чтобы отключить Remote.') 'Russian banner now displays Russian GUI-only instruction'
$script:ownerUiTexts=$en
Check ([RdcUiLanguage]::GuiNotice('window not ready','FALLBACK',$en) -ceq
 'The RDC Relay window has not appeared yet. Try opening it again from the tray; Remote was not affected.') 'allowlisted GUI startup warning localized in English'
Check ([RdcUiLanguage]::GuiNotice('open denied: unverified','FALLBACK',$en) -ceq
 'Could not verify the RDC Relay window. Remote keeps running; check the journal.' -and
 [RdcUiLanguage]::GuiNotice('open denied: unverified window','FALLBACK',$en) -ceq
 'Cannot confirm the RDC Relay window. Remote was not affected.') 'ownership denial messages distinguished without relaxing ownership'
Check ([RdcUiLanguage]::GuiNotice('GUI launch failed: IOException','FALLBACK',$en) -ceq
 'RDC Relay could not open its window. Remote was not affected; check the Host journal.' -and
 [RdcUiLanguage]::GuiNotice('open failed: ArgumentException','FALLBACK',$en) -ceq
 'Could not display the RDC Relay window. Remote keeps running.') 'coded GUI launch failures are localized without copying exception payload'
Check ([RdcUiLanguage]::GuiNotice('an unknown IPC event','RU fallback',$en) -ceq
 'RU fallback' -and [RdcUiLanguage]::GuiNotice('window not ready','RU fallback',$null) -ceq
 'RU fallback') 'unexpected codes and missing catalog are fail-closed Russian'
$guiSource=[IO.File]::ReadAllText((Join-Path $source 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
Check ($guiSource.Contains("Get-Rc1JournalUiText 'journal.ack.switchAccountAccepted'") -and
 $guiSource.Contains("Get-Rc1JournalUiText 'journal.ack.actionConfirmed'") -and
 $guiSource.Contains('Add-CompletedEvent ($ackMessage.Replace(')) 'both production ACK routes now use display-only translation'
$hostSource=[IO.File]::ReadAllText((Join-Path $source 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
Check ($hostSource.Contains('Append("gui",code);') -and
 $hostSource.Contains('RdcUiLanguage.GuiNotice(code,message,') -and
 $hostSource.Contains('tray.ShowBalloonTip(3000);') -and
 $hostSource.Contains('if((now-lastGuiNoticeUtc).TotalSeconds<8)return;')) 'source preserves notification rate gate, diagnostics and duration'
$errors=$null;$tokens=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'rc1-owner-gui.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'journal source parses in Windows PowerShell 5.1'
Write-Output ('RC1_OWNER_JOURNAL_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
