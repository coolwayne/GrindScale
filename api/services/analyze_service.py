from __future__ import annotations

import uuid
from typing import Any

import numpy as np

from api.profile_map import resolve_coin_diameter_mm, resolve_profile
from api.services.histogram import build_histogram
from api.services.image_io import decode_image_bytes, encode_png_base64, resize_long_edge
from grindscale.analysis import analyze, check_capture_quality
from grindscale.calibration import compute_um_per_px, detect_reference_coin_diameter_px
from grindscale.recommendation import build_recommendation
from grindscale.visualization import draw_particle_overlay


class CoinNotFoundError(Exception):
    pass


def run_analysis(
    image_bytes: bytes,
    profile_id: str,
    coin_id: str,
    max_dimension_px: int,
) -> dict[str, Any]:
    image_bgr = decode_image_bytes(image_bytes)
    image_bgr = resize_long_edge(image_bgr, max_dimension_px)

    profile = resolve_profile(profile_id)
    coin_mm = resolve_coin_diameter_mm(coin_id)

    quality_raw = check_capture_quality(image_bgr)
    blur = float(quality_raw["blur_score"])
    brightness = float(quality_raw["mean_brightness"])
    occupancy = float(quality_raw["occupancy"])
    contrast = max(1.0, blur * 0.35)
    quality_pass = bool(quality_raw["pass"])
    quality_text = (
        f"亮度 {brightness:.1f} / 對比 {contrast:.1f} / 覆蓋率 {occupancy:.3f} "
        f"{'（品質通過）' if quality_pass else '（建議重拍）'}"
    )

    um_per_px: float | None = None
    calibration_text = "相對模式（未校正）"

    if coin_mm is not None:
        coin_px = detect_reference_coin_diameter_px(image_bgr)
        if coin_px is None:
            raise CoinNotFoundError(
                "未偵測到硬幣，無法輸出 0-1000um 分布。請將硬幣完整放在白紙上並重拍。"
            )
        um_per_px = compute_um_per_px(coin_mm, coin_px)
        calibration_text = f"校正模式：1 px ≈ {um_per_px:.2f} µm"

    output = analyze(image_bgr, profile, um_per_px=um_per_px)
    stats = output.stats
    recommendation = build_recommendation(stats, profile.name)
    overlay = draw_particle_overlay(image_bgr, output.particles)
    overlay_b64, ow, oh = encode_png_base64(overlay)

    diameters = sorted(float(d) for d in output.diameters_for_hist.tolist())
    hist_bins, hist_meta = build_histogram(diameters, stats.mode)
    unit_label = "µm" if stats.mode == "calibrated" else "px"

    return {
        "analysisId": str(uuid.uuid4()),
        "calibrationText": calibration_text,
        "recommendation": recommendation,
        "quality": {
            "pass": quality_pass,
            "brightness": brightness,
            "contrast": contrast,
            "occupancy": occupancy,
            "text": quality_text,
        },
        "stats": {
            "particleCount": stats.particle_count,
            "mean": stats.mean,
            "std": stats.std,
            "cv": stats.cv,
            "d10": stats.d10,
            "d50": stats.d50,
            "d90": stats.d90,
            "fineRatio": stats.fine_ratio,
            "targetRatio": stats.target_ratio,
            "coarseRatio": stats.coarse_ratio,
            "bimodal": stats.bimodal,
            "uniformityScore": stats.uniformity_score,
            "mode": stats.mode,
            "unitLabel": unit_label,
        },
        "histogram": {"bins": hist_bins, "meta": hist_meta},
        "particleDiameters": diameters,
        "images": {
            "overlayPngBase64": overlay_b64,
            "overlayWidth": ow,
            "overlayHeight": oh,
        },
    }
