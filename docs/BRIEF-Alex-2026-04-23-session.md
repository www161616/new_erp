---
title: Alex 接班 Brief — 2026-04-23 香奈 session 全摘
audience: Alex K.T. Chen（alexktchen + alexchenproject）
from: 香奈 via Claude
status: action-required
created: 2026-04-23
related: 21 commits in repo 2026-04-23
---

# Alex：今天香奈跟 Claude 跑了一整天 session、21 commits、方向有大調整

先掃 TL;DR、然後挑有動到你負責部分的節讀細節。

---

## TL;DR（3 分鐘 scan）

| 類別 | 主要變動 | 影響到你的地方 |
|---|---|---|
| **系統立場** | 確立 **C 混合型 ADR**（加盟店自主 + 總部可視 + 總部統一項）| 所有未來 PRD / RLS 設計的決策基準 |
| **Q17 發票政策** | 策略大轉彎：~~綠界新戶 0 元~~ → **ezPay 老客戶擴容** | schema 新增 `stores.invoice_mode` + ezpay_sub_merchant_id；PR #101 之後要做 ezPay 子商店 API 對接 |
| **v0.2 PRD Q&A** | 5 份 addendum（庫存/採購/供應商/訂單/AP）全部 close；商品加 Q14 樂樂建品項 XLS | 設計階段近完成、可進 RPC 實作 |
| **Schema delta** | 新增 1 份 migration `20260424130000_v02_q_closure_delta.sql`（203 行 / 9 段） | **你要 review 這份 migration** — commit `2f6f1f7` |
| **AI vision 策略** | 跑了 7 張 POC；**推翻商品照識別**、轉向「解析已結構化資料」| 3 個新 P0 spike issues (#102/#103/#104) |
| **訂單 §7.3 重寫** | 推翻 `+N 聊天留言` 假設、改為 **LINE 記事本按讚式**（qty 預設 1）| P1 截圖解析路徑完全重設計 |
| **Pilot 決定** | 5 家定案、**5/5 已同意**（桃園平鎮/古華/南平 + 新北林口/三峽）| 5/23 上線 AA 時程需要你 commit 能不能衝 |

---

## 1. 系統立場 ADR（新、最重要）

📄 `docs/decisions/2026-04-23-系統立場-混合型.md`（commit `be534a5`）

**三層劃分 / 核心原則：看得到 ≠ 管得到**

| 層面 | 立場 |
|---|---|
| **數據可視性** | 總部**看得到全部**（抽成、進貨結算）|
| **日常營運** | 加盟店**自主**（發票、LINE OA、促銷、人事、雜支、預算） |
| **總部統一項** | 供應鏈、品牌、會員系統、ERP、發票廠商 |

**RLS 預設模式**（新表都要套這套）：
```sql
-- store-owned + hq-admin all-read
CREATE POLICY p_store_read_own ON <table>
  FOR SELECT USING (store_id = current_setting('app.store_id')::BIGINT
                    OR current_user_role() = 'hq_admin');
```

---

## 2. Q17 發票政策大轉彎（影響 PR #101 後續）

📄 `docs/Q17-電子發票廠商比較.md` v0.2（commit `4e4e915`）
📄 `docs/PRD-訂單取貨模組.md` §7.12（commit `7f277f8`）

### 業務事實（香奈今天才透露）
- 總部**已是 ezPay 基本型 3+ 年客戶**（$4,800/yr 月 100 張 B2B）
- 100 家加盟店**全部目前未開電子發票**（可能有法遵風險）
- ezPay LINE 回覆：**支持多統編獨立帳號、各自開發票、分店明細**

### 架構決定
- **首推 ezPay 老客戶擴容**（不走綠界、轉換成本 > 優惠折扣）
- **per-store 模式**：`stores.invoice_mode ∈ {enabled, manual, none}`，預設 `none`
- **on-demand 開通**：加盟主切到 `enabled` 時、系統呼叫 ezPay 主帳號 API 建立子商店

### 你要做的對接
- ezPay 子商店 API 整合（等香奈拿到書面報價會再 sync）
- `stores.ezpay_sub_merchant_id` 欄位已加（見 §4 migration）
- `rpc_ezpay_provision_sub_merchant(store_id)` 還沒寫、可等 ezPay 確認架構再開

---

## 3. 你要 review 的 Schema Migration

📄 `supabase/migrations/20260424130000_v02_q_closure_delta.sql`（commit `2f6f1f7`，203 行）

**9 段 delta**（基於今天 Q&A 決議）：

| 段 | 內容 | 影響表 |
|---|---|---|
| §1 | `customer_orders` 加 `rollover_opt_out` / `called_at` / `external_order_no` / `external_source` / `ordered_at` | Order |
| §2 | `members.external_id` + `takeout_store_name_hint` / `skus.external_code` | 樂樂 CSV 對應 |
| §3 | **新表 `lele_order_imports`**（append-only staging，JSONB raw + parsed） | 樂樂訂單匯入 |
| §4 | `vendor_payments.cleared_via_hq` + `hq_clearing_leg` + `linked_payment_id` | AP Q6 HQ clearing |
| §5 | `expense_categories.store_id` + `monthly_budget_cents`（+ 放寬 UNIQUE） | AP Q2 per-store 預算 |
| §6 | **Drop `trg_store_as_supplier` trigger**、**新 `ensure_store_supplier(BIGINT)` helper** | AP Q5 on-demand |
| §7 | `stores.tax_id` + `invoice_mode` + `ezpay_sub_merchant_id` + `monthly_revenue_threshold_cents` | Q17 per-store 發票模式 |
| §8 | `products.lele_meta JSONB` | 商品 Q14 樂樂通路 bonus |
| §9 | `lele_order_imports` RLS policy | 新表權限 |

**要 review 的幾點**：
- §5 的 `UNIQUE (tenant_id, COALESCE(store_id, 0), code)` — 我用 COALESCE 0 當 nullable unique workaround，你可能有更好的 partial index 寫法
- §6 我改 trigger 為 helper function，因為 Q5 改為 on-demand（見 `project_new_erp_current_work.md`）
- §7 `monthly_revenue_threshold_cents BIGINT DEFAULT 20000000` — 20 萬 NTD = 20,000,000 cents

---

## 4. v0.2 Q&A 全部 close（5 份 PRD addendum）

| PRD | commit | 主要決議 |
|---|---|---|
| 庫存 v0.2 addendum | `81fa8ad` | 總倉不參與互助、backorder rollover_opt_out 加欄位、net=0 不建 bill、supplier mapping on-demand |
| 採購 v0.2 addendum | `29c5005` | PR 審核 LINE 通知、**1688/拼多多憑證不存、沒 API** |
| 供應商整合 v0.2 | `a883f89` | Sheets tab 不偵測、歷史不匯、**1688/拼多多都走手動 CSV 上傳** |
| 訂單 v0.2 addendum | `9e88947` | **樂樂訂單 CSV 23 欄 mapping 定義完**、波次自動 defer、called_at 欄位 |
| AP v0.2 PRD | `f074405` | Q1~Q6 全 close + schema delta（已 merge 進 migration）|

### 1688 / 拼多多的大事（你要注意）

**香奈明確拒絕存憑證、沒 API 能用**。v1 路線是：
- 採購員手動下載 CSV / Excel → 後台上傳 → AI 解析（spike issue #103）
- 不做自動 scraping、不存帳密、不串 API

---

## 5. AI Vision POC（今天跑了 7 張實物）

📄 `docs/POC-2026-04-23-vision-reality-check.md`（commit `1453899`）

### 重要發現

**推翻**：
- ❌ 拍商品實物照建檔（70~80% 商品無標籤 — 香奈揭露）
- ❌ 手寫發票 OCR 入帳（錯誤率高 + 量分散）
- ❌ 電子發票 vision 解析（走財政部 API 更乾淨）

**高 ROI spike（3 個 P0 issue）**：
- **#102** 團購記事本貼文解析 → 每天省 1.5-2 小時（香奈自寫、格式穩定、🥇 最該做）
- **#103** 1688 / 拼多多商品頁解析 → 陸貨建檔、每週省 2-8 小時
- **#104** LINE 記事本按讚名單解析 → 訂單登打（每日大量）

每個 issue 都有：acceptance criteria / 目標 JSON schema / golden dataset 要求 / complexity 估計。可直接 kickoff。

### 業務事實新增

香奈今天揭露：
1. **顧客下單都在 LINE 記事本**按讚（不在聊天訊息）→ 推翻 `+N` 留言假設
2. **每天開團 21-30 樣**、70~80% 商品無標籤（生鮮 / 陸貨）

存記憶：
- `memory/project_new_erp_line_order_reality.md`
- `memory/project_new_erp_product_reality.md`

---

## 6. 訂單 §7.3 重寫（你原本寫的 +N 假設被推翻）

📄 `docs/PRD-訂單取貨模組.md` §7.3（commit `91f8d8e`）

### 原本的假設
> 上傳 LINE 頻道截圖 → Claude Haiku vision → 回傳 `[{nickname, orders: [{sku_id, qty, action}]}]`

### 新的兩段式流程
**A. 按讚名單解析**（issue #104）
- 輸入：LINE 記事本按讚列表截圖
- 輸出：`[{raw_nickname, parsed_store_hint, default_qty: 1, reaction_time}]`
- qty 預設 1、不試圖從按讚推數量

**B. 留言數量補充**（次要）
- 顧客需 qty > 1 會留言寫
- v1 手動改 qty、P2 才做第二段 vision

### 反模式（明確寫進 PRD、不要做）
- 解析 LINE 一般聊天找 `+N`（那裡沒人喊單）
- 從按讚推數量
- 商品實物照辨識

---

## 7. Pilot 5 家定案（5/5 已同意）

📄 `docs/PILOT-2026-04-23-選店策略.md` v4（commit `80071ff`）

### 名單
| # | 店 | 配合度 | HQ 車程 |
|---|---|---|---|
| 1 | 桃園 平鎮 | 100% | 市內 |
| 2 | 桃園 古華 | 80% | 市內 |
| 3 | 桃園 南平 | 50%（中立） | 市內 |
| 4 | 新北 林口 | 80% | 30-45 min |
| 5 | 新北 三峽 | 90% | 45-60 min |

### 時程兩版（**需要你評估哪個現實**）

**方案 AA — 5/23 上線**（香奈選的）：
- W1 (4/23-4/30): 選店 + 意願 ✅ 已完成
- W2-4 (5/1-5/22): **工程衝刺 3 週**（RPC / 管理後台 / ezPay API）
- W5-8 (5/23-6/20): Pilot 跑 4 週
- **硬核前提**：**你 full-time 衝刺 3 週**

**方案 BB — 7/1 上線**（安全版）：
- 5 月工程、6 月測試 + onboarding、7/1 上線、7-8 月 pilot

### 你要回答：
1. **AA 5/23 上線可行嗎？**（可行 / 不可行 / 可行但要砍功能）
2. 若可行、**需要砍什麼功能**才趕得上？
3. 若不可行、**BB 7/1 你能 deliver 哪些**？

---

## 8. 其他 reality check（影響你的工作流）

### 教育訓練哲學（香奈裁定）
- 📄 `memory/project_new_erp_training_philosophy.md`
- **不寫長手冊**、**不開訓練週**
- 上線當天 30 分鐘 on-boarding + LINE 一對一即時教學 + FAQ 滾動累積
- UI 設計時要考慮「0 訓練也能用」

### 加盟主溝通風格
- 📄 `memory/project_new_erp_franchise_comms_style.md`
- 不簽 MOU、不包裝、沒誘因、不講退出機制
- pilot 談話 one-liner：「有新系統要試、4 週、照常用、有問題 LINE 我」

### 團隊
- 📄 `memory/project_new_erp_team.md`
- 香奈（業主）＋ 你（工程）= 核心二人

---

## 9. 給你的問題清單（請回覆）

**🔴 最高優先（影響 AA/BB 時程決定）**
1. AA 5/23 上線時程你能 commit 嗎？full-time 3 週？
2. PR #101 要不要本週 merge？merge 後直接在 main 衝 RPC？
3. Schema delta migration `2f6f1f7` 你 review 過嗎？有要改嗎？

**🟡 中優先（工程規劃）**
4. 3 個 spike issues #102/#103/#104 你自己寫還是找人？
5. ezPay 子商店 API 整合你擔任？等書面報價到位後啟動？
6. PR #101 的 Next.js 16 / Tailwind 4 / static export → GitHub Pages deploy workflow 你排什麼時候？

**🟢 低優先（有空處理）**
7. 今天 PRD 大動有沒有你覺得需要反駁 / 調整的地方？
8. 商品模組 HTML mockups → Next.js 元件移植時程？
9. LIFF 前端 PRD 需不需要對齊 LINE 記事本下單現實（§7.3 新版）？

---

## 10. 建議閱讀順序

如果只讀 30 分鐘，照這個順序：

1. **這份 BRIEF**（你現在看的）
2. `docs/decisions/2026-04-23-系統立場-混合型.md` — **5 分鐘**
3. `supabase/migrations/20260424130000_v02_q_closure_delta.sql` — **10 分鐘**，**請 review**
4. `docs/POC-2026-04-23-vision-reality-check.md` — **5 分鐘**（翻翻 TL;DR + ROI 表）
5. `docs/PILOT-2026-04-23-選店策略.md` v4 — **5 分鐘**
6. GitHub issues #102 / #103 / #104 — 各 2 分鐘

如果有更多時間：
7. `docs/PRD-訂單取貨模組.md` §7.3（新版）+ §7.12（新增）+ §13 Q17（部分解）
8. `docs/Q17-電子發票廠商比較.md` v0.2
9. 5 份 v0.2 PRD addenda 的 Open Questions section
10. `memory/` 所有 `project_new_erp_*` 檔（掌握業務事實）

---

## 11. 今天所有 commit 清單（時間序）

```
2494856 docs(order): Q17 e-invoice vendor comparison (A'-2)
be534a5 docs(decision): C 混合型系統立場 ADR
f074405 docs(ap): close Q1~Q6 per C 混合型 ADR
81fa8ad docs(v0.2): close Open Questions [庫存]
29c5005 docs(v0.2): close Open Questions [採購]
a883f89 docs(v0.2): close Open Questions [供應商]
9e88947 docs(v0.2): close Open Questions [訂單]
1c9ca0f docs(product): add Q14 樂樂建品項 XLS export
2f6f1f7 feat(db): v0.2 Q-closure delta migration ← 你要 review
4649ae4 docs(g): ADR cross-ref [通知]
0d2dfac docs(g): ADR cross-ref [訂單]
1088308 docs(g): ADR cross-ref [會員]
7f277f8 docs(l): per-store invoice mode → Order §7.12
a8015d5 docs(l): per-store invoice mode → Notif §6.1
4e4e915 docs(q17): v0.2 pivot to ezPay 老客戶擴容
1453899 docs(poc): vision reality check
91f8d8e docs(order §7.3 §14): 記事本按讚式
f605583 docs(pilot): v1 選店策略
e161bfc docs(pilot): v2 簡化
e802150 docs(pilot): v3 5 家名單
80071ff docs(pilot): v4 意願全數確認
```

**issues**：#102 / #103 / #104（三個 P0 spike）

---

## 附：若你 AA 不可行

香奈的 fallback 清楚：**自動降為 BB（7/1 上線）**。不是災難、只是多 1 個月準備時間。誠實告訴他就好、不用硬撐。
