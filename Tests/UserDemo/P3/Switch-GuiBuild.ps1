$ErrorActionPreference='Stop'
$marker=Join-Path $PSScriptRoot 'RunState\active-demo.json'
if(-not(Test-Path -LiteralPath $marker)){throw 'Нет активного тестового запуска. Сначала нажмите Запустить RDC Relay DEMO.cmd'}
$active=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
$root=[IO.Path]::GetFullPath([string]$active.Root).TrimEnd([char]92)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
if(-not [String]::Equals([IO.Path]::GetDirectoryName($root),$temp,[StringComparison]::OrdinalIgnoreCase) -or
   [IO.Path]::GetFileName($root) -cnotmatch '^RDC-P3-[0-9a-f]{32}$'){throw 'Отказ: путь вне тестового каталога'}
& (Join-Path $PSScriptRoot 'Set-GuiBuild.ps1') -FixtureRoot $root -Build B
if(-not $?){throw 'Не удалось изменить тестовый GUI'}
Write-Output 'После закрытия GUI версии A дважды щёлкните значок RDC Relay DEMO в трее для открытия GUI B.'
