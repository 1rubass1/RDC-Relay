# Strictly synthetic release staging regression; does not run Setup, update ARP,
# write links, launch Host/Remote or touch real installed application data.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'Installer\RdcReleaseDurableStage.cs'
$harness=Join-Path $PSScriptRoot 'RdcReleaseDurableStageAssertions.cs'
$dir=Join-Path $env:TEMP ('RDC-Release-Stage-Test-'+[Guid]::NewGuid().ToString('N'))
if(-not ($dir.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',
 [StringComparison]::OrdinalIgnoreCase))){throw 'RDC_STAGE_FIXTURE_UNSAFE_PATH'}
[void][IO.Directory]::CreateDirectory($dir)
try {
 $cp=New-Object System.CodeDom.Compiler.CompilerParameters
 $cp.CompilerOptions='/define:RDC_INSTALLER_TEST'
 [void]$cp.ReferencedAssemblies.Add('System.dll')
 [void]$cp.ReferencedAssemblies.Add('System.Core.dll')
 $types=@(Add-Type -Path @($source,$harness) -CompilerParameters $cp -PassThru -ErrorAction Stop)
 if(-not @($types|Where-Object{$_.Name -ceq 'RdcReleaseDurableStageAssertions'})){throw 'RDC_STAGE_TEST_TYPE_MISSING'}
 $result=[RdcReleaseDurableStageAssertions]::Run($dir)
 Write-Output $result
 if(-not $result.EndsWith('FAIL=0')){exit 1}
}finally {
 if(Test-Path -LiteralPath $dir){
  Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction Stop |
   ForEach-Object{
    if(($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'TEST_FIXTURE_REPARSE_REFUSED'}
   }
  Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
 }
}
