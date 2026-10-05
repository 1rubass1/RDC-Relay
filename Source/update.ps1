param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [Parameter(Mandatory=$true)][string]$CurrentVersion,
    [string]$ManifestUrl = 'https://raw.githubusercontent.com/1rubass1/Remote-Desktop-Commander/main/Source/update-manifest.json',
    [string]$BaseUrl = 'https://raw.githubusercontent.com/1rubass1/Remote-Desktop-Commander/main/Source',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$statePath = Join-Path $InstallRoot '.update-state.json'
$tempRoot = $null
$backupRoot = $null

function Write-UpdateState {
    param([string]$Version)
    try {
        $state = [ordered]@{
            lastCheckUtc = [DateTime]::UtcNow.ToString('o')
            version = $Version
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    } catch {}
}

try {
    if (-not $Force -and (Test-Path -LiteralPath $statePath)) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $last = [DateTime]::Parse([string]$state.lastCheckUtc).ToUniversalTime()
            if (([DateTime]::UtcNow - $last).TotalHours -lt 6) {
                exit 0
            }
        } catch {}
    }

    $manifestResponse = Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing -TimeoutSec 5
    $manifest = $manifestResponse.Content | ConvertFrom-Json
    if (-not $manifest.version -or -not $manifest.files) {
        throw 'Invalid update manifest.'
    }

    Write-UpdateState ([string]$manifest.version)

    $remoteVersion = [Version][string]$manifest.version
    $localVersion = [Version]$CurrentVersion
    if ($remoteVersion -le $localVersion) {
        exit 0
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('RemoteDesktopCommander-update-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    foreach ($file in $manifest.files) {
        $name = [string]$file.name
        $expected = ([string]$file.sha256).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($name) -or $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $name -match '[\\/]') {
            throw ('Unsafe update file name: ' + $name)
        }

        $staged = Join-Path $tempRoot $name
        $url = $BaseUrl.TrimEnd('/') + '/' + [Uri]::EscapeDataString($name)
        Invoke-WebRequest -Uri $url -OutFile $staged -UseBasicParsing -TimeoutSec 12

        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $staged).Hash.ToUpperInvariant()
        if ($actual -ne $expected) {
            throw ('SHA256 mismatch for ' + $name)
        }
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Join-Path $InstallRoot ('backups\auto-' + $stamp + '-v' + $CurrentVersion)
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $applied = New-Object System.Collections.ArrayList
    foreach ($file in $manifest.files) {
        $name = [string]$file.name
        $source = Join-Path $tempRoot $name
        $dest = Join-Path $InstallRoot $name
        $existed = Test-Path -LiteralPath $dest

        if ($existed) {
            Copy-Item -LiteralPath $dest -Destination (Join-Path $backupRoot $name) -Force
        }

        Copy-Item -LiteralPath $source -Destination $dest -Force
        [void]$applied.Add([pscustomobject]@{ Name=$name; Existed=$existed })
    }

    exit 42
}
catch {
    if ($backupRoot -and (Test-Path -LiteralPath $backupRoot) -and $applied) {
        foreach ($item in $applied) {
            try {
                $dest = Join-Path $InstallRoot $item.Name
                $backup = Join-Path $backupRoot $item.Name
                if ($item.Existed -and (Test-Path -LiteralPath $backup)) {
                    Copy-Item -LiteralPath $backup -Destination $dest -Force
                } elseif (-not $item.Existed -and (Test-Path -LiteralPath $dest)) {
                    Remove-Item -LiteralPath $dest -Force
                }
            } catch {}
        }
    }

    Write-UpdateState $CurrentVersion
    exit 0
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
