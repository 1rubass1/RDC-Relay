# Full pinned Remote 0.2.52 startup header / 1.5.18 color renderer contract.
# No real Remote, Host, or GUI is started. Private test data are synthetic.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$files=@('RdcOwnerWire.cs','RdcOwnerProcess.cs','RdcOwnerTicketStore.cs','RdcOwnerRemoteState.cs','RdcOwnerManagedProcess.cs','RdcOwnerRuntime.cs')|ForEach-Object{Join-Path $src $_}
Add-Type -Path $files -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll','System.dll')
$parser=([RdcOwnerRuntime]).GetMethod('TrySafeStartupLine',[Reflection.BindingFlags]'Static,NonPublic')
$gui=Get-Content (Join-Path $src 'rc1-owner-gui.ps1') -Raw -Encoding UTF8
$old=Get-Content (Join-Path $env:LOCALAPPDATA 'RemoteDesktopCommanderLauncher\remote-window.ps1') -Raw -Encoding UTF8
$new=Get-Content (Join-Path $src 'remote-window.ps1') -Raw -Encoding UTF8
$runtime=Get-Content (Join-Path $src 'RdcOwnerRuntime.cs') -Raw -Encoding UTF8
$pass=0;$fail=0
function Check([bool]$ok,[string]$title){
 if($ok){$script:pass++;Write-Output ('PASS '+$title)}else{$script:fail++;Write-Output ('FAIL '+$title)}
}
function SafeLine([string]$line,[bool]$allowed,[string]$suffix){
 $args=[object[]]@($line,'')
 $ok=[bool]$parser.Invoke($null,$args)
 Check ($ok -eq $allowed -and (-not $allowed -or [string]$args[1] -match [regex]::Escape($suffix))) ('header '+$(if($allowed){'kept '}else{'excluded '})+$suffix)
}
Check ($null -ne $parser) 'static source header allowlist exists'
if($parser){
 SafeLine '██████████╗' $true '████'
 SafeLine '🔌 Remote Connection' $true 'Remote Connection'
 SafeLine '🔧 Starting MCP Device...' $true 'Starting MCP Device'
 SafeLine '  - 🔌 Connected to Remote MCP' $true 'Connected to Remote MCP'
 SafeLine '✅ Device ready:' $true 'Device ready:'
 SafeLine '    - User: tester@example.org' $true 'User: tester@example.org'
 SafeLine '    - Device ID: 12345678-1234-1234-1234-123456789abc' $true 'Device ID:'
 SafeLine '    - Device Name: STARMER (Work)' $true 'Device Name:'
 SafeLine '    Device: STARMER' $true 'Device:'
 SafeLine '    Status: Online' $true 'Status: Online'
 SafeLine '🚀 Next' $true 'Next'
 SafeLine '➡ Return to ChatGPT or Claude and continue your conversation.' $true 'Return to ChatGPT'
 SafeLine '💻 Keep this Terminal running. You can minimize it.' $true 'Keep this Terminal'
 SafeLine '⌨ Press Ctrl+C to disconnect.' $true 'Press Ctrl+C'
 SafeLine '🔧 Commands' $true 'Commands'
 SafeLine '  Help:    npx @wonderwhy-er/desktop-commander@latest remote --help' $true 'remote --help'
 SafeLine '  Log out: npx @wonderwhy-er/desktop-commander@latest remote --logout' $true 'remote --logout'
 SafeLine '🔧 Run these in a new Terminal, or after disconnecting.' $true 'Run these'
 SafeLine ' - Connecting to Local Desktop Commander MCP using: C:\Private\tool.exe --api-token=hidden' $true 'Connecting to Local Desktop Commander MCP using'
 SafeLine '🔌 Connecting to Remote MCP https://private.invalid/token' $true 'Connecting to Remote MCP'
 SafeLine '⚠ Channel error: credential=example' $false 'Channel error'
 SafeLine 'Received tool call 12345678-1234-1234-1234-123456789abc: start_process {"command":"secret"}' $false 'Received tool call'
 SafeLine '   Help: npx evil-package remote --help' $false 'evil-package'
 SafeLine '  - User: leaked-token' $false 'leaked-token'
 SafeLine '  - Device Name: [bad-control]' $false 'bad-control'
 SafeLine 'secret: nobody-should-see-this' $false 'secret'
}
# Regression: verification can emit dozens of empty/whitespace progress rows.
# Preserve exactly one separator while retaining all subsequent useful text.
$keepBlank=([RdcOwnerRuntime]).GetMethod('ShouldKeepStartupLine',[Reflection.BindingFlags]'Static,NonPublic')
Check ($null -ne $keepBlank) 'Startup whitespace compaction guard exists'
if($keepBlank){
 $rows=New-Object 'System.Collections.Generic.List[string]'
 foreach($v in @('██████████╗','Remote Connection','','Found persisted session for device 12345678-1234-1234-1234-123456789abc')){
  [void]$rows.Add($v)
 }
 $skipped=0
 for($i=0;$i -lt 120;$i++){
  $v=if(($i%2) -eq 0){''}else{'          '}
  $invokeArgs=New-Object object[] 2
  $invokeArgs[0]=$rows.psobject.BaseObject
  $invokeArgs[1]=$v
  if([bool]$keepBlank.Invoke($null,$invokeArgs)){
   [void]$rows.Add($(if([string]::IsNullOrWhiteSpace($v)){''}else{$v}))
  }else{$skipped++}
 }
 foreach($v in @('Channel subscribed','Device ready:','Next','Commands')){
  $invokeArgs=New-Object object[] 2
  $invokeArgs[0]=$rows.psobject.BaseObject
  $invokeArgs[1]=$v
  if([bool]$keepBlank.Invoke($null,$invokeArgs)){[void]$rows.Add($v)}
 }
 $combined=[string]::Join("`n",$rows.ToArray())
 Check ($skipped -eq 119 -and $rows.Count -eq 9) '120 empty verification progress rows become one visible separator'
 Check ($combined.Contains('Channel subscribed') -and $combined.Contains('Device ready:') -and
  $combined.EndsWith("Next`nCommands")) 'Verification compaction preserves later startup instructions'
 Check ($combined.StartsWith('██████████╗') -and $combined.Contains('Remote Connection')) 'Header artwork and content remain intact'
}
Check ($runtime.Contains('if(!ShouldKeepStartupLine(managedStartupHeader,line))return;') -and
 $runtime.Contains('managedStartupScanned++;')) 'Skipped duplicate empty rows do not consume the capture budget'
Check ($runtime.Contains('AcceptManagedStartupLine(cleanLine)')) 'Host captures complete intro only from owned managed log'
Check ($runtime.Contains('managedStartupComplete=true;return;')) 'Host ends capture at tool call boundary'
Check ($runtime.Contains('"remoteStartupHeader",managedMode?')) 'Only managed Host publishes header via authenticated IPC'
Check ($gui.Contains('$safeOriginalHeader=$candidateHeader.TrimEnd()')) 'GUI consumes original filtered intro'
Check ($gui.Contains('$script:startupBlock=$safeOriginalHeader')) 'GUI puts original header in existing renderer'
Check ($new.Contains('StyleStartupBanner(') -and $new.Contains('Color-HeaderSemantics $headerLog')) 'Original rich-color renderer remains enabled'
# Ensure the specific original classic style pipeline has not been replaced.
Check ($old.Contains('function Color-HeaderSemantics') -and $new.Contains('function Color-HeaderSemantics')) 'Full 1.5.18 header coloring function available'
$pattern='(?s)(function Color-HeaderSemantics.*?)(?=function Render-CompactLog)'
$oldColors=([regex]::Match($old,$pattern).Groups[1].Value -replace "`r`n","`n").Trim()
$newColors=([regex]::Match($new,$pattern).Groups[1].Value -replace "`r`n","`n").Trim()
Check ($oldColors.Length -gt 300 -and $newColors -ceq $oldColors) 'Original 1.5.18 semantic coloring rules identical'
Write-Output ('FULL_ORIGINAL_HEADER_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
