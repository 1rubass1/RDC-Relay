# RDC Relay 1.6 RC1 product GUI attach path.
# Dot-sourced ONLY from Source/remote-window.ps1 -OwnerGui.
# Reuses the original complete WinForms window, controls, geometry and renderer.
# Adopted/Unknown Remote is immutable. Managed-mode Remote actions are
# executed exclusively by the authenticated persistent Host after explicit UI.
# The RC1 Host streams monotonic, sanitized event IDs. Show only the
# fixed-width sequence and a Unicode status, never the Host/Remote prefix.
# This formatter never receives raw Remote stdout, credentials or tool args.
# Single action vocabulary for start, complete and failure, including
# unpaired pinned Remote 0.2.52 markers. The phase is carried by the icon.
# Journal translation is presentation-only: never change tool verbs, markers, subjects or sequences.
# Tests which run this formatter without a GUI resource catalog retain exact Russian output.
function Get-Rc1JournalUiText([string]$key,[string]$fallback) {
 if(-not $script:ownerUiTexts){return $fallback}
 return Get-RdcOwnerUiText $key $fallback
}
function Get-Rc1ToolAction([string]$tool) {
 switch -CaseSensitive ($tool) {
  'read_file' {(Get-Rc1JournalUiText 'journal.tool.readFile' 'Чтение файла');break}
  'read_multiple_files' {(Get-Rc1JournalUiText 'journal.tool.readMultipleFiles' 'Чтение файлов');break}
  'write_file' {(Get-Rc1JournalUiText 'journal.tool.writeFile' 'Запись файла');break}
  'edit_block' {(Get-Rc1JournalUiText 'journal.tool.editFile' 'Изменение файла');break}
  'list_directory' {(Get-Rc1JournalUiText 'journal.tool.listDirectory' 'Просмотр папки');break}
  'get_file_info' {(Get-Rc1JournalUiText 'journal.tool.fileInfo' 'Сведения о файле');break}
  'start_process' {(Get-Rc1JournalUiText 'journal.tool.startProcess' 'Запуск программы');break}
  'read_process_output' {(Get-Rc1JournalUiText 'journal.tool.processOutput' 'Вывод процесса');break}
  'interact_with_process' {(Get-Rc1JournalUiText 'journal.tool.processInput' 'Ввод в процесс');break}
  'list_processes' {(Get-Rc1JournalUiText 'journal.tool.listProcesses' 'Просмотр процессов');break}
  'start_search' {(Get-Rc1JournalUiText 'journal.tool.search' 'Поиск');break}
  'get_more_search_results' {(Get-Rc1JournalUiText 'journal.tool.searchResults' 'Результаты поиска');break}
  'stop_search' {(Get-Rc1JournalUiText 'journal.tool.stopSearch' 'Остановка поиска');break}
  'move_file' {(Get-Rc1JournalUiText 'journal.tool.moveFile' 'Перемещение файла');break}
  'create_directory' {(Get-Rc1JournalUiText 'journal.tool.createDirectory' 'Создание папки');break}
  'get_config' {(Get-Rc1JournalUiText 'journal.tool.settings' 'Настройки');break}
  default {(Get-Rc1JournalUiText 'journal.tool.operation' 'Операция')}
 }
}
function Format-Rc1JournalLine([long]$number,[string]$message) {
 if($number -lt 0){throw 'RC1_JOURNAL_NEGATIVE_SEQUENCE'}
 $text=([string]$message).Trim()
 $gutter=$number.ToString('D6',[Globalization.CultureInfo]::InvariantCulture)+' │ '
 $unknown=Get-Rc1JournalUiText 'journal.target.unknown' 'без уточнения'
 # Exactly one readable "action → subject" scheme for all tool phases.
 # Never echo unvalidated raw log arguments or private identifiers.
 if($text -cmatch '\ARemote tool (started|completed|failed)\|([1-9][0-9]{0,11})\|([a-z][a-z0-9_]{1,39})\|([\p{L}\p{Nd}_ .()\-]{0,64})\z'){
  $phase=[string]$Matches[1]
  $operation=[long]$Matches[2]
  $tool=[string]$Matches[3]
  $target=[string]$Matches[4]
  $action=Get-Rc1ToolAction $tool
  # A completed start_process MCP call acknowledges the start request,
  # NOT the later exit or ultimate success of the OS process.
  if($phase -ceq 'completed' -and $tool -ceq 'start_process'){
   $action=Get-Rc1JournalUiText 'journal.tool.startRequest' 'Запрос запуска программы'
  }
  $icon=switch -Exact ($phase) {
   'started' {'🔧';break}
   'completed' {'✅';break}
   'failed' {'❌';break}
  }
  if(-not $target){$target=$unknown}
  return $operation.ToString('D6',[Globalization.CultureInfo]::InvariantCulture)+
   ' │ '+$icon+' '+$action+' → '+$target
 }
 # Method-name completion is ambiguous when same-type calls overlap:
 # make the missing subject explicit rather than inventing correlation.
 if($text -cmatch '\ARemote tool (completed|failed): ([a-z][a-z0-9_]{1,39})\z'){
  $phase=[string]$Matches[1];$tool=[string]$Matches[2]
  $icon=if($phase -ceq 'completed'){'✅'}else{'❌'}
  $action=Get-Rc1ToolAction $tool
  if($phase -ceq 'completed' -and $tool -ceq 'start_process'){
   $action=Get-Rc1JournalUiText 'journal.tool.startRequest' 'Запрос запуска программы'
  }
  return $gutter+$icon+' '+$action+' → '+$unknown
 }
 # Fail closed for malformed rich tool data.
 if($text.StartsWith('Remote tool ',[StringComparison]::Ordinal) -and $text.Contains('|')){
  return $gutter+(Get-Rc1JournalUiText 'journal.event.toolUnspecifiedPrefix' '• Событие инструмента → ')+$unknown
 }
 if($text -cmatch '\ARemote tool started: ([a-z][a-z0-9_]{1,39})\z'){
  return $gutter+'🔧 '+(Get-Rc1ToolAction ([string]$Matches[1]))+' → '+$unknown
 }
 switch -CaseSensitive ($text) {
  'Remote tool started' {return $gutter+'🔧 '+(Get-Rc1JournalUiText 'journal.tool.operation' 'Операция')+' → '+$unknown}
  'Remote tool completed' {return $gutter+'✅ '+(Get-Rc1JournalUiText 'journal.tool.operation' 'Операция')+' → '+$unknown}
  'Remote tool failed' {return $gutter+'❌ '+(Get-Rc1JournalUiText 'journal.tool.operation' 'Операция')+' → '+$unknown}
  'Remote connected' {return $gutter+(Get-Rc1JournalUiText 'journal.event.remoteConnected' '🔌 Remote → подключён')}
  'Authentication pending' {return $gutter+(Get-Rc1JournalUiText 'journal.event.authenticationPending' '⏳ Авторизация → ожидание')}
  'Remote channel unavailable' {return $gutter+(Get-Rc1JournalUiText 'journal.event.channelUnavailable' '❌ Канал Remote → недоступен')}
  'Remote start failed' {return $gutter+(Get-Rc1JournalUiText 'journal.event.remoteStartFailed' '❌ Запуск Remote → ошибка')}
  'Local MCP recovering' {return $gutter+(Get-Rc1JournalUiText 'journal.event.mcpRecovering' '⏳ MCP → восстановление')}
  'Remote launcher replaced' {return $gutter+(Get-Rc1JournalUiText 'journal.event.remoteReplaced' '🔌 Сессия Remote → обновлена')}
  default {return $gutter+(Get-Rc1JournalUiText 'journal.event.genericPrefix' '• Событие → ')+$text}
 }
}
# Separate, bounded diagnostic history for Help -> Show Journal. Unlike the
# lower activity pane it retains 512 recent sanitized entries, each tagged
# with its *GUI receipt time* (not an invented Remote execution timestamp).
# Raw Remote stdout, private paths and tool arguments never reach this data.
function Add-Rc1OwnerDetailedEvent([string]$origin,[string]$entry) {
 if($origin -cnotin @('Remote','Host')){return}
 if([string]::IsNullOrWhiteSpace($entry)){return}
 if($entry.Length -gt 320 -or $entry.Contains("`r") -or $entry.Contains("`n")){return}
 if($entry -match '(?i)([A-Za-z]:\\|\\\\|https?://|@|authorization:\s*bearer|password\s*[=:]|api[_-]?key\s*[=:]|private[_-]?key\s*[=:])'){return}
 if(-not $script:ownerDetailedJournal){
  $script:ownerDetailedJournal=New-Object 'System.Collections.Generic.List[string]'
 }
 $received=[DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss.fff',
  [Globalization.CultureInfo]::InvariantCulture)
 [void]$script:ownerDetailedJournal.Add(
  '['+$received+' UTC / '+(Get-Rc1JournalUiText 'journal.receipt.received' 'получено')+'] ['+$origin+'] '+$entry)
 while($script:ownerDetailedJournal.Count -gt 512){
  $script:ownerDetailedJournal.RemoveAt(0)
 }
}
# These are the original, allowlisted Remote startup lines from Host. Only
# Owner GUI's display copy is adapted: the source log and IPC snapshot remain
# unchanged for evidence/provenance, and legacy 1.5.18 rendering is untouched.
function Convert-Rc1OwnerStartupInstructions([string]$header) {
 if([string]::IsNullOrEmpty($header)){return $header}
 $terminalKeep='Keep this Terminal running. You can minimize it.'
 $terminalStop='Press Ctrl+C to disconnect.'
 $ownerKeep=Get-Rc1JournalUiText 'journal.banner.keepRunning' 'You can close this window; RDC Relay continues running in the system tray.'
 $ownerStop=Get-Rc1JournalUiText 'journal.banner.stopRemote' 'Click Stop to disconnect Remote.'
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
# User-only opt-out of the existing automatic quota client. No OAuth secret
# is stored here; absence of a marker means the historical default: ON.
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
function Set-Rc1QuotaDisplayEnabled([string]$path,[bool]$enabled) {
 if([string]::IsNullOrWhiteSpace($path)){throw 'RC1_QUOTA_SETTING_PATH_REQUIRED'}
 $dir=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
 if(-not $dir){throw 'RC1_QUOTA_SETTING_PARENT_REQUIRED'}
 # The historical behavior is ON; only an explicit opt-out is stored.
 if($enabled){
  if([IO.File]::Exists($path)){
   if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RC1_QUOTA_SETTING_REPARSE_DENIED'}
   [IO.File]::Delete($path)
  }
  if([IO.File]::Exists($path)){throw 'RC1_QUOTA_SETTING_ENABLE_FAILED'}
  return
 }
 if(-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
 if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RC1_QUOTA_SETTING_REPARSE_DENIED'}
 $temp=Join-Path $dir ('quota-display-'+[Guid]::NewGuid().ToString('N')+'.tmp')
 $backup=Join-Path $dir ('quota-display-'+[Guid]::NewGuid().ToString('N')+'.bak')
 try {
  [IO.File]::WriteAllText($temp,'disabled-v1',(New-Object Text.UTF8Encoding($false)))
  if([IO.File]::Exists($path)){
   if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RC1_QUOTA_SETTING_REPARSE_DENIED'}
   [IO.File]::Replace($temp,$path,$backup)
  }else{[IO.File]::Move($temp,$path)}
  if([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -cne 'disabled-v1'){
   throw 'RC1_QUOTA_SETTING_VERIFY_FAILED'
  }
 }finally{
  if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
  if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
 }
}
# A read-only, expiring private snapshot from an authorized official
# Remote Desktop Commander who_am_i call. The Windows device-agent's OAuth
# credentials are NOT reused: they are not the ChatGPT/hosted MCP client grant.
# If no fresh service-provided snapshot is present, show an honest dash.
function Get-Rc1QuotaStatus([string]$path,[string]$expectedEmail,[DateTime]$nowUtc,$percentOut=$null) {
 $missing='Остаток вызовов: --%'
 if($null -ne $percentOut){$percentOut.Value=$null}
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
  if($null -ne $percentOut){$percentOut.Value=$n}
  return ('Остаток вызовов: '+$n+'%')
 }catch{return $missing}
}
# RC1 Owner-only presentation: translate the six Host state codes into a
# short Russian title, with an independent, allowlisted explanation underneath.
# Never render raw Host status/diagnostics or alter the actual Remote state.
function Get-Rc1OwnerCompletionKind([string]$value) {
 if($value -cin @('preflight_failed','launch_failed','exit_before_ready','startup_stop_requested',
    'authorization_stop_requested','stop_requested_after_ready','unexpected_after_ready')){return $value}
 return 'unknown'
}
function Get-Rc1OwnerConnectionText([string]$state,[string]$detail,[bool]$observed,[string]$activity='idle',[string]$completion='unknown') {
 # Presentation only: Host retains its technical state and permissions.
 if(-not $observed -and $state -ceq 'Disconnected'){
  switch -CaseSensitive (Get-Rc1OwnerCompletionKind $completion){
   'exit_before_ready' {return @{Name=(Get-RdcOwnerUiText 'owner.connection.name.fault' 'Ошибка связи');Detail=(Get-RdcOwnerUiText 'owner.completion.beforeReady' 'Remote завершился до подключения');CompletionFault=$true}}
   'unexpected_after_ready' {return @{Name=(Get-RdcOwnerUiText 'owner.connection.name.fault' 'Ошибка связи');Detail=(Get-RdcOwnerUiText 'owner.completion.unexpected' 'Remote неожиданно завершился');CompletionFault=$true}}
   'launch_failed' {return @{Name=(Get-RdcOwnerUiText 'owner.connection.name.fault' 'Ошибка связи');Detail=(Get-RdcOwnerUiText 'owner.connection.detail.fault.start' 'Не удалось запустить Remote');CompletionFault=$true}}
   'authorization_stop_requested' {return @{Name=(Get-RdcOwnerUiText 'owner.connection.name.disconnected' 'Отключён');Detail=(Get-RdcOwnerUiText 'owner.completion.authStopped' 'Остановка при авторизации')}}
   'startup_stop_requested' {return @{Name=(Get-RdcOwnerUiText 'owner.connection.name.disconnected' 'Отключён');Detail=(Get-RdcOwnerUiText 'owner.completion.startStopped' 'Запуск остановлен')}}
   'stop_requested_after_ready' {return @{Name=(Get-RdcOwnerUiText 'owner.connection.name.disconnected' 'Отключён');Detail=''}}
  }
 }

 # Quietness is not a positive proof of connectivity, nor a recovery event.
 # This trusted Host reason is display-only: never promote technical Ready.
 if(-not $observed -and $state -ceq 'Reconnecting' -and
    $detail -ceq 'Remote channel unconfirmed; awaiting new connectivity evidence'){
  return @{
   Name=(Get-RdcOwnerUiText 'owner.connection.name.ready' 'Подключён')
   Detail=$(if($activity -ceq 'working'){Get-RdcOwnerUiText 'owner.connection.detail.working' 'Выполнение запроса'}else{Get-RdcOwnerUiText 'owner.connection.detail.waiting' 'Ожидание запроса'})
   Waiting=$true
  }
 }
 $name=switch -CaseSensitive ($state) {
  'Ready' {(Get-RdcOwnerUiText 'owner.connection.name.ready' 'Подключён');break}
  'Connecting' {(Get-RdcOwnerUiText 'owner.connection.name.connecting' 'Подключение');break}
  'AuthPending' {(Get-RdcOwnerUiText 'owner.connection.name.connecting' 'Подключение');break}
  'Reconnecting' {(Get-RdcOwnerUiText 'owner.connection.name.reconnecting' 'Восстановление');break}
  'Fault' {(Get-RdcOwnerUiText 'owner.connection.name.fault' 'Ошибка связи');break}
  'Disconnected' {(Get-RdcOwnerUiText 'owner.connection.name.disconnected' 'Отключён');break}
  default {(Get-RdcOwnerUiText 'owner.connection.name.unknown' 'Состояние неизвестно')}
 }
 $info=switch -CaseSensitive ($state) {
  'Ready' {
   if($observed){(Get-RdcOwnerUiText 'owner.connection.detail.ready.observed' 'Только наблюдение')}
   elseif($detail -ceq 'Successful Remote tool call confirmed connectivity'){
    (Get-RdcOwnerUiText 'owner.connection.detail.ready.toolConfirmed' 'Ожидание запроса')
   }else{(Get-RdcOwnerUiText 'owner.connection.detail.ready.managed' 'Ожидание запроса')}
   break
  }
  'Connecting' {
   if($observed){(Get-RdcOwnerUiText 'owner.connection.detail.connecting.observed' 'Проверка существующего подключения')}
   elseif($detail -ceq 'Starting pinned Desktop Commander Remote'){
    (Get-RdcOwnerUiText 'owner.connection.detail.connecting.starting' 'Запуск Remote')
   }else{(Get-RdcOwnerUiText 'owner.connection.detail.connecting.waiting' 'Установление связи')}
   break
  }
  'AuthPending' {
   if($observed){(Get-RdcOwnerUiText 'owner.connection.detail.auth.observed' 'Ожидание подтверждения; только наблюдение')}
   elseif($detail -ceq 'Official device logout in progress'){
    (Get-RdcOwnerUiText 'owner.connection.detail.auth.logout' 'Выход из аккаунта')
   }else{(Get-RdcOwnerUiText 'owner.connection.detail.auth.verifyDevice' 'Ожидание подтверждения')}
   break
  }
  'Reconnecting' {
   if($observed){(Get-RdcOwnerUiText 'owner.connection.detail.reconnecting.observed' 'Проверка связи; только наблюдение')}
   else{(Get-RdcOwnerUiText 'owner.connection.detail.reconnecting.managed' 'Восстановление связи')}
   break
  }
  'Fault' {
   if($observed){(Get-RdcOwnerUiText 'owner.connection.detail.fault.observed' 'Сессия недоступна')}
   else{
    switch -CaseSensitive ($detail) {
     'Remote channel unavailable' {(Get-RdcOwnerUiText 'owner.connection.detail.fault.channel' 'Канал недоступен');break}
     'Remote start failed' {(Get-RdcOwnerUiText 'owner.connection.detail.fault.start' 'Не удалось запустить Remote');break}
     'Required Node.js runtime is missing; run RDC Relay Setup' {(Get-RdcOwnerUiText 'owner.connection.detail.fault.nodeMissing' 'Требуется повторная установка RDC Relay');break}
     'Remote startup failed; inspect Host status and retry manually' {
      (Get-RdcOwnerUiText 'owner.connection.detail.fault.autoStart' 'Запустите Remote вручную');break
     }
     'Account switch refused; owned Remote remains stopped' {
      (Get-RdcOwnerUiText 'owner.connection.detail.fault.switchRefused' 'Смена аккаунта отклонена; Remote остановлен');break
     }
     'Authorization revoked; Remote restart failed' {
      (Get-RdcOwnerUiText 'owner.connection.detail.fault.authRevoked' 'Авторизация отозвана; запуск не удался');break
     }
     'Logout not confirmed; Remote remains stopped' {
      (Get-RdcOwnerUiText 'owner.connection.detail.fault.logoutUnconfirmed' 'Выход не подтверждён; Remote остановлен');break
     }
     default {(Get-RdcOwnerUiText 'owner.connection.detail.fault.generic' 'Подробности в журнале')}
    }
   }
   break
  }
  'Disconnected' {
   if($observed){(Get-RdcOwnerUiText 'owner.connection.detail.disconnected.observed' 'Предыдущая сессия завершена')}
   else{
    switch -CaseSensitive ($detail) {
     'Host-owned Remote stopped' {'';break}
     'Host-owned Remote process exited' {(Get-RdcOwnerUiText 'owner.connection.detail.disconnected.processExited' 'Remote завершил работу');break}
     'Previous Remote exited; RC1 Host preparing a new managed session' {
      (Get-RdcOwnerUiText 'owner.connection.detail.disconnected.newSession' 'Подготовка к запуску');break
     }
     'Waiting for the previous Remote and shell to exit; no duplicate launched' {
      (Get-RdcOwnerUiText 'owner.connection.detail.disconnected.waitingOld' 'Ожидание завершения сессии');break
     }
     'RC1 Host ready to start pinned Remote' {'';break}
     default {''}
    }
   }
   break
  }
  default {(Get-RdcOwnerUiText 'owner.connection.detail.unknown' 'Состояние уточняется')}
 }
 if(-not $observed -and $state -ceq 'Ready' -and $activity -ceq 'working'){
  $info=Get-RdcOwnerUiText 'owner.connection.detail.working' 'Выполнение запроса'
 }
 return @{Name=[string]$name;Detail=[string]$info}
}
# Display-only localization. Remote ownership, IPC verbs and historical logs are unchanged.
function Get-RdcOwnerUiText([string]$key,[string]$fallback){
 return [RdcUiLanguage]::Text($script:ownerUiTexts,$key,$fallback)
}
function Apply-RdcOwnerLocale([switch]$Force){
 $locale=[RdcUiLanguage]::Current
 if(-not $Force -and $script:ownerUiLocale -ceq $locale){return}
 $script:ownerUiLocale=$locale
 $script:ownerUiTexts=[RdcUiLanguage]::LoadResources($root,$locale)
 $script:ownerLastQuotaText=''
 $script:ownerQuotaNextCheckUtc=[DateTime]::MinValue
 $script:ownerLastUptimeText=''
 # Locale selection is tray-only; the existing preference poll repaints this GUI.
 # Repaint update notice text only; do not rerun version checks or animation.
 if(Get-Command Refresh-RdcOwnerUpdateNoticeLanguage -CommandType Function -ErrorAction SilentlyContinue){
  Refresh-RdcOwnerUpdateNoticeLanguage
 }
 $accountButton.Text=Get-RdcOwnerUiText 'gui.menu.account' 'Аккаунт'
 $switchAccountItem.Text=Get-RdcOwnerUiText 'gui.menu.switchAccount' 'Сменить аккаунт…'
 $reconnectItem.Text=Get-RdcOwnerUiText 'tray.menu.reconnect' 'Переподключить'
 $devicesItem.Text=Get-RdcOwnerUiText 'gui.menu.devices' 'Управление устройствами…'
 $autoConnectAuthItem.Text=Get-RdcOwnerUiText 'tray.menu.autoConnect' 'Автоподключение'
 $autoConnectAuthItem.AccessibleDescription=Get-RdcOwnerUiText 'tray.menu.autoConnectTooltip' 'Запуск Remote при следующем запуске RDC Relay.'
 $quotaAuthItem.Text=Get-RdcOwnerUiText 'tray.menu.showRemainingCalls' 'Выводить остаток вызовов'
 $quotaAuthItem.AccessibleDescription=Get-RdcOwnerUiText 'gui.menu.quotaDesc' 'Флажок: включить или выключить автоматическое отображение остатка вызовов.'
 # No duplicate program settings in the account menu.
 $helpButton.AccessibleName=Get-RdcOwnerUiText 'gui.help.accessible' 'Справка / О программе'
 $tip.SetToolTip($accountButton,(Get-RdcOwnerUiText 'gui.account.tooltip' 'Действия с аккаунтом'))
 $tip.SetToolTip($accountInfo,(Get-RdcOwnerUiText 'gui.account.infoTooltip' 'Аккаунт Desktop Commander, к которому привязан этот компьютер'))
 $tip.SetToolTip($helpButton,(Get-RdcOwnerUiText 'gui.help.accessible' 'Справка / О программе'))
 # Do not replace a verified email; only the unknown-account placeholder
 # is re-rendered on locale change without a Remote or Host request.
 if(-not $script:accountEmail){Set-AccountDisplay $null}
 if($script:ownerObservedMode){
  $form.Text=Get-RdcOwnerUiText 'gui.title.observedRemote' 'RDC Relay 1.6.0 RC1 — существующий Remote (только чтение)'
 }elseif($script:ownerManagedMode){
  $form.Text=Get-RdcOwnerUiText 'gui.title.managedRemote' 'RDC Relay 1.6.0 RC1 — управляемый Host/GUI'
 }else{
  $form.Text=Get-RdcOwnerUiText 'gui.title.testMode' 'RDC Relay 1.6.0 RC1 — Remote не подключён (режим проверки)'
 }
 $finish.AccessibleDescription=if($script:ownerManagedMode){
  Get-RdcOwnerUiText 'gui.tooltip.ownedRemoteOnly' 'Запуск или остановка только Remote, принадлежащего текущему Host.'
 }else{
  Get-RdcOwnerUiText 'gui.tooltip.unownedRemote' 'Управление существующим Remote недоступно: сессия не принадлежит RC1.'
 }
 $tip.SetToolTip($finish, $(if($script:ownerManagedMode){
  Get-RdcOwnerUiText 'gui.tooltip.manageOwnedRemote' 'Управление только собственным Remote этого Host.'
 }else{
  Get-RdcOwnerUiText 'gui.tooltip.legacyRemote' 'Существующий Remote принадлежит старой оболочке. После её штатного завершения RC1 создаст новую управляемую сессию.'
 }))
 $accountButton.AccessibleDescription=Get-RdcOwnerUiText 'gui.accessibility.accountDeviceManagement' 'Аккаунт: переход к управлению устройствами без изменения Remote.'
 # Re-render only the last validated Host status; never re-read provider text or IPC.
 if($script:ownerLastSafePresentation){
  $safe=$script:ownerLastSafePresentation
  $localized=Get-Rc1OwnerConnectionText ([string]$safe.State) ([string]$safe.Detail) ([bool]$safe.Observed) ([string]$safe.Activity) ([string]$safe.Completion)
  Set-State $localized.Name $localized.Detail $safe.Color
 }
 # The already-authorized periodic GET_SNAPSHOT rebuilds the sanitized fallback
 # banner on locale change. No extra Remote action or forced vendor parsing.
 if($script:ownerRealMode){
  $script:ownerLastShownRevision=-1
  $script:ownerLastShownRemoteRevision=-1
 }
}
function Set-RdcOwnerLocalizedFinishLabel {
 # Only the validated Host capability determines Start/Stop; never caption text.
 $expected=if($script:ownerCanStop){
  Get-RdcOwnerUiText 'tray.menu.stop' 'Остановить'
 }else{
  Get-RdcOwnerUiText 'tray.menu.start' 'Запустить'
 }
 if($finish.Text -cne $expected){$finish.Text=$expected}
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
 Add-Type -Path @((Join-Path $root 'RdcOwnerWire.cs'),(Join-Path $root 'RdcUiLanguage.cs')) -ReferencedAssemblies @(
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
 # Only the authenticated current Host run may supply a raw Remote log.
 $script:ownerRawLogRunRoot=$run
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
 $quotaAuthItem.Enabled=$script:ownerManagedMode
 $autoConnectAuthItem.Enabled=$script:ownerManagedMode
 $accountMenu.Add_Opening({
  $autoConnectAuthItem.Checked=[RdcOwnerAutoConnectPreference]::Enabled([RdcOwnerAutoConnectPreference]::CurrentPath)
 })
 $autoConnectAuthItem.Add_Click({
  if(-not $script:ownerManagedMode){return}
  try{
   [RdcOwnerAutoConnectPreference]::Set([RdcOwnerAutoConnectPreference]::CurrentPath,[bool]$autoConnectAuthItem.Checked)
  }catch{
   $autoConnectAuthItem.Checked=[RdcOwnerAutoConnectPreference]::Enabled([RdcOwnerAutoConnectPreference]::CurrentPath)
   [void][Windows.Forms.MessageBox]::Show((Get-RdcOwnerUiText 'tray.notice.autoConnectSaveFailed' 'Не удалось сохранить настройку автоподключения.'),
      'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
  }
 })
 $accountButton.AccessibleDescription='Аккаунт: переход к управлению устройствами без изменения Remote.'
 # Handshake capability values must be validated before any binding.
 $initialCapabilities=$handshake.payload.capabilities
 if(-not $initialCapabilities){throw 'RC1_OWNER_CAPABILITIES_MISSING'}
 $script:ownerCanSwitchAccount=[bool]$initialCapabilities.switchAccount
 $switchAccountItem.Enabled=$script:ownerCanSwitchAccount
 $reconnectItem.Enabled=$false
 $devicesItem.Enabled=[bool]$initialCapabilities.deviceManagementLink
 $verifyDeviceItem.Enabled=$false # RC1 manual verification removed
 $script:ownerJournalAllowed=[bool]$initialCapabilities.sanitizedJournal
 # G121 removed the Help context menu and $openLogItem. The About dialog
 # now creates its own "Показать журнал" control over sanitized Owner events.
 # Never access an obsolete control here: this prevented Owner GUI startup.
 $helpButton.Enabled=$true
 # UI language lives in an independent per-user preference; never in IPC or Remote auth.
 $script:ownerUiLocale=''
 $script:ownerUiTexts=$null
 $script:ownerLastSafePresentation=$null
 $script:ownerLocaleNextCheckUtc=[DateTime]::MinValue
 # Language changes are persisted by the native tray menu, not by account controls.
 Apply-RdcOwnerLocale -Force
 $script:ownerCloseGeneration=[int]$handshake.payload.closeGeneration
 $script:ownerEventCursor=0
  $script:ownerTrayHelpSeenSequence=0
 $script:ownerNextVerb='GET_SNAPSHOT'
 $script:ownerPending=$null
 $script:ownerQueuedNavigation=''
 $script:ownerRequestedNavigation=''
 $script:ownerQueuedAction=''
 $script:ownerRequestedAction=''
 $script:ownerStatus=if($script:ownerObservedMode){'OBSERVED_READ_ONLY_RC1'}elseif($script:ownerManagedMode){'MANAGED_OWNER_RC1'}else{'FAKE_ONLY_RC1'}
 $script:ownerLastShownRevision=-1
 $script:ownerLastShownRemoteRevision=-1
 $script:ownerLastShownToolActivity=''
 $script:ownerRemoteBornTicks=0
 $script:ownerLastSnapshotUtcTicks=0
 $script:ownerRemotePid=0
 $script:ownerLastUptimeText=''
 $script:ownerQuotaPath=Join-Path (Join-Path $env:LOCALAPPDATA 'RDCRelayOwnerPilot') 'remote-usage-cache.json'
 $script:ownerQuotaEnabledPath=Join-Path (Join-Path $env:LOCALAPPDATA 'RDCRelayOwnerPilot') 'quota-display.opt-in'
 $quotaAuthItem.Checked=[bool](Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath)
 $script:ownerQuotaNextCheckUtc=[DateTime]::MinValue
 $script:ownerLastQuotaText=''
 $script:ownerLastLogCursor=0
 $script:ownerLastLogEpoch=-1
 $script:ownerDetailedJournal=New-Object 'System.Collections.Generic.List[string]'
 $script:ownerRecentDiagnostics=@()
 $script:ownerAttemptDiagnostics=@()
 $script:ownerJournalRemoteState='Unknown'
 $script:ownerJournalRemotePid=0
 $script:ownerJournalOwnership='Unknown'
 $script:ownerJournalToolActivity='idle'
 $script:ownerJournalLastSnapshotUtc=[DateTime]::MinValue
 # Owner-only compact activity journal; legacy 1.5.18 renderer remains spaced.
 $script:ownerCompactJournal=$true
 $script:ownerLastJournalCapacity=-1
 $script:ownerLastToolFault=$false
 $script:ownerLastRemoteLinkState=''
 if($script:ownerObservedMode){
  Set-State (Get-RdcOwnerUiText 'owner.initial.observedName' 'Подключение') (Get-RdcOwnerUiText 'owner.initial.observedDetail' 'Проверка существующего подключения') ([Drawing.Color]::Khaki)
  Set-RuntimeDisplay ('PID '+[string]$ticket.hostPid) (Get-RdcOwnerUiText 'owner.runtime.adopted' 'Remote: существующая сессия / Adopted') $true
  Add-CompletedEvent (Get-RdcOwnerUiText 'owner.initial.observedEvent' 'RC1 подключён к работающему Desktop Commander Remote только для наблюдения. X закрывает GUI; Remote не затрагивается.')
 }elseif($script:ownerManagedMode){
  Set-FinishButtonMode $false
  $finish.Enabled=[bool]$initialCapabilities.startRemote
  $script:ownerCanStart=[bool]$initialCapabilities.startRemote
  $script:ownerCanStop=$false
  $script:ownerCanReconnect=$false
  Set-State (Get-RdcOwnerUiText 'owner.initial.managedName' 'Отключён') '' ([Drawing.Color]::Gray)
  Set-RuntimeDisplay ('PID '+[string]$ticket.hostPid) (Get-RdcOwnerUiText 'owner.runtime.managedWaiting' 'Remote: Host-owned / ожидание запуска') $true
  Add-CompletedEvent (Get-RdcOwnerUiText 'owner.initial.managedEvent' 'RDC Relay RC1: управление Remote выполняет постоянный Host. X закрывает только это окно.')
 }else{
  Set-State (Get-RdcOwnerUiText 'owner.initial.fakeName' 'Тестовый режим') (Get-RdcOwnerUiText 'owner.initial.fakeDetail' 'Нет активной сессии Remote') ([Drawing.Color]::Khaki)
  Set-RuntimeDisplay ('PID '+[string]$ticket.hostPid) (Get-RdcOwnerUiText 'owner.runtime.fakeHost' 'Тестовый Host / Remote не подключён') $true
  Add-CompletedEvent (Get-RdcOwnerUiText 'owner.initial.fakeEvent' 'RDC Relay 1.6.0 RC1. Host использует синтетическое состояние; настоящий Remote не запущен.')
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
     $script:ownerJournalAllowed=[bool]$snapshot.capabilities.sanitizedJournal
     $script:ownerCanSwitchAccount=[bool]$snapshot.capabilities.switchAccount
     $switchAccountItem.Enabled=$script:ownerCanSwitchAccount
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
     # Read-only Host diagnostic tail is distinct from compact tool rows.
     $script:ownerJournalRemoteState=[string]$remoteSnapshot.state
     $script:ownerJournalRemotePid=[int]$remoteSnapshot.processPid
     $script:ownerJournalOwnership=[string]$remoteSnapshot.ownership
     $script:ownerJournalToolActivity=[string]$remoteSnapshot.toolActivity
     $script:ownerJournalLastSnapshotUtc=[DateTime]::UtcNow
     $completion=Get-Rc1OwnerCompletionKind ([string]$snapshot.remoteCompletionKind)
     $script:ownerAttemptDiagnostics=if($script:ownerManagedMode){@($snapshot.remoteAttemptDiagnostics | Select-Object -First 22)}else{@()}
     $script:ownerRecentDiagnostics=@($remoteSnapshot.diagnostics |
       Where-Object{
        $v=[string]$_
        $v.Length -gt 0 -and $v.Length -le 140 -and
        $v -notmatch '[\r\n\x00-\x1F]' -and
        $v -notmatch '(?i)(authorization:\s*bearer|password\s*[=:]|api[_-]?key\s*[=:]|private[_-]?key\s*[=:])'
       })
     $epoch=[long]$remoteSnapshot.logStreamEpoch
     if($epoch -ne $script:ownerLastLogEpoch){
      $script:ownerLastLogEpoch=$epoch
      $script:ownerLastLogCursor=0
      Add-Rc1OwnerDetailedEvent 'Host' ((Get-Rc1JournalUiText 'journal.synthetic.streamEpochPrefix' 'Поток событий Remote: эпоха ')+[string]$epoch)
      Reset-CompactLogSession
      Add-CompletedEvent $(if($script:ownerObservedMode){
       Get-Rc1JournalUiText 'journal.synthetic.observedRestore' 'RC1: восстановлен обезличенный журнал наблюдения Host.'
      }elseif($script:ownerManagedMode){
       Get-Rc1JournalUiText 'journal.synthetic.managedRestore' 'RC1: восстановлен журнал управляемого Remote из Host.'
      }else{Get-Rc1JournalUiText 'journal.synthetic.fakeJournal' 'RC1: синтетический журнал Host.'})
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
      $formatted=Format-Rc1JournalLine $lineCursor $line.Substring($Matches[0].Length)
      Add-CompletedEvent $formatted
      Add-Rc1OwnerDetailedEvent 'Remote' $formatted
      $script:ownerLastLogCursor=$lineCursor
      $hasNewLog=$true
     }
     if($hasNewLog){Render-CompactLog}
     # The Remote store increments its own revision when the connection
     # state changes. Host event sequence is independent and may not move.
     $remoteRevision=[long]$remoteSnapshot.revision
     if([long]$snapshot.revision -ne $script:ownerLastShownRevision -or
        $remoteRevision -ne $script:ownerLastShownRemoteRevision -or
        $toolActivity -cne $script:ownerLastShownToolActivity){
      $script:ownerLastShownToolActivity=$toolActivity
      $script:ownerLastShownRevision=[long]$snapshot.revision
      $script:ownerLastShownRemoteRevision=$remoteRevision
      if($script:ownerObservedMode){
       $online=([string]$remoteSnapshot.state -ceq 'Ready')
       $color=if($online){[Drawing.Color]::PaleGreen}elseif([string]$remoteSnapshot.state -ceq 'Fault'){
        [Drawing.Color]::LightCoral
       }elseif([string]$remoteSnapshot.state -ceq 'Disconnected'){[Drawing.Color]::Gray
       }else{[Drawing.Color]::Khaki}
       $presentation=Get-Rc1OwnerConnectionText ([string]$remoteSnapshot.state) ([string]$remoteSnapshot.status) $true
       $script:ownerLastSafePresentation=@{
        State=[string]$remoteSnapshot.state;Detail=[string]$remoteSnapshot.status
        Observed=$true;Color=$color
       }
       Set-State $presentation.Name $presentation.Detail $color
       Set-RuntimeDisplay ('PID '+[string]$remoteSnapshot.processPid) (Get-RdcOwnerUiText 'owner.runtime.adoptedShort' 'Существующая сессия / Adopted') $true
      }elseif($script:ownerManagedMode){
       $connected=([string]$remoteSnapshot.state -ceq 'Ready')
       $color=if($connected){[Drawing.Color]::PaleGreen}elseif([string]$remoteSnapshot.state -ceq 'Fault'){
        [Drawing.Color]::LightCoral
       }elseif([string]$remoteSnapshot.state -ceq 'Disconnected'){[Drawing.Color]::Gray
       }else{[Drawing.Color]::Khaki}
       $presentation=Get-Rc1OwnerConnectionText ([string]$remoteSnapshot.state) ([string]$remoteSnapshot.status) $false $toolActivity $completion
       if($presentation.Waiting){$color=[Drawing.Color]::PaleGreen}
       if($presentation.CompletionFault){$color=[Drawing.Color]::LightCoral}
       $script:ownerLastSafePresentation=@{
        State=[string]$remoteSnapshot.state;Detail=[string]$remoteSnapshot.status
        Observed=$false;Color=$color;Activity=$toolActivity;Completion=$completion
       }
       Set-State $presentation.Name $presentation.Detail $color
       $script:ownerLastUptimeText=''  # Timer owns the original runtime footer.
       if($script:ownerRemoteBornTicks -le 0){Set-RuntimeDisplay 'PID —' (Get-RdcOwnerUiText 'owner.runtime.disconnected' 'Remote отключён') $true}
      }else{
       $script:ownerLastSafePresentation=$null
       Set-State (Get-RdcOwnerUiText 'owner.initial.fakeName' 'Тестовый режим') (Get-RdcOwnerUiText 'owner.runtime.fakeDetail' 'Нет активной сессии Remote') ([Drawing.Color]::Khaki)
       Set-RuntimeDisplay ('PID '+[string]$snapshot.hostPid) (Get-RdcOwnerUiText 'owner.runtime.notConnected' 'Remote НЕ подключён | RC1') $true
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
       $modeLabel=if($script:ownerManagedMode){
        Get-RdcOwnerUiText 'owner.fallback.ownership.managed' 'Managed: Host-owned Job'
       }else{Get-RdcOwnerUiText 'owner.fallback.ownership.adopted' 'Adopted: read-only'}
       $statusProof=if([string]$remoteSnapshot.state -ceq 'Ready'){
        Get-RdcOwnerUiText 'owner.fallback.proof.receivedMarker' 'Remote connection marker received by Host'
       }else{Get-RdcOwnerUiText 'owner.fallback.proof.unconfirmed' 'Connected state not currently confirmed'}
       $safeDisplayState=switch -CaseSensitive ($safeState){
        'Connected' {(Get-RdcOwnerUiText 'owner.fallback.status.online' 'Online');break}
        'Connecting' {(Get-RdcOwnerUiText 'owner.fallback.status.connecting' 'Connecting');break}
        'Authenticating' {(Get-RdcOwnerUiText 'owner.fallback.status.authenticating' 'Authenticating');break}
        'Reconnecting' {(Get-RdcOwnerUiText 'owner.fallback.status.reconnecting' 'Reconnecting');break}
        'Connection fault' {(Get-RdcOwnerUiText 'owner.fallback.status.connectionFault' 'Connection fault');break}
        'Disconnected' {(Get-RdcOwnerUiText 'owner.fallback.status.disconnected' 'Disconnected');break}
        default {(Get-RdcOwnerUiText 'owner.fallback.status.unknown' 'Unknown')}
       }
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
         ((Get-RdcOwnerUiText 'owner.fallback.label.status' 'Status: ')+$safeDisplayState),
         ((Get-RdcOwnerUiText 'owner.fallback.label.user' '- User: ')+$(if($safeUser){$safeUser}else{Get-RdcOwnerUiText 'owner.fallback.value.notReported' 'not reported'})),
         ((Get-RdcOwnerUiText 'owner.fallback.label.deviceName' '- Device Name: ')+$(if($safeDeviceName){$safeDeviceName}else{Get-RdcOwnerUiText 'owner.fallback.value.notReported' 'not reported'})),
         ((Get-RdcOwnerUiText 'owner.fallback.label.deviceId' '- Device ID: ')+$(if($safeDeviceId){$safeDeviceId}else{Get-RdcOwnerUiText 'owner.fallback.value.notReported' 'not reported'})),
         ((Get-RdcOwnerUiText 'owner.fallback.label.process' 'Process: ')+$(if($safePid -gt 0){'PID '+$safePid}else{Get-RdcOwnerUiText 'owner.fallback.value.notStarted' 'not started'})),
         ((Get-RdcOwnerUiText 'owner.fallback.label.ownership' 'Ownership: ')+$modeLabel),
         $statusProof
        ))
       }
       Render-CompactLog
      }
     }
     $script:ownerNextVerb='GET_EVENTS'
      # Show the exact existing About+Journal dialog after a verified
      # Host tray request. The sequence blocks repeats from every poll.
      $trayHelpSeq=[int]$snapshot.trayHelpSequence
      if($trayHelpSeq -gt 0 -and $trayHelpSeq -ne $script:ownerTrayHelpSeenSequence){
       $script:ownerTrayHelpSeenSequence=$trayHelpSeq
       Show-RdcAbout
      }
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
       $formatted=Format-Rc1JournalLine ([long]$ev.sequence) ([string]$ev.text)
       Add-CompletedEvent $formatted
       Add-Rc1OwnerDetailedEvent 'Host' $formatted
      }
      $script:ownerNextVerb=if($eventData.moreAvailable){'GET_EVENTS'}else{'GET_SNAPSHOT'}
     }
    }elseif([string]$reply.type -eq 'ACK'){
     if(-not $script:ownerRequestedAction -or
        [string]$reply.payload.action -cne $script:ownerRequestedAction -or
        -not [bool]$reply.payload.success){throw 'RC1_REMOTE_ACK_MISMATCH'}
     if($script:ownerRequestedAction -ceq 'SWITCH_ACCOUNT'){
      Add-CompletedEvent (Get-Rc1JournalUiText 'journal.ack.switchAccountAccepted' 'Host принял смену аккаунта; ожидается штатный выход и новый вход.')
     }else{
      $ackMessage=Get-Rc1JournalUiText 'journal.ack.actionConfirmed' 'Host подтвердил выполнение: {action}'
      Add-CompletedEvent ($ackMessage.Replace('{action}',[string]$script:ownerRequestedAction))
     }
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
    $script:ownerLastSafePresentation=$null
    if($script:ownerRequestedNavigation){
     Set-State (Get-RdcOwnerUiText 'owner.error.navigationName' 'Операция не выполнена') (Get-RdcOwnerUiText 'owner.error.navigationDetail' 'Переход не выполнен; Remote без изменений') ([Drawing.Color]::Khaki)
    }elseif($script:ownerRequestedAction -and $_.Exception.Message -ceq 'RC1_BAD_OR_DENIED_REPLY_MANAGED_NODE_MISSING'){
     $detail='Required Node.js runtime is missing; run RDC Relay Setup'
     $presentation=Get-Rc1OwnerConnectionText 'Fault' $detail $false
     $script:ownerLastSafePresentation=@{State='Fault';Detail=$detail;Observed=$false;Color=[Drawing.Color]::LightCoral}
     Set-State $presentation.Name $presentation.Detail ([Drawing.Color]::LightCoral)
    }elseif($script:ownerRequestedAction){
     # Only allowlisted action names are displayed; never echo raw IPC verb/error text.
     $actionLabel=switch -CaseSensitive ([string]$script:ownerRequestedAction){
      'START' {(Get-RdcOwnerUiText 'owner.action.start' 'запуск');break}
      'STOP' {(Get-RdcOwnerUiText 'owner.action.stop' 'остановку');break}
      'RECONNECT' {(Get-RdcOwnerUiText 'owner.action.reconnect' 'переподключение');break}
      'SWITCH_ACCOUNT' {(Get-RdcOwnerUiText 'owner.action.switch' 'смену аккаунта');break}
      default {(Get-RdcOwnerUiText 'owner.action.unknown' 'операцию')}
     }
     $actionMessage=(Get-RdcOwnerUiText 'owner.error.actionDetail' 'Действие отклонено: {action}').Replace('{action}',[string]$actionLabel)
     Set-State (Get-RdcOwnerUiText 'owner.error.actionName' 'Операция отклонена') $actionMessage ([Drawing.Color]::LightCoral)
    }else{
     # A failed poll invalidates the display revision cache. A subsequent
     # successful snapshot must repaint even when Host state did not change.
     $script:ownerLastShownRevision=-1
     $script:ownerLastShownRemoteRevision=-1
     $script:ownerLastSnapshotUtcTicks=0L
     $script:ownerCanStart=$false
     $script:ownerCanStop=$false
     $script:ownerCanReconnect=$false
     $script:ownerCanSwitchAccount=$false
     $switchAccountItem.Enabled=$false
     $finish.Enabled=$false
     $reconnectItem.Enabled=$false
     Set-DividerWorkState $false
     $script:ownerLastSafePresentation=$null
     Set-State (Get-RdcOwnerUiText 'owner.error.hostName' 'Связь с Host') (Get-RdcOwnerUiText 'owner.error.hostDetail' 'Состояние неизвестно; остановка недоступна') ([Drawing.Color]::Khaki)
    }
   }finally{$script:ownerPending=$null;$script:ownerRequestedNavigation='';$script:ownerRequestedAction=''}
  }
  # Passive, async public stable-manifest check (no update installation,
  # candidate replacement or Remote process action). Owner keeps -Preview
  # solely to suppress the legacy startup/process side effects.
  if($script:enableUpdateNotice){Update-RdcUpdateNoticePolling}
  # Poll only the private, short-lived official snapshot (no credential IO,
  # no network requests on the WinForms UI thread). Expired means unknown.
  if([DateTime]::UtcNow -ge $script:ownerQuotaNextCheckUtc){
   $script:ownerQuotaNextCheckUtc=[DateTime]::UtcNow.AddSeconds(15)
   $quotaDisplayEnabled=Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath
   if($quotaAuthItem.Checked -ne $quotaDisplayEnabled){$quotaAuthItem.Checked=$quotaDisplayEnabled}
   $quotaPercent=$null
   # The quota validator remains invariant; only its verified numeric result is formatted.
   $quotaText=if($quotaDisplayEnabled){
    [void](Get-Rc1QuotaStatus $script:ownerQuotaPath ([string]$script:accountEmail) ([DateTime]::UtcNow) -percentOut ([ref]$quotaPercent))
    if($null -ne $quotaPercent){
     (Get-RdcOwnerUiText 'gui.quota.value' 'Остаток вызовов: {percent}%').Replace(
      '{percent}',[string]$quotaPercent)
    }else{Get-RdcOwnerUiText 'gui.quota.unknown' 'Остаток вызовов: --%'}
   }else{Get-RdcOwnerUiText 'gui.quota.unknown' 'Остаток вызовов: --%'}
   if($quotaText -cne $script:ownerLastQuotaText){
    $script:ownerLastQuotaText=$quotaText
    $quotaLabel.Text=$quotaText
    # Emphasis uses the validated numeric value, never the translated caption.
    $quotaLabel.ForeColor=if($null -ne $quotaPercent -and $quotaPercent -eq 0){
     [Drawing.Color]::LightCoral
    }else{[Drawing.Color]::Silver}
   }
  }
  if($script:ownerManagedMode -and $script:ownerRemoteBornTicks -gt 0 -and
     $script:ownerRemotePid -gt 0 -and $script:ownerLastSnapshotUtcTicks -gt 0 -and
     ([DateTime]::UtcNow.Ticks-$script:ownerLastSnapshotUtcTicks) -le 50000000){
   $seconds=[Math]::Max(0,[Math]::Floor(([DateTime]::UtcNow.Ticks-$script:ownerRemoteBornTicks)/10000000.0))
   $uptime=(Get-RdcOwnerUiText 'gui.runtime.uptime' 'Время работы {0:00}:{1:00}:{2:00}') -f [Math]::Floor($seconds/3600),[Math]::Floor(($seconds%3600)/60),($seconds%60)
   if($uptime -cne $script:ownerLastUptimeText){
    $script:ownerLastUptimeText=$uptime
    Set-RuntimeDisplay ('PID '+[string]$script:ownerRemotePid) $uptime $true
   }
  }
  # A tray-side locale selection is reflected without restarting GUI, Host or Remote.
  if([DateTime]::UtcNow -ge $script:ownerLocaleNextCheckUtc){
   $script:ownerLocaleNextCheckUtc=[DateTime]::UtcNow.AddSeconds(1)
   Apply-RdcOwnerLocale
  }
  Set-RdcOwnerLocalizedFinishLabel
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
