# Security Guardian — Liders CRM

## פקודה: `/security-guardian`

הגנת מידע, threat model ו-incident response עבור **Liders** — CRM נדל"ן ישראלי, **מולטי-טננטי** (SaaS).

> ⚠️ גרסה קודמת של הסקיל הזה הייתה מועתקת מפרויקט אחר (סלון יופי "מלי" — `bookings`/`clients`/PIN).
> הגרסה הזו נכתבה מחדש מול הסכימה והקוד האמיתיים של Liders.

---

## ההקשר: על מה אנחנו מגנים

Liders הוא **מולטי-טננט** — עשרות סוכנויות נדל"ן חולקות אותו DB (`scyfywvzoogfrlalgftv`,
eu-central-1), מבודדות באמצעות `tenant_id` + RLS (ראה `/supabase-security`).

**דליפת מידע בין טננטים (cross-tenant leak) היא הסיכון המרכזי במערכת הזו** — חמור בהרבה
מכל באג UI, כי משמעותו שסוכנות א' רואה לידים, נכסים ונתוני billing של סוכנות ב'.

---

## Data Classification

| נתון | טבלה / מיקום | רמת רגישות | הגנה נדרשת |
|------|--------------|-----------|-----------|
| שם + טלפון ליד | `leads` | גבוה | RLS לפי `tenant_id`, masking בלוגים |
| תקציב / שלב משא-ומתן | `leads.budget_*`, `status` | עסקי-רגיש | RLS, לא נחשף ב-API ציבורי |
| כתובות נכסים | `properties` | בינוני-גבוה | RLS לפי `tenant_id` |
| פרטי סוכנים (email, role) | `agent_users` | גבוה | RLS + Supabase Auth |
| Stripe customer/subscription IDs | `tenants` | קריטי | RLS; לכתיבה — webhook בלבד |
| **מפתחות API (Claude / Make webhook)** | `localStorage` בדפדפן | 🔴 **קריטי — חשוף כרגע** | ראה "סיכון פתוח" למטה |
| audit trail | `audit_log` | קריטי | `service_role` בלבד, append-only |

---

## 🔴 סיכון פתוח שזוהה — מפתח Claude API נחשף בצד הלקוח

ב-`AI` module (`index.html`):
```js
localStorage.setItem('claude_api_key', k.trim());          // plaintext בדפדפן
fetch('https://api.anthropic.com/v1/messages', { headers: {
  'x-api-key': key,
  'anthropic-dangerous-direct-browser-access': 'true',     // 🚩 השם מדבר בעד עצמו
}});
```
**וקטור התקפה:** XSS כלשהו (יש 31 שימושי `innerHTML` בקוד) / תוסף דפדפן זדוני / גישה פיזית
למחשב משותף ⟵ גניבת מפתח API מלא של הסוכנות, שימוש לרעה על חשבונה.

**התיקון הנכון:** Supabase Edge Function שמחזיק את המפתח ב-Vault/secrets בצד השרת;
הדפדפן קורא ל-Edge Function בלבד — **לעולם לא** ל-`api.anthropic.com` ישירות.
אותו דפוס חל על `make_webhook_url` (פחות קריטי — לא secret כשלעצמו, אך חושף תשתית פנימית).

> זהו פריט #1 ל-backlog האבטחה — ראו גם `.claude/agents/security-hardener.md`.

---

## Security Checklist — Daily

```
□ אין API keys / service_role_key ב-git history   (git log --all -p | grep -E "sk-ant-|sk_live_|eyJhbGci")
□ .env.local / .env.production ב-.gitignore
□ Supabase advisors scan נקי                       (mcp: get_advisors)
□ אין secret חדש שנכנס ל-localStorage
```

## Security Checklist — Pre-Deploy (לכל feature חדש)

```
□ RLS מופעל, ונבדק עם 2 טננטים אמיתיים — ודא בידוד מלא (ה"מבחן הדו-טננטי")
□ כל query/RPC חדש משתמש ב-get_my_tenant_id(), לא ב-tenant_id שמגיע מה-client
□ service_role_key ו-Stripe secret key לא נחשפים ב-index.html / git
□ קלט חופשי ממשתמש (שם ליד, הערה, חיפוש) → escape לפני innerHTML, עדיפות ל-textContent
□ Stripe webhook מאמת חתימה (stripe-signature header) לפני שינוי plan
□ הודעות שגיאה ללקוח לא חושפות SQL / stack traces
```

---

## Threat Model — Liders CRM

### 1. Cross-Tenant Data Leak ⟵ הסיכון המרכזי
```
וקטורים: RLS policy שגוי/חסר, query בלי tenant_id, materialized views משותפים
          (lead_score_summary, pipeline_summary, overdue_tasks), state בצד הלקוח
          שלא מתאפס בין החלפת טננט.
מניעה: get_my_tenant_id() בכל policy; "מבחן דו-טננטי" ידני אחרי כל migration;
       רענון מלא של State בכל login/logout (לא רק עדכון חלקי).
```

### 2. XSS דרך שדות חופשיים (31 שימושי innerHTML בקוד)
```
וקטור: <script> מוזרק דרך שם ליד / הערה / כתובת נכס שמוצגים עם innerHTML.
מניעה: escape HTML על כל ערך שמגיע מ-DB לפני הזרקה ל-innerHTML; textContent כברירת מחדל;
       CSP header (Content-Security-Policy) ב-hosting.
```

### 3. דליפת מפתחות API מהדפדפן
```
ראה "סיכון פתוח" למעלה — claude_api_key + direct-browser-access header.
```

### 4. ניצול-לרעה של signup אוטומטי / register_demo_agent()
```
וקטור: יצירת tenants/agents מזויפים בהמוניהם (spam signup), מיצוי trial quota, DoS.
מניעה: rate limiting על signup; ניטור audit_log לקצב יצירת tenants חריג;
       ודא ש-register_demo_agent() (SECURITY DEFINER) לא קריאה ע"י anon.
```

### 5. Stripe Billing Tampering — עקיפת ה-Paywall
```
וקטור: שינוי plan / trial_ends_at ישירות מה-client כדי "לפרוץ" את חסימת ה-Paywall.
מניעה: plan/trial_ends_at משתנים אך ורק דרך Stripe webhook מאומת-חתימה + service_role
       (Edge Function) — לעולם לא דרך update ישיר מה-client. RLS: read בלבד ללקוח.
```

---

## Incident Response

### חשד לדליפת מידע בין טננטים
```bash
# 1. נעל גישה מיידית — Supabase Dashboard → Auth → Disable signups
# 2. בדוק audit_log לפעילות חריגה:
SELECT * FROM audit_log WHERE created_at > now() - interval '24 hours' ORDER BY created_at DESC;
# 3. הרץ get_advisors — אתר RLS policies חסרות/רחבות מדי
# 4. תקן את ה-policy → migration → deploy → רק אז פתח signups מחדש
```

### API Key נחשף (Claude / Stripe / Supabase)
```bash
# 1. Revoke מיידי בדשבורד הרלוונטי (Anthropic Console / Stripe / Supabase → Settings → API)
# 2. צור מפתח חדש — שמור ב-Edge Function secrets, לא ב-index.html
# 3. git log --all -p | grep -E "sk-ant-|sk_live_|eyJhbGci" — ודא שלא נכנס להיסטוריה
# 4. אם כן נכנס: BFG Repo Cleaner + force-push מתואם
```

### ליד / נכס נמחק בטעות
```bash
SELECT * FROM audit_log WHERE entity_type='lead' AND action='DELETE' ORDER BY created_at DESC LIMIT 20;
# שחזור: Supabase Dashboard → Database → Backups → Point-in-time recovery
```

---

## פרטיות — חוק הגנת הפרטיות (ישראל)

```
□ יידוע סוכנים/לקוחות-קצה על איסוף ושמירת מידע (privacy notice בהרשמה)
□ זכות עיון/תיקון/מחיקה — מסלול למחיקת ליד/נתון לפי בקשה
□ מינימיזציה — לא שומרים שדות שלא נחוצים לתפעול
□ מדיניות שימור מוגדרת (ראה: 30 יום שימור נתונים אחרי תום ניסיון — Billing module)
□ טלפוני לידים לא עוברים לצד ג' (Make.com/WhatsApp) בלי בסיס חוקי/הסכמה
□ מידע שנשלח ל-AI (Claude) — לוודא שאין PII רגיש מעבר לנדרש בפרומפט
□ להתעדכן בדרישות התיקון העדכני לחוק הגנת הפרטיות (תיקון 13, נכנס לתוקף 2025) —
  ייתכן שמטיל חובות נוספות (ממונה הגנת פרטיות, רישום מאגרים) שרלוונטיות ל-SaaS עם PII
```
