#!/usr/bin/env bash
# Start API + LIFF dev servers. Requires: Python venv with [api], Node 18+.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  echo "Create venv first: python3 -m venv .venv && source .venv/bin/activate && pip install -e '.[api,dev]'"
  exit 1
fi

if [[ ! -d web/liff/node_modules ]]; then
  (cd web/liff && npm install)
fi

cleanup() {
  kill "$API_PID" "$LIFF_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

source .venv/bin/activate
uvicorn api.main:app --reload --host 127.0.0.1 --port 8000 &
API_PID=$!

(cd web/liff && npm run dev) &
LIFF_PID=$!

echo ""
echo "API:  http://127.0.0.1:8000  (docs: /docs)"
echo "LIFF: http://127.0.0.1:5173"
echo "Press Ctrl+C to stop."
wait
