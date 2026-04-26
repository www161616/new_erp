---
title: TEST — order-entry「為分店叫貨」mode (Phase 5b 第二段)
module: Order / UI
status: draft
owner: alex.chen
created: 2026-04-26
---

# 測試清單 — order-entry 加 store_internal mode

把 5a-1 已 ship 的 `rpc_create_store_internal_order` 接到 UI 上：訂單登打 page 加「為分店叫貨」mode toggle，店長可直接 key 內部叫貨單（含 88 折定價）。客戶下單 mode 行為完全保留。

## Scope

- **改：** [apps/admin/src/app/(protected)/campaigns/order-entry/page.tsx](../apps/admin/src/app/(protected)/campaigns/order-entry/page.tsx)
- **不改 schema / 不改 RPC**（5a-1 已 ship）
- **依賴：** `rpc_create_store_internal_order` (5a-1 [PR #132](https://github.com/lt-foods/new_erp/pull/132)、`supabase/migrations/20260507000000_order_transfer_and_internal.sql`)

## 設計重點

- 預設 mode = `customer`（客戶下單），行為與舊版 100% 一致
- `internal` mode 共用同一份 SKU dropdown / autosave / Ctrl+S，但：
  * 隱藏 customer entries / channel selector
  * 顯示 store picker (active stores)、optional notes textarea
  * Items table 每列加可編輯 `unit_price` 欄（預設 = SKU list price）
- Submit 路由依 mode 二選一：
  * customer → `rpc_create_customer_orders` (既有)
  * internal → `rpc_create_store_internal_order` + `auth.getUser().id` 當 operator

## 1. UI 行為（preview 互動）

### 1.1 預設 mode + toggle
- [ ] page 載入時 mode = customer、UI 與 5b-1 之前一致（channel selector + customer cards 都在）
- [ ] 點「為分店叫貨」toggle：channel selector 與 customer cards 隱藏、store picker + 內部 items panel 顯示
- [ ] 切回「客戶下單」：UI 還原、原本的 entries 不被清掉（草稿不毀）

### 1.2 internal mode 必填驗證
- [ ] store 未選 + 點送出 → 顯示錯誤訊息「請選取貨店」、未呼叫 RPC
- [ ] store 已選但 items 為空 → 顯示錯誤訊息「請至少加一項商品」、未呼叫 RPC
- [ ] 任一 item qty <= 0 或非數字 → 該列邊框紅、送出顯示錯誤
- [ ] 任一 item unit_price < 0 → 該欄邊框紅、送出顯示錯誤
- [ ] item unit_price = 0 → 允許（業務允許 0 元贈品）

### 1.3 internal mode 加商品 + 編 unit_price
- [ ] 從「+ 加商品」dropdown 加一個 SKU、items table 出現該列、unit_price 預設 = SKU list price
- [ ] 直接編 unit_price 欄、值寫得進 state（小計即時更新）
- [ ] 加第二個 SKU、不可重複（dropdown 已不出現該選項）

### 1.4 internal mode 提交成功 (88 折)
**情境：** campaign 有 SKU list price 100；store_internal mode 加該 SKU、qty=10、unit_price=88、submit
**預期：**
- toast 顯示「已建立內部訂單」+ 新訂單編號（含 `-INT0001` suffix）
- DB：`customer_orders` 新增 1 筆 (member = STORE-{id}、pickup_store_id = 選的店、order_no LIKE '%-INT%')
- DB：`customer_order_items` 1 筆 unit_price = 88 (非 100)
- `customer_order_items.source = 'store_internal'`

```sql
SELECT o.order_no, o.pickup_store_id, m.member_no, oi.unit_price, oi.source
  FROM customer_orders o
  JOIN customer_order_items oi ON oi.order_id = o.id
  JOIN members m ON m.id = o.member_id
 WHERE o.campaign_id = <id>
   AND m.member_type = 'store_internal'
 ORDER BY o.id DESC LIMIT 5;
```

### 1.5 internal mode 同 campaign 同 store 二次提交（upsert）
**情境：** 1.4 之後、同店再 submit 另一 SKU qty=5
**預期：**
- 不新建 `customer_orders`、items 累加在原 order
- toast 訊息（複用「已建立內部訂單」即可，不需特別區分 update vs insert）

### 1.6 internal mode 不同 store
**情境：** 切到第二個 store、submit 同 campaign 同 SKU
**預期：** 新建一筆 `customer_orders`（不同 store_internal member、不同 pickup_store_id）

### 1.7 operator UUID 帶過去
- [ ] RPC payload `p_operator` = 當前 supabase auth user id（非 NULL、非 anon）
- [ ] `customer_orders.created_by = updated_by = p_operator`

### 1.8 草稿不混（internal mode 不寫 customer 草稿）
- [ ] internal mode submit 不影響 `localStorage.getItem('draft:order-entry:<id>')`
- [ ] 切 mode 時 customer 草稿仍在

## 2. Regression — 客戶下單 mode 不能壞

### 2.1 既有 happy path
- [ ] 載入 page、預設 customer mode、選 channel、加會員、加 SKU、Ctrl+S 送出
- [ ] 訂單成功建立（呼叫 `rpc_create_customer_orders`，非 `rpc_create_store_internal_order`）
- [ ] 沒有 console error / TS warning

### 2.2 Alt+N、Ctrl+S 鍵盤快捷
- [ ] customer mode：Alt+N 加新顧客、Ctrl+S 送出
- [ ] internal mode：Alt+N 應 no-op（沒有 customer card）、Ctrl+S 送出 internal 訂單

### 2.3 Draft autosave
- [ ] customer mode：30s autosave 寫 localStorage、refresh 後 prompt 還原
- [ ] internal mode：不寫 / 不讀 customer 草稿

### 2.4 SKU 搜尋共用
- [ ] internal mode 的 SKU dropdown 與 customer mode 的 ItemEditorRow 共用 `rpc_search_skus_for_campaign` 結果

## 3. RPC 行為健全性（5a-1 已 cover、本 PR 只快速回歸）

### 3.1 後端 unit_price 驗證
- [ ] 用 `psql` 直呼 `rpc_create_store_internal_order(..., p_items='[{"campaign_item_id":1,"qty":1,"unit_price":-5}]', ...)` → RAISE 'unit_price cannot be negative'
- [ ] `unit_price` 不傳 → fallback 到 `campaign_items.unit_price`

### 3.2 跨 tenant 拒絕
- [ ] 拿別 tenant 的 store_id 呼叫 → RAISE 或 RLS 拒絕

## 4. 驗收門檻

全部 §1-§3 勾完、**preview 無 console error**、**`npm run build` + type-check 過**、**git diff 無 customer mode 行為變動** 才可標 done。

## 5. 預期 diff 大小

- `apps/admin/src/app/(protected)/campaigns/order-entry/page.tsx` +200~300 / -0
- 不新建檔（避免 component 拆分讓 PR 膨脹）
- 完工後上 PR、補 wiki module 頁 + Home + Sidebar
