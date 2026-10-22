-- בדיקות מקומיות למיגרציות 126 ו-127. הרצה: plans/drafts/tests/run-local.sh
\set ON_ERROR_STOP on
\set A  '''a0000000-0000-0000-0000-000000000001'''
\set B  '''b0000000-0000-0000-0000-000000000002'''
\set L  '''c0000000-0000-0000-0000-000000000003'''
\set M  '''d0000000-0000-0000-0000-000000000004'''

\echo === שלב א: המצב הנוכחי (לפני 126). העדכון הישיר נכשל בשקט ===
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111',
  'WITH u AS (UPDATE public.tenants SET industry = ''interior'' RETURNING 1) SELECT count(*) FROM u'),
  'ok:0', 'עדכון ישיר מעדכן 0 שורות ובלי שגיאה');
SELECT t.eq((SELECT industry FROM public.tenants WHERE id = :A), 'other', 'התחום לא השתנה');

\echo === שלב ב: החלת 126 ===
\i plans/drafts/126_set_tenant_industry.sql

\echo --- הרשאות
SELECT t.eq((SELECT count(*)::text FROM pg_proc WHERE proname = 'set_tenant_industry'), '1', 'overload יחיד');
SELECT t.eq(has_function_privilege('anon','public.set_tenant_industry(text,boolean)','EXECUTE')::text, 'false', 'anon לא יכול להריץ');
SELECT t.eq(has_function_privilege('authenticated','public.set_tenant_industry(text,boolean)','EXECUTE')::text, 'true', 'authenticated יכול להריץ');
SELECT t.eq(has_function_privilege('service_role','public.set_tenant_industry(text,boolean)','EXECUTE')::text, 'false', 'service_role לא נדרש, ואין לו הרשאה');
SELECT t.like(t.run('anon', NULL, 'SELECT public.set_tenant_industry(''interior'')::text'), 'err:permission denied%', 'anon נחסם');
SELECT t.like(t.run('authenticated', NULL, 'SELECT public.set_tenant_industry(''interior'')::text'), 'err:not authenticated%', 'בלי JWT נחסם');
SELECT t.like(t.run('authenticated','99999999-9999-9999-9999-999999999999', 'SELECT public.set_tenant_industry(''interior'')::text'), 'err:no tenant%', 'משתמש בלי עסק נחסם');
SELECT t.like(t.run('authenticated','12121212-1212-1212-1212-121212121212', 'SELECT public.set_tenant_industry(''interior'')::text'), 'err:insufficient permissions%', 'תפקיד agent נחסם');
SELECT t.like(t.run('authenticated','13131313-1313-1313-1313-131313131313', 'SELECT public.set_tenant_industry(''interior'')::text'), 'err:insufficient permissions%', 'תפקיד viewer נחסם');

\echo --- ולידציה
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(NULL)::text'), 'err:invalid_industry', 'null נדחה');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry('''')::text'), 'err:invalid_industry', 'מחרוזת ריקה נדחית');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''real_estate'')::text'), 'err:invalid_industry', 'ערך ישן מהסכמה הישנה נדחה');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''REALESTATE'')::text'), 'err:invalid_industry', 'אותיות גדולות נדחות');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''realestate '')::text'), 'err:invalid_industry', 'רווח בסוף נדחה');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''interior''''; DROP TABLE tenants; --'')::text'), 'err:invalid_industry', 'ניסיון הזרקה נדחה');
SELECT t.eq((SELECT industry FROM public.tenants WHERE id = :A), 'other', 'אחרי כל הדחיות התחום לא השתנה');

\echo --- שמירה תקינה ואי אפשר לשנות שדות אחרים
CREATE TEMP TABLE before_a AS SELECT to_jsonb(x) - 'industry' - 'onboarding_completed' - 'updated_at' AS j FROM public.tenants x WHERE id = :A;
CREATE TEMP TABLE before_other AS SELECT id, to_jsonb(x) AS j FROM public.tenants x WHERE id <> :A;
GRANT SELECT ON before_a, before_other TO PUBLIC;
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''interior'')::text'),
  'ok:{"industry": "interior", "onboarding_completed": false}', 'owner שומר תחום, האשף נשאר פתוח');
SELECT t.eq((SELECT industry FROM public.tenants WHERE id = :A), 'interior', 'התחום נשמר ב-DB');
SELECT t.eq(t.run('authenticated','14141414-1414-1414-1414-141414141414', 'SELECT public.set_tenant_industry(''other'', true)::text'),
  'ok:{"industry": "other", "onboarding_completed": true}', 'admin שומר תחום ומסיים אשף');
SELECT t.eq((SELECT (to_jsonb(x) - 'industry' - 'onboarding_completed' - 'updated_at' = (SELECT j FROM before_a))::text FROM public.tenants x WHERE id = :A),
  'true', 'כל שאר העמודות של העסק לא השתנו (plan, trial_ends_at, marketing_addon, stripe, name, slug)');
SELECT t.eq((SELECT count(*)::text FROM public.tenants x JOIN before_other b ON b.id = x.id WHERE to_jsonb(x) <> b.j), '0', 'שורות של עסקים אחרים לא השתנו בכלל');
SELECT t.eq((SELECT count(*)::text FROM public.plan_change_log), '0', 'טריגר ה-plan לא הופעל');
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''realestate'', false)::text'),
  'ok:{"industry": "realestate", "onboarding_completed": true}', 'onboarding_completed לא חוזר מ-true ל-false');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''interior'', NULL)::text'),
  'ok:{"industry": "interior", "onboarding_completed": true}', 'null בדגל לא מאפס אותו');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(p_industry => ''interior'', p_plan => ''lifetime'')::text'),
  'err:function public.set_tenant_industry% does not exist%', 'אי אפשר להעביר פרמטר נוסף (plan)');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(p_industry => ''interior'', p_tenant_id => ''b0000000-0000-0000-0000-000000000002'')::text'),
  'err:function public.set_tenant_industry% does not exist%', 'אי אפשר לציין עסק אחר');

\echo --- עסק של עורך דין
SELECT t.like(t.run('authenticated','33333333-3333-3333-3333-333333333333', 'SELECT public.set_tenant_industry(''realestate'')::text'),
  'err:industry_change_locked%', 'עו"ד עם לידים לא יכול לצאת מהתחום');
SELECT t.eq((SELECT industry FROM public.tenants WHERE id = :L), 'realestate_lawyer', 'התחום של עו"ד נשאר');
SELECT t.eq(t.run('authenticated','33333333-3333-3333-3333-333333333333', 'SELECT public.set_tenant_industry(''realestate_lawyer'')::text'),
  'ok:{"industry": "realestate_lawyer", "onboarding_completed": true}', 'עו"ד יכול לשמור שוב את אותו תחום');
SELECT t.eq(t.run('authenticated','44444444-4444-4444-4444-444444444444', 'SELECT public.set_tenant_industry(''interior'')::text'),
  'ok:{"industry": "interior", "onboarding_completed": false}', 'עו"ד בלי נתונים (בחירה בטעות באשף) יכול לתקן');
SELECT t.eq(t.run('authenticated','44444444-4444-4444-4444-444444444444', 'SELECT public.set_tenant_industry(''realestate_lawyer'')::text'),
  'ok:{"industry": "realestate_lawyer", "onboarding_completed": false}', 'וכניסה לתחום עו"ד מותרת');

\echo --- עמידות מול search_path
CREATE SCHEMA evil;
CREATE TABLE evil.agent_users (tenant_id uuid, auth_user_id uuid, role text);
INSERT INTO evil.agent_users VALUES ('b0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'owner');
GRANT USAGE ON SCHEMA evil TO authenticated; GRANT SELECT ON evil.agent_users TO authenticated;
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111',
  'SELECT (set_config(''search_path'', ''evil,public'', true) IS NOT NULL)::text || public.set_tenant_industry(''other'')::text'),
  'ok:true{"industry": "other", "onboarding_completed": true}', 'search_path זדוני לא מפנה את העדכון לעסק אחר');
SELECT t.eq((SELECT industry FROM public.tenants WHERE id = :B), 'realestate', 'העסק B לא הושפע');
DROP SCHEMA evil CASCADE;

\echo === שלב ג: החלת 127 ===
-- לפני: למשתמש מחובר יש הרשאת UPDATE, וגם הרשאת עמודה
SELECT t.eq(has_table_privilege('authenticated','public.tenants','UPDATE')::text, 'true', 'לפני 127: יש UPDATE ברמת הטבלה');
SELECT t.eq(has_column_privilege('authenticated','public.tenants','onboarding_completed','UPDATE')::text, 'true', 'לפני 127: יש UPDATE על העמודה');
\i plans/drafts/127_revoke_tenants_update.sql
SELECT t.eq(has_table_privilege('authenticated','public.tenants','UPDATE')::text, 'false', 'אחרי 127: אין UPDATE ברמת הטבלה');
SELECT t.eq((SELECT count(*)::text FROM information_schema.columns c WHERE c.table_name = 'tenants' AND c.table_schema = 'public'
   AND has_column_privilege('authenticated','public.tenants', c.column_name, 'UPDATE')), '0', 'אחרי 127: אין UPDATE על אף עמודה, כולל onboarding_completed');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'WITH u AS (UPDATE public.tenants SET plan = ''lifetime'' RETURNING 1) SELECT count(*) FROM u'),
  'err:permission denied for table tenants', 'עדכון ישיר של plan נכשל בשגיאה ולא בשקט');
SELECT t.like(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'WITH u AS (UPDATE public.tenants SET onboarding_completed = true RETURNING 1) SELECT count(*) FROM u'),
  'err:permission denied for table tenants', 'גם עדכון onboarding_completed ישיר נכשל');

\echo --- שום פונקציונליות לגיטימית לא נשברת
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.set_tenant_industry(''interior'')::text'),
  'ok:{"industry": "interior", "onboarding_completed": true}', 'set_tenant_industry עובד אחרי 127');
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.update_tenant_profile(''New Name'')::text'),
  'ok:', 'update_tenant_profile (SECURITY DEFINER) עובד');
SELECT t.eq((SELECT name FROM public.tenants WHERE id = :A), 'New Name', 'והשם נשמר');
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT public.admin_set_plan(''a0000000-0000-0000-0000-000000000001'', ''basic'')::text'),
  'ok:', 'פונקציית admin (SECURITY DEFINER) עדיין מעדכנת plan');
SELECT t.eq((SELECT count(*)::text FROM public.plan_change_log), '1', 'וטריגר ה-plan רץ');
SELECT t.like(t.run('service_role', NULL, 'WITH u AS (UPDATE public.tenants SET notes_placeholder = 1 RETURNING 1) SELECT count(*) FROM u'), 'err:column%notes_placeholder%', 'service_role עדיין מורשה (השגיאה היא על עמודה לא קיימת, לא על הרשאה)');
SELECT t.eq(t.run('service_role', NULL, 'WITH u AS (UPDATE public.tenants SET marketing_addon = true WHERE id = ''b0000000-0000-0000-0000-000000000002'' RETURNING 1) SELECT count(*) FROM u'),
  'ok:1', 'service_role מעדכן tenants');
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'SELECT count(*) FROM public.tenants'), 'ok:1', 'SELECT עם RLS ממשיך להחזיר רק את העסק של המשתמש');
SELECT t.eq(t.run('anon', NULL, 'SELECT count(*) FROM public.tenants'), 'err:permission denied for table tenants', 'anon עדיין חסום מהטבלה (כמו בחי, שם אין לו הרשאות)');
SELECT t.eq((SELECT (updated_at > now() - interval '1 minute')::text FROM public.tenants WHERE id = :A), 'true', 'טריגר updated_at עדיין רץ');

\echo === שלב ד: חזרה לאחור של 127 ===
GRANT UPDATE ON TABLE public.tenants TO authenticated;
SELECT t.eq(has_table_privilege('authenticated','public.tenants','UPDATE')::text, 'true', 'ה-GRANT מחזיר את ההרשאה');
SELECT t.eq(t.run('authenticated','11111111-1111-1111-1111-111111111111', 'WITH u AS (UPDATE public.tenants SET plan = ''lifetime'' RETURNING 1) SELECT count(*) FROM u'),
  'ok:0', 'אחרי החזרה, RLS חוסם שוב בשקט (המצב המקורי)');
\echo === כל הבדיקות עברו ===
