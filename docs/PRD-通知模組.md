---
title: PRD - 通知模組
module: Notification
status: draft-v0.1
owner: www161616
created: 2026-04-21
updated: 2026-04-21
tags: [PRD, ERP, 通知, Notification, LINE, OA]
---

# PRD — 通知模組（Notification Module）

> 零售連鎖 ERP，總倉 1 + 門市 100 + SKU 15,000。
> 本模組負責「何時、對誰、透過什麼管道、發什麼訊息」，以及「送達 / 失敗 / 重試」的稽核。
> v0.1 checklist 版（Q1~Q11 已決策，Q12 待使用者評估）。

---

## 1. 模組定位
- [x] **事件驅動**：其他模組（訂單 / 庫存 / 採購）發事件，本模組消費
- [x] 統一 **訊息發送管道**：v1 只接 LINE（顧客走 OA、店長走群組）；簡訊 / Email 未來再開
- [x] 統一 **訊息範本 / 變數代入**（總部預設、店長可微調）
- [x] **失敗不擋業務主流程**：送不到只記錄、不 rollback 上游（例如訂單仍算成立）
- [x] **不承擔會員生命週期通知**（生日 / 升等 / 點數到期 / 儲值金餘額）— v1 明確排除
- [x] 其他模組 **不得直接呼叫 LINE API**，一律透過本模組 RPC（`rpc_enqueue_notification`）

---

## 2. 核心概念 / 名詞定義
- [x] **通知事件（Event）**：由上游模組產生的訊號，如「訂單到貨」「快過期」
- [x] **通知類型（Notification Type）**：對應的通知種類 code，如 `pickup_ready` / `pickup_reminder`
- [x] **範本（Template）**：特定通知類型的訊息格式（含變數 placeholder），總部出預設、店長可覆寫
- [x] **通知記錄（Notification Log）**：每一則實際發出的通知，狀態 = `queued / queued_deferred / sent / failed / blocked`
- [x] **收件人（Recipient）**：顧客（`line_user_id`）或店長群組（`line_group_id`）
- [x] **時段規則（Quiet Hours）**：僅允許發送的時間窗（顧客 09:00–21:00；店長全天）
- [x] **失敗清單（Failure List）**：`status = failed / blocked` 的後台清單，供店長人工跟進
- [x] **公休日（Off Day）**：每店自行設定的休息日，影響取貨期限計算

---

## 3. Goals
- [x] G1 — 訂單到貨、觸發顧客通知 ≤ 10 秒內排入佇列
- [x] G2 — 佇列中的通知 95% 以上 ≤ 60 秒內送達 LINE API
- [x] G3 — 失敗清單可在後台即時查看，店長可一鍵「標記已電聯」
- [x] G4 — 每月統計報表一鍵產出（總發送數、失敗數、各類型分布）
- [x] G5 — 時段外產生的顧客通知自動延至隔天 09:00 發送

---

## 4. Non-Goals（v1 不做）
- [x] ❌ 下單成功確認通知（顧客在 LINE 社群對話中已確認）
- [x] ❌ 會員相關通知（生日 / 點數到期 / 會員升等 / 儲值金餘額低）
- [x] ❌ 庫存過低警示（採購端另案處理）
- [x] ❌ 簡訊 / Email 備援（LINE 送不到 → 店長打電話跟進）
- [x] ❌ 顧客端細分類 opt-out（顧客要全關只能封鎖 OA）
- [x] ❌ 即時 dashboard（v1 只做每月報表，P1 再升級）
- [x] ❌ EDM / 行銷推播 / A/B test
- [x] ❌ P2P 客服對話（非通知範圍）
- [x] ❌ **店長群「新訂單通知」**（Q7 決定：店員直接看後台訂單列表）

---

## 5. User Stories

### 顧客
- [x] 作為顧客，我要在商品到店當天收到 LINE 通知，告知訂單編號與取貨期限
- [x] （v1 決策待 Q12）作為顧客，我要在取貨期限前 1 天收到提醒，避免忘記取
- [x] （v1 決策待 Q12）作為顧客，我要在逾期後收到通知，知道商品如何處理

### 店長
- [x] 作為店長，我要收到「商品快過期」警示，優先安排出貨或促銷
- [x] 作為店長，我要收到「顧客逾期未取」通知，安排電話跟進
- [x] 作為店長，我要能在後台看「送不到的失敗清單」（限本店），勾選「已電聯」
- [x] 作為店長，我要能微調本店範本（例如加開店時間、地址）
- [x] 作為店長，我要能看本店每月發送統計

### 總部
- [x] 作為總部，我要維護全系統預設範本
- [x] 作為總部，我要看到全系統每月發送報表（總量、失敗率、各類型分布）
- [x] 作為總部，我要看全部門市的失敗清單

---

## 6. Functional Requirements

### 6.1 通知類型清單（v1）

> ⚠️ Q7 已決策：移除 `store_new_order`（店員看後台）
> ⚠️ Q12 評估中：視成本方案，`pickup_reminder` / `pickup_overdue` 可能移除

| 代碼 | 對象 | 觸發事件 | 時機 | 時段限制 | 狀態 |
|---|---|---|---|---|---|
| `pickup_ready` | 顧客 | 訂單到店（`goods_receipt` 綁定 `customer_order`）| 立即 | 09:00–21:00 | ✅ 確定保留 |
| `pickup_reminder` | 顧客 | 每日 09:00 job 掃描（到貨後第 4 天）| 批次 | 09:00–21:00 | 🟡 待 Q12 |
| `pickup_overdue` | 顧客 | 每日 09:00 job 掃描（到貨後第 6 天）| 批次 | 隨時 | 🟡 待 Q12 |
| `store_expiry_alert` | 店長 | 每日 08:00 job **彙整一則** | 批次 | 全天 | ✅ 確定保留 |
| `store_pickup_overdue` | 店長 | 每日 09:00 job 掃描 | 批次 | 全天 | ✅ 確定保留 |
| ~~`store_new_order`~~ | ~~店長~~ | — | — | — | ❌ Q7 移除 |

### 6.2 取貨期限（含公休日順延）
- [x] 預設 **5 天**（可由總部 `tenant_config` 覆寫）
- [x] **錨點**：從**實際發送 `pickup_ready` 通知當天**起算（Q10-1 B）
  - 若到貨時間在 21:00 後 → 通知延到隔天 09:00 發 → 5 天從隔天起算
  - 避免顧客因通知延遲而少掉取貨時間
- [x] **公休日順延**（Q10-3）：若 5 天期限終點落在該店公休日 → 自動順延到下個營業日
- [x] **每店公休日自訂**（Q10-2 E）：`stores.off_days` JSONB 欄位，存週幾 / 特定日期
- [x] **通知照樣發**：公休日仍會發送到貨通知（顧客自行規劃）
- [x] `pickup_reminder` 發送日：`通知錨點 + 4 天`（若遇公休順延後 + 4 天）
- [x] `pickup_overdue` 發送日：`通知錨點 + 6 天`

### 6.3 範本管理（Q1 風格決策）
- [x] **語氣風格**：統一採**友善親切**（因顧客以婆婆媽媽為主）
  - 範例：「嗨～您訂的東西到囉 😊 訂單 #{{order_no}}，5 天內來拿唷！地址：{{store_address}}」
  - 不用商務正式、不用俏皮（年齡層差異）
- [x] `notification_templates` 兩層：
  - `scope = tenant`：總部層級預設
  - `scope = store, scope_id = store_id`：店長覆寫
- [x] 優先序：店長覆寫 > 總部預設
- [x] 標準變數：`{{customer_name}}` / `{{order_no}}` / `{{pickup_deadline}}` / `{{store_name}}` / `{{store_address}}` / `{{store_phone}}` / `{{order_items}}`
- [x] **隱私遮罩規則（Q6）**：店長群組通知中 `{{customer_name}}` / `{{customer_phone}}` **一律遮罩**
  - 姓名：`王**`、手機：`0912-***-678`
  - 完整資料需店長登入後台查看
- [x] 範本修改走版本化（`notification_templates_history`），可回溯

### 6.4 時段與批次發送規則
- [x] 顧客端 `quiet_hours = {start: 21:00, end: 09:00}`，對 `pickup_ready` / `pickup_reminder` 生效
- [x] 超出時段 → `status = queued_deferred`，`scheduled_at` 設隔天 09:00，由 job 批次放行
- [x] `pickup_overdue`（顧客）+ 所有店長通知 → 不受時段限制
- [x] **定時 job 排程**：
  - 每日 **08:00**：`store_expiry_alert` 彙整發送（Q8 B）
  - 每日 **09:00**：`pickup_reminder` / `pickup_overdue` / `store_pickup_overdue` 批次發送（Q4 A）

### 6.5 發送流程
- [x] 上游呼叫 `rpc_enqueue_notification(...)` → 寫入 `notification_logs`（`status = queued` 或 `queued_deferred`）
- [x] Worker（Supabase Edge Function / Cron）輪詢 queue → 渲染範本 → 打 LINE API
- [x] 成功 → `status = sent`，記 `sent_at`、`line_message_id`
- [x] 失敗（API 錯誤）→ `status = failed`，記 `error_code`、`error_detail`
- [x] 顧客封鎖 OA 特例 → `status = blocked`（與一般 failed 區分，失敗清單呈現不同提示）

### 6.6 失敗處理與重試
- [x] **系統不自動重試**（避免對封鎖用戶的疲勞轟炸）
- [x] **顧客無 `line_user_id` 特例**（Q3 B）：系統每日自動重試一次，等顧客補加 OA 後自動補發
  - 若超過 `pickup_overdue` 觸發日仍未綁 → 自動停止重試、轉入失敗清單
- [x] 失敗自動進「失敗清單」頁面
- [x] 店長手動動作：`標記已電聯 / 新增備註 / 重發`
- [x] **重發限制（Q9 D）**：
  - 同一則 `notification_log` 最多重發 **3 次**
  - 兩次重發間隔至少 **10 分鐘**（冷卻時間）
  - 重發走新 `notification_logs` 列（不改原失敗列，保留稽核）
- [x] **失敗清單保留（Q11 B）**：90 天後自動 `archive`（資料仍在、UI 不再顯示），總部可查歷史

### 6.7 統計報表
- [x] 每月自動產生：`notification_monthly_reports` 物化表（每月 1 號 02:00 job）
- [x] 欄位：`yyyymm, type, store_id, total_sent, total_failed, total_blocked`
- [x] 後台頁面：類型 × 門市 × 月份 三維查詢；店長只能看本店；行銷 / 總部看全部

### 6.8 顧客綁定 LINE OA 策略（Q2 C）
- [x] **雙管齊下**：
  - 所有 LINE 社群**置頂貼文**放「請加入 XX 團購店 LINE 官方帳號」QR code + 連結
  - 店員看到 +1 留言時**確認顧客是否已加 OA**；未加 → 私訊補推 OA 連結
- [x] 綁定流程：顧客加 OA → 系統收 webhook → 若能透過手機號 / LIFF 綁定對應會員 → 寫入 `member_line_bindings`
- [x] 無 `line_user_id` 的顧客：走 §6.6 每日重試流程（Q3 B）

---

## 7. Data Model (High Level)

```
notification_templates
  id (PK), tenant_id, scope (enum: tenant / store), scope_id,
  type (code), body (含 {{vars}}), version, active,
  created_by, updated_by, created_at, updated_at

notification_templates_history
  id, template_id (FK), version, body, changed_by, changed_at

notification_logs                 ← append-only
  id (PK), tenant_id, type (code),
  recipient_type (customer / store_group), recipient_id,
  variables JSONB, rendered_text,
  status (queued / queued_deferred / sent / failed / blocked / archived),
  scheduled_at, sent_at, line_message_id,
  error_code, error_detail,
  source_module, source_ref_id,      -- 上游事件來源（冪等 key）
  resend_count INT DEFAULT 0,        -- 重發次數（Q9 上限 3）
  parent_log_id UUID,                -- 若為重發，指向原 log
  created_at

notification_failure_followups
  id (PK), notification_log_id (FK),
  action (called / noted / resent), note,
  operator_id, created_at

notification_monthly_reports       ← 物化
  id, tenant_id, yyyymm, type, store_id,
  total_sent, total_failed, total_blocked,
  last_calculated_at

-- 跨模組（這張表實際上屬於 stores 表擴充）
stores
  ...,
  off_days JSONB,      -- Q10-2 公休日，格式 {"weekly": [0, 6]} 或 {"dates": ["2026-05-01"]}
  line_group_id TEXT,  -- Q5 一店一群（店長群組）
```

---

## 8. RPC / API

| RPC | 用途 |
|---|---|
| `rpc_enqueue_notification(p_type, p_recipient_type, p_recipient_id, p_variables, p_source_module, p_source_ref_id)` | 上游模組排入通知 |
| `rpc_mark_followup(p_log_id, p_action, p_note, p_operator)` | 店長標記失敗已處理 |
| `rpc_resend_notification(p_log_id, p_operator)` | 店長重發（含冷卻 + 上限檢查） |
| `rpc_upsert_template(p_scope, p_scope_id, p_type, p_body, p_operator)` | 新增 / 更新範本 |
| `rpc_compile_template(p_type, p_scope_id, p_variables) → text` | 純函數，前台預覽用 |
| `rpc_monthly_report(p_yyyymm, p_store_id?) → json` | 報表查詢 |
| `rpc_compute_pickup_deadline(p_received_at, p_store_id) → date` | 計算取貨期限（含公休順延） |

---

## 9. 權限（RBAC 摘要）

| 動作 | 店員 | 店長 | 行銷 | 總部老闆 |
|---|---|---|---|---|
| 看失敗清單（本店）| ❌ | ✅ | ❌ | ✅ |
| 看失敗清單（全店）| ❌ | ❌ | ❌ | ✅ |
| 標記已電聯 / 備註 | ❌ | ✅ | ❌ | ✅ |
| 重發通知 | ❌ | ✅ | ❌ | ✅ |
| 編輯本店範本 | ❌ | ✅ | ❌ | ✅ |
| 編輯總部預設範本 | ❌ | ❌ | ❌ | ✅ |
| 看每月報表（本店）| ❌ | ✅ | ✅ | ✅ |
| 看每月報表（全店）| ❌ | ❌ | ✅ | ✅ |
| 手動觸發 job | ❌ | ❌ | ❌ | ✅ |
| 設定店長群組 `line_group_id` | ❌ | ❌ | ❌ | ✅ |

---

## 10. 整合點

- **訂單 / 取貨模組**（上游，待建）：觸發 `pickup_ready` / `pickup_overdue`
- **採購 / 收貨模組**（上游）：`goods_receipts.received_at` → 起算取貨期限
- **庫存模組**（上游）：`stock_lots.expiry_date` 臨近 → 觸發 `store_expiry_alert`
- **會員模組**（被讀）：解出顧客 `line_user_id`（`member_line_bindings`）
- **主檔 / 門市**（被讀）：`stores.off_days` / `stores.line_group_id`
- **LIFF 前端**（另案）：若未來開 opt-out 頁面會來呼叫本模組 API
- **LINE OA / Messaging API**（外部）：實際送達管道

---

## 11. 非功能需求

- [x] **延遲**：事件 → 排入 queue ≤ 10s；queue → 送達 95% ≤ 60s
- [x] **可用性**：LINE API 中斷時 queue 累積、不丟訊息、人為恢復後重試（P1）；v1 失敗即止
- [x] **冪等**：同一 `source_module + source_ref_id + type` 在 24h 內只能成功送出一次（避免重發）
- [x] **稽核**：`notification_logs` append-only；所有狀態轉換都有時間戳
- [x] **法遵**：範本需包含「取消訂閱」指引（說明封鎖 OA 即停止通知）；店長群組資料遮罩避免個資外洩
- [x] **監控**：失敗率 > 5% / 小時 → 告警總部

---

## 12. Open Questions

### ✅ Q1 訊息語氣 / 情感風格 — **友善親切**
顧客以婆婆媽媽為主 → 採 B 友善風。
範例：「嗨～您訂的東西到囉 😊 訂單 #{{order_no}}，5 天內來拿唷！」
（2026-04-21）

### ✅ Q2 顧客 `line_user_id` 綁定策略 — **雙管齊下**
- LINE 社群置頂貼文放 OA QR code
- 店員看到 +1 留言 → 確認是否已加 OA → 未加者私訊補推
（2026-04-21）

### ✅ Q3 無 `line_user_id` 的顧客怎麼辦 — **系統每日自動重試**
Worker 每日掃一次「未綁定」的通知 → 若顧客已補綁 → 自動補發；超過 `pickup_overdue` 觸發日仍未綁 → 轉入失敗清單由店長跟進。
（2026-04-21）

### ✅ Q4 `pickup_reminder` 掃描策略 — **固定每日 09:00 統一發**
婆婆媽媽早上看手機機率高，時間寬鬆但實作簡單。
（2026-04-21）

### ✅ Q5 店長群組管理 — **一店一群 + 原群組交接**
- 一店設一個 LINE 工作群（店長 + 副店 + 資深店員）
- 店長離職：新店長直接被邀請加入原群組（不重建）
- `stores.line_group_id` 由總部維護
（2026-04-21）

### ✅ Q6 範本變數隱私 — **店長群組全部遮罩**
姓名遮罩（王**）、手機遮罩（末 3 碼）；店員要看完整資料需登入後台。
（2026-04-21）

### ✅ Q7 `store_new_order` 合流策略 — **不發此通知**
店員直接看後台訂單列表（避免高峰期刷屏）。
通知類型清單從 6 種縮至 5 種。
（2026-04-21）

### ✅ Q8 `store_expiry_alert` 合流策略 — **每日 08:00 彙整一則**
每店每日一則，列出當日需優先處理的臨期商品清單。
（2026-04-21）

### ✅ Q9 重發限制 — **10 分鐘冷卻 + 最多 3 次**
避免手滑連按、避免疲勞轟炸顧客。
（2026-04-21）

### ✅ Q10 跨時段延遲 + 公休日 — **通知錨點起算 + 公休順延**
- **Q10-1**：取貨 5 天期限從「實際發送通知當天」起算（不從到貨當天）
- **Q10-2**：每店自行設定公休日（`stores.off_days`）
- **Q10-3**：公休日照樣發通知；5 天期限若落在公休日自動順延到下個營業日
（2026-04-21）

### ✅ Q11 失敗清單保留期限 — **90 天後 archive**
資料仍保留（總部可查歷史），前台清單不再顯示。
（2026-04-21）

### 🟡 Q12 LINE OA 成本方案 — **使用者評估中（A 精簡版 / C 零推播版）**

**背景**：LINE OA 專業方案 $1,800/月僅含 25,000 則推播，原 PRD 預估需 ~9 萬則。使用者覺得 $1~2 萬/月太貴，考慮縮小通知範圍。

**方案 A — 精簡版（約 $3,400 / 月）**
- 顧客端：**只發 `pickup_ready`**（移除 `pickup_reminder` 和 `pickup_overdue`）
- 店長端：保留 `store_expiry_alert` 和 `store_pickup_overdue`
- 顧客未取改由店長看後台「未取清單」手動打電話 / LINE 私訊
- 預估月量：約 3.3 萬則 → 專業方案 $1,800 + 超量 $1,600

**方案 C — 零推播版（$0 / 月）**
- 完全不發 LINE 推播
- 顧客自己看 LINE 社群公告 / LIFF 查詢
- 店長只看後台
- 對婆婆媽媽客群**非常不友善**

**使用者決策後，需更新：**
- §5 User Stories（移除顧客 pickup_reminder / pickup_overdue 相關 story）
- §6.1 通知類型表（移除對應列）
- §4 Non-Goals（增加明確排除）

（待決策）

---

## 13. 下一步
- [ ] 使用者決定 Q12（A 精簡版 或 C 零推播版）→ PRD 進入 v0.2
- [ ] 確認「訂單 / 取貨模組」PRD 後補事件來源對齊（本模組消費）
- [ ] Spike：LINE Messaging API 發送節流（100 則 / 分鐘）
- [ ] Spike：`line_user_id` 綁定流程（含 LIFF 首綁）
- [ ] LINE OA 月推播量實際估算（抓 pilot 門市一週真實資料）

---

## 相關連結
- [[PRD-會員模組]] — `line_user_id` 來源
- [[PRD-訂單取貨模組]] — 主要事件來源（待建）
- [[PRD-庫存模組]] — `stock_lots` 臨期事件來源
- [[PRD-採購模組]] — `goods_receipts` 收貨事件來源
- [[專案總覽]]
