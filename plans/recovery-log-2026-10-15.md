# יומן שיקום, 15.10.2026

תיעוד קצר של מה שבוצע ומה נבדק. בלי מפתחות, כתובות webhook או מידע אישי.

## בוצע

- מיגרציה 121 (מחיקת `reorder_stops` שנוספה בטעות, והסרת הרשאות מיותרות מ-`_notify_owner_new_tenant`): הורצה ואומתה, ונרשמה ב-`schema_migrations`.
- מיגרציה 122: הדיג'סט היומי שולח ספירות בלבד דרך Resend. נבדקה קודם בטרנזקציה שנכשלה בכוונה (rollback מלא) עם לידים מלאכותיים, ולא דלפו שם או טלפון.
- `notify-owner` נפרסה ומוזגה (PR #155). האתר החי כבר לא פונה ל-Make בנתיב התראות הבעלים.
- מיגרציות 123 ו-124 (PR #156): תיעוד רטרואקטיבי של שתי מיגרציות שרצו בחי בלי קובץ. ה-SQL זהה למה שרץ. אין להריץ אותן על הפרויקט החי.
- PR #150 נסגר בלי מיזוג.
- Meta Pixel (PR #157): הפיקסל הפיקטיבי כובה, והטעינה מותנית במזהה אמיתי. פייסבוק הוסר מה-CSP של דף הנחיתה.

## נבדק ותקין

- הפונקציה החיה `send_daily_lead_digest()` הייתה זהה למיגרציה 111 לפני השינוי.
- ההרשאות על `send_daily_lead_digest()` ועל `_notify_owner_new_tenant()`: `postgres` ו-`service_role` בלבד.
- מסלול Resend: מייל בדיקה הגיע לתיבה.
- מיגרציות 120 עד 124 עקביות מול `schema_migrations` החי.
- 8 דפי האתר נטענים ב-390px בלי גלישה אופקית ובלי בקשות עם `${...}` (בדיקה עם stubs).
- Supabase advisors (אבטחה): אין ממצאי ERROR. 16 טבלאות עם RLS בלי policies הן RPC בלבד בכוונה. 15 פונקציות פתוחות ל-`anon` הן RPC של דפים ציבוריים לפי token או slug. 99 פונקציות פתוחות ל-`authenticated` הן ה-RPC של האפליקציה.
- Supabase advisors (ביצועים): INFO בלבד (אינדקסים שלא נוצלו וארבעה מפתחות זרים בלי אינדקס בטבלאות קטנות). לא נדרשת פעולה בנפח הנוכחי.

## פתוח (מצב 15.10, העדכון העדכני בסוף המסמך)

- בדיקת 200 ו-403 על `notify-owner` החיה (דורשת משתמש מחובר; 403 דורש משתמש שאינו אדמין).
- ניתוק ה-hook והתרחיש הראשי ב-Make וניקוי `tenants.make_webhook_url`, אחרי שהתראה אמיתית הגיעה.
- הגנת סיסמאות דולפות (`auth_leaked_password_protection`) כבויה. מופעלת בהגדרות Auth בדשבורד (בתוכנית שתומכת בכך).
- מחיקת מפתחות Supabase `default` ו-`make_trial_expiry` אחרי בדיקת "Last used" ורשימת סודות ב-Edge Functions.
- הפונקציות הפרוסות `admin-ops` ו-`temp-selftest` (מחזירות 410) ו-`cro-report-email` (תשתיתה הוסרה במיגרציה 088) אינן בריפו. אין כלי מחיקה זמין מהסשן.
- מזהה Meta Pixel אמיתי, ואם יתווסף: עדכון CSP ובדיקת מדיניות הפרטיות.
- מיגרציות 118 ו-119 של הריפו קיימות במסד החי, אבל לא רשומות ב-`schema_migrations` בשמותיהן.
- ערכי UTM בהרשמה נשמרים בלי מגבלת אורך. הסיכון נמוך, כי אף מסך לא מציג אותם.

## 16.10.2026: בדיקת זרימות מול ה-DB החי

נבדק עם חשבון בדיקה ייעודי שאינו אדמין (בעל עסק רגיל, ללא מיילים ללקוחות ובלי חיובים). נוצר ישירות ב-DB, והעסק נוצר דרך `ensure_agent_and_tenant` האמיתית כשה-trigger של מייל הבעלים מושבת רק לאותה פעולה. החשבון נחסם (`banned_until`) והסיסמה לא נשמרה. **נשאר למחוק ידנית:** עסק "QA-TEST (בדיקה, למחיקה)" והמשתמש `qa-nonadmin-20261016@example.org` (מחיקה דורשת אישור ידני בכלי).

**עבר (35 בדיקות API ו-14 מסכים בדפדפן):**
- בידוד בין עסקים: קריאה ושינוי של נתוני עסק אחר נחסמים, ושינוי תוכנית או סיום ניסיון של עסק עצמו חסום.
- לידים, שלבי פייפליין, פעילויות ומשימות (יצירה, שינוי שלב, סיום משימה). שם ליד עם HTML נשמר כטקסט ומוצג בטקסט.
- הפניות: עמלה נדחית (`commission_not_allowed`), הפניה לעצמך נדחית, תצוגה מקדימה אנונימית בלי מזהי עסק או אימיילים, הסכמת לקוח (פעם אחת בלבד).
- מעקב ליד ודפי לקוח: תצוגה ציבורית בלי טלפון, תקציב או מזהה ליד. קישורים לא תקינים מחזירים תשובה תקינה.
- RPC של אדמין: כולן דורשות אדמין (נבדקו ברמת הקוד, והקריאות לקריאה בלבד נדחו).
- `notify-owner` החיה: 403 לאירוע אדמין ממשתמש רגיל, 400 לאירוע לא מוכר ולשדה חובה חסר.
- 14 מסכי האפליקציה נטענים אחרי התחברות במובייל (390px) בלי שגיאות JS, בלי בקשות שנכשלו ובלי גלישה אופקית.

**נמצא ותוקן:**
- שם העסק נכנס כ-HTML גולמי למיילי "נרשם עסק חדש" ו"עסק פעיל 14 יום". מיגרציה 125 הוסיפה `_html_escape` ושימוש בה בשני המיילים.
- חלון הגנת ה-PIN נפתח מתחת לסיור המודרך. עכשיו הוא ממתין לסיום הסיור.
- אזורי לחיצה קטנים מ-44px במסך הכניסה, באדמין ובדף הנחיתה (PR #159).

**לא תוקן:**
- ימי הניסיון: ההרשמה נותנת 30, ברירת המחדל בעמודה ו-`admin_save_account` על 21. אין השפעה על משתמשים.
- ההגנה על סיסמאות דולפות זמינה רק בתוכנית Pro של Supabase.

## מצב ומשימות שנותרו (16.10)

### ניקוי חשבון הבדיקה (ממתין לאישור ידני)
כלי ה-SQL של הסשן דורש אישור ידני לכל DELETE, ולכן המחיקה לא בוצעה. מה שנבדק לפני כן:
- מחיקת העסק מוחקת אוטומטית (CASCADE) את הלידים, המשימות, הפעילויות, השלבים, ההפניות, ההסכמות, דפי הלקוח, עדכוני המעקב והמשתמשים. מחיקת משתמש ה-auth מוחקת את הזהויות, ה-sessions וה-refresh tokens.
- `audit_log` אינה מקושרת בהפניה זרה (10 שורות של הבדיקה), ולכן היא נמחקת במפורש.
- אין trigger או rule שחוסמים מחיקה בטבלאות האלה.
- הסקריפט נבדק בתחביר עם מפרק Postgres, כולל גוף ה-plpgsql. הוא עוצר אם המזהים אינם של עסק ומשתמש הבדיקה, ואם נשארה שורה אחת אחריו הוא מבטל הכול.

להרצה ב-SQL Editor של פרויקט PLTO (פקודה אחת, אטומית):

```sql
DO $cleanup$
DECLARE
  v_tid uuid := '20dd3198-d5a3-4460-b942-6170d86acd9a';
  v_uid uuid := '72819a42-6805-4ba0-b7ae-8f269b7eabc9';
  r record;
  n int;
BEGIN
  -- Guards: stop unless these are exactly the QA test tenant and user.
  IF NOT EXISTS (SELECT 1 FROM tenants WHERE id = v_tid AND billing_email = 'qa-nonadmin-20261016@example.org' AND name LIKE 'QA-TEST%') THEN
    RAISE EXCEPTION 'tenant does not match the QA test tenant, nothing deleted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_uid AND email = 'qa-nonadmin-20261016@example.org') THEN
    RAISE EXCEPTION 'user does not match the QA test user, nothing deleted';
  END IF;

  DELETE FROM audit_log WHERE tenant_id = v_tid;   -- no foreign key, so it is not cascaded
  DELETE FROM tenants   WHERE id = v_tid;          -- cascades to leads, tasks, activities, stages, referrals, consents, pages, tracker, agent_users
  DELETE FROM auth.users WHERE id = v_uid;         -- cascades to identities, sessions, refresh tokens

  -- Post-conditions: any leftover rolls everything back.
  FOR r IN
    SELECT c.table_name FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = $1', r.table_name) INTO n USING v_tid;
    IF n > 0 THEN RAISE EXCEPTION 'leftover rows in %: %', r.table_name, n; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM tenants WHERE id = v_tid)
     OR EXISTS (SELECT 1 FROM auth.users WHERE id = v_uid)
     OR EXISTS (SELECT 1 FROM auth.identities WHERE user_id = v_uid)
     OR EXISTS (SELECT 1 FROM lead_referrals WHERE from_tenant_id = v_tid)
     OR EXISTS (SELECT 1 FROM leads WHERE name IN ('QA ליד בדיקה', '<img src=x onerror=alert(1)>')) THEN
    RAISE EXCEPTION 'leftovers remain, rolled back';
  END IF;
END
$cleanup$;
```

אחרי ההרצה נשאר לאמת: 0 עסקים ו-0 משתמשים עם `qa-nonadmin`, ו-4 עסקים בסך הכל.

### מחיקת שלוש פונקציות Edge ישנות (דשבורד)
`admin-ops`, `temp-selftest`, `cro-report-email`. אין להן שימוש פעיל:
- אין אזכור שלהן בקוד האתר, ב-workflows או ב-Edge Functions בריפו (רק בהערות של מיגרציות 086 ו-088 ההיסטוריות).
- ב-DB היחידה ששולחת בקשות החוצה היא `_notify_owner_email` (ל-Resend). אין database webhooks, ויש רק שתי משימות cron.
- `admin-ops` ו-`temp-selftest` מחזירות 410 לכל בקשה. `cro-report-email` דורשת סוד שנבדק מול הפונקציה `verify_cron_report_secret`, והיא לא קיימת ואין סוד כזה ב-Vault, ולכן כל קריאה נדחית.
- לא נבדק: קריאות חיצוניות היסטוריות. לוגי הפונקציות אינם נגישים מהסשן.

צעדים: Supabase, פרויקט PLTO, Edge Functions. לכל אחת מהשלוש: לפתוח אותה, לבדוק בלשונית Invocations שאין קריאות בשבוע האחרון (בדיקה אופציונלית), ואז Details או Settings ולחיצה על Delete function. אחרי המחיקה נשארות ברשימה `ai-proxy`, `gmail-oauth-callback`, `gmail-proxy`, `notify-owner`, `stripe-webhook` ו-`twilio-whatsapp`.

### נשאר פתוח
- אישור שמייל "הצעת רעיון חדשה" מהטלפון הגיע. רק אחריו מנתקים את ה-hook ואת התרחיש ב-Make (בלי מחיקת התרחיש, כדי לאפשר חזרה).
- מחיקת מפתחות Supabase `default` ו-`make_trial_expiry`: דורשת בדיקת "Last used" ורשימת סודות ב-Edge Functions בדשבורד.
- מזהה Meta Pixel אמיתי, ואם יתווסף: עדכון CSP ובדיקת מדיניות הפרטיות.
- הגנת סיסמאות דולפות: דורשת תוכנית Pro של Supabase.
- מיגרציות 118 ו-119 של הריפו אינן רשומות ב-`schema_migrations` בשמותיהן (האובייקטים קיימים בחי).
