# Legacy bridge: qualification only, dot-sourced by the old GUI.
# No action happens on import. The permanent gateway is the sole allowed asset.
$script:rdcMigrationOffer=$null
$script:rdcMigrationDownload=$null
$script:rdcMigrationHandoff=$null
function Get-RdcMigrationOffer($manifest,[string]$installed){
 try{
  $local=[Version]$installed
  $m=$manifest.migration
  if($local -ge [Version]'1.6.0' -or [string]$manifest.version -cne '1.5.18' -or
   !$m -or $m.schema -isnot [int] -or $m.schema -ne 1 -or
   $m.ready -isnot [bool] -or !$m.ready -or
   [string]$m.targetVersion -cne '1.6.0' -or [string]$m.releaseTag -cne 'v1.6.0' -or
   [string]$m.mode -cne 'installer-handoff' -or
   [string]$m.asset -cne 'RDC.Relay.Setup.v1.6.0.exe' -or
   [string]$m.setupSha256 -cnotmatch '^[0-9a-fA-F]{64}$'){return $null}
  return [pscustomobject]@{Digest=([string]$m.setupSha256).ToUpperInvariant();Uri=[Uri]'https://github.com/Rubo-Facility/RDC-Relay/releases/download/v1.6.0/RDC.Relay.Setup.v1.6.0.exe'}
 }catch{return $null}
}
function Test-RdcMigrationUri([Uri]$uri){
 return ($uri -and $uri.IsAbsoluteUri -and $uri.Scheme -ceq 'https' -and
  $uri.IsDefaultPort -and !$uri.UserInfo -and
  @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com') -ccontains $uri.DnsSafeHost)
}
function Get-RdcMigrationDigest([byte[]]$bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function Test-RdcMigrationBytes([byte[]]$bytes,[string]$digest){
 return ($bytes -and $bytes.Length -ge 2 -and $bytes.Length -le 32MB -and
  $bytes[0] -eq 77 -and $bytes[1] -eq 90 -and $digest -cmatch '^[0-9A-F]{64}$' -and
  (Get-RdcMigrationDigest $bytes) -ceq $digest)
}
function Test-RdcMigrationNoRemote{
 try{
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='cmd.exe'" -ErrorAction Stop)){
   if(!$p.CommandLine -or ($p.CommandLine -match '(?i)desktop-commander' -and $p.CommandLine -match '(?i)\bremote\b')){return $false}
  }
  return $true
 }catch{return $false}
}
function Test-RdcMigrationIdle{
 if($script:initializing -or $script:remoteOperation -or $script:autoReconnectAt -or $script:closeRequested){return $false}
 try{if($script:proc -and !$script:proc.HasExited){return $false}}catch{return $false}
 return (Test-RdcMigrationNoRemote)
}
function Assert-RdcMigrationPath([string]$path){
 for($p=[IO.Path]::GetFullPath($path);$p;$p=[IO.Path]::GetDirectoryName($p)){
  if(([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) -and
   ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint)){throw 'MIGRATION_REPARSE'}
 }
}
function Save-RdcMigrationCandidate([byte[]]$bytes,[string]$digest){
 if(!(Test-RdcMigrationBytes $bytes $digest)){throw 'MIGRATION_HASH'}
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-Migration-'+[Guid]::NewGuid().ToString('N'))
 Assert-RdcMigrationPath $dir
 if(Test-Path -LiteralPath $dir){throw 'MIGRATION_COLLISION'}
 [void][IO.Directory]::CreateDirectory($dir)
 $path=Join-Path $dir 'RDC.Relay.Setup.v1.6.0.exe'
 Assert-RdcMigrationPath $path
 $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $digest){throw 'MIGRATION_DISK_HASH'}
 # Preserve Windows Internet-zone provenance for normal SmartScreen policy.
 Set-Content -LiteralPath $path -Stream Zone.Identifier -Value @('[ZoneTransfer]','ZoneId=3') -Encoding ASCII -ErrorAction Stop
 if((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw -ErrorAction Stop) -notmatch '(?m)^ZoneId=3\r?$'){throw 'MIGRATION_ZONE_MARK'}
 return [pscustomobject]@{Path=$path;Digest=$digest}
}
function Clear-RdcMigrationDownload{
 $d=$script:rdcMigrationDownload
 $script:rdcMigrationDownload=$null
 if($d){
  if($d.Timer){$d.Timer.Stop();$d.Timer.Dispose()}
  if($d.Client){$d.Client.Dispose()}
 }
 $script:rdcNoticeInstalling=$false
 if($script:rdcNoticeControl -and !$script:rdcNoticeControl.IsDisposed){$script:rdcNoticeControl.Installing=$false}
}
function Show-RdcMigrationMessage([string]$message){
 [void][Windows.Forms.MessageBox]::Show($message,'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
}
function Update-RdcMigrationDownload{
 $d=$script:rdcMigrationDownload
 if(!$d){return}
 try{
  if([DateTime]::UtcNow -ge $d.Deadline){throw 'MIGRATION_TIMEOUT'}
  if(!$d.Task.IsCompleted){return}
  $r=$d.Task.GetAwaiter().GetResult()
  try{
   if([int]$r.StatusCode -in @(301,302,303,307,308)){
    if(!$r.Headers.Location -or $d.Hops -ge 5){throw 'MIGRATION_REDIRECT'}
    $next=[Uri]::new($d.Uri,$r.Headers.Location)
    if(!(Test-RdcMigrationUri $next)){throw 'MIGRATION_REDIRECT'}
    $d.Hops++;$d.Uri=$next
    $d.Task=$d.Client.GetAsync($next)
    return
   }
   [void]$r.EnsureSuccessStatusCode()
   $bytes=$r.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
   $candidate=Save-RdcMigrationCandidate $bytes $d.Digest
  }finally{$r.Dispose()}
  Clear-RdcMigrationDownload
  if(!(Test-RdcMigrationIdle)){
   Show-RdcMigrationMessage 'Remote активен. Остановите его штатно и повторите обновление.'
   return
  }
  $script:rdcMigrationHandoff=$candidate
  # Normal FormClosing; do not set allowClose or force-stop any process.
  $form.Close()
  if(!$form.IsDisposed -and $form.Visible){$script:rdcMigrationHandoff=$null}
 }catch{
  Clear-RdcMigrationDownload
  Show-RdcMigrationMessage 'Не удалось подготовить обновление до 1.6.0. Текущая версия не изменена.'
 }
}
function Start-RdcLegacyMigration{
 if($script:rdcMigrationDownload -or !$script:rdcMigrationOffer){return}
 if(!(Test-RdcMigrationIdle)){
  Show-RdcMigrationMessage 'Перед обновлением остановите Remote штатной кнопкой.'
  return
 }
 $answer=[Windows.Forms.MessageBox]::Show('Обновить RDC Relay до 1.6.0? После загрузки текущая оболочка закроется и откроется установщик.','RDC Relay',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2)
 if($answer -ne [Windows.Forms.DialogResult]::Yes -or !(Test-RdcMigrationIdle)){return}
 try{
  Add-Type -AssemblyName System.Net.Http
  $offer=$script:rdcMigrationOffer
  if(!(Test-RdcMigrationUri $offer.Uri)){throw 'MIGRATION_URI'}
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $handler=New-Object Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect=$false;$handler.UseCookies=$false;$handler.UseDefaultCredentials=$false
  $client=New-Object Net.Http.HttpClient($handler)
  $client.Timeout=[TimeSpan]::FromSeconds(45)
  $client.MaxResponseContentBufferSize=32MB
  $client.DefaultRequestHeaders.UserAgent.ParseAdd('RDCRelayMigration/1.0')
  $timer=New-Object Windows.Forms.Timer
  $timer.Interval=150
  $script:rdcMigrationDownload=[pscustomobject]@{Client=$client;Timer=$timer;Task=$null;Uri=$offer.Uri;Digest=$offer.Digest;Hops=0;Deadline=[DateTime]::UtcNow.AddSeconds(90)}
  $script:rdcNoticeInstalling=$true;$script:rdcNoticeControl.Installing=$true
  $script:rdcMigrationDownload.Task=$client.GetAsync($offer.Uri)
  $timer.Add_Tick({Update-RdcMigrationDownload})
  $timer.Start()
 }catch{
  Clear-RdcMigrationDownload
  Show-RdcMigrationMessage 'Не удалось начать загрузку обновления.'
 }
}
function Complete-RdcMigrationHandoff{
 $c=$script:rdcMigrationHandoff
 $script:rdcMigrationHandoff=$null
 if(!$c){return}
 try{
  Assert-RdcMigrationPath $c.Path
  if(!(Test-RdcMigrationNoRemote)){throw 'MIGRATION_REMOTE_ACTIVE'}
  if((Get-FileHash -LiteralPath $c.Path -Algorithm SHA256).Hash -cne $c.Digest){throw 'MIGRATION_RECHECK'}
  if((Get-Content -LiteralPath $c.Path -Stream Zone.Identifier -Raw -ErrorAction Stop) -notmatch '(?m)^ZoneId=3\r?$'){throw 'MIGRATION_ZONE_MARK'}
  # Normal interactive Setup, no private flags or security-policy changes.
  Start-Process -FilePath $c.Path -ErrorAction Stop
 }catch{
  Show-RdcMigrationMessage 'Не удалось запустить установщик. Запустите прежнюю версию с рабочего стола и повторите обновление.'
 }
}
