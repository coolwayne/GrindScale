export interface BrewProfileMeta {
  id: string;
  name: string;
  idealRange: string;
}

export interface CoinMeta {
  id: string;
  name: string;
  diameterMm: number | null;
}

export interface MetaResponse {
  brewProfiles: BrewProfileMeta[];
  coins: CoinMeta[];
  roastLevels: string[];
  limits: { maxImageBytes: number; maxDimensionPx: number };
}

export interface QualityInfo {
  pass: boolean;
  brightness: number;
  contrast: number;
  occupancy: number;
  text: string;
}

export interface StatsInfo {
  particleCount: number;
  mean: number;
  std: number;
  cv: number;
  d10: number;
  d50: number;
  d90: number;
  fineRatio: number;
  targetRatio: number;
  coarseRatio: number;
  bimodal: boolean;
  uniformityScore: number;
  mode: "relative" | "calibrated";
  unitLabel: string;
}

export interface HistogramBin {
  start: number;
  end: number;
  count: number;
}

export interface AnalyzeResponse {
  analysisId: string;
  calibrationText: string;
  recommendation: string;
  quality: QualityInfo;
  stats: StatsInfo;
  histogram: { bins: HistogramBin[]; meta: string };
  particleDiameters: number[];
  images: {
    overlayPngBase64: string;
    overlayWidth: number;
    overlayHeight: number;
  };
}

export interface ApiError {
  error: { code: string; message: string };
}

export interface HistoryRecord {
  id: string;
  timestamp: number;
  profileName: string;
  mode: "relative" | "calibrated";
  score: number;
  particleCount: number;
  cv: number;
}

export interface AppSettings {
  profileId: string;
  coinId: string;
  roastLevel: string;
  beanDescription: string;
  grinderDescription: string;
}
