// Pure helpers for twilio-whatsapp. No Deno or network APIs here, so they can be
// unit-tested with plain Node (see supabase/tests/twilio-whatsapp-guard.test.ts).
//
// The function only ever sends a short fixed notification to the tenant's OWN
// number. The destination and the wording are decided on the server: the browser
// sends an event name and a few small values, never a phone number or free text.

export const EVENTS = ['new_lead', 'stage_changed', 'deal_closed', 'tasks_due', 'cold_leads', 'test'] as const;
export type WaEvent = typeof EVENTS[number];

export const MAX_BODY_BYTES = 2 * 1024;
export const MAX_MESSAGE_LEN = 300;

const EVENT_SET = new Set<string>(EVENTS);
export function isEvent(v: unknown): v is WaEvent {
  return typeof v === 'string' && EVENT_SET.has(v);
}

// Lead names and stage names are entered by users, so they are untrusted. The text goes to the
// tenant's own number, but still: no links, no line breaks, no WhatsApp formatting characters.
export function cleanText(v: unknown, max: number): string {
  if (typeof v !== 'string') return '';
  return v
    .replace(/https?:\/\/\S+|www\.\S+/gi, '')
    .replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, ' ')
    .replace(/[*_~`]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function cleanCount(v: unknown): number | null {
  const n = typeof v === 'number' ? v : Number.NaN;
  return Number.isInteger(n) && n >= 1 && n <= 999 ? n : null;
}

export type Built = { ok: true; text: string } | { ok: false; error: 'invalid_event' | 'invalid_data' };

export function buildMessage(event: unknown, data: unknown): Built {
  if (!isEvent(event)) return { ok: false, error: 'invalid_event' };
  const d = data && typeof data === 'object' && !Array.isArray(data) ? (data as Record<string, unknown>) : {};
  let text: string;
  switch (event) {
    case 'new_lead': {
      const name = cleanText(d.name, 40);
      text = name ? `🆕 ליד חדש ב-PLTO: ${name}` : '🆕 ליד חדש ב-PLTO';
      break;
    }
    case 'stage_changed': {
      const name = cleanText(d.name, 40);
      const stage = cleanText(d.stage, 40);
      if (!name || !stage) return { ok: false, error: 'invalid_data' };
      text = `🔄 ${name} עבר לשלב: ${stage}`;
      break;
    }
    case 'deal_closed': {
      const name = cleanText(d.name, 40);
      if (!name) return { ok: false, error: 'invalid_data' };
      text = `🎉 עסקה נסגרה: ${name}`;
      break;
    }
    case 'tasks_due': {
      const n = cleanCount(d.count);
      if (n === null) return { ok: false, error: 'invalid_data' };
      text = `⏰ ${n} ${n === 1 ? 'משימה שהגיע זמנה' : 'משימות שהגיע זמנן'} להיום. הפרטים במסך "היום" ב-PLTO`;
      break;
    }
    case 'cold_leads': {
      const n = cleanCount(d.count);
      if (n === null) return { ok: false, error: 'invalid_data' };
      text = `❄️ ${n} ${n === 1 ? 'ליד התקרר' : 'לידים התקררו'}, בלי קשר כבר 14 ימים ומעלה. הפרטים במסך "היום" ב-PLTO`;
      break;
    }
    case 'test':
      text = '✅ בדיקת חיבור מ-PLTO: ההתראות מוגדרות';
      break;
  }
  return { ok: true, text: text.slice(0, MAX_MESSAGE_LEN) };
}

// The kill switch: any value other than exactly "true" (including a missing secret) keeps the feature off.
export function isEnabled(v: string | undefined | null): boolean {
  return v === 'true';
}

// What the RPC reserve_whatsapp_send can answer, mapped to an HTTP status and a public error code.
// Nothing about phone numbers or limits' internals is returned to the browser.
export function mapReserveFailure(reason: unknown): { status: number; error: string; scope?: 'tenant' | 'global' } {
  switch (reason) {
    case 'tenant_daily_limit': return { status: 429, error: 'limit_reached', scope: 'tenant' };
    case 'global_daily_limit': return { status: 429, error: 'limit_reached', scope: 'global' };
    case 'no_number': return { status: 422, error: 'no_number' };
    case 'invalid_number': return { status: 422, error: 'invalid_number' };
    case 'invalid_event': return { status: 400, error: 'invalid_event' };
    case 'tenant_blocked':
    case 'no_agent': return { status: 403, error: 'forbidden' };
    default: return { status: 502, error: 'reserve_failed' };
  }
}
