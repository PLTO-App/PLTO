# CLAUDE.md — Liders CRM

## 🚨 LAUNCH BLOCKER — חובה להזכיר בכל שיחה

> **Stripe Live Mode ממתין לאישור עסקי**
> - מס עוסק מורשה — בתהליך פתיחה, צפוי **שבוע הבא (סביב 19–20 יוני 2026)**
> - חשבון בנק עסקי — נפתח במקביל
> - **עד שאלה מוכנים — לא ניתן לעבור ל-Live ולגבות כסף אמיתי**
>
> כשיהיו מוכנים — דרוש:
> 1. להשלים אימות Stripe (העלאת מסמכים)
> 2. ליצור Payment Links חדשים ב-Live mode (ללא `test_` prefix)
> 3. ליצור Webhook חדש ב-Live mode ← לעדכן `STRIPE_WEBHOOK_SECRET` ב-Supabase
> 4. לשלוח את 4 ה-URLs לקלוד ← יעדכן `index.html` ויעלה ל-main

---

## חזון הפרויקט

**Liders CRM** — הפלטפורמה שהופכת לידים לעסקאות.

מערכת CRM מודרנית, מובייל-ראשון, לניהול פייפליין מכירות.
דגש על **חווית משתמש** מעולה ו**אבטחה** מקסימלית.

---

## Stack

- **Frontend**: HTML + CSS + Vanilla JS (RTL, עברית)
- **Database**: Supabase (PostgreSQL + RLS)
- **Auth**: PIN-based admin (bcrypt hash)
- **Automations**: Make.com
- **Calendar**: Google Calendar MCP
- **Design**: Figma + Canva MCP
- **Architecture**: Miro MCP
- **Docs**: Notion MCP
- **Storage**: Airtable MCP
- **AI Agents**: Anthropic Claude API

---

## Entities

| Entity | תיאור |
|--------|-------|
| `Lead` | ליד: שם, חברה, טלפון, אימייל, ערך עסקה, שלב פייפליין |
| `CrmSettings` | הגדרות: שם חברה, tagline |
| `AdminAuth` | PIN hash — ללא גישה ישירה מה-API |

---

## Pipeline Stages

| ID | שם | צבע |
|----|-----|------|
| 1 | ליד חדש | אפור |
| 2 | יצרנו קשר | כחול |
| 3 | הצעה נשלחה | סגול |
| 4 | במשא ומתן | כתום |
| 5 | עסקה סגורה ✓ | ירוק |

---

## Design System

- **Palette**: Navy (#0F1F3D) + Blue (#2563EB) + Light gray (#F1F5F9)
- **Font**: Heebo
- **Direction**: RTL מלא
- **Mobile-first**: 390px viewport ראשוני

---

## Supabase Project

- **Project ID**: `scyfywvzoogfrlalgftv`
- **Region**: eu-central-1
- **URL**: `https://scyfywvzoogfrlalgftv.supabase.co`

### טבלאות

| טבלה | RLS | הערה |
|------|-----|------|
| `leads` | anon CRUD | פייפליין לידים |
| `crm_settings` | anon READ בלבד | עדכון דרך RPC |
| `admin_auth` | ללא גישה | PIN hash בלבד |

### RPCs

| פונקציה | תיאור |
|---------|-------|
| `verify_admin_pin(pin_input)` | אימות PIN — מחזיר boolean |
| `save_crm_settings(pin, name, tagline, new_pin?)` | שמירת הגדרות + שינוי PIN |

---

## קישורים חיים

| | URL |
|-|-----|
| CRM (לקוחות) | https://liders-crm.github.io/liders_crm/ |
| פאנל אדמין | https://liders-crm.github.io/liders_crm/admin.html |

> האדמין מחובר לאותה Supabase. כניסה: אימייל + סיסמה. קישור אליו גם מתוך הגדרות ה-CRM.

---

## Make.com

- **Team ID**: `1851801`
- **Zone**: `eu1.make.com`
- **Webhook URL**: `https://hook.eu1.make.com/f0nzngm6gdokri5naqu7enbay538ay8i`

### סצנריות פעילות

| סצנריו | ID | קישור | טריגר |
|--------|-----|-------|-------|
| Lead Notifications | 6083347 | https://eu1.make.com/1851801/scenarios/6083347/edit | Webhook |
| Trial Expiry Notifications | 6185659 | https://eu1.make.com/1851801/scenarios/6185659/edit | Scheduled (24h) |

---

## MCP Servers

| שרת | UUID prefix | שימוש |
|-----|-------------|-------|
| Supabase | `f474d5bb` | DB, migrations, RLS |
| Google Calendar | `6368118b` | ניהול יומן |
| Gmail | `4e93495e` | תקשורת |
| Make.com | `194941ca` | אוטומציות |
| Figma | `88a7dadd` | UI design |
| Canva | `3f33a9a8` | Marketing |
| Notion | `97537a26` | תיעוד |
| Airtable | `273af94e` | דיווח |
| Miro | `4a81aac9` | ארכיטקטורה |
| GitHub | `github` | version control |

---

## Files

```
index.html     — האפליקציה המלאה (HTML + CSS + JS)
CLAUDE.md      — קובץ זה
.claude/
  settings.json
  skills/
```

---

## כללי עבודה

1. **עברית RTL** — כל טקסט UI בעברית
2. **Mobile-first** — תמיד בדוק ב-390px
3. **CSS variables** — אף פעם לא hardcoded colors
4. **RLS על כל טבלה** — אין יוצא מהכלל
5. **Secrets** — לעולם לא ב-git
6. **PIN** — מאוחסן כ-bcrypt, לא plaintext
7. **פנייה למשתמש** — תמיד בלשון זכר

---

## Quick Commands

```bash
open index.html              # הרץ לוקאל
python3 -m http.server 8080  # שרת לוקאל
```

---

## ניתוח מתחרים — סיכום (יוני 2026)

> נבדק לעומק ב-16.6.2026 עם 5 סוכני מחקר במקביל.

### מתחרים עיקריים ומחירים

| מתחרה | חינמי | כניסה | בינוני | הערה |
|--------|-------|-------|--------|------|
| HubSpot | ✅ 2 users | $15/mo | $50/user | RTL חלקי, Trustpilot 2.0/5 |
| Pipedrive | ❌ | $14/user | $39/user | RTL גרוע, צריך תוסף Chrome |
| Monday CRM | ❌ | $12/user | $17/user | ישראלי, RTL חלקי |
| Zoho CRM | ✅ 3 users | $14/user | $52/user | RTL מלא, פותח משרד בת"א |
| Salesforce | ❌ | $25/user | $100/user | מגביל ל-10 users ב-Starter |
| Freshsales | ✅ 3 users | $11/user | $71/user | אפליקציה איטית |
| Bitrix24 | ✅ ללא הגבלה | $49/ארגון | $399/ארגון | תמחור לפי ארגון |
| Scalla CRM | ❓ | לא פורסם | — | ישראלי, עברית מלאה |

### יתרון תחרותי נוכחי של Liders

- **עברית 100% נייטיב** — אף מתחרה גלובלי לא מספק זאת
- **RTL מלא** — Pipedrive דורש תוסף Chrome; אנחנו נייטיב
- **Mobile-First אמיתי** — המתחרים מוסיפים מובייל בדיעבד
- **פשטות** — 5 שלבים, ללא עקומת למידה

### כאבים שהשוק הישראלי חווה (מחקר)

1. לידים "נופלים בין הכסאות" — אין מעקב מרכזי
2. RTL שבור בכל הכלים הגלובליים
3. מחיר: הסף הנסבל בישראל — מתחת ל-₪100-200/חודש לצוות
4. אין WhatsApp Integration נייטיב באף כלי גלובלי
5. אין ציות לרשות המיסים (חשבוניות)
6. מורכבות יתר — עסקים קטנים נוטשים מערכות כבדות

---

## חזון Liders CRM 2.0 — "Sales OS"

> **הפרדיגמה החדשה:** במקום CRM שאנשים *צריכים לעדכן* — CRM שמתעדכן **לבד.**
> כל מתחרה בנה מחסן נתונים יפה. אנחנו בונים שותף עסקי שמוכר בשבילך.

### 7 חידושים שאין למתחרים

#### 1. Zero Input CRM — "מתעדכן לבד"
- WhatsApp Auto-Sync: AI קורא שיחת WhatsApp ומעדכן הליד אוטומטית
- Call Intelligence: תמלול שיחות טלפון + חילוץ: שלב, פעולה הבאה, תאריכים
- Email Forward: Forward אימייל לכתובת מיוחדת → הליד מתעדכן
- **Stack:** WhatsApp Business API (360Dialog) + Claude API + Make.com

#### 2. WhatsApp IS the CRM — "ממשק בלי ממשק"
- שולח הודעה לבוט: "דיברתי עם רוני, מעוניין, פגישה ביום ד׳"
- הבוט מעדכן CRM + שולח אישור + מתזמן תזכורת
- **Stack:** WhatsApp Business API + Claude API (NLP) + Supabase

#### 3. Buying Signal Radar — "יודע מתי להתקשר"
- ליד פתח הצעה 3 פעמים → התראה: "רוני קורא ההצעה עכשיו — התקשר!"
- ליד חזר לאתר אחרי שבוע → "חזר — זמן ליצור קשר"
- ליד לא ראה מסר 3 ימים → "שנה גישה"
- **Stack:** email tracking pixel + Supabase webhooks + Make.com

#### 4. Morning Briefing — "המנהל שמתכנן את היום"
- כל יום ב-8:00 → WhatsApp עם: לידים חמים, עסקאות בסיכון, יעד חודשי
- **Stack:** Make.com scheduled scenario + Supabase query

#### 5. Reverse CRM — "Lead Portal"
- כל ליד מקבל קישור אישי לראות את ההצעה שלו + לאשר + לשאול שאלות
- כשהוא מבקר → התראה + עדכון CRM אוטומטי
- **Stack:** דף HTML חדש (lead.html) + Supabase tokens

#### 6. Personal Coach — "לומד אותך"
- אחרי 3 חודשי נתונים: מזהה דפוסים בעסקאות שלך
- מציע: "5 עסקאות פתוחות מעל 20 יום — בהיסטוריה שלך, Zoom סוגר אותן"
- **Stack:** Claude API + Supabase analytics

#### 7. Community Intelligence — "מה עסקים כמוך מגלים"
- נתונים אנונימיים ואגרגטיביים מכל משתמשי Liders
- תובנות ישראליות: "עסקים שמתקשרים תוך 5 דקות סוגרים 4x יותר"
- דורש: מינימום ~100 עסקים פעילים במערכת
- **Stack:** Supabase aggregated views + Claude API

---

## רואדמאפ V2 — לפי פאזות

> **כלל:** לא מוציאים כסף עד שיש לקוחות. כל פאזה ממתינה לפאזה לפניה.

### פאזה 0 — תשתית (שבוע 1-2) | עלות: $0
- [ ] מעבר ל-Supabase Auth מלא (multi-user אמיתי)
- [ ] טבלת `users` + `organizations`
- [ ] שדה `source` לכל ליד (WhatsApp/אתר/טלפון/הפנייה)

### פאזה 1 — Quick Wins (שבוע 3-6) | עלות: $0
- [ ] לוח דוחות: המרה לפי שלב, ערך פייפליין, ממוצע ימים לסגירה
- [ ] Follow-up Reminders אוטומטיים (Make.com קיים)
- [ ] Freemium Tier: חינמי (2 users, 50 לידים) | ₪99 | ₪199

### פאזה 2 — WhatsApp First (שבוע 7-14) | עלות: ~$5/חודש (360Dialog)
> להפעיל רק כשיש 20-30 לקוחות פעילים
- [ ] WhatsApp Bot לעדכון CRM בשפה טבעית
- [ ] Morning Briefing יומי ב-WhatsApp

### פאזה 3 — Buying Signals (שבוע 15-22) | עלות: נמוכה
> להפעיל רק כשיש בסיס לקוחות יציב
- [ ] Email open tracking + התראות מיידיות
- [ ] Lead Portal (Reverse CRM)

### פאזה 4 — Zero Input CRM (חודש 6-8) | עלות: Claude API per-use
> הבנייה המרכזית — דורשת לקוחות פעילים שמשלמים
- [ ] WhatsApp Auto-Sync (AI קורא שיחות)
- [ ] Personal Coach Insights

### פאזה 5 — Community Intelligence (חודש 9+)
> דורש: מינימום 100 עסקים פעילים
- [ ] Aggregated insights אנונימיים
- [ ] Dashboard "Insights" חדש

---

## עלויות V2 לפי פאזה

| פאזה | עלות חודשית | תנאי הפעלה |
|------|-------------|------------|
| 0-1 (תשתית + Quick Wins) | $0 | עכשיו |
| 2 (WhatsApp Bot) | ~$5/חודש | 20-30 לקוחות |
| 3 (Buying Signals) | ~$10/חודש | בסיס יציב |
| 4 (Zero Input) | Claude API per-use | לקוחות משלמים |
| 5 (Community) | $0 תוספת | 100+ עסקים |

---

## WhatsApp Business API — מה צריך

- **ספק מומלץ:** 360Dialog (הכי פשוט לישראל)
- **עלות:** ~$5/חודש
- **תהליך אישור:** 1-3 ימים (חד-פעמי)
- **מה Claude יבנה:** 80% מהלוגיקה (Make.com + Claude API + Supabase)
- **מה המשתמש צריך לעשות:** רק אישור חשבון 360Dialog

---

## מודל תמחור V2 (מתוכנן)

| תוכנית | מחיר | מה כלול |
|--------|------|---------|
| חינמי | ₪0 | 2 משתמשים, 50 לידים, פייפליין בסיסי |
| Pro | ₪99/חודש | משתמשים ללא הגבלה, 500 לידים, Dashboard |
| Growth | ₪199/חודש | הכל + WhatsApp Bot + Morning Briefing |
| Scale | ₪399/חודש | הכל + Buying Signals + Lead Portal + Coach |

> **מחכה ל:** מס עוסק + חשבון בנק עסקי (צפוי 19-20 יוני 2026) → Stripe Live
