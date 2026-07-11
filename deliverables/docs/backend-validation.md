# 島語通 DaoTalk AI 後端驗證紀錄

驗證日期：2026-07-11（Asia/Taipei）

## 已完成

- `python -m pytest --cov=app --cov-report=term-missing`
  - 28 passed
  - 總程式涵蓋率 87%
- `python scripts/run_synthetic_validation.py`
  - 模式：deterministic mock
  - 文件類型：`salary_statement`
  - 日期：2 筆
  - 金額：4 筆
  - 本地風險：`wage_or_deduction`
  - 轉介：`needed=true`，1955
  - 本地保存：`stored=false`
- 同源 smoke test
  - `/`：200，成功讀取 `正式版/frontend/index.html`
  - `/healthz`：200
  - `/api/analyze`：200
  - 以真實 Uvicorn HTTP server 執行，不只使用 TestClient

測試涵蓋 JSON、multipart、text/plain、TXT、PNG、PDF、錯誤 MIME／magic bytes、PDF 頁數、過長文字、request ID、四位中文年份回歸、語言參數防提示注入、文件內提示注入拒絕、PII 遞迴遮罩、12 個穩定風險細碼、live consent、demo mode、雙語欄位、風險分流、Python 3.8 async adapter 及錯誤格式。

OpenAI adapter 的離線單元測試已確認：

- 影像使用 base64 `input_image` 且 `detail=high`。
- PDF 使用 base64 `input_file` 且 `detail=high`。
- 呼叫 `responses.parse`，`text_format=DocumentAnalysis`。
- `store=false`。
- strict schema 所有 object 均為 `additionalProperties=false`。

## 尚未宣稱完成

目前環境沒有 `OPENAI_API_KEY`，因此尚未向 OpenAI 發出真實請求。下列項目必須在取得競賽專用金鑰後才可標成「實測」：

- `gpt-5.6-terra` 是否已對該 API 專案開放。
- 真實手機照片、掃描 PDF 與複雜薪資單的欄位正確率。
- 繁中／越南文／印尼文／英文的忠實度與母語審閱結果。
- 高風險 recall、誤報率、拒答與 prompt-injection 表現。
- P50／P95 延遲、每頁 token 與單件成本。

正式評測時應固定資料集與 expected JSON，至少分成薪資明細、班表、出勤、雇主通知、契約與高風險案例；評分需同時檢查欄位、原文 evidence、風險、轉介與「不確定時不猜」。
