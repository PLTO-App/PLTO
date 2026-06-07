# Supabase Security — Liders CRM

## פקודה: `/supabase-security`

RLS policies, auth, secrets ו-audit — מול הסכימה **האמיתית** של Liders
(`scyfywvzoogfrlalgftv`, eu-central-1).

> ⚠️ גרסה קודמת של הסקיל הזה הייתה מועתקת מפרויקט אחר (`bookings`/`clients`/PIN auth).
> הגרסה הזו נכתבה מחדש מול המיגרציות והקוד האמיתיים (001–010).

---

## ארכיטקטורת בידוד (Multi-Tenant Isolation)

כל טבלה tenant-scoped מבודדת באמצעות helper function אחד — `get_my_tenant_id()` —
שמחזיר את ה-`tenant_id` של המשתמש המחובר (`auth.uid()`).

### תבנית ה-RLS הסטנדרטית בפרויקט (העתק לכל טבלה חדשה — ראה 004_leads.sql)
```sql
ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant isolation" ON <table>
  FOR ALL
  USING       (tenant_id = get_my_tenant_id())
  WITH CHECK  (tenant_id = get_my_tenant_id());
```

### "המבחן הדו-טננטי" — חובה אחרי כל migration חדשה
```
1. התחבר כסוכן מ-tenant A → ודא שאתה רואה רק את הנתונים שלו
2. התחבר כסוכן מ-tenant B → ודא 0 חפיפה עם A
3. נסה query ישיר על הטבלה החדשה בלי get_my_tenant_id() → ודא ש-RLS חוסם
```

---

## טבלאות המערכת — מצב RLS נוכחי (מ-migrations 001–009)

| טבלה | RLS | Policy | מקור |
|------|-----|--------|------|
| `tenants` | ✅ | כתיבה — `service_role` בלבד | 001 |
| `agent_users` | ✅ | tenant isolation | 002 |
| `pipeline_stages` | ✅ | tenant isolation | 003 |
| `leads` | ✅ | tenant isolation | 004 |
| `properties` | ✅ | tenant isolation | 005 |
| `tasks` | ✅ | tenant isolation | 006 |
| `showings` | ✅ | tenant isolation | 007 |
| `activities` | ✅ | tenant isolation | 008 |
| `audit_log` | ✅ | `service_role` בלבד, append-only | 009 |

**שים לב — views/materialized views משותפים** (`lead_score_summary`, `pipeline_summary`,
`overdue_tasks` מ-009): הם מחזיקים `tenant_id` כעמודה, אך views לא יורשים RLS אוטומטית
מהטבלאות הבסיס באותה צורה — ודא שה-query בצד הלקוח **תמיד** מסנן לפי `get_my_tenant_id()`,
ושאין דרך לבקש את ה-view בלי הסינון הזה.

> טבלה חדשה בלי RLS + tenant isolation = לא עובר code review (כלל #5 ב-CLAUDE.md, ללא יוצא מן הכלל).

---

## Auth — איך זה עובד בפועל

Liders משתמש ב-**Supabase Auth (email + password, auto-signup)** — אין PIN, אין custom auth:

```js
// register_demo_agent() — SECURITY DEFINER fn (מיגרציה 010)
// פותר bootstrap problem: יוצר tenant + agent_user בעסקה אחת,
// בלי לחשוף ל-client את היכולת לעקוף RLS ישירות
await sbClient.auth.signInWithPassword({ email, password });
// signUp אוטומטי בכניסה ראשונה אם המשתמש לא קיים
```

**נקודות לבדיקה (Auth):**
```
□ register_demo_agent() — ודא שהיא ניתנת לקריאה רק ע"י authenticated, לא anon
□ Email confirmation: כבוי בדמו הפנימי בלבד! ללקוחות אמיתיים — חובה דלוק (CLAUDE.md מדגיש)
□ session timeout / refresh-token rotation — ברירת המחדל של Supabase; לא לגעת בלי סיבה טובה
□ מה קורה ב-double-signup עם אותו email משני דפדפנים? race condition אפשרי?
```

---

## 🔴 Secrets שזוהו חשופים בצד ה-Client (ב-localStorage)

| מפתח ב-localStorage | מודול | חומרה | פירוט |
|---------------------|-------|-------|-------|
| `claude_api_key` | `AI` | 🔴 קריטי | מפתח Anthropic מלא, נשלח ישירות מהדפדפן ל-`api.anthropic.com` עם `anthropic-dangerous-direct-browser-access: true` |
| `make_webhook_url` | `Make` | 🟡 בינוני | לא secret כשלעצמו, אך חושף תשתית אוטומציה פנימית |
| `whatsapp_number` | `Make` | 🟢 נמוך | נתון תפעולי בלבד |

**התיקון הנכון ל-`claude_api_key`:** Edge Function (`deploy_edge_function`) שמחזיק את
המפתח ב-Supabase Vault/secrets בצד השרת; הדפדפן קורא ל-Edge Function בלבד.
ה-header `anthropic-dangerous-direct-browser-access` הוא 🚩 — אנתרופיק עצמה קוראת לו
"dangerous" כי הוא נועד לפיתוח/דמואים, לא לפרודקשן עם משתמשי קצה.

**כל secret עתידי** (Stripe secret key, service_role key, OAuth client secrets) —
**אסור** שיגיע ל-localStorage. רק Edge Function + Vault.

---

## Secrets Management — כללים

```bash
# .env.local — לעולם לא commit!
SUPABASE_URL=https://scyfywvzoogfrlalgftv.supabase.co
SUPABASE_ANON_KEY=eyJ...           # ✅ מותר ב-client — מוגן ע"י RLS
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # ❌ לעולם לא ב-client — Edge Functions בלבד
ANTHROPIC_API_KEY=sk-ant-...       # ❌ לא ב-localStorage — Edge Function + Vault
STRIPE_SECRET_KEY=sk_live_...      # ❌ Edge Function בלבד (webhook handler)
MAKE_WEBHOOK_URL=https://hook.eu1.make.com/...
```

```
.gitignore חובה: .env.local  .env.production  *.key
```

---

## Audit Trail — המבנה הקיים (009_rls_policies.sql)

```sql
-- audit_log: id, tenant_id, agent_id, action, entity_type, entity_id,
--            old_value, new_value, ip_address, user_agent, created_at
-- RLS: "service role only" — FOR ALL TO service_role — append-only,
--      אף משתמש (כולל admin) לא יכול לקרוא/לערוך/למחוק ישירות מה-client
```

```
□ כל פעולה רגישה (מחיקת ליד/נכס, שינוי plan, גישת admin) → INSERT ל-audit_log
□ ודא שאין trigger/policy שמתיר UPDATE/DELETE על audit_log עצמה
□ old_value/new_value לא כוללים secrets (API keys, סיסמאות, טוקנים)
```

---

## Security Checklist — לפני כל deploy

```
טננטים ובידוד:
□ get_advisors רץ ונקי (RLS חסר / policy רחבה מדי)
□ "מבחן דו-טננטי" עבר ידנית עם 2 חשבונות אמיתיים
□ views/materialized views משותפים מסוננים תמיד לפי get_my_tenant_id()

Auth:
□ Email confirmation דלוק עבור לקוחות אמיתיים (לא דמו)
□ register_demo_agent() לא חשוף ל-anon role

Secrets:
□ אין service_role / Stripe secret / Anthropic key בקוד צד-לקוח
□ git log --all -p | grep -E "sk-ant-|sk_live_|service_role" — נקי

Billing (Stripe):
□ plan / trial_ends_at משתנים רק דרך webhook מאומת-חתימה (לא update ישיר מה-client)
□ Customer Portal URL ו-Checkout links לא חושפים מידע על טננטים אחרים
```
