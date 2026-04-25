-- ============================================================================
-- Issue #75: members.member_type + customer_orders.order_type + guest RPCs
-- PRD-訂單取貨模組.md §Q8
-- ============================================================================

-- 1. members.member_type
ALTER TABLE members
  ADD COLUMN IF NOT EXISTS member_type TEXT NOT NULL DEFAULT 'full'
    CHECK (member_type IN ('full','guest'));

-- 2. customer_orders.order_type
ALTER TABLE customer_orders
  ADD COLUMN IF NOT EXISTS order_type TEXT NOT NULL DEFAULT 'regular'
    CHECK (order_type IN ('regular','employee','guest'));

-- ============================================================================
-- RPC: rpc_create_guest_member
-- 小幫手遇到無法綁定的 nickname → 自動建訪客會員
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_create_guest_member(
  p_tenant_id  UUID,
  p_channel_id BIGINT,
  p_nickname   TEXT
) RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id  BIGINT;
  v_store_id   BIGINT;
BEGIN
  SELECT home_store_id INTO v_store_id
    FROM line_channels
   WHERE id = p_channel_id AND tenant_id = p_tenant_id;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'channel % not found for tenant %', p_channel_id, p_tenant_id;
  END IF;

  -- 插入訪客會員；member_no 先用 placeholder，再用 id 補正
  INSERT INTO members (
    tenant_id, home_store_id, member_type, name, member_no,
    created_by, updated_by, created_at, updated_at
  ) VALUES (
    p_tenant_id, v_store_id, 'guest', p_nickname, 'G-PENDING',
    auth.uid(), auth.uid(), NOW(), NOW()
  ) RETURNING id INTO v_member_id;

  UPDATE members
     SET member_no = 'G' || lpad(v_member_id::text, 8, '0')
   WHERE id = v_member_id;

  -- 在 customer_line_aliases 記錄 nickname 對應
  INSERT INTO customer_line_aliases (tenant_id, channel_id, nickname, member_id,
                                     created_at, updated_at)
  VALUES (p_tenant_id, p_channel_id, p_nickname, v_member_id, NOW(), NOW())
  ON CONFLICT (tenant_id, channel_id, nickname) DO NOTHING;

  RETURN v_member_id;
END;
$$;

-- ============================================================================
-- RPC: rpc_merge_member
-- 訪客升級為正式會員時，搬移所有關聯資料
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_merge_member(
  p_guest_id BIGINT,
  p_real_id  BIGINT,
  p_operator UUID DEFAULT NULL,
  p_reason   TEXT DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tenant    UUID;
  v_operator  UUID;
  v_points    NUMERIC(18,2);
  v_wallet    NUMERIC(18,2);
  v_cards     INTEGER;
BEGIN
  v_operator := COALESCE(p_operator, auth.uid());

  SELECT tenant_id INTO v_tenant FROM members WHERE id = p_guest_id;

  -- 守衛
  IF (SELECT member_type FROM members WHERE id = p_guest_id) <> 'guest' THEN
    RAISE EXCEPTION 'member % is not a guest', p_guest_id;
  END IF;
  IF (SELECT status FROM members WHERE id = p_guest_id) = 'merged' THEN
    RAISE EXCEPTION 'member % is already merged', p_guest_id;
  END IF;
  IF p_guest_id = p_real_id THEN
    RAISE EXCEPTION 'guest_id and real_id must differ';
  END IF;

  -- 搬訂單
  UPDATE customer_orders SET member_id = p_real_id WHERE member_id = p_guest_id;

  -- 搬 LINE 暱稱對應
  UPDATE customer_line_aliases SET member_id = p_real_id WHERE member_id = p_guest_id;

  -- 搬標籤
  UPDATE member_tags SET member_id = p_real_id WHERE member_id = p_guest_id;

  -- 搬會員卡
  SELECT COUNT(*) INTO v_cards FROM member_cards WHERE member_id = p_guest_id;
  UPDATE member_cards SET member_id = p_real_id WHERE member_id = p_guest_id;

  -- 取得訪客點數 / 儲值金餘額
  SELECT COALESCE(balance, 0) INTO v_points
    FROM member_points_balance WHERE tenant_id = v_tenant AND member_id = p_guest_id;
  SELECT COALESCE(balance, 0) INTO v_wallet
    FROM wallet_balances WHERE tenant_id = v_tenant AND member_id = p_guest_id;

  -- 搬流水帳
  UPDATE points_ledger  SET member_id = p_real_id WHERE member_id = p_guest_id;
  UPDATE wallet_ledger  SET member_id = p_real_id WHERE member_id = p_guest_id;

  -- 合併餘額（UPSERT）
  INSERT INTO member_points_balance (tenant_id, member_id, balance, version, updated_at)
  VALUES (v_tenant, p_real_id, GREATEST(v_points, 0), 1, NOW())
  ON CONFLICT (tenant_id, member_id) DO UPDATE
    SET balance          = member_points_balance.balance + GREATEST(EXCLUDED.balance, 0),
        version          = member_points_balance.version + 1,
        last_movement_at = NOW(),
        updated_at       = NOW();

  INSERT INTO wallet_balances (tenant_id, member_id, balance, version, updated_at)
  VALUES (v_tenant, p_real_id, GREATEST(v_wallet, 0), 1, NOW())
  ON CONFLICT (tenant_id, member_id) DO UPDATE
    SET balance          = wallet_balances.balance + GREATEST(EXCLUDED.balance, 0),
        version          = wallet_balances.version + 1,
        last_movement_at = NOW(),
        updated_at       = NOW();

  -- 刪除訪客餘額快取列
  DELETE FROM member_points_balance WHERE tenant_id = v_tenant AND member_id = p_guest_id;
  DELETE FROM wallet_balances        WHERE tenant_id = v_tenant AND member_id = p_guest_id;

  -- 標記訪客為 merged
  UPDATE members
     SET status                = 'merged',
         merged_into_member_id = p_real_id,
         updated_at            = NOW(),
         updated_by            = v_operator
   WHERE id = p_guest_id;

  -- 寫合併紀錄
  INSERT INTO member_merges (
    tenant_id, primary_member_id, merged_member_id,
    points_moved, wallet_moved, cards_moved, reason, operator_id
  ) VALUES (
    v_tenant, p_real_id, p_guest_id,
    v_points, v_wallet, v_cards, p_reason, v_operator
  );
END;
$$;
