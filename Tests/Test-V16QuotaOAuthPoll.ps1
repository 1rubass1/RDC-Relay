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
foreach($method in @('Parse-Quota','Parse-McpResponse','Get-ClientAuth','Add-ClientAuth','Write-PrivateFile','Save-Credentials','Read-Credentials','Store-Session')){
 $n=$ast.Find({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq $method},$true)
 Check ($null -ne $n) ('pure parser '+$method)
 if($n){. ([scriptblock]::Create($n.Extent.Text))}
}
# The live hosted DCR service returns client_secret_post even when
# token_endpoint_auth_method=none was requested. Verify both token paths.
$registration=[pscustomobject]@{token_endpoint_auth_method='client_secret_post';client_secret=('Y'*40)}
$auth=Get-ClientAuth $registration
Check ($auth.Method -ceq 'client_secret_post' -and $auth.Secret.Length -eq 40) 'DCR response client_secret_post recognized'
$exchange=Add-ClientAuth @{client_id='example';grant_type='authorization_code'} $auth.Method $auth.Secret
Check ($exchange.ContainsKey('client_secret') -and $exchange.client_secret -ceq $auth.Secret) 'token code exchange includes confidential client_secret'
$refresh=Add-ClientAuth @{client_id='example';grant_type='refresh_token'} $auth.Method $auth.Secret
Check ($refresh.ContainsKey('client_secret') -and $refresh.client_secret -ceq $auth.Secret) 'token refresh includes confidential client_secret'
$public=Get-ClientAuth ([pscustomobject]@{token_endpoint_auth_method='none';client_secret='ignore'})
$publicBody=Add-ClientAuth @{client_id='public';grant_type='authorization_code'} $public.Method $public.Secret
Check (-not $publicBody.ContainsKey('client_secret')) 'genuinely public registration does not send client_secret'
$rejected=$false
try{[void](Get-ClientAuth ([pscustomobject]@{token_endpoint_auth_method='client_secret_post';client_secret=''}))}catch{$rejected=$true}
Check $rejected 'confidential DCR without a secret is refused'
$unsupported=$false
try{[void](Get-ClientAuth ([pscustomobject]@{token_endpoint_auth_method='client_secret_basic';client_secret=('Y'*40)}))}catch{$unsupported=$true}
Check $unsupported 'unsupported client auth method refused'
# Use a disposable synthetic vault; never touch real OAuth credentials.
Add-Type -AssemblyName System.Security
$state=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaUnit-'+[Guid]::NewGuid().ToString('N'))
$vault=Join-Path $state 'synthetic-secret.dpapi'
try{
 $testSecret='only-synthetic-demo-secret-eu-12345'
 $tok=[pscustomobject]@{access_token='dummy-test-access';refresh_token='dummy-test-refresh';expires_in=3600}
 $saved=Store-Session 'test-client' $tok 'client_secret_post' $testSecret
 Check ((Test-Path -LiteralPath $vault -PathType Leaf) -and
     $saved.tokenAuthMethod -ceq 'client_secret_post') 'credential vault written via current-user DPAPI'
 $encrypted=[IO.File]::ReadAllBytes($vault)
 Check (-not ([Text.Encoding]::UTF8.GetString($encrypted).Contains($testSecret))) 'client secret not present in plaintext vault bytes'
 $loaded=Read-Credentials
 Check ($loaded.clientSecret -ceq $testSecret -and
     $loaded.tokenAuthMethod -ceq 'client_secret_post' -and
     $loaded.refreshToken -ceq 'dummy-test-refresh') 'encrypted secret and refresh token roundtrip safely'
 # Repeat with an existing destination. This exercises .NET Framework File.Replace
 # which rejects a null backup path on Windows and previously broke live quota.
 $replacement=[pscustomobject]@{
  access_token='dummy-test-access-new';refresh_token='dummy-test-refresh-new';expires_in=3300
 }
 [void](Store-Session 'test-client' $replacement 'client_secret_post' $testSecret)
 $reloaded=Read-Credentials
 Check ($reloaded.refreshToken -ceq 'dummy-test-refresh-new') 'existing encrypted credential vault replaces atomically on Windows'
 Check (@([IO.Directory]::GetFiles($state,'quota-*.bak')).Count -eq 0 -and
        @([IO.Directory]::GetFiles($state,'quota-*.tmp')).Count -eq 0) 'atomic credential replacement cleans temporary backup'
 $statusPath=Join-Path $state 'synthetic-status.json'
 [void](Write-PrivateFile $statusPath ([Text.Encoding]::UTF8.GetBytes('{"result":"starting"}')))
 [void](Write-PrivateFile $statusPath ([Text.Encoding]::UTF8.GetBytes('{"result":"finished"}')))
 Check ([IO.File]::ReadAllText($statusPath) -ceq '{"result":"finished"}') 'existing quota status can be replaced after authorization'
 Check (@([IO.Directory]::GetFiles($state,'quota-*.bak')).Count -eq 0) 'status replacement also removes backup'
 [IO.File]::Delete($statusPath)
}finally{
 if([IO.File]::Exists($vault)){[IO.File]::Delete($vault)}
 if([IO.Directory]::Exists($state)){[IO.Directory]::Delete($state,$false)}
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
Check ($hostCode.Contains('$quotaNextPollUtc=[DateTime]::UtcNow.AddMinutes(30)') -and
 $hostCode.Contains('$quotaTimer.Interval=15000') -and
 $hostCode.Contains('quotaPollProcess=Start-Process') -and
 $hostCode.Contains('if($Full -and -not $TrialRoot)')) 'Host schedules quota at 30min after verified managed account appears'
$runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
Check ($runtime.Contains('public string ActiveManagedAccount') -and
 $runtime.Contains('managedState!="Ready"') -and
 $runtime.Contains('!managedProcess.Running') -and
 $hostCode.Contains('$activeAccount=[string]$owner.ActiveManagedAccount')) 'automatic quota browser launch gated by actual ready Host-owned identity'
Check ($hostCode.Contains("$"+'mode='+"'-Authorize'") -and
 $hostCode.Contains("$"+'quotaAutoTried.ContainsKey') -and
 $hostCode.Contains("$"+'quotaData.source -cne '+"'official-remote-who-am-i'") -and
 $hostCode.Contains('[StringComparison]::OrdinalIgnoreCase')) 'mismatch triggers one automatic browser attempt without repeated prompts'
Check (-not $hostCode.Contains("'remote --logout'") -and
 -not $hostCode.Contains('StopManagedRemote(')) 'automatic quota never logs out or controls Remote'
Check ($window.Contains('rc1-quota-client.ps1') -and $window.Contains("'-Authorize'") -and $gui.Contains('$quotaAuthItem.Enabled=$script:ownerRealMode')) 'manual Account-menu OAuth fallback remains available'
Check ($gui.Contains('Остаток вызовов: 0%') -and $gui.Contains('[Drawing.Color]::LightCoral')) '0% rendered red'
Write-Output ('RC1_QUOTA_OAUTH_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
