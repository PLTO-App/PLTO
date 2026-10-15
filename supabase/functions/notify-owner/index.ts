import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { buildPayload, makeLimiter, MAX_BODY_BYTES } from './validate.ts';

// Server-side relay for the owner notifications that used to be sent straight
// from the browser to a public Make.com webhook. The webhook address lives only
// in the MAKE_OWNER_WEBHOOK_URL secret of this function.

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

// 20 notifications per user per hour.
const allow = makeLimiter(20, 60 * 60 * 1000);

serve(async (req) => {
  const cors = corsHeaders(req.headers.get('origin'));
  const json = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseAnon = Deno.env.get('SUPABASE_ANON_KEY');
    const hookUrl = Deno.env.get('MAKE_OWNER_WEBHOOK_URL');
    if (!supabaseUrl || !supabaseAnon || !hookUrl) return json({ error: 'server_misconfigured' }, 500);

    const sb = createClient(supabaseUrl, supabaseAnon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authErr } = await sb.auth.getUser();
    if (authErr || !user) return json({ error: 'unauthorized' }, 401);

    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json({ error: 'too_large' }, 413);
    let body: unknown;
    try { body = JSON.parse(raw); } catch { return json({ error: 'invalid_json' }, 400); }

    const result = buildPayload(body, { email: user.email });
    if (!result.ok) return json({ error: result.error }, result.status);

    if (!allow(user.id)) return json({ error: 'rate_limited' }, 429);

    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 5000);
    try {
      const res = await fetch(hookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(result.payload),
        signal: ctrl.signal,
      });
      if (!res.ok) return json({ error: 'upstream_failed' }, 502);
    } finally {
      clearTimeout(timer);
    }
    return json({ ok: true });
  } catch (_e) {
    // Never echo upstream details: they can contain the webhook address.
    return json({ error: 'internal_error' }, 500);
  }
});
