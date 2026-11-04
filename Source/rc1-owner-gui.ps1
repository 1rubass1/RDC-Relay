# RDC Relay 1.6 RC1 product GUI attach path.
# Dot-sourced ONLY from Source/remote-window.ps1 -OwnerGui.
# Reuses the original complete WinForms window, controls, geometry and renderer.
# Adopted/Unknown Remote is immutable. Managed-mode Remote actions are
# executed exclusively by the authenticated persistent Host after explicit UI.
# The RC1 Host streams monotonic, sanitized event IDs. Show only the
# fixed-width sequence and a Unicode status, never the Host/Remote prefix.
# This formatter never receives raw Remote stdout, credentials or tool args.
function Format-Rc1JournalLine([long]$number,[string]$message) {
 if($number -lt 0){throw 'RC1_JOURNAL_NEGATIVE_SEQUENCE'}
 $text=([string]$message).Trim()
 # The Host correlates calls using private remote IDs. Only a generated
 # operation number and bounded safe labels are accepted in the GUI.
 if($text -cmatch '\ARemote tool (started|completed|failed)\|([1-9][0-9]{0,11})\|([a-z][a-z0-9_]{1,39})\|([\p{L}\p{Nd}_ .()\-]{0,64})\z'){
  $phase=[string]$Matches[1];$operation=[long]$Matches[2]
  $tool=[string]$Matches[3];$target=[string]$Matches[4]
  $action=switch -Exact ($tool){
   'read_file' {'Чтение файла'} 'read_multiple_files' {'Чтение файлов'}
   'write_file' {'Запись файла'} 'edit_block' {'Изменение файла'}
   'list_directory' {'Просмотр папки'} 'get_file_info' {'Сведения о файле'}
   'start_process' {'Запуск программы'} 'read_process_output' {'Вывод процесса'}
   'interact_with_process' {'Ввод в процесс'} 'list_processes' {'Просмотр процессов'}
   'start_search' {'Поиск'} 'get_more_search_results' {'Результаты поиска'}
   'stop_search' {'Остановка поиска'} 'move_file' {'Перемещение файла'}
   'create_directory' {'Создание папки'} 'get_config' {'Настройки'}
   default {'Операция'}
  }
  $done=switch -Exact ($tool){
   'read_file' {'Файл прочитан'} 'read_multiple_files' {'Файлы прочитаны'}
   'write_file' {'Файл записан'} 'edit_block' {'Файл изменён'}
   'list_directory' {'Содержимое папки получено'}
   'get_file_info' {'Сведения получены'} 'start_process' {'Запрос запуска обработан'}
   'read_process_output' {'Вывод получен'} 'interact_with_process' {'Ввод обработан'}
   'list_processes' {'Список процессов получен'}
   'start_search' {'Поиск запущен'} 'get_more_search_results' {'Результаты получены'}
   'stop_search' {'Поиск остановлен'} 'move_file' {'Файл перемещён'}
   'create_directory' {'Папка создана'} 'get_config' {'Настройки получены'}
   default {'Вызов завершён'}
  }
  $messageText=switch -Exact ($phase){
   'started' {'🔧 '+$action}
   'completed' {'✅ '+$done}
   'failed' {'❌ Ошибка: '+$action}
  }
  if($target){$messageText+=' — '+$target}
  return $operation.ToString('D6',[Globalization.CultureInfo]::InvariantCulture)+' │ '+$messageText
 }
 # Remote 0.2.52 completion lines identify a tool but not its call UUID.
 # If several calls of that tool overlap, Host does not invent a pairing.
 if($text -cmatch '\ARemote tool (completed|failed): ([a-z][a-z0-9_]{1,39})\z'){
  $phase=[string]$Matches[1];$tool=[string]$Matches[2]
  $kind=switch -Exact ($tool){
   'read_file' {'чтение файла'} 'read_multiple_files' {'чтение файлов'}
   'write_file' {'запись файла'} 'edit_block' {'изменение файла'}
   'list_directory' {'просмотр папки'} 'start_process' {'запуск программы'}
   'read_process_output' {'чтение вывода'} 'interact_with_process' {'ввод в процесс'}
   'list_processes' {'просмотр процессов'} 'start_search' {'поиск'}
   'get_more_search_results' {'получение результатов'}
   'get_file_info' {'сведения о файле'} 'move_file' {'перемещение файла'}
   'create_directory' {'создание папки'} 'stop_search' {'остановка поиска'}
   'get_config' {'чтение настроек'} default {'операция'}
  }
  $status=if($phase -ceq 'completed'){'✅ Завершено: '}else{'❌ Ошибка: '}
  return $number.ToString('D6',[Globalization.CultureInfo]::InvariantCulture)+' │ '+$status+$kind
 }
 # Fail closed on malformed tool-rich rows so payloads are never reflected.
 if($text.StartsWith('Remote tool ',[StringComparison]::Ordinal) -and $text.Contains('|')){
  return $number.ToString('D6',[Globalization.CultureInfo]::InvariantCulture)+' │ • Событие инструмента'
 }
 $description=switch -CaseSensitive -Regex ($text) {
  '^Remote tool started: ([a-z][a-z0-9_]{1,39})$' { '🔧 Начато: '+$Matches[1];break }
  '^Remote tool started$' { '🔧 Начато';break }
  '^Remote tool completed$' { '✅ Выполнено';break }
  '^Remote tool failed$' { '❌ Ошибка выполнения';break }
  '^Remote connected$' { '🔌 Remote подключён';break }
  '^Authentication pending$' { '⏳ Ожидание авторизации';break }
  '^Remote channel unavailable$' { '❌ Канал Remote недоступен';break }
  '^Remote start failed$' { '❌ Ошибка запуска Remote';break }
  '^Local MCP recovering$' { '⏳ Восстановление MCP';break }
  '^Remote launcher replaced$' { '🔌 Сессия Remote обновлена';break }
  default { '• '+$text }
 }
 return $number.ToString('D6',[Globalization.CultureInfo]::InvariantCulture)+' │ '+$description
}
# These are the original, allowlisted Remote startup lines from Host. Only
# Owner GUI's display copy is adapted: the source log and IPC snapshot remain
# unchanged for evidence/provenance, and legacy 1.5.18 rendering is untouched.
function Convert-Rc1OwnerStartupInstructions([string]$header) {
 if([string]::IsNullOrEmpty($header)){return $header}
 $terminalKeep='Keep this Terminal running. You can minimize it.'
 $terminalStop='Press Ctrl+C to disconnect.'
 $ownerKeep='You can close this window; RDC Relay continues running in the system tray.'
 $ownerStop='Click Stop to disconnect Remote.'
 $display=New-Object 'System.Collections.Generic.List[string]'
 foreach($line in ($header.Replace("`r`n","`n") -split "`n",-1)){
  # Ctrl+C interrupts an interactive terminal, not this separate Host/GUI.
  # Replace its keyboard hint with the action's Stop symbol in the same
  # final instruction slot, so the Next block keeps its visual ending.
  if($line.EndsWith($terminalStop,[StringComparison]::Ordinal)){
   $prefix=$line.Substring(0,$line.Length-$terminalStop.Length)
   if($prefix.EndsWith('⌨ ',[StringComparison]::Ordinal)){
    $prefix=$prefix.Substring(0,$prefix.Length-2)+'⏹ '
   }
   [void]$display.Add($prefix+$ownerStop)
  }elseif($line.EndsWith($terminalKeep,[StringComparison]::Ordinal)){
   [void]$display.Add($line.Substring(0,$line.Length-$terminalKeep.Length)+$ownerKeep)
  }else{[void]$display.Add($line)}
 }
 return [string]::Join("`n",$display.ToArray())
}
# A read-only, expiring private snapshot from an authorized official
# Remote Desktop Commander who_am_i call. The Windows device-agent's OAuth
# credentials are NOT reused: they are not the ChatGPT/hosted MCP client grant.
# If no fresh service-provided snapshot is present, show an honest dash.
function Get-Rc1QuotaStatus([string]$path,[string]$expectedEmail,[DateTime]$nowUtc) {
 $missing='Остаток вызовов: --%'
 if(-not $path -or -not $expectedEmail -or -not [IO.File]::Exists($path)){return $missing}
 try {
  $file=Get-Item -LiteralPath $path -ErrorAction Stop
  if($file.Length -lt 40 -or $file.Length -gt 512){return $missing}
  $raw=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
  $data=ConvertFrom-Json -InputObject $raw -ErrorAction Stop
  if([string]$data.source -cne 'official-remote-who-am-i'){return $missing}
  if(-not [string]::Equals([string]$data.accountEmail,$expectedEmail.Trim(),
      [StringComparison]::OrdinalIgnoreCase)){return $missing}
  $n=0
  if(-not [int]::TryParse([string]$data.remainingPercent,[ref]$n) -or $n -lt 0 -or $n -gt 100){
   return $missing
  }
  $observed=[DateTime]::MinValue
  if(-not [DateTime]::TryParseExact([string]$data.observedAtUtc,'yyyy-MM-ddTHH:mm:ssZ',
      [Globalization.CultureInfo]::InvariantCulture,
      ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal),
      [ref]$observed)){return $missing}
  $age=($nowUtc.ToUniversalTime()-$observed).TotalMinutes
  if($age -lt -2 -or $age -ge 60){return $missing}
  return ('Остаток вызовов: '+$n+'%')
 }catch{return $missing}
}
function Start-RdcOwnerGui {
 $ErrorActionPreference='Stop'
 if(-not $OwnerGui -or [string]::IsNullOrWhiteSpace($OwnerTicketPath)){
  throw 'RC1_OWNER_GUI_CONTEXT_REQUIRED'
 }
 $ticketFull=[IO.Path]::GetFullPath($OwnerTicketPath)
 $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath('LocalApplicationData')).TrimEnd([char]92)
 $pilot=Join-Path $local 'RDCRelayOwnerPilot\1.6.0-RC1'
 if($OwnerTrialRoot){
  $trial=[IO.Path]::GetFullPath($OwnerTrialRoot).TrimEnd([char]92)
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  if(-not [String]::Equals([IO.Path]::GetDirectoryName($trial),$temp,[StringComparison]::OrdinalIgnoreCase) -or
     [IO.Path]::GetFileName($trial) -cnotmatch '^RDC-RC1-OS-[a-f0-9]{32}$' -or
     -not [IO.Directory]::Exists($trial)) {throw 'RC1_OWNER_TRIAL_ROOT_BOUNDARY'}
  $pilot=Join-Path $trial 'owner-state'
 }
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
 $script:ownerObservedMode=([string]$ticket.remoteMode -ceq 'OBSERVED_READ_ONLY_RC1')
 $script:ownerManagedMode=([string]$ticket.remoteMode -ceq 'MANAGED_OWNER_RC1')
 $script:ownerRealMode=$script:ownerObservedMode -or $script:ownerManagedMode
 if(([string]$ticket.remoteMode -cne 'FAKE_ONLY_RC1' -and -not $script:ownerRealMode) -or
    [int]$ticket.protocol -ne 1){throw 'RC1_UNKNOWN_OWNER_MODE'}
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
    [bool]$handshake.payload.isActualRemote -ne $script:ownerRealMode){
  throw 'RC1_OWNER_SNAPSHOT_MISMATCH'
 }
 $form.Text=if($script:ownerObservedMode){
  'RDC Relay 1.6.0 RC1 — существующий Remote (только чтение)'
 }elseif($script:ownerManagedMode){
  'RDC Relay 1.6.0 RC1 — управляемый Host/GUI'
 }else{'RDC Relay 1.6.0 RC1 — Remote не подключён (режим проверки)'}
 # Keep the real original Account/Help controls functional for SAFE routes.
 # Only Remote/account-mutating actions remain disabled for Adopted/Unknown.
 $finish.Enabled=$script:ownerManagedMode
 $finish.AccessibleDescription=if($script:ownerManagedMode){'Запуск или остановка только Remote, принадлежащего текущему Host.'}else{
  'Управление существующим Remote недоступно: сессия не принадлежит RC1.'
 }
 $tipText=if($script:ownerManagedMode){'Управление только собственным Remote этого Host.'}else{
  'Существующий Remote принадлежит старой оболочке. После её штатного завершения RC1 создаст новую управляемую сессию.'
 }
 $tip.SetToolTip($finish,$tipText)
 $accountButton.Enabled=$true
 $quotaAuthItem.Enabled=$script:ownerRealMode
 $accountButton.AccessibleDescription='Аккаунт: переход к управлению устройствами без изменения Remote.'
 $switchAccountItem.Enabled=$false
 $reconnectItem.Enabled=$false
 $initialCapabilities=$handshake.payload.capabilities
 if(-not $initialCapabilities){throw 'RC1_OWNER_CAPABILITIES_MISSING'}
 $devicesItem.Enabled=[bool]$initialCapabilities.deviceManagementLink
 $verifyDeviceItem.Enabled=$false # RC1 manual verification removed
 $openLogItem.Enabled=[bool]$initialCapabilities.sanitizedJournal
 $openLogItem.Text='Показать журнал RC1'
 $helpButton.Enabled=$true
 $script:ownerCloseGeneration=[int]$handshake.payload.closeGeneration
 $script:ownerEventCursor=0
 $script:ownerNextVerb='GET_SNAPSHOT'
 $script:ownerPending=$null
 $script:ownerQueuedNavigation=''
 $script:ownerRequestedNavigation=''
 $script:ownerQueuedAction=''
 $script:ownerRequestedAction=''
 $script:ownerStatus=if($script:ownerObservedMode){'OBSERVED_READ_ONLY_RC1'}elseif($script:ownerManagedMode){'MANAGED_OWNER_RC1'}else{'FAKE_ONLY_RC1'}
 $script:ownerLastShownRevision=-1
 $script:ownerLastShownRemoteRevision=-1
 $script:ownerRemoteBornTicks=0
 $script:ownerLastSnapshotUtcTicks=0
 $script:ownerRemotePid=0
 $script:ownerLastUptimeText=''
 $script:ownerQuotaPath=Join-Path (Join-Path $env:LOCALAPPDATA 'RDCRelayOwnerPilot') 'remote-usage-cache.json'
 $script:ownerQuotaNextCheckUtc=[DateTime]::MinValue
 $script:ownerLastQuotaText=''
 $script:ownerLastLogCursor=0
 $script:ownerLastLogEpoch=-1
 # Owner-only compact activity journal; legacy 1.5.18 renderer remains spaced.
 $script:ownerCompactJournal=$true
 $script:ownerLastToolFault=$false
 $script:ownerLastRemoteLinkState=''
 if($script:ownerObservedMode){
  Set-State 'Подключение к Host' 'Старый Remote обнаружен. После штатного завершения прежней оболочки RC1 запустит новый.' ([Drawing.Color]::Khaki)
  Set-RuntimeDisplay ('PID '+[string]$ticket.hostPid) 'Remote: существующая сессия / Adopted' $true
  Add-CompletedEvent 'RC1 подключён к работающему Desktop Commander Remote только для наблюдения. X закрывает GUI; Remote не затрагивается.'
 }elseif($script:ownerManagedMode){
  Set-FinishButtonMode $false
  $finish.Enabled=[bool]$initialCapabilities.startRemote
  $script:ownerCanStart=[bool]$initialCapabilities.startRemote
  $script:ownerCanStop=$false
  $script:ownerCanReconnect=$false
  Set-State 'Remote отключён' 'Host готов запустить новую управляемую сессию Desktop Commander.' ([Drawing.Color]::Khaki)
  Set-RuntimeDisplay ('PID '+[string]$ticket.hostPid) 'Remote: Host-owned / ожидание запуска' $true
  Add-CompletedEvent 'RDC Relay RC1: управление Remote выполняет постоянный Host. X закрывает только это окно.'
 }else{
  Set-State 'Демонстрация RC1' 'Настоящий Desktop Commander Remote не подключён; действия недоступны.' ([Drawing.Color]::Khaki)
  Set-RuntimeDisplay ('PID '+[string]$ticket.hostPid) 'Тестовый Host / Remote не подключён' $true
  Add-CompletedEvent 'RDC Relay 1.6.0 RC1. Host использует синтетическое состояние; настоящий Remote не запущен.'
 }
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
        [bool]$snapshot.isActualRemote -ne $script:ownerRealMode){
      throw 'RC1_OWNER_GENERATION_OR_MODE_CHANGED'
     }
     if([int]$snapshot.closeGeneration -gt $script:ownerCloseGeneration){$form.Close();return}
     # The Host, never this GUI, owns the monotonic fake log cursor/state.
     # A fresh GUI reconstructs its journal from the bounded Host snapshot.
     $remoteSnapshot=$snapshot.remote
     $script:ownerRemoteBornTicks=if($script:ownerManagedMode){[long]$snapshot.remoteBornUtcTicks}else{0L}
     $script:ownerRemotePid=[int]$remoteSnapshot.processPid
     $script:ownerLastSnapshotUtcTicks=[DateTime]::UtcNow.Ticks
     if(-not $snapshot.capabilities){throw 'RC1_CAPABILITIES_MISSING'}
     # Permissions come from Host, never from a GUI-local PID/ownership guess.
     $devicesItem.Enabled=[bool]$snapshot.capabilities.deviceManagementLink
     $verifyDeviceItem.Enabled=[bool]$snapshot.capabilities.deviceVerificationLink
     $openLogItem.Enabled=[bool]$snapshot.capabilities.sanitizedJournal
     if($script:ownerManagedMode){
      $script:ownerCanStart=[bool]$snapshot.capabilities.startRemote
      $script:ownerCanStop=[bool]$snapshot.capabilities.stopRemote
      $script:ownerCanReconnect=[bool]$snapshot.capabilities.reconnectRemote
      $finish.Enabled=($script:ownerCanStart -or $script:ownerCanStop)
      Set-FinishButtonMode $script:ownerCanStop
      $reconnectItem.Enabled=$script:ownerCanReconnect
     }
     if(-not $remoteSnapshot -or
        [bool]$remoteSnapshot.isActualRemote -ne $script:ownerRealMode){
      throw 'RC1_REMOTE_MODE_MISMATCH'
     }
     # Unlike old monolithic GUI, live Remote output is owned by Host.
     # Authenticated snapshots carry only fixed tool activity categories.
     # Apply on every snapshot, even when Host/Remote revisions are unchanged:
     # activity hold expiry is clock-based and must return the shader to idle.
     $toolActivity=[string]$remoteSnapshot.toolActivity
     if($toolActivity -cnotin @('working','hold','idle')){throw 'RC1_TOOL_ACTIVITY_INVALID'}
     Set-DividerWorkState ($toolActivity -ne 'idle')
     $toolFault=[bool]$remoteSnapshot.toolFault
     $remoteLinkState=[string]$remoteSnapshot.state
     $remoteFault=($remoteLinkState -ceq 'Fault')
     $recoveredLink=($remoteLinkState -ceq 'Ready' -and
      $script:ownerLastRemoteLinkState -in @('Fault','Reconnecting','AuthPending','Connecting'))
     if(($script:ownerLastToolFault -and -not $toolFault) -or $recoveredLink){
      Start-DividerRecoveryFlash
     }
     Set-DividerFaultState ($toolFault -or $remoteFault)
     $script:ownerLastToolFault=$toolFault
     $script:ownerLastRemoteLinkState=$remoteLinkState
     $epoch=[long]$remoteSnapshot.logStreamEpoch
     if($epoch -ne $script:ownerLastLogEpoch){
      $script:ownerLastLogEpoch=$epoch
      $script:ownerLastLogCursor=0
      Reset-CompactLogSession
      Add-CompletedEvent $(if($script:ownerObservedMode){
       'RC1: восстановлен обезличенный журнал наблюдения Host.'
      }elseif($script:ownerManagedMode){
       'RC1: восстановлен журнал управляемого Remote из Host.'
      }else{'RC1: синтетический журнал Host.'})
     }
     $lastCursor=[long]$remoteSnapshot.logCursor
     if($lastCursor -lt $script:ownerLastLogCursor){throw 'RC1_LOG_CURSOR_REGRESSED'}
     $hasNewLog=$false
     foreach($entry in @($remoteSnapshot.tail)){
      $line=[string]$entry
      if($line -notmatch '^([0-9]{6,18}) \| '){throw 'RC1_INVALID_LOG_TAIL'}
      $lineCursor=[long]$Matches[1]
      if($lineCursor -le $script:ownerLastLogCursor){continue}
      if($lineCursor -gt $lastCursor){throw 'RC1_LOG_CURSOR_MISMATCH'}
      Add-CompletedEvent (Format-Rc1JournalLine $lineCursor $line.Substring($Matches[0].Length))
      $script:ownerLastLogCursor=$lineCursor
      $hasNewLog=$true
     }
     if($hasNewLog){Render-CompactLog}
     # The Remote store increments its own revision when the connection
     # state changes. Host event sequence is independent and may not move.
     $remoteRevision=[long]$remoteSnapshot.revision
     if([long]$snapshot.revision -ne $script:ownerLastShownRevision -or
        $remoteRevision -ne $script:ownerLastShownRemoteRevision){
      $script:ownerLastShownRevision=[long]$snapshot.revision
      $script:ownerLastShownRemoteRevision=$remoteRevision
      if($script:ownerObservedMode){
       $online=([string]$remoteSnapshot.state -ceq 'Ready')
       $color=if($online){[Drawing.Color]::PaleGreen}elseif([string]$remoteSnapshot.state -ceq 'Fault'){
        [Drawing.Color]::LightCoral
       }else{[Drawing.Color]::Khaki}
       $statusText=if($online){'Remote подключён (наблюдение)'}else{'Remote: '+[string]$remoteSnapshot.state}
       Set-State $statusText ([string]$remoteSnapshot.status+'; управление старой сессией отключено. RC1 ждёт её штатного завершения.') $color
       Set-RuntimeDisplay ('PID '+[string]$remoteSnapshot.processPid) 'Существующая сессия / Adopted' $true
      }elseif($script:ownerManagedMode){
       $connected=([string]$remoteSnapshot.state -ceq 'Ready')
       $color=if($connected){[Drawing.Color]::PaleGreen}elseif([string]$remoteSnapshot.state -ceq 'Fault'){
        [Drawing.Color]::LightCoral
       }else{[Drawing.Color]::Khaki}
       $name=if($connected){'Remote подключён'}elseif([string]$remoteSnapshot.state -ceq 'Disconnected'){
        'Remote отключён'
       }else{'Remote: '+[string]$remoteSnapshot.state}
       Set-State $name ([string]$remoteSnapshot.status) $color
       $script:ownerLastUptimeText=''  # Timer owns the original runtime footer.
       if($script:ownerRemoteBornTicks -le 0){Set-RuntimeDisplay 'PID —' 'Remote отключён' $true}
      }else{
       Set-State 'Remote отключён (RC1)' ('Host: '+[string]$remoteSnapshot.state+'; только синтетические данные.') ([Drawing.Color]::Khaki)
       Set-RuntimeDisplay ('PID '+[string]$snapshot.hostPid) 'Remote НЕ подключён | RC1' $true
      }
      # Authenticated Host supplies only strictly validated startup fields,
      # not raw Remote stdout, tokens or unrecognized device metadata.
      if($script:ownerRealMode){
       $safeUser=''
       $safeDeviceName=''
       $safeDeviceId=''
       if($script:ownerManagedMode -and $snapshot.remoteIdentity){
        $identity=$snapshot.remoteIdentity
        if([string]$identity.user -cmatch '\A[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9.\-]{1,120}\.[A-Za-z]{2,20}\z'){$safeUser=[string]$identity.user}
        if([string]$identity.deviceName -cmatch '\A[\p{L}\p{Nd} _().\-]{1,80}\z'){$safeDeviceName=[string]$identity.deviceName}
        if([string]$identity.deviceId -cmatch '\A[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z'){$safeDeviceId=[string]$identity.deviceId}
       }
       Set-AccountDisplay $safeUser
       $safeState=switch([string]$remoteSnapshot.state){
        'Ready' {'Connected'} 'Connecting' {'Connecting'} 'AuthPending' {'Authenticating'}
        'Reconnecting' {'Reconnecting'} 'Fault' {'Connection fault'}
        'Disconnected' {'Disconnected'} default {'Unknown'}
       }
       $modeLabel=if($script:ownerManagedMode){'Managed: Host-owned Job'}else{'Adopted: read-only'}
       $statusProof=if([string]$remoteSnapshot.state -ceq 'Ready'){
        'Remote connection marker received by Host'
       }else{'Connected state not currently confirmed'}
       $safePid=[int]$remoteSnapshot.processPid
       $safeArt=''
       if($script:ownerManagedMode -and $snapshot.remoteStartupArt){
        $candidateArt=[string]$snapshot.remoteStartupArt
        if($candidateArt.Length -le 1600 -and
           $candidateArt -cmatch '\A[\s\u2500-\u259F\u00A0/\\_|.]+\z'){
         $safeArt=$candidateArt.TrimEnd()
        }
       }
       # The original 1.5.18 RdcLogBox already contains the exact Unicode,
       # glyph and semantic colorizing pipeline. Feed the whole finite pinned
       # Remote startup banner from Host, not a synthetic shortened summary.
       # Host only emits allowlisted startup lines, never subsequent tool calls.
       $safeOriginalHeader=''
       if($script:ownerManagedMode -and $snapshot.remoteStartupHeader){
        $candidateHeader=[string]$snapshot.remoteStartupHeader
        if($candidateHeader.Length -le 8192 -and
           $candidateHeader -cnotmatch '[\x00-\x08\x0B\x0C\x0E-\x1F]' -and
           $candidateHeader -cnotmatch '(?i)Received tool call|Tool call '){
         $safeOriginalHeader=$candidateHeader.TrimEnd()
        }
       }
       if($safeOriginalHeader){
        $script:startupBlock=$safeOriginalHeader
       }else{
        # Before the first real Host log line, retain a minimal truthful
        # fallback, including Adopted/read-only cases with no owned log.
        $script:startupBlock=[string]::Join($nl,@(
         $safeArt,'','Remote Connection','',
         'RDC Relay 1.6.0 RC1 / Desktop Commander 0.2.52','',
         ('Status: '+$(if($safeState -eq 'Connected'){'Online'}else{$safeState})),
         ('- User: '+$(if($safeUser){$safeUser}else{'not reported'})),
         ('- Device Name: '+$(if($safeDeviceName){$safeDeviceName}else{'not reported'})),
         ('- Device ID: '+$(if($safeDeviceId){$safeDeviceId}else{'not reported'})),
         ('Process: '+$(if($safePid -gt 0){'PID '+$safePid}else{'not started'})),
         ('Ownership: '+$modeLabel),
         $statusProof
        ))
       }
       Render-CompactLog
      }
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
       Add-CompletedEvent (Format-Rc1JournalLine ([long]$ev.sequence) ([string]$ev.text))
      }
      $script:ownerNextVerb=if($eventData.moreAvailable){'GET_EVENTS'}else{'GET_SNAPSHOT'}
     }
    }elseif([string]$reply.type -eq 'ACK'){
     if(-not $script:ownerRequestedAction -or
        [string]$reply.payload.action -cne $script:ownerRequestedAction -or
        -not [bool]$reply.payload.success){throw 'RC1_REMOTE_ACK_MISMATCH'}
     Add-CompletedEvent ('Host подтвердил выполнение: '+$script:ownerRequestedAction)
     $script:ownerNextVerb='GET_SNAPSHOT'
    }elseif([string]$reply.type -eq 'NAVIGATION'){
     $route=[string]$reply.payload.route
     $url=[string]$reply.payload.url
     $expectedUrl=switch($script:ownerRequestedNavigation){
      'DEVICE_MANAGEMENT' {'https://mcp.desktopcommander.app/'}
      default {''}
     }
     if(-not $expectedUrl -or $route -cne $script:ownerRequestedNavigation -or
        $url -cne $expectedUrl){throw 'RC1_NAVIGATION_NOT_APPROVED'}
     # Only the exact Host-approved official URL is opened, and only after
     # an explicit owner click. The Remote process is not touched.
     Start-Process -FilePath $url -ErrorAction Stop
     $script:ownerNextVerb='GET_SNAPSHOT'
    }else{throw ('RC1_BAD_OR_DENIED_REPLY_'+[string]$reply.code)}
   }catch{
    $script:ownerNextVerb='GET_SNAPSHOT'
    if($script:ownerRequestedNavigation){
     Set-State 'Операция не выполнена' 'Host отклонил переход или браузер недоступен. Remote не изменён.' ([Drawing.Color]::Khaki)
    }elseif($script:ownerRequestedAction){
     Set-State 'Операция отклонена' ('Host не подтвердил '+$script:ownerRequestedAction+'. Перепроверьте состояние Remote.') ([Drawing.Color]::LightCoral)
    }else{
     # A failed poll invalidates the display revision cache. A subsequent
     # successful snapshot must repaint even when Host state did not change.
     $script:ownerLastShownRevision=-1
     $script:ownerLastShownRemoteRevision=-1
     $script:ownerLastSnapshotUtcTicks=0L
     $script:ownerCanStart=$false
     $script:ownerCanStop=$false
     $script:ownerCanReconnect=$false
     $finish.Enabled=$false
     $reconnectItem.Enabled=$false
     Set-DividerWorkState $false
     Set-State 'Связь с Host' 'IPC временно недоступен; состояние Remote неизвестно, остановка запрещена.' ([Drawing.Color]::Khaki)
    }
   }finally{$script:ownerPending=$null;$script:ownerRequestedNavigation='';$script:ownerRequestedAction=''}
  }
  # Poll only the private, short-lived official snapshot (no credential IO,
  # no network requests on the WinForms UI thread). Expired means unknown.
  if([DateTime]::UtcNow -ge $script:ownerQuotaNextCheckUtc){
   $script:ownerQuotaNextCheckUtc=[DateTime]::UtcNow.AddSeconds(15)
   $quotaText=Get-Rc1QuotaStatus $script:ownerQuotaPath ([string]$script:accountEmail) ([DateTime]::UtcNow)
   if($quotaText -cne $script:ownerLastQuotaText){
    $script:ownerLastQuotaText=$quotaText
    $quotaLabel.Text=$quotaText
    $quotaLabel.ForeColor=if($quotaText -ceq 'Остаток вызовов: 0%'){
     [Drawing.Color]::LightCoral
    }else{[Drawing.Color]::Silver}
   }
  }
  if($script:ownerManagedMode -and $script:ownerRemoteBornTicks -gt 0 -and
     $script:ownerRemotePid -gt 0 -and $script:ownerLastSnapshotUtcTicks -gt 0 -and
     ([DateTime]::UtcNow.Ticks-$script:ownerLastSnapshotUtcTicks) -le 50000000){
   $seconds=[Math]::Max(0,[Math]::Floor(([DateTime]::UtcNow.Ticks-$script:ownerRemoteBornTicks)/10000000.0))
   $uptime='Время работы {0:00}:{1:00}:{2:00}' -f [Math]::Floor($seconds/3600),[Math]::Floor(($seconds%3600)/60),($seconds%60)
   if($uptime -cne $script:ownerLastUptimeText){
    $script:ownerLastUptimeText=$uptime
    Set-RuntimeDisplay ('PID '+[string]$script:ownerRemotePid) $uptime $true
   }
  }
  if(-not $script:ownerPending -and -not $form.IsDisposed){
   # One shared sequence and one in-flight IPC call: a user menu action can
   # never overtake the background state/event poll and be rejected as replay.
   $navigation=[string]$script:ownerQueuedNavigation
   $action=[string]$script:ownerQueuedAction
   $verb=if($action){'REMOTE_ACTION'}elseif($navigation){'OPEN_EXTERNAL'}else{$script:ownerNextVerb}
   $script:ownerRequestedNavigation=$navigation
   $script:ownerRequestedAction=$action
   $script:ownerQueuedNavigation=''
   $script:ownerQueuedAction=''
   $script:ownerRequestSequence++
   $packet=[RdcOwnerWire]::Decode([RdcOwnerWire]::Request($verb,$script:ownerNonce,
     $script:ownerGeneration,[long]$script:ownerEventCursor,$null,[long]$script:ownerRequestSequence))
   if($navigation){$packet['navigation']=$navigation}
   if($action){$packet['action']=$action;$packet['userConfirmed']='YES'}
   $wire=[RdcOwnerWire]::Json.Serialize($packet)
   $timeout=if($action){15000}else{800}
   $script:ownerPending=[RdcOwnerWire]::CallBackground($script:ownerPipe,
    $script:ownerIdentity,$wire,$timeout)
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
