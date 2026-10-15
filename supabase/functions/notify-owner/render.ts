// Turns a validated notify-owner payload into the subject and HTML of the owner
// email. Pure code (no Deno or network APIs), so it is unit-tested with plain
// Node (see supabase/tests/notify-owner-render.test.ts).
//
// Every value comes from a signed-in user, so each one is escaped before it is
// placed in the HTML.

export function escapeHtml(v: string): string {
  return v
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const LABELS: Record<string, string> = {
  ticket_id: 'מזהה פנייה',
  tenant_name: 'עסק',
  tenant: 'עסק',
  tenant_id: 'מזהה עסק',
  agent_name: 'שם המשתמש',
  agent_email: 'אימייל',
  message: 'הודעה',
  response: 'תשובה',
  plan: 'תוכנית',
  plan_name: 'שם התוכנית',
  plan_price: 'מחיר',
  name: 'שם',
  phone: 'טלפון',
  need: 'הצורך',
  text: 'הצעה',
  category: 'קטגוריה',
};

const TITLES: Record<string, string> = {
  'support.needs_human': 'פנייה בתמיכה שממתינה למענה אנושי',
  'support.admin_replied': 'נשלחה תשובה לפנייה בתמיכה',
  upgrade_request: 'בקשת שדרוג תוכנית',
  full_service_request: 'בקשה לשירות מלא',
  idea_suggestion: 'הצעת רעיון חדשה',
};

// The subject is one line: no line breaks, capped in length.
function oneLine(v: string, max: number): string {
  return v.replace(/\s+/g, ' ').trim().slice(0, max);
}

export function renderEmail(payload: Record<string, string>): { subject: string; html: string } {
  const event = payload.event;
  const title = TITLES[event] ?? 'התראה חדשה';

  let subject = `PLTO: ${title}`;
  if (event === 'upgrade_request' && payload.plan_name) subject += `, ${oneLine(payload.plan_name, 60)}`;
  if (event === 'full_service_request' && payload.name) subject += `, ${oneLine(payload.name, 60)}`;

  const rows = Object.entries(payload)
    .filter(([k]) => k !== 'event' && k in LABELS)
    .map(([k, v]) => {
      const value = escapeHtml(v).replace(/\r?\n/g, '<br>');
      return `<tr>`
        + `<td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;font-weight:600;white-space:nowrap;vertical-align:top;">${LABELS[k]}</td>`
        + `<td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;">${value}</td>`
        + `</tr>`;
    })
    .join('');

  const html = `<div dir="rtl" style="font-family:Arial,Helvetica,sans-serif;color:#0F1F3D;max-width:560px;">`
    + `<h2 style="margin:0 0 12px;font-size:18px;">${escapeHtml(title)}</h2>`
    + `<table style="width:100%;border-collapse:collapse;font-size:14px;">${rows}</table>`
    + `</div>`;

  return { subject: subject.slice(0, 150), html };
}
