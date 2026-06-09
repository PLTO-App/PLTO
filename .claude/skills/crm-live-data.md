# CRM Live Data — שאיבת נתונים חיים

## פקודה: `/crm-live-data`

סקיל לשאיבה, סנכרון וניתוח נתונים חיים מכל מערכות ה-MCP:
Supabase, Google Calendar, Gmail, Make.com, Airtable, Notion.

---

## מה הסקיל הזה עושה

כשמפעילים `/crm-live-data` Claude:
1. **שולף נתונים עדכניים** מ-Supabase (liders_accounts, liders_invoices)
2. **בודק Make.com** (automations פעילות/כשלים)
3. **מושך דואר מ-Gmail** (בקשות לקוחות, תשלומים)
4. **מעדכן Notion** (דשבורד, דוחות)
5. **מנתח ומסכם** את מצב הפלטפורמה

---

## Supabase — שאיבת נתונים

```typescript
// Accounts פעילים
async function getLiveAccounts() {
  return await supabase
    .from('liders_accounts')
    .select('*')
    .order('created_at', { ascending: false });
}

// חשבוניות פתוחות
async function getOpenInvoices() {
  return await supabase
    .from('liders_invoices')
    .select('*, liders_accounts(business_name, owner_name, phone)')
    .in('status', ['pending', 'overdue']);
}

// MRR חישוב
async function getMRR() {
  const { data } = await supabase
    .from('liders_accounts')
    .select('mrr, plan, status')
    .eq('status', 'active');
  return (data ?? []).reduce((sum, a) => sum + Number(a.mrr), 0);
}

// Revenue stats
async function getRevenueStats(period: 'week' | 'month') {
  // mcp__f474d5bb__execute_sql
  const sql = `
    SELECT
      status,
      COUNT(*) as count,
      SUM(amount) as total
    FROM liders_invoices
    WHERE created_at >= NOW() - INTERVAL '1 ${period}'
    GROUP BY status
  `;
}
```

---

## Gmail — בקשות ותשלומים

```typescript
// mcp__4e93495e__search_threads

async function checkPaymentEmails() {
  // mcp__4e93495e__search_threads({
  //   query: 'subject:(תשלום OR invoice OR חשבונית) is:unread'
  // })
}

async function checkNewClientRequests() {
  // mcp__4e93495e__search_threads({
  //   query: 'subject:(הצטרפות OR demo OR Liders CRM) newer_than:7d'
  // })
}
```

---

## Make.com — בדיקת Automations

```typescript
// mcp__194941ca__scenarios_list + executions_list

async function checkAutomationHealth() {
  // 1. רשימת סצנריות פעילות
  // mcp__194941ca__scenarios_list()

  // 2. executions אחרונות
  // mcp__194941ca__executions_list({ limit: 20 })

  // 3. דווח על כשלים
  const failed = executions.filter(e => e.status === 'error');
  return failed;
}
```

---

## Notion — עדכון Dashboard

```typescript
// mcp__97537a26__notion-update-page

async function updateNotionDashboard(stats: PlatformStats) {
  // mcp__97537a26__notion-search({ query: 'Liders CRM Dashboard' })
  // מצא pageId
  // mcp__97537a26__notion-update-page({
  //   pageId,
  //   properties: {
  //     'MRR': { number: stats.mrr },
  //     'Active Accounts': { number: stats.activeAccounts },
  //     'Open Invoices': { number: stats.openInvoices },
  //     'Last Updated': { date: new Date().toISOString() }
  //   }
  // })
}
```

---

## Airtable — גיבוי נתונים

```typescript
// mcp__273af94e__list_records_for_table

async function syncAccountsToAirtable() {
  const accounts = await getLiveAccounts();
  // mcp__273af94e__search_bases({ query: 'Liders CRM' })
  // mcp__273af94e__update_records_for_table(...)
}
```

---

## Live Status Report — `/crm-live-data status`

```
📊 דוח פלטפורמה — Liders CRM
═══════════════════════════════
📅 תאריך: [היום]

👥 חשבונות פעילים: X / סה"כ: Y
💰 MRR כולל: ₪X
   - Basic: X × ₪149 = ₪X
   - Pro: X × ₪299 = ₪X
   - Enterprise: X × ₪599 = ₪X

📄 חשבוניות:
   - ממתינות לתשלום: X (₪X)
   - בחריגה: X (₪X)
   - שולם החודש: ₪X

⚙️  Make.com: X automations פעילות | X כשלים
📧  Gmail: X הודעות לא נקראו

🔴 דורש טיפול:
   - [רשימת בעיות]
```

---

## הוראות הפעלה

```bash
/crm-live-data              # שאיבה כללית
/crm-live-data status       # דוח מלא
/crm-live-data invoices     # חשבוניות פתוחות בלבד
/crm-live-data mrr          # מצב MRR עדכני
/crm-live-data check-automations  # בדיקת Make.com
/crm-live-data sync-notion  # עדכון דשבורד Notion
```
