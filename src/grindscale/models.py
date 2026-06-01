from __future__ import annotations

from dataclasses import dataclass
from typing import Literal


Mode = Literal["relative", "calibrated"]
ParticleClass = Literal["fine", "target", "coarse"]


@dataclass(frozen=True)
class BrewProfile:
    name: str
    # Used in calibrated mode (micrometers).
    target_low_um: float
    target_high_um: float
    fine_threshold_um: float
    coarse_threshold_um: float
    # Used in relative mode (multipliers around sample median).
    relative_fine_ratio: float
    relative_coarse_ratio: float
    # Score weights.
    weight_cv: float
    weight_outlier: float
    weight_bimodal: float


@dataclass(frozen=True)
class Particle:
    x: float
    y: float
    radius_px: float
    diameter_px: float
    diameter_um: float | None
    kind: ParticleClass


@dataclass(frozen=True)
class AnalysisStats:
    particle_count: int
    mean: float
    std: float
    cv: float
    d10: float
    d50: float
    d90: float
    fine_ratio: float
    target_ratio: float
    coarse_ratio: float
    bimodal: bool
    uniformity_score: int
    mode: Mode
