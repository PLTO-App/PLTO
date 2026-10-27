-- Migration 131 (טיוטה, לא הורצה): הקשחת agent_users, כדי שמשתמש לא ישנה לעצמו תפקיד.
--
-- הבעיה (נבדקה בחי ב-27.10.2026)
--   המדיניות "agents in same tenant" היא FOR ALL, ול-authenticated יש הרשאות INSERT, UPDATE ו-DELETE
--   על הטבלה, כולל UPDATE על העמודות role, is_active, auth_user_id ו-email. לכן כל משתמש בעסק יכול:
--   - לשנות את role של עצמו ל-owner, ולקבל גישה לפעולות של בעל העסק (הזמנת סוכנים, שינוי תחום ועוד)
--   - לשנות או למחוק שורות של משתמשים אחרים באותו עסק, כולל של בעל העסק
--   - להוסיף משתמשים לעסק בלי מגבלת המושבים של invite_agent
--   ההפרדה בין עסקים נשמרת (tenant_id = get_my_tenant_id() ב-USING וב-WITH CHECK).
--   נכון ל-27.10.2026 בכל עסק יש משתמש אחד (owner), ולכן אין היום מי שינצל את זה. זה הופך לרלוונטי
--   ברגע שעסק מצרף משתמש נוסף.
--
-- מה משתמש בטבלה (נבדק)
--   הדפדפן: SELECT של השורה של המשתמש, ו-UPDATE של name בשורה שלו (DB.updateAgentName). שאר הכתיבות
--   עוברות דרך פונקציות SECURITY DEFINER בבעלות postgres (ensure_agent_and_tenant,
--   register_demo_agent, invite_agent ועוד), ופונקציות Edge עם service_role. אף אחד מהם לא תלוי
--   בהרשאות של authenticated על הטבלה.
--
-- מה משתנה
--   - קריאה: כמו היום, משתמשים באותו עסק פעיל.
--   - עדכון: רק השורה של המשתמש עצמו, ורק name, phone ו-avatar_url.
--   - בלי INSERT, DELETE ו-TRUNCATE ישירים ל-anon ול-authenticated.

DROP POLICY IF EXISTS "agents in same tenant" ON public.agent_users;

CREATE POLICY agent_users_select_same_tenant ON public.agent_users
  FOR SELECT TO authenticated
  USING (tenant_id = public.get_my_tenant_id() AND public.tenant_access_active());

CREATE POLICY agent_users_update_own_row ON public.agent_users
  FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid() AND tenant_id = public.get_my_tenant_id() AND public.tenant_access_active())
  WITH CHECK (auth_user_id = auth.uid() AND tenant_id = public.get_my_tenant_id());

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.agent_users FROM PUBLIC, anon, authenticated;
REVOKE SELECT ON public.agent_users FROM anon;
GRANT SELECT ON public.agent_users TO authenticated;
GRANT UPDATE (name, phone, avatar_url) ON public.agent_users TO authenticated;

-- בדיקות אחרי הרצה (קריאה בלבד):
--   SELECT policyname, cmd, roles FROM pg_policies WHERE tablename = 'agent_users';
--   SELECT privilege_type FROM information_schema.role_table_grants
--    WHERE table_name = 'agent_users' AND grantee = 'authenticated';          -- SELECT בלבד
--   SELECT column_name FROM information_schema.column_privileges
--    WHERE table_name = 'agent_users' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';
--                                                                             -- name, phone, avatar_url
--   ואז באפליקציה: שינוי שם בהגדרות נשמר, הזמנת סוכן (חשבון עם מושבים) עובדת.
--
-- חזרה לאחור (מחזיר את המצב הקודם, כולל הבעיה):
--   DROP POLICY agent_users_select_same_tenant ON public.agent_users;
--   DROP POLICY agent_users_update_own_row ON public.agent_users;
--   CREATE POLICY "agents in same tenant" ON public.agent_users
--     USING (tenant_id = get_my_tenant_id() AND tenant_access_active())
--     WITH CHECK (tenant_id = get_my_tenant_id() AND tenant_access_active());
--   GRANT INSERT, UPDATE, DELETE ON public.agent_users TO authenticated;
