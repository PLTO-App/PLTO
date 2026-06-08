# CLAUDE.md — מלי • יופי ועור CRM

## חזון הפרויקט

**המטרה הסופית:** לבנות מערכת CRM חדשנית, יוקרתית ואיכותית לעסקים —
משהו טוב יותר מכל המתחרים הקיימים, שיתן מענה אמיתי ללקוח.

המערכת תאפשר לעסקים לנהל את עצמם בצורה קלה ופשוטה,
עם דגש עיקרי על **חווית משתמש** מעולה.

בנוסף — דגש מרכזי על **אבטחת המוצר**: לבנות את המערכת בצורה מאובטחת לחלוטין,
מפורטת ועשירה במידע.

---

## מה הפרויקט הזה

מערכת CRM + Booking לסלון יופי **מלי אלגרבלי** — קוסמטיקאית רפואית מוסמכת בטבריה.
מתמחה בטיפולי KB Pure, עור רגיש, אקנה, פדיקור רפואי.

---

## ⚠️ מצב נוכחי של הקוד (חשוב לכל סוכן AI)

**`index.html` הוא כרגע פרוטוטייפ סטטי, חד-קובצי, ללא backend מחובר בפועל:**

- כל הנתונים (שירותים, לקוחות, תורים, שעות עבודה, PIN) חיים ב-state object יחיד
  בשם `S` בתוך ה-`<script>`, מאותחלים עם **נתוני דמה קשיחים (hardcoded)**.
- **אין פרסיסטנציה** — לא `localStorage`, לא Supabase, לא קריאות `fetch`. רענון דף מאפס
  הכל בחזרה לנתוני הדמה המקוריים. כל הזמנה/שינוי "נשמר" רק בזיכרון של הדפדפן הנוכחי.
- ה-**Stack** וה-**MCP Servers** המתוארים למטה הם **הארכיטקטורה היעדית/המתוכננת**
  (Supabase, Make.com, Google Calendar וכו') — עדיין לא מקושרים בפועל ל-`index.html`.
- כשמבקשים "לחבר ל-DB" / "לשמור הזמנה" / "לשלוח תזכורת" — זו עבודת אינטגרציה אמיתית
  (להגדיר טבלאות + RLS ב-Supabase, להחליף את ה-state המקומי בקריאות API), לא רק
  עדכון של ה-state המקומי.

**מסקנה לעבודה:** לפני שמניחים שמשהו "כבר עובד מול ה-DB" — תבדקו ב-`index.html`
האם זו פונקציונליות UI-בלבד מול `S`, או אינטגרציה אמיתית.

---

## Stack

| | נוכחי (מומש ב-`index.html`) | יעד (מתוכנן/חלקית מחובר) |
|---|---|---|
| **Frontend** | HTML + CSS + Vanilla JS, קובץ יחיד, RTL מלא | ללא שינוי — נשאר vanilla, בלי framework |
| **Database** | JS state object בזיכרון (`S`), נתוני דמה | Supabase (PostgreSQL + RLS) |
| **Auth** | נעילת PIN לוקאלית (`S.pin`, ברירת מחדל `1234`) | PIN-based admin + Supabase Auth |
| **Automations** | — | Make.com (WhatsApp, Gmail) |
| **Calendar** | — | Google Calendar MCP |
| **Design** | CSS variables ב-`:root` | Figma + Canva MCP |
| **Architecture docs** | — | Miro / Mermaid MCP |
| **Docs** | — | Notion MCP |
| **Storage/Reporting** | — | Airtable MCP |
| **AI Agents** | — | Anthropic Claude API |

---

## מבנה `index.html` (~1300 שורות, קובץ יחיד)

| חלק | שורות בערך | תיאור |
|-----|-----------|-------|
| `<style>` | 8–728 | כל ה-CSS: design tokens ב-`:root`, רכיבים, RTL |
| HTML markup | 730–942 | 3 "עמודים" (`.page`) שמתחלפים: הזמנה / אודות / ניהול |
| `<script>` | 944–1294 | כל הלוגיקה: state, רינדור, אירועים |

### State (זיכרון בלבד, לא נשמר)

```js
const S = {
  salonName, tagline, pin, slotMin,
  services:  [...],   // {id, name, price, duration, tag}
  schedule:  {...},   // 0-6 (יום בשבוע) → {open, from, to}
  bookings:  [...],   // {id, name, phone, service, price, date, time, notes}
};

let bk   = { service:null, date:null, time:null }; // טיוטת ההזמנה הנוכחית
let step = 1;          // שלב באשף ההזמנה (1-4)
let calMonth, pinStr, adminOpen;                   // state עזר ל-UI
```

### זרימת המסך (3 טאבים, מוחלפים ע"י `showPage(name, btn)`)

1. **הזמנת תור** (`page-booking`) — אשף 4 שלבים: בחירת טיפול → תאריך → שעה → פרטים אישיים
   ומסך הצלחה. לוגיקה: `selectSvc → selectDate → selectTime → submitBooking`.
2. **אודות** (`page-about`) — תוכן סטטי על מלי אלגרבלי.
3. **ניהול** (`page-admin`) — נעול מאחורי **PIN בן 4 ספרות** (`buildNumpad`/`pinPress`),
   מציג: רשימת תורים קרובים, עריכת שירותים/מחירים, שעות עבודה, הגדרות כלליות.

### מוסכמות קוד שחוזרות על עצמן

- **`render*()`** — פונקציות שמייצרות HTML (template literals) ומזריקות ל-`innerHTML`
  לפי ה-state הנוכחי (`renderServices`, `renderCal`, `renderSlots`, `renderBookingList`...).
- **`select*()` / `change*()` / `save*()`** — משנות את ה-state ואז קוראות ל-`render*`
  המתאים כדי לרענן את ה-DOM (אין framework/reactivity — רינדור ידני בכל שינוי).
- **Event handlers inline** — `onclick="..."` / `onchange="..."` ישירות ב-template strings,
  לא `addEventListener`. עקביות חשובה — אל תערבבו סגנונות בקובץ אחד.
- **עברית בקוד** — שמות שירותים, ימים, חודשים, הודעות UI כתובים כ-string ספרותיים
  בעברית בתוך ה-JS עצמו (`MONTHS`, `DAY_NM`, טקסטים בתבניות).
- **פונקציות עזר תאריך** — `todayStr`, `dateStr`, `fmtDate`, `fmtDay`, `slots` — כל
  לוגיקת התאריכים/השעות עוברת דרכן; אל תשכפלו לוגיקת פורמט תאריך במקום אחר.

---

## Entities הראשיים

| Entity | תיאור | מיוצג היום כ- |
|--------|-------|---------------|
| `Service` | טיפולים: שם, מחיר, משך, קטגוריה | `S.services[]` |
| `Booking` | תורים: לקוח, טיפול, תאריך, שעה | `S.bookings[]` |
| `Client` | לקוחות: פרופיל, היסטוריה, סוג עור | עדיין לא קיים כ-entity נפרד (שם+טלפון בתוך `Booking` בלבד) |
| `Schedule` | שעות עבודה לכל יום בשבוע | `S.schedule{0-6}` |
| `SalonSettings` | הגדרות: שם, PIN, tagline | `S.salonName` / `S.tagline` / `S.pin` |

> כשבונים schema ב-Supabase — אלו ה-entities להתחיל מהם, אבל שימו לב ש-`Client`
> עדיין לא מנורמל בקוד הנוכחי.

---

## Design System

- **Palette**: Espresso (#3A2318) + Terracotta (#B06A4A) + Sand/Blush — מוגדרים כ-CSS
  variables ב-`:root` (`--espresso`, `--terracotta`, `--sand`, `--blush`, `--parch`, `--ivory`...)
- **Fonts**: Cormorant Garamond (display, `--font-display`) + Heebo (body, `--font-body`)
- **Direction**: RTL מלא — `<html lang="he" dir="rtl">`, `direction:rtl` על ה-`body`
- **Mobile-first**: 390px viewport ראשוני
- **חוק ברזל**: שימוש תמיד ב-CSS variables (`var(--terracotta)` וכו'), **אסור** hardcoded
  hex colors בקוד חדש.

---

## כללי עבודה

### UX / עיצוב
1. **עברית RTL** — כל טקסט UI בעברית, `dir="rtl"`
2. **Mobile-first** — תמיד בדוק ב-390px
3. **Design tokens** — השתמש תמיד ב-CSS variables, לא hardcoded colors
4. **חווית משתמש קודמת לכל** — כל feature חדש חייב להיות פשוט ואינטואיטיבי

### אבטחה (Security First)
5. **RLS** — כל טבלת Supabase חייבת RLS — אין יוצאים מהכלל
6. **Secrets** — לעולם לא ב-git, תמיד ב-.env.local
7. **PIN** — לא לשנות default 1234 בלי hash. שימו לב: כיום ה-PIN מושווה כ-plain string
   בצד הלקוח (`pinStr === S.pin`) — זה תקין לפרוטוטייפ סטטי, אבל **חובה להחליף בבדיקה
   צד-שרת + hashing** ברגע שמתחברים ל-backend אמיתי.
8. **בדיקת אבטחה** — כל feature חדש עובר `/security-review` לפני merge
9. **Audit trail** — כל פעולה רגישה (מחיקה, עדכון מחיר, שינוי PIN) נרשמת ב-audit_log

### קוד ואיכות
10. **תיעוד ב-GitHub** — כל שינוי משמעותי מגיע עם commit message ברור
11. **נתונים פתוחים** — APIs ונתוני דוגמה זמינים ב-GitHub לצורך פיתוח ובדיקות
12. **שמירה על מבנה חד-קובצי** — אלא אם התבקש אחרת, היצמדו למבנה הקיים (CSS+HTML+JS
    באותו `index.html`); אל תפצלו לקבצים/build step בלי לתאם עם המשתמש.

---

## Development Workflow

אין build step, אין dependencies, אין שרת חובה — קובץ HTML סטטי יחיד:

```bash
# פתיחה ישירה בדפדפן
open index.html

# או דרך שרת מקומי (מומלץ ל-RTL/fonts/CSP תקינים)
python3 -m http.server 8080
# ואז גלשו ל- http://localhost:8080

# בדיקות E2E (Playwright — ראו /playwright-crm)
npx playwright test

# Supabase types (כש-DB אמיתי יחובר)
npx supabase gen types typescript --project-id [id] > types/supabase.ts
```

**איך לבדוק שינוי:**
1. פתחו/רעננו את `index.html` בדפדפן (390px viewport קודם כל).
2. עברו את 3 הטאבים: הזמנת תור (אשף 4 שלבים מלא, כולל מסך הצלחה), אודות, ניהול
   (PIN ברירת מחדל `1234`).
3. זכרו: רענון דף מאפס state — אם בדקתם "שמירה", זה תקין שהיא נעלמת ברענון
   (זו לא רגרסיה, זה המצב הנוכחי של הקוד ללא פרסיסטנציה).
4. השתמשו ב-`/verify` או `/run` כדי להריץ ולבדוק בפועל לפני שמדווחים שתכונה הושלמה.

---

## סקילים זמינים

### מותאמים אישית (`.claude/skills/`)

| פקודה | קובץ | תיאור |
|-------|------|-------|
| `/liders-crm` | `liders-crm.md` | ארכיטקטורה, entities, workflow |
| `/playwright-crm` | `playwright-crm.md` | בדיקות E2E + CI |
| `/figma-crm-ui` | `figma-crm-ui.md` | עיצוב Figma + Canva, RTL |
| `/supabase-security` | `supabase-security.md` | RLS, auth, secrets, audit |
| `/crm-agents` | `crm-agents.md` | AI: booking, reminders, insights |
| `/competitor-research` | `competitor-research.md` | מחקר שוק + בידולים |
| `/security-guardian` | `security-guardian.md` | data protection, incident response |
| `/design-system` | `design-system.md` | tokens, components, RTL specs |
| `/crm-live-data` | `crm-live-data.md` | ⭐ שאיבת נתונים חיים מכל MCPs |
| `/mali-marketing` | `mali-marketing.md` | מנהל שיווק דיגיטלי מלא למלי יופי ועור |
| `/liders-marketing` | `liders-marketing.md` | מנהל שיווק דיגיטלי אוניברסלי לעסקי Liders CRM |

> **חשוב**: כשכותבים סקיל חדש ל-`.claude/skills/*.md`, ה-hook ב-
> `.claude/update-skills-hook.sh` יזכיר אוטומטית לעדכן גם את `.claude/SKILLSEXPORT.md`.

### מובנים ב-Claude Code (תמיד זמינים)

| פקודה | תיאור |
|-------|-------|
| `/code-review` | ביקורת קוד |
| `/security-review` | ביקורת אבטחה |
| `/deep-research` | מחקר עם web search |
| `/verify` | אימות שינוי עובד |
| `/run` | הרצת האפליקציה |
| `/init` | יצירת/עדכון CLAUDE.md |
| `/update-config` | עדכון settings.json |

---

## MCP Servers מחוברים

| שרת | UUID prefix | שימוש |
|-----|-------------|-------|
| Supabase | `f474d5bb` | DB, migrations, RLS, edge functions, logs |
| Google Calendar | `6368118b` | ניהול תורים בלוח שנה |
| Gmail | `4e93495e` | תקשורת לקוחות |
| Make.com | `194941ca` | WhatsApp, SMS automations |
| Figma | `88a7dadd` | UI design, components, design tokens |
| Canva | `3f33a9a8` | Marketing materials, mockups |
| Notion | `97537a26` | תיעוד, dashboard |
| Airtable | `273af94e` | נתוני לקוחות, reporting |
| Miro | `4a81aac9` | ארכיטקטורה, diagrams |
| Mermaid | `faee5592` | ERD, flowcharts |
| Forms | `b0914b59` | יצירת טפסים, ניתוח תגובות |
| Google Drive | `c83a2f70` | קבצים: חיפוש, קריאה, שיתוף |
| GitHub | `github` | version control, PRs, issues |

> רשימת ההרשאות בפועל ל-MCP tools מוגדרת ב-`.claude/settings.json` (allow/deny).
> אם כלי MCP לא זמין ישירות — חפשו אותו עם `ToolSearch` לפני שמדווחים שהוא חסר.

---

## Files

```
index.html              — האפליקציה המלאה (HTML + CSS + JS, ~1300 שורות, חד-קובצי)
README.md               — כמעט ריק (placeholder)
install-skills.sh       — סקריפט להתקנת חבילת ה-skills בפרויקט חדש
CLAUDE.md               — קובץ זה
.claude/
  settings.json         — permissions (allow/deny), env vars, hooks
  update-skills-hook.sh — PostToolUse hook: מזכיר לעדכן SKILLSEXPORT.md בעת כתיבת סקיל חדש
  SKILLSEXPORT.md       — קטלוג מלא של כל הסקילים, להעתקה לפרויקטים חדשים
  skills/
    liders-crm.md
    playwright-crm.md
    figma-crm-ui.md
    supabase-security.md
    crm-agents.md
    competitor-research.md
    security-guardian.md
    design-system.md
    crm-live-data.md
    mali-marketing.md
    liders-marketing.md
```

---

## Quick Commands

```bash
# הרץ לוקאל
open index.html  # או: python3 -m http.server 8080

# בדיקות E2E
npx playwright test

# Supabase types
npx supabase gen types typescript --project-id [id] > types/supabase.ts

# התקנת חבילת הסקילים בפרויקט חדש (curl one-liner)
curl -fsSL https://raw.githubusercontent.com/elgrablidudu-prog/-/main/install-skills.sh | bash
```
