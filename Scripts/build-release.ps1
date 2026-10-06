param(
    [switch]$SkipSelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $root 'Source'
$assetsDir = Join-Path $root 'Assets'
$installerDir = Join-Path $root 'Installer'
$distRoot = Join-Path $root 'dist'

$version = (Get-Content -LiteralPath (Join-Path $sourceDir 'version.txt') -Raw -Encoding UTF8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw ('Invalid version.txt: ' + $version)
}

function Convert-ToCanonicalUtf8Lf {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom =
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString($bytes,$offset,$bytes.Length-$offset)
    $text = $text.Replace("`r`n","`n").Replace("`r","`n")
    $encoding = New-Object Text.UTF8Encoding($hasBom)
    [IO.File]::WriteAllText($Path,$text,$encoding)
}

foreach ($name in @(
    'remote-window.ps1',
    'update.ps1',
    'version.txt',
    'RDC Relay.cmd'
)) {
    Convert-ToCanonicalUtf8Lf (Join-Path $sourceDir $name)
}

Write-Host 'Compiling shaders...'
& (Join-Path $PSScriptRoot 'build-shaders.ps1')

$sourceIcon = Join-Path $assetsDir 'DesktopCommander.ico'
$runtimeIcon = Join-Path $sourceDir 'DesktopCommander.ico'
if (-not (Test-Path -LiteralPath $sourceIcon)) {
    throw ('Missing application icon: ' + $sourceIcon)
}
Copy-Item -LiteralPath $sourceIcon -Destination $runtimeIcon -Force

$manifestPayload = @(
    'remote-window.ps1',
    'divider-caustic.ps',
    'divider-particles.ps',
    'DesktopCommander.ico',
    'version.txt',
    'update.ps1',
    'RDC Relay.cmd'
)

$manifestFiles = @()
foreach ($name in $manifestPayload) {
    $path = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw ('Missing update payload: ' + $path)
    }
    $manifestFiles += [ordered]@{
        name = $name
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    }
}

$manifest = [ordered]@{
    version = $version
    files = $manifestFiles
}
$manifestPath = Join-Path $sourceDir 'update-manifest.json'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 5),
    $utf8NoBom
)

if (-not $SkipSelfTest) {
    Write-Host 'Running GUI self-test...'
    $selfTestOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sourceDir 'remote-window.ps1') -SelfTest -SkipUpdate 2>&1
    $selfTestOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or ($selfTestOutput -notmatch 'GUI SELF TEST PASSED')) {
        throw 'GUI self-test failed.'
    }
}

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) {
    throw 'C# compiler from .NET Framework 4.x was not found.'
}

$outDir = Join-Path $distRoot ('v' + $version)
if (Test-Path -LiteralPath $outDir) {
    Remove-Item -LiteralPath $outDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$buildTemp = Join-Path ([IO.Path]::GetTempPath()) ('RDC-build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildTemp -Force | Out-Null

try {
    $assemblyInfo = Join-Path $buildTemp 'AssemblyInfo.cs'
    $assemblyVersion = $version + '.0'
    $assemblySource = @"
using System.Reflection;
[assembly: AssemblyTitle("RDC Relay Setup")]
[assembly: AssemblyDescription("Installer for RDC Relay")]
[assembly: AssemblyCompany("UMAS")]
[assembly: AssemblyProduct("RDC Relay")]
[assembly: AssemblyCopyright("Copyright (c) UMAS")]
[assembly: AssemblyVersion("$assemblyVersion")]
[assembly: AssemblyFileVersion("$assemblyVersion")]
"@
    [IO.File]::WriteAllText($assemblyInfo,$assemblySource,$utf8NoBom)

    $setupExe = Join-Path $outDir ('RDC Relay Setup v' + $version + '.exe')
    $setupSource = Join-Path $installerDir 'Setup.cs'

    $compilerArgs = @(
        '/nologo',
        '/target:winexe',
        '/optimize+',
        '/platform:anycpu',
        '/reference:System.Windows.Forms.dll',
        ('/win32icon:' + $runtimeIcon),
        ('/out:' + $setupExe),
        $setupSource,
        $assemblyInfo,
        ('/resource:' + (Join-Path $sourceDir 'remote-window.ps1') + ',RdcPayload.remote-window.ps1'),
        ('/resource:' + (Join-Path $sourceDir 'divider-caustic.ps') + ',RdcPayload.divider-caustic.ps'),
        ('/resource:' + (Join-Path $sourceDir 'divider-particles.ps') + ',RdcPayload.divider-particles.ps'),
        ('/resource:' + (Join-Path $sourceDir 'DesktopCommander.ico') + ',RdcPayload.DesktopCommander.ico'),
        ('/resource:' + (Join-Path $sourceDir 'version.txt') + ',RdcPayload.version.txt'),
        ('/resource:' + (Join-Path $sourceDir 'update.ps1') + ',RdcPayload.update.ps1'),
        ('/resource:' + (Join-Path $sourceDir 'update-manifest.json') + ',RdcPayload.update-manifest.json'),
        ('/resource:' + (Join-Path $sourceDir 'RDC Relay.cmd') + ',RdcPayload.launch.cmd')
    )

    & $csc @compilerArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $setupExe)) {
        throw 'Installer compilation failed.'
    }

    $portableRoot = Join-Path $buildTemp ('RDC Relay v' + $version)
    New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
    foreach ($name in ($manifestPayload + 'update-manifest.json')) {
        Copy-Item -LiteralPath (Join-Path $sourceDir $name) -Destination (Join-Path $portableRoot $name) -Force
    }

    $portableZip = Join-Path $outDir ('RDC Relay v' + $version + ' Portable.zip')
    Compress-Archive -LiteralPath $portableRoot -DestinationPath $portableZip -CompressionLevel Optimal -Force

    $releaseInfo = [ordered]@{
        version = $version
        installer = [IO.Path]::GetFileName($setupExe)
        installerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $setupExe).Hash
        portable = [IO.Path]::GetFileName($portableZip)
        portableSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $portableZip).Hash
    }
    $releaseInfoPath = Join-Path $outDir 'release-info.json'
    [IO.File]::WriteAllText(
        $releaseInfoPath,
        ($releaseInfo | ConvertTo-Json),
        $utf8NoBom
    )

    Write-Host ''
    Write-Host ('Release v' + $version + ' built successfully:')
    Write-Host ('  ' + $setupExe)
    Write-Host ('  ' + $portableZip)
    Write-Host ('  ' + $releaseInfoPath)
}
finally {
    if (Test-Path -LiteralPath $buildTemp) {
        Remove-Item -LiteralPath $buildTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
