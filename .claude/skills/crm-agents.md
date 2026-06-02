# CRM AI Agents — מלי יופי ועור

## פקודה: `/crm-agents`

סוכני AI: booking assistant, תזכורות, insights, ניתוח לקוחות.

---

## סוכן 1: Booking Assistant

מטרה: סוכן שמטפל בהזמנות דרך WhatsApp/צ'אט

```typescript
import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic();

const BOOKING_SYSTEM_PROMPT = `
אתה עוזר הזמנות של מלי • יופי ועור בטבריה.
אתה עונה בעברית, בשפה חמה ומקצועית.

שירותים זמינים:
- טיפול פנים קלאסי — ₪220, 60 דקות
- טיפול פנים עמוק (KB Pure) — ₪320, 75 דקות
- טיפול אנטי-אייג'ינג — ₪380, 75 דקות
- טיפול אקנה ובעיות עור — ₪280, 60 דקות
- פדיקור רפואי — ₪200, 60 דקות
- פדיקור + לק — ₪240, 70 דקות
- הסרת שיער בשעווה (פנים) — ₪80, 25 דקות
- עיצוב גבות — ₪70, 20 דקות

שעות פעילות: א'-ה' 09:00-17:00, ו' 09:00-13:30
סגור: שבת

תמיד:
1. שאל איזה טיפול מעניין
2. הצע תאריך ושעה פנויה
3. אשר שם ומספר טלפון
4. שלח אישור
`;

async function bookingAgent(userMessage: string, history: any[]) {
  const response = await client.messages.create({
    model: 'claude-opus-4-8',
    max_tokens: 1024,
    system: BOOKING_SYSTEM_PROMPT,
    messages: [
      ...history,
      { role: 'user', content: userMessage }
    ],
    tools: [
      {
        name: 'check_availability',
        description: 'בדוק זמינות תורים לתאריך ושירות',
        input_schema: {
          type: 'object',
          properties: {
            date: { type: 'string', description: 'YYYY-MM-DD' },
            service_id: { type: 'number' }
          },
          required: ['date', 'service_id']
        }
      },
      {
        name: 'create_booking',
        description: 'צור הזמנה חדשה',
        input_schema: {
          type: 'object',
          properties: {
            client_name: { type: 'string' },
            phone: { type: 'string' },
            service_id: { type: 'number' },
            date: { type: 'string' },
            time: { type: 'string' },
            notes: { type: 'string' }
          },
          required: ['client_name', 'phone', 'service_id', 'date', 'time']
        }
      }
    ]
  });
  return response;
}
```

---

## סוכן 2: Reminder Agent

מטרה: שליחת תזכורות אוטומטיות 24 שעות לפני תור

```typescript
// Make.com Webhook trigger — runs daily at 10:00
async function sendReminders() {
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const dateStr = tomorrow.toISOString().split('T')[0];

  // שלוף תורים למחר מ-Supabase
  const { data: bookings } = await supabase
    .from('bookings')
    .select('*')
    .eq('date', dateStr)
    .eq('status', 'confirmed');

  for (const booking of bookings ?? []) {
    await sendWhatsAppReminder(booking);
  }
}

async function sendWhatsAppReminder(booking: Booking) {
  const message = `
שלום ${booking.client_name} 😊

תזכורת לתורך מחר:
📅 ${formatDate(booking.date)} בשעה ${booking.time}
💆 ${booking.service}
💰 ₪${booking.price}

לביטול/שינוי: 050-XXXXXXX
מלי • יופי ועור 🌿
  `.trim();

  // Make.com webhook → WhatsApp
  await fetch(process.env.MAKE_WEBHOOK_URL!, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: booking.phone, message })
  });
}
```

---

## סוכן 3: Client Insights Agent

מטרה: ניתוח לקוחות, המלצות טיפולים, זיהוי לקוחות לא פעילים

```typescript
async function clientInsightsAgent(clientId: string) {
  const { data: client } = await supabase
    .from('clients')
    .select('*, bookings(*)')
    .eq('id', clientId)
    .single();

  const prompt = `
נתח את פרופיל הלקוחה הבא ותן המלצות:

שם: ${client.name}
ביקורים: ${client.total_visits}
הוצאה כוללת: ₪${client.total_spent}
ביקור אחרון: ${client.last_visit ?? 'אין'}
סוג עור: ${client.skin_type ?? 'לא ידוע'}
אלרגיות: ${client.allergies ?? 'אין'}
היסטוריית טיפולים: ${JSON.stringify(client.bookings)}

תן:
1. ניתוח קצר של הלקוחה
2. 3 המלצות טיפולים הבאים
3. האם היא בסיכון לנטישה?
4. הודעת WhatsApp מומלצת לחזרה
`;

  const response = await client.messages.create({
    model: 'claude-opus-4-8',
    max_tokens: 500,
    messages: [{ role: 'user', content: prompt }]
  });

  return response.content[0].text;
}
```

---

## סוכן 4: Revenue Analytics Agent

```typescript
async function revenueInsights(period: 'week' | 'month' | 'quarter') {
  // שאל Claude לנתח נתוני הכנסות
  const prompt = `
נתח את נתוני ההכנסות הבאים ותן insights:
[נתונים מ-Supabase]

תן:
- סה"כ הכנסות vs תקופה קודמת
- שירות הכי רווחי
- ימים/שעות עמוסים
- המלצה לתמחור
- תחזית לחודש הבא
`;
  // ...
}
```

---

## Make.com Automations

| Trigger | Action | סוכן |
|---------|--------|------|
| הזמנה חדשה | WhatsApp אישור | Booking |
| 24h לפני תור | WhatsApp תזכורת | Reminder |
| תור בוטל | SMS + Email | Booking |
| לקוח לא חזר 60 יום | WhatsApp reactivation | Insights |
| סוף שבוע | סיכום שבועי למלי | Analytics |
