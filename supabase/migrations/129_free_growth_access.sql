-- Migration 129 (טיוטה, לא הורצה): גישה חינמית בלי הגבלת זמן בתקופת הצמיחה.
--
-- רקע
--   החלטת דוד (27.10.2026): PLTO Sales חינמית בלי הגבלת זמן בתקופת הצמיחה, בלי מחירים
--   ובלי מסכי תשלום. עד היום עסק בתוכנית trial ננעל בתום trial_ends_at בשני מקומות בשרת:
--   - tenant_access_active() משמשת במדיניות ה-RLS של הטבלאות העסקיות (לידים, משימות,
--     שלבים, פעילויות, נכסים ועוד). אחרי תום הניסיון המשתמש לא יכול לקרוא או לכתוב.
--   - public_page_tenant_active() סוגרת את הדפים הציבוריים (דף לקוח, תיק עבודות, מעקב).
--   ההסתרה בדפדפן לבדה לא מספיקה: משתמש שהניסיון שלו פג יקבל שגיאת טעינה במקום מסך תשלום.
--
-- מה משתנה
--   מתג אחד בשרת, free_growth_period(), שמחזיר true. כשהוא true עסק בתוכנית trial נחשב
--   פעיל גם אחרי trial_ends_at. העמודה trial_ends_at לא משתנה, כך שחזרה למודל ניסיון
--   בעתיד היא שינוי של פונקציה אחת, בלי לחשב מחדש נתונים.
--   לא משתנה: עסק בתוכנית cancelled נשאר חסום, עקיפת האדמין נשארת כמו בחי, תוכניות בתשלום.
--
-- סדר פריסה
--   להריץ את המיגרציה לפני מיזוג קוד הדפדפן שמכבה את מסך התשלום (Billing.FREE_GROWTH).
--   אחרת משתמש שהניסיון שלו פג ייכנס לאפליקציה ויקבל שגיאת טעינה מה-RLS.
--
-- הגדרות הבסיס הועתקו מהפונקציות החיות (pg_get_functiondef, 27.10.2026).

CREATE OR REPLACE FUNCTION public.free_growth_period()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  -- להחזרת מודל הניסיון: להחליף ל-false (ולעדכן את Billing.FREE_GROWTH בדפדפן)
  SELECT true;
$$;

-- נקראת רק מתוך פונקציות SECURITY DEFINER, ולכן אין צורך בהרשאת הרצה לתפקידי הלקוח
REVOKE ALL ON FUNCTION public.free_growth_period() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tenant_access_active()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN auth.email() IN ('info@plto.app', 'elgrablidudu@gmail.com') THEN true
    WHEN t.plan = 'cancelled' THEN false
    WHEN t.plan = 'trial'     THEN (public.free_growth_period() OR t.trial_ends_at IS NULL OR now() <= t.trial_ends_at)
    ELSE true
  END
  FROM tenants t WHERE t.id = get_my_tenant_id();
$$;

CREATE OR REPLACE FUNCTION public.public_page_tenant_active(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN t.id IS NULL THEN false
    WHEN t.plan = 'cancelled' THEN false
    WHEN t.plan = 'trial' THEN (public.free_growth_period() OR t.trial_ends_at IS NULL OR now() <= t.trial_ends_at)
    ELSE true
  END
  FROM (SELECT 1) x
  LEFT JOIN tenants t ON t.id = p_tenant_id;
$$;

-- CREATE OR REPLACE שומר את ההרשאות הקיימות של שתי הפונקציות (נבדק בחי):
--   tenant_access_active: authenticated, service_role
--   public_page_tenant_active: anon, authenticated, service_role

-- בדיקה אחרי הרצה (קריאה בלבד):
--   SELECT public.free_growth_period();                                  -- true
--   SELECT id, public.public_page_tenant_active(id) FROM tenants;         -- trial שפג: true
--
-- חזרה לאחור: להריץ את שתי ההגדרות בלי free_growth_period() (כמו ב-043 וב-102), ואז
--   DROP FUNCTION public.free_growth_period();
