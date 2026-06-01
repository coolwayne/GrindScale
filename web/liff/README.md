# GrindScale LINE LIFF 前端

在 LINE 內開啟的粒徑分析網頁（Phase 2）。

## 開發

1. 啟動 API（專案根目錄）：

```bash
source .venv/bin/activate
uvicorn api.main:app --reload --port 8000
```

2. 安裝並啟動前端：

```bash
cd web/liff
cp .env.example .env
npm install
npm run dev
```

瀏覽 `http://127.0.0.1:5173`。未設定 `VITE_LIFF_ID` 時為**開發模式**（可不透過 LINE 開啟）。

Vite 會將 `/v1`、`/healthz` 代理到 `http://127.0.0.1:8000`。

## 環境變數

| 變數 | 說明 |
|------|------|
| `VITE_LIFF_ID` | LINE Developers 的 LIFF ID |
| `VITE_API_BASE` | 正式環境 API 網址（留空則同源） |
| `VITE_API_PROXY_TARGET` | 本機 dev proxy 目標 |

## 建置

```bash
npm run build
```

產出在 `dist/`，部署到 HTTPS 靜態託管（Cloudflare Pages、Vercel 等），並將網址設為 LINE Mini App 的 Endpoint URL。

詳見 [docs/line-mini-app/DEPLOY.md](../../docs/line-mini-app/DEPLOY.md) 與 [LINE-CONSOLE.md](../../docs/line-mini-app/LINE-CONSOLE.md)。

## 畫面

- `#/home` — 選沖煮方式、更多選項、SKIP
- `#/analysis` — 拍照、硬幣、分析
- `#/result` — 統計、直方圖、疊圖、CSV 下載
- `#/privacy` — 隱私權政策（簡版）
