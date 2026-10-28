// Runs the real twilio-whatsapp handler (index.ts) in plain Node with the Deno server and the
// Supabase client replaced by stubs, and with fetch replaced by a spy. No request ever reaches
// Twilio, no secret is used and nothing is sent. Tokens and keys below are fake labels.
// Verifies: the WHATSAPP_ENABLED kill switch, that the destination and the wording come only from
// the server, the daily-cap and failure mapping, and that no upstream detail reaches the browser.
// Run: node --experimental-strip-types --test supabase/tests/twilio-whatsapp-guard.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { buildMessage, cleanText, isEnabled, mapReserveFailure, EVENTS } from '../functions/twilio-whatsapp/guard.ts';

// ── pure helpers ─────────────────────────────────────────────────────────────
test('isEnabled: only the exact string "true" turns the feature on', () => {
  assert.equal(isEnabled('true'), true);
  for (const v of [undefined, null, '', 'false', 'TRUE', 'True', '1', 'yes', ' true', 'true ']) assert.equal(isEnabled(v as string), false, String(v));
});

test('cleanText: strips links, line breaks, control and formatting characters, and caps the length', () => {
  assert.equal(cleanText('יוסי https://evil.example/x?a=1 כהן', 40), 'יוסי כהן');
  assert.equal(cleanText('www.evil.example יוסי', 40), 'יוסי');
  assert.equal(cleanText('שורה1\nשורה2\r\n\tשורה3', 40), 'שורה1 שורה2 שורה3');
  assert.equal(cleanText('*bold* _it_ ~x~ `code`', 40), 'bold it x code');
  assert.equal(cleanText('‮רע‬', 40), 'רע');
  assert.equal(cleanText('x'.repeat(100), 40).length, 40);
  for (const v of [null, undefined, 5, {}, []]) assert.equal(cleanText(v, 40), '');
});

test('buildMessage: every event produces fixed wording and unknown events are rejected', () => {
  for (const e of ['constructor', '__proto__', 'toString', '', 'free_text', undefined, 5]) {
    assert.deepEqual(buildMessage(e, {}), { ok: false, error: 'invalid_event' }, String(e));
  }
  const n = buildMessage('new_lead', { name: 'דנה' });
  assert.ok(n.ok && n.text === '🆕 ליד חדש ב-PLTO: דנה');
  assert.ok(buildMessage('new_lead', {}).ok, 'a new lead without a name still works');
  assert.ok(buildMessage('stage_changed', { name: 'דנה', stage: 'הצעה' }).ok);
  assert.deepEqual(buildMessage('stage_changed', { name: 'דנה' }), { ok: false, error: 'invalid_data' });
  assert.deepEqual(buildMessage('deal_closed', {}), { ok: false, error: 'invalid_data' });
  assert.ok(buildMessage('tasks_due', { count: 3 }).ok);
  for (const c of [0, -1, 1000, 1.5, '3', null, undefined, NaN]) assert.equal(buildMessage('tasks_due', { count: c }).ok, false, String(c));
  assert.ok(buildMessage('cold_leads', { count: 1 }).ok);
  assert.ok(buildMessage('test', null).ok);
  assert.equal(EVENTS.length, 6);
});

test('buildMessage: values typed by users cannot inject links or break the format, and the text stays short', () => {
  const r = buildMessage('stage_changed', { name: 'x'.repeat(500) + ' https://evil.example', stage: '*גדול*\nhttp://evil.example' });
  assert.ok(r.ok);
  if (r.ok) {
    assert.equal(/https?:|www\./.test(r.text), false);
    assert.equal(r.text.includes('\n'), false);
    assert.ok(r.text.length <= 300);
  }
  // fields the template does not know are ignored, including a client supplied phone or text
  const s = buildMessage('test', { to: '+972500000000', message: 'שלחו לי כסף', text: 'x' });
  assert.ok(s.ok && !s.text.includes('שלחו') && !s.text.includes('972'));
});

test('mapReserveFailure: caps are 429, number problems 422, everything else is a safe generic code', () => {
  assert.deepEqual(mapReserveFailure('tenant_daily_limit'), { status: 429, error: 'limit_reached', scope: 'tenant' });
  assert.deepEqual(mapReserveFailure('global_daily_limit'), { status: 429, error: 'limit_reached', scope: 'global' });
  assert.equal(mapReserveFailure('no_number').status, 422);
  assert.equal(mapReserveFailure('invalid_number').status, 422);
  assert.equal(mapReserveFailure('tenant_blocked').status, 403);
  assert.equal(mapReserveFailure('no_agent').status, 403);
  assert.deepEqual(mapReserveFailure('anything else'), { status: 502, error: 'reserve_failed' });
  assert.deepEqual(mapReserveFailure(undefined), { status: 502, error: 'reserve_failed' });
});

// ── the real handler ─────────────────────────────────────────────────────────
const src = new URL('../functions/twilio-whatsapp/', import.meta.url);
const dir = mkdtempSync(join(tmpdir(), 'twilio-wa-'));
writeFileSync(join(dir, 'guard.ts'), readFileSync(new URL('guard.ts', src), 'utf8'));
writeFileSync(
  join(dir, 'index.ts'),
  readFileSync(new URL('index.ts', src), 'utf8').replace("'https://esm.sh/@supabase/supabase-js@2'", "'./stub_supabase.ts'"),
);
writeFileSync(join(dir, 'stub_supabase.ts'), `
const USERS: Record<string, { id: string }> = { 'fake-user-token': { id: 'user-from-token' }, 'fake-other-token': { id: 'other-user' } };
export function createClient(_url: string, key: string, opts?: { global?: { headers?: { Authorization?: string } } }) {
  (globalThis as any).__clients.push(key);
  const auth = opts?.global?.headers?.Authorization;
  return {
    auth: {
      getUser: async () => {
        const u = auth ? USERS[auth.replace('Bearer ', '')] : undefined;
        return u ? { data: { user: u }, error: null } : { data: { user: null }, error: { message: 'bad token' } };
      },
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      (globalThis as any).__rpcCalls.push({ name, args, key });
      const r = (globalThis as any).__rpcResult;
      return typeof r === 'function' ? r(args) : r;
    },
  };
}
`);

const g = globalThis as any;
const env: Record<string, string | undefined> = {
  SUPABASE_URL: 'https://example.invalid', SUPABASE_ANON_KEY: 'anon-placeholder', SUPABASE_SERVICE_ROLE_KEY: 'service-placeholder',
  TWILIO_ACCOUNT_SID: 'AC-fake-sid', TWILIO_AUTH_TOKEN: 'fake-auth-token', WHATSAPP_ENABLED: 'true',
};
g.Deno = { env: { get: (k: string) => env[k] }, serve: (h: unknown) => { g.__handler = h; } };
g.__clients = [];
g.__rpcCalls = [];
g.__fetchCalls = [] as { url: string; init: RequestInit }[];
g.__twilio = { ok: true, status: 201, body: { sid: 'SM-fake', message: 'secret upstream detail', code: 21211 } };
g.fetch = async (url: string, init: RequestInit) => {
  g.__fetchCalls.push({ url: String(url), init });
  return { ok: g.__twilio.ok, status: g.__twilio.status, json: async () => g.__twilio.body };
};
g.__rpcResult = { data: { ok: true, to: '+972501234567' }, error: null };

await import(pathToFileURL(join(dir, 'index.ts')).href);
const handler = g.__handler as (r: Request) => Promise<Response>;

function reset() {
  g.__clients.length = 0; g.__rpcCalls.length = 0; g.__fetchCalls.length = 0;
  g.__rpcResult = { data: { ok: true, to: '+972501234567' }, error: null };
  g.__twilio = { ok: true, status: 201, body: { sid: 'SM-fake', message: 'secret upstream detail', code: 21211 } };
  env.WHATSAPP_ENABLED = 'true';
}
function call(token: string | null, body: unknown, opts: { method?: string; raw?: string } = {}) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', Origin: 'https://realestate.plto.app' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return handler(new Request('http://stub/twilio-whatsapp', {
    method: opts.method ?? 'POST', headers,
    body: opts.method === 'GET' || opts.method === 'OPTIONS' ? undefined : (opts.raw ?? JSON.stringify(body)),
  }));
}
const form = () => new URLSearchParams(String(g.__fetchCalls[0].init.body));

test('kill switch: off by default and for any value other than "true", nothing runs at all', async () => {
  for (const v of [undefined, '', 'false', 'TRUE', '1', 'yes']) {
    reset();
    env.WHATSAPP_ENABLED = v;
    const r = await call('fake-user-token', { event: 'test' });
    assert.equal(r.status, 503, String(v));
    assert.deepEqual(await r.json(), { error: 'whatsapp_disabled' });
    assert.equal(g.__clients.length, 0, 'no database client is even created');
    assert.equal(g.__rpcCalls.length, 0);
    assert.equal(g.__fetchCalls.length, 0, 'no request to Twilio');
  }
  reset();
  env.WHATSAPP_ENABLED = undefined;
  assert.equal((await call(null, { event: 'test' })).status, 503, 'it answers 503 before it even looks at the token');
});

test('GET is 405, OPTIONS answers the preflight, and the production origin is allowed', async () => {
  reset();
  assert.equal((await call('fake-user-token', null, { method: 'GET' })).status, 405);
  const pre = await call('fake-user-token', null, { method: 'OPTIONS' });
  assert.equal(pre.status, 200);
  assert.equal(pre.headers.get('Access-Control-Allow-Origin'), 'https://realestate.plto.app');
});

test('no token or a bad token: 401, no reservation and no send', async () => {
  reset();
  assert.equal((await call(null, { event: 'test' })).status, 401);
  assert.equal((await call('fake-wrong-token', { event: 'test' })).status, 401);
  assert.equal(g.__rpcCalls.length, 0);
  assert.equal(g.__fetchCalls.length, 0);
});

test('invalid JSON, oversized body, unknown event and missing data: 4xx, no reservation and no send', async () => {
  reset();
  assert.equal((await call('fake-user-token', null, { raw: '{not json' })).status, 400);
  assert.equal((await call('fake-user-token', null, { raw: JSON.stringify({ event: 'test', data: { x: 'y'.repeat(3000) } }) })).status, 413);
  const unknown = await call('fake-user-token', { event: 'free_text', data: { message: 'hi' } });
  assert.equal(unknown.status, 400);
  assert.deepEqual(await unknown.json(), { error: 'invalid_event' });
  const missing = await call('fake-user-token', { event: 'stage_changed', data: { name: 'דנה' } });
  assert.equal(missing.status, 400);
  assert.deepEqual(await missing.json(), { error: 'invalid_data' });
  assert.equal(g.__rpcCalls.length, 0);
  assert.equal(g.__fetchCalls.length, 0);
});

test('a send: one reservation with the admin key for the verified user, and Twilio gets only server-decided values', async () => {
  reset();
  const r = await call('fake-user-token', {
    event: 'new_lead', data: { name: 'דנה https://evil.example' },
    // a client trying to choose the destination, the wording or the identity
    to: '+972509999999', message: 'שלחו כסף', Body: 'x', p_auth_user_id: 'someone-else', user_id: 'someone-else',
  });
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { success: true });
  assert.equal(g.__rpcCalls.length, 1);
  const rpc = g.__rpcCalls[0];
  assert.equal(rpc.name, 'reserve_whatsapp_send');
  assert.equal(rpc.key, 'service-placeholder');
  assert.deepEqual(rpc.args, { p_auth_user_id: 'user-from-token', p_event: 'new_lead' });
  assert.equal(g.__fetchCalls.length, 1);
  assert.ok(g.__fetchCalls[0].url.startsWith('https://api.twilio.com/2010-04-01/Accounts/AC-fake-sid/Messages.json'));
  const f = form();
  assert.equal(f.get('To'), 'whatsapp:+972501234567', 'the destination is the one the database returned');
  assert.equal(f.get('From'), 'whatsapp:+14155238886', 'the default sender is the Twilio Sandbox');
  assert.equal(f.get('Body'), '🆕 ליד חדש ב-PLTO: דנה', 'the text is built from the template, without links');
  assert.equal(String(g.__fetchCalls[0].init.body).includes('999999'), false);
});

test('a cap or a number problem: mapped status, scope only for caps, and nothing is sent', async () => {
  const cases: [string, number, string][] = [
    ['tenant_daily_limit', 429, 'limit_reached'], ['global_daily_limit', 429, 'limit_reached'],
    ['no_number', 422, 'no_number'], ['invalid_number', 422, 'invalid_number'],
    ['tenant_blocked', 403, 'forbidden'], ['no_agent', 403, 'forbidden'],
  ];
  for (const [reason, status, error] of cases) {
    reset();
    g.__rpcResult = { data: { ok: false, reason }, error: null };
    const r = await call('fake-user-token', { event: 'test' });
    assert.equal(r.status, status, reason);
    assert.equal((await r.json()).error, error, reason);
    assert.equal(g.__fetchCalls.length, 0, reason);
  }
  reset();
  g.__rpcResult = { data: null, error: { message: 'db down' } };
  const down = await call('fake-user-token', { event: 'test' });
  assert.equal(down.status, 502);
  assert.deepEqual(await down.json(), { error: 'reserve_failed' });
  assert.equal(g.__fetchCalls.length, 0, 'a database failure never ends in a send');
});

test('a bad number from the database is refused before Twilio', async () => {
  for (const to of ['+15551234567', '0501234567', '', '+972501234567; drop', undefined]) {
    reset();
    g.__rpcResult = { data: { ok: true, to }, error: null };
    const r = await call('fake-user-token', { event: 'test' });
    assert.equal(r.status, 422, String(to));
    assert.equal(g.__fetchCalls.length, 0, String(to));
  }
});

test('Twilio failure: 502 with a generic code, and no upstream message, code or number reaches the browser', async () => {
  reset();
  g.__twilio = { ok: false, status: 400, body: { message: 'secret upstream detail 972501234567', code: 63015 } };
  const r = await call('fake-user-token', { event: 'test' });
  assert.equal(r.status, 502);
  const text = await r.text();
  assert.deepEqual(JSON.parse(text), { error: 'send_failed' });
  assert.equal(/secret|63015|972501234567/.test(text), false);
});

test('an unexpected exception: 500 with a generic code', async () => {
  reset();
  g.__rpcResult = () => { throw new Error('boom with internal detail'); };
  const r = await call('fake-user-token', { event: 'test' });
  assert.equal(r.status, 500);
  const text = await r.text();
  assert.deepEqual(JSON.parse(text), { error: 'internal_error' });
  assert.equal(text.includes('boom'), false);
});

test('missing Twilio secrets: 500 before any reservation', async () => {
  reset();
  const saved = env.TWILIO_AUTH_TOKEN;
  env.TWILIO_AUTH_TOKEN = undefined;
  const r = await call('fake-user-token', { event: 'test' });
  env.TWILIO_AUTH_TOKEN = saved;
  assert.equal(r.status, 500);
  assert.equal(g.__rpcCalls.length, 0);
  assert.equal(g.__fetchCalls.length, 0);
});
