import type { AnalyzeResponse, ApiError, MetaResponse } from "./types";

const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined)?.replace(/\/$/, "") ?? "";

function url(path: string): string {
  return `${API_BASE}${path}`;
}

const ANALYZE_TIMEOUT_MS = 600_000;

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** Free Render may sleep ~60s; poll until API responds. */
export async function waitForApiReady(maxWaitMs = 120_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    if (await pingHealth()) return;
    await delay(2000);
  }
  throw new Error("分析伺服器喚醒逾時，請 30 秒後再按「開始分析」。");
}

async function fetchWithTimeout(input: string, init: RequestInit = {}): Promise<Response> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ANALYZE_TIMEOUT_MS);
  try {
    return await fetch(input, { ...init, signal: ctrl.signal });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error("分析逾時（超過 10 分鐘），請縮小照片或稍後重試。");
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

async function parseError(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as ApiError;
    if (body?.error?.message) return body.error.message;
  } catch {
    /* ignore */
  }
  return `請求失敗（${res.status}）`;
}

export async function fetchMeta(): Promise<MetaResponse> {
  const res = await fetchWithTimeout(url("/v1/meta"));
  if (!res.ok) throw new Error(await parseError(res));
  return res.json() as Promise<MetaResponse>;
}

export interface AnalyzeParams {
  image: Blob;
  profileId: string;
  coinId: string;
  roastLevel?: string;
  beanDescription?: string;
  grinderDescription?: string;
}

export async function analyzeImage(params: AnalyzeParams): Promise<AnalyzeResponse> {
  const form = new FormData();
  form.append("image", params.image, "capture.jpg");
  form.append("profileId", params.profileId);
  form.append("coinId", params.coinId);
  if (params.roastLevel) form.append("roastLevel", params.roastLevel);
  if (params.beanDescription) form.append("beanDescription", params.beanDescription);
  if (params.grinderDescription) form.append("grinderDescription", params.grinderDescription);

  let lastErr: unknown;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      if (attempt > 0) await waitForApiReady(90_000);
      const res = await fetchWithTimeout(url("/v1/analyze"), { method: "POST", body: form });
      if (!res.ok) throw new Error(await parseError(res));
      return (await res.json()) as AnalyzeResponse;
    } catch (e) {
      lastErr = e;
      const msg = String(e);
      const retryable =
        msg.includes("Failed to fetch") ||
        msg.includes("NetworkError") ||
        msg.includes("喚醒逾時") ||
        msg.includes("fetch");
      if (!retryable || attempt === 1) break;
    }
  }
  const msg = String(lastErr);
  if (msg.includes("Failed to fetch") || msg.includes("NetworkError")) {
    throw new Error(
      "與分析伺服器連線中斷（免費方案可能休眠或記憶體不足）。請先等 1 分鐘，再按一次「開始分析」。"
    );
  }
  throw lastErr instanceof Error ? lastErr : new Error(msg);
}

export async function pingHealth(): Promise<boolean> {
  try {
    const res = await fetch(url("/healthz"));
    return res.ok;
  } catch {
    return false;
  }
}
