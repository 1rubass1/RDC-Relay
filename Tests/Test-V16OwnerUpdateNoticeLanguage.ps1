# Owner RC1 real update notice: locale affects only UI/accessibility text.
# Isolated real production functions and fake WinForms-like controls, never a Host/Remote/install/network call.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
Add-Type -Path (Join-Path $src 'RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$astErrors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'update-notice.ps1'),[ref]$tokens,[ref]$astErrors)
if($astErrors.Count){throw 'UPDATE_NOTICE_PARSE_FAILED'}
foreach($name in @('Get-RdcOwnerNoticeText','Refresh-RdcOwnerUpdateNoticeLanguage')){
 $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
 if(-not $node){throw ('MISSING_PRODUCT_FUNCTION_'+$name)}
 . ([scriptblock]::Create($node.Extent.Text))
}
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$OwnerGui=$true
$script:rdcNoticeActive=$false
$script:rdcNoticeControl=[pscustomobject]@{
 OfferedVersion='';AccessibleName='RDC Relay v1.6.0 RC1'
 BeginCount=0;Installing=$false;VisualPreviewOnly=$true
}
$tip=[pscustomobject]@{Text='';Calls=0}
$tip|Add-Member ScriptMethod SetToolTip {
 param($control,[string]$message)
 $this.Text=$message
 $this.Calls++
}
function Get-RdcOwnerUiText([string]$key,[string]$fallback){
 return [RdcUiLanguage]::Text($script:ownerUiTexts,$key,$fallback)
}
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources($src,'en-US')
Check ($script:ownerUiTexts.Count -ge 139) 'English source catalog contains update notice keys'
Refresh-RdcOwnerUpdateNoticeLanguage
Check ($tip.Text -ceq 'RDC Relay RC1: checking the published version. Automatic installation is disabled.' -and
 $script:rdcNoticeControl.AccessibleName -ceq 'RDC Relay v1.6.0 RC1') 'idle English tooltip updates without changing the idle accessible version'
$script:rdcNoticeControl.OfferedVersion='1.6.2'
$script:rdcNoticeActive=$true
$script:rdcNoticeControl.BeginCount=1
Refresh-RdcOwnerUpdateNoticeLanguage
Check ($script:rdcNoticeControl.AccessibleName -ceq
 'Stable RDC Relay version v1.6.2 is available. Installation from RC1 is disabled.' -and
 $tip.Text -ceq 'Stable version v1.6.2 published. RC1: automatic installation is disabled.') 'active English tooltip and accessible name describe the same verified offer'
Check ($script:rdcNoticeControl.BeginCount -eq 1 -and $script:rdcNoticeControl.OfferedVersion -ceq '1.6.2' -and
 $script:rdcNoticeControl.VisualPreviewOnly -and -not $script:rdcNoticeControl.Installing) 'English copy does not restart animation or enable installation'
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources($src,'ru-RU')
Refresh-RdcOwnerUpdateNoticeLanguage
Check ($script:rdcNoticeControl.AccessibleName -ceq
 'Доступна стабильная версия RDC Relay v1.6.2. Установка из RC1 отключена.' -and
 $tip.Text -ceq 'Опубликована стабильная версия v1.6.2. RC1: автоматическая установка отключена.') 'Russian switch updates both display-only surfaces while active'
Check ($script:rdcNoticeControl.BeginCount -eq 1 -and $script:rdcNoticeControl.OfferedVersion -ceq '1.6.2' -and
 $script:rdcNoticeControl.VisualPreviewOnly -and -not $script:rdcNoticeControl.Installing) 'Russian copy does not mutate offer or interactivity'
$script:ownerUiTexts=$null
Refresh-RdcOwnerUpdateNoticeLanguage
Check ($script:rdcNoticeControl.AccessibleName -ceq
 'Доступна стабильная версия RDC Relay v1.6.2. Установка из RC1 отключена.') 'absent catalog safely falls back to Russian'
$tipBefore=$tip.Text;$accessibleBefore=$script:rdcNoticeControl.AccessibleName;$callsBefore=$tip.Calls
$OwnerGui=$false
Refresh-RdcOwnerUpdateNoticeLanguage
Check ($tip.Text -ceq $tipBefore -and $script:rdcNoticeControl.AccessibleName -ceq $accessibleBefore -and
 $tip.Calls -eq $callsBefore) 'legacy GUI does not receive Owner-only update copy'
$OwnerGui=$true
$script:rdcNoticeActive=$false
$script:rdcNoticeControl.OfferedVersion=''
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources($src,'en-US')
Refresh-RdcOwnerUpdateNoticeLanguage
Check ($tip.Text -ceq 'RDC Relay RC1: checking the published version. Automatic installation is disabled.') 'hiding offer restores idle translated tooltip'
$notice=[IO.File]::ReadAllText((Join-Path $src 'update-notice.ps1'),[Text.Encoding]::UTF8)
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
Check ($notice.Contains('if ($SelfTest -or $Preview -or $script:ownerUpdateDemoMode -or') -and
 $notice.Contains('public bool ButtonReady { get { return !visualPreviewOnly') -and
 $gui.Contains('Refresh-RdcOwnerUpdateNoticeLanguage')) 'Owner no-install guard and locale refresh hook retained'
Check ($notice.Contains('$script:rdcNoticeControl.Begin($appVersion,$Version,') -and
 $notice.Contains('$script:rdcNoticeActive = $true') -and
 $notice.Contains('if($OwnerGui){') -and
 $notice.Contains('Refresh-RdcOwnerUpdateNoticeLanguage')) 'same production update animation renderer; only display attributes refreshed'
Write-Output ('RC1_OWNER_UPDATE_NOTICE_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
