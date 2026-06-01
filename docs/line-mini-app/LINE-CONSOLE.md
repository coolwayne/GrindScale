# LINE 後台設定（台灣官方帳號 + Mini App）

依 [LINE Mini App Console 指南](https://developers.line.biz/en/docs/line-mini-app/discover/console-guide/) 與台灣 Messaging API 免費額度操作。實際畫面以 Console 為準。

---

## 前置條件

- [ ] LIFF 已部署至 **HTTPS**（見 [DEPLOY.md](./DEPLOY.md)）
- [ ] API 已上線且 `CORS_ORIGINS` 含 Pages 網域
- [ ] 已取得 `VITE_LIFF_ID` 對應的 LIFF ID

---

## 1. 建立 Messaging API Channel（官方帳號）

1. 登入 [LINE Developers Console](https://developers.line.biz/console/)。
2. 建立 **Provider**（若尚無）。
3. **Create a new channel** → **Messaging API**。
4. 地區選 **Taiwan**，填寫帳號名稱、說明、類別等。
5. 建立後在 **Messaging API** 分頁：
   - 記下 **Channel ID**、**Channel secret**（日後若啟用 ID Token 驗證會用到）。
   - 在 LINE Official Account Manager 連結此 Channel（Console 內有連結按鈕）。

**免費方案**：台灣帳號每月有免費則數；本 Mini App 僅開網頁分析，**不主動推播**則可長期維持低用量。

---

## 2. 建立 LINE Mini App

1. 同一 Provider 下 **Create a new channel** → **LINE Mini App**（或從 Mini App 專區建立）。
2. 填寫 App 名稱、說明、圖示（建議與 `splash.svg` 風格一致）。
3. **Endpoint URL**（必填）：

   ```
   https://<你的-pages專案>.pages.dev/
   ```

   - 必須 **HTTPS**。
   - 結尾斜線與 Console 要求一致即可；LIFF 使用 hash 路由（`#/home`）。
4. 儲存後取得 **LIFF ID**（或 Mini App 連結用的 ID），寫入 Cloudflare Pages 的 `VITE_LIFF_ID` 並 **重新建置**。

**對外連結格式**：

```
https://miniapp.line.me/<LIFF_ID>
```

開發時也可用 `https://liff.line.me/<LIFF_ID>`（依 Console 顯示為準）。

---

## 3. 綁定官方帳號與 Mini App

1. 在 **LINE Official Account Manager** 選擇你的帳號。
2. 設定 → **LINE Mini App** / **連結的 Mini App**（名稱依介面版本可能不同）。
3. 選擇步驟 2 建立的 Mini App channel。

---

## 4. Rich Menu（選單「粒徑分析」）

1. Official Account Manager → **Rich menus** → 建立選單。
2. 上傳 2500×843 圖（可單一大按鈕「粒徑分析」）。
3. 動作類型：**Link**，URI：

   ```
   https://miniapp.line.me/<LIFF_ID>
   ```

4. 設為預設選單並發布。

API 建立範例 JSON 見 [`rich-menu-example.json`](./rich-menu-example.json)（需搭配 Messaging API 上傳圖片與 `createRichMenu`）。

---

## 5. 實機測試清單

在 **iOS / Android LINE App** 內（勿只用桌面瀏覽器）：

- [ ] 從 Rich Menu 或聊天室連結開啟 Mini App
- [ ] `liff.init` 成功（首頁顯示暱稱，非「請在 LINE 內開啟」）
- [ ] 選擇沖煮方式 → 拍照 → 分析完成 → 直方圖與疊圖
- [ ] 硬幣未入鏡時顯示「未偵測到硬幣」類錯誤
- [ ] CSV 下載、歷史紀錄（localStorage）
- [ ] 首次開啟若 API 休眠，約 30–60 秒內可完成分析

**開發模式**：未設 `VITE_LIFF_ID` 時仍可於瀏覽器測 UI，但無法測 LINE 相機與關閉視窗。

---

## 6. 隱私與審核（Phase 4）

- [ ] 應用內 **隱私權政策**：`#/privacy`（已內建簡版，上線前請依實際營運修訂）
- [ ] 官方帳號說明欄可放政策連結：`https://<pages>/#/privacy`
- [ ] 若申請 **Verified Mini App**：準備隱私政策 URL、截圖、測試帳號說明

---

## 7. 環境變數對照

| 位置 | 變數 | 說明 |
|------|------|------|
| Cloudflare Pages | `VITE_LIFF_ID` | Console 的 LIFF ID |
| Cloudflare Pages | `VITE_API_BASE` | Render API 根 URL |
| Render | `CORS_ORIGINS` | Pages origin |
| Render（選用） | `LINE_CHANNEL_ID` | 啟用 token 驗證時 |
| Render（選用） | `REQUIRE_LIFF_TOKEN=true` | Phase 4 |

---

## 8. 疑難排解

| 問題 | 可能原因 |
|------|----------|
| 外開瀏覽器顯示「請在 LINE 內開啟」 | 預期行為；用 LINE 開啟 |
| Endpoint 審核失敗 | 非 HTTPS、憑證錯誤、或網域與部署不一致 |
| 拍照按鈕無反應 | 非 LINE WebView；或權限被系統拒絕 |
| API 401/403 | 若已開 `REQUIRE_LIFF_TOKEN`，前端需送 Authorization（尚未實作） |

完成 Phase 3 後，可在 [DESIGN.md](./DESIGN.md) Phase 3 勾選項目打勾。
