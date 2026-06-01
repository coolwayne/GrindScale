# Cloudflare：修復 ERR_NAME_NOT_RESOLVED

`grindscale-liff1.pages.dev` 在 DNS 上**不存在**（尚未建立 Pages 網域）。  
建置成功 ≠ 已有 `pages.dev` 網址。

---

## 方案 A — 上傳靜態檔（最快，約 5 分鐘）

不用 Git、不用部署命令。

1. 本機建置：

```bash
cd web/liff
VITE_API_BASE=https://grindscale-api.onrender.com npm ci && npm run build
```

2. 開啟 https://dash.cloudflare.com/ → **Workers & Pages** → **Create**
3. 選 **Upload your static files**（上傳靜態檔案）
4. 專案名稱：`grindscale-liff1`（或新名稱 `grindscale-web`）
5. 把 **`web/liff/dist` 資料夾內所有檔案**拖進去（含 `index.html`、`_redirects`、`assets/`）
6. **Deploy** 完成後，畫面會顯示 **實際網址**（一定要從這裡複製，不要自己猜）

---

## 方案 B — 重建「Pages」專案（Git 自動部署）

**刪除或停用** 目前這個只會 Worker 建置的 `grindscale-liff1`（可選）。

1. **Create application** → 切到 **Pages** 分頁（不是 Workers）
2. **Connect to Git** → `coolwayne/GrindScale`
3. 設定：

| 欄位 | 值 |
|------|-----|
| Project name | `grindscale-liff1` |
| Root directory | `web/liff` |
| Build command | `npm ci && npm run build` |
| Build output directory | `dist` |
| **Deploy command** | **留空** |

4. Environment variables：

```
VITE_API_BASE=https://grindscale-api.onrender.com
```

5. Deploy 後在專案頁按 **Visit site** 取得網址。

---

## 方案 C — 本機 CLI（有 API Token 時）

1. https://dash.cloudflare.com/profile/api-tokens → **Create Token** → 範本 **Edit Cloudflare Workers**（含 Account + Pages）
2. 複製 token，並在 Overview 複製 **Account ID**

```bash
cd /Users/hung-yupan/GrindScale
cp deploy/.env.deploy.example deploy/.env.deploy
# 編輯填入 CLOUDFLARE_API_TOKEN、CLOUDFLARE_ACCOUNT_ID

cd web/liff
VITE_API_BASE=https://grindscale-api.onrender.com npm run build
source ../../deploy/.env.deploy
npx wrangler pages deploy dist --project-name=grindscale-liff1
```

終端機會印出 **Deployment URL**。

---

## 驗證

在終端機（替換成 Visit site 顯示的網址）：

```bash
dig +short 你的專案.pages.dev
curl -I https://你的專案.pages.dev/
```

`dig` 應有 IP（例如 `104.x.x.x`），不應再是空白。

---

## LINE Console

Endpoint 填 **Visit site 顯示的網址** + `/`：

```
https://（實際子網域）.pages.dev/
```
