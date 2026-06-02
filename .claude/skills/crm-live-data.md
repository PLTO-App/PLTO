# CRM Live Data — שאיבת נתונים חיים

## פקודה: `/crm-live-data`

סקיל לשאיבה, סנכרון וניתוח נתונים חיים מכל מערכות ה-MCP המחוברות:
Supabase, Google Calendar, Gmail, Make.com, Airtable, Notion.

---

## מה הסקיל הזה עושה

כשמפעילים `/crm-live-data` Claude:
1. **שולף נתונים עדכניים** מ-Supabase (תורים, לקוחות, שירותים)
2. **מסנכרן עם Google Calendar** (בדיקת conflicts, הוספת תורים)
3. **מושך דואר מ-Gmail** (בקשות הזמנה, ביטולים)
4. **בודק Make.com** (automations שפועלות/נכשלות)
5. **מעדכן Notion** (דשבורד, דוחות שבועיים)
6. **מנתח ומסכם** את מצב המערכת

---

## Supabase — שאיבת נתונים

```typescript
// פונקציות שאיבה ראשיות

async function getLiveBookings(date?: string) {
  // mcp: mcp__f474d5bb__execute_sql
  const sql = date
    ? `SELECT * FROM bookings WHERE date = '${date}' ORDER BY time`
    : `SELECT * FROM bookings WHERE date >= CURRENT_DATE ORDER BY date, time LIMIT 50`;
  return await supabase.from('bookings').select('*').gte('date', date ?? new Date().toISOString().split('T')[0]);
}

async function getClientHistory(phone: string) {
  return await supabase
    .from('bookings')
    .select('*')
    .eq('phone', phone)
    .order('date', { ascending: false });
}

async function getRevenueStats(period: 'week' | 'month') {
  const sql = `
    SELECT
      COUNT(*) as total_bookings,
      SUM(price) as total_revenue,
      AVG(price) as avg_price,
      service,
      COUNT(*) as service_count
    FROM bookings
    WHERE date >= CURRENT_DATE - INTERVAL '1 ${period}'
      AND status NOT IN ('cancelled', 'no_show')
    GROUP BY service
    ORDER BY service_count DESC
  `;
  // mcp: execute_sql(sql)
}
```

---

## Google Calendar — סנכרון תורים

```typescript
// mcp: mcp__6368118b__list_events

async function syncCalendarWithBookings() {
  // 1. שלוף תורים מ-Supabase
  const bookings = await getLiveBookings();

  // 2. שלוף events מ-Google Calendar
  // mcp__6368118b__list_events({
  //   calendarId: 'mali-beauty@gmail.com',
  //   timeMin: new Date().toISOString(),
  //   maxResults: 50
  // })

  // 3. מצא conflicts ודיווח
}

async function addBookingToCalendar(booking: Booking) {
  // mcp__6368118b__create_event({
  //   summary: `${booking.service} — ${booking.client_name}`,
  //   description: `טלפון: ${booking.phone}\nהערות: ${booking.notes}`,
  //   start: { dateTime: `${booking.date}T${booking.time}:00`, timeZone: 'Asia/Jerusalem' },
  //   end: { dateTime: calculateEnd(booking), timeZone: 'Asia/Jerusalem' },
  //   colorId: '3'  // sage green
  // })
}
```

---

## Gmail — בקשות ובקרה

```typescript
// mcp: mcp__4e93495e__search_threads

async function checkBookingRequests() {
  // חפש הזמנות שהגיעו דרך אימייל
  // mcp__4e93495e__search_threads({
  //   query: 'subject:(תור OR הזמנה OR booking) is:unread'
  // })
}

async function checkCancellations() {
  // mcp__4e93495e__search_threads({
  //   query: 'subject:(ביטול OR cancel) newer_than:1d'
  // })
}
```

---

## Make.com — בדיקת Automations

```typescript
// mcp: mcp__194941ca__scenarios_list + executions_list

async function checkAutomationHealth() {
  // 1. רשימת כל הסצנריות
  // mcp__194941ca__scenarios_list()

  // 2. בדוק executions אחרונות
  // mcp__194941ca__executions_list({ limit: 20 })

  // 3. דווח על כשלים
  const failedExecutions = executions.filter(e => e.status === 'error');
  return failedExecutions;
}
```

---

## Notion — עדכון Dashboard

```typescript
// mcp: mcp__97537a26__notion-update-page

async function updateNotionDashboard(stats: RevenueStats) {
  // mcp__97537a26__notion-search({ query: 'CRM Dashboard מלי' })
  // מצא pageId
  // mcp__97537a26__notion-update-page({
  //   pageId,
  //   properties: {
  //     'הכנסות השבוע': { number: stats.weekly_revenue },
  //     'תורים השבוע': { number: stats.weekly_bookings },
  //     'עדכון אחרון': { date: new Date().toISOString() }
  //   }
  // })
}
```

---

## Airtable — סנכרון לקוחות

```typescript
// mcp: mcp__273af94e__list_records_for_table

async function syncClientsToAirtable() {
  // 1. שלוף לקוחות מ-Supabase
  const clients = await supabase.from('clients').select('*');

  // 2. עדכן/צור ב-Airtable
  // mcp__273af94e__search_bases({ query: 'מלי CRM' })
  // mcp__273af94e__update_records_for_table(...)
}
```

---

## Live Status Report — `/crm-live-data status`

כשמריצים עם פרמטר `status`, Claude יפיק דוח כזה:

```
📊 דוח מערכת — מלי יופי ועור
═══════════════════════════════
📅 תאריך: [היום]

🗓️  תורים היום: X תורים
   הבא: [שם] — [שעה] — [שירות]

📆 תורים השבוע: X | הכנסה צפויה: ₪X

👥 לקוחות חדשות החודש: X
   לקוחות לא פעילות (>60 יום): X

⚙️  Make.com: X automations פעילות | X כשלים
📧  Gmail: X הודעות לא נקראו

🔴 דורש תשומת לב:
   - [רשימת בעיות אם יש]
```

---

## הוראות הפעלה

```bash
# בשיחה עם Claude:
/crm-live-data              # שאיבה כללית
/crm-live-data status       # דוח מלא
/crm-live-data today        # תורים היום בלבד
/crm-live-data week         # סיכום שבועי
/crm-live-data client [phone]  # היסטוריית לקוח ספציפי
/crm-live-data sync-calendar   # סנכרון עם Google Calendar
/crm-live-data check-automations # בדיקת Make.com
```
