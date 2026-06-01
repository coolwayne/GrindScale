from __future__ import annotations

import os

MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", "8388608"))
MAX_IMAGE_DIMENSION_PX = int(os.getenv("MAX_IMAGE_DIMENSION_PX", "2048"))
CORS_ORIGINS = [
    o.strip()
    for o in os.getenv(
        "CORS_ORIGINS",
        "http://localhost:5173,http://127.0.0.1:5173",
    ).split(",")
    if o.strip()
]
LINE_CHANNEL_ID = os.getenv("LINE_CHANNEL_ID", "")
REQUIRE_LIFF_TOKEN = os.getenv("REQUIRE_LIFF_TOKEN", "").lower() in ("1", "true", "yes")
