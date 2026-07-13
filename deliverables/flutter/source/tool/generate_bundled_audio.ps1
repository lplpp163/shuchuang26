[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PiperExe,

    [Parameter(Mandatory = $true)]
    [string]$ModelPath,

    [string]$DartExe = "C:\tools\flutter\bin\dart.bat",

    [string]$FfmpegExe = "ffmpeg"
)

$ErrorActionPreference = "Stop"
$expectedModelSha256 = "EC7C89E2C85F4D1EDC24B6120C18AAF1BDA614F06B511567EB9C7C0DE15E2DAB"
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$catalogTool = Join-Path $PSScriptRoot "bundled_audio_catalog.dart"
$outputRoot = Join-Path $projectRoot "assets\audio"

foreach ($path in @($PiperExe, $ModelPath, $DartExe)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash -ne $expectedModelSha256) {
    throw "Unexpected Piper model hash. Use the pinned vi_VN-vais1000-medium v1.0.0 model."
}
if ($PiperExe -match "[^\x00-\x7F]" -or $ModelPath -match "[^\x00-\x7F]") {
    throw "Piper on Windows cannot reliably load models through non-ASCII paths. Use an ASCII path or junction."
}

function Invoke-PiperLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PiperExe
    $startInfo.WorkingDirectory = Split-Path -Parent $PiperExe
    $startInfo.ArgumentList.Add("--model")
    $startInfo.ArgumentList.Add($ModelPath)
    $startInfo.ArgumentList.Add("--output_file")
    $startInfo.ArgumentList.Add($OutputPath)
    $startInfo.ArgumentList.Add("--sentence_silence")
    $startInfo.ArgumentList.Add("0.12")
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $process.StandardInput.WriteLine($Text)
    $process.StandardInput.Close()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Piper failed for '$Text': $stderr"
    }
}

Push-Location $projectRoot
try {
    $catalogLines = @(& $DartExe run $catalogTool)
    if ($LASTEXITCODE -ne 0) { throw "Audio catalog failed with exit code $LASTEXITCODE" }
    if ($catalogLines.Count -ne 119) {
        throw "Expected 119 referenced audio assets, found $($catalogLines.Count)."
    }

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "hometongue-piper-audio"
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    $manifest = [Collections.Generic.List[object]]::new()

    foreach ($line in $catalogLines) {
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { throw "Invalid catalog row: $line" }
        $relativePath = $parts[0]
        $text = $parts[1]
        $outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $relativePath))
        if (-not $outputPath.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Catalog output escapes assets/audio: $relativePath"
        }

        $basename = [IO.Path]::GetFileNameWithoutExtension($outputPath)
        $temporaryWav = Join-Path $temporaryRoot "$basename.wav"
        Invoke-PiperLine -Text $text -OutputPath $temporaryWav
        & $FfmpegExe -hide_banner -loglevel error -y -i $temporaryWav -codec:a libmp3lame -q:a 5 -ar 22050 -ac 1 $outputPath
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for $relativePath" }
        $item = Get-Item -LiteralPath $outputPath
        if ($item.Length -le 0) { throw "Generated an empty audio file: $relativePath" }
        $manifest.Add([ordered]@{
            path = $relativePath.Replace("\", "/")
            text = $text
            bytes = $item.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
        })
        Remove-Item -Force -LiteralPath $temporaryWav
    }

    $manifestPath = Join-Path $outputRoot "piper_generation_manifest.json"
    $manifestDocument = [ordered]@{
        generator = "Piper 1.2.0"
        model = "rhasspy/piper-voices v1.0.0 vi_VN-vais1000-medium"
        model_sha256 = $expectedModelSha256
        dataset_license = "CC BY 4.0"
        generated_at = (Get-Date).ToString("o")
        files = @($manifest)
    }
    [IO.File]::WriteAllText(
        $manifestPath,
        ($manifestDocument | ConvertTo-Json -Depth 5) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    Write-Output "Generated $($manifest.Count) pinned Piper MP3 files."
    Write-Output $manifestPath
}
finally {
    Pop-Location
}
