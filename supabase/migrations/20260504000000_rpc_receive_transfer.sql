-- rpc_receive_transfer：分店端確認收貨
--
-- 流程：
--   transfers.status='shipped' → 'received'
--   每行 transfer_items 寫入實收 qty + transfer_in stock_movement 至 dest_location
--   short receipt（qty_received < qty_shipped）只記錄 variance、不卡單；over receipt 擋住
--
-- 上游：generate_transfer_from_wave 產生的 hq_to_store TR
-- 下游：分店 inbox UI（後續 PR）

CREATE OR REPLACE FUNCTION rpc_receive_transfer(
  p_transfer_id BIGINT,
  p_lines       JSONB,        -- [{transfer_item_id, qty_received}, ...] 或 NULL = 全收
  p_operator    UUID,
  p_notes       TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_tenant_id        UUID;
  v_status           TEXT;
  v_dest_location    BIGINT;
  v_existing_notes   TEXT;
  v_item             RECORD;
  v_qty_received     NUMERIC;
  v_unit_cost        NUMERIC;
  v_in_mov_id        BIGINT;
  v_total_qty        NUMERIC := 0;
  v_total_variance   NUMERIC := 0;
  v_items_received   INTEGER := 0;
  v_lines_consumed   INTEGER := 0;
  v_lines_count      INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('transfer:' || p_transfer_id));

  SELECT tenant_id, status, dest_location, notes
    INTO v_tenant_id, v_status, v_dest_location, v_existing_notes
    FROM transfers
   WHERE id = p_transfer_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'transfer % not found', p_transfer_id;
  END IF;

  IF v_status <> 'shipped' THEN
    RAISE EXCEPTION 'transfer % is in status %, expected shipped', p_transfer_id, v_status;
  END IF;

  IF p_lines IS NOT NULL THEN
    v_lines_count := jsonb_array_length(p_lines);

    -- p_lines 內所有 transfer_item_id 必須屬於本 transfer
    IF EXISTS (
      SELECT 1
        FROM jsonb_array_elements(p_lines) AS l
        LEFT JOIN transfer_items ti
          ON ti.id = (l->>'transfer_item_id')::BIGINT
         AND ti.transfer_id = p_transfer_id
       WHERE ti.id IS NULL
    ) THEN
      RAISE EXCEPTION 'p_lines contains transfer_item_id not belonging to transfer %', p_transfer_id;
    END IF;
  END IF;

  FOR v_item IN
    SELECT ti.id, ti.sku_id, ti.qty_shipped, sm.unit_cost AS out_cost
      FROM transfer_items ti
      LEFT JOIN stock_movements sm ON sm.id = ti.out_movement_id
     WHERE ti.transfer_id = p_transfer_id
     ORDER BY ti.id
  LOOP
    -- 預設全收；若 p_lines 有指定該 item，採用指定值
    v_qty_received := v_item.qty_shipped;

    IF p_lines IS NOT NULL THEN
      SELECT (l->>'qty_received')::NUMERIC
        INTO v_qty_received
        FROM jsonb_array_elements(p_lines) AS l
       WHERE (l->>'transfer_item_id')::BIGINT = v_item.id
       LIMIT 1;

      IF FOUND THEN
        v_lines_consumed := v_lines_consumed + 1;
      ELSE
        v_qty_received := v_item.qty_shipped;  -- 漏列 = 視為全收
      END IF;
    END IF;

    IF v_qty_received IS NULL OR v_qty_received < 0 THEN
      RAISE EXCEPTION 'transfer_item % qty_received must be >= 0, got %', v_item.id, v_qty_received;
    END IF;
    IF v_qty_received > v_item.qty_shipped THEN
      RAISE EXCEPTION 'transfer_item % over-receipt: qty_received=% > qty_shipped=%',
        v_item.id, v_qty_received, v_item.qty_shipped;
    END IF;

    IF v_qty_received > 0 THEN
      v_unit_cost := COALESCE(ABS(v_item.out_cost), 0);

      v_in_mov_id := rpc_inbound(
        p_tenant_id       => v_tenant_id,
        p_location_id     => v_dest_location,
        p_sku_id          => v_item.sku_id,
        p_quantity        => v_qty_received,
        p_unit_cost       => v_unit_cost,
        p_movement_type   => 'transfer_in',
        p_source_doc_type => 'transfer',
        p_source_doc_id   => p_transfer_id,
        p_operator        => p_operator
      );

      UPDATE transfer_items
         SET qty_received   = v_qty_received,
             in_movement_id = v_in_mov_id,
             updated_by     = p_operator
       WHERE id = v_item.id;
    ELSE
      -- 0 收：仍標記 qty_received=0，no movement
      UPDATE transfer_items
         SET qty_received = 0,
             updated_by   = p_operator
       WHERE id = v_item.id;
    END IF;

    v_total_qty      := v_total_qty + v_qty_received;
    v_total_variance := v_total_variance + (v_qty_received - v_item.qty_shipped);
    v_items_received := v_items_received + 1;
  END LOOP;

  UPDATE transfers
     SET status      = 'received',
         received_by = p_operator,
         received_at = NOW(),
         notes       = CASE
                         WHEN p_notes IS NULL OR p_notes = '' THEN v_existing_notes
                         WHEN v_existing_notes IS NULL OR v_existing_notes = '' THEN p_notes
                         ELSE v_existing_notes || E'\n' || p_notes
                       END,
         updated_by  = p_operator
   WHERE id = p_transfer_id;

  RETURN jsonb_build_object(
    'transfer_id',        p_transfer_id,
    'items_received',     v_items_received,
    'total_qty_received', v_total_qty,
    'total_variance',     v_total_variance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION rpc_receive_transfer(BIGINT, JSONB, UUID, TEXT) TO authenticated;
