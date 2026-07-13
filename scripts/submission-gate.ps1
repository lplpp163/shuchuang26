<#
.SYNOPSIS
驗證「傳家話」送審產物的名稱、流程、音檔與同步狀態。

.DESCRIPTION
預設只做本機、可重現的檢查，不要求尚須對外取得的影片、公開網址、真人母語審閱與人工插圖權利聲明。
使用 -RequireVideo 可驗證 MP4/MOV 的 10 分鐘與 300MB 上限；使用
-RequirePublicUrl 時，須另以 -PublicUrl 或 SUBMISSION_PUBLIC_URL 提供 HTTPS 網址。
使用 -RequireImageRights 時，須另以 -ImageRightsAttestationPath 或
IMAGE_RIGHTS_ATTESTATION_PATH 提供已由有權限者完成、且與三份 manifest 雜湊綁定的聲明。

.EXAMPLE
pwsh -NoProfile -File .\submission-gate.ps1

.EXAMPLE
pwsh -NoProfile -File .\submission-gate.ps1 -RequireVideo -RequirePublicUrl -PublicUrl https://example.invalid/app/

.EXAMPLE
pwsh -NoProfile -File .\submission-gate.ps1 -RequireImageRights -ImageRightsAttestationPath .\image_rights_attestation.json
#>
[CmdletBinding()]
param(
    [switch]$RequireVideo,
    [switch]$RequirePublicUrl,
    [string]$PublicUrl = $env:SUBMISSION_PUBLIC_URL,
    [switch]$RequireNativeReview,
    [string]$NativeReviewPath = $env:NATIVE_REVIEW_PATH,
    [switch]$RequireImageRights,
    [string]$ImageRightsAttestationPath = $env:IMAGE_RIGHTS_ATTESTATION_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$siteRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $siteRoot))
$projectPrefix = $projectRoot.TrimEnd("\") + "\"
$sitePrefix = $siteRoot.TrimEnd("\") + "\"

$failures = [Collections.Generic.List[string]]::new()
$hashCache = @{}

function Add-Pass {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Output "[PASS] $Message"
}

function Add-Skip {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Output "[SKIP] $Message"
}

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
    Write-Output "[FAIL] $Message"
}

function Add-ProblemSummary {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][Collections.IEnumerable]$Problems,
        [int]$MaximumExamples = 8
    )

    $problemList = @($Problems)
    if ($problemList.Count -eq 0) {
        return
    }
    $examples = @($problemList | Select-Object -First $MaximumExamples)
    $suffix = if ($problemList.Count -gt $examples.Count) {
        "；其餘 $($problemList.Count - $examples.Count) 項省略"
    }
    else {
        ""
    }
    Add-Failure "$Label 共 $($problemList.Count) 項：$($examples -join '；')$suffix"
}

function Get-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $fullPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not $fullPath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "路徑超出專案根目錄：$RelativePath"
    }
    return $fullPath
}

function Get-SitePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $fullPath = [IO.Path]::GetFullPath((Join-Path $siteRoot $RelativePath))
    if (-not $fullPath.StartsWith($sitePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "路徑超出團隊進度網站：$RelativePath"
    }
    return $fullPath
}

function Get-CachedSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $hashCache.ContainsKey($fullPath)) {
        $hashCache[$fullPath] = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath).Hash.ToUpperInvariant()
    }
    return [string]$hashCache[$fullPath]
}

function Test-NonPublicIpAddress {
    param([Parameter(Mandatory = $true)][Net.IPAddress]$Address)

    if ($Address.IsIPv4MappedToIPv6) {
        return Test-NonPublicIpAddress -Address $Address.MapToIPv4()
    }
    if ([Net.IPAddress]::IsLoopback($Address)) {
        return $true
    }
    if ($Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
        $bytes = $Address.GetAddressBytes()
        return (
            $bytes[0] -eq 0 -or
            $bytes[0] -eq 10 -or
            $bytes[0] -eq 127 -or
            ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
            ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -eq 2) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
            ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) -or
            ($bytes[0] -eq 198 -and ($bytes[1] -eq 18 -or $bytes[1] -eq 19)) -or
            ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) -or
            ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113) -or
            $bytes[0] -ge 224
        )
    }
    if ($Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
        $bytes = $Address.GetAddressBytes()
        $firstTwelveZero = $true
        for ($index = 0; $index -lt 12; $index++) {
            if ($bytes[$index] -ne 0) {
                $firstTwelveZero = $false
                break
            }
        }
        return (
            $Address.Equals([Net.IPAddress]::IPv6Any) -or
            $firstTwelveZero -or
            ($bytes[0] -band 0xFE) -eq 0xFC -or
            ($bytes[0] -eq 0xFE -and ($bytes[1] -band 0xC0) -eq 0x80) -or
            ($bytes[0] -eq 0xFE -and ($bytes[1] -band 0xC0) -eq 0xC0) -or
            $bytes[0] -eq 0xFF -or
            ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8)
        )
    }
    return $true
}

function Get-DocxText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $parts = @($archive.Entries | Where-Object {
            $_.FullName -match '^word/(document|header\d+|footer\d+|footnotes|endnotes)\.xml$'
        })
        if ($parts.Count -eq 0) {
            throw "DOCX 沒有可讀取的 Word XML 內容。"
        }

        $textParts = [Collections.Generic.List[string]]::new()
        foreach ($entry in $parts) {
            $stream = $entry.Open()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            try {
                $xml = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
                $stream.Dispose()
            }
            $plainText = $xml -replace '<w:tab[^>]*/>', ' ' -replace '</w:p>', "`n" -replace '<[^>]+>', ''
            $textParts.Add([Net.WebUtility]::HtmlDecode($plainText))
        }
        return ($textParts -join "`n")
    }
    finally {
        $archive.Dispose()
    }
}

function Get-PdfTextIfAvailable {
    param([Parameter(Mandatory = $true)][string]$Path)

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($null -eq $pdftotext) {
        return $null
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pdftotext.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in @('-enc', 'UTF-8', '-layout', $Path, '-')) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "無法啟動 pdftotext。"
    }
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "pdftotext 失敗（exit $($process.ExitCode)）：$standardError"
    }
    return $standardOutput
}

$canonicalBrand = "傳家話"
$legacyPatterns = @(
    @{ Label = "舊品牌『我們家怎麼說』"; Pattern = "我們家怎麼說" },
    @{ Label = "舊品牌『家語貼』"; Pattern = "家語貼|HomeTongue\s+Tags" },
    @{ Label = "舊流程『聲音信箱』"; Pattern = "聲音信箱" },
    @{ Label = "舊流程『聲音簿』"; Pattern = "聲音簿" },
    @{ Label = "舊流程『今天這一句』"; Pattern = "今天這一句" },
    @{ Label = "舊固定複習排程"; Pattern = "一[、，]三[、，]七[、，]十四(?:天)?|1\s*[-／/]\s*3\s*[-／/]\s*7\s*[-／/]\s*14(?:\s*天)?|依固定天數" },
    @{ Label = "舊家人回覆選項"; Pattern = "我聽懂了|我們家會這樣說" },
    @{ Label = "舊題型敘事"; Pattern = "四種題型|看圖配對" }
)

function Test-CanonicalText {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $localFailureCount = $failures.Count
    if (-not $Text.Contains($canonicalBrand, [StringComparison]::Ordinal)) {
        Add-Failure "$Label 未使用 canonical 名稱『$canonicalBrand』：$Path"
    }

    foreach ($legacy in $legacyPatterns) {
        $match = [regex]::Match($Text, [string]$legacy.Pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if ($match.Success) {
            $beforeMatch = $Text.Substring(0, $match.Index)
            $lineNumber = 1 + [regex]::Matches($beforeMatch, "\r\n|\n").Count
            Add-Failure "$Label 第 $lineNumber 行含$($legacy.Label)『$($match.Value)』：$Path"
        }
    }

    if ($failures.Count -eq $localFailureCount) {
        Add-Pass "$Label 名稱與流程一致"
    }
}

Write-Output "=== 傳家話｜跨產物 submission gate ==="
Write-Output "專案：$projectRoot"

$canonicalTextFiles = @(
    @{ Label = "計畫書正文"; RelativePath = "交付成果\計畫書\計畫書內容.md" },
    @{ Label = "根目錄 README"; RelativePath = "README.md" },
    @{ Label = "交付成果 README"; RelativePath = "交付成果\README.md" },
    @{ Label = "計畫書 README"; RelativePath = "交付成果\計畫書\README.md" },
    @{ Label = "正式版 README"; RelativePath = "正式版\README.md" },
    @{ Label = "Flutter README"; RelativePath = "正式版\flutter_app\README.md" },
    @{ Label = "嚴格驗收報告"; RelativePath = "交付成果\嚴格驗收報告.md" },
    @{ Label = "技術驗證紀錄"; RelativePath = "交付成果\作品\傳家話_技術驗證紀錄.md" },
    @{ Label = "影片分鏡與旁白"; RelativePath = "交付成果\影片\傳家話_初審影片分鏡與旁白.md" },
    @{ Label = "家庭需求與試演問卷"; RelativePath = "交付成果\問卷\傳家話_新住民家庭需求與試演問卷.md" },
    @{ Label = "越南語母語審閱工具"; RelativePath = "交付成果\語言審閱\傳家話_越南語119句母語審閱工具.html" },
    @{ Label = "越南語母語審閱說明"; RelativePath = "交付成果\語言審閱\README.md" },
    @{ Label = "成果網站"; RelativePath = "團隊進度網站\index.html" },
    @{ Label = "成果網站 README"; RelativePath = "團隊進度網站\README.md" },
    @{ Label = "成果網站舊入口"; RelativePath = "團隊進度網站\開會簡報.html" },
    @{ Label = "Flutter 鏡像入口"; RelativePath = "團隊進度網站\deliverables\flutter\index.html" },
    @{ Label = "Flutter 鏡像 README"; RelativePath = "團隊進度網站\deliverables\flutter\README.md" },
    @{ Label = "計畫書鏡像 README"; RelativePath = "團隊進度網站\deliverables\plan\README.md" },
    @{ Label = "影片分鏡網頁"; RelativePath = "團隊進度網站\deliverables\video\index.html" },
    @{ Label = "影片旁白鏡像"; RelativePath = "團隊進度網站\deliverables\video\narration.md" },
    @{ Label = "影片內容設定鏡像"; RelativePath = "團隊進度網站\deliverables\video\video_content.json" },
    @{ Label = "影片重建腳本鏡像"; RelativePath = "團隊進度網站\deliverables\video\build_submission_video.ps1" },
    @{ Label = "影片製作說明鏡像"; RelativePath = "團隊進度網站\deliverables\video\production-notes.md" },
    @{ Label = "影片驗證紀錄鏡像"; RelativePath = "團隊進度網站\deliverables\video\verification.json" },
    @{ Label = "嚴格驗收鏡像"; RelativePath = "團隊進度網站\deliverables\docs\strict-review.md" },
    @{ Label = "技術驗證鏡像"; RelativePath = "團隊進度網站\deliverables\docs\technical-validation.md" },
    @{ Label = "需求問卷鏡像"; RelativePath = "團隊進度網站\deliverables\docs\family-pilot-questionnaire.md" },
    @{ Label = "越南語母語審閱工具鏡像"; RelativePath = "團隊進度網站\deliverables\review\index.html" },
    @{ Label = "越南語母語審閱說明鏡像"; RelativePath = "團隊進度網站\deliverables\review\README.md" }
)

Write-Output "`n--- canonical 名稱與流程 ---"
foreach ($artifact in $canonicalTextFiles) {
    $artifactPath = Get-ProjectPath $artifact.RelativePath
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        Add-Failure "$($artifact.Label) 不存在：$($artifact.RelativePath)"
        continue
    }
    $artifactText = Get-Content -Raw -Encoding UTF8 -LiteralPath $artifactPath
    Test-CanonicalText -Label $artifact.Label -Path $artifact.RelativePath -Text $artifactText
}

$canonicalPlanBaseName = "2026臺灣數創大賞_數位組創業計畫書_傳家話_正式版"
$canonicalPlanDocx = Get-ProjectPath "交付成果\計畫書\$canonicalPlanBaseName.docx"
$canonicalPlanPdf = Get-ProjectPath "交付成果\計畫書\$canonicalPlanBaseName.pdf"

if (-not (Test-Path -LiteralPath $canonicalPlanDocx -PathType Leaf)) {
    Add-Failure "缺少 canonical 計畫書 DOCX：$canonicalPlanDocx"
}
else {
    try {
        $docxText = Get-DocxText -Path $canonicalPlanDocx
        Test-CanonicalText -Label "正式計畫書 DOCX" -Path ([IO.Path]::GetRelativePath($projectRoot, $canonicalPlanDocx)) -Text $docxText
    }
    catch {
        Add-Failure "正式計畫書 DOCX 無法檢查：$($_.Exception.Message)"
    }
}

if (-not (Test-Path -LiteralPath $canonicalPlanPdf -PathType Leaf)) {
    Add-Failure "缺少 canonical 計畫書 PDF：$canonicalPlanPdf"
}
else {
    $pdfItem = Get-Item -LiteralPath $canonicalPlanPdf
    if ($pdfItem.Length -le 0 -or $pdfItem.Length -gt 25MB) {
        Add-Failure "正式計畫書 PDF 大小不合法（必須 > 0 且 <= 25MB）：$($pdfItem.Length) bytes"
    }
    else {
        Add-Pass "正式計畫書 PDF 存在且小於 25MB"
    }
    try {
        $pdfText = Get-PdfTextIfAvailable -Path $canonicalPlanPdf
        if ($null -eq $pdfText) {
            Add-Skip "系統沒有 pdftotext；PDF 文字由 DOCX 與 Markdown 交叉檢查取代"
        }
        else {
            Test-CanonicalText -Label "正式計畫書 PDF" -Path ([IO.Path]::GetRelativePath($projectRoot, $canonicalPlanPdf)) -Text $pdfText
        }
    }
    catch {
        Add-Failure "正式計畫書 PDF 無法檢查文字：$($_.Exception.Message)"
    }
}

$legacyPlanFiles = @(Get-ChildItem -LiteralPath (Get-ProjectPath "交付成果\計畫書") -File | Where-Object {
    $_.Name -match '我們家怎麼說.*正式版\.(docx|pdf)$'
})
if ($legacyPlanFiles.Count -gt 0) {
    Add-Failure "計畫書根目錄仍有容易誤傳的舊正式檔：$($legacyPlanFiles.Name -join '、')"
}
else {
    Add-Pass "計畫書根目錄沒有舊品牌正式檔"
}

$legacyNamedSourceArtifacts = @(Get-ChildItem -LiteralPath (Get-ProjectPath "交付成果") -File -Recurse | Where-Object {
    $_.FullName -notmatch '[\\/]舊版[\\/]' -and
    $_.Name.Contains('我們家怎麼說', [StringComparison]::Ordinal)
})
if ($legacyNamedSourceArtifacts.Count -gt 0) {
    $legacyRelativeNames = @($legacyNamedSourceArtifacts | ForEach-Object {
        [IO.Path]::GetRelativePath($projectRoot, $_.FullName)
    })
    Add-Failure "交付成果仍有舊品牌檔名：$($legacyRelativeNames -join '、')"
}
else {
    Add-Pass "交付成果檔名只使用『傳家話』主品牌"
}

Write-Output "`n--- 隨包音檔 manifest ---"
$flutterRoot = Get-ProjectPath "正式版\flutter_app"
$audioRoot = [IO.Path]::GetFullPath((Join-Path $flutterRoot "assets\audio"))
$audioPrefix = $audioRoot.TrimEnd("\") + "\"
$audioManifestPath = Join-Path $audioRoot "piper_generation_manifest.json"

if (-not (Test-Path -LiteralPath $audioManifestPath -PathType Leaf)) {
    Add-Failure "缺少音檔 manifest：$audioManifestPath"
}
else {
    try {
        $audioManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $audioManifestPath | ConvertFrom-Json
        $audioRecords = @($audioManifest.files)
        $audioFiles = @(Get-ChildItem -LiteralPath $audioRoot -Filter "*.mp3" -File)
        $audioProblems = [Collections.Generic.List[string]]::new()
        $audioMirrorRoots = @(
            [IO.Path]::GetFullPath((Join-Path $flutterRoot "build\web\assets\assets\audio")),
            (Get-SitePath "deliverables\app\assets\assets\audio")
        )
        if ($audioRecords.Count -ne 119) {
            $audioProblems.Add("manifest 應為 119 筆，實際 $($audioRecords.Count) 筆")
        }
        if ($audioFiles.Count -ne 119) {
            $audioProblems.Add("assets/audio 應為 119 個 MP3，實際 $($audioFiles.Count) 個")
        }

        $manifestAudioPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($record in $audioRecords) {
            $relativePath = [string]$record.path
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                $audioProblems.Add("manifest 含空白 path")
                continue
            }

            $audioPath = [IO.Path]::GetFullPath((Join-Path $flutterRoot ($relativePath -replace '/', '\')))
            if (-not $audioPath.StartsWith($audioPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                $audioProblems.Add("路徑超出 assets/audio：$relativePath")
                continue
            }
            if (-not $manifestAudioPaths.Add($audioPath)) {
                $audioProblems.Add("路徑重複：$relativePath")
                continue
            }
            if (-not (Test-Path -LiteralPath $audioPath -PathType Leaf)) {
                $audioProblems.Add("找不到實體檔：$relativePath")
                continue
            }

            $audioItem = Get-Item -LiteralPath $audioPath
            if ($audioItem.Length -ne [long]$record.bytes) {
                $audioProblems.Add("bytes 不一致：$relativePath")
            }
            $declaredHash = ([string]$record.sha256).ToUpperInvariant()
            if ($declaredHash -notmatch '^[A-F0-9]{64}$') {
                $audioProblems.Add("SHA-256 欄位格式錯誤：$relativePath")
            }
            elseif ((Get-CachedSha256 -Path $audioPath) -ne $declaredHash) {
                $audioProblems.Add("SHA-256 不一致：$relativePath")
            }
            foreach ($mirrorRoot in $audioMirrorRoots) {
                $mirrorPath = Join-Path $mirrorRoot ([IO.Path]::GetFileName($audioPath))
                if (-not (Test-Path -LiteralPath $mirrorPath -PathType Leaf)) {
                    $audioProblems.Add("Web mirror 缺檔：$mirrorPath")
                    continue
                }
                $mirrorItem = Get-Item -LiteralPath $mirrorPath
                if ($mirrorItem.Length -ne [long]$record.bytes -or
                    (Get-CachedSha256 -Path $mirrorPath) -ne $declaredHash) {
                    $audioProblems.Add("Web mirror bytes／SHA-256 不一致：$mirrorPath")
                }
            }
        }

        foreach ($audioFile in $audioFiles) {
            if (-not $manifestAudioPaths.Contains($audioFile.FullName)) {
                $audioProblems.Add("未列入 manifest：$($audioFile.Name)")
            }
        }
        foreach ($mirrorRoot in $audioMirrorRoots) {
            $mirrorManifestPath = Join-Path $mirrorRoot "piper_generation_manifest.json"
            if (-not (Test-Path -LiteralPath $mirrorManifestPath -PathType Leaf) -or
                (Get-CachedSha256 -Path $mirrorManifestPath) -ne (Get-CachedSha256 -Path $audioManifestPath)) {
                $audioProblems.Add("Web mirror 的音檔 manifest 不一致：$mirrorManifestPath")
            }
        }

        if ($audioProblems.Count -gt 0) {
            Add-ProblemSummary -Label "音檔 manifest／實體檔不一致" -Problems $audioProblems
        }
        else {
            Add-Pass "119 筆來源音檔與 build/web、deliverables/app mirrors 的 bytes／SHA-256 完全一致"
        }
    }
    catch {
        Add-Failure "音檔 manifest 無法解析：$($_.Exception.Message)"
    }
}

Write-Output "`n--- 母語逐檔審閱工具 ---"
$nativeReviewToolPath = Get-ProjectPath "交付成果\語言審閱\傳家話_越南語119句母語審閱工具.html"
$nativeReviewContextPath = Get-ProjectPath "交付成果\語言審閱\傳家話_越南語119句語境目錄.json"
$nativeReviewZipPath = Get-ProjectPath "交付成果\語言審閱\傳家話_越南語119句母語審閱可攜包.zip"
if (-not (Test-Path -LiteralPath $nativeReviewToolPath -PathType Leaf)) {
    Add-Failure "缺少 119 句母語審閱工具：$nativeReviewToolPath"
}
elseif (-not (Test-Path -LiteralPath $nativeReviewContextPath -PathType Leaf)) {
    Add-Failure "缺少母語審閱語境目錄：$nativeReviewContextPath"
}
elseif (-not (Test-Path -LiteralPath $nativeReviewZipPath -PathType Leaf)) {
    Add-Failure "缺少可攜式母語審閱 ZIP：$nativeReviewZipPath"
}
elseif (-not (Test-Path -LiteralPath $audioManifestPath -PathType Leaf)) {
    Add-Failure "無法用缺少的音檔 manifest 驗證母語審閱工具"
}
else {
    try {
        $reviewToolText = Get-Content -Raw -Encoding UTF8 -LiteralPath $nativeReviewToolPath
        $reviewToolProblems = [Collections.Generic.List[string]]::new()
        $reviewContextCatalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $nativeReviewContextPath | ConvertFrom-Json
        $reviewToolRecords = @([regex]::Matches(
            $reviewToolText,
            '"path":"(?<path>assets/audio/[^"/]+\.mp3)","text":"(?:\\.|[^"\\])*","bytes":\d+,"sha256":"[A-Fa-f0-9]{64}"',
            [Text.RegularExpressions.RegexOptions]::CultureInvariant
        ))
        $reviewToolPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($match in $reviewToolRecords) {
            if (-not $reviewToolPaths.Add($match.Groups['path'].Value)) {
                $reviewToolProblems.Add("審閱工具重複嵌入音檔：$($match.Groups['path'].Value)")
            }
        }
        $reviewManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $audioManifestPath | ConvertFrom-Json
        $reviewManifestRecords = @($reviewManifest.files)
        if ($reviewToolPaths.Count -ne 119) {
            $reviewToolProblems.Add("審閱工具應嵌入 119 個唯一音檔，實際 $($reviewToolPaths.Count) 個")
        }
        foreach ($record in $reviewManifestRecords) {
            if (-not $reviewToolPaths.Contains([string]$record.path)) {
                $reviewToolProblems.Add("審閱工具缺少 manifest 音檔：$($record.path)")
            }
        }
        $reviewManifestHash = Get-CachedSha256 -Path $audioManifestPath
        if (-not $reviewToolText.Contains($reviewManifestHash, [StringComparison]::OrdinalIgnoreCase)) {
            $reviewToolProblems.Add("審閱工具未綁定目前音檔 manifest SHA-256")
        }
        if ([string]$reviewContextCatalog.schema -ne 'our-family-says/native-review-context/v1' -or
            [string]$reviewContextCatalog.manifestSha256 -ne $reviewManifestHash -or
            [int]$reviewContextCatalog.audioPathCount -ne 119 -or
            [int]$reviewContextCatalog.usageCount -ne 204 -or
            [int]$reviewContextCatalog.unknownRelationshipPathCount -ne 28 -or
            @($reviewContextCatalog.records).Count -ne 119 -or
            [string]$reviewContextCatalog.contextCatalogSha256 -notmatch '^[A-F0-9]{64}$') {
            $reviewToolProblems.Add("語境目錄 schema／manifest／119 路徑／204 usages／未知關係統計不正確")
        }
        if (-not $reviewToolText.Contains([string]$reviewContextCatalog.contextCatalogSha256, [StringComparison]::OrdinalIgnoreCase) -or
            -not $reviewToolText.Contains('our-family-says/native-review/v2', [StringComparison]::Ordinal)) {
            $reviewToolProblems.Add("審閱工具未綁定目前語境目錄或 v2 evidence schema")
        }
        $contextByPath = @{}
        $contextUsageCount = 0
        foreach ($contextRecord in @($reviewContextCatalog.records)) {
            $contextPath = [string]$contextRecord.path
            if ($contextByPath.ContainsKey($contextPath)) {
                $reviewToolProblems.Add("語境目錄路徑重複：$contextPath")
                continue
            }
            $contextByPath[$contextPath] = $contextRecord
            $contexts = @($contextRecord.contexts)
            $contextUsageCount += $contexts.Count
            if ($contexts.Count -eq 0 -or @($contextRecord.intendedMeaningsZh).Count -eq 0 -or
                [string]::IsNullOrWhiteSpace([string]$contextRecord.registerReviewScope)) {
                $reviewToolProblems.Add("語境目錄缺少中文意圖、usage 或審閱範圍：$contextPath")
            }
            foreach ($context in $contexts) {
                if ([string]$context.path -ne $contextPath -or
                    [string]::IsNullOrWhiteSpace([string]$context.translationZh) -or
                    [string]::IsNullOrWhiteSpace([string]$context.usageType) -or
                    [string]::IsNullOrWhiteSpace([string]$context.usageContextZh) -or
                    [string]::IsNullOrWhiteSpace([string]$context.sourceReference)) {
                    $reviewToolProblems.Add("語境 usage 缺必要欄位：$contextPath")
                }
                if ($context.relationshipKnown -eq $true -and
                    ([string]::IsNullOrWhiteSpace([string]$context.semanticSpeakerZh) -or
                     [string]::IsNullOrWhiteSpace([string]$context.semanticListenerZh) -or
                     [string]::IsNullOrWhiteSpace([string]$context.kinshipZh))) {
                    $reviewToolProblems.Add("已知親屬語境缺 speaker／listener／kinship：$contextPath")
                }
            }
        }
        if ($contextUsageCount -ne 204) {
            $reviewToolProblems.Add("語境目錄實際 usages 應為 204，實際 $contextUsageCount")
        }
        foreach ($record in $reviewManifestRecords) {
            $path = [string]$record.path
            if (-not $contextByPath.ContainsKey($path) -or
                [string]$contextByPath[$path].text -ne [string]$record.text) {
                $reviewToolProblems.Add("語境目錄缺少或文字漂移：$path")
            }
        }
        foreach ($sourceEntry in @(
            @{ Relative = 'lib/models/conversation_episode.dart'; Path = (Join-Path $flutterRoot 'lib\models\conversation_episode.dart') },
            @{ Relative = 'lib/services/app_store.dart'; Path = (Join-Path $flutterRoot 'lib\services\app_store.dart') }
        )) {
            $declaredSourceHash = [string]$reviewContextCatalog.sourceSha256.($sourceEntry.Relative)
            if ($declaredSourceHash -ne (Get-CachedSha256 -Path $sourceEntry.Path)) {
                $reviewToolProblems.Add("語境目錄來源 SHA-256 漂移：$($sourceEntry.Relative)")
            }
        }
        if (-not $reviewToolText.Contains("這是一份空白真人審閱工具，不是審閱成果", [StringComparison]::Ordinal)) {
            $reviewToolProblems.Add("審閱工具缺少不可冒充真人成果的證據邊界")
        }
        if (-not $reviewToolText.Contains("尚未完整播放；聽完才可判定", [StringComparison]::Ordinal) -or
            -not $reviewToolText.Contains("三項都必須明確選", [StringComparison]::Ordinal)) {
            $reviewToolProblems.Add("審閱工具未強制完整播放與三項明確 yes/no")
        }

        $zip = [IO.Compression.ZipFile]::OpenRead($nativeReviewZipPath)
        try {
            $zipEntries = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
            $zipByName = @{}
            $zipHashes = @{}
            foreach ($entry in $zipEntries) {
                $entryName = $entry.FullName.Replace('\', '/')
                if ($entryName.StartsWith('/') -or $entryName.Contains('../') -or $entry.FullName.Contains('\')) {
                    $reviewToolProblems.Add("可攜 ZIP 含不安全路徑：$($entry.FullName)")
                    continue
                }
                if ($zipByName.ContainsKey($entryName)) {
                    $reviewToolProblems.Add("可攜 ZIP 路徑重複：$entryName")
                    continue
                }
                $zipByName[$entryName] = $entry
                $stream = $entry.Open()
                try {
                    $hasher = [Security.Cryptography.SHA256]::Create()
                    try {
                        $zipHashes[$entryName] = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '')
                    }
                    finally {
                        $hasher.Dispose()
                    }
                }
                finally {
                    $stream.Dispose()
                }
            }
            $expectedZipNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($name in @(
                'index.html',
                'README.txt',
                'assets/audio/piper_generation_manifest.json',
                'context/native_review_context_catalog.json',
                'SHA256SUMS.txt'
            )) { $expectedZipNames.Add($name) | Out-Null }
            foreach ($record in $reviewManifestRecords) { $expectedZipNames.Add([string]$record.path) | Out-Null }
            foreach ($name in $expectedZipNames) {
                if (-not $zipByName.ContainsKey($name)) { $reviewToolProblems.Add("可攜 ZIP 缺檔：$name") }
            }
            foreach ($name in $zipByName.Keys) {
                if (-not $expectedZipNames.Contains($name)) { $reviewToolProblems.Add("可攜 ZIP 多檔：$name") }
            }
            if ($zipByName.Count -ne 124) {
                $reviewToolProblems.Add("可攜 ZIP 應恰有 124 個檔案，實際 $($zipByName.Count)")
            }
            if ($zipHashes['assets/audio/piper_generation_manifest.json'] -ne $reviewManifestHash -or
                $zipHashes['context/native_review_context_catalog.json'] -ne (Get-CachedSha256 -Path $nativeReviewContextPath)) {
                $reviewToolProblems.Add("可攜 ZIP 的 manifest 或語境目錄不是目前交付版本")
            }
            foreach ($record in $reviewManifestRecords) {
                $path = [string]$record.path
                if (-not $zipByName.ContainsKey($path)) { continue }
                if ([long]$zipByName[$path].Length -ne [long]$record.bytes -or
                    $zipHashes[$path] -ne ([string]$record.sha256).ToUpperInvariant()) {
                    $reviewToolProblems.Add("可攜 ZIP 音檔 bytes／SHA-256 不一致：$path")
                }
            }
            if ($zipByName.ContainsKey('index.html')) {
                $reader = [IO.StreamReader]::new($zipByName['index.html'].Open(), [Text.Encoding]::UTF8, $true)
                try { $zipHtml = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if (-not $zipHtml.Contains($reviewManifestHash, [StringComparison]::OrdinalIgnoreCase) -or
                    -not $zipHtml.Contains([string]$reviewContextCatalog.contextCatalogSha256, [StringComparison]::OrdinalIgnoreCase) -or
                    $zipHtml -notmatch 'const\s+audioPrefix\s*=\s*["'']\./["''];') {
                    $reviewToolProblems.Add("可攜 ZIP 的 HTML 未綁定目前 manifest／語境或離線 audio prefix")
                }
            }
            if ($zipByName.ContainsKey('SHA256SUMS.txt')) {
                $reader = [IO.StreamReader]::new($zipByName['SHA256SUMS.txt'].Open(), [Text.Encoding]::UTF8, $true)
                try { $sumText = $reader.ReadToEnd() } finally { $reader.Dispose() }
                $sumRecords = @([regex]::Matches($sumText, '(?m)^(?<hash>[A-Fa-f0-9]{64})  (?<path>[^\r\n]+)$'))
                if ($sumRecords.Count -ne 123) {
                    $reviewToolProblems.Add("可攜 ZIP SHA256SUMS 應列 123 筆，實際 $($sumRecords.Count)")
                }
                foreach ($sumRecord in $sumRecords) {
                    $path = $sumRecord.Groups['path'].Value
                    if (-not $zipHashes.ContainsKey($path) -or
                        $zipHashes[$path] -ne $sumRecord.Groups['hash'].Value.ToUpperInvariant()) {
                        $reviewToolProblems.Add("可攜 ZIP SHA256SUMS 不一致：$path")
                    }
                }
            }
        }
        finally {
            $zip.Dispose()
        }
        if ($reviewToolProblems.Count -gt 0) {
            Add-ProblemSummary -Label "母語審閱工具與 119 檔 manifest 不一致" -Problems $reviewToolProblems
        }
        else {
            Add-Pass "母語審閱工具綁定119音檔／204語境／來源hash，強制完整播放與yes/no，且124檔可攜ZIP逐檔SHA-256一致"
        }
    }
    catch {
        Add-Failure "母語審閱工具無法驗證：$($_.Exception.Message)"
    }
}

Write-Output "`n--- 場景插圖成品完整性 ---"
$imageRoot = Join-Path $flutterRoot "assets\images"
$imageInventoryPath = Join-Path $imageRoot "README.md"
if (-not (Test-Path -LiteralPath $imageInventoryPath -PathType Leaf)) {
    Add-Failure "缺少場景插圖成品完整性清單：$imageInventoryPath"
}
else {
    $imageProblems = [Collections.Generic.List[string]]::new()
    $imageFiles = @(Get-ChildItem -LiteralPath $imageRoot -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @('.png', '.webp', '.jpg', '.jpeg')
    })
    $imageInventoryText = Get-Content -Raw -Encoding UTF8 -LiteralPath $imageInventoryPath
    $imageRecords = @([regex]::Matches(
        $imageInventoryText,
        '\|\s*`(?<name>[^`]+\.(?:png|webp|jpe?g))`\s*\|\s*(?<bytes>\d+)\s*\|\s*`(?<sha>[A-Fa-f0-9]{64})`\s*\|',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
    ))
    if ($imageFiles.Count -ne 11 -or $imageRecords.Count -ne 11) {
        $imageProblems.Add("場景圖與完整性清單應各為 11 筆，實體=$($imageFiles.Count)，紀錄=$($imageRecords.Count)")
    }
    $recordedImageNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $imageRecords) {
        $name = $record.Groups['name'].Value
        if (-not $recordedImageNames.Add($name)) {
            $imageProblems.Add("完整性清單檔名重複：$name")
            continue
        }
        $imagePath = Join-Path $imageRoot $name
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
            $imageProblems.Add("完整性清單找不到場景圖：$name")
            continue
        }
        $imageItem = Get-Item -LiteralPath $imagePath
        if ($imageItem.Length -ne [long]$record.Groups['bytes'].Value) {
            $imageProblems.Add("場景圖 bytes 不一致：$name")
        }
        if ((Get-CachedSha256 -Path $imagePath) -ne $record.Groups['sha'].Value.ToUpperInvariant()) {
            $imageProblems.Add("場景圖 SHA-256 不一致：$name")
        }
    }
    foreach ($imageFile in $imageFiles) {
        if (-not $recordedImageNames.Contains($imageFile.Name)) {
            $imageProblems.Add("場景圖未列入完整性清單：$($imageFile.Name)")
        }
    }
    if ($imageProblems.Count -gt 0) {
        Add-ProblemSummary -Label "場景插圖完整性清單／實體檔不一致" -Problems $imageProblems
    }
    else {
        Add-Pass "11 張場景插圖的 bytes／SHA-256 與成品完整性清單一致；此關不代表來源或使用授權"
    }
}

Write-Output "`n--- 場景插圖技術來源 ---"
$imageEvidenceRoot = Get-ProjectPath "競賽資料\權利證據\生成式插圖"
$imageEvidenceVerifier = Join-Path $imageEvidenceRoot "verify-provenance.ps1"
$publicImageManifestPath = Join-Path $imageRoot "provenance_manifest.json"
$imageGenerationManifestPath = Join-Path $imageEvidenceRoot "generation_manifest.json"
$imageTransformManifestPath = Join-Path $imageEvidenceRoot "transform_manifest.json"
if (-not (Test-Path -LiteralPath $imageEvidenceVerifier -PathType Leaf)) {
    Add-Failure "缺少場景插圖技術來源驗證腳本：$imageEvidenceVerifier"
}
else {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwshCommand) {
        Add-Failure "找不到 pwsh，無法隔離執行插圖技術來源驗證"
    }
    else {
        $imageEvidenceOutput = @(& $pwshCommand.Source -NoProfile -File $imageEvidenceVerifier 2>&1)
        $imageEvidenceExitCode = $LASTEXITCODE
        if ($imageEvidenceExitCode -ne 0) {
            $detail = ($imageEvidenceOutput | Select-Object -First 8) -join "；"
            Add-Failure "場景插圖技術來源驗證失敗：$detail"
        }
        else {
            Add-Pass "10 次生成的原始 PNG／prompt／record／時間／引用鏈，以及 11 筆成品轉換均通過 hash 綁定"
            Write-Output "[INFO] C2PA 僅確認嵌入 claim markers；此關未宣稱密碼學簽章或使用權已驗證"
        }
    }
}

Write-Output "`n--- 場景插圖人工權利聲明 ---"
if ([string]::IsNullOrWhiteSpace($ImageRightsAttestationPath)) {
    $resolvedImageRightsAttestationPath = Join-Path $imageEvidenceRoot "image_rights_attestation.json"
}
elseif ([IO.Path]::IsPathRooted($ImageRightsAttestationPath)) {
    $resolvedImageRightsAttestationPath = [IO.Path]::GetFullPath($ImageRightsAttestationPath)
}
else {
    $resolvedImageRightsAttestationPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $ImageRightsAttestationPath))
}

if (-not $RequireImageRights) {
    Add-Skip "未啟用 -RequireImageRights；不把技術來源、雜湊或 C2PA markers 誤當人工使用授權"
}
elseif (-not (Test-Path -LiteralPath $resolvedImageRightsAttestationPath -PathType Leaf)) {
    Add-Failure "正式權利模式缺少人工 attestation 實檔：$resolvedImageRightsAttestationPath"
}
else {
    $rightsProblems = [Collections.Generic.List[string]]::new()
    try {
        $attestation = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedImageRightsAttestationPath | ConvertFrom-Json
        if ([string]$attestation.schema -ne 'hometongue.image-rights-attestation.v1') {
            $rightsProblems.Add('attestation schema 不符')
        }
        if ([string]$attestation.project -ne $canonicalBrand) {
            $rightsProblems.Add("attestation project 不是『$canonicalBrand』")
        }
        if ([string]::IsNullOrWhiteSpace([string]$attestation.attestationId)) {
            $rightsProblems.Add('attestationId 不得空白')
        }
        if ([string]::IsNullOrWhiteSpace([string]$attestation.attester.fullName) -or
            [string]::IsNullOrWhiteSpace([string]$attestation.attester.role)) {
            $rightsProblems.Add('attester fullName／role 不得空白')
        }

        $signedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse(
                [string]$attestation.attester.signedAtUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal,
                [ref]$signedAt
            )) {
            $rightsProblems.Add('attester signedAtUtc 不是有效時間')
        }
        elseif ($signedAt -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
            $rightsProblems.Add('attester signedAtUtc 不得是未來時間')
        }

        foreach ($requiredManifest in @($publicImageManifestPath, $imageGenerationManifestPath, $imageTransformManifestPath)) {
            if (-not (Test-Path -LiteralPath $requiredManifest -PathType Leaf)) {
                $rightsProblems.Add("attestation 要綁定的 manifest 不存在：$requiredManifest")
            }
        }
        if ($rightsProblems.Count -eq 0) {
            $expectedBindings = @{
                publicProvenanceManifestSha256 = Get-CachedSha256 -Path $publicImageManifestPath
                generationManifestSha256 = Get-CachedSha256 -Path $imageGenerationManifestPath
                transformManifestSha256 = Get-CachedSha256 -Path $imageTransformManifestPath
            }
            foreach ($bindingName in $expectedBindings.Keys) {
                $property = $attestation.evidenceBindings.PSObject.Properties[$bindingName]
                if ($null -eq $property -or ([string]$property.Value).ToUpperInvariant() -ne $expectedBindings[$bindingName]) {
                    $rightsProblems.Add("attestation manifest hash 不一致：$bindingName")
                }
            }
        }

        $requiredConfirmations = @(
            'accountAuthority',
            'allInputRights',
            'noUndisclosedThirdPartyInputs',
            'competitionSubmissionAuthorized',
            'commercialPrototypeUseAuthorized',
            'aiGenerationDisclosureAccurate',
            'organizerRulesReviewed'
        )
        foreach ($confirmationName in $requiredConfirmations) {
            $property = $attestation.confirmations.PSObject.Properties[$confirmationName]
            if ($null -eq $property -or $property.Value -ne $true) {
                $rightsProblems.Add("人工確認尚未為 true：$confirmationName")
            }
        }

        $requiredAffirmation = '本人確認上述資料為真，並授權「傳家話」團隊於本競賽送件、展示及商業原型中使用本證據包所列插圖。'
        if ([string]$attestation.requiredAffirmationText -ne $requiredAffirmation -or $attestation.affirmationAccepted -ne $true) {
            $rightsProblems.Add('人工授權聲明文字不符或尚未接受')
        }
        if ([string]::IsNullOrWhiteSpace([string]$attestation.termsBasis.serviceType) -or
            [string]::IsNullOrWhiteSpace([string]$attestation.termsBasis.termsEffectiveDate)) {
            $rightsProblems.Add('termsBasis serviceType／termsEffectiveDate 不得空白')
        }
        $termsEffectiveDate = [DateTime]::MinValue
        if (-not [DateTime]::TryParseExact(
                [string]$attestation.termsBasis.termsEffectiveDate,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$termsEffectiveDate
            )) {
            $rightsProblems.Add('termsBasis termsEffectiveDate 必須是 yyyy-MM-dd')
        }
        $termsUri = $null
        if (-not [Uri]::TryCreate([string]$attestation.termsBasis.termsUrl, [UriKind]::Absolute, [ref]$termsUri) -or $termsUri.Scheme -ne 'https') {
            $rightsProblems.Add('termsBasis termsUrl 必須是有效 HTTPS URL')
        }
        $reviewedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse(
                [string]$attestation.termsBasis.reviewedAtUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal,
                [ref]$reviewedAt
            )) {
            $rightsProblems.Add('termsBasis reviewedAtUtc 不是有效時間')
        }
        elseif ($reviewedAt -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
            $rightsProblems.Add('termsBasis reviewedAtUtc 不得是未來時間')
        }
    }
    catch {
        $rightsProblems.Add("attestation 無法解析或欄位不完整：$($_.Exception.Message)")
    }

    if ($rightsProblems.Count -gt 0) {
        Add-ProblemSummary -Label "場景插圖人工權利聲明未完成" -Problems $rightsProblems
    }
    else {
        Add-Pass "人工 attestation 已確認帳號／輸入權利、競賽與商業原型使用、AI 揭露及主辦規章，且三份 manifest hash 一致"
    }
}

Write-Output "`n--- deliverables manifest 與 Web build ---"
$deliverablesManifestPath = Get-SitePath "deliverables\manifest.json"
$webSourceRoot = [IO.Path]::GetFullPath((Join-Path $flutterRoot "build\web"))
$webDestinationRoot = Get-SitePath "deliverables\app"

if (-not (Test-Path -LiteralPath $deliverablesManifestPath -PathType Leaf)) {
    Add-Failure "缺少 deliverables manifest：$deliverablesManifestPath"
}
else {
    try {
        $deliverablesManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $deliverablesManifestPath | ConvertFrom-Json
        if ([string]$deliverablesManifest.project -ne $canonicalBrand) {
            Add-Failure "deliverables manifest project 不是『$canonicalBrand』"
        }
        if ([string]$deliverablesManifest.source_of_truth -ne "交付成果/README.md") {
            Add-Failure "deliverables manifest source_of_truth 應為交付成果/README.md"
        }

        $manifestRecords = @($deliverablesManifest.files)
        $manifestDestinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $manifestAppPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $manifestProblems = [Collections.Generic.List[string]]::new()
        foreach ($claimRelativePath in @(
            "README.md",
            "交付成果\嚴格驗收報告.md",
            "團隊進度網站\deliverables\docs\strict-review.md"
        )) {
            $claimPath = Get-ProjectPath $claimRelativePath
            if (-not (Test-Path -LiteralPath $claimPath -PathType Leaf)) {
                continue
            }
            $claimText = Get-Content -Raw -Encoding UTF8 -LiteralPath $claimPath
            foreach ($claimMatch in [regex]::Matches($claimText, '(?<count>\d+)\s*筆跨產物')) {
                if ([int]$claimMatch.Groups['count'].Value -ne $manifestRecords.Count) {
                    $manifestProblems.Add("manifest 數字宣稱漂移：$claimRelativePath 寫 $($claimMatch.Groups['count'].Value)，實際 $($manifestRecords.Count)")
                }
            }
        }
        foreach ($record in $manifestRecords) {
            $sourceRelative = ([string]$record.source -replace '/', '\')
            $destinationRelative = ([string]$record.destination -replace '/', '\')
            if ([string]::IsNullOrWhiteSpace($sourceRelative) -or [string]::IsNullOrWhiteSpace($destinationRelative)) {
                $manifestProblems.Add("含空白 source 或 destination")
                continue
            }

            $sourcePath = Get-ProjectPath $sourceRelative
            $destinationPath = Get-SitePath $destinationRelative
            if (-not $manifestDestinations.Add($destinationPath)) {
                $manifestProblems.Add("destination 重複：$destinationRelative")
            }
            if ($destinationPath.StartsWith($webDestinationRoot.TrimEnd("\") + "\", [StringComparison]::OrdinalIgnoreCase)) {
                $manifestAppPaths.Add($destinationPath) | Out-Null
            }

            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $manifestProblems.Add("source 不存在：$sourceRelative")
                continue
            }
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                $manifestProblems.Add("destination 不存在：$destinationRelative")
                continue
            }

            $sourceItem = Get-Item -LiteralPath $sourcePath
            $destinationItem = Get-Item -LiteralPath $destinationPath
            if ($sourceItem.Length -ne [long]$record.bytes -or $destinationItem.Length -ne [long]$record.bytes) {
                $manifestProblems.Add("bytes 不一致：$destinationRelative")
                continue
            }
            $declaredHash = ([string]$record.sha256).ToUpperInvariant()
            $sourceHash = Get-CachedSha256 -Path $sourcePath
            $destinationHash = Get-CachedSha256 -Path $destinationPath
            if ($declaredHash -notmatch '^[A-F0-9]{64}$' -or $sourceHash -ne $declaredHash -or $destinationHash -ne $declaredHash) {
                $manifestProblems.Add("SHA-256 不一致：$destinationRelative")
            }
        }

        $managedAllowlist = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($relativePath in @(
            "deliverables\plan\README.md",
            "deliverables\video\index.html",
            "deliverables\video\styles.css"
        )) {
            $managedAllowlist.Add((Get-SitePath $relativePath)) | Out-Null
        }
        foreach ($managedRelativeRoot in @(
            "deliverables\plan",
            "deliverables\docs",
            "deliverables\video",
            "deliverables\review"
        )) {
            $managedRoot = Get-SitePath $managedRelativeRoot
            if (-not (Test-Path -LiteralPath $managedRoot -PathType Container)) {
                continue
            }
            foreach ($managedFile in Get-ChildItem -LiteralPath $managedRoot -File -Recurse) {
                if (-not $manifestDestinations.Contains($managedFile.FullName) -and
                    -not $managedAllowlist.Contains($managedFile.FullName)) {
                    $manifestProblems.Add("受管交付目錄有未列入 manifest 的多餘檔案：$([IO.Path]::GetRelativePath($siteRoot, $managedFile.FullName))")
                }
            }
        }

        if ($manifestProblems.Count -gt 0) {
            Add-ProblemSummary -Label "deliverables source manifest 已過期或損壞" -Problems $manifestProblems
        }

        if (-not (Test-Path -LiteralPath $webSourceRoot -PathType Container)) {
            Add-Failure "缺少 Flutter Web build：$webSourceRoot"
        }
        elseif (-not (Test-Path -LiteralPath $webDestinationRoot -PathType Container)) {
            Add-Failure "缺少 deliverables app：$webDestinationRoot"
        }
        else {
            $webProblems = [Collections.Generic.List[string]]::new()
            $sourceFiles = @(Get-ChildItem -LiteralPath $webSourceRoot -File -Recurse)
            $destinationFiles = @(Get-ChildItem -LiteralPath $webDestinationRoot -File -Recurse)
            $sourceByRelativePath = @{}
            foreach ($file in $sourceFiles) {
                $relativePath = [IO.Path]::GetRelativePath($webSourceRoot, $file.FullName)
                $sourceByRelativePath[$relativePath] = $file
            }
            $destinationByRelativePath = @{}
            foreach ($file in $destinationFiles) {
                $relativePath = [IO.Path]::GetRelativePath($webDestinationRoot, $file.FullName)
                $destinationByRelativePath[$relativePath] = $file
            }

            foreach ($relativePath in $sourceByRelativePath.Keys) {
                if (-not $destinationByRelativePath.ContainsKey($relativePath)) {
                    $webProblems.Add("deliverables 缺檔：$relativePath")
                    continue
                }
                $sourceFile = $sourceByRelativePath[$relativePath]
                $destinationFile = $destinationByRelativePath[$relativePath]
                if ($sourceFile.Length -ne $destinationFile.Length -or
                    (Get-CachedSha256 -Path $sourceFile.FullName) -ne (Get-CachedSha256 -Path $destinationFile.FullName)) {
                    $webProblems.Add("內容不一致：$relativePath")
                }
                if (-not $manifestAppPaths.Contains($destinationFile.FullName)) {
                    $webProblems.Add("未列入 source manifest：$relativePath")
                }
            }
            foreach ($relativePath in $destinationByRelativePath.Keys) {
                if (-not $sourceByRelativePath.ContainsKey($relativePath)) {
                    $webProblems.Add("deliverables 多檔：$relativePath")
                }
            }

            if ($sourceFiles.Count -ne $destinationFiles.Count -or $destinationFiles.Count -ne $manifestAppPaths.Count) {
                $webProblems.Add("檔案數不同步：build=$($sourceFiles.Count)，deliverables=$($destinationFiles.Count)，manifest=$($manifestAppPaths.Count)")
            }
            if ($webProblems.Count -gt 0) {
                Add-ProblemSummary -Label "deliverables app／build/web／source manifest 不同步" -Problems $webProblems
            }
        }

        if ($manifestProblems.Count -eq 0 -and
            (Test-Path -LiteralPath $webSourceRoot -PathType Container) -and
            (Test-Path -LiteralPath $webDestinationRoot -PathType Container) -and
            $webProblems.Count -eq 0) {
            Add-Pass "$($manifestRecords.Count) 筆 deliverables source manifest 均可重現，app 與 build/web 完全同步"
        }
    }
    catch {
        Add-Failure "deliverables manifest 無法驗證：$($_.Exception.Message)"
    }
}

Write-Output "`n--- 可選外部送件要求 ---"
if ($RequireNativeReview) {
    if ([string]::IsNullOrWhiteSpace($NativeReviewPath)) {
        Add-Failure "-RequireNativeReview 已啟用，但未提供 -NativeReviewPath 或 NATIVE_REVIEW_PATH"
    }
    else {
        try {
            $reviewEvidencePath = if ([IO.Path]::IsPathRooted($NativeReviewPath)) {
                [IO.Path]::GetFullPath($NativeReviewPath)
            }
            else {
                Get-ProjectPath $NativeReviewPath
            }
            if (-not $reviewEvidencePath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "真人審閱紀錄必須存放在專案工作區內"
            }
            if (-not (Test-Path -LiteralPath $reviewEvidencePath -PathType Leaf)) {
                throw "找不到真人審閱匯出 JSON：$reviewEvidencePath"
            }
            $reviewEvidenceRaw = Get-Content -Raw -Encoding UTF8 -LiteralPath $reviewEvidencePath
            if ($reviewEvidenceRaw -match '[A-Za-z]:\\Users\\|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}') {
                throw "真人審閱紀錄含本機絕對路徑或電子郵件，違反匿名送審邊界"
            }
            $reviewEvidence = $reviewEvidenceRaw | ConvertFrom-Json
            $reviewEvidenceProblems = [Collections.Generic.List[string]]::new()
            if ([string]$reviewEvidence.schema -ne 'our-family-says/native-review/v2') {
                $reviewEvidenceProblems.Add("schema 不正確")
            }
            $expectedReviewManifestHash = Get-CachedSha256 -Path $audioManifestPath
            if ([string]$reviewEvidence.manifestSha256 -ne $expectedReviewManifestHash) {
                $reviewEvidenceProblems.Add("審閱紀錄不是目前 119 檔 manifest 版本")
            }
            if ([int]$reviewEvidence.generatedAudioCount -ne 119) {
                $reviewEvidenceProblems.Add("generatedAudioCount 應為 119")
            }
            $currentContextCatalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $nativeReviewContextPath | ConvertFrom-Json
            if ([string]$reviewEvidence.contextCatalogSha256 -ne [string]$currentContextCatalog.contextCatalogSha256) {
                $reviewEvidenceProblems.Add("審閱紀錄不是目前 204 usages 語境目錄版本")
            }
            foreach ($sourceEntry in @(
                @{ Relative = 'lib/models/conversation_episode.dart'; Path = (Join-Path $flutterRoot 'lib\models\conversation_episode.dart') },
                @{ Relative = 'lib/services/app_store.dart'; Path = (Join-Path $flutterRoot 'lib\services\app_store.dart') }
            )) {
                $relative = [string]$sourceEntry.Relative
                $declaredEvidenceSourceHash = [string]$reviewEvidence.contextSourceSha256.$relative
                if ($declaredEvidenceSourceHash -ne [string]$currentContextCatalog.sourceSha256.$relative -or
                    $declaredEvidenceSourceHash -ne (Get-CachedSha256 -Path $sourceEntry.Path)) {
                    $reviewEvidenceProblems.Add("審閱紀錄語境來源 SHA-256 漂移：$relative")
                }
            }
            foreach ($requiredMeta in @('reviewerCode', 'reviewDate', 'languageContext', 'childExperience')) {
                if (-not ($reviewEvidence.meta.PSObject.Properties.Name -contains $requiredMeta) -or
                    [string]::IsNullOrWhiteSpace([string]$reviewEvidence.meta.$requiredMeta)) {
                    $reviewEvidenceProblems.Add("審閱者 metadata 缺少 $requiredMeta")
                }
            }
            if ($reviewEvidence.meta.PSObject.Properties.Name -match 'name|email|phone|school') {
                $reviewEvidenceProblems.Add("審閱 metadata 不得包含姓名、信箱、電話或學校欄位")
            }
            if ([string]$reviewEvidence.meta.reviewerCode -notmatch '^R[0-9A-Z]{2,8}$') {
                $reviewEvidenceProblems.Add("reviewerCode 必須是 R 加 2–8 位大寫英數字")
            }
            if ($reviewEvidence.meta.nativeSpeakerAttestation -ne $true -or
                $reviewEvidence.meta.anonymousUseConsent -ne $true) {
                $reviewEvidenceProblems.Add("審閱者必須勾選本人母語成人聲明與匿名保存同意")
            }
            $parsedReviewDate = [datetime]::MinValue
            if (-not [datetime]::TryParseExact(
                [string]$reviewEvidence.meta.reviewDate,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$parsedReviewDate
            ) -or $parsedReviewDate.Date -gt (Get-Date).Date) {
                $reviewEvidenceProblems.Add("reviewDate 不是有效且不晚於今天的日期")
            }
            $exportedAt = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse([string]$reviewEvidence.exportedAt, [ref]$exportedAt)) {
                $reviewEvidenceProblems.Add("exportedAt 不是有效 ISO 時間")
            }
            if ($reviewEvidence.completion.metadataComplete -ne $true -or
                [int]$reviewEvidence.completion.playedCount -ne 119 -or
                [int]$reviewEvidence.completion.judgedCount -ne 119 -or
                $reviewEvidence.completion.complete -ne $true) {
                $reviewEvidenceProblems.Add("completion 必須證明 metadata、119 次完整播放與 119 筆判定全部完成")
            }
            $evidenceReviews = @($reviewEvidence.reviews)
            if ($evidenceReviews.Count -ne 119) {
                $reviewEvidenceProblems.Add("真人逐檔紀錄應為 119 筆，實際 $($evidenceReviews.Count) 筆")
            }
            $currentAudioManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $audioManifestPath | ConvertFrom-Json
            $expectedReviewByPath = @{}
            foreach ($record in @($currentAudioManifest.files)) {
                $path = [string]$record.path
                $expectedReviewByPath[$path] = [ordered]@{
                    audio = $record
                    context = @($currentContextCatalog.records | Where-Object { [string]$_.path -eq $path })[0]
                }
            }
            $seenReviewPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $passReviewCount = 0
            $reviseReviewCount = 0
            foreach ($review in $evidenceReviews) {
                $path = [string]$review.path
                if (-not $seenReviewPaths.Add($path)) {
                    $reviewEvidenceProblems.Add("真人審閱路徑重複：$path")
                    continue
                }
                if (-not $expectedReviewByPath.ContainsKey($path)) {
                    $reviewEvidenceProblems.Add("真人審閱含非目前 manifest 路徑：$path")
                    continue
                }
                $expected = $expectedReviewByPath[$path]
                if ([string]$review.text -ne [string]$expected.audio.text -or
                    [long]$review.bytes -ne [long]$expected.audio.bytes -or
                    ([string]$review.sha256).ToUpperInvariant() -ne ([string]$expected.audio.sha256).ToUpperInvariant()) {
                    $reviewEvidenceProblems.Add("真人審閱文字或音檔 bytes／雜湊漂移：$path")
                }
                $expectedMeanings = @($expected.context.intendedMeaningsZh) | ConvertTo-Json -Compress
                $actualMeanings = @($review.intendedMeaningsZh) | ConvertTo-Json -Compress
                $expectedContexts = @($expected.context.contexts) | ConvertTo-Json -Depth 12 -Compress
                $actualContexts = @($review.contexts) | ConvertTo-Json -Depth 12 -Compress
                if ($actualMeanings -ne $expectedMeanings -or
                    $actualContexts -ne $expectedContexts -or
                    [string]$review.registerReviewScope -ne [string]$expected.context.registerReviewScope) {
                    $reviewEvidenceProblems.Add("真人審閱中文意圖或使用語境漂移：$path")
                }
                if ($review.played -ne $true -or [int]$review.playCount -lt 1) {
                    $reviewEvidenceProblems.Add("未證明由 audio ended 完整播放：$path")
                }
                $lastPlayedAt = [DateTimeOffset]::MinValue
                if (-not [DateTimeOffset]::TryParse([string]$review.lastPlayedAt, [ref]$lastPlayedAt) -or
                    $lastPlayedAt -gt $exportedAt.AddMinutes(1)) {
                    $reviewEvidenceProblems.Add("lastPlayedAt 無效或晚於匯出時間：$path")
                }
                $lastDurationSeconds = 0.0
                if (-not [double]::TryParse(
                    [string]$review.lastDurationSeconds,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$lastDurationSeconds
                ) -or $lastDurationSeconds -le 0 -or $lastDurationSeconds -gt 30) {
                    $reviewEvidenceProblems.Add("lastDurationSeconds 無效：$path")
                }
                $criteriaValues = @(
                    [string]$review.textNatural,
                    [string]$review.familyRegister,
                    [string]$review.audioClear
                )
                if (@($criteriaValues | Where-Object { $_ -notin @('yes', 'no') }).Count -gt 0) {
                    $reviewEvidenceProblems.Add("三項審閱必須各為 yes 或 no：$path")
                }
                if ([string]$review.status -eq 'pass') {
                    $passReviewCount++
                    if (@($criteriaValues | Where-Object { $_ -ne 'yes' }).Count -gt 0) {
                        $reviewEvidenceProblems.Add("pass 必須三項全為 yes：$path")
                    }
                }
                elseif ([string]$review.status -eq 'revise') {
                    $reviseReviewCount++
                    if (@($criteriaValues | Where-Object { $_ -eq 'no' }).Count -eq 0 -or
                        ([string]::IsNullOrWhiteSpace([string]$review.correction) -and
                         [string]::IsNullOrWhiteSpace([string]$review.notes))) {
                        $reviewEvidenceProblems.Add("revise 必須至少一項 no，並填修訂或理由：$path")
                    }
                }
                else {
                    $reviewEvidenceProblems.Add("尚未判定可保留或需修訂：$path")
                }
                $rating = 0
                if (-not [int]::TryParse([string]$review.rating, [ref]$rating) -or $rating -lt 1 -or $rating -gt 5) {
                    $reviewEvidenceProblems.Add("自然度未填 1–5：$path")
                }
            }
            if ($reviewEvidenceProblems.Count -gt 0) {
                Add-ProblemSummary -Label "真人越南語逐檔審閱紀錄未完成" -Problems $reviewEvidenceProblems
            }
            else {
                Add-Pass "真人越南語審閱紀錄與目前 119 檔完全對齊：可保留 $passReviewCount、需修訂 $reviseReviewCount"
            }
        }
        catch {
            Add-Failure "真人越南語逐檔審閱無法驗證：$($_.Exception.Message)"
        }
    }
}
else {
    Add-Skip "未啟用 -RequireNativeReview；空白審閱工具不算真人母語成果"
}

if ($RequireVideo) {
    $videoRoot = Get-ProjectPath "交付成果\影片"
    $videoCandidates = @(Get-ChildItem -LiteralPath $videoRoot -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @('.mp4', '.mov')
    })
    $videoProblems = [Collections.Generic.List[string]]::new()
    $requiredVideoSpecs = [ordered]@{
        "傳家話_正式初審影片.mp4" = [ordered]@{
            role = 'submission_1080p'; width = 1920; height = 1080; maximumBytes = 300MB
        }
        "傳家話_網頁預覽.mp4" = [ordered]@{
            role = 'web_preview_720p'; width = 1280; height = 720; maximumBytes = 25MB
        }
    }
    foreach ($video in $videoCandidates) {
        if (-not $requiredVideoSpecs.Contains($video.Name)) {
            $videoProblems.Add("影片目錄有未定義成品，可能造成誤傳：$($video.Name)")
        }
    }

    $verificationPath = Join-Path $videoRoot "傳家話_正式初審影片_驗證.json"
    $verification = $null
    $verificationByFile = @{}
    if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
        $videoProblems.Add("缺少雙影片驗證 JSON")
    }
    else {
        try {
            $verification = Get-Content -Raw -Encoding UTF8 -LiteralPath $verificationPath | ConvertFrom-Json
            if ([int]$verification.schemaVersion -ne 3 -or [string]$verification.validation -ne 'PASS') {
                $videoProblems.Add("影片驗證 JSON 必須是 schemaVersion 3 且 validation=PASS")
            }
            if ($verification.metadataPolicy.anonymous -ne $true -or
                [string]$verification.metadataPolicy.localAbsolutePathsAllowed -ne 'False' -or
                [string]$verification.metadataPolicy.validation -ne 'PASS' -or
                $verification.evidence.humanTestimony -ne $false) {
                $videoProblems.Add("影片驗證 JSON 的匿名／無真人證言邊界不正確")
            }
            foreach ($evidenceDirectory in @(
                [string]$verification.evidence.screenshotDirectory,
                [string]$verification.evidence.imageDirectory
            )) {
                if ([IO.Path]::IsPathRooted($evidenceDirectory) -or
                    -not (Test-Path -LiteralPath (Get-ProjectPath $evidenceDirectory) -PathType Container)) {
                    $videoProblems.Add("影片驗證 JSON 的相對素材目錄不存在或不是專案相對路徑：$evidenceDirectory")
                }
            }
            foreach ($record in @($verification.outputs)) {
                $recordFile = [string]$record.file
                if ($verificationByFile.ContainsKey($recordFile)) {
                    $videoProblems.Add("影片驗證 JSON 檔名重複：$recordFile")
                }
                else {
                    $verificationByFile[$recordFile] = $record
                }
            }
            if ($verificationByFile.Count -ne 2) {
                $videoProblems.Add("影片驗證 JSON 應恰有正式檔與 Web preview 兩筆輸出")
            }
        }
        catch {
            $videoProblems.Add("影片驗證 JSON 無法解析：$($_.Exception.Message)")
        }
    }

    $ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -eq $ffprobe) {
        $videoProblems.Add("系統沒有 ffprobe，無法驗證實際影音 stream")
    }
    if ($null -eq $ffmpeg) {
        $videoProblems.Add("系統沒有 ffmpeg，無法驗證影片開場音軌是否真的可聽")
    }
    if ($null -ne $ffprobe) {
        foreach ($entry in $requiredVideoSpecs.GetEnumerator()) {
            $videoName = [string]$entry.Key
            $spec = $entry.Value
            $videoPath = Join-Path $videoRoot $videoName
            if (-not (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
                $videoProblems.Add("缺少必要影片：$videoName")
                continue
            }
            $video = Get-Item -LiteralPath $videoPath
            if ($video.Length -le 0 -or $video.Length -ge [long]$spec.maximumBytes) {
                $videoProblems.Add("影片必須 >0 且嚴格小於 $([long]$spec.maximumBytes) bytes：$videoName（$($video.Length) bytes）")
            }

            if ($null -ne $ffmpeg) {
                $openingVolumeRaw = (& $ffmpeg.Source -hide_banner -nostats -ss 0 -t 12 -i $video.FullName -map 0:a:0 -af volumedetect -f null NUL 2>&1 | Out-String)
                $openingVolumeExitCode = $LASTEXITCODE
                $meanMatch = [regex]::Match($openingVolumeRaw, 'mean_volume:\s*(?<value>-?(?:\d+(?:\.\d+)?|inf))\s*dB')
                $maxMatch = [regex]::Match($openingVolumeRaw, 'max_volume:\s*(?<value>-?(?:\d+(?:\.\d+)?|inf))\s*dB')
                $openingMeanDb = [double]::NegativeInfinity
                $openingMaxDb = [double]::NegativeInfinity
                if ($meanMatch.Success -and $meanMatch.Groups['value'].Value -ne '-inf') {
                    [double]::TryParse(
                        $meanMatch.Groups['value'].Value,
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$openingMeanDb
                    ) | Out-Null
                }
                if ($maxMatch.Success -and $maxMatch.Groups['value'].Value -ne '-inf') {
                    [double]::TryParse(
                        $maxMatch.Groups['value'].Value,
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$openingMaxDb
                    ) | Out-Null
                }
                if ($openingVolumeExitCode -ne 0 -or -not $meanMatch.Success -or -not $maxMatch.Success) {
                    $videoProblems.Add("ffmpeg 無法量測開場 12 秒音量：$videoName")
                }
                elseif ($openingMeanDb -lt -42 -or $openingMaxDb -lt -30) {
                    $videoProblems.Add("開場 12 秒近似靜音：$videoName（mean $openingMeanDb dBFS、max $openingMaxDb dBFS；需 mean >= -42 且 max >= -30）")
                }
            }

            $probeRaw = (& $ffprobe.Source -v error -show_streams -show_format -of json -- $video.FullName 2>&1 | Out-String)
            $probeExitCode = $LASTEXITCODE
            if ($probeExitCode -ne 0) {
                $videoProblems.Add("ffprobe 無法解析：$videoName")
                continue
            }
            try {
                $probe = $probeRaw | ConvertFrom-Json
                $videoStreams = @($probe.streams | Where-Object { [string]$_.codec_type -eq 'video' })
                $audioStreams = @($probe.streams | Where-Object { [string]$_.codec_type -eq 'audio' })
                if ($videoStreams.Count -ne 1 -or $audioStreams.Count -ne 1) {
                    $videoProblems.Add("應恰有一條 video 與一條 audio stream：$videoName")
                    continue
                }
                $videoStream = $videoStreams[0]
                $audioStream = $audioStreams[0]
                $duration = [double]$probe.format.duration
                if ($duration -le 0 -or $duration -gt 180.0) {
                    $videoProblems.Add("影片應在 3 分鐘內：$videoName（$duration 秒）")
                }
                if ([string]$videoStream.codec_name -ne 'h264' -or
                    [string]$videoStream.pix_fmt -ne 'yuv420p' -or
                    [int]$videoStream.width -ne [int]$spec.width -or
                    [int]$videoStream.height -ne [int]$spec.height -or
                    [string]$videoStream.avg_frame_rate -ne '30/1') {
                    $videoProblems.Add("影像規格不是 H.264／$($spec.width)x$($spec.height)／yuv420p／30fps：$videoName")
                }
                if ([string]$audioStream.codec_name -ne 'aac' -or
                    [int]$audioStream.sample_rate -ne 48000 -or
                    [int]$audioStream.channels -ne 2) {
                    $videoProblems.Add("音訊規格不是 AAC／48kHz／雙聲道：$videoName")
                }
                $tagText = @($probe.format.tags, @($probe.streams | ForEach-Object { $_.tags })) | ConvertTo-Json -Depth 6 -Compress
                if ($tagText -match '[A-Za-z]:\\Users\\|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|我們家怎麼說|島語通|DaoTalk|WorkBridge|家語貼|HomeTongue Tags') {
                    $videoProblems.Add("影片 metadata 含本機身分、電子郵件或舊題目：$videoName")
                }

                if (-not $verificationByFile.ContainsKey($videoName)) {
                    $videoProblems.Add("驗證 JSON 缺少：$videoName")
                    continue
                }
                $record = $verificationByFile[$videoName]
                if ([string]$record.role -ne [string]$spec.role -or
                    [string]$record.validation -ne 'PASS' -or
                    [long]$record.bytes -ne $video.Length -or
                    ([string]$record.sha256).ToUpperInvariant() -ne (Get-CachedSha256 -Path $videoPath) -or
                    [int]$record.video.width -ne [int]$spec.width -or
                    [int]$record.video.height -ne [int]$spec.height -or
                    [string]$record.video.codec -ne 'h264' -or
                    [string]$record.audio.codec -ne 'aac' -or
                    [math]::Abs([double]$record.durationSeconds - $duration) -gt 0.02 -or
                    $record.metadata.anonymous -ne $true -or
                    [string]$record.metadata.localAbsolutePathScan -ne 'PASS') {
                    $videoProblems.Add("驗證 JSON 的 bytes／SHA／ffprobe／匿名欄位與實檔不一致：$videoName")
                }
            }
            catch {
                $videoProblems.Add("影片 stream 驗證失敗：$videoName（$($_.Exception.Message)）")
            }
        }
    }
    if ($videoProblems.Count -gt 0) {
        Add-ProblemSummary -Label "正式初審影片雙輸出未通過" -Problems $videoProblems
    }
    else {
        Add-Pass "1080p 正式檔與 <25MiB 720p Web preview 的實檔、SHA-256、ffprobe、匿名 metadata 全部一致"
    }
}
else {
    Add-Skip "未啟用 -RequireVideo；預設模式不要求外部影片成品"
}

if ($RequirePublicUrl) {
    if ([string]::IsNullOrWhiteSpace($PublicUrl)) {
        Add-Failure "-RequirePublicUrl 已啟用，但未提供 -PublicUrl 或 SUBMISSION_PUBLIC_URL"
    }
    else {
        $uri = $null
        if (-not [Uri]::TryCreate($PublicUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            Add-Failure "公開作品網址必須是有效 HTTPS URL"
        }
        elseif (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
            Add-Failure "公開作品網址不得在 URL 內嵌帳號或密碼"
        }
        elseif ($uri.IsLoopback -or $uri.Host -in @('localhost', '0.0.0.0', '::1') -or $uri.Host.EndsWith('.local', [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "公開作品網址不得使用 localhost 或 loopback：$($uri.Host)"
        }
        else {
            try {
                $resolvedAddresses = @([Net.Dns]::GetHostAddresses($uri.DnsSafeHost))
                if ($resolvedAddresses.Count -eq 0 -or @($resolvedAddresses | Where-Object { Test-NonPublicIpAddress $_ }).Count -gt 0) {
                    throw "主機未解析到純公開 IP"
                }
                $response = Invoke-WebRequest -Uri $uri -MaximumRedirection 5 -TimeoutSec 20
                if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
                    Add-Failure "公開作品網址回傳 HTTP $($response.StatusCode)"
                }
                elseif (-not ([string]$response.Content).Contains('flutter_bootstrap.js', [StringComparison]::OrdinalIgnoreCase)) {
                    Add-Failure "公開作品網址可連線，但回應不是目前 Flutter Web 入口（缺少 flutter_bootstrap.js）"
                }
                else {
                    $publicAssetProblems = [Collections.Generic.List[string]]::new()
                    $appBaseUri = [Uri]::new($uri.AbsoluteUri.TrimEnd('/') + '/')
                    $httpClient = [Net.Http.HttpClient]::new()
                    try {
                        $httpClient.DefaultRequestHeaders.CacheControl = [Net.Http.Headers.CacheControlHeaderValue]::new()
                        $httpClient.DefaultRequestHeaders.CacheControl.NoCache = $true
                        foreach ($assetName in @('main.dart.js', 'flutter_bootstrap.js')) {
                            $localAssetPath = Join-Path $webSourceRoot $assetName
                            if (-not (Test-Path -LiteralPath $localAssetPath -PathType Leaf)) {
                                $publicAssetProblems.Add("本機 build/web 缺少 $assetName")
                                continue
                            }
                            $cacheKey = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                            $assetUri = [Uri]::new($appBaseUri, "$assetName`?gate=$cacheKey")
                            $assetResponse = $httpClient.GetAsync($assetUri).GetAwaiter().GetResult()
                            if (-not $assetResponse.IsSuccessStatusCode) {
                                $publicAssetProblems.Add("公開 $assetName 回傳 HTTP $([int]$assetResponse.StatusCode)")
                                continue
                            }
                            $assetBytes = $assetResponse.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                            $publicHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($assetBytes))
                            if ($publicHash -ne (Get-CachedSha256 -Path $localAssetPath)) {
                                $publicAssetProblems.Add("公開 $assetName 與本機 build/web SHA-256 不同")
                            }
                        }
                    }
                    finally {
                        $httpClient.Dispose()
                    }
                    if ($publicAssetProblems.Count -gt 0) {
                        Add-ProblemSummary -Label "公開作品不是目前通過驗證的 Web build" -Problems $publicAssetProblems
                    }
                    else {
                        Add-Pass "公開 HTTPS 作品可連線，且 main.dart.js／flutter_bootstrap.js 與本機 build/web SHA-256 一致"
                    }
                }
            }
            catch {
                Add-Failure "公開作品網址無法連線：$($_.Exception.Message)"
            }
        }
    }
}
else {
    Add-Skip "未啟用 -RequirePublicUrl；預設模式不連線外部網址"
}

Write-Output ""
if ($failures.Count -gt 0) {
    Write-Output "SUBMISSION GATE FAILED：共 $($failures.Count) 項。"
    Write-Output "修正上列 [FAIL] 後重新執行；外部影片、網址、真人母語審閱與人工插圖權利只在對應 switch 啟用時檢查。"
    exit 1
}

Write-Output "SUBMISSION GATE PASSED：canonical、119 音檔、11 張插圖技術來源與 deliverables 同步檢查全部通過。"
exit 0
