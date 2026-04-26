---
title: TEST — rpc_receive_transfer
module: Inventory / Transfer
status: draft
owner: alex.chen
created: 2026-04-26
---

# 測試清單 — `rpc_receive_transfer`

分店端確認收貨：把 `transfers.status='shipped'` 推進到 `'received'`、寫 `transfer_items.qty_received`、對 dest_location 做 `transfer_in` stock_movement。

## Scope

- Migration：`supabase/migrations/20260504000000_rpc_receive_transfer.sql`
- 上游：`generate_transfer_from_wave` 產生的 `WAVE-{wave_id}-S{store_id}` TR (status='shipped')
- 下游（本 PR 不含）：分店收貨 UI

## Schema 假設（已存在、不改）

- `transfers.status` enum 包含 `'received'`
- `transfer_items.qty_received` / `in_movement_id` 欄位存在
- `transfer_items.qty_variance` 是 `qty_received - qty_shipped` 的 generated stored column
- `stock_movements.movement_type` 包含 `'transfer_in'`

## 簽章

```sql
rpc_receive_transfer(
  p_transfer_id BIGINT,
  p_lines       JSONB,   -- [{transfer_item_id: BIGINT, qty_received: NUMERIC}, ...] 或 NULL = 全收 (qty_received = qty_shipped)
  p_operator    UUID,
  p_notes       TEXT DEFAULT NULL
) RETURNS JSONB
-- { transfer_id, items_received: int, total_qty_received: numeric, total_variance: numeric }
```

## 測試項目

### A. Happy path — 全收

- [ ] A1：`p_lines=NULL` 時，每行 `qty_received := qty_shipped`
- [ ] A2：每行寫入 1 筆 `transfer_in` stock_movement 至 `dest_location`，`source_doc_type='transfer'`、`source_doc_id=transfer_id`
- [ ] A3：`stock_movements.unit_cost` 沿用對應 `out_movement` 的 unit_cost（保持成本流）
- [ ] A4：`transfer_items.in_movement_id` 寫入新 movement id
- [ ] A5：`transfers.status='received'`、`received_by=p_operator`、`received_at=NOW()`
- [ ] A6：dest_location 的 `stock_balances.on_hand` 增加對應 qty
- [ ] A7：返回 JSONB 含 `items_received` / `total_qty_received` / `total_variance=0`

### B. Happy path — 部分收（短收）

- [ ] B1：`p_lines` 指定 `qty_received < qty_shipped` → 該行寫入該 qty
- [ ] B2：`qty_variance` (generated) 自動算為負值
- [ ] B3：`transfer_in` stock_movement 只進實收 qty
- [ ] B4：status 仍轉 `'received'`（短收不卡單）
- [ ] B5：返回 JSONB 中 `total_variance < 0`

### C. 邊界 / 錯誤

- [ ] C1：transfer 不存在 → `RAISE EXCEPTION 'transfer % not found'`
- [ ] C2：transfer status ≠ 'shipped'（draft / received / cancelled）→ `RAISE EXCEPTION 'transfer % is in status %, expected shipped'`
- [ ] C3：`qty_received < 0` → exception
- [ ] C4：`qty_received > qty_shipped`（過收）→ exception（避免無中生有）
- [ ] C5：`p_lines` 內含不屬於本 transfer 的 `transfer_item_id` → exception
- [ ] C6：`p_lines` 漏掉某 transfer_item（不全列出）→ 該行視為全收 `qty_received = qty_shipped`（與 A1 一致的 default）
- [ ] C7：concurrent 兩支 RPC 同 transfer_id → 第二支拿不到 lock，後執行者看到 status 已轉 received → exception（advisory lock 或 SELECT FOR UPDATE）

### D. 與既有 wave 鏈路整合

- [ ] D1：完整鏈路 wave open → picked → ship（generate transfers）→ rpc_receive_transfer → 庫存從 HQ 流到 store，`stock_movements` 兩筆對應（transfer_out @ HQ + transfer_in @ store）
- [ ] D2：`v_pr_progress` view 不受影響（如果有用 transfers.status 的話）
- [ ] D3：append-only 約束：transfer 已 received，再呼叫 rpc_receive_transfer → C2 擋住

### E. RLS / 權限（後續 UI 才驗，本 RPC 是 SECURITY DEFINER）

- [ ] E1：RPC GRANT EXECUTE TO authenticated
- [ ] E2：應用層由 UI 傳 p_operator（後續 admin / 店長 RLS 在 UI 層 / view 層處理）

## 不在範圍

- 短收處理流程（補單 / 退款 / claim 對 carrier）— 短收只記錄 variance，後續處理另案
- 收貨 UI（下個 PR）
- 月結算金流（PRD §3.5）— 那是另一條線
