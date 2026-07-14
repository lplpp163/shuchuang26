# 傳家話｜團隊成果網站

這個目錄是作品的本機展示與交付鏡像。產品有兩條可展示主線：「約30秒三幕零資料試演 → 孩子點場景圖 → 外婆同圖回話 → 三棒傳回家 → 成人同意後進入五集三幕劇場 → 家庭故事卡 → 家長第一屏先回最新故事」，以及「孩子選第一棒 → 成人PIN／家人確認 → 看、聽、排、答四階段 → 三棒家庭接力作品 → 家人圈重播」。麥克風不是完成故事的必要條件；家長的過去故事與管理工具預設收合。試演只使用固定Piper合成示範，不建立家庭、故事、接力或作答資料。

## 直接瀏覽

- `index.html`：問題、產品流程、技術邊界與成果狀態。
- `deliverables/app/index.html`：可操作的 Flutter Web 作品。
- `deliverables/flutter/index.html`：Flutter 原始碼鏡像索引。
- `deliverables/plan/chuan-jia-hua-plan.pdf`：正式計畫書 PDF。
- `deliverables/plan/chuan-jia-hua-plan.docx`：正式計畫書 DOCX。
- `deliverables/video/chuan-jia-hua-submission.mp4`：2分53.9秒、720p H.264／AAC 網頁預覽；1080p正式檔保留在上層送審來源，不放入有25 MiB單檔上限的公開站點。
- `deliverables/video/index.html`：影片播放、規格、分鏡與誠實邊界。
- `deliverables/docs/technical-validation.md`：最新技術驗證紀錄。
- `deliverables/docs/strict-review.md`：嚴格驗收與外部缺口。
- `deliverables/docs/family-pilot-questionnaire.md`：家庭需求、約 30 秒三幕試演與導入端訪談協議；空白模板不等於實證。
- [22頁教師家庭延伸情境包（四週試辦版）](deliverables/pilot/teacher-family-extension-pack.pdf)：可執行的導入工具；唯一價格單位是8,000元／一班／一次四週／最多30戶待訪談假設。
- [離線匿名試辦彙整台](deliverables/pilot/evidence-workbench.html)：固定schema白名單，拒絕疑似個資、重複cohort與錯誤漏斗；工具不等於真人結果。
- `deliverables/review/index.html`：逐檔完整播放119個交付音檔，依204個可追溯使用語境作三項是／否判定並匯出v2 JSON／CSV；空白工具不等於審閱完成。
- `deliverables/review/context-catalog.json`：119路徑的中文意圖、劇集／教案、說話者／聽者與來源雜湊。
- `deliverables/review/chuan-jia-hua-native-review-portable.zip`：含HTML、119個MP3、manifest、語境目錄、README及逐檔SHA256SUMS的離線包。

## 啟動與停止

從上一層工作區執行：

```bat
啟動網頁版.cmd
停止網頁版.cmd
```

啟動器在 `127.0.0.1:8765` 背景執行；命令視窗自動關閉代表啟動完成。重複啟動會重用同一個 PID，不會建立第二個 server；可執行 `啟動網頁版.cmd status` 查看 PID。停止器只會停止這個工作區在該埠的 Python server，不會終止占用相同埠的其他程式。

可用隔離的隨機連接埠自動驗證「連續啟動仍是同一 PID、停止後 PID 與 listener 都消失」，不會碰正在使用的 8765：

```powershell
.\scripts\local-web-server.test.ps1
```

影片頁另提供「播放有聲預覽」按鈕；它必須由使用者點擊，並會明確取消影片元素靜音、把音量設為 100% 及顯示播放狀態。若仍無聲，請確認瀏覽器分頁未被靜音及系統選對輸出裝置。

## 同步與驗收

```powershell
.\scripts\sync-deliverables.ps1
.\scripts\submission-gate.ps1
```

同步腳本從上層專案複製正式計畫書、影片、驗收、試辦／審閱工具、Flutter原始碼及相對路徑Web build，重建`deliverables/manifest.json`並核對SHA-256。submission gate另精確要求「傳家話｜說一句・演成我們家的故事」、拒絕舊副標，檢查匿名彙整台離線邊界、119個Piper MP3的bytes／hash，以及鏡像與來源完全一致。

Round 15把孩子與家長兩個高雜訊頁面改成圖像與任務優先：圖內兩個選擇、選後才展開練習、免麥克風直達同圖外婆回應，以及家長最新故事先出現、過去故事與管理工具預設收合。下列是目前可採信證據；Round 14以前數字只作歷史快照。

- 格式70檔無漂移、`flutter analyze` 0問題、Flutter測試137／137、相對路徑Web build通過；Chromium與Edge的App各8／8。
- 最終同步網站的Chromium與Edge完整套件各12／12；Edge有聲媒體另為2／2。`-RequireVideo` submission gate通過426筆manifest、119音檔／204語境、124檔可攜包、匿名彙整台與雙影片實檔核對。
- 正式計畫書PDF／DOCX皆19頁：PDF 841,392 bytes／`006669BD0935BDEE87331CD6365D008C7335E85F25201B5FAA0D171CE7E70637`；DOCX 971,099 bytes／`AC1FD8FDCAD1008884B2D9E7CDF10C3210B97B535807D8811748F02B05A75A21`。22頁教師包為594,647 bytes／`4422A71CC412660B6705B2853963C77DBF8183E7E8EDC7A8FC340CCACBC4C97A`；兩者QA通過。
- 正式影片173.900秒、53,608,354 bytes／`BC250BC3BB0CC39AE1E69A21F51215A2C91FDF855DD36660815E8DABC847B84D`；720p預覽21,425,556 bytes／`AC05BF77E8B2DC3771B9EEEC4087B9E63232433C3A6E4C6CB70889172F8DCFC4`。15／15場景與17／17語音窗PASS，驗證JSON為`BCC6D6693959CCCAD8AB825A74C0405E67E19EB8B6CE747079AE0330EA11C7BA`。
- 八面向本機平均8.94／10、一票否決0、P0 0；沒有新增真人家庭、母語者或買方證據，因此嚴格IEC仍為74／100，市場仍受16／30上限。

Round 12 的產品與文件已加入五題材家庭接力、只在完成後蓋章的故事護照、每筆教育資訊的本機主題延伸，以及 19 頁四週教師家庭延伸試辦包。教育延伸均須明示「非官方授權教案」；試辦包不代表已採用、有效、合作或成交。目前已由來源端核對的 Round 12 快照如下，上一輪 121／121、瀏覽器 5／5與舊影片 hash 只作 Round 11 歷史紀錄：

- `flutter analyze` 0 問題、Flutter 測試 133／133，完整 quality gate 與相對路徑 Web build 通過。Web build 內公開匿名的 `assets/images/provenance_manifest.json` 為 11,385 bytes，SHA-256 `3F1F6503E5103C08896BBB17954BAE4F7D24ED8EDDC4337FA2A12FE3E367E41B`。
- Chromium 與 Edge 的 App 回歸各 7／7，皆包含 Pixel 7 viewport 視覺 2／2與 Web 行為 5／5；兩個瀏覽器都從同一次明確點擊取得實際 MP3 HTTP 200，並由真正的 `HTMLAudioElement` 完成 `play → playing → ended`、無 `error`、duration／currentTime 大於 0。Pixel 7 viewport 不是實體手機證據。
- 同步網站的完整 Playwright 套件由 Chromium 與 Edge 各一次不中斷跑完 10／10，加入影片交付頁、線上母語審閱工具與解壓後 124 檔可攜包；Edge 有聲媒體另為 2／2。119 檔逐檔核對 HTTP bytes／SHA-256；影片開場 Web Audio 能量，以及代表性 MP3 解碼／播畢另經實測。
- 正式計畫書 PDF 與 DOCX 均為 18 頁：PDF 626,645 bytes、SHA-256 `0206A96923B68FF46D11997E873517DE8A3E39858CB5F251121F99F20631E7A7`；DOCX 1,016,205 bytes、SHA-256 `1A3F2F023AFDF3C6168287F3B8B8782FCEA4D2A3D281014D46BBDBCE21B92729`。
- Round 12 正式 1080p 影片為 173.900 秒、52,590,880 bytes、SHA-256 `33D6FE8D4BF914D047023C9F82ACA4A2A6860BA278FC1A5C222BA1B7EA7C85E4`、-14.61 LUFS／-1.82 dBTP；720p 網頁預覽為 21,433,106 bytes（小於 25 MiB）、SHA-256 `0D86FAE761214CB40EBB8D7571CD1343216A901F94EA5A821C4219F5BE22BD39`、-14.62 LUFS／-1.64 dBTP。15／15 場景與 17／17 語音窗均 PASS；驗證 JSON SHA-256 `C58D348DAF87BC2B62549A8F762E96CEAEBB45AA6CEA39EBED6805B66F7ACA8C`。
- Android 三個分架構候選包只有建置、ABI 與簽章檢查證據，尚未在真機安裝或操作：arm64-v8a 44,751,023 bytes／`FDAD942D0C7877D97B7BEF08DA42180D984B0909FC05E447E9366ED12A3C2356`，armeabi-v7a 40,620,833 bytes／`70BC0161860F0A6D66F3E25B95093F11530023A96CFE216A475ACCE6B68886D4`，x86_64 47,208,618 bytes／`6F617EF166DA56B2C39DE093126A1266ACE84FACB2F84420BCE83AD39DA4044F`。
- 嚴格 IEC 內部分數維持 74／100，市場面向維持 16／30 硬上限；自動化與本機產物不能代替家庭／兒童實測、越南語母語審閱、買方與付費證據、公開 HTTPS 或人工圖像權利聲明。

網站啟動後可再執行媒體實測；它不只檢查 AAC／MP3 track 存在，還會量測影片開場 Web Audio PCM、解碼 MP3 能量，並用實際點擊讓審閱音檔播到 `ended`：

```powershell
.\scripts\test-site-media.ps1
```

正式送件前另執行外部條件：

```powershell
.\scripts\submission-gate.ps1 -RequireVideo -RequirePublicUrl -PublicUrl 'https://作品公開網址/'
```

11 張插圖成品所對應的 10 次生成技術來源鏈已封存；一般 gate 可驗證來源、轉換與成品完整性。人工權利聲明完成後，才可額外執行正式權利模式：

```powershell
.\scripts\submission-gate.ps1 -RequireImageRights
```

在聲明尚未由本人簽署前，正式權利模式應拒絕通過；不得拿公開 manifest、prompt、C2PA marker 或 SHA-256 代替權利確認。

正式送件前必須在最後一次來源同步後重跑程式與正式 MP4 閘門；公開 HTTPS、行政附件、越南語母語逐句審閱、目標家庭與導入端的第一手證據仍須真人完成，不能由自動化結果代替。

公開部署腳本預設只檢查、不發佈；必須明確加入 `-Publish` 才會更新外部 Cloudflare Pages：

```powershell
.\scripts\deploy-cloudflare-pages.ps1 -ProjectName 'chuan-jia-hua-2026'
.\scripts\deploy-cloudflare-pages.ps1 -ProjectName 'chuan-jia-hua-2026' -Publish
```

## 證據邊界

- 119 個隨包越南語 MP3 是釘選 Piper 模型產生的合成操作示範，不是家人真人原音，也不是母語審閱成果。
- 家庭錄音與資料預設留在本機；裝置聽寫或 TTS 是否連網、系統備份是否包含資料，仍依瀏覽器或作業系統設定。
- 家人圈的一次性邀請是本機手動交換與本人核准流程，不是遠端帳號、雲端同步或產品級端對端加密。
- 三筆教育資訊雖具資格、報名角色、規則與複查狀態，仍不是官方授權教材；22頁試辦包與匿名彙整台也沒有教師／家庭試辦、採用或成效證據。
- 10 次生成紀錄、完整 prompt、後製對照與 11 張成品 hash 已封存，但人工圖像權利聲明仍待有權限者本人完成，不能宣稱權利已通過。
- 自動化可證明狀態、資源路徑、音訊事件與錯誤退回，不能證明孩子看得懂、越南語自然、家庭會長期使用或市場願意付費。
