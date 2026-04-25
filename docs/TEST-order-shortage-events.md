# TEST — Issue #73: order_shortage_events

## 目標
驗證 `order_shortage_events` 表結構、generated column `shortage_qty`、append-only 守衛。

## 前置條件
- Migration `20260429140000_order_shortage_events.sql` 已 apply
- 至少一筆 `customer_orders` 存在

---

## T1 — 表結構確認

| # | 步驟 | 預期 |
|---|------|------|
| T1-1 | 查 `information_schema.columns WHERE table_name='order_shortage_events'` | 欄位：id, tenant_id, campaign_id, order_id, sku_id, requested_qty, fulfilled_qty, shortage_qty, reason, created_at |
| T1-2 | `SELECT is_generated FROM information_schema.columns WHERE table_name='order_shortage_events' AND column_name='shortage_qty'` | `ALWAYS` |

## T2 — Generated column

| # | 步驟 | 預期 |
|---|------|------|
| T2-1 | INSERT requested_qty=10, fulfilled_qty=7 | shortage_qty = 3.000 |
| T2-2 | INSERT requested_qty=5, fulfilled_qty=5 | shortage_qty = 0.000 |
| T2-3 | 嘗試 INSERT 帶 shortage_qty 值 | ERROR：generated column 不可手動賦值 |

## T3 — Append-only 守衛

| # | 步驟 | 預期 |
|---|------|------|
| T3-1 | `UPDATE order_shortage_events SET reason='x' WHERE id = <id>` | EXCEPTION 含 "append-only" |
| T3-2 | `DELETE FROM order_shortage_events WHERE id = <id>` | EXCEPTION 含 "append-only" |

## T4 — 索引

| # | 步驟 | 預期 |
|---|------|------|
| T4-1 | `\d order_shortage_events` 或查 pg_indexes | 3 個 index：tenant+campaign, tenant+order, tenant+sku |
