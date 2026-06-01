from __future__ import annotations

from grindscale.models import BrewProfile
from grindscale.profiles import (
    BREW_PROFILES_BY_ID,
    COIN_DIAMETER_MM_BY_ID,
    COIN_DISPLAY_BY_ID,
    IDEAL_RANGE_BY_ID,
)

SKIP_DEFAULT_PROFILE_ID = "v60"


def resolve_profile(profile_id: str) -> BrewProfile:
    key = profile_id.strip().lower()
    if key not in BREW_PROFILES_BY_ID:
        raise KeyError(f"Unknown profileId: {profile_id}")
    return BREW_PROFILES_BY_ID[key]


def resolve_coin_diameter_mm(coin_id: str) -> float | None:
    key = coin_id.strip().lower()
    if key not in COIN_DIAMETER_MM_BY_ID:
        raise KeyError(f"Unknown coinId: {coin_id}")
    return COIN_DIAMETER_MM_BY_ID[key]


def meta_brew_profiles() -> list[dict[str, str]]:
    return [
        {
            "id": pid,
            "name": BREW_PROFILES_BY_ID[pid].name,
            "idealRange": IDEAL_RANGE_BY_ID[pid],
        }
        for pid in ("espresso", "moka", "v60", "french")
    ]


def meta_coins() -> list[dict[str, str | float | None]]:
    return [
        {
            "id": cid,
            "name": COIN_DISPLAY_BY_ID[cid],
            "diameterMm": COIN_DIAMETER_MM_BY_ID[cid],
        }
        for cid in ("none", "twd1", "twd5", "twd10", "twd50")
    ]
