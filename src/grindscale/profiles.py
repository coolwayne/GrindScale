from __future__ import annotations

from grindscale.models import BrewProfile

# Stable IDs used by LINE LIFF / mobile apps.
BREW_PROFILES_BY_ID: dict[str, BrewProfile] = {
    "espresso": BrewProfile(
        name="義式咖啡",
        target_low_um=200.0,
        target_high_um=600.0,
        fine_threshold_um=200.0,
        coarse_threshold_um=600.0,
        relative_fine_ratio=0.68,
        relative_coarse_ratio=1.38,
        weight_cv=1.0,
        weight_outlier=1.0,
        weight_bimodal=1.0,
    ),
    "moka": BrewProfile(
        name="摩卡壺",
        target_low_um=220.0,
        target_high_um=560.0,
        fine_threshold_um=220.0,
        coarse_threshold_um=560.0,
        relative_fine_ratio=0.72,
        relative_coarse_ratio=1.4,
        weight_cv=0.9,
        weight_outlier=1.0,
        weight_bimodal=0.9,
    ),
    "v60": BrewProfile(
        name="手沖咖啡",
        target_low_um=400.0,
        target_high_um=900.0,
        fine_threshold_um=400.0,
        coarse_threshold_um=900.0,
        relative_fine_ratio=0.7,
        relative_coarse_ratio=1.35,
        weight_cv=1.0,
        weight_outlier=1.0,
        weight_bimodal=1.0,
    ),
    "french": BrewProfile(
        name="法式壓濾壺",
        target_low_um=600.0,
        target_high_um=1400.0,
        fine_threshold_um=600.0,
        coarse_threshold_um=1400.0,
        relative_fine_ratio=0.65,
        relative_coarse_ratio=1.45,
        weight_cv=1.1,
        weight_outlier=1.1,
        weight_bimodal=1.0,
    ),
}

COIN_DIAMETER_MM_BY_ID: dict[str, float | None] = {
    "none": None,
    "twd1": 20.0,
    "twd5": 22.0,
    "twd10": 26.5,
    "twd50": 28.0,
    "usd_quarter": 24.26,
}

# Streamlit / legacy keys (kept for app.py compatibility).
BREW_PROFILES: dict[str, BrewProfile] = {
    "V60": BREW_PROFILES_BY_ID["v60"],
    "Moka Pot": BREW_PROFILES_BY_ID["moka"],
    "French Press": BREW_PROFILES_BY_ID["french"],
    "Espresso": BREW_PROFILES_BY_ID["espresso"],
}

COIN_DIAMETER_MM: dict[str, float] = {
    "None (relative mode)": 0.0,
    "TWD 1": 20.0,
    "TWD 5": 22.0,
    "TWD 10": 26.5,
    "TWD 50": 28.0,
    "USD Quarter": 24.26,
}

IDEAL_RANGE_BY_ID: dict[str, str] = {
    "espresso": "約 200–600 µm",
    "moka": "約 220–560 µm",
    "v60": "約 400–900 µm",
    "french": "約 600–1400 µm",
}

COIN_DISPLAY_BY_ID: dict[str, str] = {
    "none": "不使用（相對模式）",
    "twd1": "TWD 1 元",
    "twd5": "TWD 5 元",
    "twd10": "TWD 10",
    "twd50": "TWD 50 元",
    "usd_quarter": "USD Quarter",
}
