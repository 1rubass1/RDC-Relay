param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [Parameter(Mandatory=$true)][string]$CurrentVersion,
    [string]$Repository = '1rubass1/Remote-Desktop-Commander',
    [string]$Branch = 'stable',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$statePath = Join-Path $InstallRoot '.update-state.json'
$logPath = Join-Path $InstallRoot 'update.log'
$tempRoot = $null
$backupRoot = $null
$applied = $null

function Write-UpdateLog {
    param([string]$Message)
    try {
        $line = '[' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    } catch {}
}

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

function Test-InstalledPayload {
    param($Manifest)

    foreach ($file in $Manifest.files) {
        $name = [string]$file.name
        $expected = ([string]$file.sha256).ToUpperInvariant()
        $dest = Join-Path $InstallRoot $name
        if (-not (Test-Path -LiteralPath $dest)) { return $false }
        try {
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash.ToUpperInvariant()
        } catch {
            return $false
        }
        if ($actual -ne $expected) { return $false }
    }
    return $true
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

    # Resolve the stable branch to one immutable commit before downloading
    # either the manifest or payload files.
    $apiHeaders = @{
        'User-Agent' = 'RemoteDesktopCommanderUpdater'
        'Accept' = 'application/vnd.github+json'
    }
    $refUrl = 'https://api.github.com/repos/' + $Repository + '/commits/' + [Uri]::EscapeDataString($Branch)
    $refResponse = Invoke-WebRequest -Uri $refUrl -Headers $apiHeaders -UseBasicParsing -TimeoutSec 8
    $refInfo = $refResponse.Content | ConvertFrom-Json
    $commitSha = [string]$refInfo.sha
    if ($commitSha -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'GitHub did not return a valid commit SHA.'
    }

    $baseUrl = 'https://raw.githubusercontent.com/' + $Repository + '/' + $commitSha + '/Source'
    $manifestUrl = $baseUrl + '/update-manifest.json'
    $manifestResponse = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 8
    $manifestText = ([string]$manifestResponse.Content).TrimStart([char]0xFEFF)
    $manifest = $manifestText | ConvertFrom-Json
    if (-not $manifest.version -or -not $manifest.files) {
        throw 'Invalid update manifest.'
    }

    $remoteVersion = [Version][string]$manifest.version
    $localVersion = [Version]$CurrentVersion
    Write-UpdateState ([string]$manifest.version)

    if ($remoteVersion -lt $localVersion) {
        exit 0
    }

    if ($remoteVersion -eq $localVersion -and (Test-InstalledPayload $manifest)) {
        exit 0
    }

    if ($remoteVersion -eq $localVersion) {
        Write-UpdateLog ('Repairing v' + $CurrentVersion + ' because one or more installed files failed SHA256 validation.')
    } else {
        Write-UpdateLog ('Updating v' + $CurrentVersion + ' -> v' + [string]$manifest.version + '.')
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
        Invoke-WebRequest -Uri $url -OutFile $staged -UseBasicParsing -TimeoutSec 15

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

    Write-UpdateLog ('Applied v' + [string]$manifest.version + ' from commit ' + $commitSha + '.')
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

    Write-UpdateLog ('Update failed: ' + $_.Exception.Message)
    Write-UpdateState $CurrentVersion
    exit 0
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
