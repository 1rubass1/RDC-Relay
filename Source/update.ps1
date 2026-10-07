param(
    [string]$InstallRoot,
    [string]$CurrentVersion,
    [string]$Repository = '1rubass1/RDC-Relay',
    [string]$Branch = 'stable',
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = $PSScriptRoot
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)

function Remove-RdcShortcuts {
    foreach ($shortcutRoot in @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    )) {
        if ([string]::IsNullOrWhiteSpace($shortcutRoot)) { continue }
        foreach ($name in @(
            'RDC Relay.lnk',
            'Remote Desktop Commander.lnk',
            'CommanderRelay.lnk'
        )) {
            try {
                $path = Join-Path $shortcutRoot $name
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                }
            } catch {}
        }
    }
}

function Stop-RdcInstalledProcesses {
    try {
        $rootNeedle = $InstallRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        $scriptNeedle = Join-Path $rootNeedle 'remote-window.ps1'
        $logNeedle = Join-Path $rootNeedle 'remote-session.log'
        $targets = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProcessId -ne $PID -and
                    $_.CommandLine -and
                    (
                        $_.CommandLine.IndexOf($scriptNeedle,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                        $_.CommandLine.IndexOf($logNeedle,[StringComparison]::OrdinalIgnoreCase) -ge 0
                    )
                } |
                Sort-Object CreationDate |
                Select-Object -ExpandProperty ProcessId -Unique
        )

        foreach ($targetPid in $targets) {
            try {
                & taskkill.exe /PID $targetPid /T /F 2>$null | Out-Null
            } catch {}
        }
        if ($targets.Count -gt 0) {
            Start-Sleep -Milliseconds 500
        }
    } catch {}
}

function Invoke-RdcUninstall {
    if (-not $Silent) {
        Add-Type -AssemblyName System.Windows.Forms
        $choice = [System.Windows.Forms.MessageBox]::Show(
            'Remove RDC Relay from this computer?',
            'RDC Relay',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            return 0
        }
    }

    Stop-RdcInstalledProcesses
    Remove-RdcShortcuts

    try {
        if (Test-Path -LiteralPath $InstallRoot) {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        if (-not $Silent) {
            [System.Windows.Forms.MessageBox]::Show(
                'RDC Relay could not be completely removed.' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message,
                'RDC Relay',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        return 1
    }

    try {
        $bs = [char]92
        $keyPath = 'Software'+$bs+'Microsoft'+$bs+'Windows'+$bs+'CurrentVersion'+$bs+'Uninstall'+$bs+'RDC Relay'
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($keyPath,$false)
    } catch {}

    if (-not $Silent) {
        [System.Windows.Forms.MessageBox]::Show(
            'RDC Relay has been removed.',
            'RDC Relay',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    return 0
}

if ($Uninstall) {
    exit (Invoke-RdcUninstall)
}

if ([string]::IsNullOrWhiteSpace($CurrentVersion)) {
    throw 'CurrentVersion is required for update mode.'
}

$statePath = Join-Path $InstallRoot '.update-state.json'
$logPath = Join-Path $InstallRoot 'update.log'
$tempRoot = $null
$backupRoot = $null
$applied = $null
$payloadMutex = $null
$ownsPayload = $false

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
    # A local review build must not be silently repaired back to stable.
    $candidatePath = Join-Path $InstallRoot '.local-candidate.json'
    if (-not $Force -and (Test-Path -LiteralPath $candidatePath)) {
        $candidate = Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $runtimeHash = (Get-FileHash -LiteralPath (Join-Path $InstallRoot 'remote-window.ps1') -Algorithm SHA256).Hash
        if ($candidate.version -eq $CurrentVersion -and $candidate.runtimeSha256 -eq $runtimeHash) { exit 0 }
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($InstallRoot.TrimEnd('\','/').ToLowerInvariant()))).Replace('-','') }
    finally { $sha.Dispose() }
    $payloadMutex = New-Object Threading.Mutex($false,('Local\RDCRelayPayload-' + $key))
    try { $ownsPayload = $payloadMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsPayload = $true }
    if (-not $ownsPayload) { throw 'Another installation or update is already running.' }

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
        'User-Agent' = 'RDCRelayUpdater'
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

    if ($remoteVersion -lt $localVersion) {
        Write-UpdateState $CurrentVersion
        exit 0
    }

    if ($remoteVersion -eq $localVersion -and (Test-InstalledPayload $manifest)) {
        Write-UpdateState $CurrentVersion
        exit 0
    }

    if ($remoteVersion -eq $localVersion) {
        Write-UpdateLog ('Repairing v' + $CurrentVersion + ' because one or more installed files failed SHA256 validation.')
    } else {
        Write-UpdateLog ('Updating v' + $CurrentVersion + ' -> v' + [string]$manifest.version + '.')
    }

    # Stage on the destination volume so File.Replace/File.Move stay atomic.
    $tempRoot = Join-Path $InstallRoot ('.update-stage-' + [Guid]::NewGuid().ToString('N'))
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

    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
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

        # Journal BEFORE attempting the replacement, including the failing file.
        [void]$applied.Add([pscustomobject]@{ Name=$name; Existed=$existed })
        if ($existed) { [IO.File]::Replace($source,$dest,[NullString]::Value) }
        else { [IO.File]::Move($source,$dest) }
    }

    Write-UpdateState ([string]$manifest.version)
    Write-UpdateLog ('Applied v' + [string]$manifest.version + ' from commit ' + $commitSha + '.')
    exit 42
}
catch {
    if ($backupRoot -and (Test-Path -LiteralPath $backupRoot) -and $applied) {
        for ($index = $applied.Count - 1; $index -ge 0; $index--) {
            $item = $applied[$index]
            try {
                $dest = Join-Path $InstallRoot $item.Name
                $backup = Join-Path $backupRoot $item.Name
                if ($item.Existed -and (Test-Path -LiteralPath $backup)) {
                    if ((Test-Path -LiteralPath $dest) -and
                        (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash) { continue }
                    $restore = Join-Path $tempRoot ('restore-' + $item.Name)
                    Copy-Item -LiteralPath $backup -Destination $restore -Force
                    if (Test-Path -LiteralPath $dest) { [IO.File]::Replace($restore,$dest,[NullString]::Value) }
                    else { [IO.File]::Move($restore,$dest) }
                } elseif (-not $item.Existed -and (Test-Path -LiteralPath $dest)) {
                    Remove-Item -LiteralPath $dest -Force
                }
            } catch { Write-UpdateLog ('ROLLBACK FAILED for ' + $item.Name + ': ' + $_.Exception.Message + '; backup: ' + $backupRoot) }
        }
    }

    Write-UpdateLog ('Update failed: ' + $_.Exception.Message)
    exit 1
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($ownsPayload) { $payloadMutex.ReleaseMutex() }
    if ($payloadMutex) { $payloadMutex.Dispose() }
}
