-- ============================================================================
-- members 直接加 line_user_id 欄位
-- 雖然 member_line_bindings 已經記了一份，但 admin UI 直接查 members 時
-- 需要 join 才能拿到 LINE ID，不方便。加冗餘欄位簡化讀取。
-- ============================================================================

ALTER TABLE members ADD COLUMN IF NOT EXISTS line_user_id TEXT;
COMMENT ON COLUMN members.line_user_id IS 'LIFF / LINE Login 綁定的 LINE user id（跟 member_line_bindings 同步維護）';

-- 每個 tenant 內 line_user_id 唯一（同 LINE 帳號不該對應多 member）
CREATE UNIQUE INDEX IF NOT EXISTS uniq_members_line_user_id
  ON members (tenant_id, line_user_id)
  WHERE line_user_id IS NOT NULL;

-- Backfill：從現有 bindings 把 line_user_id 寫回 members
UPDATE members m
   SET line_user_id = b.line_user_id
  FROM member_line_bindings b
 WHERE b.member_id = m.id
   AND b.unbound_at IS NULL
   AND m.line_user_id IS NULL;
