# 場景插圖完整性與公開來源摘要

本目錄的 11 個場景圖是本原型開發期間由團隊以生成式影像工具製作、挑選並裁切／壓縮的合成插圖，不是實拍照片、圖庫素材、受訪家庭影像或真實使用者證言。已追回並封存 10 次生成紀錄；`family-meal-lesson.png` 與其 WebP 版本共用同一張原始輸出，所以 10 次生成對應 11 張成品。此生成鏈的 reference images 都是同鏈較早產出的插圖，不含第三方或家庭照片。App 不會在執行時即時生成圖片，也不會把家庭照片拿來訓練模型。

公開技術紀錄在 `provenance_manifest.json`；內部匿名化證據包在 `競賽資料/權利證據/生成式插圖/`，包含 10 張原始 PNG、完整 prompts、逐次 records、UTC、reference lineage 與後製紀錄。原始 PNG 內可檢出 `OpenAI Media Service API`、`gpt-image` `2.0` 及 `trainedAlgorithmicMedia` 等 C2PA claim markers，但尚未以 `c2patool` 完成密碼學簽章驗證，不得寫成「C2PA 已驗證」。

這些技術紀錄不等於使用授權。正式送件仍須由有權限的人確認帳號權限、所有輸入權利、適用服務條款、主辦規章以及競賽／商業原型使用，並另行完成 hash 綁定的人工 attestation；系統不會代填或推定。

| 檔案 | bytes | SHA-256 |
|---|---:|---|
| `family-bedtime-theater-v1.png` | 2010515 | `9BBEB732FCAC790E7EE7384A18715174705872F63F865C2DED370F87614283D1` |
| `family-garden-theater-v1.png` | 2204040 | `8943686DD50A330DE5B874861B843359CA349D3ABDB0ED643AA27C41C8F03054` |
| `family-homecoming-game-v1.webp` | 152872 | `A4E5022337E6E7FB2BB75E36A0CBB3EE07DE88EDA471E63CFF43125B895FE2F3` |
| `family-homecoming-theater-v2.png` | 2071447 | `91C58B71D436F6681DC908AB1BA1E38C658A96A7A192BC9FC844220E81C2BAE1` |
| `family-kitchen-game-v2.webp` | 172488 | `62DDA9C1D1C8788573175847161C0437796F2815D04C8E4DF854CCF51A691D36` |
| `family-meal-lesson.png` | 2503761 | `4D93170DC0C216743D4C9103D120D9557DC4869BCCE6D67D861DA26FCC3EB2F7` |
| `family-meal-lesson.webp` | 120778 | `50085BB1B4BF5319F892BEBFAB78382BE120F6CFD5C8A2D8F7359DE16A34A792` |
| `family-mealtime-game-v1.webp` | 206280 | `0A382B82344CBA09EBB79DBA8F65F0376781F509BA19781FD516C4BF589868B5` |
| `family-mealtime-theater-v2.png` | 2091643 | `DD532767916199490BDC15A079FA402B7C7A75D5B04B4DD20D3085BF29875B95` |
| `family-morning-game-v1.webp` | 140222 | `20A192047B36FB9675A9C3100CEED0DC80CC8C59FB45EA522EA31F08DB82C33F` |
| `family-stage-duo-v1.png` | 614884 | `9881463BA16E2F2638AC0AEB4A09F600453BC7C577A87FD2E60ABB0626912AF4` |

這些雜湊只證明目前交付檔案未漂移；來源 manifest 與 C2PA markers 也不代表已取得權利，或語言、文化姿態與服飾已經真人審閱。涉及越南家庭文化的畫面仍應與母語／文化顧問一起檢查。
