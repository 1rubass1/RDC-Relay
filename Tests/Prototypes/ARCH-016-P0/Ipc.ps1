# ARCH-016-P0 local-only fake state IPC; never expose arbitrary commands.
function Assert-ProbePipeName([string]$Name) {
    if ($Name -cnotmatch '^rdcrelay-arch016p0-[0-9a-f]{32}$') {
        throw 'Refusing non-prototype pipe name'
    }
}
function Invoke-ProbePipe {
    param([Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$Command,
          [int]$TimeoutMs=1500)
    Assert-ProbePipeName $Name
    $client=New-Object IO.Pipes.NamedPipeClientStream(
        '.', $Name, [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::None)
    $reader=$null;$writer=$null
    try {
        $client.Connect($TimeoutMs)
        $encoding=New-Object Text.UTF8Encoding($false)
        $reader=New-Object IO.StreamReader($client,$encoding,$false,1024,$true)
        $writer=New-Object IO.StreamWriter($client,$encoding,1024,$true)
        $writer.AutoFlush=$true
        $writer.WriteLine($Command)
        # Bound the fixture client's response wait as well as Connect. This is
        # cooperative test reliability, not a production IPC framing protocol.
        $responseTask=$reader.ReadLineAsync()
        if (-not $responseTask.Wait($TimeoutMs)) { throw 'Prototype IPC response timeout' }
        $raw=$responseTask.Result
        if (-not $raw) { throw 'Pipe response missing' }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } finally {
        if ($writer) {$writer.Dispose()}
        if ($reader) {$reader.Dispose()}
        $client.Dispose()
    }
}
