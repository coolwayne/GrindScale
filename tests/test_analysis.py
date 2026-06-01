from __future__ import annotations

import numpy as np

from grindscale.analysis import _bimodal_flag, _build_stats
from grindscale.models import BrewProfile


def _profile() -> BrewProfile:
    return BrewProfile(
        name="Test",
        target_low_um=300,
        target_high_um=600,
        fine_threshold_um=250,
        coarse_threshold_um=650,
        relative_fine_ratio=0.7,
        relative_coarse_ratio=1.3,
        weight_cv=1.0,
        weight_outlier=1.0,
        weight_bimodal=1.0,
    )


def test_bimodal_flag_detects_two_peaks() -> None:
    left = np.random.normal(loc=300, scale=20, size=120)
    right = np.random.normal(loc=600, scale=25, size=120)
    arr = np.concatenate([left, right]).astype(np.float32)
    assert _bimodal_flag(arr) is True


def test_build_stats_outputs_valid_ranges() -> None:
    diameters = np.array([200, 220, 240, 260, 280], dtype=np.float32)
    classes = ["fine", "target", "target", "target", "coarse"]
    stats = _build_stats(diameters, classes, _profile(), "relative")

    assert stats.particle_count == 5
    assert 0.0 <= stats.fine_ratio <= 1.0
    assert 0.0 <= stats.target_ratio <= 1.0
    assert 0.0 <= stats.coarse_ratio <= 1.0
    assert 0 <= stats.uniformity_score <= 100
