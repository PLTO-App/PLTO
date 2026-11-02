-- Migration 129: הקשחת track_funnel_event
--
-- הפונקציה פתוחה ל-anon (נדרש: ה-landing שולח אירועים בלי התחברות), ולכן כל
-- קלט שלה הוא לא אמין. בדיקת הגרסה החיה (זהה ל-067) העלתה:
--   1. p_tenant_id מגיע מהלקוח ונכתב כמו שהוא. כל מבקר יכול לשייך אירועים
--      ל-tenant אחר, או לכתוב UUID שלא קיים בכלל (אין FK בטבלה).
--   2. אין הגבלת אורך על p_session_id ואין הגבלת גודל על p_event_data, כך
--      שקריאה אנונימית אחת יכולה לנפח את הטבלה.
--   3. p_event_name או p_session_id ריקים (NULL) זורקים חריגה במקום להיפסל
--      בשקט, בניגוד להתנהגות הכללית של הפונקציה ("fire-and-forget").
--
-- התיקון:
--   * tenant_id נגזר בשרת מ-get_my_tenant_id() (תלוי ב-auth.uid()), ולכן
--     אנונימי מקבל NULL ומשתמש מחובר מקבל רק את ה-tenant שלו. הפרמטר
--     p_tenant_id נשאר בחתימה לתאימות לאחור (index.html עדיין שולח אותו)
--     אבל מתעלמים ממנו.
--   * p_session_id חייב להיות באורך 8..64 תווים.
--   * p_event_data חייב להיות אובייקט JSON עד 2000 תווים, אחרת האירוע נפסל.
--   * קלט לא תקין נפסל בשקט (RETURN), כמו בבדיקת שם האירוע הקיימת.
--
-- לא משתנה: חתימה, שם, טיפוס החזרה, GRANTs (anon + authenticated), regex
-- של שמות האירועים. אין שינוי בטבלה ואין שינוי ב-RLS (נשארת בלי policies,
-- ראו מיגרציה 095).

CREATE OR REPLACE FUNCTION public.track_funnel_event(
  p_session_id TEXT,
  p_event_name TEXT,
  p_event_data JSONB DEFAULT '{}'::jsonb,
  p_tenant_id  UUID  DEFAULT NULL  -- deprecated: מתעלמים מהערך מהלקוח
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data JSONB := COALESCE(p_event_data, '{}'::jsonb);
BEGIN
  IF p_event_name IS NULL OR length(p_event_name) > 80 OR p_event_name !~ '^[a-z_]+$' THEN
    RETURN;
  END IF;

  IF p_session_id IS NULL OR length(p_session_id) NOT BETWEEN 8 AND 64 THEN
    RETURN;
  END IF;

  IF jsonb_typeof(v_data) <> 'object' OR length(v_data::text) > 2000 THEN
    RETURN;
  END IF;

  INSERT INTO funnel_events (session_id, tenant_id, event_name, event_data)
  VALUES (p_session_id, get_my_tenant_id(), p_event_name, v_data);
END;
$$;

-- CREATE OR REPLACE שומר על ה-ACL הקיים, אבל מצהירים במפורש כדי שהמיגרציה
-- תהיה עצמאית (anon חייב לשמור הרשאה, ה-landing שולח בלי התחברות).
GRANT EXECUTE ON FUNCTION public.track_funnel_event(TEXT, TEXT, JSONB, UUID) TO anon, authenticated;
