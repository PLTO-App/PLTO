-- חזרה לאחור של מיגרציה 129. מחזיר את שתי הפונקציות להגדרה שהייתה בחי ב-28.10.2026
-- (נשלפה עם pg_get_functiondef), ואז מוחק את free_growth_period().
-- שימו לב: אחרי ההרצה עסק בתוכנית trial שהניסיון שלו פג ננעל שוב, ב-RLS ובדפים הציבוריים.
-- לפני כן יש להחזיר את Billing.FREE_GROWTH = false בקוד, אחרת המשתמש יראה שגיאת טעינה במקום מסך תשלום.
-- לא משנה נתונים. הקובץ הזה אינו בתיקיית migrations, ולכן לא יורץ אוטומטית.

CREATE OR REPLACE FUNCTION public.tenant_access_active()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN auth.email() IN ('info@plto.app', 'elgrablidudu@gmail.com') THEN true
    WHEN t.plan = 'cancelled' THEN false
    WHEN t.plan = 'trial'     THEN (t.trial_ends_at IS NULL OR now() <= t.trial_ends_at)
    ELSE true
  END
  FROM tenants t WHERE t.id = get_my_tenant_id();
$function$;

CREATE OR REPLACE FUNCTION public.public_page_tenant_active(p_tenant_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN t.id IS NULL THEN false
    WHEN t.plan = 'cancelled' THEN false
    WHEN t.plan = 'trial' THEN (t.trial_ends_at IS NULL OR now() <= t.trial_ends_at)
    ELSE true
  END
  FROM (SELECT 1) x
  LEFT JOIN tenants t ON t.id = p_tenant_id;
$function$;

DROP FUNCTION IF EXISTS public.free_growth_period();
