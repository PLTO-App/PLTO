-- 130: זיהוי מנהל PLTO לפי מזהה משתמש (auth.uid) במקום לפי אימייל
--
-- למה: 25 פונקציות זיהו מנהל לפי auth.email() IN ('info@plto.app','elgrablidudu@gmail.com').
-- אימות אימייל כבוי (mailer_autoconfirm), ולכן כתובת ברשימה שלא נרשמה הייתה פתוחה
-- להרשמה של כל אחד, עם גישת מנהל מלאה. ב-2.11.2026 נרשמה info@plto.app בידי הבעלים
-- כהקלה מיידית. המיגרציה הזו סוגרת את המנגנון עצמו: מזהה משתמש לא ניתן לתפוס בהרשמה.
--
-- שינוי התנהגות מכוון: הבדיקה הישנה `v_email NOT IN (...)` החזירה NULL כשאין אימייל,
-- ולכן לא חסמה. הבדיקה החדשה מחזירה תמיד true או false.
--
-- איך: הפונקציות לא מועתקות ידנית. לכל חתימה ברשימה הסגורה נקראת ההגדרה החיה,
-- מוחלפת רק שורת בדיקת המנהל, וההגדרה מורצת מחדש (CREATE OR REPLACE שומר הרשאות).
-- בסוף נבדק שאין פונקציה ב-public שעדיין מזהה מנהל לפי האימייל. כל כישלון מבטל הכול.

-- פונקציית העזר. SECURITY INVOKER: היא נקראת רק מתוך פונקציות SECURITY DEFINER
-- שבבעלות postgres, ולכן אין צורך לחשוף אותה ל-anon או ל-authenticated.
CREATE OR REPLACE FUNCTION public._is_plto_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT COALESCE(
    auth.uid() = ANY (ARRAY[
      '05d15a28-3ef6-4aaf-aa29-9c037cd0b555',  -- elgrablidudu@gmail.com (Google)
      '0d2f3e72-c693-4ee9-9fbc-fa132c1c264a'   -- info@plto.app (Google)
    ]::uuid[]),
    false
  );
$$;

REVOKE ALL ON FUNCTION public._is_plto_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._is_plto_admin() FROM anon, authenticated;

DO $mig$
DECLARE
  v_sigs constant text[] := ARRAY[
    'public.admin_archive_client_page(uuid)',
    'public.admin_delete_roadmap_item(uuid)',
    'public.admin_extend_trial(uuid,integer)',
    'public.admin_get_accounts()',
    'public.admin_get_invoices()',
    'public.admin_list_client_pages()',
    'public.admin_list_roadmap_items()',
    'public.admin_list_tenant_seats()',
    'public.admin_reply_support(uuid,text,text)',
    'public.admin_save_account(uuid,text,text,text)',
    'public.admin_save_invoice(uuid,uuid,numeric,text,text)',
    'public.admin_save_roadmap_item(uuid,text,text,text,text,boolean,integer)',
    'public.admin_set_billing_period(uuid,text)',
    'public.admin_set_plan(uuid,text,timestamp with time zone)',
    'public.admin_set_tenant_notes(uuid,text)',
    'public.admin_toggle_marketing_addon(uuid,boolean)',
    'public.check_and_increment_ai_usage(text)',
    'public.check_and_increment_lead_image_import()',
    'public.check_and_increment_page_copy()',
    'public.get_lead_image_import_quota()',
    'public.get_page_copy_quota()',
    'public.get_saas_tenants_admin()',
    'public.get_support_tickets_admin()',
    'public.list_referral_conversion_rewards()',
    'public.tenant_access_active()'
  ];
  -- הרשימה שהופיעה בכל הפונקציות, עם רווח אחרי הפסיק או בלעדיו
  v_list constant text := '\(''info@plto\.app'', ?''elgrablidudu@gmail\.com''\)';
  v_sig  text;
  v_old  text;
  v_new  text;
  v_left int;
BEGIN
  FOREACH v_sig IN ARRAY v_sigs LOOP
    v_old := pg_get_functiondef(v_sig::regprocedure);
    v_new := v_old;
    -- סדר ההחלפות חשוב: קודם NOT IN, ואחר כך IN
    v_new := regexp_replace(v_new, '\m(v_email|v_caller) NOT IN ' || v_list, 'NOT public._is_plto_admin()', 'g');
    v_new := regexp_replace(v_new, '\mv_email IN ' || v_list, 'public._is_plto_admin()', 'g');
    v_new := regexp_replace(v_new, '\mauth\.email\(\) IN ' || v_list, 'public._is_plto_admin()', 'g');

    IF v_new = v_old THEN
      RAISE EXCEPTION '130: no admin check replaced in %', v_sig;
    END IF;
    IF v_new ~ 'info@plto\.app|elgrablidudu@gmail\.com' THEN
      RAISE EXCEPTION '130: admin email still present in % after rewrite', v_sig;
    END IF;

    EXECUTE v_new;
  END LOOP;

  -- אף פונקציה ב-public לא מזהה עוד מנהל לפי רשימת האימיילים.
  -- בודקים את תבנית ההשוואה ולא כל אזכור: _notify_owner_email משתמשת בכתובת כנמען
  -- של התראות הבעלים, וזה שימוש לגיטימי שלא נוגעים בו.
  SELECT count(*) INTO v_left
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
    AND pg_get_functiondef(p.oid) ~ ('IN ' || v_list);
  IF v_left > 0 THEN
    RAISE EXCEPTION '130: % function(s) in public still reference an admin email', v_left;
  END IF;
END
$mig$;
