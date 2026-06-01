from __future__ import annotations

import cv2
import matplotlib.pyplot as plt
import numpy as np

from grindscale.models import Particle


COLOR_MAP = {
    "fine": (255, 120, 0),   # Blue-ish in BGR
    "target": (0, 200, 0),   # Green
    "coarse": (0, 0, 255),   # Red
}


def draw_particle_overlay(image_bgr: np.ndarray, particles: list[Particle]) -> np.ndarray:
    overlay = image_bgr.copy()
    for p in particles:
        color = COLOR_MAP[p.kind]
        center = (int(round(p.x)), int(round(p.y)))
        radius = int(max(2, round(p.radius_px)))
        cv2.circle(overlay, center, radius, color, 1)
    return overlay


def make_hist_figure(
    diameters: np.ndarray,
    unit: str,
    title: str,
) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(7, 3))
    if len(diameters) == 0:
        ax.text(0.5, 0.5, "No particles detected", ha="center", va="center")
        ax.set_axis_off()
        return fig

    ax.hist(diameters, bins=25, color="#3b82f6", alpha=0.85, edgecolor="white")
    ax.set_title(title)
    ax.set_xlabel(f"Particle diameter ({unit})")
    ax.set_ylabel("Count")
    ax.grid(alpha=0.2)
    fig.tight_layout()
    return fig
