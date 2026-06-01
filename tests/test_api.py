from __future__ import annotations

import io

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from api.main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _sample_jpeg() -> bytes:
    img = np.ones((480, 640, 3), dtype=np.uint8) * 255
    for cx, cy, r in [(160, 200, 18), (320, 240, 22), (480, 280, 16)]:
        cv2.circle(img, (cx, cy), r, (40, 40, 40), -1)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def test_healthz(client: TestClient) -> None:
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["ok"] is True


def test_meta(client: TestClient) -> None:
    r = client.get("/v1/meta")
    assert r.status_code == 200
    body = r.json()
    ids = {p["id"] for p in body["brewProfiles"]}
    assert ids == {"espresso", "moka", "v60", "french"}
    coin_ids = {c["id"] for c in body["coins"]}
    assert "twd10" in coin_ids
    assert body["limits"]["maxImageBytes"] > 0


def test_analyze_relative_mode(client: TestClient) -> None:
    files = {"image": ("sample.jpg", _sample_jpeg(), "image/jpeg")}
    data = {"profileId": "v60", "coinId": "none"}
    r = client.post("/v1/analyze", files=files, data=data)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["stats"]["mode"] == "relative"
    assert body["stats"]["unitLabel"] == "px"
    assert "overlayPngBase64" in body["images"]
    assert body["stats"]["particleCount"] >= 0


def test_analyze_invalid_profile(client: TestClient) -> None:
    files = {"image": ("sample.jpg", _sample_jpeg(), "image/jpeg")}
    data = {"profileId": "unknown", "coinId": "none"}
    r = client.post("/v1/analyze", files=files, data=data)
    assert r.status_code == 400
