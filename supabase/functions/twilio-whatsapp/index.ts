import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { buildMessage, isEnabled, mapReserveFailure, MAX_BODY_BYTES } from './guard.ts';

// Only allow production domain + local dev
const ALLOWED_ORIGINS = [
  'https://realestate.plto.app',
  'https://plto.app',
  'https://www.plto.app',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
];

function corsHeaders(origin: string | null) {
  const allowed = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

// What this function does (rewritten 28.10.2026, see plans/sales-game-plan-2026-10-27.md, section 7):
//   - OFF by default. Only the secret WHATSAPP_ENABLED=true turns it on. Checked before auth and before any call.
//   - The browser sends an event name and small values. It never sends a phone number or free text.
//   - The destination is always the tenant's own number, read in the database (reserve_whatsapp_send).
//     Israeli mobile numbers only.
//   - A slot is reserved in the database before every send: daily cap per tenant and a global daily cap.
//   - The browser gets short error codes only. Twilio details stay in the server log.
Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  const cors = corsHeaders(origin);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    // Kill switch first: nothing else runs, no database read and no call to Twilio.
    if (!isEnabled(Deno.env.get('WHATSAPP_ENABLED'))) return json({ error: 'whatsapp_disabled' }, 503);

    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseAnon = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !supabaseAnon || !serviceKey) return json({ error: 'server_misconfigured' }, 500);

    const sb = createClient(supabaseUrl, supabaseAnon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authErr } = await sb.auth.getUser();
    if (authErr || !user) return json({ error: 'unauthorized' }, 401);

    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json({ error: 'too_large' }, 413);
    let body: { event?: unknown; data?: unknown };
    try { body = JSON.parse(raw); } catch { return json({ error: 'invalid_json' }, 400); }
    if (!body || typeof body !== 'object') return json({ error: 'invalid_json' }, 400);

    const built = buildMessage(body.event, body.data);
    if (!built.ok) return json({ error: built.error }, 400);

    const accountSid = Deno.env.get('TWILIO_ACCOUNT_SID');
    const authToken = Deno.env.get('TWILIO_AUTH_TOKEN');
    const from = Deno.env.get('TWILIO_WHATSAPP_FROM') ?? '+14155238886';
    if (!accountSid || !authToken) return json({ error: 'server_misconfigured' }, 500);

    // The reservation is made with the admin key, and only after the caller was verified above.
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: slot, error: slotErr } = await admin.rpc('reserve_whatsapp_send', {
      p_auth_user_id: user.id, p_event: body.event,
    });
    if (slotErr || !slot) return json({ error: 'reserve_failed' }, 502);
    if (!slot.ok) {
      const f = mapReserveFailure(slot.reason);
      return json(f.scope ? { error: f.error, scope: f.scope } : { error: f.error }, f.status);
    }

    const to = String(slot.to || '');
    if (!/^\+972[0-9]{9}$/.test(to)) return json({ error: 'invalid_number' }, 422);

    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          From: from.startsWith('whatsapp:') ? from : `whatsapp:${from}`,
          To: `whatsapp:${to}`,
          Body: built.text,
        }).toString(),
        signal: AbortSignal.timeout(8000),
      },
    );

    if (!res.ok) {
      // The reserved slot stays counted. Only the status code is logged: no number, no text, no Twilio message.
      console.error('twilio send failed', res.status);
      return json({ error: 'send_failed' }, 502);
    }
    return json({ success: true });
  } catch (_e) {
    // Never echo upstream details back to the browser.
    return json({ error: 'internal_error' }, 500);
  }
});
