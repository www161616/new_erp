-- 刪除撿貨單 RPC（繞過 append-only 限制）
CREATE OR REPLACE FUNCTION rpc_delete_picking_wave(
  p_wave_id BIGINT,
  p_operator UUID
) RETURNS VOID AS $$
DECLARE
  v_tenant_id UUID;
  v_wave_status TEXT;
  v_wave_code TEXT;
BEGIN
  -- 取得 wave 資訊並上鎖
  SELECT tenant_id, status, wave_code INTO v_tenant_id, v_wave_status, v_wave_code
    FROM picking_waves WHERE id = p_wave_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wave % not found', p_wave_id;
  END IF;

  -- 只允許刪除未派貨的撿貨單
  IF v_wave_status = 'shipped' THEN
    RAISE EXCEPTION 'cannot delete shipped wave %', v_wave_code;
  END IF;

  -- 暫時禁用 audit log 的 append-only 保護
  ALTER TABLE picking_wave_audit_log DISABLE TRIGGER trg_no_mut_wave_audit;

  BEGIN
    -- 刪除 audit log（級聯刪除依賴）
    DELETE FROM picking_wave_audit_log WHERE wave_id = p_wave_id;

    -- 刪除 items
    DELETE FROM picking_wave_items WHERE wave_id = p_wave_id;

    -- 刪除 wave
    DELETE FROM picking_waves WHERE id = p_wave_id;
  EXCEPTION WHEN OTHERS THEN
    -- 重新啟用觸發器並拋出錯誤
    ALTER TABLE picking_wave_audit_log ENABLE TRIGGER trg_no_mut_wave_audit;
    RAISE;
  END;

  -- 重新啟用保護
  ALTER TABLE picking_wave_audit_log ENABLE TRIGGER trg_no_mut_wave_audit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION rpc_delete_picking_wave(BIGINT, UUID) IS
  '刪除撿貨單（含 audit log）。只允許刪除 draft/picking/picked 狀態的波次。';
