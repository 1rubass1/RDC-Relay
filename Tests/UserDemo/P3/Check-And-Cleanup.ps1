$ErrorActionPreference='Stop'
$marker=Join-Path $PSScriptRoot 'RunState\active-demo.json'
if(-not(Test-Path -LiteralPath $marker)){Write-Output 'Нет зарегистрированной тестовой сборки P3.';exit 0}
$info=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
$root=[IO.Path]::GetFullPath([string]$info.Root).TrimEnd([char]92)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
if(-not [String]::Equals([IO.Path]::GetDirectoryName($root),$temp,[StringComparison]::OrdinalIgnoreCase) -or
  [IO.Path]::GetFileName($root) -cnotmatch '^RDC-P3-[0-9a-f]{32}$'){throw 'Нельзя проверять или удалять неизвестный путь'}
$hostFile=Join-Path $root 'Host.ps1';$gui=Join-Path $root 'Gui.ps1'
$running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object {
 ([string]$_.CommandLine).Contains(' -File "'+$hostFile+'"') -or
 ([string]$_.CommandLine).Contains(' -File "'+$gui+'"')
})
if($running.Count -gt 0){
 Write-Output ('Тестовый экземпляр ещё работает. PID: '+($running.ProcessId -join ', '))
 Write-Output 'Закройте сборку пунктом «Завершить тестовую сборку…» в её собственном трее.'
 exit 0
}
Write-Output 'Проверено: процессы тестового экземпляра завершены.'
if(Test-Path -LiteralPath $root){
 & (Join-Path $PSScriptRoot 'Remove-Fixture.ps1') -FixtureRoot $root
 if(-not $?){throw 'Не удалось очистить только собственный тестовый каталог'}
}
Remove-Item -LiteralPath $marker -Force
Write-Output 'Очищен только каталог завершённого P3. Исторические TEMP не затрагивались.'
