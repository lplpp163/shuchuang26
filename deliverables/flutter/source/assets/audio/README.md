# 越南語隨包示範音檔

> 這些音檔只提供競賽原型操作示範。它們不是家人原音，也尚未經越南語母語者逐句驗收；正式公開展示前仍須由母語家人複聽或以同名真人錄音替換。

## 現行交付範圍

- App 實際引用 119 個 MP3：28 個教材完整句／自然分段／替換例句，以及五集家庭劇場的 91 條唯一台詞。
- 119／119 檔案皆由同一個已釘選的 Piper 模型離線產生；不含 `edge-tts` 或 Microsoft neural voice 產物。
- 119／119 皆非空且可由 `ffprobe` 解析，合計 799,305 bytes、134.82 秒；最短 0.283 秒，最長 3.518 秒。
- `piper_generation_manifest.json` 記錄每個檔案的路徑、文字、bytes 與 SHA-256。`tool/bundled_audio_catalog.dart` 是 119 條「路徑／輸入文字」的可重現 catalog。

2026-07-13 曾使用無完整再散布證據的 Microsoft 開發候選檔；這些候選已全部被下列釘選 Piper 產物覆蓋，三個不再引用的歷史 MP3 也已移除，不進入目前交付包。

## 來源、版本與授權

| 項目 | 釘選內容 | 授權／用途 |
|---|---|---|
| 合成器 | Piper `2023.11.14-2`，CLI 回報 `1.2.0` | MIT；只在開發期離線產檔，App 執行時不依賴它 |
| 聲音模型 | `rhasspy/piper-voices` v1.0.0，`vi_VN-vais1000-medium` | 模型庫標示 MIT |
| 訓練語料 | VAIS-1000 | 模型卡列 CC BY 4.0 |
| 模型 SHA-256 | `EC7C89E2C85F4D1EDC24B6120C18AAF1BDA614F06B511567EB9C7C0DE15E2DAB` | 產生腳本先驗證，不符即停止 |
| 模型卡 SHA-256 | `302DB8A930FFC2B1C2181DB26DEAF8272116ECA2B08B8F80DA6375B0A994AF7B` | 保存來源內容完整性 |

上游來源：

- Piper release：`https://github.com/rhasspy/piper/releases/tag/2023.11.14-2`
- 模型、設定與模型卡：`https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0/vi/vi_VN/vais1000/medium`
- 模型卡所列 VAIS-1000：`https://ieee-dataport.org/documents/vais-1000-vietnamese-speech-synthesis-corpus`
- CC BY 4.0：`https://creativecommons.org/licenses/by/4.0/`

## 可重現產生

Windows 版 Piper 對非 ASCII 模型路徑不穩定，因此以下示例使用 ASCII 路徑或 junction：

```powershell
pwsh -NoProfile -File .\tool\generate_bundled_audio.ps1 `
  -PiperExe C:\work\piper-v1.0.0\runtime\piper\piper.exe `
  -ModelPath C:\work\piper-v1.0.0\vi_VN-vais1000-medium.onnx
```

腳本會先核對模型 SHA-256，再由 `bundled_audio_catalog.dart` 讀取 119 條文字，逐檔產生 WAV、用 FFmpeg 轉為 22,050 Hz mono MP3，最後寫出 manifest。產生結果仍須通過資產測試與母語者實聽；hash 一致只證明位元內容可重現，不證明聲調或稱謂正確。

## App 播放策略

- Web 第一次進入每一幕不依賴自動播放；孩子必須點「聽長輩這一句」，讓 Edge／Chrome 收到明確媒體手勢。
- 家人已錄下同一節點時，真人家人原音優先於隨包示範。
- 隨包檔案失敗時才誠實退回裝置 TTS，並在介面標示來源。
- 家庭自訂但尚未錄音的文字可使用裝置 TTS，不把合成語音冒充家人原音。
- 完整句的句尾助詞不拆成孤立練習項目；自然分段仍保留句內語境。

## 驗證邊界

自動測試、`ffprobe`、瀏覽器媒體事件與 SHA-256 能證明路徑、檔案和播放流程；它們不能認證越南語聲調、自然度、家族稱謂或地方語氣。正式送件仍需要一份母語者逐句審閱紀錄，並直接替換任何不自然的同名 MP3。
