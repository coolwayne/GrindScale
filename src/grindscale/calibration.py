from __future__ import annotations

import cv2
import numpy as np


def detect_reference_coin_diameter_px(image_bgr: np.ndarray) -> float | None:
    """Detect the largest circle candidate as the reference coin diameter (pixels)."""
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (9, 9), 2.0)
    circles = cv2.HoughCircles(
        blur,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=80,
        param1=120,
        param2=30,
        minRadius=20,
        maxRadius=600,
    )
    if circles is None:
        return None

    circles = np.round(circles[0, :]).astype(int)
    largest = max(circles, key=lambda c: c[2])
    return float(largest[2] * 2)


def compute_um_per_px(coin_diameter_mm: float, coin_diameter_px: float) -> float:
    if coin_diameter_px <= 0:
        raise ValueError("coin_diameter_px must be positive")
    return (coin_diameter_mm * 1000.0) / coin_diameter_px
