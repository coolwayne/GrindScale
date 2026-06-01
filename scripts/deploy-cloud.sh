#!/usr/bin/env bash
# Deploy API (Render) + LIFF (Cloudflare Pages) when tokens are set.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?Set CLOUDFLARE_ACCOUNT_ID}"
: "${VITE_LIFF_ID:?Set VITE_LIFF_ID}"
: "${VITE_API_BASE:?Set VITE_API_BASE (e.g. https://grindscale-api.onrender.com)}"
: "${CORS_ORIGINS:?Set CORS_ORIGINS (Pages origin, comma-separated)}"

PAGES_PROJECT="${PAGES_PROJECT:-grindscale-liff}"

log() { echo "[deploy] $*"; }

log "Building LIFF with production env..."
(cd web/liff && npm ci && npm run build)

log "Deploying to Cloudflare Pages ($PAGES_PROJECT)..."
npx wrangler@3 pages deploy web/liff/dist \
  --project-name="$PAGES_PROJECT" \
  --branch=main \
  --commit-dirty=true

log "LIFF deploy requested."
echo ""
echo "Next: Render dashboard → set CORS_ORIGINS=$CORS_ORIGINS"
echo "      LINE Console → Endpoint = https://<project>.pages.dev/"
echo ""
echo "If Render API not created yet, connect repo and apply render.yaml from repo root."
