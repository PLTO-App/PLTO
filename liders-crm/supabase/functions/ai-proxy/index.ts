// Liders CRM — Edge Function: ai-proxy
//
// Server-side proxy for Claude API calls. Holds ANTHROPIC_API_KEY as a server
// secret (Deno.env) so it never reaches the browser — replaces the previous
// client-side pattern of storing the key in localStorage and calling
// api.anthropic.com directly with 'anthropic-dangerous-direct-browser-access'.
//
// Authorization model (mirrors migration 012_billing_access_enforcement.sql):
// verify_jwt proves the caller holds *some* valid session, but not that their
// tenant is allowed to use the product right now. We forward the caller's own
// JWT to PostgREST and call the existing tenant_access_active() RPC (already
// GRANTed to `authenticated`) — the same gate RLS uses to block expired/
// cancelled tenants from operational tables. Without this, any authenticated
// user — including one whose trial+retention window has fully lapsed — could
// spend the operator's Anthropic budget indefinitely with no per-tenant cap.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');
const SUPABASE_URL      = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

// Cheaper, fast model — these four prompts are short, templated, bounded
// Hebrew CRM tasks (lead scoring, follow-up/rescue messages, deal advice);
// Opus-tier reasoning isn't needed and would multiply abuse-cost ceiling.
const MODEL = 'claude-haiku-4-5';
const MAX_TOKENS_CAP = 1000;
// Generous bound for our 4 fixed templated prompts (each well under 2KB of
// JSON) — blocks a direct caller from inflating Anthropic input-token cost
// via an oversized `messages` payload.
const MAX_MESSAGES_JSON_BYTES = 8000;

// Browsers preflight cross-origin calls that carry Authorization/Content-Type
// headers with an OPTIONS request — without these headers on every response
// (including the OPTIONS reply itself), the browser blocks the real POST
// before it's sent and supabase-js surfaces it as a generic "failed to fetch".
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  if (!ANTHROPIC_API_KEY) return json({ error: 'AI is not configured on the server yet' }, 500);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'authentication required' }, 401);

  // Forward the caller's own JWT so tenant_access_active() resolves auth.uid()
  // to THEM, not to this function's service context.
  const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: active, error: rpcError } = await sb.rpc('tenant_access_active');
  if (rpcError || active !== true) {
    return json({ error: 'AI is unavailable — your trial or subscription is not active' }, 402);
  }

  let body: { messages?: unknown; max_tokens?: number };
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }

  const messages = body?.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return json({ error: 'messages is required' }, 400);
  }
  if (JSON.stringify(messages).length > MAX_MESSAGES_JSON_BYTES) {
    return json({ error: 'messages payload too large' }, 413);
  }

  const maxTokens = Math.min(Math.max(1, Number(body?.max_tokens) || 400), MAX_TOKENS_CAP);

  const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, messages }),
  });

  const data = await anthropicRes.json();
  if (!anthropicRes.ok) {
    return json({ error: data?.error?.message || 'Claude API error' }, anthropicRes.status);
  }
  return json(data);
});
