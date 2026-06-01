#!/usr/bin/env bash
# Fix LIFF hosting: Render static (primary) + optional Cloudflare Pages CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { echo "[fix] $*"; }

export VITE_API_BASE="${VITE_API_BASE:-https://grindscale-api.onrender.com}"
log "Building LIFF (VITE_API_BASE=$VITE_API_BASE)..."
(cd web/liff && npm ci && npm run build)

if npx wrangler@3 whoami >/dev/null 2>&1; then
  log "Wrangler logged in — deploying Cloudflare Pages..."
  (cd web/liff && npx wrangler pages deploy dist --project-name=grindscale-liff1 --branch=main) || true
else
  log "Wrangler not logged in. Run: cd web/liff && npx wrangler login"
  log "Then: npm run pages:deploy"
fi

log ""
log "=== Render (recommended — already linked to GitHub) ==="
log "1. Open https://dashboard.render.com/ → Blueprint GrindScale"
log "2. Click Manual sync (render.yaml now includes static site grindscale-liff)"
log "3. After deploy, open: https://grindscale-liff.onrender.com/#/home"
log "4. LINE Endpoint: https://grindscale-liff.onrender.com/"
log ""
