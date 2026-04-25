-- ============================================================
-- 規格刪除：實質為軟刪除（status='discontinued'），避免 FK 衝突
-- 若有 inventory / orders 參照仍可保留歷史紀錄
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_delete_sku(
  p_id BIGINT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_tenant UUID := public._current_tenant_id();
  v_found  BIGINT;
BEGIN
  UPDATE skus
     SET status     = 'discontinued',
         updated_by = auth.uid()
   WHERE id = p_id AND tenant_id = v_tenant
   RETURNING id INTO v_found;
  IF v_found IS NULL THEN
    RAISE EXCEPTION 'sku % not in tenant', p_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_delete_sku TO authenticated;

COMMENT ON FUNCTION public.rpc_delete_sku IS
  '規格軟刪除：將 status 設為 discontinued';
