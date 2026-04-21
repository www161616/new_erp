---
title: PRD - 訂單 / 取貨模組
module: Order
status: draft-v0.1
owner: www161616
created: 2026-04-21
tags: [PRD, ERP, 訂單, Order, Pickup, GroupBuy, LINE, 團購]
---

# PRD — 訂單 / 取貨模組（Order / Pickup Module）

> 零售連鎖 ERP，總倉 1 + 門市 100（加盟店模式）+ SKU 15,000。
> **本模組是團購店的核心業務流程**：從總部發團、顧客在 LINE 社群下單、結團、採購、到貨、取貨到結案。
> v0.1 checklist 版（Q1~Q15 已決策，僅 Q15 發票政策為 Open Question 待會計師確認）。

---

## 1. 模組定位
- [x] **業務主模組**：團購店所有訂單流程的 SSOT（single source of truth）
- [x] 整合上游：**採購模組**（結團後自動產生建議 PR）、**庫存模組**（收貨 / 取貨扣 lots）
- [x] 觸發下游：**通知模組**（`pickup_ready` / `pickup_reminder` / `pickup_overdue`）
- [x] 識別支撐：**會員模組**（手機後 6 碼查會員 / 會員價 / 員工身份）
- [x] **貼文 = 活動（Campaign）**：每張 LINE 社群貼文對應一筆 `campaigns` 紀錄，所有訂單歸屬此活動
- [x] **v1 以人工登打為主**，P1 再加 Claude vision 解析截圖

---

## 2. 核心概念 / 名詞定義
- [x] **LINE 社群（Community）**：5000 人公開頻道，**不是群組**；無官方 API，留言需人工 / 截圖處理
- [x] **團購活動（Campaign）**：一張團購貼文對應一筆 campaign；綁定發佈社群 / 起訖時間 / 商品 / 數量上限
- [x] **訂單（Customer Order）**：顧客在社群留言 +1 後，店員登打成形的訂單
- [x] **取貨店（Pickup Store）**：顧客固定綁定一家加盟店，由**暱稱規則**帶入
- [x] **暱稱規則（Nickname Convention）**：`{姓名}-{手機後6碼}-{取貨店縮寫}`
  - 多對多社群：必須含取貨店
  - 1:1 獨立社群：可省略取貨店（由社群直接推斷）
- [x] **貼文範本（Post Template）**：總部預建 50+ 種商品貼文模板，發文時套用
- [x] **留言截圖（Comment Snapshot）**：店員登打完訂單後截圖留言區，爭議時佐證
- [x] **結團（Closing）**：campaign 停止接單的時刻，分時間結 / 數量結 / 手動結三型
- [x] **黑名單（Blacklist）**：累積 3 次未取（或惡意棄單一次）的顧客，不再接單
- [x] **員工餐（Employee Meal）**：店員自用走獨立折扣 + 月結流程（見 §6.10）

---

## 3. Goals
- [x] G1 — 店員在後台 ≤ 30 秒完成一筆訂單登打（從看到留言到存檔）
- [x] G2 — 結團後系統**5 秒內**彙總全社群 / 全店訂單 → 產生建議 PR
- [x] G3 — 取貨時店員輸入手機後 6 碼 ≤ 2 秒叫出顧客所有待取訂單
- [x] G4 — 缺貨時「先到先得」依下單時間戳精準排序
- [x] G5 — 所有訂單狀態變動可稽核（append-only log）
- [x] G6 — 貼文截圖 / 留言截圖永久保存可追溯

---

## 4. Non-Goals（v1 不做）
- [x] ❌ **LINE 社群自動爬蟲 / 官方 API 整合**（LINE 5000 人社群無 API；v1 純手工）
- [x] ❌ **Claude vision 自動解析截圖**（P1 功能，v1 先不做）
- [x] ❌ **顧客 LIFF 自主下單頁面**（v1 只有社群 +1；P1 可加 LIFF 訂單）
- [x] ❌ **跨店下單**（一顧客綁一店，不允許切換）
- [x] ❌ **預購 / 訂金**（v1 訂單狀態機簡化：下單即完整、結團前可改）
- [x] ❌ **訂單硬刪除**（Q13-2：append-only，只能標記取消）
- [x] ❌ **自動產生廠商訂單**（Q13-1：系統只到「建議 PR」，總部審核後才送採購模組）
- [x] ❌ **月結 / 預付** 給顧客（取貨現場付；員工餐除外）

---

## 5. User Stories

### 顧客
- [x] 作為顧客，我要在 LINE 社群留言 +1 下單，不用下載 APP
- [x] 作為顧客，我要**不用每次講取貨店**（靠暱稱帶入）
- [x] 作為顧客，我要在結團前能改數量或取消（社群留言或私訊店員）
- [x] 作為顧客，我要到店**只報手機後 6 碼** 就能領到貨
- [x] 作為顧客，我要**現場付現金**或（部分店）LINE Pay

### 總部
- [x] 作為總部，我要在後台「貼文範本庫」中選模板 → 一鍵產出貼文文字 → 複製貼到 LINE
- [x] 作為總部，我要能先建立 campaign（指定社群 / 商品 / 結團時間）→ 再發文
- [x] 作為總部，我要看到全部社群的訂單彙總 → 一鍵產建議 PR 給採購模組
- [x] 作為總部，我要知道哪些顧客在黑名單

### 店員 / 店長
- [x] 作為店員，我要看到「本店相關社群」的貼文列表，點進去**登打本店顧客訂單**
- [x] 作為店員，我要能用暱稱 / 手機後 6 碼自動帶入顧客資訊
- [x] 作為店員，我要**截圖留言區**快速附加到 campaign（爭議佐證）
- [x] 作為店員，我要在驗收時對照採購單檢查數量與品質
- [x] 作為店員，我要在顧客來取貨時快速查到訂單、收款、結案
- [x] 作為店長，我要隨機抽查店員驗收結果
- [x] 作為店長，我要處理異常：缺貨分配 / 退貨 / 逾期報廢或降價
- [x] 作為店員，我要能為本人下員工餐（自動走月結專用流程）

---

## 6. Functional Requirements

### 6.1 貼文範本庫與 Campaign 管理

#### 範本庫（Post Template Library）
- [x] 總部維護 `post_templates`：每種商品 / 類別一個範本
- [x] 範本欄位：`title`, `body_text`, `variables JSONB`（`{{price}}` / `{{close_date}}` / `{{limit_qty}}`）
- [x] 範本分類：生鮮蔬果 / 冷凍肉品 / 常溫雜貨 / 節慶禮盒 等
- [x] 每個範本版本化（可回溯）

#### Campaign（團購活動）
- [x] 總部發文前先建 campaign：
  - `template_id`（用哪個範本）
  - `channel_ids[]`（發到哪幾個社群，可多選）
  - `opened_at`（開團時間）
  - `closed_at`（結團時間，可後改）
  - `close_type`: `time`（時間結）/ `qty`（數量結）/ `manual`（手動結）
  - `qty_limit`（數量結用）
  - `product_sku`, `campaign_price`（團購價，可異於 `prices` 表定價）
- [x] 系統產出「貼文文字」→ 總部**手動貼到 LINE 社群**
- [x] 常見型別：
  - **常規團**：3 天（例：4/1 開、4/3 結）
  - **快速團**：1.5 天
  - **限量團**：`close_type = qty`，達 `qty_limit` 自動關

### 6.2 訂單登打（v1 人工模式）

- [x] 店員登入後台 → 看到「本店相關社群」的 **active campaigns 列表**
- [x] 點進一張 campaign → 登打頁面：
  - 快捷欄：手機後 6 碼搜尋 → 自動帶顧客姓名、取貨店
  - 商品自動帶入（campaign 已指定）
  - 填數量、備註 → 存檔
- [x] 驗證規則：
  - `nickname suffix = phone_last_6`（校驗顧客暱稱一致性）
  - `customer.home_store == current_staff.store`（跨店訂單擋）
  - `now <= campaign.closed_at`（結團後 UI 禁止新增）
- [x] 晚到留言處理（Q4-2 Z）：店員可手動**超時補登**，需填「超時登打原因」
- [x] 留言截圖：店員可從登打頁一鍵上傳截圖，綁定本訂單或整個 campaign

### 6.3 訂單狀態機

```
[draft_typed] ← 店員登打中
     ↓ 存檔
[confirmed] ← 已確認（結團前可改）
     ↓ campaign.closed_at
[locked] ← 結團後鎖定
     ↓ 採購下單 → 到貨 → 分揀到店
[arrived] ← 到店
     ↓ rpc_notify_pickup_ready（若該店通知模式 ≠ none）
[ready_for_pickup]
     ↓ 顧客取走
[picked_up] ← 完成
     
分支：
[confirmed] → [cancelled]（結團前顧客取消，軟刪）
[locked] → [shortage]（缺貨未分到）→ [refunded] / [exchanged] / [deferred]
[ready_for_pickup] → [overdue]（超過取貨期限）→ 
    生鮮 [scrapped] / 常溫 [resale_stocked] / 高單價 [awaiting_payment]
[picked_up] → [returned]（當天內退貨）
```

- [x] 所有狀態轉換寫 `order_status_log` append-only
- [x] **不允許硬刪除**（Q13-2）：取消走 `cancelled`、反悔走 `reopen`（限結團前）

### 6.4 結團 + 自動彙總 PR（Q13-1 B）

- [x] Campaign 達 `closed_at` 或 `qty_limit` → 狀態轉 `closed`
- [x] 手動結團：總部按「結團」按鈕 → 立即 close
- [x] 系統自動彙總：
  - 撈出此 campaign 所有 `confirmed` 訂單
  - 按 SKU × 取貨店 分組加總
  - 呼叫採購模組 `rpc_create_suggested_pr(campaign_id, lines[])` → 寫入 `purchase_requests` (status = `draft_suggested`)
- [x] 總部審核 PR → 按「送出」→ 進採購模組正式流程
- [x] 結團後晚到的留言（Q4-2 Z）：
  - 店員可點「補登」→ 系統開新訂單 → `status = post_close_candidate`
  - 若採購已下單 / 仍可加量 → 店員決定是否併單
  - 若已出貨 → 列為**候補**，等有退單或缺貨轉出

### 6.5 到貨 + 驗收

- [x] 物流路徑（Q12-1 A）：**廠商 → 總倉 → 各店**
  - 總倉收貨走「採購模組 `goods_receipt`」
  - 總倉分揀 → 各店走「庫存模組 `transfers`」調撥
- [x] 各店驗收（Q12-2 Z）：
  - 店員當場驗數量 / 品質 → `transfer.received_by`
  - 有問題 → 標記 `discrepancy` + 拍照存檔 → 回報總部協調
  - 店長每週抽查 N 筆 → 寫 `transfer_audit_log`
- [x] 到店 + 驗收通過 → 訂單狀態轉 `arrived`
- [x] 若該店 `notification_mode ≠ none` → 自動呼叫通知模組 `rpc_enqueue_notification(pickup_ready)`

### 6.6 取貨流程（Q6-1 A）

- [x] 店員打開「取貨」頁面 → 輸入手機後 6 碼 → 顯示該顧客所有 `ready_for_pickup` 訂單
- [x] 勾選要取的訂單 → 確認品項 / 數量 → 點「結案」
- [x] 付款方式（Q5-1 B, Q5-2 現金 + 部分店 LINE Pay）：
  - 讀 `stores.allowed_payment_methods` → 顯示該店可用方式
  - v1 支援：`cash`（所有店）、`line_pay`（啟用店）
- [x] **不開發票（Q15 暫定）** — 僅列印簡單收據（顧客要求才給）
  - ⚠️ **法遵風險**：上線前會計師確認；見 §12 Open Question
- [x] 結案：狀態轉 `picked_up`、寫 `pos_sales` 記錄、呼叫庫存 `rpc_outbound`

### 6.7 異常處理

#### 缺貨（Q9-1 A, Q9-2 W）
- [x] 到貨數量 < 訂單需求 → 系統按 `order.created_at` 排序
- [x] 早訂單全量分配、晚訂單分配到 0 → 標記 `shortage`
- [x] 缺貨顧客三選一（UI 讓店員打電話問）：
  - 退款（`refunded`）→ 呼叫付款模組退款；若未付款則直接 close
  - 下次補（`deferred`）→ 下一個同商品 campaign 優先出
  - 換商品（`exchanged`）→ 店員手動改成其他同價位商品

#### 退貨（Q10-1 B+C+D, Q10-2 X+Y）
- [x] 取貨後當天內可退：`picked_up` → `returned`
- [x] 商品類型差異化：
  - 生鮮：當天內
  - 常溫：3~7 天（店家可 per-SKU 設定 `return_window_days`）
- [x] 店員判斷彈性：即使超過期限，店長可覆寫允許退貨
- [x] 退回商品處置：
  - 進「退貨倉」待銷毀（破損 / 過期）
  - 進「瑕疵品倉」可再處理（例：降價賣）
  - 透過 `stock_movements` 記錄
- [x] 退款走付款模組（若現金 → 直接退現、若 LINE Pay → 退至 LINE Pay）

#### 逾期（Q7-1 B+C+D, Q7-2 Y+Z）
- [x] 取貨期限（見通知模組 §6.2：通知錨點起算 5 天 + 公休順延）
- [x] 超過期限 → 狀態轉 `overdue`
- [x] 商品處置（店家 per-SKU 或 per-category 規則）：
  - 生鮮 → `scrapped`（報廢，進 `stock_movements type=scrap`）
  - 常溫 → `resale_stocked`（回架，待降價賣）
  - 高單價（>$500 可設定）→ `awaiting_payment`（店長打電話催款）
- [x] 顧客懲罰（per-store 可調）：
  - 預設：累積 **3 次逾期未取** → 進黑名單
  - 惡意棄單：店長可勾選「直接黑名單」
- [x] 黑名單顧客新下單 → UI 警告店員 → 店員可選擇仍接單（但需備註理由）

### 6.8 改單 / 取消（Q8）

- [x] **結團前**（`campaign.status = open` 且 `order.status = confirmed`）：
  - 顧客透過 LINE 社群再留言或私訊店員
  - 店員在後台手動改數量 / 取消
  - 系統記 `order_change_log`（誰改、什麼時候、改什麼）
- [x] **結團後**：
  - UI 鎖定「改數量 / 取消」按鈕
  - 店長可覆寫（例：退單後有餘量允許加單），需填理由

### 6.9 留言截圖（Q11-2 Y）

- [x] 店員可在 campaign 頁面上傳截圖：
  - `campaign_snapshots`：全局截圖（整個留言區）
  - `order_snapshots`：單筆訂單截圖（某則 +1 留言）
- [x] 截圖存 Supabase Storage，DB 存路徑
- [x] 爭議時店員可 reopen 訂單對照截圖裁決
- [x] 截圖保留期限：與訂單同 7 年（配合稅捐留存）

### 6.10 員工餐（Q14 C + Z）

- [x] 店員於取貨頁勾選「員工購買」
- [x] 價格自動套「員工價」（`product_prices.scope = employee`，per-SKU 或預設 7~8 折）
- [x] 走獨立表 `employee_meals`（不進 `pos_sales`）
- [x] 月結流程：
  - 每月 1 號產出 `employee_meal_statements` 每員工一張
  - 店東核對 → 薪資扣款或現金結清
- [x] 員工餐仍扣庫存（`rpc_outbound` type = `employee_meal`）

---

## 7. Data Model (High Level)

```
post_templates
  id (PK), tenant_id, name, category,
  title_template, body_template,
  variables JSONB,   -- {{price}} 等 placeholder 清單
  version, active,
  created_by, updated_by, created_at, updated_at

post_templates_history
  id, template_id (FK), version, body_template, changed_by, changed_at

line_communities           -- 20 個 LINE 社群
  id (PK), tenant_id, name, channel_type ('community_5000' / 'group'),
  description, owner_id, active

community_stores           -- 社群 × 門市 多對多
  community_id, store_id,
  UNIQUE(community_id, store_id)

campaigns                  -- 團購活動
  id (PK), tenant_id, template_id,
  title, body_text,       -- 實際貼文內容（範本渲染後）
  product_sku, campaign_price NUMERIC(18,2),
  qty_limit INT,
  opened_at, closed_at,
  close_type ('time' / 'qty' / 'manual'),
  status ('draft' / 'open' / 'closed' / 'archived'),
  posted_by, posted_at,
  closed_by, closed_at_actual,
  created_at

campaign_channels          -- campaign × community 多對多（一團可貼多社群）
  campaign_id, community_id,
  UNIQUE(campaign_id, community_id)

campaign_snapshots
  id, campaign_id, file_path, uploaded_by, uploaded_at

customer_orders
  id (PK), tenant_id, campaign_id,
  customer_id (FK members),
  pickup_store_id (FK stores),
  source_nickname TEXT,   -- 保留當下暱稱
  source_raw_text TEXT,   -- 原始留言內容
  source_screenshots TEXT[],  -- 相關截圖路徑
  qty NUMERIC(18,3),
  unit_price NUMERIC(18,2),
  total_amount NUMERIC(18,2),
  is_employee BOOLEAN DEFAULT false,  -- 員工餐旗標
  is_post_close BOOLEAN DEFAULT false, -- 超時補登
  post_close_reason TEXT,
  status (見 §6.3 狀態機),
  created_by, created_at,
  updated_by, updated_at

order_status_log           ← append-only
  id, order_id, from_status, to_status,
  reason, operator_id, occurred_at

order_change_log           ← append-only（改數量 / 內容）
  id, order_id, field_changed, old_value, new_value,
  reason, operator_id, changed_at

order_shortages
  id, order_id,
  resolution ('refund' / 'defer' / 'exchange'),
  exchange_to_sku, note,
  resolved_by, resolved_at

order_returns
  id, order_id, qty_returned,
  reason, disposition ('scrap' / 'defect_stock'),
  approved_by, returned_at

customer_blacklist
  id, tenant_id, customer_id, store_id,
  reason, overdue_count,
  listed_by, listed_at,
  cleared_by, cleared_at,
  status ('active' / 'cleared')

employee_meals
  id, tenant_id, store_id, employee_id,
  order_id (FK customer_orders),
  price NUMERIC(18,2), qty,
  yyyymm INT,  -- 結算月份
  settled BOOLEAN DEFAULT false,
  settled_at

employee_meal_statements
  id, yyyymm, employee_id, store_id,
  total_amount, settled_by, settled_at
```

---

## 8. RPC / API

| RPC | 用途 |
|---|---|
| `rpc_create_campaign(...)` | 總部建立 campaign |
| `rpc_render_post(template_id, variables)` | 渲染貼文文字（供複製用） |
| `rpc_close_campaign(campaign_id, operator)` | 手動結團 |
| `rpc_enqueue_customer_order(campaign_id, customer_id, qty, source_raw_text, nickname, screenshots)` | 店員登打訂單 |
| `rpc_change_order(order_id, new_qty, reason, operator)` | 結團前改數量 |
| `rpc_cancel_order(order_id, reason, operator)` | 取消訂單（軟刪） |
| `rpc_suggest_pr(campaign_id) → pr_id` | 結團後自動彙總產 PR |
| `rpc_resolve_shortage(order_id, resolution, exchange_sku?, operator)` | 缺貨處理 |
| `rpc_pickup_orders(phone_last6, store_id, payment_method, operator)` | 取貨結案 |
| `rpc_return_order(order_id, qty, disposition, operator)` | 退貨 |
| `rpc_mark_overdue_disposition(order_id, disposition, operator)` | 逾期處置（報廢 / 回架 / 催款） |
| `rpc_add_to_blacklist(customer_id, store_id, reason)` | 加黑名單 |
| `rpc_record_employee_meal(order_id)` | 記員工餐 |
| `rpc_generate_monthly_statement(yyyymm)` | 月結員工餐 |

---

## 9. 權限（RBAC 摘要）

| 動作 | 店員 | 店長 | 店東 | 總部行銷 | 總部老闆 |
|---|---|---|---|---|---|
| 看本店訂單 | ✅ | ✅ | ✅ | ✅（全店） | ✅ |
| 登打訂單 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 改 / 取消訂單（結團前） | ✅ | ✅ | ✅ | ❌ | ✅ |
| 改 / 取消訂單（結團後，覆寫） | ❌ | ✅ | ✅ | ❌ | ✅ |
| 取貨結案 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 處理退貨（當天內） | ✅ | ✅ | ✅ | ❌ | ✅ |
| 處理退貨（超期覆寫） | ❌ | ✅ | ✅ | ❌ | ✅ |
| 缺貨分配 | ❌ | ✅ | ✅ | ❌ | ✅ |
| 逾期處置 | ❌ | ✅ | ✅ | ❌ | ✅ |
| 建立 campaign | ❌ | ❌ | ❌ | ✅ | ✅ |
| 結團（手動） | ❌ | ❌ | ❌ | ✅ | ✅ |
| 產建議 PR | ❌ | ❌ | ❌ | ✅ | ✅ |
| 維護貼文範本 | ❌ | ❌ | ❌ | ✅ | ✅ |
| 驗收抽查 | ❌ | ✅ | ✅ | ❌ | ✅ |
| 加 / 解黑名單 | ❌ | ✅ | ✅ | ❌ | ✅ |
| 產員工餐月結 | ❌ | ❌ | ✅ | ❌ | ✅ |

---

## 10. 整合點

- **商品模組**（被讀）：`products` / `skus` / `prices`（team buy price 存於 `campaigns.campaign_price`）
- **會員模組**（被讀）：`members.phone_hash` 查會員 / 手機後 6 碼搜尋索引
- **庫存模組**（被寫）：`rpc_inbound`（到貨）/ `rpc_outbound`（取貨、員工餐、報廢）/ `transfers`（總倉→店）
- **採購模組**（被寫）：`rpc_create_suggested_pr` 產建議 PR
- **通知模組**（被寫）：`rpc_enqueue_notification(pickup_ready / pickup_reminder / pickup_overdue)`
- **銷售模組**（被寫）：`pos_sales`（取貨結案時記錄）、`employee_meals`
- **LINE 社群**（外部，手動）：無 API，全靠人工貼文 / 截圖 / 人工登打
- **Supabase Storage**（外部）：截圖檔案儲存

---

## 11. 非功能需求

- [x] **登打效率**：店員 ≤ 30 秒一筆（手機後 6 碼自動帶入）
- [x] **併發安全**：同一訂單多人同時改 → 樂觀鎖 `version`
- [x] **稽核完整性**：`order_status_log` / `order_change_log` append-only
- [x] **截圖保存**：Supabase Storage，7 年留存
- [x] **資料隔離**：加盟店 RLS 嚴格，不可看其他店訂單
- [x] **結團時效**：`closed_at` 到達 → 5 秒內 UI 反映「已結團」
- [x] **效能**：單店每天 ≤ 500 單可流暢登打；全系統每天 ≤ 5 萬單
- [x] **時區**：所有時間 TIMESTAMPTZ、UI 顯示台北時區

---

## 12. Open Questions — Q1~Q14 已決策，Q15 待會計師確認

### ✅ Q1 發團流程 — **總部統一發，多對多社群映射**（2026-04-21）
- 100 店對應 20 個 LINE 社群（5000 人社群，非群組）
- 社群 × 門市多對多：有些 1:1、有些 1:N

### ✅ Q2 顧客識別與取貨店 — **暱稱規則 `{姓名}-{手機後6碼}-{取貨店}`**（2026-04-21）
- 顧客綁定一店，不可跨店
- 系統靠暱稱解析自動帶入手機與店

### ✅ Q3 訂單登打 — **v1 店員人工登打**（2026-04-21）
- P1 再加 Claude vision 解析截圖

### ✅ Q4 結團規則 — **多型並存**（2026-04-21）
- 常規團 3 天、快速團 1.5 天、限量團（數量結）
- 晚到留言：店員彈性判斷（超時補登需填原因）

### ✅ Q5 付款 — **取貨現場付，現金為主 + per-store LINE Pay**（2026-04-21）

### ✅ Q6 取貨身份驗證 — **手機後 6 碼**（2026-04-21）

### ✅ Q7 逾期處理 — **彈性：商品分類 + 顧客黑名單 3 次制**（2026-04-21）
- 生鮮報廢 / 常溫降價 / 高單價催款
- 累積 3 次未取列黑名單；惡意棄單可一次列入

### ✅ Q8 改單 / 取消 — **結團前可，社群 / 私訊觸發，店員後台改**（2026-04-21）

### ✅ Q9 缺貨分配 — **先到先得 + 缺貨顧客三選一（退款 / 換貨 / 下次補）**（2026-04-21）

### ✅ Q10 退貨政策 — **當天內為原則 + 商品類型差異 + 店員彈性判斷**（2026-04-21）
- 退品分：退貨倉（銷毀）/ 瑕疵品倉（再處理）

### ✅ Q11 貼文管理 — **範本庫 + Campaign 紀錄 + 留言截圖存系統**（2026-04-21）

### ✅ Q12 物流與驗收 — **廠商 → 總倉 → 各店；店員驗收 + 店長抽查**（2026-04-21）

### ✅ Q13 結團銜接採購 — **系統自動彙總建議 PR + 訂單僅軟刪**（2026-04-21）

### ✅ Q14 員工自用 — **員工價 + 員工餐月結流程**（2026-04-21）
- 整合 `employee_meals` 表（與銷售模組既有結構對齊）

### 🟡 Q15 發票政策 — **v1 暫訂「不開發票」，上線前會計師確認** ⚠️

**背景**：
使用者表示目前團購店實務上**不開發票**。但台灣稅法規定月營業額 > NT$20 萬強制開統一發票，100 間加盟店多數可能觸發。

**風險**：
- 被國稅局查到 → 補稅 + 罰款（可能 5~10 倍）
- 加盟店會因此受牽連

**v1 暫定**：
- 系統不實作開發票功能
- 取貨 UI 僅提供「列印簡單收據」供顧客要求時使用
- `pos_sales` 表仍完整記錄交易（稅務需要時可後補發票）

**待決策**：
1. 是否上線前改為「走電子發票」（綠界 / 藍新），**每加盟店自己串**（與 LINE OA 同模式）？
2. 若維持不開發票，是否有其他合法途徑（例如「免用統一發票收據」適用條件）？
3. 諮詢會計師 + 稅務律師取得書面意見。

---

## 13. 下一步
- [ ] Q15 找會計師諮詢 → 決定 v1 發票策略（影響取貨結案流程）
- [ ] 展開 `campaigns` / `customer_orders` schema 細節進 v0.2
- [ ] Spike：單店 500 單 / 日的登打壓力測試（UI 反應速度）
- [ ] Spike：結團後自動彙總 PR 的 SQL 效能（3 社群 × 100 店 × 多 SKU）
- [ ] UI 原型：店員「取貨結案」頁（手機後 6 碼 → 訂單列表 → 結案）
- [ ] UI 原型：總部「建 campaign」頁（選範本 → 填欄位 → 產貼文文字）
- [ ] 制定 Claude vision 解析截圖 P1 POC 範圍

---

## 相關連結
- [[PRD-商品模組]] — `products` / `skus` / `prices`（campaign_price 獨立定價）
- [[PRD-會員模組]] — 手機後 6 碼查會員 / 員工身份
- [[PRD-庫存模組]] — 到貨 `rpc_inbound` / 取貨 `rpc_outbound`
- [[PRD-採購模組]] — 結團自動產建議 PR
- [[PRD-通知模組]] — pickup_ready / pickup_reminder / pickup_overdue
- [[PRD-銷售模組]] — `pos_sales` / `employee_meals`
- [[專案總覽]]
