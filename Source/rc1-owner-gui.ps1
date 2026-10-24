# RDC Relay 1.6 RC1 product GUI attach path.
# Dot-sourced ONLY from Source/remote-window.ps1 -OwnerGui.
# Reuses the original complete WinForms window, controls, geometry and renderer.
# Remote/account/write operations are strictly disabled pending approved OS trials.
function Start-RdcOwnerGui {
 $ErrorActionPreference='Stop'
 if(-not $OwnerGui -or [string]::IsNullOrWhiteSpace($OwnerTicketPath)){
  throw 'RC1_OWNER_GUI_CONTEXT_REQUIRED'
 }
 $ticketFull=[IO.Path]::GetFullPath($OwnerTicketPath)
 $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath('LocalApplicationData')).TrimEnd([char]92)
 $pilot=Join-Path $local 'RDCRelayOwnerPilot\1.6.0-RC1'
 $run=[IO.Path]::GetDirectoryName($ticketFull)
 if([IO.Path]::GetFileName($ticketFull) -cne 'gui-ticket.json' -or
    [IO.Path]::GetFileName($run) -cnotmatch '^run-[0-9a-f]{32}$' -or
    -not [String]::Equals([IO.Path]::GetDirectoryName($run),$pilot,[StringComparison]::OrdinalIgnoreCase)){
  throw 'RC1_INVALID_OWNER_TICKET_PATH'
 }
 $cursor=$ticketFull
 while($cursor){
  if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){
   if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'RC1_OWNER_PATH_REPARSE_REFUSED'
   }
  }
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if(-not $parent -or $parent -ceq $cursor){break}
  $cursor=$parent
 }
 Add-Type -Path (Join-Path $root 'RdcOwnerWire.cs') -ReferencedAssemblies @(
  'System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
 $ticket=[RdcOwnerWire]::Decode([IO.File]::ReadAllText($ticketFull,[Text.Encoding]::UTF8))
 if([string]$ticket.remoteMode -cne 'FAKE_ONLY_RC1' -or [int]$ticket.protocol -ne 1){
  throw 'RC1_NOT_FAKE_OWNER'
 }
 $script:ownerIdentity=([string]$ticket.hostPid)+'|'+([string]$ticket.hostTicks)+'|'+([string]$ticket.hostSession)
 $script:ownerGeneration=[string]$ticket.hostGeneration
 $script:ownerNonce=[string]$ticket.nonce
 $script:ownerPipe=[string]$ticket.pipe
 if($script:ownerPipe -cnotmatch '^rdc-rc1-gui-[a-f0-9]{32}$' -or
  $script:ownerGeneration -cnotmatch '^[a-f0-9]{32}$' -or
  $script:ownerNonce -cnotmatch '^[a-f0-9]{32}$'){
  throw 'RC1_OWNER_TICKET_INVALID'
 }
 $script:ownerRequestSequence=1
 $hello=[RdcOwnerWire]::Decode(
  [RdcOwnerWire]::Request('HELLO',$script:ownerNonce,$script:ownerGeneration,0,$null,$script:ownerRequestSequence))
 $hello['guiBuild']='1.6.0 RC1'
 $handshake=[RdcOwnerWire]::Decode([RdcOwnerWire]::Call(
  $script:ownerPipe,$script:ownerIdentity,[RdcOwnerWire]::Json.Serialize($hello),1200))
 if([string]$handshake.type -cne 'WELCOME'){throw 'RC1_OWNER_HELLO_REJECTED'}
 if([string]$handshake.payload.hostGeneration -cne $script:ownerGeneration -or
    [bool]$handshake.payload.isActualRemote){throw 'RC1_OWNER_SNAPSHOT_MISMATCH'}
 $form.Text='RDC Relay 1.6.0 RC1 — Remote не подключён (режим проверки)'
 $finish.Enabled=$false;$accountButton.Enabled=$false
 $helpButton.Enabled=$true
 $script:ownerCloseGeneration=[int]$handshake.payload.closeGeneration
 $script:ownerEventCursor=0
 $script:ownerNextVerb='GET_SNAPSHOT'
 $script:ownerPending=$null
 $script:ownerStatus='FAKE_ONLY_RC1'
 $script:ownerLastShownRevision=-1
 Set-State 'Демонстрация RC1' 'Настоящий Desktop Commander Remote не подключён; действия недоступны.' ([Drawing.Color]::Khaki)
 Set-RuntimeDisplay ('Host PID '+[string]$ticket.hostPid) 'Тестовый Host / Remote не подключён' $true
 Add-CompletedEvent 'RDC Relay 1.6.0 RC1. Авторитетный Host использует только синтетическое состояние; настоящий Remote НЕ запущен.'
 Render-CompactLog
 $script:ownerTimer=New-Object Windows.Forms.Timer
 $script:ownerTimer.Interval=150
 $script:ownerTimer.Add_Tick({
  if($script:ownerPending -and $script:ownerPending.IsCompleted){
   try{
    $reply=[RdcOwnerWire]::Decode([string]$script:ownerPending.GetAwaiter().GetResult())
    if([string]$reply.type -eq 'SNAPSHOT'){
     $snapshot=$reply.payload
     if([string]$snapshot.hostGeneration -cne $script:ownerGeneration -or
        [bool]$snapshot.isActualRemote){throw 'RC1_OWNER_GENERATION_OR_MODE_CHANGED'}
     if([int]$snapshot.closeGeneration -gt $script:ownerCloseGeneration){$form.Close();return}
     if([long]$snapshot.revision -ne $script:ownerLastShownRevision){
      $script:ownerLastShownRevision=[long]$snapshot.revision
      Set-RuntimeDisplay ('Host PID '+[string]$snapshot.hostPid) 'Remote НЕ подключён | RC1' $true
     }
     $script:ownerNextVerb='GET_EVENTS'
    }elseif([string]$reply.type -eq 'EVENT_BATCH'){
     $eventData=$reply.payload
     if([string]$eventData.hostGeneration -cne $script:ownerGeneration){throw 'RC1_STALE_EVENTS'}
     if([bool]$eventData.gap){
      $script:ownerEventCursor=[long]$eventData.lastEventSeq
      $script:ownerNextVerb='GET_SNAPSHOT'
     }else{
      foreach($ev in $eventData.events){
       if([long]$ev.sequence -le $script:ownerEventCursor){throw 'RC1_DUPLICATE_EVENT'}
       $script:ownerEventCursor=[long]$ev.sequence
       Add-CompletedEvent ('[RC1 '+[string]$ev.sequence+'] '+[string]$ev.text)
      }
      $script:ownerNextVerb=if($eventData.moreAvailable){'GET_EVENTS'}else{'GET_SNAPSHOT'}
     }
    }else{throw 'RC1_BAD_REPLY'}
   }catch{
    $script:ownerNextVerb='GET_SNAPSHOT'
    Set-State 'Связь с Host' 'IPC временно недоступен, Remote не подключён.' ([Drawing.Color]::Khaki)
   }finally{$script:ownerPending=$null}
  }
  if(-not $script:ownerPending -and -not $form.IsDisposed){
   $script:ownerRequestSequence++
   $wire=[RdcOwnerWire]::Request($script:ownerNextVerb,$script:ownerNonce,
     $script:ownerGeneration,[long]$script:ownerEventCursor,$null,[long]$script:ownerRequestSequence)
   $script:ownerPending=[RdcOwnerWire]::CallBackground($script:ownerPipe,
    $script:ownerIdentity,$wire,800)
  }
 })
 $form.Add_FormClosed({if($script:ownerTimer){$script:ownerTimer.Stop();$script:ownerTimer.Dispose()}})
 try{
  $script:ownerTimer.Start()
  [Windows.Forms.Application]::Run($form)
 }finally{
  if($script:ownerTimer){$script:ownerTimer.Stop();$script:ownerTimer.Dispose()}
  $form.Dispose()
 }
}
