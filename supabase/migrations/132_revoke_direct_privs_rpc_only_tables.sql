-- 132: ביטול הרשאות טבלה ישירות של anon ו-authenticated על טבלאות שנגישות רק דרך RPC.
--
-- בטבלאות האלה RLS פעיל ואין אף מדיניות, ולכן כבר היום אין גישה ישירה דרך REST, וכל השימוש
-- עובר בפונקציות SECURITY DEFINER או בפונקציות Edge עם מפתח שירות. ההרשאות הרחבות שנשארו
-- (SELECT, INSERT, UPDATE, DELETE, TRUNCATE ועוד, ברירת המחדל של Supabase לטבלאות חדשות) הן
-- שכבת הגנה חסרה: מדיניות שתתווסף בטעות בעתיד, למשל USING (true), הייתה חושפת אותן מיד.
--
-- השינוי לא משנה התנהגות: פונקציות SECURITY DEFINER רצות בהרשאות הבעלים, ומפתח השירות לא מושפע.
-- לפני הביטול כל טבלה נבדקת: קיימת, RLS פעיל ואין לה מדיניות. אם אחד התנאים לא מתקיים
-- המיגרציה נכשלת בלי לשנות דבר.
--
-- ביטול: GRANT ALL ON TABLE public.<table> TO anon, authenticated;
--
-- לשים לב בהמשך: אם תתווסף בכוונה מדיניות RLS לאחת הטבלאות, צריך גם GRANT מפורש לתפקיד המתאים.
-- טבלה שנמחקת ונוצרת מחדש מקבלת שוב את הרשאות ברירת המחדל של Supabase. REVOKE על טבלה לא חל על
-- sequences (לטבלאות האלה אין כרגע sequence בבעלותן).

DO $mig$
DECLARE
  v_tables constant text[] := ARRAY[
    'client_consents',
    'client_pages',
    'cro_ab_tests',
    'funnel_events',
    'gmail_tokens',
    'lead_image_import_usage',
    'lead_referrals',
    'lead_tracker_updates',
    'market_board_posts',
    'opportunity_applications',
    'page_copy_usage',
    'partner_opportunities',
    'referral_agreements',
    'referral_claims',
    'referral_conversion_rewards',
    'roadmap_item_votes'
  ];
  t text;
  v_oid oid;
BEGIN
  -- קודם בודקים את כולן, ורק אחר כך משנים, כדי שכישלון לא ישאיר מצב חלקי
  FOREACH t IN ARRAY v_tables LOOP
    SELECT c.oid INTO v_oid
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = t AND c.relkind = 'r';
    IF v_oid IS NULL THEN
      RAISE EXCEPTION '132: table public.% not found', t;
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = v_oid) THEN
      RAISE EXCEPTION '132: RLS is not enabled on public.%', t;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = v_oid) THEN
      RAISE EXCEPTION '132: public.% has RLS policies, so it is not RPC-only', t;
    END IF;
  END LOOP;

  FOREACH t IN ARRAY v_tables LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', t);
  END LOOP;
END
$mig$;
