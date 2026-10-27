// הרצה מקומית (לא ב-CI): בתיקייה זמנית מחוץ לריפו: npm i @electric-sql/pglite@0.2.17
// ואז: node <path>/supabase/tests/migrations-129-131.pglite.mjs <repo-root> מתוך אותה תיקייה
// בדיקת מיגרציות 129, 130 ו-131 מול PGlite (Postgres ב-WASM), עם הדמיה של auth ותפקידי Supabase.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const repo = process.argv[2];
const db = new PGlite();
let fails = 0;
const ok = (c, m) => { console.log((c ? '✓ ' : '✗ ') + m); if (!c) fails++; };
const q = async (sql, p) => (await db.query(sql, p)).rows;
const err = async (sql, p) => { try { await db.query(sql, p); return null; } catch (e) { return e.message; } };

const A_T = '00000000-0000-0000-0000-0000000000a1', B_T = '00000000-0000-0000-0000-0000000000b1', C_T = '00000000-0000-0000-0000-0000000000c1';
const A2_U = '10000000-0000-0000-0000-0000000000a2';
const A_U = '10000000-0000-0000-0000-0000000000a1', B_U = '10000000-0000-0000-0000-0000000000b1', C_U = '10000000-0000-0000-0000-0000000000c1';

await db.exec(`
  CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;
  GRANT USAGE ON SCHEMA public TO anon, authenticated;
  -- כמו ב-Supabase: הרשאות ברירת מחדל רחבות לפונקציות ולטבלאות חדשות
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
  CREATE SCHEMA auth; GRANT USAGE ON SCHEMA auth TO anon, authenticated;
  CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  CREATE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.email', true), '') $$;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO anon, authenticated;
  CREATE TABLE public.tenants (id uuid PRIMARY KEY, plan text, trial_ends_at timestamptz);
  CREATE TABLE public.agent_users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid REFERENCES tenants(id), auth_user_id uuid UNIQUE, is_active boolean DEFAULT true, role text DEFAULT 'agent', name text, phone text, avatar_url text, email text);
  CREATE TABLE public.leads (id serial PRIMARY KEY, tenant_id uuid, name text);
  CREATE FUNCTION public.get_my_tenant_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
    AS $$ SELECT tenant_id FROM agent_users WHERE auth_user_id = auth.uid() LIMIT 1; $$;
  -- הגדרות החי לפני המיגרציה
  CREATE FUNCTION public.tenant_access_active() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT CASE WHEN auth.email() IN ('info@plto.app','elgrablidudu@gmail.com') THEN true WHEN t.plan='cancelled' THEN false
      WHEN t.plan='trial' THEN (t.trial_ends_at IS NULL OR now() <= t.trial_ends_at) ELSE true END
    FROM tenants t WHERE t.id = get_my_tenant_id(); $$;
  CREATE FUNCTION public.public_page_tenant_active(p_tenant_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT CASE WHEN t.id IS NULL THEN false WHEN t.plan='cancelled' THEN false
      WHEN t.plan='trial' THEN (t.trial_ends_at IS NULL OR now() <= t.trial_ends_at) ELSE true END
    FROM (SELECT 1) x LEFT JOIN tenants t ON t.id = p_tenant_id; $$;
  ALTER TABLE public.agent_users ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "agents in same tenant" ON public.agent_users USING (tenant_id = get_my_tenant_id() AND tenant_access_active()) WITH CHECK (tenant_id = get_my_tenant_id() AND tenant_access_active());
  ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
  CREATE POLICY tenant_iso ON public.leads FOR ALL USING (tenant_id = get_my_tenant_id() AND tenant_access_active());
  INSERT INTO tenants VALUES ('${A_T}','trial', now() - interval '40 days'), ('${B_T}','basic', null), ('${C_T}','cancelled', null);
  INSERT INTO agent_users (id, tenant_id, auth_user_id, role, name) VALUES (gen_random_uuid(),'${A_T}','${A_U}','owner','בעלים'), (gen_random_uuid(),'${A_T}','${A2_U}','agent','סוכן'), (gen_random_uuid(),'${B_T}','${B_U}','owner','b'), (gen_random_uuid(),'${C_T}','${C_U}','owner','c');
  INSERT INTO leads (tenant_id, name) VALUES ('${A_T}','a1'), ('${B_T}','b1');
`);

const as = async (role, uid) => {
  await db.exec(`RESET ROLE; SELECT set_config('request.jwt.claim.sub', '${uid || ''}', false); SELECT set_config('request.jwt.claim.email', '', false);`);
  if (role) await db.exec(`SET ROLE ${role}`);
};

// לפני 129: ניסיון שפג חסום
await as('authenticated', A_U);
ok((await q('SELECT count(*)::int n FROM leads'))[0].n === 0, 'לפני 129: עסק בניסיון שפג לא רואה לידים (מצב החי היום)');

await as(null);
await db.exec(readFileSync(`${repo}/supabase/migrations/129_free_growth_access.sql`, 'utf8'));

await as('authenticated', A_U);
ok((await q('SELECT count(*)::int n FROM leads'))[0].n === 1, 'אחרי 129: עסק בניסיון שפג רואה את הליד שלו בלבד');
await as('authenticated', C_U);
ok((await q('SELECT tenant_access_active() v'))[0].v === false, 'אחרי 129: עסק cancelled נשאר חסום');
await as('anon');
ok((await q(`SELECT public_page_tenant_active('${A_T}') v`))[0].v === true, 'אחרי 129: דף ציבורי של ניסיון שפג פעיל');
ok((await q(`SELECT public_page_tenant_active('${C_T}') v`))[0].v === false, 'אחרי 129: דף ציבורי של cancelled סגור');
ok(!!(await err('SELECT free_growth_period()')), 'free_growth_period לא ניתנת להרצה ל-anon');
await as('authenticated', A_U);
ok(!!(await err('SELECT free_growth_period()')), 'free_growth_period לא ניתנת להרצה ל-authenticated');

await as(null);
await db.exec(readFileSync(`${repo}/supabase/migrations/130_agent_progress.sql`, 'utf8'));

await as('authenticated', A_U);
const at = await q(`SELECT save_my_progress('{"xp":120,"achievements":["first_lead"]}'::jsonb) v`);
ok(!!at[0].v, 'משתמש A שומר התקדמות');
const got = (await q('SELECT get_my_progress() v'))[0].v;
ok(got?.data?.xp === 120, 'משתמש A קורא את ההתקדמות שלו');
ok(!!(await err('SELECT * FROM agent_progress')), 'אין קריאה ישירה מהטבלה ל-authenticated');
ok(!!(await err(`INSERT INTO agent_progress (agent_id, tenant_id) SELECT id, tenant_id FROM agent_users LIMIT 1`)), 'אין כתיבה ישירה לטבלה');
await q(`SELECT save_my_progress('{"xp":150}'::jsonb)`);
ok((await q('SELECT get_my_progress() v'))[0].v.data.xp === 150, 'שמירה שנייה מעדכנת את אותה שורה');

for (const [bad, label] of [['{"xp":-5}', 'שלילי'], ['{"xp":"abc"}', 'מחרוזת'], ['{"xp":1.5}', 'שבר'], ['{"streak":3}', 'בלי xp'], ['[1,2]', 'מערך'], ['{"xp":123456789}', 'גדול מדי']]) {
  ok(!!(await err(`SELECT save_my_progress($1::jsonb)`, [bad])), `נדחה: xp ${label}`);
}
ok(!!(await err(`SELECT save_my_progress($1::jsonb)`, [JSON.stringify({ xp: 1, pad: 'x'.repeat(40000) })])), 'נדחה: גוש גדול מ-32KB');

await as('authenticated', B_U);
ok((await q('SELECT get_my_progress() v'))[0].v === null, 'משתמש B מעסק אחר לא רואה את ההתקדמות של A');
await as('authenticated', C_U);
ok(/tenant_inactive/.test(await err(`SELECT save_my_progress('{"xp":1}'::jsonb)`) || ''), 'עסק cancelled לא שומר התקדמות');
await as('anon');
ok(!!(await err('SELECT get_my_progress()')), 'anon לא מריץ get_my_progress');
ok(!!(await err(`SELECT save_my_progress('{"xp":1}'::jsonb)`)), 'anon לא מריץ save_my_progress');
await as('authenticated', '');
ok(/not authenticated|42501|28000/.test(await err('SELECT get_my_progress()') || ''), 'בלי משתמש מחובר נדחה');

await as('authenticated', A2_U);
ok((await q('SELECT get_my_progress() v'))[0].v === null, 'משתמש שני באותו עסק לא רואה את ההתקדמות של הראשון');

await as(null);
const rls = (await q(`SELECT relrowsecurity v FROM pg_class WHERE oid='public.agent_progress'::regclass`))[0].v;
ok(rls === true, 'RLS פעיל על agent_progress');

// ── 131: הקשחת agent_users ──
await as('authenticated', A2_U);
const esc = await err(`UPDATE agent_users SET role = 'owner' WHERE auth_user_id = '${A2_U}'`);
ok(!esc && (await q(`SELECT role FROM agent_users WHERE auth_user_id = '${A2_U}'`))[0].role === 'owner', 'לפני 131: סוכן יכול להפוך את עצמו ל-owner (הבעיה, משוחזרת)');
await as(null);
await db.exec(`UPDATE agent_users SET role = 'agent' WHERE auth_user_id = '${A2_U}'`);
await db.exec(readFileSync(`${repo}/supabase/migrations/131_agent_users_least_privilege.sql`, 'utf8'));

await as('authenticated', A2_U);
ok(!!(await err(`UPDATE agent_users SET role = 'owner' WHERE auth_user_id = '${A2_U}'`)), 'אחרי 131: אי אפשר לשנות role');
ok(!!(await err(`UPDATE agent_users SET is_active = false WHERE auth_user_id = '${A_U}'`)), 'אחרי 131: אי אפשר לשנות is_active');
ok(!!(await err(`UPDATE agent_users SET auth_user_id = '${A2_U}' WHERE auth_user_id = '${A_U}'`)), 'אחרי 131: אי אפשר לשנות auth_user_id');
await q(`UPDATE agent_users SET name = 'שם חדש' WHERE auth_user_id = '${A2_U}'`);
await q(`UPDATE agent_users SET name = 'נפרץ' WHERE auth_user_id = '${A_U}'`);
await as(null);
const names = Object.fromEntries((await q('SELECT auth_user_id::text u, name FROM agent_users')).map(r => [r.u, r.name]));
ok(names[A2_U] === 'שם חדש', 'אחרי 131: משתמש משנה את השם של עצמו (כמו בהגדרות)');
ok(names[A_U] === 'בעלים', 'אחרי 131: אי אפשר לשנות שם של משתמש אחר בעסק');
await as('authenticated', A2_U);
ok(!!(await err(`DELETE FROM agent_users WHERE auth_user_id = '${A_U}'`)), 'אחרי 131: אי אפשר למחוק משתמש אחר');
ok(!!(await err(`INSERT INTO agent_users (tenant_id, role) VALUES ('${A_T}', 'owner')`)), 'אחרי 131: אי אפשר להוסיף משתמש ישירות');
const seen = (await q('SELECT tenant_id::text t FROM agent_users')).map(r => r.t);
ok(seen.length === 2 && seen.every(t => t === A_T), 'אחרי 131: רואים רק את המשתמשים של העסק שלך');
ok((await q('SELECT count(*)::int n FROM leads'))[0].n === 1, 'אחרי 131: ההרשאות על לידים לא השתנו');
await as('anon');
ok(!!(await err('SELECT * FROM agent_users')), 'אחרי 131: anon לא קורא את agent_users');
await as('authenticated', C_U);
ok((await q('SELECT count(*)::int n FROM agent_users'))[0].n === 0, 'אחרי 131: עסק שבוטל לא רואה משתמשים');

console.log(fails ? `\n${fails} בדיקות נכשלו` : '\nכל הבדיקות עברו');
process.exit(fails ? 1 : 0);
