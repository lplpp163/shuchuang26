# 島語通 DaoTalk AI｜團隊成果網站

這個儲存庫是組員查看最新成果的靜態網站。首頁以專案根目錄的 `交付成果/README.md` 為最新索引，並把需要在 GitHub Pages 瀏覽的檔案鏡像到本儲存庫。

## 直接瀏覽

- 首頁：`index.html`
- 最新計畫書：`deliverables/plan/DaoTalk-AI-plan.pdf`
- 正式互動 Demo：`deliverables/demo/index.html`
- 3 分 20 秒正式動畫：`deliverables/video/index.html`
- 訪談素材：`deliverables/interview/index.html`
- 同步來源與 SHA-256：`deliverables/manifest.json`

正式 Demo 放在 GitHub Pages 時，可以操作清楚標示的合成範例與前端備援。自訂圖片、PDF 或文字的 live AI 分析仍需啟動 `正式版/backend`，不可把 Pages 版本描述成已部署完整 AI 後端。

## 更新最新交付成果

在這個儲存庫目錄執行：

```powershell
.\scripts\sync-deliverables.ps1
```

腳本會從同層專案的 `交付成果/` 與 `正式版/` 複製 22 個指定成果，驗證來源與鏡像的 SHA-256，並重建 `deliverables/manifest.json`。執行後請檢查首頁、Demo、影片與所有本機連結，再提交 Git。

## 版本界線

- `deliverables/`：目前最新的可瀏覽成果鏡像。
- `archive/2026-07-07/`：早期「移工／新住民多語生活導航」提案頁與三份草稿，只供追溯決策歷程。
- `開會簡報.html`：保留舊網址，會導向目前首頁。

最新版本聚焦「在臺移工的職場文件 AI 行動導航」。求職媒合、醫療、租屋與未驗證的機構採購不屬於目前 MVP。

## 發布

GitHub Pages 應使用 `main` 分支的儲存庫根目錄。所有站內資產都使用相對路徑，可部署在 `/shuchuang26/` 專案子路徑。
