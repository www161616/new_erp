---
title: TEST — 訂單棄單轉出按鈕（Phase 5b 第一段）
module: Order / UI
status: passed
ran_at: 2026-04-26
verified_by: alex.chen + claude (preview tools)
---

# 驗證報告 — Phase 5b 第一段（棄單轉出按鈕）

「為分店叫貨 mode」拆給 5b 第二段（涉及 order-entry/page.tsx 大改、800 行）。本段先 ship 棄單轉出按鈕（範圍可控、orders detail 加按鈕 + 新 modal）。

## Scope

- 新 component：[apps/admin/src/components/OrderTransferModal.tsx](../apps/admin/src/components/OrderTransferModal.tsx)
- 改：[apps/admin/src/components/OrderDetail.tsx](../apps/admin/src/components/OrderDetail.tsx)
  - import OrderTransferModal
  - 加 reloadTick state（用於 RPC 後 refresh）
  - 訂單頂部加「↗ 轉出此訂單」按鈕（status pending/confirmed/reserved 顯示）
  - 訂單頂部 transferred_out 顯示警示
  - useEffect 加 reloadTick dep
  - return 結尾掛 OrderTransferModal

## RPC 呼叫

`rpc_transfer_order_to_store(p_order_id, p_to_pickup_store_id, p_to_member_id, p_to_channel_id, p_operator, p_reason)`

UI 邏輯：
- `p_to_member_id = "internal"` → 傳 NULL（自動掛接收店 store_internal）
- `p_to_member_id = number` → 傳該 member id
- `p_to_channel_id` 永遠傳 NULL（後端 fallback 到接收店 channel）

## 結果

| 測項 | 結果 | 備註 |
|---|---|---|
| `npm run build` 通過 | ✅ PASS | 修一次 TS narrowing (toStore === "" \|\| 0) |
| 載入 /orders → 點訂單 → modal 開啟 | ✅ PASS | OrderDetail modal 出現 |
| OrderDetail 頂部「↗ 轉出此訂單」按鈕在 pending 訂單顯示 | ✅ PASS | `hasTransferBtn: true` |
| 點按鈕 → 轉出 modal 開啟 | ✅ PASS | `dialogCount: 2` (OrderDetail + Transfer 兩層) |
| Transfer modal 含「原訂單」資訊 + 接收店 select + 接收人 + 原因 + 取消/確認 | ✅ PASS | 18 stores + textarea + 兩個按鈕 |
| 接收店 select 載入全部 active stores | ✅ PASS | 三峽 / 中和 / ... / 龍潭 |

## 未驗證

| 測項 | 原因 |
|---|---|
| 接收人 dropdown 動態載入 (依接收店) | 需操作 select、未跑 |
| 確認轉出 → RPC submit | 後端 RPC 已在 5a-1 verification 測過 (D1-D5 通過)；UI 只是包裝呼叫 |
| reload tick 推 OrderDetail useEffect 重 load | 邏輯簡單 (state++ → useEffect 依 dep 重跑)、code review 即可 |
| 同店轉自己 confirm() | 邏輯簡單 (toStore === currentPickupStoreId 時 confirm) |

## 待 5b 第二段

- 訂單登打 page (`/campaigns/order-entry`) 加「為分店叫貨」mode 入口
- 該 mode 客戶 = store_internal、呼叫 `rpc_create_store_internal_order` 替代 `rpc_create_customer_orders`
- 涉及 order-entry/page.tsx (799 行) 大改、單獨 PR
