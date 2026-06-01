#!/usr/bin/env bash
# One-shot: Docker API + LIFF preview + ngrok HTTPS URL for LINE Mini App Endpoint.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
STATE_DIR="$ROOT/.grindscale-tunnel"
mkdir -p "$STATE_DIR"

log() { echo "[grindscale] $*"; }

cleanup() {
  if [[ -f "$STATE_DIR/pids" ]]; then
    while read -r pid _; do
      kill "$pid" 2>/dev/null || true
    done < "$STATE_DIR/pids"
    rm -f "$STATE_DIR/pids"
  fi
}
trap cleanup EXIT INT TERM

if ! command -v ngrok >/dev/null; then
  echo "Install ngrok: https://ngrok.com/download"
  exit 1
fi
USE_DOCKER=1
if ! docker ps >/dev/null 2>&1; then
  log "Docker unavailable — starting API with uvicorn instead."
  USE_DOCKER=0
  if [[ ! -d "$ROOT/.venv" ]]; then
    echo "Create venv: python3 -m venv .venv && source .venv/bin/activate && pip install -e '.[api]'"
    exit 1
  fi
fi

LIFF_PORT="${LIFF_PORT:-4173}"
API_PORT="${API_PORT:-8001}"
NGROK_PORT="${NGROK_PORT:-4040}"

if lsof -iTCP:"$API_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $API_PORT already in use. Set API_PORT= to another free port."
  exit 1
fi

log "Building LIFF (API proxy → :$API_PORT)..."
export GRINDSCALE_API_PROXY="http://127.0.0.1:${API_PORT}"
(cd web/liff && npm run build >/dev/null)

log "Starting LIFF preview on :$LIFF_PORT..."
(cd web/liff && npx vite preview --host 127.0.0.1 --port "$LIFF_PORT") &
echo "$! vite-preview" >> "$STATE_DIR/pids"
sleep 2

log "Starting ngrok..."
ngrok http "$LIFF_PORT" --log=stdout >"$STATE_DIR/ngrok.log" 2>&1 &
echo "$! ngrok" >> "$STATE_DIR/pids"

PUBLIC_URL=""
for _ in $(seq 1 30); do
  sleep 1
  PUBLIC_URL="$(curl -sf "http://127.0.0.1:${NGROK_PORT}/api/tunnels" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('tunnels') or []; print(next((x['public_url'] for x in t if x.get('public_url','').startswith('https')), ''))" 2>/dev/null || true)"
  [[ -n "$PUBLIC_URL" ]] && break
done

if [[ -z "$PUBLIC_URL" ]]; then
  echo "Could not read ngrok URL. Check: $STATE_DIR/ngrok.log"
  exit 1
fi

ENDPOINT="${PUBLIC_URL%/}/"
log "Tunnel URL: $ENDPOINT"

CORS_ORIGINS="http://127.0.0.1:${LIFF_PORT},http://localhost:${LIFF_PORT},${ENDPOINT%/}"
if [[ "$USE_DOCKER" == "1" ]]; then
  log "Starting API (docker compose)..."
  CORS_ORIGINS="$CORS_ORIGINS" docker compose up -d --build api
else
  log "Starting API (uvicorn :$API_PORT)..."
  source "$ROOT/.venv/bin/activate"
  CORS_ORIGINS="$CORS_ORIGINS" \
    uvicorn api.main:app --host 127.0.0.1 --port "$API_PORT" &
  echo "$! uvicorn" >> "$STATE_DIR/pids"
fi
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:${API_PORT}/healthz" >/dev/null; then
    break
  fi
  sleep 1
done
curl -sf "http://127.0.0.1:${API_PORT}/healthz" >/dev/null || {
  echo "API failed to start."
  exit 1
}

cat > "$STATE_DIR/last.env" <<EOF
GRINDSCALE_LIFF_ENDPOINT=$ENDPOINT
GRINDSCALE_API_LOCAL=http://127.0.0.1:${API_PORT}
GRINDSCALE_LIFF_LOCAL=http://127.0.0.1:${LIFF_PORT}
EOF

log "Verifying API through tunnel..."
sleep 2
curl -sf "${ENDPOINT}healthz" >/dev/null && log "healthz OK via tunnel" || log "warn: healthz via tunnel failed (ngrok interstitial?)"

echo ""
echo "=============================================="
echo " LINE Mini App Endpoint (paste in Console):"
echo "   $ENDPOINT"
echo ""
echo " Privacy policy URL:"
echo "   ${ENDPOINT}#/privacy"
echo ""
echo " Local preview: http://127.0.0.1:${LIFF_PORT}"
echo " API:           http://127.0.0.1:${API_PORT}"
echo ""
echo " Saved: $STATE_DIR/last.env"
echo " Stop: kill \$(cat $STATE_DIR/pids 2>/dev/null | awk '{print \$1}') 2>/dev/null; docker compose stop api"
echo "=============================================="
echo ""

if [[ "${DETACH:-}" == "1" ]]; then
  trap - EXIT INT TERM
  log "DETACH=1: leaving services running."
  exit 0
fi

wait
