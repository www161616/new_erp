---
title: PRD - LIFF 前端（顧客端）
module: LIFF
status: draft-v0.1
owner: alex.chen
created: 2026-04-21
tags: [PRD, ERP, LIFF, LINE, Frontend, 顧客端]
---

# PRD — LIFF 前端（顧客端網頁）

> **定位**：顧客端在 LINE 內開啟的網頁應用，取代原生 APP。提供會員 QR、訂單查詢、取貨確認、社群暱稱綁定等功能。
>
> **加盟店模式**：共用單一 LIFF channel，URL 帶 `store_id` 參數區分顧客是從哪店 OA 進入。
>
> v0.1 checklist 版。

---

## 1. 模組定位

- [ ] **顧客端唯一前端**（v1）：會員服務、訂單查詢、取貨確認、綁定設定
- [ ] **加盟店模式設計**：同一個 LIFF 被 100+ 家加盟店 OA 共用、用 URL query 區分 store
- [ ] **消費 ERP 後端 API**：Supabase auto-gen REST + RPC，不自建 server
- [ ] **不做行銷 / 促銷頁**（v1，屬行銷模組 P2）
- [ ] **不做下單功能**（v1，顧客下單仍靠 LINE 社群 `+N` 留言；P2+ 才考慮 APP / LIFF 下單）

---

## 2. 核心架構

```
┌─────────────────────────────────────────────────────────────┐
│ 顧客手機 LINE App                                           │
│                                                             │
│   ↓ 加入 A 店 LINE OA → OA 推播連結                         │
│   ↓ https://liff.line.me/{LIFF_ID}?store=a_store_id         │
│                                                             │
│ LIFF 網頁（共用）                                           │
│   · liff.init() 取得 LINE context                           │
│   · 從 URL 取 store_id                                      │
│   · liff.getIDToken() → 送後端驗證                          │
│   · 呼叫 Supabase API（含 store_id 上下文）                 │
│                                                             │
│             ↓                                               │
│ Supabase Edge Function: /liff/session                       │
│   · 驗證 LIFF ID Token（JWK verify）                        │
│   · 依 line_user_id + store_id 查 member_line_bindings      │
│   · 發 Supabase JWT（含 tenant_id / store_id / member_id）  │
│                                                             │
│             ↓                                               │
│ LIFF 呼叫 Supabase API（帶新 JWT）                          │
│   · RLS 自動限 tenant + store + member 範圍                 │
│   · 取餘額、訂單、點數、QR payload 等                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 名詞定義

- [ ] **LIFF（LINE Front-end Framework）**：LINE 提供的 SDK，讓網頁能在 LINE App 內開啟並取得 user_id
- [ ] **LIFF ID**：LINE Dev 後台申請的 LIFF 應用識別碼
- [ ] **ID Token**：LIFF 給的 JWT，含 `sub=line_user_id`、後端驗證
- [ ] **Store Context**：URL 帶 `?store=<store_id>` 決定顧客是哪店的會員
- [ ] **動態 QR**：會員卡 QR code，每 60 秒刷新（Member Q3 決策）
- [ ] **Session JWT**：系統自己發的 token，含 tenant/store/member 資訊供 RLS 使用

---

## 4. Goals

- [ ] G1 — 顧客從 LINE OA 點連結開啟 LIFF 全程 < 2 秒
- [ ] G2 — 會員 QR 顯示 < 500ms（含 HMAC 簽章產生）
- [ ] G3 — 首次進入自動綁定 `member_line_bindings` 成功率 > 95%
- [ ] G4 — 歷史訂單載入 < 1 秒（最近 3 個月）
- [ ] G5 — UI 響應式、支援 iOS / Android LINE 內瀏覽器

---

## 5. Non-Goals（v1 不做）

- [ ] ❌ **下單 / 購物功能**（v1 仍透過 LINE 社群 `+N`；P2+ 才評估）
- [ ] ❌ **促銷 / 行銷活動頁**（屬行銷模組 P2）
- [ ] ❌ **即時客服 / 留言**（LINE OA 直接對話即可）
- [ ] ❌ **瀏覽商品目錄**（顧客從 LINE 社群看商品貼文、不重複做）
- [ ] ❌ **儲值金加值**（v1 在門市現金加值、不透過 LIFF）
- [ ] ❌ **點數折抵操作**（在門市結帳時由店員操作）
- [ ] ❌ **P2P 分享**（顧客傳訊邀好友）
- [ ] ❌ **推送設定細分 opt-out**（通知模組 Non-Goals 已定）
- [ ] ❌ **多語系**（v1 中文即可）
- [ ] ❌ **離線 PWA**（LIFF 本來就靠 LINE 連網）

---

## 6. User Stories

### 首次使用者（剛加 OA）
- [ ] 作為顧客，我掃 A 店 LINE OA QR 加好友後、OA 自動發一條「歡迎！點此完成會員綁定」
- [ ] 我點連結 → LIFF 開啟 → 提示我輸入手機號碼綁定會員
- [ ] 系統找到既有會員（A 店） → 綁定成功 → 進入主畫面
- [ ] 系統找不到會員 → 提示「申辦新會員」→ 填姓氏 + 生日 → 建檔 + 綁定

### 一般會員
- [ ] 作為 A 店會員，我要看到**我的會員 QR**（到門市取貨時給店員掃）
- [ ] QR 每 60 秒自動刷新、畫面顯示倒數
- [ ] 我要查「我在 A 店的**點數餘額**」+「點數流水」
- [ ] 我要查「我在 A 店的**儲值金餘額**」+「儲值金流水」
- [ ] 我要查「我的**進行中訂單**」（campaign 名稱 / 商品 / 狀態 / 取貨期限）
- [ ] 我要查「歷史訂單」最近 3 個月
- [ ] 我要看「會員等級」（銅 / 銀 / 金 / 鑽）+ 升等進度
- [ ] 我要看「下次到期點數」提醒（例：2027/12/31 到期 500 點）

### 跨店顧客
- [ ] 作為同時是 A 店和 B 店的會員，我要能從 A 店 OA 進 LIFF → 看 A 店資料；從 B 店 OA 進 → 看 B 店資料
- [ ] 我要清楚看到「目前檢視：A 店」標示、避免混淆
- [ ] 切換店家：**無功能**（v1 不提供 LIFF 內切換、要從對應店的 OA 重新進）

### 社群暱稱綁定
- [ ] 作為顧客，我在 LIFF 可設定「我在 A 店 LINE 社群的暱稱」= 涂003886
- [ ] 系統存 `customer_line_aliases`，下次小幫手登打 `+N` 時自動帶我的會員

### 身份更新
- [ ] 我要能在 LIFF 改自己的姓名、生日、Email
- [ ] 我不能改手機號（要請店員協助 or 電聯）
- [ ] 我可以退訂 OA（LINE 內封鎖本 OA）→ 系統自動標記 `status = blocked`

---

## 7. Functional Requirements

### 7.1 LIFF 初始化 + Session 取得

- [ ] 頁面載入 → `liff.init({ liffId })` → 取得 profile + context
- [ ] 從 URL 取 `store_id`（若無 → 顯示錯誤「請從 LINE 官方帳號連結進入」）
- [ ] 呼叫 `liff.getIDToken()` 取得 ID Token
- [ ] POST `/functions/v1/liff-session` with `{ id_token, store_id }`
- [ ] Edge Function 驗證 ID Token（LINE JWK）、查 `member_line_bindings` 是否已綁
  - 已綁 → 發 Supabase JWT（含 tenant_id / store_id / member_id / line_user_id）
  - 未綁 → 發 temp JWT + 引導綁定流程
- [ ] LIFF 存 JWT 到 sessionStorage、後續 Supabase 呼叫帶

### 7.2 首次綁定流程（未綁會員）

```
進入 LIFF (未綁) → 顯示「歡迎！請輸入手機完成會員綁定」
  ↓
輸入手機 → POST /functions/v1/bind-member { phone, store_id, line_user_id }
  ↓
  ├ 查 members where (tenant, store, phone_hash) → 找到 → 綁定 + 成功
  ├ 找不到 → 顯示「是否申辦 A 店新會員？」→ 是 → 輸入姓氏+生日 → 建檔 + 綁定
  └ 驗證失敗 → 顯示錯誤
```

- [ ] 手機號驗證：透過 OTP 或簡訊驗證（v1 可先信任、P1 加 OTP）
- [ ] 建檔欄位最小化：手機 + 姓氏 + 生日（依會員 PRD Q1 已決）
- [ ] 綁定成功 → 寫 `member_line_bindings` + 重發 JWT（含 member_id）

### 7.3 會員主畫面

Layout：
```
┌─────────────────────────────────────┐
│ 🏪 A 店           (店名、logo)       │  ← store context 明顯
├─────────────────────────────────────┤
│                                     │
│       [ 動態 QR Code ]              │  ← 會員卡 QR
│       王小明 / 金卡                 │
│       剩 45 秒刷新                  │  ← 倒數
│                                     │
├─────────────────────────────────────┤
│ 💰 儲值金  $2,500    │ ⭐ 點數 850 │
├─────────────────────────────────────┤
│ 📦 進行中訂單 (2)                    │
│   · 保鮮袋 × 3  到貨待取 截止 5/10 │
│   · 草莓禮盒 × 1  預購中 結單 5/3  │
├─────────────────────────────────────┤
│ 🔗 社群暱稱：涂003886 [編輯]       │
├─────────────────────────────────────┤
│ [ 歷史訂單 ]  [ 點數流水 ]         │
│ [ 儲值金流水 ] [ 個人資料 ]        │
└─────────────────────────────────────┘
```

- [ ] 頂部明確顯示 `store_id` 對應的店名 / logo
- [ ] 動態 QR 區塊：
  - 呼叫 `/functions/v1/member-qr?member_id=xxx` 取 payload
  - 每 60s 自動刷新（不用使用者手動）
  - 畫面可見倒數計時
- [ ] 餘額區：呼叫 `supabase.rpc('rpc_resolve_member', ...)` 即時取
- [ ] 進行中訂單：最多顯示 3 筆、以「取貨期限」升序

### 7.4 動態 QR 產生 + 驗證

- [ ] `/functions/v1/member-qr?member_id=xxx`：
  - 產 `nonce = randomUUID()`、`exp_ts = NOW() + 60s`
  - 取 store OA HMAC secret（從 Vault）
  - `sig = HMAC_SHA256(secret, f"{tenant}|{store}|{member_id}|{nonce}|{exp_ts}")`
  - Return JSON：`{ payload: { type:"member", tenant, store, member_id, nonce, exp_ts, sig } }`
- [ ] LIFF 將 JSON 轉 QR（前端庫如 `qrcode.js`）
- [ ] 店員掃碼 → POS → Edge Function 驗證 → 回 `member_id`

### 7.5 訂單查詢

- [ ] 「進行中」：`customer_orders WHERE member_id = ? AND status IN ('draft','confirmed','partially_ready','ready','partially_picked_up') ORDER BY pickup_deadline_at`
- [ ] 「歷史」：`status IN ('completed','expired','cancelled') AND created_at > NOW() - INTERVAL '3 months'`
- [ ] 每筆顯示：訂單號、活動名、商品摘要、數量、金額、狀態、取貨期限 / 完成日
- [ ] 點擊進詳情頁：
  - 完整明細（SKU 列表）
  - 付款狀態（v1 取貨才付、會顯示「現場結清」）
  - 取貨地點（店名 + 地址 + 電話）
  - 來源截圖（若 P1 LLM 解析有存）

### 7.6 取貨確認（Scan flow）

- [ ] 顧客在門市 → 給店員看動態 QR → 店員 POS 掃
- [ ] POS 建立 `pos_sale` + 扣庫存 + 賺點 + 釋放 reserved
- [ ] LIFF 端**不做**取貨確認操作（屬店員端）— 只被動顯示訂單狀態
- [ ] LIFF 拉新訂單狀態時看到 `status = completed`

### 7.7 社群暱稱綁定

- [ ] LIFF 設定頁：
  - 顯示目前綁定狀況（若有 `customer_line_aliases` 紀錄）
  - 輸入暱稱 → 存 `customer_line_aliases (tenant, channel_id, nickname, member_id)`
  - 如何知道 `channel_id`？→ 依 `store_id` 對應該店的主要 LINE 社群（`locations.line_community_channel_id`）
- [ ] 一店可能多社群 → 顧客選 / 系統預設

### 7.8 個人資料管理

- [ ] 可改：姓名、Email、生日、性別（若允許）
- [ ] **不可改**：手機號（要實體門市處理）
- [ ] GDPR 權利：可在此頁點「申請刪除帳號」→ 寄 Email 給總部處理（**v1 手動處理、不自動執行** rpc_member_gdpr_delete）

### 7.9 認證 & Session 管理

- [ ] LIFF session 有效 24 小時（超過要重新 `liff.getIDToken()`）
- [ ] 後端 Supabase JWT 1 小時、自動 refresh
- [ ] 顧客封鎖 OA → 下次 LIFF 驗證失敗（取不到 ID Token）→ 提示「請先加入本店 LINE OA」

---

## 8. 非功能需求（NFR）

- [ ] **效能**：LIFF 初始化 < 2s；每個 API 呼叫 P95 < 300ms
- [ ] **可用性**：支援 LINE App iOS / Android 最新 2 個版本
- [ ] **安全**：
  - ID Token 必經後端驗證（不信任前端）
  - QR payload 必含 HMAC（防偽造）
  - RLS 隔離（顧客只能看自己的資料）
- [ ] **隱私**：
  - 不存 LINE profile picture / display name 到本系統（只存 `line_user_id`）
  - 顯示他人資料時一律 masked
- [ ] **響應式**：iPhone SE (320px) 到 iPad Pro (1024px) 皆可讀
- [ ] **觀察性**：
  - LIFF 端錯誤上報（Sentry 或類似）
  - Edge Function latency / error rate 監控

---

## 9. 技術棧（建議）

- **框架**：Next.js 14+ (App Router) / React 18
- **樣式**：Tailwind CSS + shadcn/ui（或類似）
- **LIFF SDK**：`@line/liff` 官方套件
- **Supabase**：`@supabase/supabase-js`
- **QR**：`qrcode` npm package
- **部署**：Vercel 或 Netlify（自動 SSL）
- **獨立 repo**：`new_erp_liff`（跟主 ERP 分離）

---

## 10. 權限（RBAC / RLS）

- [ ] LIFF 顧客**僅看**自己的資料（透過 Supabase JWT 帶 `member_id`）
- [ ] RLS policy 範例：
  ```sql
  CREATE POLICY liff_own_orders ON customer_orders FOR SELECT USING (
    member_id = (auth.jwt() ->> 'member_id')::bigint
    AND tenant_id = (auth.jwt() ->> 'tenant_id')::uuid
  );
  ```
- [ ] 不允許 LIFF 直接 UPDATE / DELETE（一切靠 RPC）
- [ ] 敏感 RPC（如 rpc_wallet_topup）LIFF 不能呼叫 — 只能門市端執行

---

## 11. 與其他模組整合

- [ ] **會員模組**：`rpc_resolve_member`、`member_line_bindings`、動態 QR HMAC 邏輯
- [ ] **訂單取貨模組**：讀 `customer_orders` + `customer_order_items`
- [ ] **商品模組**：讀商品名 / 售價（呈現訂單明細用）
- [ ] **通知模組**：LIFF 不直接發通知、但顯示「最近收到的通知」（讀 `notification_logs` where recipient = self）
- [ ] **店家主檔**（待擴充 `locations` 欄位）：讀店名、logo、地址、LINE 社群 channel

---

## 12. 驗收準則（Acceptance Criteria）

- [ ] 首次掃 A 店 OA QR → 加好友 → LINE 跳 LIFF 連結 → 點擊 → 2 秒內載入
- [ ] 輸入手機 → 成功找到會員 → 綁定寫入 `member_line_bindings`
- [ ] 主畫面顯示 A 店標示 + QR + 餘額 + 訂單
- [ ] QR 顯示後 60 秒自動刷新（新 payload、新 sig）
- [ ] 店員用 POS 掃此 QR → 後端驗簽通過 → 辨識會員成功
- [ ] 顧客改姓名 → 即時寫 DB、下次載入顯示新姓名
- [ ] 同顧客從 B 店 OA 連結進入 → 看到的是 B 店會員資料（member_id 不同）
- [ ] 顧客封鎖 OA → 再次開 LIFF → 顯示「請先加入本店」
- [ ] 在 iPhone / Android LINE 內測試皆正常

---

## 13. Open Questions

### LIFF 技術
- [ ] **Q1 LIFF 申請方**：總部一次申請、全加盟店共用？還是每加盟店自己申請？（推薦總部申請共用）
- [ ] **Q2 手機 OTP 驗證**：綁定時是否需簡訊驗證？成本 vs 安全 tradeoff
- [ ] **Q3 Session 存放**：sessionStorage vs Supabase Auth cookie？
- [ ] **Q4 LIFF size**：full / tall / compact 哪個？（影響 UI layout）

### 流程 / UX
- [ ] **Q5 新會員申辦欄位**：手機 + 姓氏 + 生日 夠嗎？要加 Email？
- [ ] **Q6 忘記手機**：顧客換號碼 → 可以自助改嗎？還是必須到門市？
- [ ] **Q7 主畫面訂單顯示筆數**：3 筆 / 5 筆 / 無限捲動？
- [ ] **Q8 歷史訂單保留期限**：3 個月 / 6 個月 / 永久？（與會員模組 7 年對齊？）

### 整合
- [ ] **Q9 LIFF URL 欄位**：`locations.liff_url` 還是 `tenant_settings.liff_url`？加盟店是否可自訂？
- [ ] **Q10 HMAC secret 儲存**：Supabase Vault 還是 env var？
- [ ] **Q11 社群 channel 對應**：`locations.line_community_channel_id`（需新增）— 一店多社群怎處理？

### 未來擴充
- [ ] **Q12 LIFF 下單功能**：P2+ 是否開放在 LIFF 下單（取代社群 `+N`）？預留設計點
- [ ] **Q13 多語系**：v1 中文、P1 是否要英文？
- [ ] **Q14 P2+ 整合原生 APP**：APP 推出後，LIFF 還保留嗎？還是停用？

---

## 14. 下一步

- [ ] 回答 Q1~Q14 → 進入 v0.2
- [ ] 申請 LIFF（LINE Dev 後台）、取 LIFF ID
- [ ] 建 `new_erp_liff` repo（Next.js scaffold）
- [ ] Spike：LIFF SDK 整合、LIFF → Supabase Edge Function 驗證流程
- [ ] Spike：動態 QR HMAC 產生 + POS 驗證端到端
- [ ] 設計 wireframe / mockup（主畫面 + 綁定流程）

---

## 相關連結

- [[PRD-會員模組]] — member_line_bindings、QR 驗證規範
- [[PRD-訂單取貨模組]] — 訂單查詢來源
- [[PRD-通知模組]] — 加盟店 OA 對應、每店 LIFF 入口
- [[PRD-銷售模組]] — 取貨結算後狀態更新
- [LIFF 官方文件](https://developers.line.biz/en/docs/liff/)
- [專案總覽](Home)

---

## 本 PRD 吸收的既有決策（跨模組）

- **加盟店模式**：共用 LIFF channel + URL 帶 `store_id`
- **會員分店獨立**：LIFF 進 A 店 ≠ 進 B 店，`member_id` 不同
- **動態 QR 60s 刷新**（會員 Q3）+ HMAC 簽章（會員 Q11）
- **不做下單**（訂單模組 Non-Goals、P2+ 原生 APP 時再談）
- **不做 SMS / Email**（通知模組決策）— OTP 驗證是 P1
- **社群暱稱綁定**：LIFF 提供 self-service 補綁 entry（訂單 Q8）
- **GDPR 申請刪除**：LIFF 提交、總部手動處理（會員 Q13）
- **技術棧**：Next.js + Supabase（跟主系統一致）
