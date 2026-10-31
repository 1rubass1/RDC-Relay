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
Check ($source.Contains('Format-Rc1JournalLine $lineCursor') -and
 $source.Contains('Format-Rc1JournalLine ([long]$ev.sequence)')) 'snapshot and Host events use the same renderer'
Check ($source.Contains('$script:ownerCompactJournal=$true') -and
 $renderer.Contains('if($script:ownerCompactJournal){$nl}else{$nl+$nl}')) 'RC1 uses single lines, stable retains two-line spacing'
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
