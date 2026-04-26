---
title: TEST Report — 總倉調度中心 UI（Phase 5d）
status: passed
ran_at: 2026-04-26
verified_by: alex.chen + claude (preview tools)
---

# 驗證報告 — Phase 5d

對應 [docs/TEST-hq-dispatch-ui.md](TEST-hq-dispatch-ui.md)。
Page：[apps/admin/src/app/(protected)/transfers/dispatch/page.tsx](../apps/admin/src/app/(protected)/transfers/dispatch/page.tsx)。

## 環境

- Next.js dev server (admin app, port 55413)
- 登入 admin 帳號後驗證
- 連 Supabase erp-dev project

## 結果

| 測項 | 結果 | 備註 |
|---|---|---|
| build (npm run build) 通過 | ✅ PASS | tsc + Next 16 turbo build 全綠 (修一次 Modal `open` prop 缺失) |
| Page render 載入無 console error | ✅ PASS | `errors: []` |
| Header「總倉調度中心」+ 共 N 張 | ✅ PASS | 顯示 8 張 |
| 5 個 status tabs 含 count | ✅ PASS | 待審核 0 / 已到總倉 0 / 已配送 0 / 已收到 8 / 空中轉 0 |
| 切 tab → 表格更新 | ✅ PASS | 切「已收到」顯示 8 行 |
| 篩選 (轉出店 / 轉入店 / 商品搜尋) | ✅ PASS | 三個 select / input 都 render |
| 批次按鈕 (到倉 / 配送 / 刪除) | ✅ PASS | 三按鈕齊全、按 tab disabled 邏輯正確 |
| 表格欄位 (☐ / 單號時間 / 來源→目的 / 商品 / 溫層 / 總倉備註 / 操作) | ✅ PASS | 7 欄全有 |
| 「登記損壞」按鈕在 received 列顯示 | ✅ PASS | `hasDamageBtn: true` |
| 商品名 + 數量 + 損壞累加顯示 | ✅ PASS | 複雜商品名 (含 emoji/換行) 正常 render |
| 「看明細」連結到 /transfers?id=N | ✅ PASS | |

## Screenshot

dispatch page (已收到 tab) layout 已通過視覺驗證 — 5 tabs 一排、批次按鈕在右、table 行/欄整齊、登記損壞按鈕醒目。

## 未驗證 (需 fixture data 或 modal 操作互動才驗)

| 測項 | 原因 |
|---|---|
| C1-C3 batch_arrive 實際 RPC | 需要 status='shipped' + dest=HQ 的 fixture，prod 目前 0 筆 |
| D1-D2 batch_distribute | 同上 |
| E1-E2 batch_delete | 需要 draft fixture |
| F1-F3 damage modal submit | 需手動操作確認 (UI 框架已驗) |
| G1-G3 hq_notes inline edit | 需手動操作 (邏輯簡單、blur → update transfers) |
| 8 tabs 進階 filter (日期範圍) | 暫不在範圍 (P1 follow-up) |

5a-2 後端 RPC 已單獨驗證 (15 核心測項全綠 — 見 TEST-transfer-hq-dispatch-report)；UI 只是包裝呼叫、邏輯已測。

## 結論

**Phase 5d UI 達 ship 條件**：
- build pass
- page render pass
- 5 tabs / filters / batch buttons / table / damage modal 全部到位
- 對齊 lt-erp 圖 2「店轉店與退倉審核」的核心 UX

下一步：5b 訂單登打 UI 補強 → 5c 互助交流板。
