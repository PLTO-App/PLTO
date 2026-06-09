# CRM AI Agents — Liders CRM Platform

## פקודה: `/crm-agents`

סוכני AI לפלטפורמת Liders: onboarding, alerts, insights, churn prediction.

---

## סוכן 1: Onboarding Assistant

מטרה: מדריך לקוח חדש בתהליך ההגדרה של ה-CRM שלו

```typescript
import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic();

const ONBOARDING_SYSTEM = `
אתה עוזר onboarding של Liders CRM.
אתה עוזר לבעלי עסקים חדשים להגדיר את מערכת ה-CRM שלהם.
עונה בעברית, שפה ברורה ומקצועית.

שלבי ה-onboarding:
1. חיבור Supabase
2. הגדרת שירותים/מוצרים
3. ייבוא לקוחות קיימים
4. חיבור WhatsApp / Gmail
5. הגדרת Make.com automations
`;

async function onboardingAgent(userMessage: string, history: any[]) {
  return await client.messages.create({
    model: 'claude-opus-4-8',
    max_tokens: 1024,
    system: ONBOARDING_SYSTEM,
    messages: [...history, { role: 'user', content: userMessage }],
    tools: [
      {
        name: 'check_setup_status',
        description: 'בדוק מצב ה-setup של לקוח',
        input_schema: {
          type: 'object',
          properties: { account_id: { type: 'string' } },
          required: ['account_id']
        }
      },
      {
        name: 'send_setup_email',
        description: 'שלח מייל הגדרה ללקוח',
        input_schema: {
          type: 'object',
          properties: {
            email: { type: 'string' },
            step: { type: 'string' }
          },
          required: ['email', 'step']
        }
      }
    ]
  });
}
```

---

## סוכן 2: Churn Detection Agent

מטרה: זיהוי לקוחות בסיכון לנטישה

```typescript
async function churnDetectionAgent() {
  const { data: accounts } = await supabase
    .from('liders_accounts')
    .select('*, liders_invoices(*)')
    .eq('status', 'active');

  for (const account of accounts ?? []) {
    const riskScore = calculateChurnRisk(account);

    if (riskScore > 0.7) {
      await alertChurnRisk(account, riskScore);
    }
  }
}

function calculateChurnRisk(account: LidersAccount): number {
  let score = 0;
  const overdueInvoices = account.liders_invoices?.filter(i => i.status === 'overdue').length ?? 0;
  if (overdueInvoices > 0) score += 0.4;
  if (account.plan === 'trial') score += 0.3;
  // חודש ללא שימוש ב-CRM
  const daysSinceUpdate = Math.floor((Date.now() - new Date(account.updated_at).getTime()) / 86400000);
  if (daysSinceUpdate > 30) score += 0.3;
  return Math.min(score, 1);
}
```

---

## סוכן 3: Revenue Insights Agent

מטרה: דוח הכנסות ותחזית MRR

```typescript
async function revenueInsightsAgent(period: 'month' | 'quarter') {
  const { data: invoices } = await supabase
    .from('liders_invoices')
    .select('*, liders_accounts(business_name, plan)')
    .eq('status', 'paid')
    .gte('paid_at', getPeriodStart(period));

  const prompt = `
נתח את נתוני ההכנסות הבאים של פלטפורמת Liders CRM:

${JSON.stringify(invoices, null, 2)}

תן:
- סה"כ הכנסות vs תקופה קודמת
- MRR לפי תוכנית (trial/basic/pro/enterprise)
- לקוחות הכי רווחיים
- תחזית חודש הבא
- המלצות להגדלת הכנסות
`;

  return await client.messages.create({
    model: 'claude-opus-4-8',
    max_tokens: 1000,
    messages: [{ role: 'user', content: prompt }]
  });
}
```

---

## סוכן 4: Invoice Reminder Agent

מטרה: שליחת תזכורות תשלום אוטומטיות

```typescript
// Make.com Webhook trigger — runs daily at 09:00
async function invoiceReminderAgent() {
  const { data: overdueInvoices } = await supabase
    .from('liders_invoices')
    .select('*, liders_accounts(owner_name, email, phone)')
    .in('status', ['pending', 'overdue'])
    .lt('due_date', new Date().toISOString().split('T')[0]);

  for (const invoice of overdueInvoices ?? []) {
    const message = `
שלום ${invoice.liders_accounts.owner_name},

תזכורת לתשלום חשבונית ${invoice.invoice_number}:
💰 סכום: ₪${invoice.amount}
📅 תאריך פירעון: ${invoice.due_date}

לתשלום ויצירת קשר: Liders.crm@gmail.com
Liders CRM 🚀
    `.trim();

    await fetch(process.env.MAKE_WEBHOOK_URL!, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: invoice.liders_accounts.phone, message })
    });
  }
}
```

---

## Make.com Automations

| Trigger | Action | סוכן |
|---------|--------|------|
| לקוח חדש נוסף | Welcome email + WhatsApp | Onboarding |
| חשבונית עוברת due_date | תזכורת תשלום | Invoice Reminder |
| plan ניסיון עומד לפוג | הצעת שדרוג | Churn Detection |
| MRR ירד | Alert לאדמין | Revenue Insights |
| סוף חודש | דוח MRR אוטומטי | Revenue Insights |
