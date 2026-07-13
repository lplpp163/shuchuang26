<#
.SYNOPSIS
以隔離的隨機連接埠驗證啟動器單例、狀態查詢及停止器 PID 所有權。

.DESCRIPTION
不使用預設 8765，也不開瀏覽器。測試會連續執行兩次啟動 CMD，確認 PID
完全相同且只有一個本專案 Python listener，再以停止 CMD 關閉同一 PID。
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$siteRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $siteRoot))
$startLauncherName = (-join @([char]0x555F, [char]0x52D5, [char]0x7DB2, [char]0x9801, [char]0x7248)) + '.cmd'
$stopLauncherName = (-join @([char]0x505C, [char]0x6B62, [char]0x7DB2, [char]0x9801, [char]0x7248)) + '.cmd'
$launcherRoot = if (Test-Path -LiteralPath (Join-Path $workspaceRoot $startLauncherName) -PathType Leaf) {
    $workspaceRoot
} else {
    $siteRoot
}
$startLauncher = Join-Path $launcherRoot $startLauncherName
$stopLauncher = Join-Path $launcherRoot $stopLauncherName
$stateRoot = Join-Path $workspaceRoot '.tmp'

foreach ($required in @($startLauncher, $stopLauncher, (Join-Path $siteRoot 'deliverables\app\index.html'))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required launcher-test file is missing: $required"
    }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$pidFile = Join-Path $stateRoot "web-server-$port.pid"
$logFiles = @(
    Join-Path $stateRoot "web-server-$port.out.log"
    Join-Path $stateRoot "web-server-$port.err.log"
)
$previousNoBrowser = $env:NO_BROWSER
$previousNoPause = $env:NO_PAUSE
$env:NO_BROWSER = '1'
$env:NO_PAUSE = '1'

function Invoke-CmdLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $quotedArguments = @($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
    })
    $command = '/d /c call "' + $Path + '" ' + ($quotedArguments -join ' ')
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList $command -PassThru -WindowStyle Hidden
    try {
        # Process.WaitForExit waits for this cmd.exe only. PowerShell's
        # Start-Process -Wait would also wait for the intentionally persistent
        # background Python descendant and would therefore never return here.
        if (-not $process.WaitForExit(20000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "CMD launcher timed out: $Path $($Arguments -join ' ')"
        }
        if ($process.ExitCode -ne 0) {
            throw "CMD launcher failed (exit $($process.ExitCode)): $Path $($Arguments -join ' ')"
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-TestProjectProcesses {
    return @(Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $commandLine = [string]$_.CommandLine
        $commandLine.IndexOf("http.server $port", [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine.IndexOf($siteRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
}

$startedPid = $null
try {
    Invoke-CmdLauncher -Path $startLauncher -Arguments @([string]$port)
    if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) {
        throw "First start did not create the PID file: $pidFile"
    }
    $startedPid = [int](Get-Content -Raw -LiteralPath $pidFile)
    $firstProcesses = @(Get-TestProjectProcesses)
    if ($firstProcesses.Count -ne 1 -or [int]$firstProcesses[0].ProcessId -ne $startedPid) {
        throw "First start was not a unique PID; tracked=$startedPid, found=$($firstProcesses.ProcessId -join ',')"
    }

    Invoke-CmdLauncher -Path $startLauncher -Arguments @([string]$port)
    $secondPid = [int](Get-Content -Raw -LiteralPath $pidFile)
    $secondProcesses = @(Get-TestProjectProcesses)
    if ($secondPid -ne $startedPid -or $secondProcesses.Count -ne 1 -or
        [int]$secondProcesses[0].ProcessId -ne $startedPid) {
        throw "Repeated start created an extra server; first=$startedPid, tracked=$secondPid, found=$($secondProcesses.ProcessId -join ',')"
    }
    Invoke-CmdLauncher -Path $startLauncher -Arguments @('status', [string]$port)

    Invoke-CmdLauncher -Path $stopLauncher -Arguments @([string]$port)
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        if ($null -eq (Get-Process -Id $startedPid -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($null -ne (Get-Process -Id $startedPid -ErrorAction SilentlyContinue)) {
        throw "Stop launcher did not terminate PID $startedPid."
    }
    if (@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count -ne 0) {
        throw "Port $port is still listening after the stop launcher ran."
    }
    if (Test-Path -LiteralPath $pidFile) {
        throw 'Stop launcher did not remove the PID file.'
    }

    [pscustomobject]@{
        validation = 'PASS'
        port = $port
        firstPid = $startedPid
        secondPid = $secondPid
        processCountAfterSecondStart = $secondProcesses.Count
        stoppedPid = $startedPid
    } | ConvertTo-Json
}
finally {
    if ($null -ne $startedPid -and $null -ne (Get-Process -Id $startedPid -ErrorAction SilentlyContinue)) {
        & (Join-Path $PSScriptRoot 'local-web-server.ps1') -Action Stop -Port $port -NoBrowser | Out-Null
    }
    foreach ($path in @($pidFile) + $logFiles) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    $env:NO_BROWSER = $previousNoBrowser
    $env:NO_PAUSE = $previousNoPause
}
