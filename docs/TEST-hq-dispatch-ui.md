---
title: TEST — 總倉調度中心 UI（Phase 5d）
module: Inventory / Transfer / Admin UI
status: draft
owner: alex.chen
created: 2026-04-26
---

# 測試清單 — 總倉調度中心 UI

對應 lt-erp 圖 2「店轉店與退倉審核」。

## Scope

- 新 page：`apps/admin/src/app/(protected)/transfers/dispatch/page.tsx`
- RPC 來源：Phase 5a-2 已 ship 的 `rpc_transfer_arrive_at_hq_batch` / `rpc_transfer_distribute_batch` / `rpc_register_damage` / `rpc_transfer_batch_delete`
- 不影響：既有 `/transfers/page.tsx` (列表觀察) + `/transfers/inbox/page.tsx` (店端收貨)

## UI 結構

```
┌─ Header：總倉調度中心 ─────────────────────────────┐
│ 5 個 status tabs (待審核/已到總倉/已配送/已收到/空中轉)
│ 每個 tab 顯示 count
├─ Filters：轉出店 / 轉入店 / 日期範圍 / 商品搜尋
├─ 批次操作：[全選] [批次到倉] [批次配送] [批次刪除]
├─ Table：☐ 單號 | 來源→目的地 | 商品 | 溫層 | 狀態 | 總倉備註 | 操作
│   操作：[看明細] / [確認到倉] / [登記損壞]
└─ Damage Modal：選 transfer_item + qty + notes
```

## 測試項目

### A. Tab 切換 + 5 status filter

- [ ] A1：載入時預設顯示「待審核」tab、count 正確
- [ ] A2：切「已到總倉」→ 篩 `dest=HQ + status=received`
- [ ] A3：切「已配送」→ 篩 `source=HQ + status=shipped`
- [ ] A4：切「已收到」→ 篩 `dest≠HQ + status=received`
- [ ] A5：切「空中轉」→ 篩 `is_air_transfer=true`

### B. Filter

- [ ] B1：轉出店 select 動作 → 表格 update
- [ ] B2：轉入店 select 動作 → 表格 update
- [ ] B3：日期範圍 from/to → 表格 update (filter on `shipped_at` 或 `created_at`)
- [ ] B4：商品搜尋 → 篩 transfer_items.sku 符合的 transfer

### C. 批次到倉

- [ ] C1：勾多筆「已配送 to HQ」TR → 點「批次到倉」 → 呼叫 `rpc_transfer_arrive_at_hq_batch`
- [ ] C2：成功後 reload、顯示「2 筆成功」alert
- [ ] C3：part fail → 顯示「3 筆成功 / 1 筆失敗 (reason: ...)」

### D. 批次配送

- [ ] D1：勾多筆「待審核 from HQ」TR → 點「批次配送」 → 呼叫 `rpc_transfer_distribute_batch`
- [ ] D2：成功後 reload + status 變 已配送

### E. 批次刪除

- [ ] E1：勾多筆 draft → 點「批次刪除」→ confirm → 呼叫 `rpc_transfer_batch_delete`
- [ ] E2：非 draft 在批次中 → 顯示部分失敗

### F. 損壞登記

- [ ] F1：點「登記損壞」→ Modal 開、列 transfer_items
- [ ] F2：選 item + 填 qty + notes → 送出 → 呼叫 `rpc_register_damage`
- [ ] F3：成功後 close modal + reload + transfer_items.damage_qty 更新

### G. 總倉備註

- [ ] G1：每筆 inline input 顯示 hq_notes
- [ ] G2：blur 時 update transfers.hq_notes
- [ ] G3：失敗顯示 inline error

### H. 一般

- [ ] H1：載入中顯示 loading
- [ ] H2：error 顯示在頂部 banner
- [ ] H3：空狀態顯示「目前沒有資料」

## 驗證方式

- preview_start dev server
- preview_snapshot + preview_click + preview_fill 走每個測項
- preview_screenshot 重要狀態

## 不在範圍

- 損壞登記後庫存自動補單（業務流程）
- LINE OA 通知（5c phase 之後）
- 登記損壞的對方店通知（5c phase）
