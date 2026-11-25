# RC1 optional OAuth client for read-only Remote MCP usage percentage.
# Never touches the device-agent's device.json or starts/controls Remote.
# Authorization starts from the explicit Account menu or after the Host
# confirms a newly connected managed Remote account. Browser/provider may
# still require user consent; the device-agent's credentials are never read.
param([switch]$Authorize,[switch]$Poll)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security,System.Web
if(([int][bool]$Authorize+[int][bool]$Poll) -ne 1){throw 'RC1_QUOTA_SELECT_ONE_MODE'}
$service='https://mcp.desktopcommander.app'
$endpoint=$service+'/mcp'
$state=Join-Path $env:LOCALAPPDATA 'RDCRelayOwnerPilot'
$vault=Join-Path $state 'quota-oauth-user.dpapi'
$cache=Join-Path $state 'remote-usage-cache.json'
$statusFile=Join-Path $state 'remote-usage-status.json'
$quotaDisplayPath=Join-Path $state 'quota-display.opt-in'
function Test-Rc1QuotaDisplayEnabled([string]$path) {
 try {
  if([string]::IsNullOrWhiteSpace($path)){return $false}
  # No preference is the historical behavior: quota display and refresh ON.
  if(-not [IO.File]::Exists($path)){return $true}
  $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if(($file.Length -ne 10 -and $file.Length -ne 11) -or
     ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
  # 'enabled-v1' is accepted for migration from the uninstalled G101 trial.
  # Explicit 'disabled-v1', malformed files and IO errors fail closed.
  return [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq 'enabled-v1'
 }catch{return $false}
}
$script:quotaStage='startup'
function Save-QuotaStatus([string]$result,[int]$httpStatus=0){
 # Diagnostic fields are fixed categories only; never record OAuth code,
 # client ID, secret, access/refresh token, URL or server response body.
 $stage=[string]$script:quotaStage
 if($stage -cnotin @('startup','registration','browser','callback','token',
     'vault','mcp','tool','cache','finished')){$stage='unknown'}
 $public=[ordered]@{
  result=$result;stage=$stage
  httpStatus=$httpStatus
  observedAtUtc=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
 }|ConvertTo-Json -Compress
 try{Write-PrivateFile $statusFile ([Text.Encoding]::UTF8.GetBytes($public))}catch{}
}
function Stop-Quota([string]$reason) {
 Save-QuotaStatus $reason
 # Never write arbitrary server replies, OAuth credentials, or exception text.
 Write-Output ('RC1_QUOTA_'+$reason)
 exit 0
}
function To-B64Url([byte[]]$bytes) {
 return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
function New-RandomToken([int]$size) {
 $bytes=New-Object byte[] $size
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try {$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 return To-B64Url $bytes
}
function Validate-OfficialEndpoint([string]$url) {
 try {
  $u=[Uri]$url
  if($u.Scheme -ne 'https' -or $u.Host -cne 'mcp.desktopcommander.app' -or
      $u.Port -ne 443 -or $u.UserInfo -or $u.Fragment){throw 'BOUNDARY'}
  return $url
 }catch{throw 'RC1_QUOTA_OFFICIAL_ENDPOINT_ONLY'}
}
function Read-OAuthMetadata {
 $m=Invoke-RestMethod -Uri ($service+'/.well-known/oauth-authorization-server') -TimeoutSec 12 -MaximumRedirection 0
 foreach($key in @('issuer','authorization_endpoint','token_endpoint','registration_endpoint')) {
  [void](Validate-OfficialEndpoint ([string]$m.$key))
 }
 if($m.issuer -cne $service -or @($m.code_challenge_methods_supported) -cnotcontains 'S256'){
  throw 'RC1_QUOTA_OAUTH_METADATA_UNSUPPORTED'
 }
 return $m
}
function Write-PrivateFile([string]$target,[byte[]]$bytes){
 if(-not [IO.Directory]::Exists($state)){[IO.Directory]::CreateDirectory($state)|Out-Null}
 $staging=Join-Path $state ('quota-'+[Guid]::NewGuid().ToString('N')+'.tmp')
 $backup=Join-Path $state ('quota-'+[Guid]::NewGuid().ToString('N')+'.bak')
 try {
  [IO.File]::WriteAllBytes($staging,$bytes)
  if([IO.File]::Exists($target)){
   # .NET Framework on STARMER rejects a null replacement backup name.
   # Use a unique same-directory backup, then remove it after atomic replace.
   [IO.File]::Replace($staging,$target,$backup)
  }else{[IO.File]::Move($staging,$target)}
 }finally{
  if([IO.File]::Exists($staging)){[IO.File]::Delete($staging)}
  if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
 }
}
function Save-Credentials($obj){
 $json=$obj|ConvertTo-Json -Compress -Depth 5
 $plain=[Text.Encoding]::UTF8.GetBytes($json)
 try{
  $protected=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  Write-PrivateFile $vault $protected
 }finally{[Array]::Clear($plain,0,$plain.Length)}
}
function Read-Credentials {
 if(-not [IO.File]::Exists($vault)){return $null}
 $file=Get-Item -LiteralPath $vault
 if($file.Length -lt 40 -or $file.Length -gt 16384){throw 'RC1_QUOTA_VAULT_SIZE'}
 $enc=[IO.File]::ReadAllBytes($vault)
 $bytes=[Security.Cryptography.ProtectedData]::Unprotect($enc,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 try{
  $item=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
  if([string]$item.clientId -notmatch '^[A-Za-z0-9._-]{1,220}$' -or
     [string]$item.refreshToken -notmatch '^[\x21-\x7E]{16,3000}$' -or
     [string]$item.tokenAuthMethod -cnotin @('none','client_secret_post') -or
     ([string]$item.tokenAuthMethod -ceq 'client_secret_post' -and
      [string]$item.clientSecret -notmatch '^[\x21-\x7E]{16,3000}$')){
    throw 'RC1_QUOTA_VAULT_INVALID'
  }
  return $item
 }finally{[Array]::Clear($bytes,0,$bytes.Length)}
}
function Post-Token([string]$uri,[hashtable]$body){
 [void](Validate-OfficialEndpoint $uri)
 return Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 15 -MaximumRedirection 0
}
function Get-ClientAuth($registration){
 # Honor actual DCR result. The hosted service may turn requested 'none'
 # into a confidential client (client_secret_post) with a generated secret.
 $method=[string]$registration.token_endpoint_auth_method
 if($method -cnotin @('none','client_secret_post')){throw 'RC1_QUOTA_DCR_AUTH_UNSUPPORTED'}
 $secret=[string]$registration.client_secret
 if($method -ceq 'client_secret_post' -and
    $secret -notmatch '^[\x21-\x7E]{16,3000}$'){
  throw 'RC1_QUOTA_DCR_CLIENT_SECRET_MISSING'
 }
 if($method -ceq 'none'){$secret=''}
 return @{Method=$method;Secret=$secret}
}
function Add-ClientAuth([hashtable]$body,[string]$method,[string]$secret){
 $body.client_id=[string]$body.client_id
 if($method -ceq 'client_secret_post'){
  if($secret -notmatch '^[\x21-\x7E]{16,3000}$'){
   throw 'RC1_QUOTA_OAUTH_CLIENT_SECRET_INVALID'
  }
  $body.client_secret=$secret
 }elseif($method -cne 'none'){throw 'RC1_QUOTA_OAUTH_CLIENT_AUTH_UNSUPPORTED'}
 return $body
}
function Store-Session([string]$clientId,$token,[string]$authMethod,[string]$clientSecret){
 if(-not $token.access_token -or -not $token.refresh_token){throw 'RC1_QUOTA_TOKEN_MISSING'}
 $until=[DateTime]::UtcNow.AddSeconds([Math]::Max(60,[int]$token.expires_in))
 $item=@{
  clientId=$clientId
  tokenAuthMethod=$authMethod
  clientSecret=$clientSecret
  accessToken=[string]$token.access_token
  refreshToken=[string]$token.refresh_token
  expiresUtc=$until.ToString('o',[Globalization.CultureInfo]::InvariantCulture)
 }
 Save-Credentials $item
 return $item
}
function Invoke-QuotaAuthorize {
 $metadata=Read-OAuthMetadata
 # Dedicated loopback-only PKCE callback. No authorization is requested by
 # the periodic poller; this route is reached only after the user clicks.
 $socket=New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback),0
 $socket.Start()
 try{$port=([Net.IPEndPoint]$socket.LocalEndpoint).Port}finally{$socket.Stop()}
 $redirect='http://127.0.0.1:'+$port+'/callback/'
 $registration=@{
  client_name='RDC Relay usage display'
  redirect_uris=@($redirect)
  grant_types=@('authorization_code','refresh_token')
  response_types=@('code')
  token_endpoint_auth_method='none'
 }|ConvertTo-Json -Compress
 $script:quotaStage='registration'
 $client=Invoke-RestMethod -Method Post -Uri (Validate-OfficialEndpoint $metadata.registration_endpoint) -Body $registration -ContentType 'application/json' -TimeoutSec 15 -MaximumRedirection 0
 if([string]$client.client_id -notmatch '^[A-Za-z0-9._-]{1,220}$'){throw 'RC1_QUOTA_DCR_INVALID'}
 $clientAuth=Get-ClientAuth $client
 $verifier=New-RandomToken 48
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$challenge=To-B64Url ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))}finally{$sha.Dispose()}
 $nonce=New-RandomToken 24
 $params=[ordered]@{
  response_type='code';client_id=$client.client_id
  redirect_uri=$redirect
  code_challenge=$challenge;code_challenge_method='S256'
  state=$nonce;scope='mcp:tools';resource=$service
 }
 $query=(@($params.GetEnumerator()|ForEach-Object{
  [Uri]::EscapeDataString([string]$_.Key)+'='+[Uri]::EscapeDataString([string]$_.Value)
 }) -join '&')
 $listener=New-Object Net.HttpListener
 $listener.Prefixes.Add($redirect)
 try {
  $listener.Start()
  # Browser is opened only on the explicit Account menu click.
  $authUrl=(Validate-OfficialEndpoint ([string]$metadata.authorization_endpoint))+'?'+$query
  $script:quotaStage='browser'
  if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){throw 'RC1_QUOTA_DISABLED'}
  Start-Process -FilePath $authUrl
  $pending=$listener.GetContextAsync()
  if(-not $pending.Wait(180000)){throw 'RC1_QUOTA_AUTH_TIMEOUT'}
  $context=$pending.GetAwaiter().GetResult()
  $script:quotaStage='callback'
  Add-Type -AssemblyName System.Web
  $q=[System.Web.HttpUtility]::ParseQueryString($context.Request.Url.Query)
  $valid=($context.Request.Url.AbsolutePath -ceq '/callback/' -and
    [string]$q['state'] -ceq $nonce -and
    [string]$q['code'] -match '^[\x21-\x7E]{8,4096}$')
  $message=if($valid){'Код подтверждения получен. RDC Relay проверяет доступ к статистике.'}else{'Авторизация статистики не выполнена.'}
  $bytes=[Text.Encoding]::UTF8.GetBytes($message)
  $context.Response.ContentType='text/plain; charset=utf-8'
  $context.Response.ContentLength64=$bytes.Length
  $context.Response.OutputStream.Write($bytes,0,$bytes.Length)
  $context.Response.Close()
  if(-not $valid){throw 'RC1_QUOTA_OAUTH_STATE_OR_CODE'}
  $exchange=@{
   grant_type='authorization_code';code=[string]$q['code']
   client_id=[string]$client.client_id;code_verifier=$verifier
   redirect_uri=$redirect;resource=$service
  }
  $script:quotaStage='token'
  $exchange=Add-ClientAuth $exchange $clientAuth.Method $clientAuth.Secret
  $token=Post-Token ([string]$metadata.token_endpoint) $exchange
  if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){throw 'RC1_QUOTA_DISABLED'}
  [void](Store-Session ([string]$client.client_id) $token $clientAuth.Method $clientAuth.Secret)
  $script:quotaStage='vault'
  [void](Invoke-QuotaPoll)
 }finally{if($listener.IsListening){$listener.Stop()};$listener.Close()}
}
function Parse-McpResponse([string]$body){
 if($body.Length -gt 60000){throw 'RC1_QUOTA_RESPONSE_TOO_LARGE'}
 if($body.TrimStart().StartsWith('{')){return ($body|ConvertFrom-Json)}
 # Streamable HTTP may reply with SSE data lines.
 foreach($line in ($body -split '[\r\n]+')){
  if($line.StartsWith('data: ')){
   $payload=$line.Substring(6)
   if($payload.StartsWith('{')){return ($payload|ConvertFrom-Json)}
  }
 }
 throw 'RC1_QUOTA_MCP_REPLY_MISSING'
}
function Send-Mcp([string]$token,[string]$body,[string]$session=''){
 $headers=@{Authorization=('Bearer '+$token);Accept='application/json, text/event-stream';'MCP-Protocol-Version'='2025-06-18'}
 if($session){$headers['Mcp-Session-Id']=$session}
 $res=Invoke-WebRequest -UseBasicParsing -Method Post -Uri $endpoint -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec 20 -MaximumRedirection 0
 return @{Reply=(Parse-McpResponse ([string]$res.Content));Session=[string]$res.Headers['Mcp-Session-Id']}
}
function Parse-Quota($result){
 if(-not $result -or $result.error -or $result.result.isError){throw 'RC1_QUOTA_TOOL_ERROR'}
 $details=$null
 if($result.result.structuredContent){$details=$result.result.structuredContent}
 if(-not $details){
  foreach($block in @($result.result.content)){
   if($block.type -ceq 'text' -and [string]$block.text -match '^\s*\{'){
    try{$details=[string]$block.text|ConvertFrom-Json;break}catch{}
   }
  }
 }
 if(-not $details){throw 'RC1_QUOTA_MISSING_WHO_AM_I'}
 $pct=0
 if(-not [int]::TryParse([string]$details.remote_calls_left_pct,[ref]$pct) -or
     $pct -lt 0 -or $pct -gt 100 -or
     [string]$details.email -notmatch '^[^@\s]{1,100}@[^@\s]{1,180}$'){
  throw 'RC1_QUOTA_INVALID_WHO_AM_I'
 }
 return @{Percent=$pct;Email=[string]$details.email}
}
function Invoke-QuotaPoll {
 if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){return $false}
 $item=Read-Credentials
 if(-not $item){return $false}
 $metadata=Read-OAuthMetadata
 $expires=[DateTime]::Parse([string]$item.expiresUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
 if($expires.ToUniversalTime() -le [DateTime]::UtcNow.AddMinutes(3)){
  $refresh=@{
   grant_type='refresh_token';refresh_token=[string]$item.refreshToken
   client_id=[string]$item.clientId;resource=$service
  }
  $refresh=Add-ClientAuth $refresh ([string]$item.tokenAuthMethod) ([string]$item.clientSecret)
  $token=Post-Token ([string]$metadata.token_endpoint) $refresh
  $item=Store-Session ([string]$item.clientId) $token ([string]$item.tokenAuthMethod) ([string]$item.clientSecret)
 }
 $script:quotaStage='mcp'
 $init=@{jsonrpc='2.0';id=1;method='initialize';params=@{protocolVersion='2025-06-18';capabilities=@{};clientInfo=@{name='rdc-relay-usage';version='1.6.0'}}}|ConvertTo-Json -Depth 8 -Compress
 $first=Send-Mcp ([string]$item.accessToken) $init
 if($first.Reply.error -or -not $first.Reply.result){throw 'RC1_QUOTA_MCP_INIT_FAILED'}
 $session=[string]$first.Session
 $notification=@{jsonrpc='2.0';method='notifications/initialized'}|ConvertTo-Json -Compress
 try{[void](Send-Mcp ([string]$item.accessToken) $notification $session)}catch{}
 $call=@{jsonrpc='2.0';id=2;method='tools/call';params=@{name='who_am_i';arguments=@{}}}|ConvertTo-Json -Depth 6 -Compress
 $script:quotaStage='tool'
 $reply=Send-Mcp ([string]$item.accessToken) $call $session
 $quota=Parse-Quota $reply.Reply
 $payload=@{
  source='official-remote-who-am-i';accountEmail=$quota.Email
  remainingPercent=$quota.Percent
  observedAtUtc=([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ',[Globalization.CultureInfo]::InvariantCulture))
 }|ConvertTo-Json -Compress
 $script:quotaStage='cache'
 # An in-flight poll must not publish a new value after opt-out.
 if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){return $false}
 Write-PrivateFile $cache ([Text.Encoding]::UTF8.GetBytes($payload))
 return $true
}
try{
 if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){Stop-Quota 'DISABLED'}
 if($Authorize){Invoke-QuotaAuthorize}
 elseif(-not (Invoke-QuotaPoll)){Stop-Quota 'NOT_AUTHORIZED'}
 $script:quotaStage='finished'
 Save-QuotaStatus 'ok'
 Write-Output 'RC1_QUOTA_OK'
}catch{
 # No private exception text; diagnostic only distinguishes the stage.
 # Never turn an unrelated network error into red 0%.
 Stop-Quota 'UNAVAILABLE'
}
