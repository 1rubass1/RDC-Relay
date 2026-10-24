# No Host/GUI process, no IPC listener, no Remote. Exercises EXACT product
# C# ticket CreateThen branch with an injected delegate exception.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Add-Type -Path @((Join-Path $root 'Source\RdcOwnerWire.cs'),(Join-Path $root 'Source\RdcOwnerTicketStore.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.dll')
$passes=0;$fails=0
function Assert([bool]$ok,[string]$why){if($ok){$script:passes++;Write-Output ('PASS '+$why)}else{$script:fails++;Write-Output ('FAIL '+$why)}}
$parent=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-TICKET-'+[Guid]::NewGuid().ToString('N'))
$runId=[Guid]::NewGuid().ToString('N')
$gen=[Guid]::NewGuid().ToString('N')
$run=Join-Path $parent ('run-'+$runId)
$sentinel=Join-Path $parent 'outside-sentinel.txt'
if([IO.Directory]::Exists($parent)){throw 'FAIL Unexpected test directory collision'}
[void][IO.Directory]::CreateDirectory($run)
[IO.File]::WriteAllText($sentinel,'sentinel unchanged')
$store=$null
try{
 $json=[RdcOwnerWire]::Json.Serialize(@{hostGeneration=$gen;nonce=[Guid]::NewGuid().ToString('N');remoteMode='FAKE_ONLY_RC1'})
 $sid=[RdcOwnerWire]::LogonSid()
 $store=New-Object RdcOwnerTicketStore -ArgumentList @($run,$gen,$sid)
 Assert ($store.PathName -eq (Join-Path $run 'gui-ticket.json')) 'exact direct-child ticket path'
 $threw=$false
 try{
  $unused=$store.CreateThen($json,[Func[object]]{throw [IO.IOException]::new('INJECT_START_FAILURE')})
 }catch{$threw=$true}
 Assert $threw 'injected failing spawn throws'
 Assert (-not [IO.File]::Exists($store.PathName) -and -not $store.HasOwnedTicket) 'spawn error cleans only owned ticket'
 $result=$store.CreateThen($json,[Func[object]]{return (New-Object Object)})
 Assert ($null -ne $result -and [IO.File]::Exists($store.PathName)) 'retry after failure accepts new ticket without creating process'
 Assert ($store.RevokeOnlyOwned() -and -not [IO.File]::Exists($store.PathName)) 'verified own ticket can be revoked'
 $startNullThrew=$false
 try{$unused=$store.CreateThen($json,[Func[object]]{return $null})}catch{$startNullThrew=$true}
 Assert ($startNullThrew -and -not [IO.File]::Exists($store.PathName)) 'null process handle revoked and retryable'
 $foreign='fixture-unattested-foreign-ticket'
 [IO.File]::WriteAllText($store.PathName,$foreign,(New-Object Text.UTF8Encoding($false)))
 $foreignDenied=$false
 try{$unused=$store.CreateThen($json,[Func[object]]{return (New-Object Object)})}catch{$foreignDenied=$true}
 Assert ($foreignDenied -and [IO.File]::ReadAllText($store.PathName) -ceq $foreign) 'unattested foreign ticket blocks creation and is not deleted'
 # This foreign leaf was just created by this exact negative test; delete it
 # only after exact-byte verification, never via product RevokeOnlyOwned().
 if([IO.File]::ReadAllText($store.PathName) -cne $foreign){throw 'NOT CLEAN foreign fixture bytes differ'}
 [IO.File]::Delete($store.PathName)
 $store.Create($json)
 [IO.File]::WriteAllText($store.PathName,'TAMPERED; owner marker no longer matches')
 Assert (-not $store.RevokeOnlyOwned() -and [IO.File]::Exists($store.PathName)) 'modified ticket refused without deletion'
 Assert ([IO.File]::ReadAllText($sentinel) -ceq 'sentinel unchanged') 'external sentinel byte content preserved'
}catch{$script:fails++;Write-Output ('FAIL exception '+$_.Exception.Message)}
finally{
 # Do not delete the tampered ticket: never bypass the safety assertion.
 # Fixture cleanup is only allowed if restored from a known identical owned
 # payload and the store confirms ownership. Otherwise report NOT CLEAN.
 if($store -and [IO.File]::Exists($store.PathName)){
  if([IO.File]::ReadAllText($store.PathName) -ceq 'TAMPERED; owner marker no longer matches'){
   # This fixture's test mutation belongs to this exact test (not user data),
   # but do not bypass store ownership: restore attested bytes, then revoke.
   [IO.File]::WriteAllText($store.PathName,$json,(New-Object Text.UTF8Encoding($false)))
  }
  if(-not $store.RevokeOnlyOwned()){$script:fails++;Write-Output ('FAIL NOT CLEAN own fixture ticket')}
 }
 if([IO.Directory]::Exists($parent)){
  $expected=@(('run-'+$runId),'outside-sentinel.txt')
  $actual=@([IO.Directory]::GetFileSystemEntries($parent))
  if(@($actual|Where-Object{$expected -cnotcontains [IO.Path]::GetFileName($_)}).Count -ne 0){
   $script:fails++;Write-Output ('FAIL NOT CLEAN unexpected fixture entry')
  }else{
   if([IO.Directory]::GetFileSystemEntries($run).Count -eq 0){
    [IO.Directory]::Delete($run)
    [IO.File]::Delete($sentinel)
    [IO.Directory]::Delete($parent)
   }else{$script:fails++;Write-Output ('FAIL NOT CLEAN nested fixture entry')}
  }
 }
}
Write-Output ('RC1_TICKET_TEST_PASS='+$passes+' FAIL='+$fails)
if($fails){exit 1}
exit 0
