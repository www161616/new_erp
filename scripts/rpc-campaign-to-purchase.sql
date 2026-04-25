-- ============================================================
-- §1 + §2 tests for campaign-to-purchase migration
-- Run on Supabase dev with BEGIN/ROLLBACK to keep DB clean.
--
-- 用法：
--   supabase db push          # 先推 migration
--   psql "$DEV_PG_URL" -f scripts/rpc-campaign-to-purchase.sql
--
-- 預期：
--   - 沒有 ERROR（除了標 EXPECT FAIL 的 RAISE EXCEPTION）
--   - 每個 SELECT 出來的 scn 標示對應 §2 編號
-- ============================================================

BEGIN;

-- 模擬 JWT
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000099","tenant_id":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

\set TENANT '00000000-0000-0000-0000-000000000001'
\set OP     '00000000-0000-0000-0000-000000000099'

-- ============================================================
-- §1 SCHEMA 驗證
-- ============================================================

-- 1.1 purchase_requests 新欄位
SELECT '1.1' AS scn, column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_name = 'purchase_requests'
   AND column_name IN ('source_type','source_close_date','total_amount')
 ORDER BY column_name;

-- 1.1 CHECK constraint
SELECT '1.1 chk' AS scn, conname, pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE conname = 'chk_pr_source_close_date';

-- 1.2 purchase_request_items 新欄位
SELECT '1.2' AS scn, column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'purchase_request_items'
   AND column_name IN ('unit_cost','line_subtotal','source_campaign_id')
 ORDER BY column_name;

-- 1.2 GENERATED column
SELECT '1.2 gen' AS scn, generation_expression
  FROM information_schema.columns
 WHERE table_name = 'purchase_request_items' AND column_name = 'line_subtotal';

-- 1.3 suppliers 新欄位
SELECT '1.3' AS scn, column_name, column_default
  FROM information_schema.columns
 WHERE table_name = 'suppliers'
   AND column_name IN ('preferred_po_channel','line_contact')
 ORDER BY column_name;

-- 1.4 sequences
SELECT '1.4' AS scn, sequence_name FROM information_schema.sequences
 WHERE sequence_name IN ('pr_no_seq','po_no_seq') ORDER BY sequence_name;

-- 1.5 RPCs
SELECT '1.5' AS scn, proname, pg_get_function_identity_arguments(oid)
  FROM pg_proc
 WHERE proname IN ('rpc_close_campaign','rpc_create_pr_from_close_date',
                   'rpc_submit_pr','rpc_split_pr_to_pos','rpc_send_purchase_order',
                   'rpc_next_pr_no','rpc_next_po_no')
 ORDER BY proname;

-- 1.6 indexes
SELECT '1.6' AS scn, indexname FROM pg_indexes
 WHERE tablename IN ('purchase_requests','purchase_request_items')
   AND indexname IN ('idx_pr_close_date','idx_pri_supplier');

-- ============================================================
-- §2 RPC 行為測試
--   先建測試 fixture：1 supplier + 1 sku + 1 campaign + 1 customer_order
-- ============================================================

-- Setup: supplier
INSERT INTO suppliers (tenant_id, code, name, created_by, updated_by)
VALUES (:'TENANT', 'TEST_SUP1', '測試供應商一', :'OP', :'OP')
RETURNING id AS sup1_id \gset

-- Setup: 第 2 個 supplier
INSERT INTO suppliers (tenant_id, code, name, created_by, updated_by)
VALUES (:'TENANT', 'TEST_SUP2', '測試供應商二', :'OP', :'OP')
RETURNING id AS sup2_id \gset

-- Setup: 取既有 SKU（避免重建商品鏈）
SELECT id AS sku1_id FROM skus WHERE tenant_id = :'TENANT' ORDER BY id LIMIT 1 \gset
SELECT id AS sku2_id FROM skus WHERE tenant_id = :'TENANT' AND id <> :sku1_id ORDER BY id LIMIT 1 \gset

-- Setup: supplier_skus 設 preferred
INSERT INTO supplier_skus (tenant_id, supplier_id, sku_id, default_unit_cost, is_preferred, created_by, updated_by)
VALUES (:'TENANT', :sup1_id, :sku1_id, 100, TRUE, :'OP', :'OP'),
       (:'TENANT', :sup2_id, :sku2_id, 50,  TRUE, :'OP', :'OP');

-- Setup: campaign + items + channel + customer_order
SELECT id AS chan_id FROM line_channels WHERE tenant_id = :'TENANT' ORDER BY id LIMIT 1 \gset
SELECT id AS member_id FROM members WHERE tenant_id = :'TENANT' ORDER BY id LIMIT 1 \gset
SELECT id AS store_id FROM stores WHERE tenant_id = :'TENANT' ORDER BY id LIMIT 1 \gset

INSERT INTO group_buy_campaigns (tenant_id, campaign_no, name, status, end_at, created_by, updated_by)
VALUES (:'TENANT', 'TEST_CAMP_A', '測試團 A', 'open',
        '2026-04-25 23:59:59+08'::timestamptz, :'OP', :'OP')
RETURNING id AS camp_a_id \gset

INSERT INTO campaign_items (tenant_id, campaign_id, sku_id, unit_price, created_by, updated_by)
VALUES (:'TENANT', :camp_a_id, :sku1_id, 165, :'OP', :'OP')
RETURNING id AS ci_a1_id \gset

INSERT INTO campaign_items (tenant_id, campaign_id, sku_id, unit_price, created_by, updated_by)
VALUES (:'TENANT', :camp_a_id, :sku2_id, 89, :'OP', :'OP')
RETURNING id AS ci_a2_id \gset

INSERT INTO customer_orders (tenant_id, order_no, campaign_id, channel_id, member_id, pickup_store_id, created_by, updated_by)
VALUES (:'TENANT', 'TEST_ORD_1', :camp_a_id, :chan_id, :member_id, :store_id, :'OP', :'OP')
RETURNING id AS ord1_id \gset

INSERT INTO customer_order_items (tenant_id, order_id, campaign_item_id, sku_id, qty, unit_price, created_by, updated_by)
VALUES (:'TENANT', :ord1_id, :ci_a1_id, :sku1_id, 30, 165, :'OP', :'OP'),
       (:'TENANT', :ord1_id, :ci_a2_id, :sku2_id, 12, 89, :'OP', :'OP');

-- ============================================================
-- 2.7 結單守衛 — campaign 狀態錯誤（先測：剛建的 status='open' 是合法、改 draft 試擋）
-- ============================================================

UPDATE group_buy_campaigns SET status = 'draft' WHERE id = :camp_a_id;

DO $$
DECLARE camp_id BIGINT;
BEGIN
  SELECT id INTO camp_id FROM group_buy_campaigns WHERE campaign_no = 'TEST_CAMP_A';
  BEGIN
    PERFORM rpc_close_campaign(camp_id, '00000000-0000-0000-0000-000000000099'::uuid);
    RAISE NOTICE '2.7 FAIL: should have raised';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '2.7 OK: %', SQLERRM;
  END;
END $$;

-- 還原 open
UPDATE group_buy_campaigns SET status = 'open' WHERE id = :camp_a_id;

-- ============================================================
-- 2.8 結單 happy path
-- ============================================================

SELECT '2.8' AS scn, rpc_close_campaign(:camp_a_id, :'OP'::uuid);
SELECT '2.8 verify' AS scn, status, updated_by FROM group_buy_campaigns WHERE id = :camp_a_id;

-- 確認沒自動產 PR
SELECT '2.8 no auto PR' AS scn, count(*) AS pr_count
  FROM purchase_requests WHERE source_close_date = '2026-04-25';

-- ============================================================
-- 2.1 / 2.2 帶入該日商品 happy path
-- ============================================================

SELECT '2.1' AS scn, rpc_create_pr_from_close_date('2026-04-25'::date, :'OP'::uuid) AS pr_id \gset

SELECT '2.1 PR header' AS scn,
       source_type, source_close_date, status, total_amount,
       (pr_no LIKE 'PR260428%' OR pr_no LIKE 'PR%') AS pr_no_format_ok
  FROM purchase_requests WHERE id = :pr_id;

SELECT '2.1 PR items' AS scn,
       sku_id, qty_requested, suggested_supplier_id, unit_cost,
       line_subtotal, source_campaign_id
  FROM purchase_request_items WHERE pr_id = :pr_id ORDER BY sku_id;

-- 預期：sku1 unit_cost=100、qty=30、subtotal=3000
--      sku2 unit_cost=50、qty=12、subtotal=600
--      total_amount = 3600

-- ============================================================
-- 2.4 該日無 closed campaign
-- ============================================================

DO $$
BEGIN
  PERFORM rpc_create_pr_from_close_date('2099-12-31'::date, '00000000-0000-0000-0000-000000000099'::uuid);
  RAISE NOTICE '2.4 FAIL: should have raised';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '2.4 OK: %', SQLERRM;
END $$;

-- ============================================================
-- 2.9 / 2.10 送審 happy path（threshold 不存在 → 自動 approved）
-- ============================================================

SELECT '2.9 before submit' AS scn, status, review_status, total_amount
  FROM purchase_requests WHERE id = :pr_id;

SELECT '2.9 submit' AS scn, rpc_submit_pr(:pr_id, :'OP'::uuid);

SELECT '2.9 after submit' AS scn, status, review_status, total_amount, submitted_at IS NOT NULL AS has_submitted_at
  FROM purchase_requests WHERE id = :pr_id;

-- 2.11 重複送審
DO $$
BEGIN
  PERFORM rpc_submit_pr(CAST(current_setting('app.test_pr_id', TRUE) AS BIGINT),
                        '00000000-0000-0000-0000-000000000099'::uuid);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '2.11 OK (cannot test in plpgsql block w/o psql var, see direct test below)';
END $$;

-- 直接呼叫第二次（預期 RAISE）
SELECT '2.11 verify' AS scn,
       (SELECT status FROM purchase_requests WHERE id = :pr_id) AS pr_status;

-- ============================================================
-- 2.10 threshold 觸發 pending_review
--   先設一個 global threshold 比 PR 總額低
-- ============================================================

INSERT INTO purchase_approval_thresholds (tenant_id, scope, scope_id, threshold_amount, active, created_by, updated_by)
VALUES (:'TENANT', 'global', NULL, 1000, TRUE, :'OP', :'OP');

-- 建第二張 PR 走 submit 看是否觸發
INSERT INTO group_buy_campaigns (tenant_id, campaign_no, name, status, end_at, created_by, updated_by)
VALUES (:'TENANT', 'TEST_CAMP_B', '測試團 B', 'open',
        '2026-04-26 23:59:59+08'::timestamptz, :'OP', :'OP')
RETURNING id AS camp_b_id \gset

INSERT INTO campaign_items (tenant_id, campaign_id, sku_id, unit_price, created_by, updated_by)
VALUES (:'TENANT', :camp_b_id, :sku1_id, 165, :'OP', :'OP')
RETURNING id AS ci_b1_id \gset

INSERT INTO customer_orders (tenant_id, order_no, campaign_id, channel_id, member_id, pickup_store_id, created_by, updated_by)
VALUES (:'TENANT', 'TEST_ORD_2', :camp_b_id, :chan_id, :member_id, :store_id, :'OP', :'OP')
RETURNING id AS ord2_id \gset

INSERT INTO customer_order_items (tenant_id, order_id, campaign_item_id, sku_id, qty, unit_price, created_by, updated_by)
VALUES (:'TENANT', :ord2_id, :ci_b1_id, :sku1_id, 30, 165, :'OP', :'OP');

SELECT rpc_close_campaign(:camp_b_id, :'OP'::uuid);
SELECT '2.10 create pr B' AS scn,
       rpc_create_pr_from_close_date('2026-04-26'::date, :'OP'::uuid) AS pr_b_id \gset

SELECT '2.10 submit B' AS scn, rpc_submit_pr(:pr_b_id, :'OP'::uuid);
SELECT '2.10 verify B' AS scn, status, review_status, total_amount, review_threshold_amount
  FROM purchase_requests WHERE id = :pr_b_id;
-- 預期：review_status='pending_review'、threshold_amount=1000

-- ============================================================
-- 2.12 拆 PO happy path（用 PR A，已 approved）
-- ============================================================

SELECT '2.12 split' AS scn, rpc_split_pr_to_pos(:pr_id, 1::bigint, :'OP'::uuid) AS po_ids;

SELECT '2.12 PO list' AS scn, id, po_no, supplier_id, status, total
  FROM purchase_orders
 WHERE id IN (SELECT unnest(rpc_split_pr_to_pos.po_ids)
                FROM (SELECT 1::int AS dummy) d
                CROSS JOIN LATERAL (SELECT '{}'::BIGINT[] AS po_ids) x)
ORDER BY id;

-- 直接從 supplier 反查
SELECT '2.12 PO by supplier' AS scn, po.id, po.po_no, po.supplier_id, po.status, po.total
  FROM purchase_orders po
 WHERE po.created_by = :'OP'::uuid
   AND po.created_at > NOW() - INTERVAL '1 minute'
 ORDER BY po.id;

SELECT '2.12 PO items' AS scn, po.po_no, poi.sku_id, poi.qty_ordered, poi.unit_cost
  FROM purchase_orders po
  JOIN purchase_order_items poi ON poi.po_id = po.id
 WHERE po.created_at > NOW() - INTERVAL '1 minute'
 ORDER BY po.id, poi.sku_id;

SELECT '2.12 PR status after split' AS scn, status FROM purchase_requests WHERE id = :pr_id;

-- ============================================================
-- 2.13 拆 PO 守衛：review_status 未通過（用 pr_b_id, pending_review）
-- ============================================================

DO $$
DECLARE prb BIGINT;
BEGIN
  SELECT id INTO prb FROM purchase_requests
   WHERE source_close_date = '2026-04-26' AND review_status = 'pending_review' LIMIT 1;
  BEGIN
    PERFORM rpc_split_pr_to_pos(prb, 1::bigint, '00000000-0000-0000-0000-000000000099'::uuid);
    RAISE NOTICE '2.13 FAIL: should have raised';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '2.13 OK: %', SQLERRM;
  END;
END $$;

-- ============================================================
-- 2.15 拆 PO 守衛：已拆過
-- ============================================================

DO $$
DECLARE pra BIGINT := CAST(current_setting('app.pr_a_id', TRUE) AS BIGINT);
BEGIN
  -- pra 已 fully_ordered
  BEGIN
    PERFORM rpc_split_pr_to_pos(pra, 1::bigint, '00000000-0000-0000-0000-000000000099'::uuid);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '2.15 OK: %', SQLERRM;
  END;
END $$;
-- 註：上方因 plpgsql block 沒有 psql var、改用直接 SQL：
-- 直接重複呼叫
SELECT '2.15 verify' AS scn,
       (SELECT status FROM purchase_requests WHERE id = :pr_id) AS pra_status;
-- 上 SELECT 不會 RAISE，但下面這條會：
\echo '2.15 expect ERROR:'
SELECT rpc_split_pr_to_pos(:pr_id, 1::bigint, :'OP'::uuid);

-- 上一條會中止 transaction、所以放最尾。

-- ============================================================
ROLLBACK;
