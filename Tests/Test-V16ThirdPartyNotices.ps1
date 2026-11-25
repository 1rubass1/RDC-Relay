# Release notice source contract. Pure file inspection; no npm install,
# no network requests, no Host/Remote or installed application interaction.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$notice=[IO.File]::ReadAllText((Join-Path $repo 'Source\THIRD_PARTY_NOTICES.txt'),[Text.Encoding]::UTF8)
$readme=[IO.File]::ReadAllText((Join-Path $repo 'README.md'),[Text.Encoding]::UTF8)
$script=[IO.File]::ReadAllText((Join-Path $repo 'Scripts\build-rc1-full.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$condition,[string]$title){
 if($condition){$script:pass++;Write-Output ('PASS '+$title)}
 else{$script:fail++;Write-Output ('FAIL '+$title)}
}
Check ($notice.Contains('@wonderwhy-er/desktop-commander') -and
 $notice.Contains('0.2.52') -and
 $notice.Contains('https://github.com/wonderwhy-er/DesktopCommanderMCP')) 'original local engine is attributed with pinned version and upstream repository'
Check ($notice.Contains('MIT License') -and
 $notice.Contains('Copyright (c) 2024-2025 Eduard Ruzga and Desktop Commander Contributors') -and
 $notice.Contains('The above copyright notice and this permission notice shall be included')) 'MIT copyright and license retention requirement documented'
Check ($notice.Contains('not affiliated') -and
 $notice.Contains('separate proprietary service')) 'upstream hosting and product ownership distinguished'
Check ($readme.Contains('Source/THIRD_PARTY_NOTICES.txt') -and
 $readme.Contains('https://legal.desktopcommander.app/terms_of_service')) 'product README links license notices and hosted-service terms'
Check (-not $script.Contains('node_modules') -and
 -not $script.Contains('THIRD_PARTY_NOTICES.txt')) 'private RC1 builder remains unchanged: upstream npm package is not bundled and notice does not falsely claim deployment'
Write-Output ('RC1_THIRD_PARTY_NOTICES_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
