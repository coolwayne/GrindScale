import type { AnalyzeResponse, AppSettings, HistoryRecord } from "./types";

const HISTORY_KEY = "grindscale.analysis.history";
const SETTINGS_KEY = "grindscale.settings";
const MAX_HISTORY = 30;

const DEFAULT_SETTINGS: AppSettings = {
  profileId: "v60",
  coinId: "none",
  roastLevel: "中焙",
  beanDescription: "",
  grinderDescription: "",
};

export function loadSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettings(s: AppSettings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(s));
}

export function loadHistory(): HistoryRecord[] {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    if (!raw) return [];
    const arr = JSON.parse(raw) as HistoryRecord[];
    return Array.isArray(arr) ? arr : [];
  } catch {
    return [];
  }
}

export function pushHistory(result: AnalyzeResponse, profileName: string): void {
  const records = loadHistory();
  records.unshift({
    id: result.analysisId,
    timestamp: Date.now(),
    profileName,
    mode: result.stats.mode,
    score: result.stats.uniformityScore,
    particleCount: result.stats.particleCount,
    cv: result.stats.cv,
  });
  localStorage.setItem(HISTORY_KEY, JSON.stringify(records.slice(0, MAX_HISTORY)));
}

export function formatTimeShort(ts: number): string {
  return new Date(ts).toLocaleTimeString(undefined, {
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export async function compressImage(file: File, maxDim: number, quality = 0.85): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxDim / Math.max(bitmap.width, bitmap.height));
  const w = Math.max(1, Math.round(bitmap.width * scale));
  const h = Math.max(1, Math.round(bitmap.height * scale));
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  if (!ctx) return file;
  ctx.drawImage(bitmap, 0, 0, w, h);
  bitmap.close();
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (b) => (b ? resolve(b) : reject(new Error("壓縮失敗"))),
      "image/jpeg",
      quality
    );
  });
}

export function buildCsv(result: AnalyzeResponse, profileName: string, coinName: string): string {
  const s = result.stats;
  const lines = [
    "咖啡粉粒徑分析報告,GrindScale",
    `產生時間,${new Date().toLocaleString("zh-TW")}`,
    `器具,${profileName}`,
    `參照物,${coinName}`,
    `校正說明,${result.calibrationText}`,
    "",
    "顆粒數,Score,CV,細粉%,目標%,粗粉%",
    `${s.particleCount},${s.uniformityScore},${s.cv.toFixed(4)},${(s.fineRatio * 100).toFixed(1)},${(s.targetRatio * 100).toFixed(1)},${(s.coarseRatio * 100).toFixed(1)}`,
    "",
    "建議",
    result.recommendation,
    "",
    "粒徑列表",
    ...result.particleDiameters.map((d, i) => `${i + 1},${d.toFixed(2)} ${s.unitLabel}`),
  ];
  return "\uFEFF" + lines.join("\r\n");
}

export function downloadBlob(blob: Blob, filename: string): void {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

export class AnalysisProgress {
  private timer: ReturnType<typeof setInterval> | null = null;
  private startedAt = 0;
  private readonly targetSec = 240;

  constructor(private onTick: (p: number) => void) {}

  begin(): void {
    this.stop();
    this.startedAt = Date.now();
    this.onTick(0.02);
    this.timer = setInterval(() => {
      const elapsed = (Date.now() - this.startedAt) / 1000;
      const linear = elapsed / this.targetSec;
      let p: number;
      if (linear <= 0.92) {
        p = Math.min(0.92, Math.max(0.02, linear));
      } else {
        const overrun = elapsed - this.targetSec * 0.92;
        p = Math.min(0.99, 0.92 + Math.min(0.07, overrun / 2000));
      }
      this.onTick(p);
    }, 250);
  }

  finish(): void {
    this.stop();
    this.onTick(1);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}

export function phaseDetailText(progress: number): string {
  if (progress <= 0.15) return "正在喚醒分析伺服器（免費方案可能需 1 分鐘）";
  if (progress <= 0.3) return "正在辨識顆粒並計算粒徑分布（請勿關閉頁面）";
  if (progress <= 0.7) return "正在分析數據";
  return "正在撰寫Excel跟專業報告";
}
