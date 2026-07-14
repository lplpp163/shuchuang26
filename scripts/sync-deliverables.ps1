$ErrorActionPreference = "Stop"

$siteRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $siteRoot))
$sitePrefix = $siteRoot.TrimEnd("\") + "\"

function Assert-InsideSite {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($sitePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "同步目標超出團隊進度網站：$resolved"
    }
    return $resolved
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFullPath = [IO.Path]::GetFullPath($BasePath)
    if (-not $baseFullPath.EndsWith([IO.Path]::DirectorySeparatorChar.ToString(), [StringComparison]::Ordinal)) {
        $baseFullPath += [IO.Path]::DirectorySeparatorChar
    }
    $targetFullPath = [IO.Path]::GetFullPath($TargetPath)
    $baseUri = [Uri]$baseFullPath
    $targetUri = [Uri]$targetFullPath
    if (-not $baseUri.IsBaseOf($targetUri)) {
        throw "Relative-path target is outside its base: $targetFullPath"
    }

    $relativeUri = $baseUri.MakeRelativeUri($targetUri).ToString()
    return [Uri]::UnescapeDataString($relativeUri).Replace('/', [IO.Path]::DirectorySeparatorChar)
}

function Assert-NoLegacyTopic {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$SourceText
    )

    # The widget test intentionally proves that the former title is absent.
    # Remove only that exact negative assertion before running the source scan;
    # a visible copy change or any other occurrence must still fail the sync.
    $negativeBrandAssertions = @(
        "expect(find.text('我們家怎麼說'), findsNothing);",
        "expect(find.text('聽家人說，換你回一句'), findsNothing);"
    )
    if ($Source.EndsWith("\正式版\flutter_app\test\widget_test.dart", [StringComparison]::OrdinalIgnoreCase)) {
        foreach ($negativeBrandAssertion in $negativeBrandAssertions) {
            if ($SourceText.IndexOf($negativeBrandAssertion, [StringComparison]::Ordinal) -lt 0) {
                throw "品牌拒絕回歸測試缺失或已改形：$Source"
            }
            $SourceText = $SourceText.Replace($negativeBrandAssertion, "")
        }
    }

    if ($SourceText -match "聽家人說，換你回一句|我們家怎麼說|島語通|DaoTalk|WorkBridge|移工職場文件|合成薪資單|家語貼|HomeTongue Tags|14項|十四項|三種Android|Android競賽包") {
        throw "來源仍包含前一個題目的內容，拒絕同步：$Source"
    }
}

function Copy-VerifiedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$SourceRelativePath,
        [Parameter(Mandatory = $true)][string]$DestinationRelativePath
    )

    $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $SourceRelativePath))
    $destination = Assert-InsideSite (Join-Path $siteRoot $DestinationRelativePath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "找不到『傳家話』交付來源：$source"
    }

    $textExtensions = @(".md", ".txt", ".json", ".yaml", ".yml", ".dart", ".html", ".css")
    if ($textExtensions -contains ([IO.Path]::GetExtension($source).ToLowerInvariant())) {
        $sourceText = Get-Content -Raw -Encoding UTF8 -LiteralPath $source
        Assert-NoLegacyTopic -Source $source -SourceText $sourceText
    }

    $destinationDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    Copy-Item -Force -LiteralPath $source -Destination $destination

    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "同步後雜湊不一致：$Label"
    }

    $sourceItem = Get-Item -LiteralPath $source
    $destinationItem = Get-Item -LiteralPath $destination
    return [ordered]@{
        label = $Label
        source = $SourceRelativePath.Replace("\", "/")
        destination = $DestinationRelativePath.Replace("\", "/")
        bytes = $destinationItem.Length
        source_modified_at = $sourceItem.LastWriteTime.ToString("o")
        sha256 = $destinationHash
    }
}

$records = [Collections.Generic.List[object]]::new()

# 正式公開路徑已改用「傳家話」的 chuan-jia-hua slug。同步前只清除這四個
# 明確列出的舊鏡像檔，避免網站同時留下兩套品牌或 gate 將舊檔誤判為成品。
foreach ($staleRelativePath in @(
    "deliverables\plan\our-family-says-plan.pdf",
    "deliverables\plan\our-family-says-plan.docx",
    "deliverables\video\our-family-says-submission.mp4",
    "deliverables\review\native-review-portable.zip"
)) {
    $stalePath = Assert-InsideSite (Join-Path $siteRoot $staleRelativePath)
    if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
        Remove-Item -LiteralPath $stalePath -Force
    }
}

$deliverables = @(
    @{
        Label = "『傳家話』計畫書 PDF"
        Source = "交付成果\計畫書\2026臺灣數創大賞_數位組創業計畫書_傳家話_正式版.pdf"
        Destination = "deliverables\plan\chuan-jia-hua-plan.pdf"
    },
    @{
        Label = "『傳家話』計畫書 DOCX"
        Source = "交付成果\計畫書\2026臺灣數創大賞_數位組創業計畫書_傳家話_正式版.docx"
        Destination = "deliverables\plan\chuan-jia-hua-plan.docx"
    },
    @{
        Label = "3 分鐘初審影片分鏡與旁白"
        Source = "交付成果\影片\傳家話_初審影片分鏡與旁白.md"
        Destination = "deliverables\video\narration.md"
    },
    @{
        Label = "『傳家話』初審影片 Web 預覽"
        Source = "交付成果\影片\傳家話_網頁預覽.mp4"
        Destination = "deliverables\video\chuan-jia-hua-submission.mp4"
    },
    @{
        Label = "『傳家話』正式初審影片驗證"
        Source = "交付成果\影片\傳家話_正式初審影片_驗證.json"
        Destination = "deliverables\video\verification.json"
    },
    @{
        Label = "『傳家話』正式初審影片內容設定"
        Source = "交付成果\影片\video_content.json"
        Destination = "deliverables\video\video_content.json"
    },
    @{
        Label = "『傳家話』正式初審影片重建腳本"
        Source = "交付成果\影片\build_submission_video.ps1"
        Destination = "deliverables\video\build_submission_video.ps1"
    },
    @{
        Label = "『傳家話』正式初審影片製作說明"
        Source = "交付成果\影片\正式影片製作說明.md"
        Destination = "deliverables\video\production-notes.md"
    },
    @{
        Label = "『傳家話』嚴格驗收報告"
        Source = "交付成果\嚴格驗收報告.md"
        Destination = "deliverables\docs\strict-review.md"
    },
    @{
        Label = "『傳家話』技術驗證紀錄"
        Source = "交付成果\作品\傳家話_技術驗證紀錄.md"
        Destination = "deliverables\docs\technical-validation.md"
    },
    @{
        Label = "『傳家話』家庭需求與試演問卷"
        Source = "交付成果\問卷\傳家話_新住民家庭需求與試演問卷.md"
        Destination = "deliverables\docs\family-pilot-questionnaire.md"
    },
    @{
        Label = "『傳家話』四週教師家庭延伸情境包"
        Source = "交付成果\導入\傳家話_教師家庭延伸情境包_四週試辦版.pdf"
        Destination = "deliverables\pilot\teacher-family-extension-pack.pdf"
    },
    @{
        Label = "『傳家話』四週試辦包重建與證據說明"
        Source = "交付成果\導入\README.md"
        Destination = "deliverables\pilot\README.md"
    },
    @{
        Label = "『傳家話』四週試辦包 QA"
        Source = "交付成果\導入\QA\檢查摘要.json"
        Destination = "deliverables\pilot\qa-summary.json"
    },
    @{
        Label = "『傳家話』匿名試辦彙整台"
        Source = "交付成果\導入\傳家話_匿名試辦彙整台.html"
        Destination = "deliverables\pilot\evidence-workbench.html"
    },
    @{
        Label = "『傳家話』越南語 119 句母語審閱工具"
        Source = "交付成果\語言審閱\傳家話_越南語119句母語審閱工具.html"
        Destination = "deliverables\review\index.html"
    },
    @{
        Label = "『傳家話』越南語母語審閱說明"
        Source = "交付成果\語言審閱\README.md"
        Destination = "deliverables\review\README.md"
    },
    @{
        Label = "『傳家話』越南語 119 句語境目錄"
        Source = "交付成果\語言審閱\傳家話_越南語119句語境目錄.json"
        Destination = "deliverables\review\context-catalog.json"
    },
    @{
        Label = "『傳家話』越南語母語審閱可攜包"
        Source = "交付成果\語言審閱\傳家話_越南語119句母語審閱可攜包.zip"
        Destination = "deliverables\review\chuan-jia-hua-native-review-portable.zip"
    }
)

# 先完成送審主檔預檢，避免同步到一半才發現某個來源仍是舊題目。
foreach ($item in $deliverables) {
    $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $item.Source))
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "找不到『傳家話』交付來源：$source"
    }
    $textExtensions = @(".md", ".txt", ".json", ".yaml", ".yml", ".dart", ".html", ".css")
    if ($textExtensions -contains ([IO.Path]::GetExtension($source).ToLowerInvariant())) {
        $sourceText = Get-Content -Raw -Encoding UTF8 -LiteralPath $source
        Assert-NoLegacyTopic -Source $source -SourceText $sourceText
    }
}

foreach ($item in $deliverables) {
    $records.Add((Copy-VerifiedFile -Label $item.Label -SourceRelativePath $item.Source -DestinationRelativePath $item.Destination))
}

$flutterRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot "正式版\flutter_app"))
$flutterDestinationRoot = Assert-InsideSite (Join-Path $siteRoot "deliverables\flutter\source")
if (-not (Test-Path -LiteralPath $flutterRoot -PathType Container)) {
    throw "找不到 Flutter 專案：$flutterRoot"
}

if (Test-Path -LiteralPath $flutterDestinationRoot) {
    # 目標已先經 Assert-InsideSite 驗證，只會清理網站內的鏡像目錄。
    Remove-Item -Recurse -Force -LiteralPath $flutterDestinationRoot
}
New-Item -ItemType Directory -Force -Path $flutterDestinationRoot | Out-Null

$flutterRootFiles = @("README.md", "QUALITY_SCORECARD.md", "OPEN_SOURCE_NOTICES.md", "pubspec.yaml", "pubspec.lock", "package.json", "package-lock.json", "analysis_options.yaml", ".metadata", ".gitignore")
foreach ($fileName in $flutterRootFiles) {
    $source = Join-Path $flutterRoot $fileName
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Flutter 鏡像缺少必要檔案：$source"
    }
    $sourceRelative = Get-RelativePathCompat -BasePath $projectRoot -TargetPath $source
    $destinationRelative = Join-Path "deliverables\flutter\source" $fileName
    $records.Add((Copy-VerifiedFile -Label "Flutter $fileName" -SourceRelativePath $sourceRelative -DestinationRelativePath $destinationRelative))
}

foreach ($folderName in @("lib", "test")) {
    $folder = Join-Path $flutterRoot $folderName
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "Flutter 鏡像缺少必要目錄：$folder"
    }
    $files = Get-ChildItem -LiteralPath $folder -File -Recurse | Where-Object { $_.Extension -eq ".dart" }
    if ($files.Count -eq 0) {
        throw "Flutter $folderName 目錄沒有 Dart 原始碼。"
    }
    foreach ($file in $files) {
        $sourceRelative = Get-RelativePathCompat -BasePath $projectRoot -TargetPath $file.FullName
        $flutterRelative = Get-RelativePathCompat -BasePath $flutterRoot -TargetPath $file.FullName
        $destinationRelative = Join-Path "deliverables\flutter\source" $flutterRelative
        $records.Add((Copy-VerifiedFile -Label "Flutter $($flutterRelative.Replace('\', '/'))" -SourceRelativePath $sourceRelative -DestinationRelativePath $destinationRelative))
    }
}

$flutterToolFiles = @(
    "build_web_relative.ps1",
    "bundled_audio_catalog.dart",
    "conversation_audio_catalog.dart",
    "deliverables_media.spec.js",
    "generate_bundled_audio.ps1",
    "generate_native_review_packet.py",
    "native_review.spec.js",
    "pilot_workbench.spec.js",
    "playwright.config.js",
    "quality_gate.ps1",
    "visual_audit.spec.js",
    "web_smoke.spec.js"
)
foreach ($fileName in $flutterToolFiles) {
    $source = Join-Path $flutterRoot (Join-Path "tool" $fileName)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Flutter 驗證工具缺少必要檔案：$source"
    }
    $sourceRelative = Get-RelativePathCompat -BasePath $projectRoot -TargetPath $source
    $destinationRelative = Join-Path "deliverables\flutter\source\tool" $fileName
    $records.Add((Copy-VerifiedFile -Label "Flutter tool/$fileName" -SourceRelativePath $sourceRelative -DestinationRelativePath $destinationRelative))
}

# 預載短句、分詞與家庭劇場素材是初學流程的一部分；同步原始碼時必須連同
# 音訊、插圖、字型與說明檔鏡像，否則原始碼鏡像無法重現 Playwright 流程。
$flutterAssetsRoot = Join-Path $flutterRoot "assets"
$emptyAssets = @(Get-ChildItem -LiteralPath $flutterAssetsRoot -File -Recurse | Where-Object { $_.Length -eq 0 })
if ($emptyAssets.Count -gt 0) {
    $emptyList = ($emptyAssets.FullName -join [Environment]::NewLine)
    throw "Flutter assets 包含空檔案，拒絕同步：$([Environment]::NewLine)$emptyList"
}
$syntheticAudio = Join-Path $flutterAssetsRoot "audio\vietnamese_short_demo.mp3"
if (-not (Test-Path -LiteralPath $syntheticAudio -PathType Leaf)) {
    throw "Flutter 專案缺少標示為合成示範的越南語音訊：$syntheticAudio"
}
$chunkAudio = Join-Path $flutterAssetsRoot "audio\vietnamese_chunk_day_la.mp3"
if (-not (Test-Path -LiteralPath $chunkAudio -PathType Leaf)) {
    throw "Flutter 專案缺少可獨立播放的越南語分詞音訊：$chunkAudio"
}
$audioRoot = Join-Path $flutterAssetsRoot "audio"
$audioManifestPath = Join-Path $audioRoot "piper_generation_manifest.json"
if (-not (Test-Path -LiteralPath $audioManifestPath -PathType Leaf)) {
    throw "Flutter 專案缺少隨包音檔來源 manifest：$audioManifestPath"
}
$audioManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $audioManifestPath | ConvertFrom-Json
$audioRecords = @($audioManifest.files)
$audioFiles = @(Get-ChildItem -LiteralPath $audioRoot -Filter "*.mp3" -File)
if ($audioRecords.Count -ne 119 -or $audioFiles.Count -ne 119) {
    throw "隨包音檔必須恰好是 119 個引用檔；manifest=$($audioRecords.Count)，MP3=$($audioFiles.Count)。"
}
$manifestAudioNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($record in $audioRecords) {
    $relativePath = [string]$record.path
    $audioPath = [IO.Path]::GetFullPath((Join-Path $flutterRoot $relativePath))
    if (-not $audioPath.StartsWith($audioRoot.TrimEnd("\") + "\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "音檔 manifest 路徑超出 assets/audio：$relativePath"
    }
    if (-not (Test-Path -LiteralPath $audioPath -PathType Leaf)) {
        throw "音檔 manifest 找不到檔案：$relativePath"
    }
    if (-not $manifestAudioNames.Add([IO.Path]::GetFileName($audioPath))) {
        throw "音檔 manifest 路徑重複：$relativePath"
    }
    $item = Get-Item -LiteralPath $audioPath
    if ($item.Length -ne [long]$record.bytes) {
        throw "音檔 manifest bytes 不一致：$relativePath"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $audioPath).Hash -ne [string]$record.sha256) {
        throw "音檔 manifest SHA-256 不一致：$relativePath"
    }
}
foreach ($audioFile in $audioFiles) {
    if (-not $manifestAudioNames.Contains($audioFile.Name)) {
        throw "發現未列入來源 manifest 的 MP3：$($audioFile.Name)"
    }
}
foreach ($file in Get-ChildItem -LiteralPath $flutterAssetsRoot -File -Recurse) {
    $sourceRelative = Get-RelativePathCompat -BasePath $projectRoot -TargetPath $file.FullName
    $flutterRelative = Get-RelativePathCompat -BasePath $flutterRoot -TargetPath $file.FullName
    $destinationRelative = Join-Path "deliverables\flutter\source" $flutterRelative
    $records.Add((Copy-VerifiedFile -Label "Flutter $($flutterRelative.Replace('\', '/'))" -SourceRelativePath $sourceRelative -DestinationRelativePath $destinationRelative))
}

# 初賽以 Web 為主交付，因此也鏡像 Flutter 的 Web runner；Android 與 iOS
# runner 仍保留在正式版 Flutter 專案，待決賽再做原生權限與封裝驗收。
$flutterWebRunnerRoot = Join-Path $flutterRoot "web"
if (-not (Test-Path -LiteralPath (Join-Path $flutterWebRunnerRoot "index.html") -PathType Leaf)) {
    throw "Flutter 專案缺少 Web runner：$flutterWebRunnerRoot"
}
foreach ($file in Get-ChildItem -LiteralPath $flutterWebRunnerRoot -File -Recurse) {
    $sourceRelative = Get-RelativePathCompat -BasePath $projectRoot -TargetPath $file.FullName
    $flutterRelative = Get-RelativePathCompat -BasePath $flutterRoot -TargetPath $file.FullName
    $destinationRelative = Join-Path "deliverables\flutter\source" $flutterRelative
    $records.Add((Copy-VerifiedFile -Label "Flutter $($flutterRelative.Replace('\', '/'))" -SourceRelativePath $sourceRelative -DestinationRelativePath $destinationRelative))
}

$webSourceRoot = [IO.Path]::GetFullPath((Join-Path $flutterRoot "build\web"))
$webDestinationRoot = Assert-InsideSite (Join-Path $siteRoot "deliverables\app")
if (-not (Test-Path -LiteralPath (Join-Path $webSourceRoot "index.html") -PathType Leaf)) {
    throw "找不到已建置的 Flutter Web 入口：$webSourceRoot"
}
$webIndex = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $webSourceRoot "index.html")
if (-not $webIndex.Contains('<base href="./">')) {
    throw "Flutter Web 尚未改為可部署於子目錄的相對 base href。"
}
if (Test-Path -LiteralPath $webDestinationRoot) {
    # 目標已由 Assert-InsideSite 驗證，只會重建網站內的 Web 作品目錄。
    Remove-Item -Recurse -Force -LiteralPath $webDestinationRoot
}
New-Item -ItemType Directory -Force -Path $webDestinationRoot | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $webSourceRoot -File -Recurse) {
    $sourceRelative = Get-RelativePathCompat -BasePath $projectRoot -TargetPath $file.FullName
    $webRelative = Get-RelativePathCompat -BasePath $webSourceRoot -TargetPath $file.FullName
    $destinationRelative = Join-Path "deliverables\app" $webRelative
    $records.Add((Copy-VerifiedFile -Label "Flutter Web $($webRelative.Replace('\', '/'))" -SourceRelativePath $sourceRelative -DestinationRelativePath $destinationRelative))
}

$manifest = [ordered]@{
    project = "傳家話"
    source_of_truth = "交付成果/README.md"
    synced_at = (Get-Date).ToString("o")
    files = @($records)
}

$manifestPath = Assert-InsideSite (Join-Path $siteRoot "deliverables\manifest.json")
$manifestJson = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($manifestPath, $manifestJson + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

Write-Output "已同步 $($records.Count) 個『傳家話』檔案。"
Write-Output $manifestPath
