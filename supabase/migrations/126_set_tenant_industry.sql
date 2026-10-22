-- Migration 126 (טיוטה, לא הורצה): שמירת תחום העסק וסימון סיום ההצטרפות דרך RPC צר.
--
-- רקע
--   ל-authenticated אין מדיניות UPDATE על tenants, ולכן העדכון הישיר שהאפליקציה מבצעת
--   (DB.updateIndustry) מעדכן 0 שורות בלי שגיאה, והתחום נשאר רק ב-localStorage.
--   אסור לפתור זאת במדיניות UPDATE: ל-authenticated יש הרשאת UPDATE על כל העמודות של
--   tenants, כולל plan, trial_ends_at, marketing_addon ו-stripe_*, ומדיניות רחבה הייתה
--   מאפשרת לבעל עסק לשנות לעצמו את התוכנית.
--
-- למה צריך מגבלה על יציאה מ-realestate_lawyer
--   tenants.industry משמש בשרת כתנאי הרשאה: חסימת עמלת הפניה לעו"ד (111), הסתרת ויטרינה
--   של עו"ד כי היא חושפת תיקים (114), ולוח ההתאמות שפתוח רק לנדל"ן (123). כל עוד לא היה
--   אפשר לשנות את התחום מהאפליקציה, הערך הזה היה קבוע. אחרי המיגרציה אפשר לשנות אותו,
--   ולכן עו"ד שכבר יש לו נתונים לא יכול לצאת מהתחום דרך הפונקציה הזו. שינוי כזה נעשה
--   בידי מנהל המערכת בלבד.
--
-- שדות שהפונקציה נוגעת בהם: industry ו-onboarding_completed בלבד, ובעסק של המשתמש עצמו.
-- אין פרמטר שמציין עסק, ולכן אי אפשר לשנות עסק אחר.

CREATE OR REPLACE FUNCTION public.set_tenant_industry(
  p_industry            text,
  p_complete_onboarding boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_tenant_id uuid;
  v_role      text;
  v_old       text;
  v_result    jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT tenant_id, role INTO v_tenant_id, v_role
    FROM agent_users WHERE auth_user_id = v_uid LIMIT 1;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'no tenant for current user';
  END IF;
  IF v_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'insufficient permissions' USING ERRCODE = '42501';
  END IF;

  -- אותה רשימה כמו tenants_industry_check
  IF p_industry IS NULL OR p_industry NOT IN ('realestate', 'realestate_lawyer', 'interior', 'other') THEN
    RAISE EXCEPTION 'invalid_industry' USING ERRCODE = '22023';
  END IF;

  SELECT industry INTO v_old FROM tenants WHERE id = v_tenant_id FOR UPDATE;

  -- עו"ד עם נתונים לא יוצא מהתחום דרך הפונקציה (ראו הרקע למעלה)
  IF v_old = 'realestate_lawyer' AND p_industry <> 'realestate_lawyer'
     AND (EXISTS (SELECT 1 FROM leads      WHERE tenant_id = v_tenant_id)
       OR EXISTS (SELECT 1 FROM properties WHERE tenant_id = v_tenant_id)) THEN
    RAISE EXCEPTION 'industry_change_locked'
      USING ERRCODE = '42501', HINT = 'contact support to change a legal-practice account';
  END IF;

  UPDATE tenants
     SET industry = p_industry,
         -- רק מ-false ל-true. הפונקציה לא מחזירה עסק לאשף
         onboarding_completed = onboarding_completed OR coalesce(p_complete_onboarding, false)
   WHERE id = v_tenant_id
  RETURNING jsonb_build_object('industry', industry, 'onboarding_completed', onboarding_completed)
    INTO v_result;

  RETURN v_result;
END;
$$;

-- ברירת המחדל ב-Supabase נותנת EXECUTE גם ל-anon ול-authenticated באופן מפורש,
-- ולכן נדרש REVOKE מפורש, ולא רק מ-PUBLIC.
REVOKE ALL ON FUNCTION public.set_tenant_industry(text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_tenant_industry(text, boolean) TO authenticated;

-- חזרה לאחור:
--   DROP FUNCTION public.set_tenant_industry(text, boolean);
