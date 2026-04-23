#!/usr/bin/env node
// One-off seed: set tenant_id on a user's app_metadata + insert default brand/category.
// Usage: node .claude-scripts/seed_admin_user.js <email> <tenant_uuid>
// Requires SUPABASE_DB_URL env (from .env).

const { Client } = require("pg");

async function main() {
  const [, , email, tenantId] = process.argv;
  if (!email || !tenantId) {
    console.error("usage: node seed_admin_user.js <email> <tenant_uuid>");
    process.exit(1);
  }
  const url = process.env.SUPABASE_DB_URL;
  if (!url) {
    console.error("missing SUPABASE_DB_URL env");
    process.exit(1);
  }

  const c = new Client({
    connectionString: url,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();
  try {
    // 1. tenant_id into user app_metadata
    const u = await c.query(
      `UPDATE auth.users
          SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
                                  || jsonb_build_object('tenant_id', $2::text)
        WHERE email = $1
        RETURNING id, email, raw_app_meta_data`,
      [email, tenantId]
    );
    if (u.rowCount === 0) {
      console.error(`[FAIL] no user found with email=${email}`);
      process.exit(1);
    }
    console.log(`[OK] user ${email} app_metadata updated:`);
    console.log(`     ${JSON.stringify(u.rows[0].raw_app_meta_data)}`);

    // 2. default brand (idempotent via ON CONFLICT)
    const b = await c.query(
      `INSERT INTO brands (tenant_id, code, name)
       VALUES ($1::uuid, 'DEFAULT', '預設品牌')
       ON CONFLICT (tenant_id, code) DO NOTHING
       RETURNING id`,
      [tenantId]
    );
    console.log(b.rowCount ? "[OK] default brand inserted" : "[SKIP] default brand already exists");

    // 3. default category
    const cat = await c.query(
      `INSERT INTO categories (tenant_id, code, name, level)
       VALUES ($1::uuid, 'DEFAULT', '預設分類', 1)
       ON CONFLICT (tenant_id, code) DO NOTHING
       RETURNING id`,
      [tenantId]
    );
    console.log(cat.rowCount ? "[OK] default category inserted" : "[SKIP] default category already exists");

    console.log("\ndone.");
  } finally {
    await c.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
