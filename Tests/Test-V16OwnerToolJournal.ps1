# Host-only bounded safe tool journal: pairing, arguments minimization and activity.
# No installed Host, GUI, IPC pipe, account or Remote is opened.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerRuntime.cs')|ForEach-Object{Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$j=New-Object RdcOwnerToolJournal
$a=$j.Format('🔧 Received tool call alpha: read_file {"path":"C:\\Work\\report.txt","ignored":"SENSITIVE"}','Remote tool started: read_file')
Check ($a -ceq 'Remote tool started|1|read_file|report.txt') 'started read_file exposes basename and local operation number'
Check ($a -notmatch 'Work|alpha|SENSITIVE|C:') 'raw ID, path and secret arguments do not cross boundary'
$b=$j.Format('🔧 Received tool call beta: start_process {"command":"powershell.exe -NoProfile -Command PRIVATE"}','Remote tool started: start_process')
Check ($b -ceq 'Remote tool started|2|start_process|PowerShell') 'known program presented without command arguments'
Check ($j.Format('🔧 Received tool call beta: start_process {}','Remote tool started: start_process') -ceq '') 'duplicate tool start is ignored'
$endB=$j.Format('✅ Tool call beta completed:','Remote tool completed')
Check ($endB -ceq 'Remote tool completed|2|start_process|PowerShell') 'out-of-order completion retains original call number'
$endA=$j.Format('✅ Tool call alpha completed:','Remote tool completed')
Check ($endA -ceq 'Remote tool completed|1|read_file|report.txt') 'file completion linked to original start'
$j.Reset()
$once=$j.Format('🔧 Received tool call uuid-a: read_file {"path":"C:\\Work\\status.md"}','Remote tool started: read_file')
$methodResult=$j.Format('✅ Tool call read_file completed:','Remote tool completed')
Check ($once -ceq 'Remote tool started|1|read_file|status.md' -and
 $methodResult -ceq 'Remote tool completed|1|read_file|status.md') 'real pinned Remote method-name completion pairs with sole matching call'
$j.Reset()
[void]$j.Format('🔧 Received tool call id-1: read_file {"path":"C:\\Work\\one.md"}','Remote tool started: read_file')
[void]$j.Format('🔧 Received tool call id-2: read_file {"path":"C:\\Work\\two.md"}','Remote tool started: read_file')
$uncertain1=$j.Format('✅ Tool call read_file completed:','Remote tool completed')
$uncertain2=$j.Format('✅ Tool call read_file completed:','Remote tool completed')
Check ($uncertain1 -ceq 'Remote tool completed: read_file' -and
 $uncertain2 -ceq 'Remote tool completed: read_file') 'concurrent same-tool completions never invent a call-ID match'
$j.Reset()
[void]$j.Format('🔧 Received tool call aa: read_file {"path":"C:\\Work\\a.md"}','Remote tool started: read_file')
[void]$j.Format('🔧 Received tool call bb: start_process {"command":"git status"}','Remote tool started: start_process')
Check ($j.Format('✅ Tool call start_process completed:','Remote tool completed') -ceq
 'Remote tool completed|2|start_process|Git' -and
 $j.Format('✅ Tool call read_file completed:','Remote tool completed') -ceq
 'Remote tool completed|1|read_file|a.md') 'different concurrently-running tools correlate independently'

Check ($j.Format('✅ Tool call unknown completed:','Remote tool completed') -ceq 'Remote tool completed') 'unmatched completion falls back without invented target'
$c=$j.Format('🔧 Received tool call gamma: read_file {"path":"C:\\Work\\token_secret.env"}','Remote tool started: read_file')
Check ($c -ceq 'Remote tool started|3|read_file|') 'sensitive filename is not displayed'
$failLine=$j.Format('❌ Tool call gamma failed: FORBIDDEN','Remote tool failed')
Check ($failLine -ceq 'Remote tool failed|3|read_file|') 'failed operation linked without raw error payload'
$j.Reset()
Check ($j.Format('🔧 Received tool call delta: edit_block {"file_path":"D:\\Src\\main.cpp"}','Remote tool started: edit_block') -ceq 'Remote tool started|1|edit_block|main.cpp') 'new session resets operation sequence'
$o=New-Object RdcOwnerRemoteState
$o.AttachObservedReadOnly(24680)
$o.AddObservedMarker('Remote tool started|1|read_file|report.txt')
$o.AddObservedMarker('Remote tool started|2|start_process|PowerShell')
$o.AddObservedMarker('Remote tool completed|2|start_process|PowerShell')
Check (($o.Snapshot()).toolActivity -ceq 'working' -and -not ($o.Snapshot()).canStop) 'parallel calls keep animation and observer remains read-only'
$o.AddObservedMarker('Remote tool completed|1|read_file|report.txt')
Check (($o.Snapshot()).toolActivity -ceq 'hold') 'all calls finished then activity hold'
$o.AddObservedMarker('Remote tool completed: read_file')
Check (@(($o.Snapshot()).tail)[-1] -match 'Remote tool completed: read_file' -and
 -not ($o.Snapshot()).canStop) 'read-only observer permits sanitized unpaired completion without stop authority'
$denied=$false
try{$o.AddObservedMarker('Remote tool started|3|read_file|PRIVATE:SECRET')}catch{$denied=$true}
Check $denied 'observer state refuses untrusted raw target'
$runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
$observer=[IO.File]::ReadAllText((Join-Path $src 'rc1-remote-observer.ps1'),[Text.Encoding]::UTF8)
Check ($runtime.Contains('marker=toolJournal.Format(cleanLine,marker)') -and
 -not $runtime.Contains('if(emitted++<24)') -and
 -not $runtime.Contains('if(i<start)continue')) 'owned Host does not drop markers in a bounded chunk'
Check ($observer.Contains('ObservedToolLine') -and -not $observer.Contains('if($emitted -lt 24)') -and
 -not $observer.Contains('if($lines.Count -gt 160)')) 'read-only observer does not drop pair markers in a bounded chunk'
Write-Output ('RC1_OWNER_TOOL_JOURNAL_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
