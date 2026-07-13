<#
.SYNOPSIS
在通過本機送件閘門後，把匿名成果網站部署到 Cloudflare Pages。

.DESCRIPTION
預設只做準備檢查並印出命令，不會發佈。必須明確加上 -Publish 才會建立或更新
Cloudflare Pages 專案。預設使用「傳家話」羅馬字 project name；完成後會對實際 HTTPS App URL
再跑一次影片、網址與本機產物閘門。
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{0,56}[a-z0-9])?$')]
    [string]$ProjectName = 'chuan-jia-hua-2026',
    [switch]$Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$siteRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $siteRoot))
$gate = Join-Path $PSScriptRoot 'submission-gate.ps1'
$sync = Join-Path $PSScriptRoot 'sync-deliverables.ps1'
$wrangler = Get-Command wrangler -ErrorAction SilentlyContinue

if ($null -eq $wrangler) {
    throw '找不到 Wrangler CLI；請先安裝並登入後再部署。'
}

& $sync
& $gate -RequireVideo
if ($LASTEXITCODE -ne 0) {
    throw '影片或本機交付閘門尚未通過，拒絕部署。'
}

$pagesAssetLimit = 25MB
$oversizedAssets = @(Get-ChildItem -LiteralPath $siteRoot -File -Recurse | Where-Object {
    $_.Length -ge $pagesAssetLimit
})
if ($oversizedAssets.Count -gt 0) {
    $details = @($oversizedAssets | ForEach-Object {
        "$([IO.Path]::GetRelativePath($siteRoot, $_.FullName)) ($($_.Length) bytes)"
    })
    throw "Cloudflare Pages 單檔必須小於 25 MiB；拒絕部署：$($details -join '、')"
}
Write-Output 'Cloudflare Pages 單檔上限 preflight 通過（全部 < 25 MiB）。'

$textExtensions = [Collections.Generic.HashSet[string]]::new(
    [string[]]@('.css', '.dart', '.html', '.js', '.json', '.md', '.txt', '.yaml', '.yml'),
    [StringComparer]::OrdinalIgnoreCase
)
$anonymousProblems = [Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $siteRoot -File -Recurse) {
    if (-not $textExtensions.Contains($file.Extension) -or $file.Name.EndsWith('.map', [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    $content = Get-Content -Raw -LiteralPath $file.FullName
    if ($content -match '[A-Za-z]:\\Users\\|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}') {
        $anonymousProblems.Add([IO.Path]::GetRelativePath($siteRoot, $file.FullName))
    }
}
if ($anonymousProblems.Count -gt 0) {
    throw "公開目錄含本機使用者路徑或電子郵件，拒絕部署：$($anonymousProblems -join '、')"
}

if (-not $Publish) {
    Write-Output '準備檢查通過；尚未對外發佈。'
    Write-Output "確認要公開後執行："
    Write-Output ".\scripts\deploy-cloudflare-pages.ps1 -ProjectName '$ProjectName' -Publish"
    exit 0
}

Write-Output "即將公開部署傳家話 Pages 專案：$ProjectName"
$deployOutput = @(
    & $wrangler.Source pages deploy $siteRoot `
        --project-name $ProjectName `
        --branch production `
        --commit-dirty=true 2>&1
)
$deployExitCode = $LASTEXITCODE
$deployOutput | ForEach-Object { Write-Output ([string]$_) }
if ($deployExitCode -ne 0) {
    throw "Cloudflare Pages 部署失敗（exit $deployExitCode）。"
}

$deploymentUrls = @([regex]::Matches(
    ($deployOutput -join [Environment]::NewLine),
    'https://[a-z0-9.-]+\.pages\.dev',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
) | ForEach-Object { $_.Value.TrimEnd('/') } | Select-Object -Unique)
if ($deploymentUrls.Count -eq 0) {
    throw '部署完成但無法從 Wrangler 輸出取得 pages.dev URL；請人工核對輸出。'
}

$appUrl = "$($deploymentUrls[0])/deliverables/app/"
& $gate -RequireVideo -RequirePublicUrl -PublicUrl $appUrl
if ($LASTEXITCODE -ne 0) {
    throw "部署已建立，但公開 App 驗證失敗：$appUrl"
}

Write-Output "公開 App 驗證通過：$appUrl"
