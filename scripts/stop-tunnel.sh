#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/.grindscale-tunnel/pids"
if [[ -f "$STATE" ]]; then
  while read -r pid _; do
    kill "$pid" 2>/dev/null || true
  done < "$STATE"
  rm -f "$STATE"
fi
pkill -f "uvicorn api.main:app --host 127.0.0.1" 2>/dev/null || true
docker compose -f "$ROOT/docker-compose.yml" stop api 2>/dev/null || true
echo "Stopped tunnel services."
