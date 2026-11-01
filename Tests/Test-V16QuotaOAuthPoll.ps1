# Synthetic OAuth quota parsing and static boundary contract (no network/login).
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
$client=Join-Path $src 'rc1-quota-client.ps1'
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){if($ok){$script:pass++;Write-Output ('PASS '+$name)}else{$script:fail++;Write-Output ('FAIL '+$name)}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($client,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'OAuth script parses on PowerShell 5.1'
if($errors.Count){exit 1}
foreach($method in @('Parse-Quota','Parse-McpResponse')){
 $n=$ast.Find({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq $method},$true)
 Check ($null -ne $n) ('pure parser '+$method)
 if($n){. ([scriptblock]::Create($n.Extent.Text))}
}
$raw=@{jsonrpc='2.0';id=2;result=@{content=@(@{type='text';text='{"email":"test@example.org","remote_calls_left_pct":0}'})}}|ConvertTo-Json -Depth 8 -Compress
$zero=Parse-Quota ($raw|ConvertFrom-Json)
Check ($zero.Percent -eq 0 -and $zero.Email -ceq 'test@example.org') 'official 0% remains 0%'
$ok=@{result=@{structuredContent=@{email='test@example.org';remote_calls_left_pct=78}}}
Check ((Parse-Quota $ok).Percent -eq 78) 'structured 78% response'
$invalid=$false
try{[void](Parse-Quota @{result=@{structuredContent=@{email='test@example.org';remote_calls_left_pct=101}}})}catch{$invalid=$true}
Check $invalid 'out-of-range percent rejected'
$unrelated=$false
try{[void](Parse-Quota @{error=@{code=-32000;message='other failure'}})}catch{$unrelated=$true}
Check $unrelated 'unrelated error is not interpreted as zero'
Check ((Parse-McpResponse ('data: '+$raw)).id -eq 2) 'MCP SSE response parse'
$code=[IO.File]::ReadAllText($client,[Text.Encoding]::UTF8)
$hostCode=[IO.File]::ReadAllText((Join-Path $src 'rc1-tray-host.ps1'),[Text.Encoding]::UTF8)
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
$window=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'),[Text.Encoding]::UTF8)
Check ($code.Contains("scope='mcp:tools'") -and $code.Contains("code_challenge_method='S256'") -and $code.Contains('GetContextAsync()') -and $code.Contains('state=$nonce')) 'PKCE and state checked on localhost callback'
Check ($code.Contains('[Security.Cryptography.ProtectedData]::Protect') -and $code.Contains('[Security.Cryptography.DataProtectionScope]::CurrentUser')) 'tokens encrypted with user-scoped DPAPI'
Check ($code.Contains("method='tools/call'") -and $code.Contains("name='who_am_i'") -and -not $code.Contains('Get-Content -LiteralPath $env:USERPROFILE')) 'only who_am_i and no device credentials'
Check ($code.Contains('Validate-OfficialEndpoint') -and $code.Contains('mcp.desktopcommander.app')) 'fixed official endpoints enforced'
Check ($hostCode.Contains('$quotaNextPollUtc=[DateTime]::UtcNow.AddHours(1)') -and $hostCode.Contains('quotaPollProcess=Start-Process') -and $hostCode.Contains('if($Full -and -not $TrialRoot)')) 'Host polls on startup then every hour, full mode only'
Check ($window.Contains('rc1-quota-client.ps1') -and $window.Contains("'-Authorize'") -and $gui.Contains('$quotaAuthItem.Enabled=$script:ownerRealMode')) 'browser OAuth requires explicit Account menu action'
Check ($gui.Contains('Остаток вызовов 0%') -and $gui.Contains('[Drawing.Color]::LightCoral')) '0% rendered red'
Write-Output ('RC1_QUOTA_OAUTH_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
