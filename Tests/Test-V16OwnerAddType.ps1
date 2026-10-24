# Compile-only PowerShell 5.1 loader parity: does not construct Host or open IPC.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $src 'RdcOwnerWire.cs'),(Join-Path $src 'RdcOwnerProcess.cs'),(Join-Path $src 'RdcOwnerTicketStore.cs'),(Join-Path $src 'RdcOwnerRemoteState.cs'),(Join-Path $src 'RdcOwnerRuntime.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.Security.dll','System.Windows.Forms.dll','System.Drawing.dll','System.dll')
if(-not ('RdcOwnerRuntime' -as [type]) -or -not ('RdcOwnerWire' -as [type]) -or -not ('RdcOwnerServer' -as [type])){
 throw 'RC1 Add-Type failed to load actual product Host/IPC'
}
Write-Output 'RC1_PRODUCT_HOST_ADDTYPE_COMPILE=PASS'
exit 0
