$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'P3-Ownership.ps1')
$state=Join-Path $PSScriptRoot 'RunState'
$bound=Get-P3BoundRun $state
$root=$bound.Root
# Only the intentionally user-replaceable GUI file may change its recorded hash.
& (Join-Path $PSScriptRoot 'Set-GuiBuild.ps1') -FixtureRoot $root -Build B
if(-not $?){throw 'Не удалось изменить тестовый GUI'}
Assert-P3NoLinks (Join-Path $root 'p3-owner.json')
$owner=$bound.OwnerData
$owner.FileHashes.'DemoGui.ps1'=(Get-FileHash -LiteralPath (Join-Path $root 'DemoGui.ps1') -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $root 'p3-owner.json'),($owner|ConvertTo-Json -Depth 5 -Compress),(New-Object Text.UTF8Encoding($true)))
[void](Get-P3BoundRun $state)
Write-Output 'После закрытия GUI версии A дважды щёлкните значок RDC Relay DEMO в трее для открытия GUI B.'
