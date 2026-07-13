# 「傳家話」直接相依套件與授權

本表依 `pubspec.lock` 的實際解析版本整理。「傳家話」沒有付費 API、廣告或追蹤套件；這份清單也不把套件的免費使用誤寫成「沒有授權義務」。正式發布的 Web 產物另附 Flutter 產生的 `build/web/assets/NOTICES`，收錄執行期相依項目的完整授權文字。

| 套件 | 鎖定版本 | 用途 | 授權 |
|---|---:|---|---|
| cupertino_icons | 1.0.9 | 介面圖示 | MIT |
| crypto | 3.0.7 | SHA-256、HMAC 與內容雜湊 | BSD-3-Clause |
| cryptography | 2.9.0 | PBKDF2-HMAC-SHA256 與 Ed25519 邀請簽章 | Apache-2.0 |
| flutter_tts | 4.2.5 | 家庭自訂文字或隨包音檔失敗時的裝置朗讀 | MIT |
| http | 1.6.0 | 將瀏覽器錄音 Blob 讀入持久化媒體層 | BSD-3-Clause |
| idb_shim | 2.9.6+2 | Web IndexedDB 音訊保存 | BSD-2-Clause |
| image_picker | 1.2.3 | 相機與相簿 | BSD-3-Clause |
| just_audio | 0.9.46 | 播放本機音檔 | MIT |
| mobile_scanner | 6.0.11 | QR 掃描 | BSD-3-Clause |
| path_provider | 2.1.6 | App 私有資料路徑 | BSD-3-Clause |
| qr_flutter | 4.1.0 | QR 顯示 | BSD-3-Clause |
| record | 5.2.1 | 本機錄音 | BSD-3-Clause |
| record_linux | 1.3.1 | `record` 的相容性覆寫 | BSD-3-Clause |
| sembast | 3.8.9+1 | `idb_shim` 的跨平台儲存相依 | BSD-3-Clause |
| shared_preferences | 2.5.5 | 小型本機狀態 | BSD-3-Clause |
| speech_to_text | 7.4.0 | 選配的裝置／瀏覽器短句語音辨識 | BSD-3-Clause |
| url_launcher | 6.3.2 | 在使用者明確按下後開啟官方教育資訊頁 | BSD-3-Clause |
| web | 1.1.1 | Web Blob URL 生命週期管理 | BSD-3-Clause |

`flutter` 與 `flutter_test` 由 Flutter SDK 提供；`flutter_lints` 只用於開發檢查。套件名稱、版本與授權仍應在正式上架前由自動化授權掃描再核對一次。

## 越南語合成操作示範

現行 119 個引用 MP3 全部由釘選的 Piper `vi_VN-vais1000-medium`
v1.0.0 模型離線產生，不含 Microsoft／`edge-tts` 候選檔。Piper 與模型庫標示
MIT；模型卡將 VAIS-1000 語料列為 CC BY 4.0。模型 SHA-256、119 筆輸入文字、
逐檔雜湊、產生腳本與完整署名記錄在 `assets/audio/README.md`、
`assets/audio/piper_generation_manifest.json` 與 `tool/generate_bundled_audio.ps1`。
介面將它們標示為「預錄示範」，不稱家人原音或母語者審閱版本。

## Noto Sans TC

Web 版打包 `assets/fonts/NotoSansTC-VF.ttf`，避免不同評審裝置缺少繁中、臺羅或越文變音符號。字型來源為 notofonts 的 Noto CJK 官方儲存庫，採 SIL Open Font License 1.1；完整授權文字保存在 `assets/fonts/OFL-NotoSansCJK.txt`。

## 場景插圖

作品內建場景是生成式工具製作的合成原型插圖，不是實拍、圖庫素材或使用者證言。逐檔 bytes、SHA-256、目前可證明的來源邊界，以及正式送件前仍須確認的工具揭露／使用權事項，記錄在 `assets/images/README.md`。
