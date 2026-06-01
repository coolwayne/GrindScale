from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from api.config import CORS_ORIGINS
from api.routes import analyze, meta

app = FastAPI(
    title="GrindScale API",
    version="0.1.0",
    description="Coffee grind analysis API for LINE LIFF and web clients.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(meta.router, prefix="/v1", tags=["meta"])
app.include_router(analyze.router, prefix="/v1", tags=["analyze"])


@app.get("/healthz")
def healthz() -> dict[str, bool]:
    return {"ok": True}


@app.exception_handler(HTTPException)
async def http_exception_handler(_request: Request, exc: HTTPException) -> JSONResponse:
    if isinstance(exc.detail, dict) and "error" in exc.detail:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": "HTTP_ERROR", "message": str(exc.detail)}},
    )
