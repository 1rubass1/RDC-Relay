# P3A exact owned-run completion + deletion; nonzero if unfinished.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'P3-Ownership.ps1')
try{
 $state=Join-Path $PSScriptRoot 'RunState'
 Assert-P3NoLinks $state
 $marker=Join-Path $state 'active-demo.json'
 if(-not [IO.File]::Exists($marker)){
  throw 'NOT CLEAN: собственный маркер запуска отсутствует; принадлежность процессов и каталога не подтверждена'
 }
 $bound=Get-P3BoundRun $state
 [void](Assert-P3Inventory $bound.Root $bound.MarkerData)
 # Use a separate PowerShell process for an explicit nonzero exit contract.
 $ps=Join-Path $PSHOME 'powershell.exe'
 $out=@(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Remove-Fixture.ps1') -FixtureRoot $bound.Root 2>&1)
 $code=$LASTEXITCODE
 foreach($line in $out){Write-Output $line}
 if($code -ne 0){throw ('NOT CLEAN: Remove-Fixture returned nonzero '+$code)}
 if([IO.Directory]::Exists($bound.Root)){throw 'NOT CLEAN: own fixture remains'}
 [void](Assert-P3Inventory $bound.Root $bound.MarkerData)
 Assert-P3NoLinks $marker
 Remove-Item -LiteralPath $marker -Force -ErrorAction Stop
 if([IO.File]::Exists($marker)){throw 'NOT CLEAN: marker remains after removal'}
 if([IO.Directory]::Exists($bound.Root)){throw 'NOT CLEAN: own fixture reappeared'}
 [void](Assert-P3Inventory $bound.Root $bound.MarkerData)
 Write-Output 'PASS: свои процессы отсутствуют, свой каталог и маркер удалены.'
 exit 0
}catch{
 [Console]::Error.WriteLine(('NOT CLEAN: отказ очистки: '+$_.Exception.Message))
 exit 2
}
