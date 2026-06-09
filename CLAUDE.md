# CLAUDE.md — Liders CRM

## הפרויקט

**Liders CRM** — מערכת SaaS לניהול נדל"ן: לידים, נכסים, שוכרים, סוכנים, pipeline ועסקאות.

---

## Stack

- **Frontend**: (בפיתוח)
- **Database**: Supabase (PostgreSQL + RLS) — project: `liders-crm` (`scyfywvzoogfrlalgftv`)
- **Auth**: Supabase Auth
- **Automations**: Make.com
- **AI Agents**: Anthropic Claude API

---

## Supabase — טבלאות קיימות

| טבלה | תיאור |
|------|-------|
| `liders_accounts` | חשבונות לקוח במערכת |
| `liders_invoices` | חשבוניות |
| `properties` | נכסים |
| `showings` | ביקורים/הצגות נכס |
| `agent_users` | סוכנים |
| `tenants` | שוכרים |
| `pipeline_stages` | שלבי pipeline |
| `leads` | לידים |
| `activities` | פעילויות |
| `tasks` | משימות |
| `audit_log` | יומן ביקורת |

---

## MCP Servers

| שרת | UUID prefix | שימוש |
|-----|-------------|-------|
| Supabase | `f474d5bb` | DB, migrations, RLS |
| Google Calendar | `6368118b` | לוח זמנים |
| Gmail | `4e93495e` | תקשורת |
| Make.com | `194941ca` | אוטומציות |
| Figma | `88a7dadd` | UI design |
| Canva | `3f33a9a8` | מרקטינג |
| Notion | `97537a26` | תיעוד |
| Airtable | `273af94e` | נתונים |
| Miro | `4a81aac9` | ארכיטקטורה |
| GitHub | `github` | version control |

---

## כללי עבודה

1. **RLS על כל טבלה** — אין יוצאים מהכלל
2. **Secrets** — לא ב-git, תמיד ב-.env.local
3. **Audit trail** — פעולות רגישות נרשמות ב-`audit_log`
4. **Security review** לפני כל merge
