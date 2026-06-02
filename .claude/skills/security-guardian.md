# Security Guardian — מלי יופי ועור

## פקודה: `/security-guardian`

הגנת data, checklist אבטחה, incident response.

---

## Data Classification

| נתון | רמת רגישות | הגנה נדרשת |
|------|-----------|-----------|
| שמות לקוחות | רגיש | RLS + לא מוצג בלוגים |
| מספרי טלפון | גבוה מאוד | RLS + masking בלוגים |
| הערות עור/אלרגיות | רפואי/קריטי | RLS + encryption |
| מחירים | נמוך | ציבורי |
| PIN admin | קריטי | hash + rate limit |
| API keys | קריטי | .env only, לעולם לא ב-git |

---

## Security Checklist — Daily

```
□ אין API keys ב-git history (git log --all -p | grep "sk-")
□ .env.local ב-.gitignore
□ Supabase advisors scan נקי (mcp: get_advisors)
□ PIN לא '1234' (default)
□ Admin session expires
```

## Security Checklist — Pre-Deploy

```
□ RLS enabled על כל הטבלאות
□ service_role_key לא נחשף לצד הלקוח
□ Input sanitization (XSS prevention)
□ HTTPS בלבד
□ Rate limiting על booking API
□ CORS מוגדר
□ Secrets ב-Supabase Vault (לא ב-DB)
□ Webhook secret validation
□ Error messages לא חושפים stack traces
```

---

## Threat Model — מלי CRM

### Attack Vectors

#### 1. Unauthorized Admin Access
```
ריסק: גישה לתורים, לקוחות, שינוי מחירים
מניעה:
- PIN חזק + hash
- Lockout אחרי 5 ניסיונות
- IP whitelist (optional)
- Session timeout
```

#### 2. Data Scraping / Enumeration
```
ריסק: חשיפת כל מספרי הטלפון
מניעה:
- RLS — לקוח רואה רק את עצמו
- Rate limiting
- No public API for listing clients
```

#### 3. Booking Spam
```
ריסק: מילוי כל הסלוטים בהזמנות מזויפות
מניעה:
- Phone verification (SMS OTP)
- Captcha
- Rate limit per IP
- Manual confirmation flow
```

#### 4. XSS via Notes Field
```
ריסק: הזרקת script בהערות לקוח
מניעה:
- Sanitize הערות לפני הצגה
- innerHTML → textContent
- CSP headers
```

---

## Incident Response

### תור נמחק בטעות
```bash
# 1. בדוק audit_log
SELECT * FROM audit_log WHERE table_name='bookings' ORDER BY created_at DESC;

# 2. שחזר מגיבוי Supabase
# Dashboard → Database → Backups → Point-in-time recovery
```

### חשד לפריצה
```bash
# 1. נעל מיידית
# Supabase Dashboard → Auth → Disable signups

# 2. בדוק לוגים
# mcp: get_logs (service='auth')

# 3. שנה כל הסיסמאות/keys
# Supabase → Settings → API → Regenerate keys

# 4. בדוק audit_log
SELECT * FROM audit_log WHERE created_at > now() - interval '24 hours';
```

### API Key נחשף
```bash
# 1. מיידי — revoke ב-Supabase Dashboard
# 2. Generate key חדש
# 3. Update .env.local ועדכן deploy
# 4. git log בדיקה: git log --all -p | grep "eyJhbGci"
# 5. אם ב-git history: BFG Repo Cleaner
```

---

## Privacy (GDPR-adjacent — ישראל)

```
לפי חוק הגנת הפרטיות הישראלי:
□ יידוע לקוחות על שמירת נתונים
□ זכות למחיקה — DELETE endpoint
□ לא שומרים נתונים מעבר לנדרש
□ מספרי טלפון לא מועברים לצד שלישי ללא הסכמה
□ Google Calendar — תורים ללא שמות מלאים אם אפשר
```
