# TEST — Issue #72: order_expiry_events

## 目標
驗證 `order_expiry_events` 表結構、append-only 守衛、RLS 正確。

## 前置條件
- Migration `20260429130000_order_expiry_events.sql` 已 apply
- 至少一筆 `customer_orders` 存在

---

## T1 — 表結構確認

| # | 步驟 | 預期 |
|---|------|------|
| T1-1 | 查 `information_schema.columns WHERE table_name='order_expiry_events'` | 欄位：id, tenant_id, order_id, order_item_id, action, storage_type, qty, movement_id, operator_id, created_at |
| T1-2 | action CHECK：INSERT 帶 action='invalid' | constraint violation |
| T1-3 | action 合法值（damaged / returned_to_stock / refunded）各 INSERT 一筆 | 成功 |

## T2 — Append-only 守衛

| # | 步驟 | 預期 |
|---|------|------|
| T2-1 | `UPDATE order_expiry_events SET qty = 1 WHERE id = <id>` | EXCEPTION 含 "append-only" |
| T2-2 | `DELETE FROM order_expiry_events WHERE id = <id>` | EXCEPTION 含 "append-only" |

## T3 — 欄位可為 NULL

| # | 步驟 | 預期 |
|---|------|------|
| T3-1 | INSERT 不帶 operator_id（NULL = 系統自動） | 成功 |
| T3-2 | INSERT 不帶 order_item_id | 成功 |
| T3-3 | INSERT 不帶 movement_id | 成功 |
