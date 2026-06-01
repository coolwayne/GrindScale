from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from api.config import MAX_IMAGE_DIMENSION_PX, MAX_UPLOAD_BYTES
from api.schemas import AnalyzeResponse, ErrorResponse
from api.services.analyze_service import CoinNotFoundError, run_analysis

router = APIRouter()


@router.post(
    "/analyze",
    response_model=AnalyzeResponse,
    responses={
        422: {"model": ErrorResponse},
        400: {"model": ErrorResponse},
        413: {"model": ErrorResponse},
    },
)
async def analyze_image(
    image: UploadFile = File(...),
    profileId: str = Form(...),
    coinId: str = Form(...),
    roastLevel: str | None = Form(None),
    beanDescription: str | None = Form(None),
    grinderDescription: str | None = Form(None),
) -> AnalyzeResponse:
    _ = roastLevel, beanDescription, grinderDescription

    data = await image.read()
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail={
                "error": {
                    "code": "IMAGE_TOO_LARGE",
                    "message": f"影像超過 {MAX_UPLOAD_BYTES} bytes 上限。",
                }
            },
        )
    if not data:
        raise HTTPException(
            status_code=400,
            detail={"error": {"code": "INVALID_IMAGE", "message": "未收到影像資料。"}},
        )

    try:
        payload = run_analysis(
            data,
            profile_id=profileId,
            coin_id=coinId,
            max_dimension_px=MAX_IMAGE_DIMENSION_PX,
        )
    except CoinNotFoundError as e:
        raise HTTPException(
            status_code=422,
            detail={"error": {"code": "COIN_NOT_FOUND", "message": str(e)}},
        ) from e
    except ValueError as e:
        code = str(e) if str(e) in ("INVALID_IMAGE",) else "INVALID_IMAGE"
        raise HTTPException(
            status_code=400,
            detail={"error": {"code": code, "message": "影像讀取失敗，請換一張圖片。"}},
        ) from e
    except KeyError as e:
        raise HTTPException(
            status_code=400,
            detail={"error": {"code": "INVALID_PARAMS", "message": str(e)}},
        ) from e

    return AnalyzeResponse.model_validate(payload)
