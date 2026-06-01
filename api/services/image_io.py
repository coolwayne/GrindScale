from __future__ import annotations

import cv2
import numpy as np


def decode_image_bytes(data: bytes) -> np.ndarray:
    arr = np.frombuffer(data, dtype=np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("INVALID_IMAGE")
    return image


def resize_long_edge(image_bgr: np.ndarray, max_dim: int) -> np.ndarray:
    h, w = image_bgr.shape[:2]
    long_edge = max(h, w)
    if long_edge <= max_dim:
        return image_bgr
    scale = max_dim / float(long_edge)
    new_w = max(1, int(round(w * scale)))
    new_h = max(1, int(round(h * scale)))
    return cv2.resize(image_bgr, (new_w, new_h), interpolation=cv2.INTER_AREA)


def encode_png_base64(image_bgr: np.ndarray) -> tuple[str, int, int]:
    ok, buf = cv2.imencode(".png", image_bgr)
    if not ok:
        raise ValueError("ENCODE_FAILED")
    import base64

    h, w = image_bgr.shape[:2]
    return base64.b64encode(buf.tobytes()).decode("ascii"), w, h
