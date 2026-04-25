-- ============================================================
-- Campaign 結單 → 內部採購單（PR）→ 拆 PO 流程
-- PRD: docs/PRD-訂單取貨模組.md §7.5、docs/PRD-採購模組.md §7.2~§7.4
-- TEST: docs/TEST-campaign-to-purchase.md
-- Issue: #76
--
-- 設計（對齊 lt-erp UX）：
--   1. PR 是「跨供應商工作底稿」：一張 PR 多家供應商混排，per-line suggested_supplier_id
--   2. 「帶入該日商品」一鍵把該結單日所有 closed campaign 的商品彙總到一張 PR
--   3. 送審 → 通過 → 依 suggested_supplier_id 拆多張 PO
-- ============================================================

-- ============================================================
-- 1. SCHEMA: purchase_requests 擴充
-- ============================================================

ALTER TABLE purchase_requests
  ADD COLUMN source_type        TEXT NOT NULL DEFAULT 'manual'
                                  CHECK (source_type IN ('manual','close_date')),
  ADD COLUMN source_close_date  DATE,
  ADD COLUMN total_amount       NUMERIC(18,4) NOT NULL DEFAULT 0;

ALTER TABLE purchase_requests
  ADD CONSTRAINT chk_pr_source_close_date CHECK (
    (source_type = 'close_date' AND source_close_date IS NOT NULL) OR
    (source_type = 'manual')
  );

CREATE INDEX idx_pr_close_date ON purchase_requests
  (tenant_id, source_close_date) WHERE source_type = 'close_date';

-- ============================================================
-- 2. SCHEMA: purchase_request_items 擴充
-- ============================================================

ALTER TABLE purchase_request_items
  ADD COLUMN unit_cost          NUMERIC(18,4) NOT NULL DEFAULT 0,
  ADD COLUMN line_subtotal      NUMERIC(18,2)
    GENERATED ALWAYS AS (qty_requested * unit_cost) STORED,
  ADD COLUMN source_campaign_id BIGINT REFERENCES group_buy_campaigns(id);

CREATE INDEX idx_pri_supplier ON purchase_request_items (suggested_supplier_id);

-- ============================================================
-- 3. SCHEMA: suppliers 擴充（v0.2 PRD §Q4）
-- ============================================================

ALTER TABLE suppliers
  ADD COLUMN preferred_po_channel TEXT NOT NULL DEFAULT 'line'
                                    CHECK (preferred_po_channel IN ('line','email','phone','fax','manual')),
  ADD COLUMN line_contact         TEXT;

-- ============================================================
-- 4. SEQUENCES: pr_no / po_no
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS pr_no_seq;
CREATE SEQUENCE IF NOT EXISTS po_no_seq;

CREATE OR REPLACE FUNCTION public.rpc_next_pr_no()
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN 'PR' || to_char(NOW(), 'YYMMDD') || lpad(nextval('pr_no_seq')::text, 4, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_next_po_no()
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN 'PO' || to_char(NOW(), 'YYMMDD') || lpad(nextval('po_no_seq')::text, 4, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_next_pr_no TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_next_po_no TO authenticated;

-- ============================================================
-- 5. RPC: rpc_close_campaign
--    純切 status open → closed，不自動產 PR
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_close_campaign(
  p_campaign_id BIGINT,
  p_operator    UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
    FROM group_buy_campaigns
   WHERE id = p_campaign_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'campaign % not found', p_campaign_id;
  END IF;

  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'campaign % not in open status (current: %)', p_campaign_id, v_status;
  END IF;

  UPDATE group_buy_campaigns
     SET status = 'closed',
         updated_by = p_operator,
         updated_at = NOW()
   WHERE id = p_campaign_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_close_campaign TO authenticated;

COMMENT ON FUNCTION public.rpc_close_campaign IS
  '結單：campaign open → closed（不自動產 PR，由 rpc_create_pr_from_close_date 另行觸發）';

-- ============================================================
-- 6. RPC: rpc_create_pr_from_close_date
--    「帶入該日商品」核心：彙總該結單日所有 closed campaign 的商品成單張 PR
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_create_pr_from_close_date(
  p_close_date DATE,
  p_operator   UUID
) RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_tenant      UUID := public._current_tenant_id();
  v_pr_id       BIGINT;
  v_pr_no       TEXT;
  v_dest_loc    BIGINT;
  v_campaign_count INTEGER;
  v_demand_count   INTEGER;
BEGIN
  -- 1. 守衛：該日是否有 closed campaign
  SELECT COUNT(*) INTO v_campaign_count
    FROM group_buy_campaigns
   WHERE tenant_id = v_tenant
     AND status = 'closed'
     AND DATE(end_at AT TIME ZONE 'Asia/Taipei') = p_close_date;

  IF v_campaign_count = 0 THEN
    RAISE EXCEPTION 'no closed campaigns on date %', p_close_date;
  END IF;

  -- 2. 守衛：是否有可彙總的訂單
  SELECT COUNT(*) INTO v_demand_count
    FROM group_buy_campaigns gbc
    JOIN customer_orders co ON co.campaign_id = gbc.id
    JOIN customer_order_items coi ON coi.order_id = co.id
   WHERE gbc.tenant_id = v_tenant
     AND gbc.status = 'closed'
     AND DATE(gbc.end_at AT TIME ZONE 'Asia/Taipei') = p_close_date
     AND co.status NOT IN ('cancelled','expired')
     AND coi.status NOT IN ('cancelled','expired');

  IF v_demand_count = 0 THEN
    RAISE EXCEPTION 'no orders to aggregate for close_date %', p_close_date;
  END IF;

  -- 3. 取一個 location 當 dest（預設第一個）
  SELECT id INTO v_dest_loc FROM locations
   WHERE tenant_id = v_tenant
   ORDER BY id LIMIT 1;

  IF v_dest_loc IS NULL THEN
    RAISE EXCEPTION 'no locations defined for tenant %', v_tenant;
  END IF;

  -- 4. 建 PR header
  v_pr_no := public.rpc_next_pr_no();

  INSERT INTO purchase_requests (
    tenant_id, pr_no, source_type, source_close_date,
    source_location_id, status, total_amount,
    created_by, updated_by
  ) VALUES (
    v_tenant, v_pr_no, 'close_date', p_close_date,
    v_dest_loc, 'draft', 0,
    p_operator, p_operator
  ) RETURNING id INTO v_pr_id;

  -- 5. 彙總 items（per SKU 跨 campaign 累加 qty）
  INSERT INTO purchase_request_items (
    pr_id, sku_id, qty_requested,
    suggested_supplier_id, unit_cost, source_campaign_id,
    created_by, updated_by
  )
  SELECT
    v_pr_id,
    agg.sku_id,
    agg.qty_total,
    ss.supplier_id,
    COALESCE(ss.default_unit_cost, 0),
    agg.first_campaign_id,
    p_operator,
    p_operator
  FROM (
    SELECT
      coi.sku_id,
      SUM(coi.qty) AS qty_total,
      MIN(gbc.id)  AS first_campaign_id
      FROM group_buy_campaigns gbc
      JOIN customer_orders co ON co.campaign_id = gbc.id
      JOIN customer_order_items coi ON coi.order_id = co.id
     WHERE gbc.tenant_id = v_tenant
       AND gbc.status = 'closed'
       AND DATE(gbc.end_at AT TIME ZONE 'Asia/Taipei') = p_close_date
       AND co.status NOT IN ('cancelled','expired')
       AND coi.status NOT IN ('cancelled','expired')
     GROUP BY coi.sku_id
  ) agg
  LEFT JOIN LATERAL (
    SELECT supplier_id, default_unit_cost
      FROM supplier_skus
     WHERE tenant_id = v_tenant
       AND sku_id = agg.sku_id
       AND is_preferred = TRUE
     LIMIT 1
  ) ss ON TRUE;

  -- 6. 更新 PR.total_amount 快照
  UPDATE purchase_requests pr
     SET total_amount = COALESCE((
           SELECT SUM(line_subtotal) FROM purchase_request_items WHERE pr_id = v_pr_id
         ), 0),
         updated_at = NOW()
   WHERE pr.id = v_pr_id;

  RETURN v_pr_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_create_pr_from_close_date TO authenticated;

COMMENT ON FUNCTION public.rpc_create_pr_from_close_date IS
  '「帶入該日商品」：把該結單日所有 closed campaign 的商品需求彙總到一張 PR';

-- ============================================================
-- 7. RPC: rpc_submit_pr
--    送出審核：算 total_amount + 套 threshold + 設 review_status
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_submit_pr(
  p_pr_id    BIGINT,
  p_operator UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_tenant       UUID;
  v_status       TEXT;
  v_review       TEXT;
  v_total        NUMERIC(18,4);
  v_threshold    NUMERIC(18,4);
  v_new_review   TEXT;
BEGIN
  SELECT tenant_id, status, review_status INTO v_tenant, v_status, v_review
    FROM purchase_requests
   WHERE id = p_pr_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PR % not found', p_pr_id;
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'PR % already submitted (status: %)', p_pr_id, v_status;
  END IF;

  -- 重算 total（考慮使用者已編輯 unit_cost / qty）
  SELECT COALESCE(SUM(line_subtotal), 0) INTO v_total
    FROM purchase_request_items WHERE pr_id = p_pr_id;

  -- 套 global threshold（簡化：先支援 global scope）
  SELECT MIN(threshold_amount) INTO v_threshold
    FROM purchase_approval_thresholds
   WHERE tenant_id = v_tenant
     AND active = TRUE
     AND scope = 'global'
     AND scope_id IS NULL;

  IF v_threshold IS NOT NULL AND v_total >= v_threshold THEN
    v_new_review := 'pending_review';
  ELSE
    v_new_review := 'approved';
  END IF;

  UPDATE purchase_requests
     SET status = 'submitted',
         submitted_at = NOW(),
         total_amount = v_total,
         review_status = v_new_review,
         review_threshold_amount = v_threshold,
         updated_by = p_operator,
         updated_at = NOW()
   WHERE id = p_pr_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_submit_pr TO authenticated;

COMMENT ON FUNCTION public.rpc_submit_pr IS
  'PR 送審：重算 total → 比 threshold → 設 review_status (approved / pending_review)';

-- ============================================================
-- 8. RPC: rpc_split_pr_to_pos
--    依 suggested_supplier_id 拆多張 PO
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_split_pr_to_pos(
  p_pr_id            BIGINT,
  p_dest_location_id BIGINT,
  p_operator         UUID
) RETURNS BIGINT[]
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_tenant   UUID;
  v_status   TEXT;
  v_review   TEXT;
  v_unassigned INTEGER;
  v_supplier_rec RECORD;
  v_po_id    BIGINT;
  v_po_no    TEXT;
  v_po_ids   BIGINT[] := ARRAY[]::BIGINT[];
BEGIN
  SELECT tenant_id, status, review_status INTO v_tenant, v_status, v_review
    FROM purchase_requests
   WHERE id = p_pr_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PR % not found', p_pr_id;
  END IF;

  IF v_review <> 'approved' THEN
    RAISE EXCEPTION 'PR % not approved (current: %)', p_pr_id, v_review;
  END IF;

  IF v_status IN ('fully_ordered','partially_ordered','cancelled') THEN
    RAISE EXCEPTION 'PR % already split (status: %)', p_pr_id, v_status;
  END IF;

  -- 守衛：含未指派供應商行
  SELECT COUNT(*) INTO v_unassigned
    FROM purchase_request_items
   WHERE pr_id = p_pr_id AND suggested_supplier_id IS NULL;

  IF v_unassigned > 0 THEN
    RAISE EXCEPTION 'PR % has % unassigned supplier items', p_pr_id, v_unassigned;
  END IF;

  -- 依 supplier 拆 PO
  FOR v_supplier_rec IN
    SELECT DISTINCT suggested_supplier_id AS supplier_id
      FROM purchase_request_items
     WHERE pr_id = p_pr_id
  LOOP
    v_po_no := public.rpc_next_po_no();

    INSERT INTO purchase_orders (
      tenant_id, po_no, supplier_id, dest_location_id, status,
      created_by, updated_by
    ) VALUES (
      v_tenant, v_po_no, v_supplier_rec.supplier_id, p_dest_location_id, 'draft',
      p_operator, p_operator
    ) RETURNING id INTO v_po_id;

    -- PO items 從 PR items copy
    WITH inserted AS (
      INSERT INTO purchase_order_items (
        po_id, sku_id, qty_ordered, unit_cost,
        created_by, updated_by
      )
      SELECT v_po_id, pri.sku_id, pri.qty_requested, pri.unit_cost,
             p_operator, p_operator
        FROM purchase_request_items pri
       WHERE pri.pr_id = p_pr_id
         AND pri.suggested_supplier_id = v_supplier_rec.supplier_id
      RETURNING id, sku_id
    )
    UPDATE purchase_request_items pri
       SET po_item_id = i.id,
           updated_by = p_operator
      FROM inserted i
     WHERE pri.pr_id = p_pr_id
       AND pri.suggested_supplier_id = v_supplier_rec.supplier_id
       AND pri.sku_id = i.sku_id;

    -- 更新 PO totals
    UPDATE purchase_orders po
       SET subtotal = sub.subtotal,
           total = sub.subtotal,
           updated_at = NOW()
      FROM (
        SELECT po_id, SUM(qty_ordered * unit_cost) AS subtotal
          FROM purchase_order_items WHERE po_id = v_po_id GROUP BY po_id
      ) sub
     WHERE po.id = sub.po_id;

    v_po_ids := v_po_ids || v_po_id;
  END LOOP;

  -- 標 PR 為 fully_ordered
  UPDATE purchase_requests
     SET status = 'fully_ordered',
         updated_by = p_operator,
         updated_at = NOW()
   WHERE id = p_pr_id;

  RETURN v_po_ids;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_split_pr_to_pos TO authenticated;

COMMENT ON FUNCTION public.rpc_split_pr_to_pos IS
  '依 suggested_supplier_id 把 PR 拆成多張 PO（每 supplier 一張）';

-- ============================================================
-- 9. RPC: rpc_send_purchase_order
--    PO draft → sent，守衛 source PR 不可有 pending_review / rejected
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_send_purchase_order(
  p_po_id    BIGINT,
  p_channel  TEXT,
  p_operator UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_status         TEXT;
  v_pending_count  INTEGER;
  v_rejected_count INTEGER;
BEGIN
  IF p_channel NOT IN ('line','email','phone','fax','manual') THEN
    RAISE EXCEPTION 'invalid channel: %', p_channel;
  END IF;

  SELECT status INTO v_status FROM purchase_orders WHERE id = p_po_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PO % not found', p_po_id;
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'PO % already sent (status: %)', p_po_id, v_status;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE pr.review_status = 'pending_review'),
    COUNT(*) FILTER (WHERE pr.review_status = 'rejected')
    INTO v_pending_count, v_rejected_count
    FROM purchase_request_items pri
    JOIN purchase_requests pr ON pr.id = pri.pr_id
    JOIN purchase_order_items poi ON poi.id = pri.po_item_id
   WHERE poi.po_id = p_po_id;

  IF v_pending_count > 0 THEN
    RAISE EXCEPTION 'PO has % PR pending review', v_pending_count;
  END IF;

  IF v_rejected_count > 0 THEN
    RAISE EXCEPTION 'PO has % rejected PR', v_rejected_count;
  END IF;

  UPDATE purchase_orders
     SET status = 'sent',
         sent_at = NOW(),
         sent_by = p_operator,
         sent_channel = p_channel,
         updated_by = p_operator,
         updated_at = NOW()
   WHERE id = p_po_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_send_purchase_order TO authenticated;

COMMENT ON FUNCTION public.rpc_send_purchase_order IS
  'PO 發送：draft → sent，守衛來源 PR 必須 review_status=approved';
