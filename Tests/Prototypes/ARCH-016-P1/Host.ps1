# ARCH-016-P1 isolated fake Tray Host; no Source/Remote references.
param([Parameter(Mandatory=$true)][string]$FixtureRoot,
      [Parameter(Mandatory=$true)][string]$Instance,
      [Parameter(Mandatory=$true)][int]$ControllerPid,
      [Parameter(Mandatory=$true)][long]$ControllerTicks)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'P1Wire.cs'),(Join-Path $PSScriptRoot 'P1Core.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll')
$gui=Join-Path $FixtureRoot 'Gui.ps1'
$core=$null
try {
  $core=[P1Core]::new($FixtureRoot,$gui,$Instance,$ControllerPid,$ControllerTicks)
  $core.Run()
} catch {
  [Console]::Error.WriteLine(('P1_HOST_FAILED: '+$_.Exception.Message))
  exit 10
} finally {
  if($core){$core.Dispose()}
}
