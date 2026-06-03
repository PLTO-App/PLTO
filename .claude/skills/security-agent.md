# Security Guardian Agent — מלי יופי ועור

## פקודה: `/security-agent`

סוכן AI אקטיבי שסורק, מנטר ומתריע על בעיות אבטחה בזמן אמת.
**שונה מ-`/security-guardian`** — זה סוכן שרץ ועושה, לא checklist.

---

## הרצה מהירה

```bash
# ביקורת מלאה:
python agents/security-agent.py

# מצבי ביקורת ממוקדים:
python agents/security-agent.py --mode secrets   # סריקת API keys חשופים
python agents/security-agent.py --mode auth      # בדיקת PIN + brute force
python agents/security-agent.py --mode pii       # חשיפת נתוני לקוחות
python agents/security-agent.py --mode logs      # פעילות חשודה ב-24h
python agents/security-agent.py --mode rls       # RLS policies ב-Supabase
```

---

## מה הסוכן בודק

### 🔑 Secrets Scanning
- API keys (Anthropic, Supabase) בקבצי הפרויקט
- סיסמאות hardcoded בקוד
- Tokens ב-git history
- `.env.local` ב-`.gitignore`

### 🔒 Admin Security
- PIN ברירת מחדל `1234` — חייב להחליף!
- PIN מוצפן (hash) לפני שמירה
- Brute-force protection (lockout אחרי 5 ניסיונות)
- Session timeout (logout אוטומטי אחרי 30 דקות)

### 👥 PII Protection — נתוני לקוחות
| נתון | בדיקה |
|------|-------|
| מספרי טלפון | לא נחשפים ב-console.log |
| שמות | לא ב-error messages |
| סוג עור / אלרגיות | מוגן ב-RLS, לא ב-localStorage |
| היסטוריית ביקורים | admin בלבד |

### 🗄️ Supabase RLS
```sql
-- כל טבלה חייבת:
ALTER TABLE [table] ENABLE ROW LEVEL SECURITY;
```
| טבלה | מדיניות |
|------|---------|
| `bookings` | לקוח רואה רק שלו, admin הכל |
| `clients` | admin בלבד |
| `services` | קריאה ציבורית, כתיבה admin |
| `audit_log` | admin בלבד |

### 📋 Audit Log Monitoring
- מחיקות מרובות בזמן קצר
- שינויי מחיר
- ניסיונות login כושלים
- גישה מ-IP חדש

---

## ציון אבטחה

| ציון | דרגה | משמעות |
|------|------|--------|
| 90-100 | A | מצוין — המשך לפחות פעם בחודש |
| 75-89  | B | טוב — תקן HIGH בשבוע הקרוב |
| 60-74  | C | בינוני — תקן CRITICAL מיידית |
| 40-59  | D | חלש — עצור הכל ותקן |
| 0-39   | F | קריטי — אל תעלה לפרודקשן |

---

## התקנה

```bash
# תלויות:
pip install anthropic httpx

# משתני סביבה נדרשים ב-.env.local:
ANTHROPIC_API_KEY=sk-ant-...
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...  # לביקורת RLS
MAKE_SECURITY_ALERT_WEBHOOK=https://hook.eu1.make.com/...  # להתראות
```

---

## הפעלה אוטומטית (Make.com)

הגדר סצנריה ב-Make.com שמריצה את הסוכן:

| Trigger | פעולה |
|---------|-------|
| כל יום ב-08:00 | `--mode full` — ביקורת יומית |
| לפני כל deploy | `--mode secrets` — סריקת secrets |
| בעת גישת admin | `--mode auth` — בדיקת אימות |

---

## דוח לדוגמה

```
🔒 Security Guardian Agent — ביקורת מלאה
═══════════════════════════════════════════════════
ציון: 72/100 — דרגה C

🚨 CRITICAL (2):
  • PIN ברירת מחדל '1234' — החלף מיידית
  • PIN לא מוצפן — מאוחסן כטקסט גלוי

⚠️  HIGH (1):
  • אין הגנת brute-force על admin login

ℹ️  MEDIUM (2):
  • אין session timeout
  • console.log חושף מספר טלפון (שורה 847)

✅ נקי:
  • לא נמצאו API keys חשופים
  • RLS מוגדר על כל הטבלאות

📋 דוח מלא: security-report-20260603-0800.json
═══════════════════════════════════════════════════
```

---

## קובץ: `agents/security-agent.py`

הסוכן כתוב עם Anthropic Claude API + tool_use.
כל בדיקה היא tool נפרד שהסוכן מחליט מתי ואיך להשתמש בו.
