# GrindScale — 部署指南（免費方案）

靜態 LIFF 前端與 Python API 分開部署，符合 [DESIGN.md](./DESIGN.md) 第 5 節。

| 元件 | 建議平台 | 費用 |
|------|----------|------|
| `web/liff/dist` | [Cloudflare Pages](https://pages.cloudflare.com/) | 免費 |
| `api/` (Docker) | [Render](https://render.com/) 或 [Fly.io](https://fly.io/) | 免費層（有休眠） |

---

## 1. 部署 API（Render）

1. 將 repo 連到 Render，選 **New → Blueprint** 或手動 **Web Service → Docker**。
2. 若用 Blueprint：根目錄已有 [`render.yaml`](../../render.yaml)。
3. 在 Dashboard 設定環境變數（可參考 [`deploy/env.api.example`](../../deploy/env.api.example)）：

   ```env
   CORS_ORIGINS=https://<你的-pages專案>.pages.dev
   ```

   之後若加上自訂網域，請一併加入該 `https://` origin（逗號分隔、勿空格）。

4. 部署完成後記下 URL，例如 `https://grindscale-api.onrender.com`。
5. 驗證：

   ```bash
   curl -sS https://grindscale-api.onrender.com/healthz
   curl -sS https://grindscale-api.onrender.com/v1/meta | head
   ```

**冷啟動**：免費方案約 50 秒無流量會休眠；LIFF 首屏已會呼叫 `/healthz` 預熱。

### 本機 Docker（選用）

```bash
docker compose up --build
# CORS 預設僅 localhost:5173
```

---

## 2. 部署 LIFF 前端（Cloudflare Pages）

1. Cloudflare Dashboard → **Workers & Pages** → **Create** → **Pages** → Connect Git。
2. 建置設定：

   | 欄位 | 值 |
   |------|-----|
   | Root directory | `web/liff` |
   | Build command | `npm ci && npm run build` |
   | Build output directory | `dist` |
   | Node version | `20`（環境變數 `NODE_VERSION=20`） |

3. **Production** 環境變數（建置時注入，見 [`deploy/env.liff.build.example`](../../deploy/env.liff.build.example)）：

   ```env
   VITE_LIFF_ID=<LINE Console 的 LIFF ID>
   VITE_API_BASE=https://grindscale-api.onrender.com
   ```

4. 部署後取得 Pages URL，例如 `https://grindscale.pages.dev`。
5. SPA：`public/_redirects` 已設定 `/* → /index.html`（Hash 路由 `#/home` 等）。

### 其他靜態託管

- **Vercel**：Root `web/liff`，Output `dist`，同上環境變數。
- **Netlify**：同上，並確認 SPA fallback 指向 `index.html`。

---

## 3. 串接順序（建議）

```mermaid
flowchart LR
  A[部署 API] --> B[設定 CORS_ORIGINS]
  B --> C[部署 Pages + VITE_API_BASE]
  C --> D[LINE Console Endpoint]
  D --> E[Rich Menu + 實機測試]
```

1. API 上線 → 設定 `CORS_ORIGINS` 為 Pages 網址。
2. Pages 上線 → `VITE_API_BASE` 指到 API。
3. 依 [LINE-CONSOLE.md](./LINE-CONSOLE.md) 設定 Mini App Endpoint。
4. 在 LINE 內開啟 `https://miniapp.line.me/<LIFF_ID>` 測試拍照與分析。

---

## 4. CORS 檢查清單

- [ ] `CORS_ORIGINS` 包含 Pages 的 **完整 origin**（含 `https://`，無尾斜線）。
- [ ] 本機開發時保留 `http://localhost:5173`（可寫成：`http://localhost:5173,https://xxx.pages.dev`）。
- [ ] 瀏覽器 DevTools → Network：`POST /v1/analyze` 無 CORS 錯誤。

---

## 5. 本機 HTTPS 隧道（LINE 測試，免雲端帳號）

不需先部署 Pages/Render，可用 ngrok 產生 **HTTPS Endpoint** 貼到 LINE Console：

```bash
chmod +x scripts/auto-line-tunnel.sh scripts/stop-tunnel.sh
./scripts/auto-line-tunnel.sh          # 前景執行
# 或背景：DETACH=1 ./scripts/auto-line-tunnel.sh
```

- 預設 API 埠 **8001**（避免與本機其他專案佔用 8000）；可改 `API_PORT=8002`
- 輸出網址寫入 `.grindscale-tunnel/last.env`
- 停止：`./scripts/stop-tunnel.sh`
- ngrok 免費版會有一次性「Visit Site」警告頁；LINE 內通常只出現一次

## 6. 本機一鍵開發（無隧道）

```bash
chmod +x scripts/run-dev.sh
./scripts/run-dev.sh
```

- API：`http://127.0.0.1:8000`
- LIFF：`http://127.0.0.1:5173`（Vite 代理 `/v1` → API）

---

## 7. 常見問題

| 現象 | 處理 |
|------|------|
| 分析一直轉圈後失敗 | API 休眠；先開 `/healthz` 或升級 Render 付費方案 |
| `Failed to fetch` | `VITE_API_BASE` 錯誤或未設 `CORS_ORIGINS` |
| LINE 內白屏 | Endpoint URL 須為 HTTPS；與 Pages 網域一致 |
| 硬幣未偵測 422 | 與 App 相同：白紙、硬幣與咖啡粉同框 |

---

## 8. 相關檔案

- [`render.yaml`](../../render.yaml)
- [`deploy/env.api.example`](../../deploy/env.api.example)
- [`deploy/env.liff.build.example`](../../deploy/env.liff.build.example)
- [`LINE-CONSOLE.md`](./LINE-CONSOLE.md)
