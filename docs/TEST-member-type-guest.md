# TEST — Issue #75: member_type + guest RPCs

## 目標
驗證 `members.member_type`、`customer_orders.order_type` 欄位與兩支 guest RPC 正確運作。

## 前置條件
- Migration `20260429120000_member_type_guest.sql` 已 apply
- 至少一筆 `line_channels` 與對應 `locations` 存在
- 測試用 tenant_id / channel_id 已知

---

## T1 — 欄位存在確認

| # | 步驟 | 預期 |
|---|------|------|
| T1-1 | `SELECT column_name, data_type, column_default, is_nullable FROM information_schema.columns WHERE table_name='members' AND column_name='member_type'` | 1 列：`text`, default `full`, NOT NULL |
| T1-2 | 同上查 `customer_orders.order_type` | 1 列：`text`, default `regular`, NOT NULL |
| T1-3 | 查現有 members 的 member_type | 全部應為 `full`（預設值 backfill） |

## T2 — rpc_create_guest_member

| # | 步驟 | 預期 |
|---|------|------|
| T2-1 | 呼叫 `SELECT rpc_create_guest_member('<tenant>', <channel_id>, 'TestGuest')` | 回傳 BIGINT member_id |
| T2-2 | `SELECT member_type, name, member_no, phone_hash, status FROM members WHERE id = <id>` | `member_type='guest'`, `name='TestGuest'`, `member_no` 以 `G` 開頭, `phone_hash IS NULL`, `status='active'` |
| T2-3 | `SELECT * FROM customer_line_aliases WHERE member_id = <id>` | 一筆 nickname='TestGuest' 的 alias |
| T2-4 | 傳入不存在的 channel_id | RAISE EXCEPTION 含 "not found" |

## T3 — rpc_merge_member

| # | 步驟 | 預期 |
|---|------|------|
| T3-1 | 建一筆 guest member (T2)，建一筆 full member，各建一筆 customer_order | — |
| T3-2 | 呼叫 `SELECT rpc_merge_member(<guest_id>, <real_id>)` | void，無 exception |
| T3-3 | 查 guest member | `status='merged'`, `merged_into_member_id = real_id` |
| T3-4 | 查 customer_orders | 原屬 guest 的 order `member_id` 改為 real_id |
| T3-5 | 查 customer_line_aliases | guest 的 alias `member_id` 改為 real_id |
| T3-6 | 查 member_merges | 一筆新紀錄，`primary_member_id=real_id`, `merged_member_id=guest_id` |
| T3-7 | 對同一 guest 再次呼叫 merge | RAISE EXCEPTION 含 "already merged" |
| T3-8 | 對非 guest member 呼叫 merge | RAISE EXCEPTION 含 "not a guest" |
| T3-9 | 傳 guest_id = real_id | RAISE EXCEPTION 含 "must differ" |

## T4 — customer_orders.order_type

| # | 步驟 | 預期 |
|---|------|------|
| T4-1 | INSERT customer_order 不帶 order_type | order_type = 'regular' |
| T4-2 | INSERT 帶 order_type = 'invalid' | CHECK constraint violation |
| T4-3 | INSERT 帶 order_type = 'employee' | 成功 |
