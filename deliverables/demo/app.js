(function () {
  "use strict";

  var API_BASE = window.DAOTALK_API_BASE || "";
  var MAX_FILE_BYTES = 10 * 1024 * 1024;
  var ALLOWED_TYPES = ["image/png", "image/jpeg", "image/webp", "application/pdf"];
  var SAMPLE_TEXT = [
    "薪資明細（完全合成範例）",
    "薪資月份：2026 年 6 月",
    "本薪：新臺幣 29,500 元",
    "加班費：新臺幣 2,400 元",
    "膳宿費：新臺幣 2,500 元",
    "其他扣款：新臺幣 3,500 元",
    "實領金額：新臺幣 25,900 元",
    "備註：其他扣款原因未填寫。如有疑問，請於 2026 年 7 月 10 日前向現場管理人員確認。"
  ].join("\n");

  var state = {
    file: null,
    result: null,
    lastPayload: null,
    apiOnline: false,
    apiMode: "unknown",
    toastTimer: null,
    processingTimers: []
  };

  function byId(id) { return document.getElementById(id); }
  function all(selector) { return Array.prototype.slice.call(document.querySelectorAll(selector)); }
  function setText(id, value) {
    var node = byId(id);
    if (node) node.textContent = value == null || value === "" ? "—" : String(value);
  }
  function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }
  function asArray(value) {
    if (Array.isArray(value)) return value;
    if (value == null || value === "") return [];
    return [value];
  }
  function uniqueItems(items) {
    var seen = Object.create(null);
    return items.filter(function (item) {
      var key;
      try { key = typeof item === "string" ? "s:" + item : "o:" + JSON.stringify(item); }
      catch (error) { key = "o:" + String(item); }
      if (seen[key]) return false;
      seen[key] = true;
      return true;
    });
  }
  function safeNumber(value, fallback) {
    var number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }
  function language() {
    var checked = document.querySelector("input[name='language']:checked");
    return checked ? checked.value : "vi";
  }
  function languageName(code) {
    return { vi: "Tiếng Việt", id: "Bahasa Indonesia", en: "English", "zh-TW": "繁體中文" }[code] || code;
  }
  function humanBytes(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / 1024 / 1024).toFixed(1) + " MB";
  }
  function showToast(message, warning) {
    var toast = byId("toast");
    window.clearTimeout(state.toastTimer);
    toast.textContent = message;
    toast.style.background = warning ? "#80392b" : "#102826";
    toast.hidden = false;
    state.toastTimer = window.setTimeout(function () { toast.hidden = true; }, 3500);
  }
  function showInputMessage(message) {
    var box = byId("input-message");
    box.textContent = message;
    box.hidden = !message;
  }

  async function checkHealth() {
    var pill = byId("api-pill");
    try {
      var response = await fetch(API_BASE + "/healthz", { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error("health " + response.status);
      var data = await response.json();
      state.apiOnline = true;
      state.apiMode = data.mode === "live" || data.provider === "openai" || data.live_ready ? "live" : "mock";
      pill.classList.add("online");
      pill.classList.remove("offline");
      var serviceLabel = state.apiMode === "live" ? "AI 服務可用" : "展示服務可用";
      setText("api-label", serviceLabel);
      pill.setAttribute("aria-label", "後端連線狀態：" + serviceLabel);
    } catch (error) {
      state.apiOnline = false;
      state.apiMode = "offline";
      pill.classList.add("offline");
      pill.classList.remove("online");
      setText("api-label", "後端尚未啟動");
      pill.setAttribute("aria-label", "後端連線狀態：後端尚未啟動");
    }
  }

  function updateAnalyzeState() {
    var hasInput = Boolean(state.file || byId("document-text").value.trim());
    byId("analyze").disabled = !(hasInput && byId("consent").checked);
  }

  function acceptFile(file) {
    showInputMessage("");
    if (!file) return;
    if (!ALLOWED_TYPES.includes(file.type)) {
      showInputMessage("目前只接受 PNG、JPG、WEBP 或 PDF。請改用支援的格式。");
      return;
    }
    if (file.size > MAX_FILE_BYTES) {
      showInputMessage("檔案超過 10 MB。請壓縮、裁切或只上傳需要理解的頁面。");
      return;
    }
    state.file = file;
    byId("file-name").textContent = file.name;
    byId("file-meta").textContent = humanBytes(file.size) + " · 僅供本輪分析";
    byId("file-kind").textContent = file.type === "application/pdf" ? "PDF" : "IMG";
    byId("file-chip").hidden = false;
    byId("drop-zone").hidden = true;
    byId("document-text").value = "";
    setText("text-count", "0");
    updateAnalyzeState();
  }

  function removeFile() {
    state.file = null;
    byId("document-file").value = "";
    byId("file-chip").hidden = true;
    byId("drop-zone").hidden = false;
    updateAnalyzeState();
  }

  function selectPanel(name) {
    ["input", "processing", "result"].forEach(function (key) {
      var panel = byId(key + "-panel");
      var selected = key === name;
      panel.hidden = !selected;
      panel.classList.toggle("active", selected);
    });
    var step = name === "input" ? 1 : name === "processing" ? 3 : 4;
    all(".step").forEach(function (item) {
      var itemStep = Number(item.getAttribute("data-step"));
      item.classList.toggle("active", itemStep === step);
      item.classList.toggle("complete", itemStep < step);
    });
    setText("mode-label", name === "input" ? "等待文件" : name === "processing" ? "文件處理中" : "結果可核對");
  }

  function startPipeline() {
    state.processingTimers.forEach(window.clearTimeout);
    state.processingTimers = [];
    var items = all("#pipeline li");
    items.forEach(function (item, index) {
      item.classList.toggle("running", index === 0);
      item.classList.remove("complete");
    });
    [420, 980, 1580].forEach(function (delay, nextIndex) {
      state.processingTimers.push(window.setTimeout(function () {
        items.forEach(function (item, index) {
          item.classList.toggle("complete", index <= nextIndex);
          item.classList.toggle("running", index === nextIndex + 1);
        });
      }, delay));
    });
  }

  function finishPipeline() {
    state.processingTimers.forEach(window.clearTimeout);
    state.processingTimers = [];
    all("#pipeline li").forEach(function (item) {
      item.classList.remove("running");
      item.classList.add("complete");
    });
  }

  function fallbackSample() {
    var lang = language();
    var translations = {
      vi: "Có một khoản khấu trừ 3.500 Đài tệ chưa ghi rõ lý do. Hãy giữ phiếu lương và hỏi rõ nội dung trước.",
      id: "Ada potongan NT$3.500 tanpa alasan yang jelas. Simpan slip gaji dan tanyakan rinciannya terlebih dahulu.",
      en: "There is an unexplained NT$3,500 deduction. Keep the payslip and ask for the itemized reason first.",
      "zh-TW": "薪資明細中有一筆 3,500 元的其他扣款，原因未填寫；請保留文件並先詢問明細。"
    };
    var questions = {
      vi: "Xin vui lòng cho tôi biết khoản khấu trừ 3.500 Đài tệ này là gì và cung cấp bảng chi tiết.",
      id: "Mohon jelaskan potongan NT$3.500 ini dan berikan rincian tertulisnya.",
      en: "Please explain the NT$3,500 deduction and provide the written itemization.",
      "zh-TW": "請問這筆 3,500 元扣款的項目與依據是什麼？可以提供書面明細嗎？"
    };
    return {
      request_id: "fixture-" + Date.now().toString(36),
      case_id: "ui-synthetic-payslip-001",
      mode: "frontend_fixture",
      model: "未呼叫模型",
      result: {
        document_type: "salary_statement",
        summary: "薪資明細中有一筆 3,500 元的其他扣款，原因未填寫；請保留文件並先詢問明細。",
        summary_zh: "薪資明細中有一筆 3,500 元的其他扣款，原因未填寫；請保留文件並先詢問明細。",
        summary_target: translations[lang],
        target_language: lang,
        dates: [{ label: "詢問期限", value: "2026-07-10", evidence: "請於 2026 年 7 月 10 日前向現場管理人員確認" }],
        times: [],
        amounts: [
          { label: "本薪", value: "29,500", currency: "TWD", evidence: "本薪：新臺幣 29,500 元" },
          { label: "加班費", value: "2,400", currency: "TWD", evidence: "加班費：新臺幣 2,400 元" },
          { label: "其他扣款", value: "3,500", currency: "TWD", evidence: "其他扣款：新臺幣 3,500 元" },
          { label: "實領金額", value: "25,900", currency: "TWD", evidence: "實領金額：新臺幣 25,900 元" }
        ],
        questions_to_confirm: ["請問這筆 3,500 元扣款的項目與依據是什麼？可以提供書面明細嗎？"],
        bilingual_questions: [{ target: questions[lang], zh: "請問這筆 3,500 元扣款的項目與依據是什麼？可以提供書面明細嗎？", purpose: "確認原因不明扣款" }],
        next_steps: [
          "保留薪資明細與入帳紀錄，不要先刪除或交出正本。",
          "向雇主詢問 3,500 元扣款的項目、期間與書面依據。",
          "如果仍無法說明，帶著文件聯絡 1955 專線尋求真人協助。"
        ],
        risks: [{ category: "原因不明扣款", severity: "high", evidence: "其他扣款：新臺幣 3,500 元；原因未填寫", explanation: "文件缺少扣款原因，系統不能據此判定是否合法。" }],
        confidence: { overall: 0, fields: {} },
        referral: { needed: true, service: "1955", reason: "涉及原因不明扣款，若無法取得說明，建議由真人協助。" },
        data_processing: { stored: false, local_retention: "none", provider: "browser fixture", input_type: "text" }
      },
      warnings: ["這是瀏覽器內建的合成備援結果，未呼叫 AI；啟動後端後可驗證完整 API 流程。"],
      refusal: false,
      latency_ms: 0
    };
  }

  async function callApi(options) {
    var url = API_BASE + "/api/analyze";
    if (options.sample) {
      return fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({
          text: SAMPLE_TEXT,
          document_type_hint: "salary_statement",
          preferred_language: language(),
          case_id: "ui-synthetic-payslip-001",
          consent: true,
          demo_mode: true
        })
      });
    }
    var form = new FormData();
    if (state.file) form.append("file", state.file, state.file.name);
    else form.append("text", byId("document-text").value.trim());
    form.append("preferred_language", language());
    form.append("consent", "true");
    form.append("demo_mode", "false");
    form.append("case_id", "web-" + Date.now().toString(36));
    return fetch(url, { method: "POST", headers: { Accept: "application/json" }, body: form });
  }

  async function analyze(options) {
    options = options || {};
    showInputMessage("");
    if (!options.sample) {
      if (!state.file && !byId("document-text").value.trim()) {
        showInputMessage("請先選擇檔案或貼上文件文字。");
        return;
      }
      if (!byId("consent").checked) {
        showInputMessage("請先確認隱私提醒與本次分析同意。");
        return;
      }
    }
    var ruleDemo = Boolean(options.sample || state.apiMode === "mock");
    setText("processing-title", ruleDemo ? "正在執行可重現的規則展示" : "正在把文件整理成可核對的行動卡");
    setText("processing-note", ruleDemo ? "本流程不呼叫 AI；圖片與 PDF 只驗證格式，不會假裝已辨識內容。" : "文件不會顯示在公開頁面。");
    selectPanel("processing");
    startPipeline();
    var started = performance.now();
    var minimumDelay = new Promise(function (resolve) { window.setTimeout(resolve, 1900); });
    try {
      var response = await callApi(options);
      var payload;
      try { payload = await response.json(); } catch (jsonError) { payload = null; }
      if (!response.ok) {
        var detail = payload && (payload.detail || payload.message || (payload.error && payload.error.message) || payload.error);
        throw new Error(typeof detail === "string" ? detail : "分析服務回傳錯誤（" + response.status + "）");
      }
      await minimumDelay;
      payload.latency_ms = payload.latency_ms || Math.round(performance.now() - started);
      state.result = payload;
      state.lastPayload = payload;
      finishPipeline();
      renderResult(payload);
      selectPanel("result");
    } catch (error) {
      await minimumDelay;
      if (options.sample) {
        var fixture = fallbackSample();
        state.result = fixture;
        state.lastPayload = fixture;
        finishPipeline();
        renderResult(fixture);
        selectPanel("result");
        showToast("後端未連線，已改用清楚標示的合成介面備援；這不是 AI 結果。", true);
      } else {
        selectPanel("input");
        showInputMessage(error.message || "目前無法連上分析服務。請確認後端已啟動後再試一次。");
      }
    }
  }

  function normalizeFields(payload) {
    var result = payload.result || {};
    var fields = [];
    function add(label, value, evidence, confidence) {
      if (value == null || value === "") return;
      fields.push({ label: label || "欄位", value: String(value), evidence: evidence || "未提供原文片段，請查看完整文件。", confidence: confidence });
    }
    add("文件類型", documentTypeName(result.document_type), result.document_type_evidence, result.confidence && result.confidence.fields && result.confidence.fields.document_type);
    asArray(result.dates).forEach(function (item) {
      if (typeof item === "string") add("日期", item);
      else add(item.label || "日期", item.value || item.date, item.evidence || item.quote, item.confidence);
    });
    asArray(result.times).forEach(function (item) {
      if (typeof item === "string") add("時間", item);
      else add(item.label || "時間", item.value || item.time, item.evidence || item.quote, item.confidence);
    });
    asArray(result.amounts).forEach(function (item) {
      if (typeof item === "string") add("金額", item);
      else {
        var value = item.value || item.amount;
        if (value != null && item.currency && !/(?:TWD|NTD|NT\$|新[臺台]幣|元)/i.test(String(value))) value = item.currency + " " + value;
        add(item.label || "金額", value, item.evidence || item.quote, item.confidence);
      }
    });
    if (!fields.length) {
      asArray(payload.fields).forEach(function (item) {
        if (typeof item === "string") add("欄位", item);
        else add(item.label || item.field, item.value, item.evidence || item.quote, item.confidence);
      });
    }
    return fields;
  }

  function confidenceLabel(value) {
    if (value == null) return "待核對";
    var number = safeNumber(value, 0);
    if (number > 1) number = number / 100;
    if (number >= .85) return "高信心";
    if (number >= .65) return "中信心";
    return "低信心";
  }

  function getSummary(result) {
    if (result.summary_target || result.summary_zh) {
      return {
        target: result.summary_target || result.summary || result.summary_zh,
        zh: result.summary_zh || result.summary || result.summary_target
      };
    }
    if (typeof result.summary === "string") return { target: result.summary, zh: result.summary_zh || result.summary };
    if (result.summary && typeof result.summary === "object") {
      return {
        target: result.summary.target || result.summary.translated || result.summary[language()] || result.summary.zh || "—",
        zh: result.summary.zh || result.summary["zh-TW"] || result.summary.chinese || result.summary.target || "—"
      };
    }
    return { target: "請逐項查看下方欄位與原文證據。", zh: "請逐項查看下方欄位與原文證據。" };
  }

  function documentTypeName(value) {
    return {
      salary_statement: "薪資明細",
      work_schedule: "班表或排班通知",
      employment_contract: "聘僱契約",
      employer_notice: "雇主通知",
      attendance_record: "出勤紀錄",
      government_or_residence_document: "政府或居留文件",
      other: "其他職場文件",
      unknown: "尚未分類的文件"
    }[value] || value;
  }

  function getQuestion(result) {
    var first = asArray(result.bilingual_questions)[0] || asArray(result.questions_to_confirm)[0];
    if (!first) return { target: "我想確認這份文件的內容，可以請您用簡單的方式說明嗎？", zh: "我想確認這份文件的內容，可以請您用簡單的方式說明嗎？" };
    if (typeof first === "string") return { target: first, zh: first };
    return {
      target: first.target || first.translation || first[language()] || first.question || first.zh || "—",
      zh: first.zh || first["zh-TW"] || first.chinese || first.question_zh || first.question || "—"
    };
  }

  function renderResult(payload) {
    var result = payload.result || {};
    var mode = String(payload.mode || "unknown");
    var live = mode === "live" || mode === "openai" || mode === "production";
    var fixture = mode === "frontend_fixture";
    var mock = mode === "mock";
    setText("provider-badge", live ? "多模態 AI 即時分析" : fixture ? "前端合成備援 · 非 AI" : mock ? "可重現規則展示 · 非 AI" : "未識別分析模式");
    setText("result-subtitle", live ? "每個欄位都能回到原文核對。" : "展示結果來自確定性規則，不是模型判讀；仍可回到原文核對。");
    setText("fields-title", live ? "AI 找到的關鍵欄位" : "規則擷取的關鍵欄位");

    var risks = uniqueItems(asArray(result.risks).concat(asArray(payload.risk_flags)));
    var highRisk = risks.some(function (risk) {
      var severity = typeof risk === "object" ? risk.severity : String(risk);
      return /high|critical|高|嚴重/i.test(String(severity));
    }) || Boolean(result.referral && result.referral.needed);
    setText("risk-badge", highRisk ? "高風險 · 建議真人" : "一般核對");

    var rawOverall = result.confidence && typeof result.confidence === "object" ? result.confidence.overall : result.confidence;
    if (fixture || rawOverall == null || !Number.isFinite(Number(rawOverall))) {
      setText("overall-confidence", "—");
      setText("confidence-caption", fixture ? "非 AI 結果" : "信心未提供");
      byId("confidence-ring").style.setProperty("--confidence", "0%");
      byId("confidence-ring").setAttribute("aria-label", fixture ? "合成備援不提供 AI 信心" : "輸出信心尚未提供");
    } else {
      var overall = Number(rawOverall);
      if (overall > 1) overall = overall / 100;
      overall = clamp(overall, 0, 1);
      var percent = Math.round(overall * 100);
      setText("overall-confidence", percent + "%");
      setText("confidence-caption", live ? "模型信心" : "規則擷取信心");
      byId("confidence-ring").style.setProperty("--confidence", percent + "%");
      byId("confidence-ring").setAttribute("aria-label", (live ? "模型信心 " : "規則擷取信心 ") + percent + "%");
    }

    var summary = getSummary(result);
    setText("summary-title", result.document_type ? "這是一份「" + documentTypeName(result.document_type) + "」" : "這份文件需要逐項核對");
    setText("summary-target", summary.target);
    byId("summary-target").setAttribute("lang", language());
    setText("summary-zh", summary.zh);

    var fieldList = byId("field-list");
    fieldList.replaceChildren();
    var fields = normalizeFields(payload);
    if (!fields.length) fields = [{ label: "沒有可靠欄位", value: "請重新拍攝或改由真人查看", evidence: "系統未取得足以核對的內容。", confidence: 0 }];
    fields.forEach(function (field) {
      var article = document.createElement("article");
      article.className = "field-item";
      var top = document.createElement("div"); top.className = "field-top";
      var label = document.createElement("span"); label.textContent = field.label;
      var confidence = document.createElement("em"); confidence.textContent = confidenceLabel(field.confidence);
      top.append(label, confidence);
      var value = document.createElement("strong"); value.textContent = field.value;
      var details = document.createElement("details");
      var summaryNode = document.createElement("summary"); summaryNode.textContent = "查看原文證據";
      var quote = document.createElement("blockquote"); quote.textContent = field.evidence;
      details.append(summaryNode, quote);
      article.append(top, value, details);
      fieldList.appendChild(article);
    });

    var actionList = byId("action-list");
    actionList.replaceChildren();
    var actions = uniqueItems(asArray(result.next_steps).concat(asArray(payload.action)));
    if (!actions.length) actions = ["先逐項對照文件原文。", "有不確定的地方，帶著原文件詢問真人。"];
    actions.slice(0, 6).forEach(function (action) {
      var label = typeof action === "string" ? action : action.action || action.title || action.step || JSON.stringify(action);
      var note = typeof action === "object" ? action.reason || action.note || action.detail : "完成後再進行下一步";
      var li = document.createElement("li");
      var b = document.createElement("b"); b.textContent = label;
      var small = document.createElement("small"); small.textContent = note;
      li.append(b, small); actionList.appendChild(li);
    });

    var question = getQuestion(result);
    setText("question-language", languageName(language()) + " 詢問句");
    setText("question-target", question.target);
    byId("question-target").setAttribute("lang", language());
    setText("question-zh", question.zh);

    var riskCard = byId("risk-card");
    riskCard.classList.toggle("low-risk", !highRisk);
    setText("risk-title", highRisk ? "先停下來，請真人確認" : "目前未見高風險訊號");
    var firstRisk = risks[0];
    var reason = firstRisk && typeof firstRisk === "object" ? firstRisk.explanation || firstRisk.reason || firstRisk.category : firstRisk;
    if (!reason && result.referral) reason = result.referral.reason;
    setText("risk-reason", reason || "仍請逐項對照原文；沒有風險標記不代表文件一定沒有問題。");
    var warnings = asArray(payload.warnings).slice();
    risks.slice(0, 3).forEach(function (risk) {
      if (risk && typeof risk === "object" && risk.evidence) warnings.push("證據：" + risk.evidence);
    });
    warnings = uniqueItems(warnings);
    var warningList = byId("warning-list"); warningList.replaceChildren();
    (warnings.length ? warnings : ["輸出信心不是正確率，重要內容仍需人工核對。"] ).slice(0, 5).forEach(function (warning) {
      var li = document.createElement("li"); li.textContent = typeof warning === "string" ? warning : JSON.stringify(warning); warningList.appendChild(li);
    });

    var processing = result.data_processing || payload.data_processing || {};
    setText("trace-provider", fixture ? "瀏覽器合成 fixture" : live ? "OpenAI Responses API" : processing.provider || mode);
    setText("trace-model", payload.model || processing.model || "未提供");
    setText("trace-schema", payload.schema_version || result.schema_version || "Pydantic validated");
    setText("trace-latency", payload.latency_ms != null ? payload.latency_ms + " ms" : "未提供");
    setText("trace-request", payload.request_id || "未提供");
  }

  function copyQuestion() {
    var value = byId("question-target").textContent + "\n\n中文：" + byId("question-zh").textContent;
    function success() { showToast("雙語詢問句已複製；傳送前請再核對內容。", false); }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(value).then(success).catch(function () { legacyCopy(value, success); });
    } else legacyCopy(value, success);
  }

  function legacyCopy(value, callback) {
    var area = document.createElement("textarea");
    area.value = value; area.setAttribute("readonly", "");
    area.style.position = "fixed"; area.style.opacity = "0";
    document.body.appendChild(area); area.select();
    try { document.execCommand("copy"); callback(); } catch (error) { showToast("無法自動複製，請手動選取文字。", true); }
    area.remove();
  }

  function downloadJson() {
    if (!state.lastPayload) return;
    var blob = new Blob([JSON.stringify(state.lastPayload, null, 2)], { type: "application/json;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url; link.download = "daotalk-analysis-" + (state.lastPayload.request_id || "result") + ".json";
    document.body.appendChild(link); link.click(); link.remove();
    window.setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function reset() {
    removeFile();
    byId("document-text").value = "";
    byId("consent").checked = false;
    setText("text-count", "0");
    state.result = null; state.lastPayload = null;
    showInputMessage(""); updateAnalyzeState(); selectPanel("input");
  }

  function initialize() {
    checkHealth();
    byId("choose-file").addEventListener("click", function () { byId("document-file").click(); });
    byId("document-file").addEventListener("change", function (event) { acceptFile(event.target.files[0]); });
    byId("remove-file").addEventListener("click", removeFile);
    byId("document-text").addEventListener("input", function (event) {
      if (event.target.value.trim() && state.file) removeFile();
      setText("text-count", event.target.value.length);
      updateAnalyzeState();
    });
    byId("consent").addEventListener("change", updateAnalyzeState);
    byId("analyze").addEventListener("click", function () { analyze({ sample: false }); });
    byId("load-sample").addEventListener("click", function () {
      byId("consent").checked = true;
      analyze({ sample: true });
    });
    byId("reset").addEventListener("click", reset);
    byId("analyze-another").addEventListener("click", reset);
    byId("copy-question").addEventListener("click", copyQuestion);
    byId("download-json").addEventListener("click", downloadJson);

    var drop = byId("drop-zone");
    ["dragenter", "dragover"].forEach(function (name) {
      drop.addEventListener(name, function (event) { event.preventDefault(); drop.classList.add("dragging"); });
    });
    ["dragleave", "drop"].forEach(function (name) {
      drop.addEventListener(name, function (event) { event.preventDefault(); drop.classList.remove("dragging"); });
    });
    drop.addEventListener("drop", function (event) { acceptFile(event.dataTransfer.files[0]); });

    var dialog = byId("tech-dialog");
    byId("open-tech").addEventListener("click", function () { dialog.showModal(); });
    byId("close-tech").addEventListener("click", function () { dialog.close(); });
    dialog.addEventListener("click", function (event) {
      var rect = dialog.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", initialize);
  else initialize();
}());
