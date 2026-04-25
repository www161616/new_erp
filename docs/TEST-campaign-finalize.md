# campaign-finalize 測試項目 — 開團整單結算 UI

**對應 migration:** `supabase/migrations/20260428180000_workflow_close_loop.sql`（rpc_finalize_campaign 已建）
**對應 UI 變更:**
- `apps/admin/src/app/(protected)/campaigns/page.tsx`（新增「結算」按鈕）

**對應 PRD:** `docs/PRD-訂單取貨模組.md` §7.5（結單 → 結算 timeline 第 8 步）
**對應 Issue:** [#116 campaign finalize button](https://github.com/lt-foods/new_erp/issues/116)

---

## 1. 顯示層

### 1.1 按鈕可見性
- [ ] `status='draft'` → 不顯示「結算」按鈕
- [ ] `status='open'` → 不顯示「結算」按鈕（只顯示「結單」）
- [ ] `status='closed'` → 顯示「結算」按鈕
- [ ] `status='ordered'` → 顯示「結算」按鈕
- [ ] `status='receiving'` → 顯示「結算」按鈕
- [ ] `status='ready'` → 顯示「結算」按鈕
- [ ] `status='completed'` → 不顯示
- [ ] `status='cancelled'` → 不顯示

### 1.2 按鈕狀態
- [ ] 點擊先 `confirm()` 提示「整單結算後不可逆」
- [ ] 取消 confirm 不發 RPC
- [ ] 按鈕 disabled + 顯示「結算中…」直到 RPC 完成

---

## 2. RPC 整合

### 2.1 守衛：未結案訂單
- [ ] 製造一筆 `customer_orders.status='confirmed'` 的開團 → 點結算 → 看到 error toast 含 `unfinished customer orders`
- [ ] campaign 仍維持原狀態（不改 completed）

### 2.2 成功路徑
- [ ] 全部 customer_orders 都 completed/expired/cancelled → 點結算 → 列表 reload，狀態變「已完成」
- [ ] DB 驗證：
  ```sql
  SELECT status, updated_by, updated_at
    FROM group_buy_campaigns
   WHERE id = <測試 campaign>;
  ```
  status='completed', updated_by 是當前 user

### 2.3 重複點擊
- [ ] 已 completed 的 campaign 點結算 → RPC RAISE `not in finalizable status` → UI 顯示錯誤

---

## 3. UX

- [ ] error toast 與既有 closeCampaign 風格一致
- [ ] 結算後不需手動 reload 列表
- [ ] 表頭計數（共 N 筆）不會卡住載入中狀態
