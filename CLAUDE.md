# CLAUDE.md — Liders CRM Platform

## חזון הפרויקט

**המטרה הסופית:** לבנות פלטפורמת CRM כ-Service (SaaS) —
מערכת שמאפשרת לעסקים קטנים לנהל לקוחות, תורים ותשלומים בצורה פשוטה ואינטואיטיבית.

דגש מרכזי:
- **חווית משתמש** מעולה — פשוט, מהיר, יפה
- **אבטחה** — RLS, Supabase Auth, ללא secrets ב-git
- **מדרגיות** — כל עסק מקבל CRM מותאם, מנוהל דרך Admin Dashboard

---

## מה הפרויקט הזה

**Liders CRM** — פלטפורמת ניהול לעסקים.

**Admin Dashboard** (`index.html`) — לוח בקרה פנימי של Liders לניהול לקוחות הפלטפורמה:
- ניהול חשבונות לקוחות (`liders_accounts`)
- מעקב תשלומים וחשבוניות (`liders_invoices`)
- גישה מהירה ל-CRM של כל לקוח
- כניסה עם Supabase Auth (`Liders.crm@gmail.com`)

---

## Stack

- **Frontend**: HTML + CSS + Vanilla JS (RTL, עברית)
- **Database**: Supabase (PostgreSQL + RLS) — project: `scyfywvzoogfrlalgftv`
- **Auth**: Supabase Auth (email/password)
- **Automations**: Make.com (WhatsApp, Gmail)
- **Calendar**: Google Calendar MCP
- **Design**: Figma + Canva MCP
- **Architecture**: Miro MCP
- **Docs**: Notion MCP
- **Storage**: Airtable MCP
- **AI Agents**: Anthropic Claude API

---

## Entities הראשיים — Admin Dashboard

| Entity | טבלה | תיאור |
|--------|------|-------|
| `LidersAccount` | `liders_accounts` | לקוחות פלטפורמה: עסק, בעל, תוכנית, סטטוס, MRR |
| `LidersInvoice` | `liders_invoices` | חשבוניות: סכום, סטטוס, תאריכי פירעון ותשלום |

---

## Design System — Admin Dashboard

- **Palette**: Navy (#0F172A) + Slate (#1E293B) + Gold (#F59E0B) + Semantic colors
- **Font**: Heebo (body + display)
- **Direction**: RTL מלא
- **Theme**: Dark professional SaaS admin
- **Mobile-first**: 390px viewport

---

## סקילים זמינים

### מותאמים אישית (`.claude/skills/`)

| פקודה | קובץ | תיאור |
|-------|------|-------|
| `/liders-crm` | `liders-crm.md` | ארכיטקטורה, entities, workflow של פלטפורמת Liders |
| `/playwright-crm` | `playwright-crm.md` | בדיקות E2E + CI |
| `/figma-crm-ui` | `figma-crm-ui.md` | עיצוב Figma + Canva, RTL, dark theme |
| `/supabase-security` | `supabase-security.md` | RLS, auth, secrets, audit |
| `/crm-agents` | `crm-agents.md` | AI agents לפלטפורמה |
| `/competitor-research` | `competitor-research.md` | מחקר שוק CRM SaaS |
| `/security-guardian` | `security-guardian.md` | data protection, incident response |
| `/design-system` | `design-system.md` | tokens, components, dark theme specs |
| `/crm-live-data` | `crm-live-data.md` | שאיבת נתונים חיים מכל MCPs |
| `/liders-marketing` | `liders-marketing.md` | מנהל שיווק דיגיטלי לפלטפורמה |

### מובנים ב-Claude Code (תמיד זמינים)

| פקודה | תיאור |
|-------|-------|
| `/code-review` | ביקורת קוד |
| `/security-review` | ביקורת אבטחה |
| `/deep-research` | מחקר עם web search |
| `/verify` | אימות שינוי עובד |
| `/run` | הרצת האפליקציה |

---

## MCP Servers מחוברים

| שרת | UUID prefix | שימוש |
|-----|-------------|-------|
| Supabase | `f474d5bb` | DB, migrations, RLS, logs |
| Google Calendar | `6368118b` | ניהול לוח שנה |
| Gmail | `4e93495e` | תקשורת |
| Make.com | `194941ca` | WhatsApp, SMS automations |
| Figma | `88a7dadd` | UI design, components |
| Canva | `3f33a9a8` | Marketing materials |
| Notion | `97537a26` | תיעוד, dashboard |
| Airtable | `273af94e` | נתונים, reporting |
| Miro | `4a81aac9` | ארכיטקטורה, diagrams |
| Mermaid | `faee5592` | ERD, flowcharts |
| GitHub | `github` | version control |

---

## Files

```
index.html          — Admin Dashboard של Liders CRM (HTML + CSS + JS)
CLAUDE.md           — קובץ זה
.claude/
  settings.json     — permissions, env vars
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
    liders-marketing.md
```

---

## כללי עבודה

### UX / עיצוב
1. **עברית RTL** — כל טקסט UI בעברית, `dir="rtl"`
2. **Mobile-first** — תמיד בדוק ב-390px
3. **Design tokens** — השתמש תמיד ב-CSS variables, לא hardcoded colors
4. **Dark theme** — Navy/Slate/Gold, לא בהיר

### אבטחה (Security First)
5. **RLS** — כל טבלת Supabase חייבת RLS — אין יוצאים מהכלל
6. **Secrets** — לעולם לא ב-git, תמיד ב-.env.local
7. **Auth** — Supabase email/password, לא PIN
8. **בדיקת אבטחה** — כל feature חדש עובר `/security-review` לפני merge
9. **Audit trail** — כל פעולה רגישה נרשמת

### קוד ואיכות
10. **תיעוד ב-GitHub** — כל שינוי משמעותי מגיע עם commit message ברור
11. **Single file** — האפליקציה כולה ב-`index.html` כל עוד אפשרי

---

## Quick Commands

```bash
# הרץ לוקאל
open index.html  # או: python3 -m http.server 8080

# בדיקות E2E
npx playwright test

# Supabase types
npx supabase gen types typescript --project-id scyfywvzoogfrlalgftv > types/supabase.ts
```
