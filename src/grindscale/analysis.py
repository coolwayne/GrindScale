from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import cv2
import numpy as np

from grindscale.models import AnalysisStats, BrewProfile, Particle, ParticleClass


MIN_PARTICLE_AREA = 16.0
MAX_PARTICLE_AREA = 25000.0


@dataclass(frozen=True)
class AnalyzeOutput:
    stats: AnalysisStats
    particles: list[Particle]
    mask: np.ndarray
    labels: np.ndarray
    diameters_for_hist: np.ndarray


def check_capture_quality(image_bgr: np.ndarray) -> dict[str, float | bool]:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    mean_brightness = float(np.mean(gray))
    over_ratio = float(np.mean(gray > 245))
    under_ratio = float(np.mean(gray < 20))

    # Quick occupancy proxy after thresholding.
    binary = cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        35,
        5,
    )
    occupancy = float(np.mean(binary > 0))

    pass_quality = bool(
        blur_score >= 70
        and 35 <= mean_brightness <= 220
        and over_ratio < 0.20
        and under_ratio < 0.20
        and occupancy > 0.02
    )

    return {
        "pass": pass_quality,
        "blur_score": blur_score,
        "mean_brightness": mean_brightness,
        "over_ratio": over_ratio,
        "under_ratio": under_ratio,
        "occupancy": occupancy,
    }


def preprocess_and_segment(image_bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    binary = cv2.adaptiveThreshold(
        blur,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        35,
        5,
    )
    kernel = np.ones((3, 3), np.uint8)
    opened = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)
    closed = cv2.morphologyEx(opened, cv2.MORPH_CLOSE, kernel, iterations=1)
    return closed


def watershed_labels(image_bgr: np.ndarray, binary_mask: np.ndarray) -> np.ndarray:
    distance = cv2.distanceTransform(binary_mask, cv2.DIST_L2, 5)
    if float(distance.max()) <= 0:
        return np.zeros(binary_mask.shape, dtype=np.int32)

    _, sure_fg = cv2.threshold(distance, 0.33 * float(distance.max()), 255, 0)
    sure_fg = np.uint8(sure_fg)
    unknown = cv2.subtract(binary_mask, sure_fg)

    _, markers = cv2.connectedComponents(sure_fg)
    markers = markers + 1
    markers[unknown == 255] = 0

    # Watershed modifies marker in-place.
    color = image_bgr.copy()
    cv2.watershed(color, markers)
    return markers


def _diameter_equivalent_from_area(area: float) -> float:
    return 2.0 * np.sqrt(area / np.pi)


def _classify_particle(
    diameter_px: float,
    diameter_um: float | None,
    profile: BrewProfile,
    sample_median_px: float,
) -> ParticleClass:
    if diameter_um is not None:
        if diameter_um < profile.fine_threshold_um:
            return "fine"
        if diameter_um > profile.coarse_threshold_um:
            return "coarse"
        return "target"

    if diameter_px < sample_median_px * profile.relative_fine_ratio:
        return "fine"
    if diameter_px > sample_median_px * profile.relative_coarse_ratio:
        return "coarse"
    return "target"


def _bimodal_flag(diameters: np.ndarray) -> bool:
    if len(diameters) < 40:
        return False
    counts, _ = np.histogram(diameters, bins=28)
    smooth = np.convolve(counts, np.array([0.25, 0.5, 0.25]), mode="same")
    peak_threshold = max(2, int(np.max(smooth) * 0.15))
    peaks = 0
    for i in range(1, len(smooth) - 1):
        left = smooth[i - 1]
        right = smooth[i + 1]
        if smooth[i] <= peak_threshold:
            continue
        # Require a minimal prominence to avoid counting tiny noise wiggles as peaks.
        if (smooth[i] - max(left, right)) < 1:
            continue
        if smooth[i] > left and smooth[i] > right:
            peaks += 1
    return peaks >= 2


def _safe_percentile(values: np.ndarray, p: float) -> float:
    return float(np.percentile(values, p)) if len(values) else 0.0


def _build_stats(
    diameters: np.ndarray,
    classifications: Iterable[ParticleClass],
    profile: BrewProfile,
    mode: str,
) -> AnalysisStats:
    if len(diameters) == 0:
        return AnalysisStats(
            particle_count=0,
            mean=0.0,
            std=0.0,
            cv=0.0,
            d10=0.0,
            d50=0.0,
            d90=0.0,
            fine_ratio=0.0,
            target_ratio=0.0,
            coarse_ratio=0.0,
            bimodal=False,
            uniformity_score=0,
            mode=mode,  # type: ignore[arg-type]
        )

    labels = list(classifications)
    n = len(labels)
    fine_ratio = labels.count("fine") / n
    target_ratio = labels.count("target") / n
    coarse_ratio = labels.count("coarse") / n

    mean = float(np.mean(diameters))
    std = float(np.std(diameters))
    cv = std / mean if mean > 0 else 0.0
    bimodal = _bimodal_flag(diameters)

    cv_pen = min(45.0, cv * 180.0 * profile.weight_cv)
    outlier_pen = min(45.0, (fine_ratio + coarse_ratio) * 90.0 * profile.weight_outlier)
    bimodal_pen = 12.0 * profile.weight_bimodal if bimodal else 0.0
    score = int(max(0, min(100, round(100.0 - cv_pen - outlier_pen - bimodal_pen))))

    return AnalysisStats(
        particle_count=n,
        mean=mean,
        std=std,
        cv=cv,
        d10=_safe_percentile(diameters, 10),
        d50=_safe_percentile(diameters, 50),
        d90=_safe_percentile(diameters, 90),
        fine_ratio=fine_ratio,
        target_ratio=target_ratio,
        coarse_ratio=coarse_ratio,
        bimodal=bimodal,
        uniformity_score=score,
        mode=mode,  # type: ignore[arg-type]
    )


def analyze(
    image_bgr: np.ndarray,
    profile: BrewProfile,
    um_per_px: float | None = None,
) -> AnalyzeOutput:
    mask = preprocess_and_segment(image_bgr)
    labels = watershed_labels(image_bgr, mask)

    particle_masks: list[np.ndarray] = []
    for label in np.unique(labels):
        if label <= 1:
            continue
        label_mask = np.uint8(labels == label)
        area = float(np.sum(label_mask))
        if area < MIN_PARTICLE_AREA or area > MAX_PARTICLE_AREA:
            continue
        particle_masks.append(label_mask)

    # Watershed fallback.
    if not particle_masks:
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for contour in contours:
            area = float(cv2.contourArea(contour))
            if area < MIN_PARTICLE_AREA or area > MAX_PARTICLE_AREA:
                continue
            canvas = np.zeros(mask.shape, dtype=np.uint8)
            cv2.drawContours(canvas, [contour], -1, 1, -1)
            particle_masks.append(canvas)

    if not particle_masks:
        empty = np.array([], dtype=np.float32)
        stats = _build_stats(empty, [], profile, "relative")
        return AnalyzeOutput(stats=stats, particles=[], mask=mask, labels=labels, diameters_for_hist=empty)

    diameters_px = np.array(
        [_diameter_equivalent_from_area(float(np.sum(pm))) for pm in particle_masks],
        dtype=np.float32,
    )
    median_px = float(np.median(diameters_px))

    particles: list[Particle] = []
    classes: list[ParticleClass] = []
    diameters_hist: list[float] = []
    mode = "calibrated" if um_per_px is not None else "relative"

    for pm, dpx in zip(particle_masks, diameters_px):
        ys, xs = np.where(pm > 0)
        if len(xs) == 0:
            continue
        cx = float(np.mean(xs))
        cy = float(np.mean(ys))
        radius_px = max(1.0, dpx / 2.0)
        dum = float(dpx * um_per_px) if um_per_px is not None else None
        kind = _classify_particle(dpx, dum, profile, median_px)

        particles.append(
            Particle(
                x=cx,
                y=cy,
                radius_px=float(radius_px),
                diameter_px=float(dpx),
                diameter_um=dum,
                kind=kind,
            )
        )
        classes.append(kind)
        diameters_hist.append(dum if dum is not None else float(dpx))

    diam_arr = np.array(diameters_hist, dtype=np.float32)
    stats = _build_stats(diam_arr, classes, profile, mode)
    return AnalyzeOutput(stats=stats, particles=particles, mask=mask, labels=labels, diameters_for_hist=diam_arr)
