import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// פונקציה פנימית בלבד — לא נקראת משום client בדפדפן.
// נקראת אך ורק ע"י pg_cron (דרך net.http_post) כדי לשלוח את דוח ה-CRO
// השבועי (מיגרציה 086, send_ab_test_report_email). האימות הוא לא JWT
// משתמש (לקרון אין session) — אלא secret פנימי שנוצר ונשמר ב-Supabase
// Vault ומאומת מול ה-DB דרך verify_cron_report_secret(), כך שאין secret
// נוסף שצריך להגדיר ידנית ב-Dashboard.

const REPORT_TO = 'info@plto.app';
const GMAIL_ACCOUNT = 'liders.crm@gmail.com'; // תיבת ה-OAuth המחוברת בפועל

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin':  'null',
    'Access-Control-Allow-Headers': 'content-type, x-report-secret',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

async function getAccessToken(
  supabase: ReturnType<typeof createClient>,
  clientId: string,
  clientSecret: string,
): Promise<string> {
  const { data: row, error } = await supabase
    .from('gmail_tokens')
    .select('access_token, refresh_token, expires_at')
    .eq('account', GMAIL_ACCOUNT)
    .single();

  if (error || !row) throw new Error('gmail_tokens: לא נמצא token');

  const expiresAt = row.expires_at ? new Date(row.expires_at).getTime() : 0;
  const fiveMin   = 5 * 60 * 1000;

  if (row.access_token && expiresAt - Date.now() > fiveMin) {
    return row.access_token;
  }

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    new URLSearchParams({
      client_id:     clientId,
      client_secret: clientSecret,
      refresh_token: row.refresh_token,
      grant_type:    'refresh_token',
    }),
  });

  const tokens = await res.json() as {
    access_token?: string;
    expires_in?: number;
    error?: string;
  };

  if (!tokens.access_token) throw new Error(`refresh failed: ${tokens.error}`);

  const newExpiry = new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000).toISOString();

  await supabase.from('gmail_tokens').update({
    access_token: tokens.access_token,
    expires_at:   newExpiry,
  }).eq('account', GMAIL_ACCOUNT);

  return tokens.access_token;
}

function encodeEmail(to: string, subject: string, body: string): string {
  const headers = [
    `To: ${to}`,
    `From: ${GMAIL_ACCOUNT}`,
    `Subject: =?UTF-8?B?${btoa(unescape(encodeURIComponent(subject)))}?=`,
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset=UTF-8',
  ].join('\r\n');

  const raw = `${headers}\r\n\r\n${body}`;
  return btoa(unescape(encodeURIComponent(raw)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders();

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST')
    return new Response('Method not allowed', { status: 405, headers: cors });

  const secret = req.headers.get('x-report-secret');
  if (!secret) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabase = createClient(
    supabaseUrl,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // אימות ה-secret מול ה-DB (Vault) — הפונקציה הזו נגישה רק ל-service_role.
  const { data: isValid, error: verifyErr } = await supabase.rpc(
    'verify_cron_report_secret',
    { p_secret: secret },
  );
  if (verifyErr || !isValid) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
  }

  const clientId     = Deno.env.get('GMAIL_CLIENT_ID')     ?? '';
  const clientSecret = Deno.env.get('GMAIL_CLIENT_SECRET') ?? '';
  if (!clientId || !clientSecret) {
    return new Response(JSON.stringify({ error: 'GMAIL credentials not configured' }),
      { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }),
      { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } });
  }

  const subject = (body.subject as string) || 'דוח CRO שבועי — PLTO';
  const html    = body.html as string;
  if (!html) {
    return new Response(JSON.stringify({ error: 'html נדרש' }),
      { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } });
  }

  try {
    const token = await getAccessToken(supabase, clientId, clientSecret);
    const raw   = encodeEmail(REPORT_TO, subject, html);
    const res   = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
      method:  'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify({ raw }),
    });
    const sent = await res.json();
    if (!res.ok) throw new Error(sent?.error?.message || 'gmail send failed');

    return new Response(JSON.stringify({ sent: { id: sent.id } }),
      { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
