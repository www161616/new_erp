-- 改進撿貨需求 view：加入進庫量對比
-- 顯示：訂單需求 vs 實際進庫量
DROP VIEW IF EXISTS public.v_picking_demand_by_close_date CASCADE;

CREATE OR REPLACE VIEW public.v_picking_demand_by_close_date AS
SELECT
  gbc.tenant_id,
  DATE(gbc.end_at AT TIME ZONE 'Asia/Taipei') AS close_date,
  coi.sku_id,
  COALESCE(s.product_name, '') || COALESCE(' ' || NULLIF(s.variant_name,''), '') AS sku_label,
  s.sku_code,
  co.pickup_store_id AS store_id,
  st.code AS store_code,
  st.name AS store_name,
  SUM(coi.qty) AS demand_qty,
  COUNT(DISTINCT co.id) AS order_count,
  array_agg(DISTINCT gbc.id) AS campaign_ids,
  -- 加入進庫量：同 SKU、confirmed 狀態的進貨總量
  COALESCE(SUM(gri.qty_received) FILTER (WHERE gr.status = 'confirmed'), 0)::NUMERIC AS received_qty,
  -- 加入 PO 號和訂單號追蹤
  array_agg(DISTINCT po.po_no) FILTER (WHERE po.po_no IS NOT NULL) AS po_numbers,
  array_agg(DISTINCT co.order_no) FILTER (WHERE co.order_no IS NOT NULL) AS order_numbers
FROM group_buy_campaigns gbc
JOIN customer_orders co ON co.campaign_id = gbc.id AND co.status NOT IN ('cancelled','expired')
JOIN customer_order_items coi ON coi.order_id = co.id AND coi.status NOT IN ('cancelled','expired')
JOIN skus s ON s.id = coi.sku_id
JOIN stores st ON st.id = co.pickup_store_id
-- LEFT JOIN 進貨：同 tenant、同 SKU、已確認的進貨
LEFT JOIN goods_receipt_items gri ON gri.sku_id = coi.sku_id
LEFT JOIN goods_receipts gr ON gr.id = gri.gr_id AND gr.tenant_id = gbc.tenant_id AND gr.status = 'confirmed'
-- LEFT JOIN 採購單：從 goods_receipts 連到 PO
LEFT JOIN purchase_orders po ON po.id = gr.po_id
WHERE gbc.status NOT IN ('cancelled')
GROUP BY
  gbc.tenant_id,
  DATE(gbc.end_at AT TIME ZONE 'Asia/Taipei'),
  coi.sku_id, s.product_name, s.variant_name, s.sku_code,
  co.pickup_store_id, st.code, st.name;

GRANT SELECT ON public.v_picking_demand_by_close_date TO authenticated;

COMMENT ON VIEW public.v_picking_demand_by_close_date IS
  '撿貨工作站需求矩陣（含進庫量）：close_date × sku × store
   - demand_qty: 訂單需求量
   - received_qty: 已進庫量（confirmed）';
