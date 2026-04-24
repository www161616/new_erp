-- ============================================================
-- 商品編號自動產生：依溫層加前綴 + 5 位流水
-- F = 冷凍 / R = 冷藏(生鮮) / A = 常溫 / M = 美食列車 / G = 一般
-- 例：F00001、R00012、A00007
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_next_product_code(
  p_storage_type product_storage_type DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_tenant UUID := public._current_tenant_id();
  v_prefix TEXT;
  v_next   INT;
BEGIN
  v_prefix := CASE p_storage_type
    WHEN 'frozen'        THEN 'F'
    WHEN 'refrigerated'  THEN 'R'
    WHEN 'room_temp'     THEN 'A'
    WHEN 'meal_train'    THEN 'M'
    ELSE 'G'
  END;

  SELECT COALESCE(MAX((SUBSTRING(product_code FROM '^' || v_prefix || '(\d+)$'))::INT), 0) + 1
    INTO v_next
    FROM products
   WHERE tenant_id = v_tenant
     AND product_code ~ ('^' || v_prefix || '\d+$');

  RETURN v_prefix || lpad(v_next::text, 5, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_next_product_code TO authenticated;

COMMENT ON FUNCTION public.rpc_next_product_code IS
  '依溫層回傳下一個商品編號：F=冷凍 R=冷藏 A=常溫 M=美食列車 G=未指定';
