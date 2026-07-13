# 《傳家話》正式初審影片製作說明

成品：

- `傳家話_正式初審影片.mp4`：正式送審用 1920×1080 版本。
- `傳家話_網頁預覽.mp4`：由正式檔可重現轉製的 1280×720 Web 版本，單檔嚴格小於 25 MiB。

## 可重現產生

在本資料夾以 PowerShell 7 執行：

```powershell
pwsh -NoProfile -File .\build_submission_video.ps1
```

需求：Windows、PowerShell 7、FFmpeg／ffprobe、系統字型 Microsoft JhengHei，以及 Windows 繁中語音 `Microsoft Hanhan Desktop`。腳本會從現行 `正式版/flutter_app/test-results/`、`assets/images/` 與 `assets/audio/` 讀取素材，在暫存資料夾產生畫面與每幕繁中合成旁白，先建立正式 1080p MP4，再以兩階段 H.264 編碼從正式檔轉製 720p Web preview。最後只留下兩支 MP4 與驗證 JSON。可用 `-KeepWorkFiles` 保留中間投影片、旁白 WAV、無聲母帶與壓縮紀錄。

`video_content.json` 保存每幕文字與旁白、長度、素材檔名、音訊插入時間、響度目標、Web preview 檔名、25 MiB 位元組上限與目標影像碼率；調整內容後重新執行即可產出一致規格的兩支影片。

## 素材與誠實邊界

- 介面畫面：現行 Flutter Web 的 Pixel 7 尺寸自動化截圖，不是假造的真人使用畫面。
- 場景圖：專案既有的生成式合成原型插圖，不是家庭照片或使用者證言；10 次原始生成、逐次 prompt、匿名技術紀錄與 11 個成品轉換雜湊已封存，公開邊界記錄於 App 的 `assets/images/README.md`。本人權利聲明仍須另行完成。
- 繁中旁白：由 Windows SAPI 的 `Microsoft Hanhan Desktop` 在本機依 `video_content.json` 逐幕合成，不是真人錄音或使用者證言。
- 產品語音：兩段現行 Piper 越南語合成操作示範，完整模型、資料集授權與逐檔 SHA-256 記錄於 App 的 `assets/audio/README.md` 與 manifest。影片不稱它們為家人原音或母語者審閱版本。
- 背景聲：腳本直接以 FFmpeg 數學振盪器合成的原創低音量氛圍音，不引用第三方歌曲、錄音或音效素材。
- 混音：繁中旁白、Piper 示範與背景床分別校準；背景目標為 -28 LUFS，語音出現時另做 sidechain duck，最後只套固定 +2 dB 節目增益與 -2 dBFS limiter，不以整片動態正規化把安靜段硬拉高。
- 本片不宣稱已完成母語審閱、真實兒童試演、遠端同步、逐音評分、即時生圖或公開 HTTPS。

## 成品驗證

兩支 MP4 皆移除來源 metadata，再只寫入匿名作品標題與素材邊界說明；容器內不含帳號、作者、機器名稱或本機絕對路徑。

腳本完成後會用 ffprobe 強制檢查：

- 正式檔：H.264、1920×1080、30 fps、16:9、3 分鐘內；AAC、48 kHz、雙聲道。
- Web preview：H.264、1280×720、30 fps、16:9、3 分鐘內；AAC、48 kHz、雙聲道；檔案大小必須 `< 26,214,400 bytes`，等於嚴格小於 25 MiB。
- 兩者皆為 MP4、`faststart`，並分別記錄精確 bytes、SHA-256 與 ffprobe 欄位。
- 兩者都以 EBU R128／ITU-R BS.1770 重新量測：整片名目目標約 -16 LUFS、通過區間 -19 至 -14 LUFS，true peak 必須 `<= -1 dBTP`。
- 每一幕都必須落在 -22 至 -12 LUFS；每個繁中旁白與 Piper 示範窗口也各自量測，除相同可聽區間外，還必須至少高於背景床 8 LU。這能攔住「只有三個瞬間很大聲、其餘畫面幾乎無聲」但整片數字仍看似正常的錯誤。

結果保存於 `傳家話_正式初審影片_驗證.json` 的 `outputs` 陣列；schema v3 會在每支輸出的 `audio.loudness` 記錄整片、逐幕與逐語音窗口結果。正式檔與 Web preview 使用同一個 machine-readable schema。若任一必要條件不符，腳本會以失敗結束，不會把錯誤規格當成可送件成品。
