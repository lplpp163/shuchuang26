param(
  [switch]$SkipFlutterTests
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) {
  'flutter'
} elseif (Test-Path 'C:\tools\flutter\bin\flutter.bat') {
  'C:\tools\flutter\bin\flutter.bat'
} else {
  throw '找不到 Flutter SDK'
}
$dart = if (Get-Command dart -ErrorAction SilentlyContinue) {
  'dart'
} else {
  'C:\tools\flutter\bin\dart.bat'
}
Push-Location $projectRoot
try {
  $forbidden = 'Claude|Anthropic|AI 串接|AI 教練|瀏覽器 AI|AI 聽懂|AI 只聽|發音正確|即時生成|圖片、聲音與四種玩法|你幫角色說對了|聲音已放進|聲音卡 \+1'
  $matches = & rg -n --glob '*.dart' --glob '!build/**' $forbidden lib 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host '品質閘門失敗：仍有誤導性或供應商專屬文案。'
    $matches | Write-Host
    exit 1
  }
  if ($LASTEXITCODE -gt 1) {
    throw 'rg 搜尋失敗'
  }

  & $dart format --output=none --set-exit-if-changed lib test
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  & $flutter analyze
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  if (-not $SkipFlutterTests) {
    & $flutter test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }

  if ($SkipFlutterTests) {
    Write-Host '品質閘門通過：文案、格式與靜態分析符合要求（本次略過測試）。'
  } else {
    Write-Host '品質閘門通過：文案、格式、靜態分析與測試皆符合要求。'
  }
}
finally {
  Pop-Location
}
