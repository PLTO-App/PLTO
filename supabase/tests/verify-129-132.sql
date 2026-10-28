-- בדיקת מצב אחרי הרצת מיגרציות 129, 130, 131 ו-132. קריאה בלבד: רק SELECT על קטלוג Postgres.
-- מריצים ב-SQL Editor של Supabase. כל שורה צריכה להיות ok = true אחרי שלוש המיגרציות.
-- לפני ההרצה (נבדק בחי ב-28.10.2026): שורות עם הקידומת base_ מחזירות true, ולפחות שורה אחת מכל קבוצה
-- (129_, 130_, 131_, 132_) מחזירה false. אם שורת base_ מחזירה false, עוצרים: המצב הקיים שונה ממה שנבדק.
-- אפשר להריץ אותו גם אחרי מיגרציה אחת בלבד, ולבדוק רק את השורות שלה (הקידומת 129_, 130_, 131_ או 132_).
--
-- הבדיקה לא מוכיחה התנהגות של משתמש אמיתי. את זה בודקים באפליקציה, לפי הרנבוק (plans/migrations-129-131-runbook.md).

WITH c(check_name, expected, actual) AS (
  VALUES
  -- ── 129: גישה חינמית בשרת ──
  ('129_free_growth_period_exists', 'true',
     (SELECT (count(*) = 1)::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'free_growth_period')),
  ('129_free_growth_period_not_callable_by_clients', 'false',
     (SELECT coalesce(bool_or(has_function_privilege('anon', oid, 'EXECUTE') OR has_function_privilege('authenticated', oid, 'EXECUTE')), false)::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'free_growth_period')),
  ('129_tenant_access_active_uses_switch', 'true',
     (SELECT (pg_get_functiondef(oid) LIKE '%free_growth_period()%')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'tenant_access_active')),
  ('129_public_page_active_uses_switch', 'true',
     (SELECT (pg_get_functiondef(oid) LIKE '%free_growth_period()%')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'public_page_tenant_active')),
  ('base_cancelled_still_blocked_in_rls_fn', 'true',
     (SELECT (pg_get_functiondef(oid) LIKE '%plan = ''cancelled'' THEN false%')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'tenant_access_active')),
  ('base_cancelled_still_blocked_in_public_fn', 'true',
     (SELECT (pg_get_functiondef(oid) LIKE '%plan = ''cancelled'' THEN false%')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'public_page_tenant_active')),
  ('base_tenant_access_active_still_secdef', 'true',
     (SELECT prosecdef::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'tenant_access_active')),
  ('base_tenant_access_active_authenticated_can_execute', 'true',
     (SELECT has_function_privilege('authenticated', oid, 'EXECUTE')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'tenant_access_active')),
  ('base_public_page_active_anon_can_execute', 'true',
     (SELECT has_function_privilege('anon', oid, 'EXECUTE')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'public_page_tenant_active')),

  -- ── 130: התקדמות בשרת ──
  ('130_table_exists_with_rls', 'true',
     (SELECT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.agent_progress')), false)::text)),
  ('130_no_direct_client_table_access', 'false',
     (SELECT CASE WHEN to_regclass('public.agent_progress') IS NULL THEN 'missing'
        ELSE (has_table_privilege('anon', 'public.agent_progress', 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('authenticated', 'public.agent_progress', 'SELECT,INSERT,UPDATE,DELETE'))::text END)),
  ('130_no_policies_for_client_roles', '0',
     (SELECT count(*)::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'agent_progress')),
  ('130_rpc_callable_only_by_authenticated', 'true',
     (SELECT (count(*) = 2 AND bool_and(has_function_privilege('authenticated', oid, 'EXECUTE') AND NOT has_function_privilege('anon', oid, 'EXECUTE')))::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('get_my_progress', 'save_my_progress'))),
  ('130_rpc_are_security_definer_with_fixed_search_path', 'true',
     (SELECT (count(*) = 2 AND bool_and(prosecdef AND proconfig IS NOT NULL))::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('get_my_progress', 'save_my_progress'))),
  ('130_size_and_shape_constraints', '2',
     (SELECT count(*)::text FROM pg_constraint WHERE conrelid = to_regclass('public.agent_progress') AND contype = 'c')),

  -- ── 131: agent_users בהרשאות מינימליות ──
  ('131_policy_names', 'agent_users_select_same_tenant,agent_users_update_own_row',
     (SELECT coalesce(string_agg(policyname, ',' ORDER BY policyname), '') FROM pg_policies WHERE schemaname = 'public' AND tablename = 'agent_users')),
  ('131_authenticated_cannot_insert_delete_or_update_whole_table', 'false',
     (SELECT has_table_privilege('authenticated', 'public.agent_users', 'INSERT,DELETE,UPDATE,TRUNCATE')::text)),
  ('131_authenticated_can_select', 'true',
     (SELECT has_table_privilege('authenticated', 'public.agent_users', 'SELECT')::text)),
  ('131_anon_has_no_access', 'false',
     (SELECT (has_table_privilege('anon', 'public.agent_users', 'SELECT') OR has_any_column_privilege('anon', 'public.agent_users', 'UPDATE'))::text)),
  ('131_updatable_columns', 'avatar_url,name,phone',
     (SELECT coalesce(string_agg(a.attname, ',' ORDER BY a.attname), '')
        FROM pg_attribute a
       WHERE a.attrelid = 'public.agent_users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
         AND has_column_privilege('authenticated', 'public.agent_users', a.attnum, 'UPDATE'))),
  -- ── 132: הגנות על שליחת WhatsApp ──
  -- בלי קריאה לפונקציות או המרת regclass מפורשת לאובייקטים שעוד לא קיימים (שאילתה כזו נכשלת בפענוח לפני ההרצה)
  ('132_normalize_il_mobile_exists', 'true',
     (SELECT (count(*) = 1 AND bool_and(prosrc LIKE '%^9725[0-9]{8}$%'))::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'normalize_il_mobile')),
  ('132_log_table_rls_and_no_client_access', 'true',
     (SELECT coalesce(((SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.whatsapp_send_log'))
          AND NOT has_table_privilege('anon', to_regclass('public.whatsapp_send_log'), 'SELECT,INSERT,UPDATE,DELETE')
          AND NOT has_table_privilege('authenticated', to_regclass('public.whatsapp_send_log'), 'SELECT,INSERT,UPDATE,DELETE')), false)::text)),
  ('132_log_has_no_phone_or_text_columns', 'agent_id,created_at,event,id,tenant_id',
     (SELECT string_agg(attname, ',' ORDER BY attname) FROM pg_attribute WHERE attrelid = to_regclass('public.whatsapp_send_log') AND attnum > 0 AND NOT attisdropped)),
  ('132_reserve_callable_by_service_role_only', 'true',
     (SELECT (count(*) = 1 AND bool_and(has_function_privilege('service_role', oid, 'EXECUTE')
        AND NOT has_function_privilege('authenticated', oid, 'EXECUTE') AND NOT has_function_privilege('anon', oid, 'EXECUTE')))::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'reserve_whatsapp_send')),
  ('132_reserve_is_security_definer_with_fixed_search_path', 'true',
     (SELECT (count(*) = 1 AND bool_and(prosecdef AND proconfig IS NOT NULL))::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'reserve_whatsapp_send')),
  ('132_default_limits', '20/200',
     (SELECT substring(prosrc from '"tenant_daily": ([0-9]+)') || '/' || substring(prosrc from '"global_daily": ([0-9]+)')
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'whatsapp_limits')),
  ('132_number_setter_validates_and_checks_role', 'true',
     (SELECT (pg_get_functiondef(oid) LIKE '%invalid_whatsapp_number%' AND pg_get_functiondef(oid) LIKE '%insufficient permissions%')::text
        FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'update_tenant_integrations')),
  ('base_number_setter_callable_by_authenticated', 'true',
     (SELECT has_function_privilege('authenticated', oid, 'EXECUTE')::text FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'update_tenant_integrations')),
  ('base_agent_users_rls_enabled', 'true',
     (SELECT relrowsecurity::text FROM pg_class WHERE oid = 'public.agent_users'::regclass)),
  ('base_service_role_keeps_full_access', 'true',
     (SELECT has_table_privilege('service_role', 'public.agent_users', 'SELECT,INSERT,UPDATE,DELETE')::text)),
  ('base_leads_policy_unchanged', 'tenant isolation',
     (SELECT string_agg(policyname, ',' ORDER BY policyname) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'leads' AND policyname = 'tenant isolation'))
)
SELECT check_name, expected, coalesce(actual, 'missing') AS actual, (expected = coalesce(actual, 'missing')) AS ok
  FROM c
 ORDER BY check_name;

-- ── צילום נתונים: מריצים לפני ואחרי, והערכים חייבים להיות זהים (המיגרציות לא משנות שורות) ──
-- הערכים שנצפו בחי ב-28.10.2026 לפני כל מיגרציה: agents=4, tenants=4, leads=28,
-- agent_hash=4ceb2176b823b507afee7240692e8dca, tenant_hash=848b9bfe4b23618b0fde10dec00baff4
-- (ה-hash מחושב על מזהים, תפקיד, פעילות, תוכנית ותאריך ניסיון בלבד, בלי שמות או אימיילים)
SELECT
  (SELECT count(*) FROM agent_users) AS agents,
  (SELECT count(*) FROM tenants)     AS tenants,
  (SELECT count(*) FROM leads)       AS leads,
  (SELECT md5(string_agg(id::text || tenant_id::text || coalesce(role, '') || coalesce(is_active::text, '') || coalesce(auth_user_id::text, ''), '|' ORDER BY id)) FROM agent_users) AS agent_hash,
  (SELECT md5(string_agg(id::text || plan || coalesce(trial_ends_at::text, ''), '|' ORDER BY id)) FROM tenants) AS tenant_hash;
