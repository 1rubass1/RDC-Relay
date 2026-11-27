# Static retirement gate; no product execution or live state changes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$builder=Join-Path $repo 'Scripts\build-release.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
if($errors.Count -or $ast.EndBlock.Statements.Count -ne 1 -or $ast.EndBlock.Statements[0] -isnot [System.Management.Automation.Language.ThrowStatementAst] -or $ast.EndBlock.Statements[0].Extent.Text -notmatch 'RDC_LEGACY_BUILDER_RETIRED_USE_FULL_HOST_PIPELINE'){throw 'Legacy builder must refuse all invocations'}
foreach($name in @('build-v16-legacy-bridge.ps1','v16-legacy-migration.ps1')){
 if(Test-Path -LiteralPath (Join-Path $repo ('Scripts\'+$name))){throw ('Retired script remains: '+$name)}
}
Write-Output 'PASS retired legacy release builder and bridge absent'
