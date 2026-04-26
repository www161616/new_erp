-- 測試 rpc_receive_transfer。整段在一個 transaction 裡、最後 ROLLBACK。
-- 為了單一 prepared statement，全部包在一個 DO 區塊裡，最後 RAISE 'ROLLBACK_OK' 強迫整段回滾。
DO $outer$
DECLARE
  v_tenant      UUID := '11111111-1111-1111-1111-111111111111';
  v_op          UUID := '22222222-2222-2222-2222-222222222222';
  v_src_loc     BIGINT;
  v_dst_loc     BIGINT;
  v_sku_a       BIGINT;
  v_sku_b       BIGINT;
  v_xfer_id     BIGINT;
  v_item_a_id   BIGINT;
  v_item_b_id   BIGINT;
  v_out_a       BIGINT;
  v_out_b       BIGINT;
  v_result      JSONB;
  v_status      TEXT;
  v_qty_a       NUMERIC;
  v_qty_b       NUMERIC;
  v_var_a       NUMERIC;
  v_in_mov_a    BIGINT;
  v_in_mov_b    BIGINT;
  v_in_qty      NUMERIC;
  v_in_cost     NUMERIC;
BEGIN
  -- C1: not found
  BEGIN
    PERFORM rpc_receive_transfer(-99999, NULL, v_op, NULL);
    RAISE EXCEPTION 'C1 FAILED: should have raised';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%not found%' THEN
      RAISE NOTICE 'C1 PASS: %', SQLERRM;
    ELSE RAISE; END IF;
  END;

  SELECT id INTO v_src_loc FROM locations ORDER BY id LIMIT 1;
  SELECT id INTO v_dst_loc FROM locations WHERE id <> v_src_loc ORDER BY id LIMIT 1;
  IF v_src_loc IS NULL OR v_dst_loc IS NULL THEN
    RAISE EXCEPTION 'need at least 2 locations';
  END IF;

  SELECT id INTO v_sku_a FROM skus ORDER BY id LIMIT 1;
  SELECT id INTO v_sku_b FROM skus WHERE id <> v_sku_a ORDER BY id LIMIT 1;
  IF v_sku_a IS NULL OR v_sku_b IS NULL THEN
    RAISE EXCEPTION 'need at least 2 skus';
  END IF;

  INSERT INTO transfers (tenant_id, transfer_no, source_location, dest_location,
                         status, transfer_type, requested_by, shipped_by, shipped_at,
                         created_by, updated_by)
  VALUES (v_tenant, 'TEST-RECV-' || EXTRACT(EPOCH FROM NOW())::TEXT,
          v_src_loc, v_dst_loc, 'shipped', 'hq_to_store',
          v_op, v_op, NOW(), v_op, v_op)
  RETURNING id INTO v_xfer_id;

  INSERT INTO stock_movements (tenant_id, location_id, sku_id, quantity, unit_cost,
                                movement_type, source_doc_type, source_doc_id, operator_id)
  VALUES (v_tenant, v_src_loc, v_sku_a, -10, 25.5, 'transfer_out', 'transfer', v_xfer_id, v_op)
  RETURNING id INTO v_out_a;
  INSERT INTO stock_movements (tenant_id, location_id, sku_id, quantity, unit_cost,
                                movement_type, source_doc_type, source_doc_id, operator_id)
  VALUES (v_tenant, v_src_loc, v_sku_b, -5, 100, 'transfer_out', 'transfer', v_xfer_id, v_op)
  RETURNING id INTO v_out_b;

  INSERT INTO transfer_items (transfer_id, sku_id, qty_requested, qty_shipped,
                              out_movement_id, created_by, updated_by)
  VALUES (v_xfer_id, v_sku_a, 10, 10, v_out_a, v_op, v_op)
  RETURNING id INTO v_item_a_id;
  INSERT INTO transfer_items (transfer_id, sku_id, qty_requested, qty_shipped,
                              out_movement_id, created_by, updated_by)
  VALUES (v_xfer_id, v_sku_b, 5, 5, v_out_b, v_op, v_op)
  RETURNING id INTO v_item_b_id;

  RAISE NOTICE 'fixture: transfer_id=% items=%,%', v_xfer_id, v_item_a_id, v_item_b_id;

  -- C4: over-receipt
  BEGIN
    PERFORM rpc_receive_transfer(v_xfer_id,
      jsonb_build_array(jsonb_build_object('transfer_item_id', v_item_a_id, 'qty_received', 999)),
      v_op, NULL);
    RAISE EXCEPTION 'C4 FAILED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%over-receipt%' THEN RAISE NOTICE 'C4 PASS: %', SQLERRM;
    ELSE RAISE; END IF;
  END;

  -- C3: negative
  BEGIN
    PERFORM rpc_receive_transfer(v_xfer_id,
      jsonb_build_array(jsonb_build_object('transfer_item_id', v_item_a_id, 'qty_received', -1)),
      v_op, NULL);
    RAISE EXCEPTION 'C3 FAILED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%>= 0%' THEN RAISE NOTICE 'C3 PASS: %', SQLERRM;
    ELSE RAISE; END IF;
  END;

  -- C5: foreign item id
  BEGIN
    PERFORM rpc_receive_transfer(v_xfer_id,
      jsonb_build_array(jsonb_build_object('transfer_item_id', -77777, 'qty_received', 1)),
      v_op, NULL);
    RAISE EXCEPTION 'C5 FAILED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%not belonging%' THEN RAISE NOTICE 'C5 PASS: %', SQLERRM;
    ELSE RAISE; END IF;
  END;

  -- B: A 短收 8/10，B 漏列 → 預設全收 5
  v_result := rpc_receive_transfer(v_xfer_id,
    jsonb_build_array(jsonb_build_object('transfer_item_id', v_item_a_id, 'qty_received', 8)),
    v_op, 'broken 2 in transit');

  RAISE NOTICE 'B result: %', v_result;
  IF (v_result->>'items_received')::INT <> 2 OR
     (v_result->>'total_qty_received')::NUMERIC <> 13 OR
     (v_result->>'total_variance')::NUMERIC <> -2 THEN
    RAISE EXCEPTION 'B FAILED: %', v_result;
  END IF;
  RAISE NOTICE 'B PASS';

  SELECT status INTO v_status FROM transfers WHERE id = v_xfer_id;
  IF v_status <> 'received' THEN RAISE EXCEPTION 'A5 FAILED: %', v_status; END IF;
  RAISE NOTICE 'A5 PASS: status=received';

  SELECT qty_received, qty_variance, in_movement_id
    INTO v_qty_a, v_var_a, v_in_mov_a
    FROM transfer_items WHERE id = v_item_a_id;
  IF v_qty_a <> 8 OR v_var_a <> -2 OR v_in_mov_a IS NULL THEN
    RAISE EXCEPTION 'B1/B2 FAILED: qty=% var=% mov=%', v_qty_a, v_var_a, v_in_mov_a;
  END IF;
  RAISE NOTICE 'B1/B2 PASS: A qty=8 var=-2';

  SELECT qty_received, in_movement_id INTO v_qty_b, v_in_mov_b
    FROM transfer_items WHERE id = v_item_b_id;
  IF v_qty_b <> 5 OR v_in_mov_b IS NULL THEN
    RAISE EXCEPTION 'C6 FAILED: qty_b=%', v_qty_b;
  END IF;
  RAISE NOTICE 'C6 PASS: missing line defaults full';

  SELECT quantity, unit_cost INTO v_in_qty, v_in_cost
    FROM stock_movements WHERE id = v_in_mov_a;
  IF v_in_qty <> 8 OR v_in_cost <> 25.5 THEN
    RAISE EXCEPTION 'A2/A3 FAILED: qty=% cost=%', v_in_qty, v_in_cost;
  END IF;
  RAISE NOTICE 'A2/A3 PASS: in_mov qty=+8 cost=25.5';

  -- C2: re-receive
  BEGIN
    PERFORM rpc_receive_transfer(v_xfer_id, NULL, v_op, NULL);
    RAISE EXCEPTION 'C2 FAILED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%expected shipped%' THEN RAISE NOTICE 'C2 PASS: %', SQLERRM;
    ELSE RAISE; END IF;
  END;

  RAISE NOTICE 'ALL TESTS PASSED — rolling back';
  RAISE EXCEPTION 'ROLLBACK_OK';
END
$outer$;
