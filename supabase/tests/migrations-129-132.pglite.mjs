// הרצה מקומית (לא ב-CI): בתיקייה זמנית מחוץ לריפו: npm i @electric-sql/pglite@0.2.17
// ואז: node <path>/supabase/tests/migrations-129-132.pglite.mjs <repo-root> מתוך אותה תיקייה
// בדיקת מיגרציות 129, 130, 131 ו-132 מול PGlite (Postgres ב-WASM), עם הדמיה של auth ותפקידי Supabase.
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
  CREATE TABLE public.tenants (id uuid PRIMARY KEY, plan text, trial_ends_at timestamptz, whatsapp_number text, make_webhook_url text, updated_at timestamptz);
  CREATE TABLE public.agent_users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid REFERENCES tenants(id), auth_user_id uuid UNIQUE, is_active boolean DEFAULT true, role text DEFAULT 'agent', name text, phone text, avatar_url text, email text);
  CREATE TABLE public.leads (id serial PRIMARY KEY, tenant_id uuid, name text);
  CREATE OR REPLACE FUNCTION public.update_tenant_integrations(p_make_webhook_url text DEFAULT NULL::text, p_whatsapp_number text DEFAULT NULL::text)
   RETURNS void
   LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path TO 'public'
  AS $function$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;

  SELECT tenant_id INTO v_tenant_id
  FROM agent_users
  WHERE auth_user_id = auth.uid()
  LIMIT 1;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'No tenant found for this user';
  END IF;

  UPDATE tenants SET
    make_webhook_url = COALESCE(p_make_webhook_url, make_webhook_url),
    whatsapp_number  = COALESCE(p_whatsapp_number,  whatsapp_number),
    updated_at       = now()
  WHERE id = v_tenant_id;
END;
$function$;
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
  CREATE POLICY "tenant isolation" ON public.leads FOR ALL USING (tenant_id = get_my_tenant_id() AND tenant_access_active());
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

// ── 132: הגנות על שליחת WhatsApp ──
await as(null);
await db.exec(readFileSync(`${repo}/supabase/migrations/132_whatsapp_send_guard.sql`, 'utf8'));
const norm = async v => (await q('SELECT normalize_il_mobile($1) v', [v]))[0].v;
const normCases = [['050-123-4567', '+972501234567'], ['0501234567', '+972501234567'], ['+972 50 123 4567', '+972501234567'], ['972501234567', '+972501234567'],
  ['00972501234567', '+972501234567'], ['(054) 123 4567', '+972541234567'], ['501234567', null], ['0201234567', null], ['03-1234567', null], ['+15551234567', null],
  ['abc', null], ['', null], ['05012345678', null], ['050123456', null], [null, null]];
for (const [inp, exp] of normCases) ok((await norm(inp)) === exp, `normalize_il_mobile(${JSON.stringify(inp)}) = ${exp}`);

// שמירת המספר: בעלים בלבד, מספר ישראלי בלבד, בפורמט אחיד
await as('authenticated', A2_U);
ok(/insufficient permissions/.test(await err(`SELECT update_tenant_integrations(NULL, '0501234567')`) || ''), '132: סוכן (לא בעלים) לא יכול לשמור מספר WhatsApp');
ok(!(await err(`SELECT update_tenant_integrations('https://hook.example/x', NULL)`)), '132: סוכן עדיין יכול לשמור Webhook של Make (כמו קודם)');
await as('authenticated', A_U);
ok(/invalid_whatsapp_number/.test(await err(`SELECT update_tenant_integrations(NULL, '123')`) || '') && /invalid_whatsapp_number/.test(await err(`SELECT update_tenant_integrations(NULL, '+15551234567')`) || ''), '132: מספר לא תקין או לא ישראלי נדחה');
await q(`SELECT update_tenant_integrations(NULL, '050-123-4567')`);
await as(null);
ok((await q(`SELECT whatsapp_number v, make_webhook_url h FROM tenants WHERE id = '${A_T}'`))[0].v === '+972501234567', '132: המספר נשמר בפורמט אחיד');
await as('authenticated', A_U);
await q(`SELECT update_tenant_integrations('https://hook.example/y', NULL)`);
await as(null);
ok((await q(`SELECT whatsapp_number v FROM tenants WHERE id = '${A_T}'`))[0].v === '+972501234567', '132: עדכון Webhook בלבד לא נוגע במספר');
await as('authenticated', A_U);
await q(`SELECT update_tenant_integrations(NULL, '   ')`);
await as(null);
ok((await q(`SELECT whatsapp_number v FROM tenants WHERE id = '${A_T}'`))[0].v === null, '132: הגדרה ריקה מוחקת את המספר');
await db.exec(`UPDATE tenants SET whatsapp_number = '0501234567' WHERE id = '${A_T}'`); // פורמט ישן, כמו בחי

// שמירת מקום: רק service_role, והיעד נקבע במסד
await as('authenticated', A_U);
ok(!!(await err(`SELECT reserve_whatsapp_send('${A_U}', 'test')`)), '132: authenticated לא יכול לקרוא ל-reserve_whatsapp_send');
ok(!!(await err('SELECT * FROM whatsapp_send_log')) && !!(await err('SELECT whatsapp_limits()')), '132: הטבלה וההגדרות לא נגישות ללקוח');
await as('anon');
ok(!!(await err(`SELECT reserve_whatsapp_send('${A_U}', 'test')`)), '132: anon לא יכול לקרוא ל-reserve_whatsapp_send');
await as('service_role');
const rsv = async (u, e) => (await q('SELECT reserve_whatsapp_send($1, $2) v', [u, e]))[0].v;
const lim = (await q('SELECT whatsapp_limits() v'))[0].v;
ok(lim.tenant_daily === 20 && lim.global_daily === 200 && lim.alert_at_percent === 80, '132: ברירות המחדל של התקרות: 20 ליום לעסק, 200 כללי, התראה ב-80%');
let r1 = await rsv(A_U, 'test');
ok(r1.ok === true && r1.to === '+972501234567', '132: שמירת מקום מחזירה את המספר של העסק בפורמט אחיד (מהמסד, לא מהלקוח)');
ok((await rsv(A_U, 'free_text')).reason === 'invalid_event' && (await rsv(A_U, null)).reason === 'invalid_event', '132: סוג אירוע לא מוכר נדחה');
ok((await rsv('10000000-0000-0000-0000-00000000ffff', 'test')).reason === 'no_agent' && (await rsv(null, 'test')).reason === 'no_agent', '132: משתמש לא מוכר נדחה');
ok((await rsv(B_U, 'test')).reason === 'no_number', '132: עסק בלי מספר נדחה');
await db.exec(`UPDATE tenants SET whatsapp_number = '+15551234567' WHERE id = '${B_T}'`);
ok((await rsv(B_U, 'test')).reason === 'invalid_number', '132: מספר לא ישראלי שנשמר בעבר נדחה');
await db.exec(`UPDATE tenants SET whatsapp_number = '0501234567' WHERE id = '${C_T}'`);
ok((await rsv(C_U, 'test')).reason === 'tenant_blocked', '132: עסק שבוטל לא שולח');
await as(null);
const logRows = (await q(`SELECT count(*)::int n FROM whatsapp_send_log`))[0].n;
ok(logRows === 1, '132: נרשמה רק השליחה המאושרת, ולא ניסיונות שנדחו');

// תקרות: מחליפים זמנית את ערכי הברירת מחדל בערכים קטנים (תקרה 3 לעסק, 5 כללית, התראה ב-60%)
await as(null);
await db.exec(`CREATE OR REPLACE FUNCTION public.whatsapp_limits() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public','pg_temp' AS $$ SELECT '{"tenant_daily": 3, "global_daily": 5, "alert_at_percent": 60}'::jsonb $$`);
await db.exec(`CREATE TABLE alerts (id serial, subject text); CREATE OR REPLACE FUNCTION public._notify_owner_email(p_subject text, p_html text) RETURNS void LANGUAGE sql AS $$ INSERT INTO alerts (subject) VALUES (p_subject) $$`);
await db.exec(`DELETE FROM whatsapp_send_log; UPDATE tenants SET whatsapp_number = '0501234567' WHERE id = '${B_T}'`);
await db.exec(`INSERT INTO whatsapp_send_log (tenant_id, event, created_at) VALUES ('${A_T}', 'test', now() - interval '2 days'), ('${A_T}', 'test', now() - interval '3 days')`); // אתמול ולפני: לא נספרים
await as('service_role');
const a1 = await rsv(A_U, 'new_lead'), a2 = await rsv(A_U, 'tasks_due'), a3 = await rsv(A_U, 'cold_leads');
ok(a1.ok && a2.ok && a3.ok, '132: שלוש שליחות ראשונות של העסק מאושרות (שליחות ישנות מיומיים לא נספרות)');
const a4 = await rsv(A_U, 'test');
ok(!a4.ok && a4.reason === 'tenant_daily_limit', '132: אחרי התקרה היומית של העסק השליחה נדחית');
const b1 = await rsv(B_U, 'test'), b2 = await rsv(B_U, 'test');
ok(b1.ok && b2.ok, '132: עסק אחר לא מושפע מהתקרה של העסק הראשון');
const b3 = await rsv(B_U, 'test');
ok(!b3.ok && b3.reason === 'global_daily_limit', '132: אחרי התקרה היומית הכללית כל השליחות נדחות');
await as(null);
const alerts = (await q('SELECT subject FROM alerts')).map(r => r.subject);
ok(alerts.length === 1 && /60%/.test(alerts[0]), '132: נשלחה התראה אחת בלבד לבעלים כשהספירה הכללית הגיעה לסף');
ok(!/[0-9]{9}/.test(alerts[0]), '132: בהתראה אין מספרי טלפון');
// כשל בשליחת ההתראה לא מפיל את השמירה
await db.exec(`CREATE OR REPLACE FUNCTION public._notify_owner_email(p_subject text, p_html text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'mail provider down'; END $$; DELETE FROM whatsapp_send_log`);
await as('service_role');
ok((await rsv(A_U, 'new_lead')).ok && (await rsv(A_U, 'new_lead')).ok && (await rsv(A_U, 'new_lead')).ok, '132: כשל בהתראת המייל לא חוסם שליחה מאושרת');
await as(null);
ok((await q('SELECT count(*)::int n FROM pg_attribute WHERE attrelid = \'public.whatsapp_send_log\'::regclass AND attnum > 0 AND attname IN (\'phone\',\'to\',\'message\',\'body\',\'text\')'))[0].n === 0, '132: ביומן אין עמודות של מספר או תוכן');
await db.exec(`DROP FUNCTION public._notify_owner_email(text, text); DROP TABLE alerts; CREATE OR REPLACE FUNCTION public.whatsapp_limits() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public','pg_temp' AS $$ SELECT '{"tenant_daily": 20, "global_daily": 200, "alert_at_percent": 80}'::jsonb $$`);

// ── סקריפט האימות (verify-129-132.sql): אחרי שלוש המיגרציות כל השורות ok ──
await as(null);
const verifySql = readFileSync(`${repo}/supabase/tests/verify-129-132.sql`, 'utf8');
const checksSql = verifySql.slice(verifySql.indexOf('WITH c('), verifySql.indexOf(';', verifySql.indexOf('ORDER BY check_name')));
const vr = await q(checksSql);
const badRows = vr.filter(r => !r.ok);
ok(vr.length >= 20 && badRows.length === 0, `verify-129-132.sql: ${vr.length} בדיקות, כולן ok אחרי המיגרציות` + (badRows.length ? ' | נכשלו: ' + badRows.map(r => `${r.check_name}=${r.actual}`).join(', ') : ''));

// ── חזרה לאחור (supabase/rollback): מחזירה את המצב שהיה בחי ──
// md5 של גוף הפונקציות כפי שנמדד בחי ב-28.10.2026, לפני כל מיגרציה
const LIVE_SRC_MD5 = { tenant_access_active: '932ca3fa4b021c7180f7cc8fcd03cd0a', public_page_tenant_active: '2f41f33379f3f79a8ff299938625b8d2' };
for (const f of ['132_whatsapp_send_guard', '131_agent_users_least_privilege', '130_agent_progress', '129_free_growth_access']) {
  await db.exec(readFileSync(`${repo}/supabase/rollback/${f}.down.sql`, 'utf8'));
}
const bodies = Object.fromEntries((await q(`SELECT proname, md5(prosrc) m, provolatile, prosecdef, proconfig::text cfg FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('tenant_access_active','public_page_tenant_active')`)).map(r => [r.proname, r]));
ok(Object.entries(LIVE_SRC_MD5).every(([k, m]) => bodies[k]?.m === m && bodies[k].provolatile === 's' && bodies[k].prosecdef === true && bodies[k].cfg === '{search_path=public}'), 'אחרי הרולבק: גוף שתי הפונקציות זהה בייט לבייט למה שנמדד בחי, עם אותן הגדרות');
ok((await q(`SELECT count(*)::int n FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('free_growth_period','get_my_progress','save_my_progress')`))[0].n === 0 && (await q(`SELECT to_regclass('public.agent_progress') IS NULL v`))[0].v, 'אחרי הרולבק: free_growth_period, פונקציות ההתקדמות והטבלה הוסרו');
const polAfter = await q(`SELECT policyname, cmd FROM pg_policies WHERE tablename = 'agent_users' ORDER BY 1`);
ok(polAfter.length === 1 && polAfter[0].policyname === 'agents in same tenant' && polAfter[0].cmd === 'ALL', 'אחרי הרולבק: חזרה המדיניות המקורית של agent_users');
const priv = (await q(`SELECT has_table_privilege('authenticated','public.agent_users','INSERT,UPDATE,DELETE') a, has_table_privilege('authenticated','public.agent_users','UPDATE') u, has_any_column_privilege('anon','public.agent_users','SELECT') an`))[0];
ok(priv.a && priv.u, 'אחרי הרולבק: ההרשאות של authenticated על agent_users חזרו (הטבלה כולה)');
const colAcl = (await q(`SELECT count(*)::int n FROM pg_attribute WHERE attrelid = 'public.agent_users'::regclass AND attnum > 0 AND attacl IS NOT NULL`))[0].n;
ok(colAcl === 0, 'אחרי הרולבק: לא נשארו הרשאות ברמת עמודה');
const ut = (await q(`SELECT md5(prosrc) m FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'update_tenant_integrations'`))[0].m;
ok(ut === 'fd942cfa6e3712505ddfe7deef11f7d8', 'אחרי הרולבק: update_tenant_integrations זהה בייט לבייט למה שנמדד בחי');
ok((await q(`SELECT count(*)::int n FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('reserve_whatsapp_send','whatsapp_limits','normalize_il_mobile')`))[0].n === 0 && (await q(`SELECT to_regclass('public.whatsapp_send_log') IS NULL v`))[0].v, 'אחרי הרולבק: פונקציות 132 ויומן השליחות הוסרו');
await as('authenticated', A_U);
ok((await q('SELECT count(*)::int n FROM leads'))[0].n === 0, 'אחרי הרולבק: עסק בניסיון שפג ננעל שוב (המצב הקיים בחי)');
await as('authenticated', A2_U);
ok(!(await err(`UPDATE agent_users SET role = 'owner' WHERE auth_user_id = '${A2_U}'`)), 'אחרי הרולבק: חזרה גם היכולת של סוכן לשנות role (הבעיה המקורית, לכן הרולבק הוא מוצא אחרון)');
await as(null);

console.log(fails ? `\n${fails} בדיקות נכשלו` : '\nכל הבדיקות עברו');
process.exit(fails ? 1 : 0);
