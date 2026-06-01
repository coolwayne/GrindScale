from __future__ import annotations

from grindscale.models import AnalysisStats
from grindscale.recommendation import build_recommendation


def test_recommendation_for_high_fines() -> None:
    stats = AnalysisStats(
        particle_count=100,
        mean=500,
        std=260,
        cv=0.52,
        d10=180,
        d50=460,
        d90=900,
        fine_ratio=0.35,
        target_ratio=0.50,
        coarse_ratio=0.15,
        bimodal=False,
        uniformity_score=52,
        mode="relative",
    )
    text = build_recommendation(stats, "V60")
    assert "調粗" in text
