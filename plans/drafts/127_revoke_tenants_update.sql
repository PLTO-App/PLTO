-- Migration 127 (טיוטה, לא הורצה): הסרת הרשאת UPDATE על tenants מ-authenticated.
--
-- בדיקת מסלולי העדכון (22.10.2026, מול ה-DB החי ומול הריפו):
--   * כל 12 הפונקציות שמעדכנות tenants הן SECURITY DEFINER בבעלות postgres, ולכן לא תלויות
--     בהרשאות של authenticated: update_tenant_profile, update_tenant_integrations,
--     get_referral_code, admin_save_account, admin_set_plan, admin_extend_trial,
--     admin_set_billing_period, admin_set_tenant_notes, admin_toggle_marketing_addon,
--     check_and_notify_trial14, _process_referral_conversion_reward, _referral_conversion_trigger.
--   * אין פונקציית SECURITY INVOKER שנוגעת ב-tenants.
--   * הטריגרים על tenants: referral_conversion_reward_trg ו-trg_notify_owner_new_tenant הם
--     SECURITY DEFINER, ו-update_updated_at_column לא ניגש לטבלה בהרשאות.
--   * פונקציות Edge ו-GitHub Actions משתמשות ב-service_role, שלא מושפע.
--   * בצד הלקוח: העדכון הישיר היחיד הוא DB.updateIndustry, והוא עובר ל-set_tenant_industry (126).
--     admin.html ו-index.html משתמשים ב-RPC בלבד.
--   * המענק מ-029 (GRANT UPDATE (onboarding_completed)) מעולם לא עבד בלי מדיניות UPDATE.
--
-- הערה: ב-PostgreSQL ביטול הרשאה ברמת הטבלה מבטל גם הרשאות ברמת עמודה (ראו GRANT בתיעוד),
-- ולכן פקודה אחת מספיקה. הבדיקה המקומית מאמתת זאת.
--
-- ההשפעה בפועל: היום ה-RLS כבר חוסם כל עדכון. אחרי הפקודה עדכון ישיר ייכשל בשגיאת הרשאה
-- (42501) במקום להחזיר 0 שורות בשקט. לכן יש להפעיל אותה רק אחרי שהאפליקציה עברה ל-126.

REVOKE UPDATE ON TABLE public.tenants FROM authenticated;

-- חזרה לאחור:
--   GRANT UPDATE ON TABLE public.tenants TO authenticated;
