$ErrorActionPreference = "Stop"

$siteRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $siteRoot
$sitePrefix = $siteRoot.TrimEnd("\") + "\"

$files = @(
    @{
        Label = "最新計畫書 PDF"
        Source = "交付成果\計畫書\2026臺灣數創大賞_數位組創業計畫書_島語通_AI正式版.pdf"
        Destination = "deliverables\plan\DaoTalk-AI-plan.pdf"
    },
    @{
        Label = "最新計畫書 DOCX"
        Source = "交付成果\計畫書\2026臺灣數創大賞_數位組創業計畫書_島語通_AI正式版.docx"
        Destination = "deliverables\plan\DaoTalk-AI-plan.docx"
    },
    @{
        Label = "計畫書版面預覽"
        Source = "交付成果\計畫書\AI正式版_QA\verified-contact-sheet.png"
        Destination = "deliverables\previews\plan-contact-sheet.png"
    },
    @{
        Label = "正式 Demo HTML"
        Source = "正式版\frontend\index.html"
        Destination = "deliverables\demo\index.html"
    },
    @{
        Label = "正式 Demo CSS"
        Source = "正式版\frontend\styles.css"
        Destination = "deliverables\demo\styles.css"
    },
    @{
        Label = "正式 Demo JavaScript"
        Source = "正式版\frontend\app.js"
        Destination = "deliverables\demo\app.js"
    },
    @{
        Label = "正式影片 HTML"
        Source = "正式版\video\index.html"
        Destination = "deliverables\video\index.html"
    },
    @{
        Label = "正式影片 CSS"
        Source = "正式版\video\styles.css"
        Destination = "deliverables\video\styles.css"
    },
    @{
        Label = "正式影片 JavaScript"
        Source = "正式版\video\app.js"
        Destination = "deliverables\video\app.js"
    },
    @{
        Label = "影片旁白逐字稿"
        Source = "正式版\video\旁白逐字稿.md"
        Destination = "deliverables\video\narration.md"
    },
    @{
        Label = "影片合成薪資單圖片"
        Source = "正式版\sample_documents\合成薪資明細_中越_清晰.png"
        Destination = "deliverables\sample_documents\合成薪資明細_中越_清晰.png"
    },
    @{
        Label = "合成薪資單 PDF"
        Source = "正式版\sample_documents\合成薪資明細_中越.pdf"
        Destination = "deliverables\sample_documents\synthetic-payroll.pdf"
    },
    @{
        Label = "訪談素材列印版"
        Source = "交付成果\移工訪談素材包\訪談素材列印版.html"
        Destination = "deliverables\interview\index.html"
    },
    @{
        Label = "正式產品首頁預覽"
        Source = "交付成果\QA截圖\正式版_首頁.png"
        Destination = "deliverables\previews\product-home.png"
    },
    @{
        Label = "正式產品結果預覽"
        Source = "交付成果\QA截圖\正式版_結果.png"
        Destination = "deliverables\previews\product-result.png"
    },
    @{
        Label = "訪談素材預覽"
        Source = "交付成果\QA截圖\訪談素材列印版.png"
        Destination = "deliverables\previews\interview.png"
    },
    @{
        Label = "正式影片 13 幕預覽"
        Source = "正式版\video\QA\contact-sheet.png"
        Destination = "deliverables\previews\video-contact-sheet.png"
    },
    @{
        Label = "正式版嚴格驗收報告"
        Source = "正式版\嚴格驗收報告.md"
        Destination = "deliverables\docs\acceptance-report.md"
    },
    @{
        Label = "正式版技術架構"
        Source = "正式版\docs\正式版技術架構.md"
        Destination = "deliverables\docs\technical-architecture.md"
    },
    @{
        Label = "AI 評估規格"
        Source = "正式版\docs\AI評估規格.md"
        Destination = "deliverables\docs\evaluation-spec.md"
    },
    @{
        Label = "後端驗證紀錄"
        Source = "正式版\backend\VALIDATION.md"
        Destination = "deliverables\docs\backend-validation.md"
    },
    @{
        Label = "Offline mock 評測報告"
        Source = "正式版\evals\reports\backend_offline_mock.md"
        Destination = "deliverables\docs\offline-mock-report.md"
    }
)

$records = foreach ($file in $files) {
    $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $file.Source))
    $destination = [IO.Path]::GetFullPath((Join-Path $siteRoot $file.Destination))

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "找不到交付來源：$source"
    }
    if (-not $destination.StartsWith($sitePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "同步目標超出網站儲存庫：$destination"
    }

    $destinationDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    Copy-Item -Force -LiteralPath $source -Destination $destination

    $sourceItem = Get-Item -LiteralPath $source
    $destinationItem = Get-Item -LiteralPath $destination
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "同步後雜湊不一致：$($file.Label)"
    }

    [ordered]@{
        label = $file.Label
        source = $file.Source.Replace("\", "/")
        destination = $file.Destination.Replace("\", "/")
        bytes = $destinationItem.Length
        source_modified_at = $sourceItem.LastWriteTime.ToString("o")
        sha256 = $destinationHash
    }
}

$manifest = [ordered]@{
    source_of_truth = "交付成果/README.md"
    synced_at = (Get-Date).ToString("o")
    files = @($records)
}

$manifestPath = Join-Path $siteRoot "deliverables\manifest.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText(
    $manifestPath,
    $manifestJson + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

Write-Output "已同步 $($records.Count) 個最新交付檔案。"
Write-Output $manifestPath
