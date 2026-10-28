-- חזרה לאחור של מיגרציה 131. מחזיר את המצב שהיה בחי ב-28.10.2026, כולל הבעיה שהמיגרציה סגרה:
-- כל משתמש בעסק יכול לשנות role, is_active ו-auth_user_id, ולהוסיף או למחוק משתמשים באותו עסק.
-- לא משנה נתונים. מריצים רק אם 131 גרמה לתקלה באפליקציה, ואחרי שמתעדים מה נכשל.
-- הקובץ הזה אינו בתיקיית migrations, ולכן לא יורץ אוטומטית.

DROP POLICY IF EXISTS agent_users_select_same_tenant ON public.agent_users;
DROP POLICY IF EXISTS agent_users_update_own_row ON public.agent_users;

CREATE POLICY "agents in same tenant" ON public.agent_users
  USING (tenant_id = public.get_my_tenant_id() AND public.tenant_access_active())
  WITH CHECK (tenant_id = public.get_my_tenant_id() AND public.tenant_access_active());

-- הרשאות עמודה שנוספו ב-131 מוסרות לפני שחזור ההרשאה ברמת הטבלה
REVOKE UPDATE (name, phone, avatar_url) ON public.agent_users FROM authenticated;
GRANT ALL ON TABLE public.agent_users TO authenticated;  -- לפני: authenticated=arwdDxtm
