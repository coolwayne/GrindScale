import type { AnalyzeResponse, ApiError, MetaResponse } from "./types";

const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined)?.replace(/\/$/, "") ?? "";

function url(path: string): string {
  return `${API_BASE}${path}`;
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
  const res = await fetch(url("/v1/meta"));
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

  const res = await fetch(url("/v1/analyze"), { method: "POST", body: form });
  if (!res.ok) throw new Error(await parseError(res));
  return res.json() as Promise<AnalyzeResponse>;
}

export async function pingHealth(): Promise<boolean> {
  try {
    const res = await fetch(url("/healthz"));
    return res.ok;
  } catch {
    return false;
  }
}
