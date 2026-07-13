$ErrorActionPreference = 'Stop'

$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) {
    'flutter'
} elseif (Test-Path 'C:\tools\flutter\bin\flutter.bat') {
    'C:\tools\flutter\bin\flutter.bat'
} else {
    throw '找不到 Flutter SDK'
}

& $flutter build web --base-href / --pwa-strategy=none
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$indexPath = Join-Path $PSScriptRoot '..\build\web\index.html'
$indexPath = (Resolve-Path $indexPath).Path
$content = [System.IO.File]::ReadAllText($indexPath)
if ($content.Contains('<base href="/">')) {
    $content = $content.Replace('<base href="/">', '<base href="./">')
    [System.IO.File]::WriteAllText(
        $indexPath,
        $content,
        [System.Text.UTF8Encoding]::new($false)
    )
} elseif (-not $content.Contains('<base href="./">')) {
    throw 'Flutter web output did not contain a supported root or relative base href.'
}

$bootstrapPath = Join-Path $PSScriptRoot '..\build\web\flutter_bootstrap.js'
$bootstrap = [System.IO.File]::ReadAllText((Resolve-Path $bootstrapPath).Path)
if ($bootstrap.TrimEnd() -notmatch '_flutter\.loader\.load\(\);$') {
    throw 'Flutter web output still boots with service-worker settings.'
}

$serviceWorkerPath = Join-Path $PSScriptRoot '..\build\web\flutter_service_worker.js'
if ((Test-Path -LiteralPath $serviceWorkerPath) -and
    (Get-Item -LiteralPath $serviceWorkerPath).Length -ne 0) {
    throw 'Flutter web output still contains a non-empty service worker.'
}

Write-Host "Built relative web bundle: $indexPath"
