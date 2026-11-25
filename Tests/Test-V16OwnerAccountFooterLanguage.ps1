# Standalone source-function smoke: account footer is display-only.
# No installed client, Remote process, account, registry or user preferences.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'Source'
Add-Type -Path (Join-Path $source 'RdcUiLanguage.cs') -ReferencedAssemblies @(
 'System.dll','System.Core.dll','System.Web.Extensions.dll') -ErrorAction Stop
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$legacyFile=Join-Path $source 'remote-window.ps1'
$ownerFile=Join-Path $source 'rc1-owner-gui.ps1'
$tokens=$null;$errors=$null
$tree=[Management.Automation.Language.Parser]::ParseFile(
 $legacyFile,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'product GUI parses after footer change'
$setFunctions=@($tree.FindAll({
 param($a)
 $a -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $a.Name -ceq 'Set-AccountDisplay'
},$true))
Check ($setFunctions.Count -eq 1) 'account text function is uniquely selected'
if($setFunctions.Count -ne 1){throw 'ACCOUNT_FUNC_NOT_UNIQUE'}
. ([scriptblock]::Create($setFunctions[0].Extent.Text))
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources($source,'ru-RU')
$en=[RdcUiLanguage]::LoadResources($source,'en-US')
$ru=$script:ownerUiTexts
Check ($ru.Count -eq $en.Count) 'bilingual catalogs have identical key count'
Check ($ru.ContainsKey('gui.account.unknown') -and
 $en.ContainsKey('gui.account.unknown') -and
 $ru.ContainsKey('gui.account.infoTooltip') -and
 $en.ContainsKey('gui.account.infoTooltip')) 'account placeholder and tooltip both localized'
Check ($en['gui.account.unknown'] -ceq 'Not identified' -and
 $en['gui.account.infoTooltip'].Contains('Desktop Commander')) 'English copy is meaningful'
function Get-RdcOwnerUiText([string]$key,[string]$fallback) {
 return [RdcUiLanguage]::Text($script:ownerUiTexts,$key,$fallback)
}
$script:accountInfo=New-Object PSObject -Property @{Text=''}
$script:accountEmail=$null
$script:OwnerGui=$true
Set-AccountDisplay $null
Check ($script:accountInfo.Text -ceq $ru['gui.account.unknown'] -and
 -not $script:accountEmail) 'Owner with no account shows Russian placeholder'
$script:ownerUiTexts=$en
Set-AccountDisplay $null
Check ($script:accountInfo.Text -ceq 'Not identified' -and
 -not $script:accountEmail) 'switching to English repaints unknown account'
$script:ownerUiTexts=$ru
Set-AccountDisplay $null
Check ($script:accountInfo.Text -ceq $ru['gui.account.unknown']) 'switching back repaints Russian placeholder'
$script:ownerUiTexts=$en
Set-AccountDisplay 'user@example.invalid'
Check ($script:accountInfo.Text -ceq 'user@example.invalid' -and
 $script:accountEmail -ceq 'user@example.invalid') 'known email retained as exact identity text'
$script:ownerUiTexts=$ru
Check ($script:accountInfo.Text -ceq 'user@example.invalid') 'changing locale never mutates an email'
$script:OwnerGui=$false
Set-AccountDisplay $null
Check ($script:accountInfo.Text -ceq $ru['gui.account.unknown']) 'legacy UI Russian fallback unchanged'
$owner=[IO.File]::ReadAllText($ownerFile,[Text.Encoding]::UTF8)
Check ($owner.Contains("if(-not " + '$script:accountEmail' + "){Set-AccountDisplay " + '$null' + "}") -and
 $owner.Contains("Get-RdcOwnerUiText 'gui.account.infoTooltip'")) 'locale refresh only rerenders empty account and tooltip'
Check ($owner.Contains("Get-Rc1JournalUiText 'journal.synthetic.managedRestore'") -and
 $owner.Contains('Add-CompletedEvent $formatted')) 'historical journal rows remain append-only across language switches'
Write-Output ('RC1_OWNER_ACCOUNT_FOOTER_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
