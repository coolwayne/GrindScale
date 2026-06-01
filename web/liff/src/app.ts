import { analyzeImage, fetchMeta, pingHealth } from "./api";
import { drawHistogramChart } from "./histogram";
import { closeLiffWindow, initLiff, type LiffContext } from "./liff";
import type { AnalyzeResponse, AppSettings, MetaResponse } from "./types";
import {
  AnalysisProgress,
  buildCsv,
  compressImage,
  downloadBlob,
  escapeHtml,
  formatTimeShort,
  loadHistory,
  loadSettings,
  phaseDetailText,
  pushHistory,
  saveSettings,
} from "./utils";

type Route = "splash" | "home" | "analysis" | "result" | "privacy";

interface Store {
  meta: MetaResponse | null;
  settings: AppSettings;
  liff: LiffContext | null;
  imageBlob: Blob | null;
  previewUrl: string | null;
  result: AnalyzeResponse | null;
  error: string | null;
  analyzing: boolean;
  progress: number;
  progressCtl: AnalysisProgress | null;
  apiWarming: boolean;
}

const store: Store = {
  meta: null,
  settings: loadSettings(),
  liff: null,
  imageBlob: null,
  previewUrl: null,
  result: null,
  error: null,
  analyzing: false,
  progress: 0,
  progressCtl: null,
  apiWarming: false,
};

const root = document.getElementById("app");
if (!root) throw new Error("#app missing");

function route(): Route {
  const hash = location.hash.replace(/^#\/?/, "") || "splash";
  if (hash === "home") return "home";
  if (hash === "analysis") return "analysis";
  if (hash === "result") return "result";
  if (hash === "privacy") return "privacy";
  return "splash";
}

function navigate(r: Route): void {
  location.hash = `#/${r}`;
}

function profileName(id: string): string {
  return store.meta?.brewProfiles.find((p) => p.id === id)?.name ?? id;
}

function coinName(id: string): string {
  return store.meta?.coins.find((c) => c.id === id)?.name ?? id;
}

function setPreview(blob: Blob): void {
  if (store.previewUrl) URL.revokeObjectURL(store.previewUrl);
  store.imageBlob = blob;
  store.previewUrl = URL.createObjectURL(blob);
}

async function ensureMeta(): Promise<void> {
  if (store.meta) return;
  store.meta = await fetchMeta();
}

function render(): void {
  const r = route();
  if (r === "splash") renderSplash();
  else if (r === "home") void renderHome();
  else if (r === "analysis") void renderAnalysis();
  else if (r === "privacy") renderPrivacy();
  else renderResult();
}

function renderSplash(): void {
  root!.innerHTML = `
    <div class="splash">
      <img src="/splash.svg" alt="GrindScale" onerror="this.style.display='none'" />
      <h1>GrindScale</h1>
    </div>`;
  setTimeout(() => navigate("home"), 2500);
}

async function renderHome(): Promise<void> {
  try {
    await ensureMeta();
  } catch (e) {
    root!.innerHTML = `<div class="page"><p class="banner warn">${escapeHtml(String(e))}</p></div>`;
    return;
  }

  const profiles = store.meta!.brewProfiles;
  const s = store.settings;

  root!.innerHTML = `
    <div class="page">
      ${bannerHtml()}
      <h1>選擇沖煮方式</h1>
      <p class="subtitle">依器具對應理想粒徑區間；可展開填寫豆種與設備。</p>
      <div class="grid-2">
        ${profiles
          .map(
            (p) => `
          <button type="button" class="card ${p.id === s.profileId ? "selected" : ""}" data-profile="${p.id}">
            <h3>${escapeHtml(p.name)}</h3>
            <div class="label">理想粒徑</div>
            <div class="range">${escapeHtml(p.idealRange)}</div>
          </button>`
          )
          .join("")}
      </div>
      <details class="more">
        <summary>🍃 更多選項（選填）</summary>
        <div class="field">
          <label>豆種 / 產區</label>
          <textarea id="bean" placeholder="選填，例如：衣索比亞 耶加雪菲">${escapeHtml(s.beanDescription)}</textarea>
        </div>
        <div class="field">
          <label>烘焙程度</label>
          <select id="roast">${store.meta!.roastLevels.map((r) => `<option ${r === s.roastLevel ? "selected" : ""}>${escapeHtml(r)}</option>`).join("")}</select>
        </div>
        <div class="field">
          <label>磨豆機</label>
          <input id="grinder" placeholder="選填，例如：Baratza Encore" value="${escapeHtml(s.grinderDescription)}" />
        </div>
      </details>
      <button type="button" class="btn btn-primary" id="go-analysis">進入分析</button>
      <button type="button" class="btn btn-ghost" id="skip">SKIP</button>
      <p class="subtitle" style="margin-top:4px;text-align:center">SKIP 將以「手沖咖啡」為預設沖煮方式。</p>
      <p class="subtitle" style="margin-top:12px;text-align:center">
        <a href="#/privacy" class="link-muted">隱私權政策</a>
      </p>
    </div>`;

  root!.querySelectorAll("[data-profile]").forEach((el) => {
    el.addEventListener("click", () => {
      store.settings.profileId = (el as HTMLElement).dataset.profile!;
      saveSettings(store.settings);
      render();
    });
  });

  document.getElementById("go-analysis")!.addEventListener("click", () => {
    persistHomeFields();
    navigate("analysis");
  });

  document.getElementById("skip")!.addEventListener("click", () => {
    store.settings.profileId = "v60";
    saveSettings(store.settings);
    navigate("analysis");
  });
}

function persistHomeFields(): void {
  const bean = document.getElementById("bean") as HTMLTextAreaElement | null;
  const roast = document.getElementById("roast") as HTMLSelectElement | null;
  const grinder = document.getElementById("grinder") as HTMLInputElement | null;
  if (bean) store.settings.beanDescription = bean.value;
  if (roast) store.settings.roastLevel = roast.value;
  if (grinder) store.settings.grinderDescription = grinder.value;
  saveSettings(store.settings);
}

function bannerHtml(): string {
  const parts: string[] = [];
  if (store.liff?.enabled && !store.liff.inClient) {
    parts.push("請在 LINE 內開啟此頁面以獲得最佳體驗。");
  }
  if (!store.liff?.enabled) {
    parts.push("開發模式：未設定 VITE_LIFF_ID。");
  }
  if (store.liff?.displayName) {
    parts.push(`你好，${escapeHtml(store.liff.displayName)}`);
  }
  if (parts.length === 0) return "";
  return `<div class="banner">${parts.join("<br/>")}</div>`;
}

async function renderAnalysis(): Promise<void> {
  try {
    await ensureMeta();
  } catch (e) {
    root!.innerHTML = `<div class="page"><p class="banner warn">${escapeHtml(String(e))}</p></div>`;
    return;
  }

  const s = store.settings;
  const meta = store.meta!;
  const warming = store.apiWarming;

  root!.innerHTML = `
    <div class="page">
      ${bannerHtml()}
      <div class="nav-top">
        <button type="button" class="btn btn-secondary" style="width:auto;margin:0;padding:8px 12px" id="back-home">〈 首頁</button>
        <h2>分析</h2>
        <span style="width:72px"></span>
      </div>
      <div class="summary-card">
        <div class="muted">本次沖煮設定</div>
        <div><strong>${escapeHtml(profileName(s.profileId))} · ${escapeHtml(s.roastLevel)}</strong></div>
        ${s.beanDescription ? `<div class="muted">豆種：${escapeHtml(s.beanDescription)}</div>` : ""}
        ${s.grinderDescription ? `<div class="muted">磨豆機：${escapeHtml(s.grinderDescription)}</div>` : ""}
      </div>
      <p class="subtitle">拍攝建議：只拍白紙區域，將咖啡粉與硬幣都放在同一張白紙上，避免陽光直射。</p>
      <div class="picker-card">
        <div><strong>沖煮：${escapeHtml(profileName(s.profileId))}</strong></div>
        <div class="field" style="margin-top:8px">
          <label>參照物</label>
          <select id="coin">${meta.coins.map((c) => `<option value="${c.id}" ${c.id === s.coinId ? "selected" : ""}>${escapeHtml(c.name)}</option>`).join("")}</select>
        </div>
      </div>
      <div class="row">
        <label class="btn btn-accent" style="margin:0;text-align:center">
          拍照
          <input type="file" accept="image/*" capture="environment" id="camera" hidden />
        </label>
        <label class="btn btn-secondary" style="margin:0;text-align:center">
          相簿
          <input type="file" accept="image/*" id="gallery" hidden />
        </label>
      </div>
      <div class="preview-box" id="preview">
        ${store.previewUrl ? `<img src="${store.previewUrl}" alt="preview" />` : "尚未選擇照片"}
      </div>
      <button type="button" class="btn btn-secondary" id="start-analyze" ${!store.imageBlob || store.analyzing ? "disabled" : ""}>
        開始分析
      </button>
      ${store.error ? `<p class="banner warn" style="margin-top:12px">${escapeHtml(store.error)}</p>` : ""}
      ${warming ? `<p class="banner" style="margin-top:12px">服務喚醒中，請稍候…</p>` : ""}
      <div id="history-block"></div>
    </div>
    <div id="loading-overlay" class="overlay-loading hidden"></div>`;

  document.getElementById("back-home")!.addEventListener("click", () => navigate("home"));
  document.getElementById("coin")!.addEventListener("change", (e) => {
    store.settings.coinId = (e.target as HTMLSelectElement).value;
    saveSettings(store.settings);
  });

  const onPick = async (file: File | undefined) => {
    if (!file) return;
    store.error = null;
    try {
      const maxDim = meta.limits.maxDimensionPx;
      const blob = await compressImage(file, maxDim);
      setPreview(blob);
      render();
    } catch (err) {
      store.error = String(err);
      render();
    }
  };

  document.getElementById("camera")!.addEventListener("change", (e) => {
    const input = e.target as HTMLInputElement;
    void onPick(input.files?.[0]);
  });
  document.getElementById("gallery")!.addEventListener("change", (e) => {
    const input = e.target as HTMLInputElement;
    void onPick(input.files?.[0]);
  });

  document.getElementById("start-analyze")!.addEventListener("click", () => void runAnalyze());

  renderHistoryBlock();
  void warmApi();
}

async function warmApi(): Promise<void> {
  const ok = await pingHealth();
  store.apiWarming = !ok;
  if (store.apiWarming && route() === "analysis") render();
}

function renderHistoryBlock(): void {
  const el = document.getElementById("history-block");
  if (!el) return;
  const hist = loadHistory().slice(0, 5);
  if (hist.length === 0) {
    el.innerHTML = "";
    return;
  }
  el.innerHTML = `
    <h3 style="margin-top:20px;font-size:17px">最近分析紀錄</h3>
    ${hist
      .map(
        (h) => `
      <div class="history-item">
        <span class="time">${formatTimeShort(h.timestamp)}</span>
        <span>${escapeHtml(h.profileName)}</span>
        <span class="badge">${h.mode === "calibrated" ? "校正" : "相對"}</span>
        <span>Score ${h.score}</span>
        <span>CV ${h.cv.toFixed(3)}</span>
      </div>`
      )
      .join("")}`;
}

function renderLoadingOverlay(): void {
  const overlay = document.getElementById("loading-overlay");
  if (!overlay) return;
  if (!store.analyzing) {
    overlay.classList.add("hidden");
    return;
  }
  overlay.classList.remove("hidden");
  const pct = Math.round(store.progress * 100);
  overlay.innerHTML = `
    <div class="panel">
      <div style="font-size:40px">☕</div>
      <h2>專業分析報告需要慢工出細活</h2>
      <p>${phaseDetailText(store.progress)}</p>
      <div class="progress-bar"><div style="width:${pct}%"></div></div>
      <div class="pct">${pct}%</div>
    </div>`;
}

async function runAnalyze(): Promise<void> {
  if (!store.imageBlob || store.analyzing) return;
  store.error = null;
  store.analyzing = true;
  store.progressCtl = new AnalysisProgress((p) => {
    store.progress = p;
    renderLoadingOverlay();
  });
  store.progressCtl.begin();
  render();
  renderLoadingOverlay();

  try {
    const result = await analyzeImage({
      image: store.imageBlob,
      profileId: store.settings.profileId,
      coinId: store.settings.coinId,
      roastLevel: store.settings.roastLevel,
      beanDescription: store.settings.beanDescription,
      grinderDescription: store.settings.grinderDescription,
    });
    store.progressCtl?.finish();
    await delay(400);
    store.result = result;
    pushHistory(result, profileName(store.settings.profileId));
    store.analyzing = false;
    store.progressCtl?.stop();
    navigate("result");
  } catch (e) {
    store.error = String(e);
    store.analyzing = false;
    store.progressCtl?.stop();
    store.progress = 0;
    render();
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function renderResult(): void {
  const result = store.result;
  if (!result) {
    navigate("analysis");
    return;
  }

  const s = result.stats;
  const overlaySrc = `data:image/png;base64,${result.images.overlayPngBase64}`;

  root!.innerHTML = `
    <div class="page">
      <div class="nav-top">
        <button type="button" class="btn btn-secondary" style="width:auto;margin:0;padding:8px 12px" id="back-analysis">〈 再分析</button>
        <h2>分析結果</h2>
        <span style="width:72px"></span>
      </div>
      <div class="metrics">
        ${metric("Score", String(s.uniformityScore))}
        ${metric("顆粒數", String(s.particleCount))}
        ${metric("CV", s.cv.toFixed(3))}
      </div>
      <div class="metrics">
        ${metric("細粉", `${(s.fineRatio * 100).toFixed(1)}%`)}
        ${metric("目標", `${(s.targetRatio * 100).toFixed(1)}%`)}
        ${metric("粗粉", `${(s.coarseRatio * 100).toFixed(1)}%`)}
      </div>
      <div class="metrics">
        ${metric("D10", `${s.d10.toFixed(0)} ${s.unitLabel}`)}
        ${metric("D50", `${s.d50.toFixed(0)} ${s.unitLabel}`)}
        ${metric("D90", `${s.d90.toFixed(0)} ${s.unitLabel}`)}
      </div>
      <p class="subtitle">${escapeHtml(result.calibrationText)}</p>
      <p><strong>建議：</strong>${escapeHtml(result.recommendation)}</p>
      <p class="subtitle">${escapeHtml(result.quality.text)}</p>
      ${
        result.histogram.bins.length > 0
          ? `<h3>粒徑分佈曲線（0–1000 µm）</h3>
             <div class="chart-wrap"><canvas id="hist"></canvas></div>
             <p class="subtitle">${escapeHtml(result.histogram.meta)}</p>`
          : result.histogram.meta
            ? `<p class="subtitle">${escapeHtml(result.histogram.meta)}</p>`
            : ""
      }
      ${
        result.particleDiameters.length > 0
          ? `<h3>顆粒尺寸明細</h3>
             <p class="subtitle">共辨識 ${result.particleDiameters.length} 顆</p>
             <div class="particles">${result.particleDiameters
               .map((d, i) => `<div>#${i + 1}  ${d.toFixed(1)} ${s.unitLabel}</div>`)
               .join("")}</div>`
          : ""
      }
      <h3>辨識疊圖</h3>
      <img class="overlay-img" src="${overlaySrc}" alt="overlay" />
      <p class="subtitle">藍: 細粉 / 綠: 適合 / 紅: 粗粉</p>
      <div class="row">
        <button type="button" class="btn btn-secondary" id="export-csv">匯出 Excel (CSV)</button>
        <button type="button" class="btn btn-secondary" id="save-overlay">下載辨識照片</button>
      </div>
      ${store.liff?.inClient ? `<button type="button" class="btn btn-ghost" id="close-liff">關閉</button>` : ""}
    </div>`;

  const canvas = document.getElementById("hist") as HTMLCanvasElement | null;
  if (canvas && result.histogram.bins.length > 0) {
    drawHistogramChart(canvas, result.histogram.bins);
  }

  document.getElementById("back-analysis")!.addEventListener("click", () => navigate("analysis"));
  document.getElementById("export-csv")!.addEventListener("click", () => {
    const csv = buildCsv(result, profileName(store.settings.profileId), coinName(store.settings.coinId));
    downloadBlob(new Blob([csv], { type: "text/csv;charset=utf-8" }), `GrindScale_${Date.now()}.csv`);
  });
  document.getElementById("save-overlay")!.addEventListener("click", () => {
    const a = document.createElement("a");
    a.href = overlaySrc;
    a.download = `GrindScale_overlay_${Date.now()}.png`;
    a.click();
  });
  document.getElementById("close-liff")?.addEventListener("click", () => closeLiffWindow());
}

function metric(lbl: string, val: string): string {
  return `<div class="metric"><div class="val">${escapeHtml(val)}</div><div class="lbl">${escapeHtml(lbl)}</div></div>`;
}

function renderPrivacy(): void {
  root!.innerHTML = `
    <div class="page">
      <div class="nav-top">
        <button type="button" class="btn btn-secondary" style="width:auto;margin:0;padding:8px 12px" id="privacy-back">〈 返回</button>
      </div>
      <h1>隱私權政策</h1>
      <p class="subtitle">最後更新：2026-05-29（MVP 簡版，正式上線前請依實際營運修訂）</p>
      <div class="prose">
        <h2>我們收集什麼</h2>
        <p>上傳的咖啡粉照片僅在伺服器<strong>記憶體</strong>中處理，分析完成後不儲存原圖。分析結果（統計、疊圖）回傳至你的裝置，歷史紀錄存於瀏覽器 <code>localStorage</code>，不寫入我們的資料庫。</p>
        <h2>LINE 資料</h2>
        <p>在 LINE 內開啟時，LIFF 可能提供顯示名稱等公開個人資料供介面問候；MVP 後端<strong>不要求</strong>登入，亦不綁定你的 LINE userId 至分析紀錄。</p>
        <h2>日誌</h2>
        <p>伺服器可能記錄匿名技術日誌（例如請求耗時、錯誤碼），不含照片內容。</p>
        <h2>聯絡</h2>
        <p>若有疑問，請透過官方帳號留言或專案維護者提供的聯絡方式。</p>
      </div>
    </div>`;
  document.getElementById("privacy-back")!.addEventListener("click", () => navigate("home"));
}

export async function bootstrap(): Promise<void> {
  store.liff = await initLiff();
  window.addEventListener("hashchange", () => {
    render();
    if (store.analyzing) renderLoadingOverlay();
  });

  if (!location.hash || location.hash === "#" || location.hash === "#/") {
    navigate("splash");
  } else {
    render();
  }
}
