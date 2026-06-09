# Skills Pack — Liders CRM Platform

> קובץ זה מסכם את כל הסקילים הזמינים. העתק את תיקיית `.claude/skills/` לכל repo חדש.
> **קובץ זה מתעדכן אוטומטית בכל הוספת סקיל חדש.**

---

## התקנה בפרויקט חדש — פקודה אחת

```bash
curl -fsSL https://raw.githubusercontent.com/elgrablidudu-prog/-/main/install-skills.sh | bash
```

### לאחר ההתקנה:
```bash
npx skills add supabase/agent-skills
# עדכן CLAUDE.md בפרויקט החדש
```

---

## רשימת כל הסקילים

### סקילים מותאמים (`.claude/skills/`)

| סקיל | פקודה | תיאור | נוצר |
|------|-------|-------|------|
| **CRM Workflow** | `/liders-crm` | ארכיטקטורה, entities, workflow של פלטפורמת Liders | 2026-06-02 |
| **Playwright E2E** | `/playwright-crm` | בדיקות אוטומטיות + CI integration | 2026-06-02 |
| **Figma UI/UX** | `/figma-crm-ui` | עיצוב dark theme עם Figma + Canva MCP, RTL | 2026-06-02 |
| **Supabase Security** | `/supabase-security` | RLS policies, auth, secrets, audit | 2026-06-02 |
| **CRM Agents** | `/crm-agents` | AI agents: onboarding, churn, insights, reminders | 2026-06-02 |
| **Competitor Research** | `/competitor-research` | מחקר מתחרים CRM SaaS + בידולים | 2026-06-02 |
| **Security Guardian** | `/security-guardian` | הגנת data, checklist, incident response | 2026-06-02 |
| **Design System Pro** | `/design-system` | dark theme tokens, components, RTL specs | 2026-06-02 |
| **CRM Live Data** ⭐ | `/crm-live-data` | שאיבת נתונים חיים מ-Supabase, Gmail, Make, Notion | 2026-06-02 |
| **Liders Marketing** | `/liders-marketing` | מנהל שיווק דיגיטלי לפלטפורמה — אסטרטגיה, תוכן, קופי | 2026-06-03 |

### סקילים מ-npm (`.agents/skills/`)

| סקיל | פקודה | תיאור |
|------|-------|-------|
| **Supabase** | `/supabase` | Best practices מלאים לכל Supabase |
| **Postgres Best Practices** | `/supabase-postgres-best-practices` | אופטימיזציה, indexing, RLS performance |

### סקילים מובנים ב-Claude Code (תמיד זמינים)

| פקודה | תיאור |
|-------|-------|
| `/code-review` | ביקורת קוד |
| `/security-review` | ביקורת אבטחה מלאה |
| `/deep-research` | מחקר מעמיק עם web search |
| `/claude-api` | Anthropic SDK integration |
| `/verify` | אימות שינוי עובד |
| `/run` | הרצת האפליקציה |
| `/init` | יצירת CLAUDE.md |
| `/update-config` | עדכון settings.json |

---

## MCP Servers — בדוק שמחוברים

| שרת | UUID prefix | שימוש |
|-----|-------------|-------|
| **Supabase** | `f474d5bb` | DB, migrations, RLS, edge functions |
| **Figma** | `88a7dadd` | UI design, components, tokens |
| **Canva** | `3f33a9a8` | Marketing materials |
| **Miro** | `4a81aac9` | Architecture diagrams |
| **Make.com** | `194941ca` | Automations (WhatsApp, SMS, email) |
| **Notion** | `97537a26` | Documentation |
| **Google Calendar** | `6368118b` | Calendar management |
| **Gmail** | `4e93495e` | Client communications |
| **Airtable** | `273af94e` | Data storage, reporting |
| **Mermaid** | `faee5592` | ERD + flow diagrams |

---

## Quick Start — פרויקט חדש ב-5 דקות

```bash
# 1. Init repo
git init my-crm-project && cd my-crm-project

# 2. העתק skills
mkdir -p .claude/skills
cp -r /path/to/source/.claude/skills/* .claude/skills/
cp /path/to/source/.claude/settings.json .claude/settings.json

# 3. התקן Supabase skill
npx skills add supabase/agent-skills

# 4. צור .env.local
echo "SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
ANTHROPIC_API_KEY=
MAKE_WEBHOOK_URL=" > .env.local

# 5. הרץ /init ליצירת CLAUDE.md מותאם
```

---

## הוספת סקיל חדש — נוהל

```bash
# 1. צור קובץ:
touch .claude/skills/my-new-skill.md

# 2. SKILLSEXPORT.md יתעדכן אוטומטית (hook פעיל)

# 3. עדכן CLAUDE.md manually אם צריך
```
