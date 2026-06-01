#!/usr/bin/env bash
# After GitHub auth: push repo, then optional Cloudflare deploy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GH="${GH:-/opt/homebrew/bin/gh}"

log() { echo "[auto] $*"; }

wait_gh_auth() {
  for _ in $(seq 1 120); do
    if "$GH" auth status >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "GitHub 未登入。請執行: gh auth login -h github.com -p https -w"
  exit 1
}

git_push() {
  "$GH" auth setup-git
  git push -u origin main
  log "Pushed to $(git remote get-url origin)"
}

main() {
  wait_gh_auth
  git_push
  if [[ -f "$ROOT/deploy/.env.deploy" ]]; then
    "$ROOT/scripts/bootstrap-cloud.sh" deploy
  else
    log "Cloudflare: copy deploy/.env.deploy.example → deploy/.env.deploy 後再 deploy"
    "$ROOT/scripts/bootstrap-cloud.sh" render
  fi
}

main "$@"
