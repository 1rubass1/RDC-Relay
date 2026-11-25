# RC1 Owner-only two-line header: Russian state + independent explanation.
# Read-only source/WinForms verification; no Host, Remote or installer.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
Add-Type -Path (Join-Path $root 'Source\RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources((Join-Path $root 'Source'),'ru-RU')
$ownerFile=Join-Path $root 'Source\rc1-owner-gui.ps1'
$originalFile=Join-Path $root 'Source\remote-window.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($ownerFile,[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$desc){
 if($ok){$script:pass++;Write-Output ('PASS '+$desc)}
 else{$script:fail++;Write-Output ('FAIL '+$desc)}
}
Check ($errors.Count -eq 0) 'Owner GUI parses under Windows PowerShell 5.1'
$defs=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $node.Name -ceq 'Get-Rc1OwnerConnectionText'},$true))
if($defs.Count -ne 1){throw 'MISSING_OR_DUPLICATE_HEADER_FORMATTER'}
$uiDef=$ast.Find({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $node.Name -ceq 'Get-RdcOwnerUiText'},$true)
if(-not $uiDef){throw 'OWNER_UI_TRANSLATOR_MISSING'}
. ([scriptblock]::Create($uiDef.Extent.Text))
. ([scriptblock]::Create($defs[0].Extent.Text))
# Expected literal states are fixed; Host English diagnostics never pass through.
$rows=@(
 @{State='Ready';Detail='Remote connected';Observed=$false;Name='Подключён';Info='Ожидание запроса'},
 @{State='Ready';Detail='Successful Remote tool call confirmed connectivity';Observed=$false;Name='Подключён';Info='Ожидание запроса'},
 @{State='Connecting';Detail='Starting pinned Desktop Commander Remote';Observed=$false;Name='Подключение';Info='Запуск Remote'},
 @{State='Connecting';Detail='Other';Observed=$false;Name='Подключение';Info='Установление связи'},
 @{State='AuthPending';Detail='Authentication pending';Observed=$false;Name='Подключение';Info='Ожидание подтверждения'},
 @{State='AuthPending';Detail='Official device logout in progress';Observed=$false;Name='Подключение';Info='Выход из аккаунта'},
 @{State='Reconnecting';Detail='Local MCP recovering';Observed=$false;Name='Восстановление';Info='Восстановление связи'},
 @{State='Fault';Detail='Remote channel unavailable';Observed=$false;Name='Ошибка связи';Info='Канал недоступен'},
 @{State='Fault';Detail='Remote start failed';Observed=$false;Name='Ошибка связи';Info='Не удалось запустить Remote'},
 @{State='Fault';Detail='Remote startup failed; inspect Host status and retry manually';Observed=$false;Name='Ошибка связи';Info='Запустите Remote вручную'},
 @{State='Fault';Detail='Account switch refused; owned Remote remains stopped';Observed=$false;Name='Ошибка связи';Info='Смена аккаунта отклонена; Remote остановлен'},
 @{State='Fault';Detail='Authorization revoked; Remote restart failed';Observed=$false;Name='Ошибка связи';Info='Авторизация отозвана; запуск не удался'},
 @{State='Fault';Detail='Logout not confirmed; Remote remains stopped';Observed=$false;Name='Ошибка связи';Info='Выход не подтверждён; Remote остановлен'},
 @{State='Disconnected';Detail='RC1 Host ready to start pinned Remote';Observed=$false;Name='Отключён';Info=''},
 @{State='Disconnected';Detail='Host-owned Remote stopped';Observed=$false;Name='Отключён';Info=''},
 @{State='Disconnected';Detail='Host-owned Remote process exited';Observed=$false;Name='Отключён';Info='Remote завершил работу'},
 @{State='Disconnected';Detail='Previous Remote exited; RC1 Host preparing a new managed session';Observed=$false;Name='Отключён';Info='Подготовка к запуску'},
 @{State='Disconnected';Detail='Waiting for the previous Remote and shell to exit; no duplicate launched';Observed=$false;Name='Отключён';Info='Ожидание завершения сессии'},
 @{State='Ready';Detail='Remote connected';Observed=$true;Name='Подключён';Info='Только наблюдение'},
 @{State='Connecting';Detail='Observed';Observed=$true;Name='Подключение';Info='Проверка существующего подключения'},
 @{State='AuthPending';Detail='Authentication pending';Observed=$true;Name='Подключение';Info='Ожидание подтверждения; только наблюдение'},
 @{State='Reconnecting';Detail='Local MCP recovering';Observed=$true;Name='Восстановление';Info='Проверка связи; только наблюдение'},
 @{State='Fault';Detail='Remote channel unavailable';Observed=$true;Name='Ошибка связи';Info='Сессия недоступна'},
 @{State='Disconnected';Detail='Observed';Observed=$true;Name='Отключён';Info='Предыдущая сессия завершена'},
 @{State='Ready';Detail='Remote connected';Observed=$false;Name='Подключён';Info='Ожидание запроса'}
)
foreach($row in $rows){
 $result=Get-Rc1OwnerConnectionText ([string]$row.State) ([string]$row.Detail) ([bool]$row.Observed)
 $label=([string]$row.State)+'/'+$(if($row.Observed){'Observed'}else{'Managed'})+'/'+([string]$row.Detail)
 Check ($result.Name -ceq $row.Name -and $result.Detail -ceq $row.Info) ('two-line text '+$label)
 Check ((($row.Info -ceq '' -and $result.Detail -ceq '') -or -not [string]::IsNullOrWhiteSpace($result.Detail)) -and
        $result.Name -cnotmatch '(?i)Remote|Connected|Disconnected|Fault|Ready' -and
        $result.Detail -cne $result.Name) ('short Russian state and meaningful detail '+$label)
}
$danger='Remote connected; bearer: secret-token; C:\\Users\\hidden'
foreach($state in @('Ready','Connecting','AuthPending','Reconnecting','Fault','Disconnected','Unexpected')){
 foreach($observer in @($false,$true)){
  $res=Get-Rc1OwnerConnectionText $state $danger $observer
  Check ($res.Detail -notlike '*secret*' -and $res.Detail -notlike '*hidden*' -and
   $res.Name -notlike '*Remote*' -and $res.Name -notlike '*Unexpected*' -and
   $res.Name.Length -le 26) ('unknown diagnostic is not interpolated '+$state+'/'+$observer)
 }
}
# The same sanitized state/detail values must produce English without changing
# the technical Host state codes or interpolating untrusted diagnostic strings.
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources((Join-Path $root 'Source'),'en-US')
$waitingEn=Get-Rc1OwnerConnectionText 'Reconnecting' 'Remote channel unconfirmed; awaiting new connectivity evidence' $false
Check ($waitingEn.Waiting -and $waitingEn.Name -ceq 'Connected' -and $waitingEn.Detail -ceq 'Waiting for a request') 'quiet owned timeout retains Connected heading and secondary waiting detail in English'
$observedWait=Get-Rc1OwnerConnectionText 'Reconnecting' 'Remote channel unconfirmed; awaiting new connectivity evidence' $true
$realRecovery=Get-Rc1OwnerConnectionText 'Reconnecting' 'Local MCP recovering' $false
Check (-not $observedWait.Waiting -and -not $realRecovery.Waiting -and $realRecovery.Name -ceq 'Reconnecting') 'observer and actual local MCP recovery remain reconnecting'
$busyEn=Get-Rc1OwnerConnectionText 'Ready' 'Remote connected' $false 'working'
$busyQuietEn=Get-Rc1OwnerConnectionText 'Reconnecting' 'Remote channel unconfirmed; awaiting new connectivity evidence' $false 'working'
$busyFaultEn=Get-Rc1OwnerConnectionText 'Fault' 'Remote channel unavailable' $false 'working'
Check ($busyEn.Name -ceq 'Connected' -and $busyEn.Detail -ceq 'Processing request') 'active request changes only the secondary line'
Check ($busyQuietEn.Name -ceq 'Connected' -and $busyQuietEn.Waiting -and $busyQuietEn.Detail -ceq 'Processing request') 'quiet lease expiry still displays actual request activity'
Check ($busyFaultEn.Detail -ceq 'Channel unavailable') 'actual fault retains priority over activity'
$authEn=Get-Rc1OwnerConnectionText 'AuthPending' 'Authentication pending' $false
Check ($authEn.Name -ceq 'Connecting' -and $authEn.Detail -ceq 'Awaiting confirmation') 'authorization is a connecting substate in English'
foreach($reason in @('RC1 Host ready to start pinned Remote','Host-owned Remote stopped','Unknown idle reason')){
 $idleEn=Get-Rc1OwnerConnectionText 'Disconnected' $reason $false
 Check ($idleEn.Name -ceq 'Disconnected' -and $idleEn.Detail -ceq '') 'ordinary disconnected state has no secondary prompt'
}
$readyEn=Get-Rc1OwnerConnectionText 'Ready' 'Remote connected' $false
$faultEn=Get-Rc1OwnerConnectionText 'Fault' 'Remote channel unavailable' $false
$observerEn=Get-Rc1OwnerConnectionText 'Connecting' 'raw <token secret=hidden>' $true
Check ($readyEn.Name -ceq 'Connected' -and
 $readyEn.Detail -ceq 'Waiting for a request') 'English ready status is mapped from safe Host state'
Check ($faultEn.Name -ceq 'Connection error' -and
 $faultEn.Detail -ceq 'Channel unavailable') 'English fault is a sanitized allowlisted explanation'
Check ($observerEn.Name -ceq 'Connecting' -and
 $observerEn.Detail -ceq 'Checking existing connection' -and
 $observerEn.Detail -notlike '*secret*') 'English observed status never exposes untrusted Host detail'
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources((Join-Path $root 'Source'),'ru-RU')
$waitingRu=Get-Rc1OwnerConnectionText 'Reconnecting' 'Remote channel unconfirmed; awaiting new connectivity evidence' $false
Check ($waitingRu.Waiting -and $waitingRu.Name -ceq 'Подключён' -and $waitingRu.Detail -ceq 'Ожидание запроса') 'quiet timeout retains Russian Connected heading and secondary waiting detail'
$busyRu=Get-Rc1OwnerConnectionText 'Ready' 'Remote connected' $false 'working'
Check ($busyRu.Name -ceq 'Подключён' -and $busyRu.Detail -ceq 'Выполнение запроса') 'Russian active request preserves the title'
$owner=[IO.File]::ReadAllText($ownerFile,[Text.Encoding]::UTF8)
Check ($owner.Contains('$toolActivity -cne $script:ownerLastShownToolActivity') -and $owner.Contains('Activity=$toolActivity') -and $owner.Contains('([string]$safe.Activity)')) 'activity-only snapshot updates and localization preserve current detail'
Check ($owner.Contains('if($presentation.Waiting){$color=[Drawing.Color]::PaleGreen}')) 'waiting presentation uses green without changing Host state'
$original=[IO.File]::ReadAllText($originalFile,[Text.Encoding]::UTF8)
Check ($owner.Contains('Get-Rc1OwnerConnectionText ([string]$remoteSnapshot.state) ([string]$remoteSnapshot.status) $true') -and
 $owner.Contains('Get-Rc1OwnerConnectionText ([string]$remoteSnapshot.state) ([string]$remoteSnapshot.status) $false') -and
 $owner.Contains('Set-State $presentation.Name $presentation.Detail $color')) 'both Managed and Observed use same bounded formatter'
Check ($owner.Contains('$remoteRevision -ne $script:ownerLastShownRemoteRevision') -and
 $owner.Contains('$remoteSnapshot.toolActivity') -and $owner.Contains('Set-DividerFaultState') -and
 $owner.Contains("Get-RdcOwnerUiText 'owner.error.hostName'")) 'snapshot revision, activity and localized fault-safe fallback stay active'
Check ($owner.Contains("Get-RdcOwnerUiText 'owner.initial.managedName' 'Отключён'") -and
 $owner.Contains("Get-RdcOwnerUiText 'owner.initial.fakeName' 'Тестовый режим'") -and
 $owner.Contains("Get-RdcOwnerUiText 'owner.initial.observedName' 'Подключение'")) 'initial Managed Observed and fake titles keep Russian fallback through semantic keys'
# The existing production top title + second line still go through Set-State.
$start=$original.IndexOf('function Set-State(')
$end=$original.IndexOf('function Set-FinishButtonMode(',$start)
if($start -lt 0 -or $end -le $start){throw 'ORIGINAL_SET_STATE_SPAN_MISSING'}
. ([scriptblock]::Create($original.Substring($start,$end-$start)))
$script:statusDot=[pscustomobject]@{IndicatorColor=[Drawing.Color]::Gray}
$script:title=New-Object Windows.Forms.Label
$script:statusDetail=New-Object Windows.Forms.Label
$script:title.Font=[Drawing.Font]::new('Segoe UI',13,[Drawing.FontStyle]::Bold)
$script:statusDetail.Font=[Drawing.Font]::new('Segoe UI',10)
try{
 $maxWidth=0
 foreach($row in $rows){
  $presentation=Get-Rc1OwnerConnectionText $row.State $row.Detail $row.Observed
  Set-State $presentation.Name $presentation.Detail ([Drawing.Color]::PaleGreen)
  Check ($script:title.Text -ceq ('RDC Relay  —  '+$row.Name) -and
    $script:statusDetail.Text -ceq $row.Info) ('real Set-State label binding '+$row.State+'/'+$row.Observed)
  $size=[Windows.Forms.TextRenderer]::MeasureText($script:statusDetail.Text,$script:statusDetail.Font)
  if($size.Width -gt $maxWidth){$maxWidth=$size.Width}
 }
 Check ($maxWidth -le 665) ('single-line secondary statuses fit nominal title column (max width '+$maxWidth+'px)')
}finally{
 $script:title.Font.Dispose();$script:statusDetail.Font.Dispose()
 $script:title.Dispose();$script:statusDetail.Dispose()
}
Write-Output ('RC1_OWNER_HEADER_STATUS_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
