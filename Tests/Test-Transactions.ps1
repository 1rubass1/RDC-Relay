param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SetupPath
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SetupPath)) {
    $version = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'Source\version.txt') -Raw).Trim()
    $SetupPath = Join-Path $ProjectRoot ('dist\v' + $version + '\RDC Relay Setup v' + $version + '.exe')
}
if (-not (Test-Path -LiteralPath $SetupPath)) {
    throw ('Setup binary not found: ' + $SetupPath)
}
$SetupPath = [IO.Path]::GetFullPath($SetupPath)

$scratch = Join-Path $env:TEMP ('RdcTransactions-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $scratch | Out-Null

function Assert($condition,[string]$message) {
    if (-not $condition) { throw $message }
}

function Invoke-Setup([string]$destination) {
    $p = Start-Process -FilePath $SetupPath -ArgumentList @(
        '--silent','--no-shortcuts','--no-register','--install-root',('"' + $destination + '"')
    ) -PassThru -Wait
    $code = $p.ExitCode
    $p.Dispose()
    return $code
}

try {
    $install = Join-Path $scratch 'install'
    Assert ((Invoke-Setup $install) -eq 0) 'Fresh isolated setup failed'

    $first = Join-Path $install 'remote-window.ps1'
    [IO.File]::WriteAllText($first,'OLD RUNTIME')
    $before = (Get-FileHash $first).Hash

    # Permit reads/backups but deny atomic replacement of the second file.
    $locked = [IO.File]::Open(
        (Join-Path $install 'divider-caustic.ps'),
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        Assert ((Invoke-Setup $install) -eq 1) 'Setup should fail on a locked payload'
        Assert ((Get-FileHash $first).Hash -eq $before) 'Setup did not roll back the earlier replacement'
    }
    finally {
        $locked.Dispose()
    }

    Assert ((Invoke-Setup $install) -eq 0) 'Setup retry failed'
    Write-Output 'PASS: setup partial-failure rollback and retry'

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $key = [BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($install.ToLowerInvariant()))
        ).Replace('-','')
    }
    finally {
        $sha.Dispose()
    }

    foreach ($prefix in @('Local\RemoteDesktopCommanderWindow-','Local\RDCRelayPayload-')) {
        $mutex = New-Object Threading.Mutex($true,($prefix+$key))
        try {
            Assert ((Invoke-Setup $install) -eq 1) ('Setup ignored mutex ' + $prefix)
        }
        finally {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
    }
    Write-Output 'PASS: setup refuses active window and concurrent payload writer'

    $target = Join-Path $scratch 'update'
    New-Item -ItemType Directory $target | Out-Null
    [IO.File]::WriteAllText((Join-Path $target 'a.txt'),'OLD-A')
    [IO.File]::WriteAllText((Join-Path $target 'b.txt'),'OLD-B')

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $newHash = [BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('NEW'))
        ).Replace('-','')
    }
    finally {
        $sha.Dispose()
    }

    $fakeManifest = @{
        version='2.0.0'
        files=@(
            @{name='a.txt';sha256=$newHash},
            @{name='b.txt';sha256=$newHash}
        )
    } | ConvertTo-Json -Depth 5

    # No network: exercise the real updater against deterministic responses.
    function Invoke-WebRequest {
        param($Uri,$Headers,[switch]$UseBasicParsing,$TimeoutSec,$OutFile)
        if ($OutFile) {
            [IO.File]::WriteAllText($OutFile,'NEW')
            return
        }
        if ($Uri -like '*/commits/*') {
            return [pscustomobject]@{Content=('{"sha":"'+('a'*40)+'"}')}
        }
        return [pscustomobject]@{Content=$fakeManifest}
    }

    $locked = [IO.File]::Open(
        (Join-Path $target 'b.txt'),
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        & (Join-Path $ProjectRoot 'Source\update.ps1') -InstallRoot $target -CurrentVersion '1.0.0' -Force
        Assert ($LASTEXITCODE -eq 1) 'Updater did not report replacement failure'
        Assert ([IO.File]::ReadAllText((Join-Path $target 'a.txt')) -eq 'OLD-A') 'Updater failed to restore first file'
        Assert ([IO.File]::ReadAllText((Join-Path $target 'b.txt')) -eq 'OLD-B') 'Updater damaged locked file'
        Assert (-not (Test-Path (Join-Path $target '.update-state.json'))) 'Failure incorrectly delayed retry'
    }
    finally {
        $locked.Dispose()
    }

    & (Join-Path $ProjectRoot 'Source\update.ps1') -InstallRoot $target -CurrentVersion '1.0.0' -Force
    Assert ($LASTEXITCODE -eq 42) 'Updater retry failed'
    Assert ([IO.File]::ReadAllText((Join-Path $target 'a.txt')) -eq 'NEW') 'Update payload not applied'
    Assert ([IO.File]::ReadAllText((Join-Path $target 'b.txt')) -eq 'NEW') 'Second payload not applied'
    Write-Output 'PASS: updater rollback, failure exit code, immediate retry, success'

    [IO.File]::WriteAllText((Join-Path $target 'remote-window.ps1'),'LOCAL CANDIDATE')
    $candidateVersion = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'Source\version.txt') -Raw).Trim()
    @{
        version=$candidateVersion
        runtimeSha256=(Get-FileHash (Join-Path $target 'remote-window.ps1')).Hash
    } | ConvertTo-Json | Set-Content (Join-Path $target '.local-candidate.json') -Encoding UTF8

    function Invoke-WebRequest {
        throw 'Candidate unexpectedly requested network update'
    }

    & (Join-Path $ProjectRoot 'Source\update.ps1') -InstallRoot $target -CurrentVersion $candidateVersion
    Assert ($LASTEXITCODE -eq 0) 'Candidate pin failed'
    Write-Output 'PASS: local candidate is preserved without network access'
    Write-Output 'TRANSACTION TESTS PASSED'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
