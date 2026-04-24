-- ============================================================
-- 改 home_store_id 守衛：member 身上有未取貨訂單時不允許改取貨店
-- 「未取貨」= status NOT IN ('completed','cancelled','expired')
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_upsert_member(
  p_id            BIGINT,
  p_member_no     TEXT,
  p_phone         TEXT,
  p_name          TEXT,
  p_gender        TEXT DEFAULT NULL,
  p_birthday      DATE DEFAULT NULL,
  p_email         TEXT DEFAULT NULL,
  p_tier_id       BIGINT DEFAULT NULL,
  p_home_store_id BIGINT DEFAULT NULL,
  p_status        TEXT DEFAULT 'active',
  p_notes         TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_tenant      UUID := public._current_tenant_id();
  v_id          BIGINT;
  v_phone_hash  TEXT;
  v_email_hash  TEXT;
  v_birth_md    TEXT;
  v_old_store   BIGINT;
  v_open_orders INT;
BEGIN
  IF p_phone IS NULL OR p_phone = '' THEN
    RAISE EXCEPTION 'phone is required';
  END IF;
  IF p_name IS NULL OR p_name = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;

  v_phone_hash := encode(digest(p_phone, 'sha256'), 'hex');
  v_email_hash := CASE WHEN p_email IS NOT NULL AND p_email <> ''
                       THEN encode(digest(lower(p_email), 'sha256'), 'hex')
                  END;
  v_birth_md   := CASE WHEN p_birthday IS NOT NULL
                       THEN to_char(p_birthday, 'MM-DD')
                  END;

  IF p_tier_id IS NOT NULL THEN
    PERFORM 1 FROM member_tiers WHERE id = p_tier_id AND tenant_id = v_tenant;
    IF NOT FOUND THEN RAISE EXCEPTION 'tier % not in tenant', p_tier_id; END IF;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO members (
      tenant_id, member_no, phone_hash, phone, email_hash, email,
      name, birthday, birth_md, gender, tier_id, home_store_id,
      status, notes, created_by, updated_by
    ) VALUES (
      v_tenant, p_member_no, v_phone_hash, p_phone, v_email_hash, p_email,
      p_name, p_birthday, v_birth_md, p_gender, p_tier_id, p_home_store_id,
      COALESCE(p_status, 'active'), p_notes, auth.uid(), auth.uid()
    ) RETURNING id INTO v_id;
  ELSE
    -- 取得目前 home_store_id；若有變更，先檢查未完成訂單
    SELECT home_store_id INTO v_old_store FROM members
     WHERE id = p_id AND tenant_id = v_tenant;
    IF NOT FOUND THEN RAISE EXCEPTION 'member % not in tenant', p_id; END IF;

    IF v_old_store IS DISTINCT FROM p_home_store_id THEN
      SELECT COUNT(*) INTO v_open_orders FROM customer_orders
       WHERE tenant_id = v_tenant
         AND member_id = p_id
         AND status NOT IN ('completed','cancelled','expired');
      IF v_open_orders > 0 THEN
        RAISE EXCEPTION '會員仍有 % 筆未取貨訂單，請先處理完才能改取貨店', v_open_orders;
      END IF;
    END IF;

    UPDATE members SET
      member_no     = COALESCE(p_member_no, member_no),
      phone_hash    = v_phone_hash,
      phone         = p_phone,
      email_hash    = v_email_hash,
      email         = p_email,
      name          = COALESCE(p_name, name),
      birthday      = p_birthday,
      birth_md      = v_birth_md,
      gender        = p_gender,
      tier_id       = p_tier_id,
      home_store_id = p_home_store_id,
      status        = COALESCE(p_status, status),
      notes         = p_notes,
      updated_by    = auth.uid()
    WHERE id = p_id AND tenant_id = v_tenant
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'member % not in tenant', p_id; END IF;
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_upsert_member TO authenticated;
