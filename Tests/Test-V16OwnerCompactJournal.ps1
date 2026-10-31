# Read-only compact owner journal regression. Never launches Host/GUI/Remote.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$owner=Join-Path $root 'Source\rc1-owner-gui.ps1'
$window=Join-Path $root 'Source\remote-window.ps1'
. $owner
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$cases=@(
 @{Number=1;Marker='Remote tool started: read_file';Icon='🔧';Text='Начато: read_file'},
 @{Number=2;Marker='Remote tool completed';Icon='✅';Text='Выполнено'},
 @{Number=3;Marker='Remote tool failed';Icon='❌';Text='Ошибка выполнения'},
 @{Number=4;Marker='Remote connected';Icon='🔌';Text='Remote подключён'},
 @{Number=5;Marker='Local MCP recovering';Icon='⏳';Text='Восстановление MCP'},
 @{Number=6;Marker='RC1: безопасное состояние Host';Icon='•';Text='RC1: безопасное состояние Host'}
)
$rows=@()
foreach($x in $cases){
 $line=[string](Format-Rc1JournalLine ([long]$x.Number) ([string]$x.Marker))
 $rows+= $line
 Check ($line -cmatch '^\d{6} │ ' -and $line.StartsWith(('{0:D6} │ ' -f [int]$x.Number)) -and
  $line.Contains($x.Icon) -and $line.EndsWith($x.Text)) ('aligned concise Unicode entry '+$x.Number)
}
Check ((@($rows|ForEach-Object{$_.IndexOf('│')}|Select-Object -Unique).Count -eq 1) -and
 ($rows[0].IndexOf('│') -eq 7)) 'all bars occupy the same monospace column'
Check ((Format-Rc1JournalLine 999999 'Remote tool completed').StartsWith('999999 │ ')) 'six-digit gutter does not wrap at boundary'
Check ((Format-Rc1JournalLine 1 'Remote tool started: read_file').IndexOf('Host Remote') -lt 0) 'Host Remote tag omitted'
$source=[IO.File]::ReadAllText($owner,[Text.Encoding]::UTF8)
$renderer=[IO.File]::ReadAllText($window,[Text.Encoding]::UTF8)
$pairedStart=Format-Rc1JournalLine 101 'Remote tool started|7|read_file|report.txt'
$pairedDone=Format-Rc1JournalLine 102 'Remote tool completed|7|read_file|report.txt'
Check ($pairedStart -ceq '000007 │ 🔧 Чтение файла — report.txt' -and
 $pairedDone -ceq '000007 │ ✅ Файл прочитан — report.txt') 'started and completed file events share a visible operation number'
Check ((Format-Rc1JournalLine 103 'Remote tool started|8|start_process|PowerShell') -ceq
 '000008 │ 🔧 Запуск программы — PowerShell') 'program shown without raw command arguments'
Check ((Format-Rc1JournalLine 104 'Remote tool completed|8|start_process|PowerShell') -ceq
 '000008 │ ✅ Запрос запуска обработан — PowerShell') 'tool completion does not falsely claim OS process exit'
Check ((Format-Rc1JournalLine 200 'Remote tool completed: read_file') -ceq
 '000200 │ ✅ Завершено: чтение файла') 'ambiguous parallel completion has readable type without false correlation'
Check ((Format-Rc1JournalLine 201 'Remote tool started|7|read_file|RAW:PRIVATE') -ceq
 '000201 │ • Событие инструмента') 'malformed rich marker does not leak raw payload'
Check ((Format-Rc1JournalLine 105 'Remote tool failed|9|write_file|notes.txt') -ceq
 '000009 │ ❌ Ошибка: Запись файла — notes.txt') 'failure retains matching operation and filename'
Check ($renderer.Contains("Color-LogRegex "+'$log'+" '^\d{6,18}\s+(│)' ([Drawing.Color]::Gainsboro)")) 'vertical gutter is neutral light gray, not purple'
Check ($renderer.Contains("Color-LogRegex "+'$log'+" '^(\d{6,18})\s+│' "+'$log.ForeColor'+" -1 1") -and
 -not $renderer.Contains("Color-LogRegex "+'$log'+" '^(\d{6,18})\s+│' "+'$headerValue'+" -1 1")) 'event sequence digits use same normal foreground as ordinary journal text'
Check ($source.Contains('Format-Rc1JournalLine $lineCursor') -and
 $source.Contains('Format-Rc1JournalLine ([long]$ev.sequence)')) 'snapshot and Host events use the same renderer'
Check ($source.Contains('$script:ownerCompactJournal=$true') -and
 $renderer.Contains('if($script:ownerCompactJournal){$nl}else{$nl+$nl}')) 'RC1 uses single lines, stable retains two-line spacing'
Check ($renderer.Contains('if($script:ownerCompactJournal -and $display.Length -gt 0){$display=$nl+$display}')) 'owner journal inserts exactly one initial blank line per render'
Check ($renderer.Contains('$log.SetBounds(0,0,$contentW,$contentH)') -and
 $renderer.Contains('$vScroll.SetBounds($contentW,0,17,$contentH)') -and
 $renderer.Contains('$hScroll.SetBounds(0,$contentH,$contentW,17)')) 'log and both overlay scrollbars retain original geometry'
Check (-not $renderer.Contains('$journalTopInset') -and
 -not $renderer.Contains('$journalViewportH')) 'no control offsets or viewport resizing introduced'
Check ($renderer.Contains('$log.ApplyCompactLineSpacing()') -and
 $renderer.Contains("Color-LogRegex "+'$log')) 'RichEdit tight paragraph and colored gutter preserved'
$errors=$null;$tokens=$null
[void][Management.Automation.Language.Parser]::ParseFile($owner,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'owner GUI syntax parses in Windows PowerShell'
$errors=$null;$tokens=$null
[void][Management.Automation.Language.Parser]::ParseFile($window,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'shared original renderer syntax parses'
Write-Output ('RC1_COMPACT_JOURNAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
