param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [Parameter(Mandatory=$true)][string]$CurrentVersion,
    [string]$Repository = '1rubass1/Remote-Desktop-Commander',
    [string]$Branch = 'main',
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

    # Resolve main to an immutable commit SHA first. This avoids a race where
    # raw.githubusercontent.com CDN serves manifest and payloads from different
    # moments of a moving branch.
    $apiHeaders = @{
        'User-Agent' = 'RemoteDesktopCommanderUpdater'
        'Accept' = 'application/vnd.github+json'
    }
    $refUrl = 'https://api.github.com/repos/' + $Repository + '/commits/' + [Uri]::EscapeDataString($Branch)
    $refResponse = Invoke-WebRequest -Uri $refUrl -Headers $apiHeaders -UseBasicParsing -TimeoutSec 5
    $refInfo = $refResponse.Content | ConvertFrom-Json
    $commitSha = [string]$refInfo.sha
    if ($commitSha -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'GitHub did not return a valid commit SHA.'
    }

    $baseUrl = 'https://raw.githubusercontent.com/' + $Repository + '/' + $commitSha + '/Source'
    $manifestUrl = $baseUrl + '/update-manifest.json'
    $manifestResponse = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 5
    $manifestText = ([string]$manifestResponse.Content).TrimStart([char]0xFEFF)
    $manifest = $manifestText | ConvertFrom-Json
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
        $url = $baseUrl.TrimEnd('/') + '/' + [Uri]::EscapeDataString($name)
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
