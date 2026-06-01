from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class BrewProfileMeta(BaseModel):
    id: str
    name: str
    idealRange: str


class CoinMeta(BaseModel):
    id: str
    name: str
    diameterMm: float | None = None


class LimitsMeta(BaseModel):
    maxImageBytes: int
    maxDimensionPx: int


class MetaResponse(BaseModel):
    brewProfiles: list[BrewProfileMeta]
    coins: list[CoinMeta]
    roastLevels: list[str]
    limits: LimitsMeta


class QualityResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    pass_: bool = Field(validation_alias="pass", serialization_alias="pass")
    brightness: float
    contrast: float
    occupancy: float
    text: str


class StatsResponse(BaseModel):
    particleCount: int
    mean: float
    std: float
    cv: float
    d10: float
    d50: float
    d90: float
    fineRatio: float
    targetRatio: float
    coarseRatio: float
    bimodal: bool
    uniformityScore: int
    mode: Literal["relative", "calibrated"]
    unitLabel: str


class HistogramBinResponse(BaseModel):
    start: float
    end: float
    count: int


class HistogramResponse(BaseModel):
    bins: list[HistogramBinResponse]
    meta: str


class ImagesResponse(BaseModel):
    overlayPngBase64: str
    overlayWidth: int
    overlayHeight: int


class AnalyzeResponse(BaseModel):
    analysisId: str
    calibrationText: str
    recommendation: str
    quality: QualityResponse
    stats: StatsResponse
    histogram: HistogramResponse
    particleDiameters: list[float]
    images: ImagesResponse


class ErrorBody(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorBody
