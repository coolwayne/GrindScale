from __future__ import annotations

from fastapi import APIRouter

from api.config import MAX_IMAGE_DIMENSION_PX, MAX_UPLOAD_BYTES
from api.profile_map import meta_brew_profiles, meta_coins
from api.schemas import CoinMeta, LimitsMeta, MetaResponse, BrewProfileMeta

router = APIRouter()


@router.get("/meta", response_model=MetaResponse)
def get_meta() -> MetaResponse:
    return MetaResponse(
        brewProfiles=[BrewProfileMeta(**p) for p in meta_brew_profiles()],
        coins=[CoinMeta(**c) for c in meta_coins()],
        roastLevels=["淺焙", "中淺焙", "中焙", "中深焙", "深焙"],
        limits=LimitsMeta(
            maxImageBytes=MAX_UPLOAD_BYTES,
            maxDimensionPx=MAX_IMAGE_DIMENSION_PX,
        ),
    )
