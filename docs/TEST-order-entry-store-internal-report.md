---
title: TEST 報告 — order-entry 加「為分店叫貨」mode (Phase 5b 第二段)
module: Order / UI
status: passed
ran_at: 2026-04-26
verified_by: alex.chen + claude (preview tools + REST 直查)
---

# 驗證報告 — Phase 5b 第二段（order-entry 加 store_internal mode）

## Scope

- 改：[apps/admin/src/app/(protected)/campaigns/order-entry/page.tsx](../apps/admin/src/app/(protected)/campaigns/order-entry/page.tsx) (+~250 / -10)
  - 加 `Mode = "customer" | "internal"` toggle state
  - 加 `Store` 載入（與 channels parallel）
  - 加 internal-only state：`internalStoreId / internalNotes / internalItems`
  - `ItemEditorRow` 加 `editablePrice` prop（unit_price 可改）
  - 加 `submitInternal()` → 呼叫 `rpc_create_store_internal_order` + `auth.getUser().id`
  - 加 `InternalOrderPanel` component（store picker + notes + items + submit）
  - Alt+N 在 internal mode 加新空白項目列
- 不改 schema、不改 RPC（5a-1 [#132](https://github.com/lt-foods/new_erp/pull/132) 已 ship）

## RPC 呼叫

`rpc_create_store_internal_order(p_campaign_id, p_store_id, p_items[], p_operator, p_notes)`

UI 邏輯：
- `p_operator = sb.auth.getUser().user.id`（未登入則錯）
- `p_items[].unit_price` 永遠帶（即便 = list price）— UI 已 prefill 預設值
- `p_notes = trim() || null`

## 結果

| 測項 | 結果 | 證據 |
|---|---|---|
| `npm run build` 通過 | ✅ PASS | TypeScript 4.8s、Static export 23 routes |
| 載入 page、預設 customer mode | ✅ PASS | 看到「LINE 頻道」hint + customer cards |
| 點「為分店叫貨」toggle | ✅ PASS | 顯示「內部叫貨...」hint + store/notes/items panel + 「送出內部訂單」 |
| Alt+N 提示文字切換 | ✅ PASS | customer mode 顯示「新顧客」、internal mode 顯示「新項目」 |
| 必填驗證：未選店 + submit | ✅ PASS | 顯示紅色「請選取貨店」、未呼叫 RPC |
| 必填驗證：店選了但 items 空 + submit | ✅ PASS | 顯示「請至少加一項商品」 |
| 加 SKU、預設 unit_price = list price | ✅ PASS | 蝦餅 SKU list price 135、加入後 input 預填 135 |
| 改 unit_price = 88、subtotal 即時更新 | ✅ PASS | qty=1 × unit=88 → 小計 $88 |
| 提交 88 折訂單 | ✅ PASS | DB 出現 unit_price=88、source=store_internal、member_no=STORE-2、pickup_store_id=2 |
| 多次 submit upsert 到同 order | ✅ PASS | 同 campaign+store 4 筆 items 全在 order_id=46 (campaign_id=10、channel_id=9、member STORE-2) |
| Submit 成功 form 重置 | ✅ PASS | qty 變空、unit_price 變 0、件數變 0 |
| Toggle 切回 customer mode UI 還原 | ✅ PASS | Customer search input + 新增顧客 button + 送出訂單 button 全部回來 |
| 無 console error | ✅ PASS | preview_console_logs(level=error) → No console logs |

## DB 證據

`customer_orders id=46` (campaign_id=10、channel_id=9、pickup_store_id=2、member STORE-2) 包含 4 筆 items：

```json
[
  {"qty":1,  "unit_price":135, "source":"aid_transfer"},   // 5b-1 早期測試
  {"qty":1,  "unit_price":88,  "source":"store_internal"}, // 5b-2 第一次
  {"qty":1,  "unit_price":135, "source":"store_internal"}, // 5b-2 default price
  {"qty":10, "unit_price":88,  "source":"store_internal"}  // 5b-2 final 88 折
]
```

`order_no = 351128090-TF0005`（沿用 5b-1 既有 order，未新建 — RPC upsert 行為符合預期）

## 設計決策

- **Order_no 不一定 `-INT`**：若 campaign+channel+member 已有 order，append items 而非新建。`-INT` suffix 只在新建時加（RPC 內 `if v_order_id IS NULL then ... v_campaign_no || '-INT' || lpad(v_seq::text, 4, '0')`）
- **Mode toggle 不毀草稿**：customer entries 與 internal items 是獨立 state、互不影響
- **operator 來源**：`sb.auth.getUser().user.id` 而不傳 NULL — RPC SECURITY DEFINER 不會自動帶 auth.uid()

## 未驗證（risk-assessed）

| 測項 | 原因 |
|---|---|
| customer mode happy path 完整 submit | 程式邏輯未改（only branch added at top of handleSubmit）、build 過、UI 切回正常顯示 |
| ItemEditorRow `editablePrice=false` 行為 | customer mode 共用同一 component、未傳該 prop = `undefined`（falsy）→ 走 readonly span 分支、與舊版完全一致 |
| 跨 tenant store_id 拒絕 | RPC 5a-1 已 cover (D5 PASS) |
| unit_price 負數 RPC 端拒絕 | RPC 5a-1 已 cover、UI 端也擋了 (`if (items.some((i) => i.unit_price < 0))`) |
