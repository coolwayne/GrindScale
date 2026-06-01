# GrindScale MVP

Coffee grind uniformity analyzer prototype.

## Features

- Camera capture or image upload.
- Capture quality gate (blur/exposure/occupancy).
- Particle segmentation with adaptive threshold + morphology + watershed.
- Equivalent diameter measurement.
- Distribution metrics (mean/std/CV, D10/D50/D90).
- Uniformity score and brew-oriented recommendations.
- Optional coin-based calibration (TWD 10 / USD quarter).
- Color overlay:
  - Blue: fine
  - Green: target
  - Red: coarse

## iPhone App (SwiftUI) Quick Start

```bash
xcodegen generate --spec ios/GrindScaleIOS/project.yml
open ios/GrindScaleIOS/GrindScaleIOS.xcodeproj
```

Then in Xcode:

1. Select scheme `GrindScaleIOS`.
2. Connect your iPhone and choose it as run destination.
3. Set your Team in Signing & Capabilities.
4. Press Run.

The app includes:
- Camera capture
- Photo library selection
- On-device particle analysis
- Uniformity score and ratios
- Particle overlay (blue/green/red)
- Coin reference calibration mode (TWD 1 / 5 / 10 / 50)
- D10 / D50 / D90 metrics and histogram
- Local recent analysis history

Capture note:
- Place coffee grounds on white paper.
- If using calibration, place the coin on the same white paper in the same frame.

## LINE Mini App (LIFF) — Design

方案 2（在 LINE 內開啟網頁、後端跑 Python 分析）的完整設計見：

- [docs/line-mini-app/DESIGN.md](docs/line-mini-app/DESIGN.md)
- [docs/line-mini-app/DEPLOY.md](docs/line-mini-app/DEPLOY.md) — Cloudflare Pages + Render
- [docs/line-mini-app/LINE-CONSOLE.md](docs/line-mini-app/LINE-CONSOLE.md) — 官方帳號 / Mini App / Rich Menu

## GrindScale API (LINE LIFF backend)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e ".[api,dev]"
uvicorn api.main:app --reload --port 8000
```

- `GET http://127.0.0.1:8000/healthz`
- `GET http://127.0.0.1:8000/v1/meta`
- `POST http://127.0.0.1:8000/v1/analyze` (`multipart`: `image`, `profileId`, `coinId`)

Docker:

```bash
docker compose up --build
```

API tests:

```bash
pytest tests/test_api.py -q
```

## LINE LIFF Web App

```bash
chmod +x scripts/run-dev.sh && ./scripts/run-dev.sh

# LINE 測試用 HTTPS 隧道（ngrok，免部署）
chmod +x scripts/auto-line-tunnel.sh && DETACH=1 ./scripts/auto-line-tunnel.sh
```

或分開兩個終端機：

```bash
# Terminal 1: API
uvicorn api.main:app --reload --port 8000

# Terminal 2: LIFF frontend
cd web/liff && npm install && npm run dev
```

See [web/liff/README.md](web/liff/README.md).

## Web Prototype Quick Start (Optional)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e .
streamlit run app.py
```

Open the local URL printed by Streamlit.

## Run Tests

```bash
pytest -q
```

## Project Layout

- `docs/line-mini-app/`: LINE Mini App / LIFF architecture and API design.
- `api/`: FastAPI service (`/v1/meta`, `/v1/analyze`).
- `web/liff/`: LINE LIFF 前端（Vite + TypeScript）。
- `ios/GrindScaleIOS/`: native iOS app project.
- `app.py`: Streamlit UI.
- `src/grindscale/analysis.py`: core CV pipeline and scoring.
- `src/grindscale/calibration.py`: coin detection and px->um conversion.
- `src/grindscale/recommendation.py`: rule-based recommendation.
- `src/grindscale/visualization.py`: overlay and histogram rendering.
- `tests/`: baseline unit tests.

## Notes

- This is an MVP prototype tuned for relative consistency, not lab-grade metrology.
- For best results, use white background and diffuse lighting.
