# 雲端部署快速開始（關機也能用）

預設網址（專案名稱未被佔用時）：

| 服務 | URL |
|------|-----|
| LIFF | https://grindscale-liff.pages.dev/ |
| API | https://grindscale-api.onrender.com |

---

## 步驟 1：推到 GitHub

```bash
cd /Users/hung-yupan/GrindScale
./scripts/bootstrap-cloud.sh github
# 依畫面建立 repo 後：
git remote add origin https://github.com/coolwayne/GrindScale.git
git push -u origin main
```

---

## 步驟 2：Render 部署 API

1. 登入 https://dashboard.render.com/
2. **New → Blueprint** → 選你的 GitHub repo
3. 確認 `render.yaml` 被讀取（服務名 `grindscale-api`）
4. 部署完成後：

```bash
curl -sS https://grindscale-api.onrender.com/healthz
```

---

## 步驟 3：Cloudflare Pages 部署 LIFF

### 方式 A — 網頁（推薦第一次）

1. https://dash.cloudflare.com/ → **Workers & Pages** → **Create**
2. **Pages** → Connect to Git → 選同一個 repo
3. 建置設定：

| 欄位 | 值 |
|------|-----|
| Root directory | `web/liff` |
| Build command | `npm ci && npm run build` |
| Output | `dist` |

4. 環境變數（Production）：

```
VITE_API_BASE=https://grindscale-api.onrender.com
VITE_LIFF_ID=你的LIFF_ID
```

5. 部署完成 → 確認能開 https://grindscale-liff.pages.dev/

### 方式 B — 指令（需 API Token）

```bash
cp deploy/.env.deploy.example deploy/.env.deploy
# 編輯填入 CLOUDFLARE_API_TOKEN、CLOUDFLARE_ACCOUNT_ID、VITE_LIFF_ID
./scripts/bootstrap-cloud.sh deploy
```

---

## 步驟 4：LINE Console

Endpoint URL：

```
https://grindscale-liff.pages.dev/
```

詳見 [LINE-CONSOLE.md](../docs/line-mini-app/LINE-CONSOLE.md)

---

## 自動化（選用）

Workflow 檔在 `deploy/github-actions/deploy-pages.yml`。複製到 `.github/workflows/` 後 push（需 `gh auth refresh -s workflow` 並完成裝置授權）。

GitHub repo → Settings → Secrets → 加入 `CLOUDFLARE_*`、`VITE_*` 後，push `main` 會觸發部署。
