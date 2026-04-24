-- 驗 home_store_id 改變守衛
BEGIN;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000099","tenant_id":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

CREATE TEMP TABLE _r (scn TEXT, verdict TEXT, msg TEXT);

-- A: 同 store 改其他欄位 → 應通
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    -- Alex Chen (id=6) 目前 home_store=1；改 store 仍=1 + 改名
    PERFORM rpc_upsert_member(6, 'M20260424072640046', '0979297810', 'Alex Chen 改', NULL, NULL, NULL, NULL, 1, 'active', NULL);
    INSERT INTO _r VALUES ('A 同 store 改其他欄位', 'PASS', 'no error');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    INSERT INTO _r VALUES ('A 同 store 改其他欄位', 'FAIL', v_msg);
  END;
END $$;

-- B: 改 store + 該會員身上有 pending 訂單 → 應拒
-- 先確保有 pending 訂單存在
SELECT COUNT(*) AS open_orders FROM customer_orders WHERE member_id=6 AND status NOT IN ('completed','cancelled','expired');
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    PERFORM rpc_upsert_member(6, 'M20260424072640046', '0979297810', 'Alex Chen 改', NULL, NULL, NULL, NULL, 999, 'active', NULL);
    INSERT INTO _r VALUES ('B 有未完成訂單改 store', 'FAIL', '應該拒絕但通了');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    INSERT INTO _r VALUES ('B 有未完成訂單改 store', CASE WHEN v_msg LIKE '%未取貨訂單%' THEN 'PASS' ELSE 'FAIL' END, v_msg);
  END;
END $$;

-- C: 改 store + 訂單全 completed → 應通
UPDATE customer_orders SET status='completed' WHERE member_id=6;
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    PERFORM rpc_upsert_member(6, 'M20260424072640046', '0979297810', 'Alex Chen 改', NULL, NULL, NULL, NULL, 1, 'active', NULL);
    INSERT INTO _r VALUES ('C 訂單全 completed 改 store', 'PASS', 'no error');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    INSERT INTO _r VALUES ('C 訂單全 completed 改 store', 'FAIL', v_msg);
  END;
END $$;

-- D: 沒訂單的 member 改 store → 應通（用 member id=5 asdasd）
DO $$
DECLARE v_msg TEXT;
BEGIN
  BEGIN
    PERFORM rpc_upsert_member(5, 'M20260424071146106', (SELECT phone FROM members WHERE id=5), 'asdasd', NULL, NULL, NULL, NULL, 1, 'active', NULL);
    INSERT INTO _r VALUES ('D 無訂單會員改 store', 'PASS', 'no error');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    INSERT INTO _r VALUES ('D 無訂單會員改 store', 'FAIL', v_msg);
  END;
END $$;

SELECT * FROM _r ORDER BY scn;
ROLLBACK;
