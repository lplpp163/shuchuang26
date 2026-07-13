[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Status')]
    [string]$Action = 'Start',

    [ValidateRange(1, 65535)]
    [int]$Port = 8765,

    [switch]$NoBrowser
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$siteDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspaceDirectory = Split-Path -Parent $siteDirectory
$appFile = Join-Path $siteDirectory 'deliverables\app\index.html'
$url = "http://127.0.0.1:$Port/deliverables/app/"
$stateDirectory = Join-Path $workspaceDirectory '.tmp'
$pidFile = Join-Path $stateDirectory "web-server-$Port.pid"
$stdoutLog = Join-Path $stateDirectory "web-server-$Port.out.log"
$stderrLog = Join-Path $stateDirectory "web-server-$Port.err.log"
$stopLauncherName = (-join @([char]0x505C, [char]0x6B62, [char]0x7DB2, [char]0x9801, [char]0x7248)) + '.cmd'

function Get-PortListeners {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Get-ProcessInfo([int]$ProcessId) {
    return Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
}

function Test-ProjectServer($ProcessInfo) {
    if ($null -eq $ProcessInfo) {
        return $false
    }

    $name = [string]$ProcessInfo.Name
    $commandLine = [string]$ProcessInfo.CommandLine
    return (
        $name -match '^python(?:w)?\.exe$' -and
        $commandLine.IndexOf('-m http.server', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine.IndexOf('--bind 127.0.0.1', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine.IndexOf($siteDirectory, [StringComparison]::OrdinalIgnoreCase) -ge 0
    )
}

function Get-ProjectServers {
    $servers = @()
    foreach ($listener in Get-PortListeners) {
        $processInfo = Get-ProcessInfo ([int]$listener.OwningProcess)
        if (Test-ProjectServer $processInfo) {
            $servers += [pscustomobject]@{
                Listener = $listener
                Process = $processInfo
            }
        }
    }
    return $servers
}

function Get-PortOwnerDescription {
    $descriptions = @()
    foreach ($listener in Get-PortListeners) {
        $processInfo = Get-ProcessInfo ([int]$listener.OwningProcess)
        if ($null -eq $processInfo) {
            $descriptions += "PID $($listener.OwningProcess)"
        } else {
            $descriptions += "$($processInfo.Name) (PID $($processInfo.ProcessId))"
        }
    }
    return ($descriptions -join ', ')
}

function Open-App {
    if ($NoBrowser -or -not [string]::IsNullOrWhiteSpace($env:NO_BROWSER)) {
        return
    }

    try {
        Start-Process -FilePath $url | Out-Null
    } catch {
        Write-Warning "The server is running, but the browser could not be opened: $($_.Exception.Message)"
    }
}

function Remove-StateFile {
    if (Test-Path -LiteralPath $pidFile) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
}

try {
    if (-not (Test-Path -LiteralPath $appFile -PathType Leaf)) {
        throw "Flutter Web entry point not found: $appFile"
    }

    if ($Action -eq 'Status') {
        $projectServers = @(Get-ProjectServers)
        if ($projectServers.Count -eq 0) {
            Write-Host "Local web server is not running on port $Port."
            exit 1
        }

        $processIds = @($projectServers | ForEach-Object { [int]$_.Process.ProcessId } | Select-Object -Unique)
        Write-Host "Local web server is running on port $Port (PID $($processIds -join ', '))."
        Write-Host "Open: $url"
        Write-Host "Stop it with: $stopLauncherName $Port"
        exit 0
    }

    if ($Action -eq 'Stop') {
        $listeners = @(Get-PortListeners)
        $projectServers = @(Get-ProjectServers)
        if ($projectServers.Count -eq 0) {
            Remove-StateFile
            if ($listeners.Count -eq 0) {
                Write-Host "Local web server is already stopped on port $Port."
                exit 0
            }

            throw "Port $Port belongs to another program: $(Get-PortOwnerDescription). Nothing was stopped."
        }

        $legacyParents = @()
        foreach ($server in $projectServers) {
            $parentId = [int]$server.Process.ParentProcessId
            $parentInfo = Get-ProcessInfo $parentId
            if (
                $null -ne $parentInfo -and
                ([string]$parentInfo.Name) -ieq 'cmd.exe' -and
                ([string]$parentInfo.CommandLine).IndexOf($workspaceDirectory, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                ([string]$parentInfo.CommandLine).IndexOf('.cmd', [StringComparison]::OrdinalIgnoreCase) -ge 0
            ) {
                $legacyParents += $parentId
            }
        }

        $processIds = @($projectServers | ForEach-Object { [int]$_.Process.ProcessId } | Select-Object -Unique)
        foreach ($processId in $processIds) {
            Stop-Process -Id $processId -Force -ErrorAction Stop
        }
        foreach ($parentId in ($legacyParents | Select-Object -Unique)) {
            Stop-Process -Id $parentId -Force -ErrorAction SilentlyContinue
        }

        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            $remaining = @(Get-PortListeners | Where-Object { [int]$_.OwningProcess -in $processIds })
            if ($remaining.Count -eq 0) {
                break
            }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)

        Remove-StateFile
        Write-Host "Stopped local web server on port $Port (PID $($processIds -join ', '))."
        exit 0
    }

    $listeners = @(Get-PortListeners)
    $projectServers = @(Get-ProjectServers)
    if ($listeners.Count -gt 0) {
        if ($projectServers.Count -eq 0) {
            throw "Port $Port is already in use by $(Get-PortOwnerDescription). Choose another port or close that program."
        }

        $processIds = @($projectServers | ForEach-Object { [int]$_.Process.ProcessId } | Select-Object -Unique)
        Write-Host "Local web server is already running on port $Port (PID $($processIds -join ', '))."
        Write-Host 'No second server was started.'
        Write-Host "Open: $url"
        Write-Host "Stop it with: $stopLauncherName $Port"
        Open-App
        exit 0
    }

    $pythonCommand = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pythonPrefix = ''
    if ($null -eq $pythonCommand) {
        $pythonCommand = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $pythonPrefix = '-3 '
    }
    if ($null -eq $pythonCommand) {
        throw 'Python 3 was not found. Install Python 3 and run this file again.'
    }

    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $argumentLine = "$($pythonPrefix)-u -m http.server $Port --bind 127.0.0.1 --directory `"$siteDirectory`""
    $serverProcess = Start-Process `
        -FilePath $pythonCommand.Source `
        -ArgumentList $argumentLine `
        -WorkingDirectory $siteDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru

    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        $serverProcess.Refresh()
        if ($serverProcess.HasExited) {
            break
        }

        $ownedListener = @(Get-PortListeners | Where-Object { [int]$_.OwningProcess -eq $serverProcess.Id })
        if ($ownedListener.Count -gt 0) {
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 2
                if ([int]$response.StatusCode -eq 200) {
                    $ready = $true
                    break
                }
            } catch {
                # The socket can be ready a moment before the first HTTP response.
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    if (-not $ready) {
        if (-not $serverProcess.HasExited) {
            Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
        }
        $detail = ''
        if (Test-Path -LiteralPath $stderrLog) {
            $detail = ((Get-Content -LiteralPath $stderrLog -Tail 8 -ErrorAction SilentlyContinue) -join ' ')
        }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = 'No error details were written.'
        }
        throw "The local web server did not become ready. $detail"
    }

    Set-Content -LiteralPath $pidFile -Value $serverProcess.Id -Encoding Ascii
    Write-Host "Started local web server in the background on port $Port (PID $($serverProcess.Id))."
    Write-Host 'Running this launcher again will reuse the same server.'
    Write-Host "Open: $url"
    Write-Host "Logs: $stderrLog"
    Write-Host "Stop it with: $stopLauncherName $Port"
    Open-App
    exit 0
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
