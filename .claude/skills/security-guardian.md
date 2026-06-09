# Security Guardian — Liders CRM Platform

## פקודה: `/security-guardian`

הגנת data, checklist אבטחה, incident response לפלטפורמת Liders CRM.

---

## Data Classification

| נתון | רמת רגישות | הגנה נדרשת |
|------|-----------|-----------|
| שמות לקוחות עסקיים | רגיש | RLS + לא מוצג בלוגים |
| מספרי טלפון | גבוה | RLS + masking |
| אימייל לקוחות | גבוה | RLS |
| סכומי תשלום / MRR | עסקי | RLS, לא ציבורי |
| API keys | קריטי | .env only, לעולם לא ב-git |
| Supabase service_role | קריטי | server-side only |

---

## Security Checklist — Daily

```
□ אין API keys ב-git history (git log --all -p | grep "eyJhbGci")
□ .env.local ב-.gitignore
□ Supabase advisors scan נקי (mcp: get_advisors)
□ Auth session תקין
□ Make.com webhooks עם secret validation
```

## Security Checklist — Pre-Deploy

```
□ RLS enabled על liders_accounts ו-liders_invoices
□ service_role_key לא נחשף לצד הלקוח
□ Input sanitization (XSS — esc() function)
□ HTTPS בלבד
□ CORS מוגדר
□ Error messages לא חושפים stack traces
□ Supabase Vault לסודות (לא ב-DB ישירות)
□ Webhook secret validation
```

---

## Threat Model — Liders CRM Admin

### Attack Vectors

#### 1. Unauthorized Dashboard Access
```
ריסק: גישה לנתוני לקוחות, MRR, חשבוניות
מניעה:
- Supabase Auth (email/password חזק)
- Session auto-expire
- RLS על כל הטבלאות
```

#### 2. Data Scraping
```
ריסק: חשיפת רשימת כל לקוחות הפלטפורמה
מניעה:
- RLS — גישה ל-authenticated בלבד
- Rate limiting על Supabase API
- לא expose public API
```

#### 3. XSS via Input Fields
```
ריסק: הזרקת script בשדות שם/הערות
מניעה:
- esc() function לפני כל innerHTML
- CSP headers
- textContent על טקסט דינמי
```

#### 4. Invoice Manipulation
```
ריסק: שינוי סכום/סטטוס חשבונית
מניעה:
- Auth required לכל write operation
- Audit log על כל שינוי
- לא accept server-calculated amounts מה-client
```

---

## Incident Response

### נתוני לקוח נמחקו בטעות
```sql
-- 1. בדוק audit_log
SELECT * FROM liders_audit_log
WHERE table_name = 'liders_accounts'
ORDER BY created_at DESC LIMIT 20;

-- 2. שחזר מגיבוי Supabase
-- Dashboard → Database → Backups → Point-in-time recovery
```

### חשד לגישה לא מורשית
```bash
# 1. בדוק לוגים
# mcp: get_logs(service='auth')

# 2. בדוק sessions פעילים
# Supabase → Auth → Users → Sessions

# 3. נעל מיידית אם צריך
# Auth → Settings → Disable signups

# 4. שנה password ל-Liders.crm@gmail.com
```

### API Key נחשף בגיט
```bash
# 1. מיידי — revoke ב-Supabase Dashboard
# 2. Generate key חדש
# 3. Update .env.local
# 4. בדוק git history:
git log --all -p | grep "eyJhbGci"
# 5. אם נמצא — BFG Repo Cleaner
```

---

## Privacy — ישראל

```
לפי חוק הגנת הפרטיות הישראלי:
□ יידוע לקוחות על שמירת נתונים
□ זכות למחיקה — DELETE account
□ לא מעבירים נתונים לצד שלישי ללא הסכמה
□ מספרי טלפון לא נחשפים ב-logs
```
