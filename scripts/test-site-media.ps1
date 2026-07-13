<#
.SYNOPSIS
以 Playwright 驗證團隊網站的影片有聲按鈕與 119 個 App 音訊資產。
#>
[CmdletBinding()]
param(
    [string]$SiteUrl = 'http://127.0.0.1:8765/',
    [string]$BrowserChannel = 'msedge'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$siteRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $siteRoot))
$nodeModules = Join-Path $projectRoot '正式版\flutter_app\node_modules'
$runner = Join-Path $nodeModules '.bin\playwright.cmd'
$config = Join-Path $PSScriptRoot 'site-media.playwright.config.js'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "找不到 Playwright；請先在正式版/flutter_app 安裝鎖定的 npm dependencies：$runner"
}

$previousNodePath = $env:NODE_PATH
$previousSiteUrl = $env:SITE_URL
$previousChannel = $env:PLAYWRIGHT_CHANNEL
try {
    $env:NODE_PATH = $nodeModules
    $env:SITE_URL = $SiteUrl
    $env:PLAYWRIGHT_CHANNEL = $BrowserChannel
    & $runner test --config=$config --reporter=line --workers=1
    if ($LASTEXITCODE -ne 0) {
        throw "網站媒體 Playwright 驗證失敗（exit $LASTEXITCODE）。"
    }
}
finally {
    $env:NODE_PATH = $previousNodePath
    $env:SITE_URL = $previousSiteUrl
    $env:PLAYWRIGHT_CHANNEL = $previousChannel
}
