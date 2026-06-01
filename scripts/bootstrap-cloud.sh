#!/usr/bin/env bash
# Bootstrap Git + optional Cloudflare Pages deploy + Render instructions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { echo "[bootstrap] $*"; }

cmd="${1:-help}"

load_deploy_env() {
  if [[ -f "$ROOT/deploy/.env.deploy" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ROOT/deploy/.env.deploy"
    set +a
  fi
}

git_init() {
  if [[ -d .git ]]; then
    log "Git already initialized."
    return
  fi
  git init -b main
  log "Git initialized (branch main)."
}

git_first_commit() {
  git_init
  if git rev-parse HEAD >/dev/null 2>&1; then
    log "Commit exists: $(git log -1 --oneline)"
    return
  fi
  git add -A
  git status --short | head -20
  git commit -m "$(cat <<'EOF'
Add GrindScale LINE LIFF stack and cloud deploy config.

Includes FastAPI backend, LIFF web app, Render blueprint, and Cloudflare Pages workflow.
EOF
)"
  log "Initial commit created."
}

pages_build() {
  load_deploy_env
  export VITE_API_BASE="${VITE_API_BASE:-https://grindscale-api.onrender.com}"
  export VITE_LIFF_ID="${VITE_LIFF_ID:-}"
  log "Building LIFF → VITE_API_BASE=$VITE_API_BASE"
  (cd web/liff && npm ci && npm run build)
}

pages_deploy() {
  load_deploy_env
  : "${CLOUDFLARE_API_TOKEN:?Set in deploy/.env.deploy}"
  : "${CLOUDFLARE_ACCOUNT_ID:?Set in deploy/.env.deploy}"
  PAGES_PROJECT="${PAGES_PROJECT:-grindscale-liff}"
  pages_build
  log "Deploying to Cloudflare Pages ($PAGES_PROJECT)..."
  CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" CLOUDFLARE_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID" \
    npx wrangler@3 pages deploy web/liff/dist \
      --project-name="$PAGES_PROJECT" \
      --branch=main \
      --commit-dirty=true
  PAGES_URL="${PAGES_URL:-https://${PAGES_PROJECT}.pages.dev}"
  echo ""
  echo "LIFF URL: ${PAGES_URL}/"
  echo "LINE Endpoint: ${PAGES_URL}/"
  echo "Privacy: ${PAGES_URL}/#/privacy"
}

print_render_steps() {
  load_deploy_env
  PAGES_URL="${PAGES_URL:-https://grindscale-liff.pages.dev}"
  RENDER_API_URL="${RENDER_API_URL:-https://grindscale-api.onrender.com}"
  cat <<EOF

=== Render API（一次性，約 10–20 分鐘）===

1. 先把程式推到 GitHub（見下方 github 步驟）
2. 開啟 https://dashboard.render.com/ → New → Blueprint
3. 連線你的 GitHub repo → 套用根目錄 render.yaml
4. 環境變數 CORS_ORIGINS 設為：
   ${PAGES_URL}
5. 部署完成後測試：
   curl -sS ${RENDER_API_URL}/healthz

=== GitHub Actions（可選，之後自動部署 LIFF）===

Repository → Settings → Secrets → Actions，新增：
  CLOUDFLARE_API_TOKEN
  CLOUDFLARE_ACCOUNT_ID
  VITE_API_BASE = ${RENDER_API_URL}
  VITE_LIFF_ID   = （LINE Console 的 LIFF ID）

=== LINE Console ===

Endpoint URL: ${PAGES_URL}/

EOF
}

print_github_steps() {
  cat <<'EOF'

=== GitHub ===

1. https://github.com/new 建立新 repo（例如 grindscale），不要加 README
2. 在本機執行（替換 YOUR_USER / REPO）：

   git remote add origin git@github.com:YOUR_USER/REPO.git
   git push -u origin main

3. 再到 Render 連線此 repo

EOF
}

case "$cmd" in
  git) git_first_commit ;;
  build) pages_build ;;
  deploy) pages_deploy ;;
  render) print_render_steps ;;
  github) print_github_steps ;;
  all)
    git_first_commit
    print_github_steps
    print_render_steps
    if [[ -f "$ROOT/deploy/.env.deploy" ]]; then
      pages_deploy || log "Pages deploy failed — fix deploy/.env.deploy and retry."
    else
      log "Copy deploy/.env.deploy.example → deploy/.env.deploy to deploy LIFF from CLI."
    fi
    ;;
  help|*)
    cat <<'EOF'
Usage:
  ./scripts/bootstrap-cloud.sh git      # init + first commit
  ./scripts/bootstrap-cloud.sh build    # production LIFF build
  ./scripts/bootstrap-cloud.sh deploy   # needs deploy/.env.deploy
  ./scripts/bootstrap-cloud.sh github   # GitHub push instructions
  ./scripts/bootstrap-cloud.sh render   # Render dashboard steps
  ./scripts/bootstrap-cloud.sh all      # git + instructions (+ deploy if .env.deploy)
EOF
    ;;
esac
