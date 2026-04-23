---
title: PRD - 應付帳款 + 零用金 + 費用
module: AccountsPayable
status: v0.2-qclosed
owner: alex.chen
created: 2026-04-22
updated: 2026-04-23
tags: [PRD, ERP, v0.2, 應付帳款, 零用金, 費用, lt-erp-integration, accounting, c混合型]
---

# PRD — 應付帳款 + 零用金 + 費用模組（Accounts Payable + Petty Cash + Expense）

> **新 module PRD**（非 addendum），v0.2 獨立成冊。
> 驅動原因：v0.1 原標 P1 deferred；Q4 決議拉進 v0.2、pilot 門市上線時會計帳目必備。
> 參考：lt-erp 的 `MakePayment` / `PettyCashPanel` / `AddExpense` / `ExpenseList` 四個功能。
> 決議來源：[[decisions/2026-04-22-v0.2-scope-decisions]] Q4。
> 銜接：[[PRD-庫存模組-v0.2-addendum]] §3.5（transfer settlement → vendor_bill）、[[PRD-供應商整合-v0.2]]（xiaolan → purchases → bills）。

---

## 1. 模組定位

- [x] **應付帳款（AP）**：管供應商 bill + 付款；獨立於銷售端 `payments` 表（那是 AR）
- [x] **零用金（Petty Cash）**：每店現金備用金、每日收支流水
- [x] **費用（Expense）**：費用申請 → 審核 → 支付（可從零用金支、可從公司帳戶支）
- [x] **加盟店模式兼容**（符合 [[decisions/2026-04-23-系統立場-混合型]] C 混合型）：
  - 加盟主**各自收款 / 各自月結**；總部僅代總倉供應商付款
  - 加盟店間的月結（PRD #2 §3.5）走 AP 管道代收代付
  - **加盟店間對付款走總部 clearing house**（Q6 決議 2026-04-23）：A → 總部 → B；加盟主互不看對方銀行帳戶，總部看得到全部金流
  - 加盟店自己的費用不走 AP、自行承擔（例外：總部代墊可 flag `settled_by_hq`）
- [x] **v1 範疇**（Q1~Q6 決議 2026-04-23）：
  - 發票手工對 `supplier_invoice_no`（Q1 A；不做 OCR，供應商分散投報率低）
  - 費用預算警示不擋 + per-store 自設（Q2 B；`expense_categories.monthly_budget_cents` 為 NULL 時 = 不啟用）
  - 陸貨採購下單日匯率鎖 TWD（Q4 A；bill 上用鎖定匯率算 TWD amount，匯差會計手調）
  - 加盟店 supplier on-demand 自動建（Q5 = 2；第一次結帳時建、不預建）
- [x] **不做（deferred to P1/P2）**：
  - 銀行對帳（bank reconciliation）— v1 人工做
  - 外匯 / 多幣別 — TWD only；P1 接 1688 拼多多時評估
  - 發票自動比對 — P1 朝財政部電子發票平台拉取方向（非通用 OCR）
  - 跨店 expense 代墊（Q3 確認不發生）

---

## 2. 核心概念

- [x] **Vendor Bill**：供應商帳單 — 可來自 PO 收貨、可來自 xiaolan 匯入、可來自 transfer settlement（加盟店互相欠）
- [x] **Vendor Payment**：實際付款動作 — 一筆 payment 可對多張 bill（partial pay / aggregated pay）
- [x] **Petty Cash Account**：每店一個備用金帳戶（有 balance / credit_limit）
- [x] **Petty Cash Transaction**：每筆零用金進出（append-only）
- [x] **Expense**：費用申請（交通、文具、雜支…）、需審核、支付管道可選
- [x] **Stores as Suppliers**：加盟店在 `suppliers` 表有對應 row（Flag 8 依賴、§3.1 建立規則）

---

## 3. 資料模型

### 3.1 新增表：`vendor_bills`（主檔、可編輯）

```sql
CREATE TABLE vendor_bills (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  bill_no TEXT NOT NULL,                               -- 系統生成 'BILL-202604-0001'
  supplier_id BIGINT NOT NULL REFERENCES suppliers(id),
  source_type TEXT NOT NULL
    CHECK (source_type IN ('purchase_order', 'goods_receipt', 'transfer_settlement', 'xiaolan_import', 'manual')),
  source_id BIGINT,                                    -- FK varies by source_type
  bill_date DATE NOT NULL,
  due_date DATE NOT NULL,
  amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
  paid_amount NUMERIC(18,4) NOT NULL DEFAULT 0
    CHECK (paid_amount >= 0 AND paid_amount <= amount),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'partially_paid', 'paid', 'cancelled', 'disputed')),
  currency TEXT NOT NULL DEFAULT 'TWD',                -- v1 只有 TWD
  tax_amount NUMERIC(18,4) NOT NULL DEFAULT 0,
  supplier_invoice_no TEXT,                            -- 供應商開的發票號
  notes TEXT,
  created_by UUID, updated_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tenant_id, bill_no)
);

CREATE INDEX idx_bills_supplier ON vendor_bills (tenant_id, supplier_id, status);
CREATE INDEX idx_bills_due ON vendor_bills (tenant_id, due_date)
  WHERE status IN ('pending', 'partially_paid');
CREATE INDEX idx_bills_source ON vendor_bills (tenant_id, source_type, source_id);
```

**為何 `source_type` + `source_id` 而非多個 FK**：
- bill 可從 4+ 種來源產生（PO、GR、settlement、xiaolan、手動）
- 每個來源表一個 nullable FK 會很亂（4 個欄位只一個非 NULL）
- 用 `source_type` + `source_id` polymorphic、查詢時自己 JOIN
- 代價：DB 層無 FK integrity；以 application layer 保證（RPC 建 bill 時驗證 source 存在）

### 3.2 新增表：`vendor_bill_items`（明細、append-only）

```sql
CREATE TABLE vendor_bill_items (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  bill_id BIGINT NOT NULL REFERENCES vendor_bills(id) ON DELETE CASCADE,
  line_no INTEGER NOT NULL,
  description TEXT NOT NULL,
  sku_id BIGINT REFERENCES skus(id),                   -- nullable（settlement bill 無 sku）
  qty NUMERIC(18,3),
  unit_cost NUMERIC(18,4),
  amount NUMERIC(18,4) NOT NULL,
  po_item_id BIGINT REFERENCES purchase_order_items(id),  -- source trace
  gr_item_id BIGINT REFERENCES goods_receipt_items(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- append-only，不帶 created_by（繼承 bill.created_by）+ 不帶 updated_*
);

CREATE INDEX idx_bill_items_bill ON vendor_bill_items (bill_id, line_no);
```

### 3.3 新增表：`vendor_payments`（主檔、可編輯）

和銷售端的 `payments` 表**獨立**（那邊是 AR、這邊是 AP）。

```sql
CREATE TABLE vendor_payments (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  payment_no TEXT NOT NULL,
  supplier_id BIGINT NOT NULL REFERENCES suppliers(id),
  amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL
    CHECK (method IN ('cash', 'bank_transfer', 'check', 'offset', 'petty_cash', 'other')),
  bank_account TEXT,                                   -- 轉帳帳號 tail 4
  check_no TEXT,                                       -- 支票號
  paid_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  paid_from_petty_cash_id BIGINT,                      -- FK 加在 §3.5 建表後
  cleared_via_hq BOOLEAN NOT NULL DEFAULT FALSE,       -- Q6: 加盟店間對付款走總部 clearing
  hq_clearing_leg TEXT CHECK (hq_clearing_leg IN ('store_to_hq', 'hq_to_store', NULL)),
  linked_payment_id BIGINT REFERENCES vendor_payments(id),  -- 另一條 leg 的 payment（clearing 雙腿對照）
  status TEXT NOT NULL DEFAULT 'completed'
    CHECK (status IN ('pending', 'completed', 'voided')),
  notes TEXT,
  created_by UUID, updated_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tenant_id, payment_no)
);

CREATE INDEX idx_vpay_supplier ON vendor_payments (tenant_id, supplier_id, paid_at DESC);
```

### 3.4 新增表：`vendor_payment_allocations`（付款分配、append-only）

一筆付款可對多張 bill：

```sql
CREATE TABLE vendor_payment_allocations (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  payment_id BIGINT NOT NULL REFERENCES vendor_payments(id) ON DELETE CASCADE,
  bill_id BIGINT NOT NULL REFERENCES vendor_bills(id),
  allocated_amount NUMERIC(18,4) NOT NULL CHECK (allocated_amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- append-only
);

CREATE INDEX idx_vpay_alloc_bill ON vendor_payment_allocations (bill_id);
CREATE INDEX idx_vpay_alloc_pay ON vendor_payment_allocations (payment_id);
```

### 3.5 新增表：`petty_cash_accounts`（主檔、可編輯）

```sql
CREATE TABLE petty_cash_accounts (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  account_name TEXT NOT NULL,                          -- '台北店零用金'
  balance NUMERIC(18,4) NOT NULL DEFAULT 0,            -- 當前餘額（trigger 維護）
  credit_limit NUMERIC(18,4) NOT NULL DEFAULT 0,       -- 預支上限
  custodian_user_id UUID,                              -- 保管人
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID, updated_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tenant_id, store_id, account_name)
);

CREATE INDEX idx_pca_store ON petty_cash_accounts (tenant_id, store_id) WHERE is_active;
```

**balance 維護方式**：由 `petty_cash_transactions` insert trigger 自動更新 `balance`（類似 `stock_balances`）。

### 3.6 新增表：`petty_cash_transactions`（append-only 流水）

```sql
CREATE TABLE petty_cash_transactions (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  account_id BIGINT NOT NULL REFERENCES petty_cash_accounts(id),
  txn_date DATE NOT NULL DEFAULT CURRENT_DATE,
  direction TEXT NOT NULL CHECK (direction IN ('in', 'out')),
  amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
  purpose TEXT NOT NULL,
  category_id BIGINT REFERENCES expense_categories(id),  -- §3.8，may be NULL for 'in'
  expense_id BIGINT REFERENCES expenses(id),           -- §3.7，若 expense-driven txn
  vendor_payment_id BIGINT REFERENCES vendor_payments(id),  -- 若 petty → pay supplier
  receipt_photo_url TEXT,                              -- 單據照片（Storage URL）
  notes TEXT,
  created_by UUID,                                     -- 即 operator_id
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- append-only
);

CREATE INDEX idx_pct_account_date ON petty_cash_transactions (account_id, txn_date DESC);
CREATE INDEX idx_pct_category ON petty_cash_transactions (category_id) WHERE category_id IS NOT NULL;
```

**vendor_payments.paid_from_petty_cash_id FK 回補**：

```sql
ALTER TABLE vendor_payments
  ADD CONSTRAINT fk_vpay_petty_cash
  FOREIGN KEY (paid_from_petty_cash_id) REFERENCES petty_cash_transactions(id);
```

### 3.7 新增表：`expenses`（主檔、可編輯）

```sql
CREATE TABLE expenses (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  expense_no TEXT NOT NULL,
  applicant_id UUID NOT NULL,
  store_id BIGINT REFERENCES stores(id),               -- 哪店發生（null = HQ）
  category_id BIGINT NOT NULL REFERENCES expense_categories(id),
  amount NUMERIC(18,4) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL DEFAULT 'TWD',
  expense_date DATE NOT NULL,
  description TEXT NOT NULL,
  receipt_photo_url TEXT,
  approval_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending', 'approved', 'rejected', 'paid')),
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  rejection_reason TEXT,
  paid_by_vendor_payment_id BIGINT REFERENCES vendor_payments(id),  -- 公司帳戶付
  paid_by_petty_cash_txn_id BIGINT REFERENCES petty_cash_transactions(id),  -- 零用金付
  settled_by_hq BOOLEAN NOT NULL DEFAULT FALSE,        -- 總部代墊 flag
  created_by UUID, updated_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tenant_id, expense_no),
  CHECK (
    (paid_by_vendor_payment_id IS NULL)::int
    + (paid_by_petty_cash_txn_id IS NULL)::int >= 1  -- 兩者不能同時有
  )
);

CREATE INDEX idx_expenses_status ON expenses (tenant_id, approval_status);
CREATE INDEX idx_expenses_store ON expenses (tenant_id, store_id, expense_date DESC);
CREATE INDEX idx_expenses_applicant ON expenses (applicant_id, approval_status);
```

### 3.8 新增表：`expense_categories`（主檔）

```sql
CREATE TABLE expense_categories (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  store_id BIGINT REFERENCES stores(id),               -- Q2: NULL = 總部/共用；有值 = 該店專屬預算
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  parent_id BIGINT REFERENCES expense_categories(id),
  approval_threshold NUMERIC(18,4),                    -- 超過需審核
  monthly_budget_cents BIGINT,                         -- Q2: NULL = 不啟用預算；有值 = 警示但不擋
  default_pay_method TEXT
    CHECK (default_pay_method IN ('petty_cash', 'company_account', 'either', NULL)),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID, updated_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (tenant_id, code)
);
```

**Seed data**（v0.2 初始）：交通 / 文具 / 餐飲 / 通訊 / 水電 / 雜支 / 修繕 / 採購雜項。

---

## 4. 業務流程

### 4.1 Vendor Bill 建立（來自 4 個來源）

**Source 1：PO 收貨後**
```
GR confirm → trigger 建 vendor_bill（source_type='goods_receipt'）
  amount = SUM(gr_items.qty_received * unit_cost)
  supplier_id = gr.supplier_id
  due_date = gr.receive_date + supplier.payment_terms（解析為天）
  status='pending'
```

**Source 2：xiaolan 匯入 resolve**
```
admin 在 xiaolan tab 按 resolve → RPC rpc_resolve_xiaolan_purchase
  → 建 purchase_order
  → 建 vendor_bill（source_type='xiaolan_import', source_id=xiaolan_purchase.id）
```

**Source 3：transfer settlement confirm（Flag 8）**
```
admin confirm 月結算 → rpc_confirm_transfer_settlement
  → 若 net > 0 → 建 vendor_bill（source_type='transfer_settlement', source_id=settlement.id）
    supplier_id = debtor_store 對應的 supplier（§4.7 mapping）
```

**Source 4：手動**
```
admin UI 手動建 bill（會計補登）→ RPC rpc_create_manual_bill
  source_type='manual', source_id=NULL
```

### 4.2 Vendor Payment 流程（MakePayment）

```
admin 選 supplier → 顯示該 supplier 所有 pending/partially_paid bills →
  勾選要付的 bills + 填 allocation amount（可分配部分 / 跨多張）→
  選 payment method + bank_account / check_no →
  RPC rpc_make_payment(payment, allocations[])
    前置:
      pg_advisory_xact_lock('vpay:' || supplier_id)
      for each alloc: SELECT FOR UPDATE bill + 驗 bill.paid_amount + alloc.allocated <= bill.amount
    執行:
      INSERT INTO vendor_payments (...)
      for each alloc:
        INSERT INTO vendor_payment_allocations (payment_id, bill_id, allocated_amount)
        UPDATE vendor_bills SET paid_amount += alloc.allocated,
          status = CASE WHEN paid_amount = amount THEN 'paid' ELSE 'partially_paid' END
      若 method='petty_cash' → 同步走 §4.4 零用金流水
```

**Q6 HQ Clearing 分支（加盟店間對付款）**：

當 `supplier` 是另一家加盟店（即 `suppliers.code LIKE 'STORE-%'`）時，RPC 自動拆兩條 leg：

```
rpc_make_payment_clearing(debtor_store_id, creditor_store_id, amount, bills[])
  leg 1 (store_to_hq):
    INSERT INTO vendor_payments
      (supplier_id=HQ_supplier_id, cleared_via_hq=TRUE, hq_clearing_leg='store_to_hq', ...)
    → 更新 bills.paid_amount（債務人對總部結清）
  leg 2 (hq_to_store):
    INSERT INTO vendor_payments
      (supplier_id=creditor_store.supplier_id, cleared_via_hq=TRUE, hq_clearing_leg='hq_to_store',
       linked_payment_id=<leg1.id>, ...)
    → 總部對債權人加盟店開一張 bill 並立即 paid
  UI:
    A 店畫面：「付給 B 店 2,000」→ 實際寫 leg1（對 HQ），不顯示 B 店銀行帳戶
    B 店畫面：「收到 A 店 2,000（總部代轉）」→ 從 leg2 產生
    總部後台：看得到雙 leg、可追蹤延遲
```

### 4.3 Expense 申請 → 審核 → 支付

```
員工建 expense（category, amount, photo）→ approval_status='pending'
  若 amount < category.approval_threshold → 自動 approved
  否則 → 等上層審
approver → RPC rpc_approve_expense(expense_id, note) or rpc_reject_expense(expense_id, reason)
  → approval_status='approved'
approved expense 進「待支付」清單 →
  admin 選支付方式：
    option A: 從公司帳戶 → rpc_pay_expense_via_vendor_payment
      → 建 vendor_payment（supplier_id = 員工個人 supplier，或通用 '內部費用' supplier）
      → 建 vendor_bill（source_type='manual' + expense_id 寫 note）
      → allocate payment → bill → expense.paid_by_vendor_payment_id, approval_status='paid'
    option B: 從零用金 → rpc_pay_expense_via_petty_cash
      → 建 petty_cash_transactions（direction='out', expense_id=...）
      → expense.paid_by_petty_cash_txn_id, approval_status='paid'
```

### 4.4 零用金流水（PettyCashPanel）

```
每月補款（admin）→ rpc_post_petty_cash_txn(account_id, direction='in', amount, purpose='月補款')
  → balance += amount
員工用零用金買東西（走 expense → §4.3 B）
  → petty_cash_txn direction='out'
  → balance -= amount
  → 若 balance + credit_limit < 0 → RAISE EXCEPTION
月底對帳：account.balance 應 = 實際盒內現金
```

### 4.5 Aging Report（應付帳齡）

```sql
CREATE OR REPLACE VIEW v_ap_aging AS
SELECT
  supplier_id,
  supplier_name,
  SUM(CASE WHEN due_date >= CURRENT_DATE THEN unpaid END) AS current_due,
  SUM(CASE WHEN due_date BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE - 1 THEN unpaid END) AS "1_30_overdue",
  SUM(CASE WHEN due_date BETWEEN CURRENT_DATE - 60 AND CURRENT_DATE - 31 THEN unpaid END) AS "31_60_overdue",
  SUM(CASE WHEN due_date < CURRENT_DATE - 60 THEN unpaid END) AS "60_plus_overdue",
  SUM(unpaid) AS total_unpaid
FROM (
  SELECT b.supplier_id, s.name AS supplier_name, b.due_date,
         b.amount - b.paid_amount AS unpaid
  FROM vendor_bills b JOIN suppliers s ON s.id = b.supplier_id
  WHERE b.status IN ('pending', 'partially_paid')
) sub
GROUP BY supplier_id, supplier_name;
```

### 4.6 Cash Flow Report

```sql
-- 每月 cash flow: in(AR 已收) - out(AP 已付) + petty_cash 淨流出
CREATE OR REPLACE VIEW v_cash_flow_monthly AS ...
```

（具體 SQL 在 migration 階段定；PRD 層級先定義有此 view）

### 4.7 加盟店 supplier mapping（Flag 8 依賴；Q5 決議 2026-04-23 改為 on-demand）

**Q5 決議**：不預建 — 100 家加盟店兩兩交易不會全都發生，預建會讓 supplier 清單膨脹 + 90% 沒用。改成**第一次要用時自動建**（lazy / on-demand），之後重用。

- `stores` 加欄位 `supplier_id BIGINT REFERENCES suppliers(id)`（NULL = 還沒建過 supplier mapping）
- **不再使用 `BEFORE INSERT ON stores` trigger 強制建**
- 第一次 store A 與 store B 要結帳（`rpc_confirm_transfer_settlement` 或 `rpc_make_payment_clearing`）時，RPC 內先呼叫 `ensure_store_supplier(store_id)`：
  - 若 `stores.supplier_id IS NULL` → 建新 supplier row（code = `STORE-` || store.code）並回填
  - 否則直接回傳已存在的 supplier_id

**Schema delta**：
```sql
ALTER TABLE stores ADD COLUMN supplier_id BIGINT REFERENCES suppliers(id);

-- on-demand helper（不做 trigger、由 RPC 呼叫）
CREATE OR REPLACE FUNCTION ensure_store_supplier(p_store_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
  v_supplier_id BIGINT;
  v_store stores%ROWTYPE;
BEGIN
  SELECT supplier_id INTO v_supplier_id FROM stores WHERE id = p_store_id;
  IF v_supplier_id IS NOT NULL THEN RETURN v_supplier_id; END IF;

  SELECT * INTO v_store FROM stores WHERE id = p_store_id FOR UPDATE;
  INSERT INTO suppliers (tenant_id, code, name, is_active, created_by)
  VALUES (v_store.tenant_id, 'STORE-' || v_store.code, v_store.name, TRUE, v_store.created_by)
  RETURNING id INTO v_supplier_id;

  UPDATE stores SET supplier_id = v_supplier_id WHERE id = p_store_id;
  RETURN v_supplier_id;
END;
$$ LANGUAGE plpgsql;
```

**優點**：supplier 清單只會有**真的有過交易**的店；加盟店未結帳過 = 不會污染清單。
**代價**：第一次 settlement 會多一次 INSERT（可忽略）。

---

## 5. RPC / API

列核心 6 支，其他在 migration 階段補全：

| RPC | 權限 | 作用 |
|---|---|---|
| `rpc_create_manual_bill(payload)` | admin | 手動建 bill |
| `rpc_make_payment(payment, allocations[])` | admin / hq_manager | 付款 + 分配到多張 bill |
| `rpc_add_expense(payload)` | authenticated | 員工申請費用 |
| `rpc_approve_expense(expense_id, note)` | approver role | 審核通過 |
| `rpc_reject_expense(expense_id, reason)` | approver role | 審核退回 |
| `rpc_post_petty_cash_txn(account_id, direction, amount, purpose)` | store_manager / admin | 零用金流水 |

**共通防禦**：
- 所有 RPC `SECURITY DEFINER`
- 鎖的 scope 以 supplier 或 account 為單位 (`pg_advisory_xact_lock`)
- 寫操作必 `SELECT ... FOR UPDATE` 先鎖再寫
- 返回 JSONB with error detail（不用 HTTP 400、用 PostgreSQL EXCEPTION 向上拋）

---

## 6. RLS Policy

### 6.1 `vendor_bills` / `vendor_bill_items` / `vendor_payments` / `vendor_payment_allocations`

- admin / hq_accountant：ALL
- store_manager：SELECT where 關聯 supplier_id = store.supplier_id（自己店被代收代付的 bill）
- 其他 role：看不到

### 6.2 `petty_cash_accounts` / `petty_cash_transactions`

- store_manager (custodian)：SELECT own store + INSERT txn（自己保管的 account）
- admin：ALL
- 其他店：看不到別店 petty_cash

### 6.3 `expenses`

- applicant：SELECT own + INSERT own + UPDATE own if status='pending'
- approver role：SELECT where amount >= threshold AND status='pending'
- admin：ALL

### 6.4 `expense_categories`

- 任何 authenticated：SELECT
- admin：INSERT / UPDATE / DELETE

---

## 7. 稽核

| 表 | 類型 | 稽核欄位 |
|---|---|---|
| `vendor_bills` | 主檔 | 四欄全帶 |
| `vendor_bill_items` | append-only | `created_at` only（bill_id 繼承 bill.created_by） |
| `vendor_payments` | 主檔 | 四欄全帶 |
| `vendor_payment_allocations` | append-only | `created_at` only |
| `petty_cash_accounts` | 主檔 | 四欄全帶 + `custodian_user_id` 追保管人變更 |
| `petty_cash_transactions` | append-only | `created_by` + `created_at` |
| `expenses` | 主檔 | 四欄全帶 + `approved_by`/`approved_at` 追審核動作 |
| `expense_categories` | 主檔 | 四欄全帶 |

**審核動作稽核不新開 log 表** — 依賴主檔本身欄位（approved_by / reviewed_at 等）。若 pilot 反饋需詳細 log 再建 P1。

---

## 8. 反模式避開

| # | 反模式 | 本 PRD 處理 |
|---|---|---|
| 1 | shared_kv | 全用正規表 |
| 2 | silent write failures | RPC 全 RAISE EXCEPTION |
| 3 | REST PATCH 副作用 | bill status / payment allocation 一律 RPC |
| 5 | state 只在 memory | 所有金額狀態落 DB |
| **新** | double-payment race | `pg_advisory_xact_lock('vpay:' || supplier_id)` + bill `SELECT FOR UPDATE` |
| **新** | petty cash 超支 | petty_cash_accounts.balance trigger 維護 + credit_limit CHECK |
| **新** | expense 循環批准 | RPC 檢查 `applicant_id != approved_by`（不可自審） |

---

## 9. 與其他模組的整合點

- **採購模組**（PRD #3）：GR confirm → 自動建 vendor_bill（§4.1 Source 1）
- **供應商整合**（PRD #4）：xiaolan resolve → 建 vendor_bill（§4.1 Source 2）
- **庫存模組**（PRD #2）：transfer_settlement confirm → 建 vendor_bill（§4.1 Source 3，Flag 8）
- **銷售模組**（既有）：銷售 `payments` 表是 AR；本模組 `vendor_payments` 是 AP；兩者不共用表但 cash flow view 合併
- **會員模組**（既有）：不直接耦合；員工 expense 的 applicant_id = `members.id`（若 is_employee）
- **通知模組**（既有）：
  - bill due 提醒：due_date - 7 天 → LINE OA
  - expense approval pending：> 24h → approver 收 LINE
  - 月結算 bill 新建 → debtor store 收通知

---

## 10. Open Questions — 全數已 closed（2026-04-23）

> 六題全部在 2026-04-23 session 答完，決議依據 [[decisions/2026-04-23-系統立場-混合型]] C 混合型。

- [x] **Q1 發票比對**（2026-04-23）→ **手工輸入 `supplier_invoice_no`**；P1 方向改為**財政部電子發票平台拉取**（非通用 OCR，供應商分散格式不一，投報率低）。見 `memory/project_new_erp_supplier_structure.md`。
- [x] **Q2 預算管控**（2026-04-23）→ **警示不擋 + per-store 自設**；`expense_categories.monthly_budget_cents` NULL = 不啟用；每家加盟店自己選要不要設、超過只跳警示、不擋下。符合 C 混合型「加盟店自主」。
- [x] **Q3 跨店 expense 代墊**（2026-04-23）→ **不發生**（員工不跨店調度）；現有 `expenses.store_id` 自填即可，**不加** `on_behalf_of_store_id`。
- [x] **Q4 陸貨外匯**（2026-04-23）→ **下單日匯率鎖 TWD**；bill 上以當日匯率存 TWD amount，匯差會計手工調；v1 不做多幣別，P1 再評估。
- [x] **Q5 加盟店 supplier 自動建**（2026-04-23）→ **on-demand**（需要用才自動建）；§4.7 已改：第一次結帳時由 RPC 呼叫 `ensure_store_supplier()` 建立，避免 100 家預建膨脹。
- [x] **Q6 加盟店間對付款的隱私**（2026-04-23）→ **總部 clearing house**；A → 總部 → B，加盟主互不看對方銀行帳戶、總部看得到全部金流。schema：`vendor_payments.cleared_via_hq / hq_clearing_leg / linked_payment_id`。§4.2 已加分支。

---

## 11. 相關檔案

- 決議文件：
  - [[decisions/2026-04-22-v0.2-scope-decisions]] Q4（本 PRD 拉進 v0.2 的依據）
  - [[decisions/2026-04-23-系統立場-混合型]]（Q1~Q6 決議的立場基準）
- 關聯 PRD：
  - [[PRD-採購模組-v0.2-addendum]] § 業務流程（GR → bill）
  - [[PRD-供應商整合-v0.2]] § xiaolan resolve
  - [[PRD-庫存模組-v0.2-addendum]] §3.5（settlement → bill，Flag 8）
- 整合計畫：`C:\Users\Alex\.claude\plans\snazzy-riding-toucan.md` §1（應收/應付/現金）、§3 Phase 4（本 PRD 補進）
- 後續：`supabase/migrations/20260423*_ap_petty_expense.sql`（8 張表 + RLS + trigger + seed categories）

---

## 變更歷史

- **2026-04-23** v0.2-qclosed：Q1~Q6 全數 closed（見 §10）；新增 C 混合型 立場參照；schema 增補 `vendor_payments.cleared_via_hq` 三欄、`expense_categories.monthly_budget_cents` + `store_id`；§4.2 新增 HQ clearing 分支；§4.7 supplier trigger 改為 on-demand `ensure_store_supplier()` helper。
- **2026-04-22** v0.2 初版：8 張表 schema + RPC + RLS + 6 題 Open Questions。
