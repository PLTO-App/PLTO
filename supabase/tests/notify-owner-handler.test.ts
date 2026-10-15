// Runs the real notify-owner request handler (index.ts) in plain Node with the
// Deno server and the Supabase client replaced by small stubs, so the HTTP
// behavior (status codes and ordering of the checks) is tested without a real
// user, a real JWT or any network call. Tokens below are fake labels.
// Run: node --experimental-strip-types --test supabase/tests/notify-owner-handler.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const src = new URL('../functions/notify-owner/', import.meta.url);
const dir = mkdtempSync(join(tmpdir(), 'notify-owner-'));

for (const f of ['validate.ts', 'render.ts']) writeFileSync(join(dir, f), readFileSync(new URL(f, src), 'utf8'));
writeFileSync(
  join(dir, 'index.ts'),
  readFileSync(new URL('index.ts', src), 'utf8')
    .replace("'https://deno.land/std@0.168.0/http/server.ts'", "'./stub_serve.ts'")
    .replace("'https://esm.sh/@supabase/supabase-js@2'", "'./stub_supabase.ts'"),
);
writeFileSync(join(dir, 'stub_serve.ts'), `export function serve(h: unknown) { (globalThis as any).__handler = h; }\n`);
writeFileSync(join(dir, 'stub_supabase.ts'), `
const USERS: Record<string, { id: string; email: string }> = {
  'fake-user-token': { id: 'u1', email: 'agent@example.com' },
  'fake-rate-token': { id: 'u-rate', email: 'rate@example.com' },
  'fake-admin-token': { id: 'a1', email: 'info@plto.app' },
};
export function createClient(_url: string, key: string, opts?: { global?: { headers?: { Authorization?: string } } }) {
  const auth = opts?.global?.headers?.Authorization;
  return {
    auth: {
      getUser: async () => {
        const u = auth ? USERS[auth.replace('Bearer ', '')] : undefined;
        return u ? { data: { user: u }, error: null } : { data: { user: null }, error: { message: 'bad token' } };
      },
    },
    rpc: async (name: string, args: Record<string, string>) => {
      (globalThis as any).__rpcCalls.push({ name, args, key });
      return { error: (globalThis as any).__rpcError ?? null };
    },
  };
}
`);

const g = globalThis as any;
g.__rpcCalls = [];
g.Deno = { env: { get: (k: string) => ({ SUPABASE_URL: 'http://stub', SUPABASE_ANON_KEY: 'anon-placeholder', SUPABASE_SERVICE_ROLE_KEY: 'service-placeholder' } as Record<string, string>)[k] } };
await import(pathToFileURL(join(dir, 'index.ts')).href);
const handler = g.__handler as (r: Request) => Promise<Response>;

function call(token: string | null, body: unknown, opts: { method?: string; raw?: string } = {}) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', Origin: 'https://realestate.plto.app' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return handler(new Request('http://stub/notify-owner', {
    method: opts.method ?? 'POST', headers,
    body: opts.method === 'GET' ? undefined : (opts.raw ?? JSON.stringify(body)),
  }));
}
const sent = () => g.__rpcCalls.length;

test('no token or bad token: 401 and nothing is sent', async () => {
  assert.equal((await call(null, { event: 'idea_suggestion', data: { text: 'x' } })).status, 401);
  assert.equal((await call('fake-wrong-token', { event: 'idea_suggestion', data: { text: 'x' } })).status, 401);
  assert.equal(sent(), 0);
});

test('GET is 405 and OPTIONS answers the preflight with CORS headers', async () => {
  assert.equal((await call('fake-user-token', null, { method: 'GET' })).status, 405);
  const pre = await call('fake-user-token', null, { method: 'OPTIONS' });
  assert.equal(pre.status, 200);
  assert.equal(pre.headers.get('Access-Control-Allow-Origin'), 'https://realestate.plto.app');
});

test('unknown event, invalid JSON and missing required field: 400, nothing is sent', async () => {
  const unknown = await call('fake-user-token', { event: 'no_such_event' });
  assert.equal(unknown.status, 400);
  assert.deepEqual(await unknown.json(), { error: 'unknown_event' });
  assert.equal((await call('fake-user-token', null, { raw: '{not json' })).status, 400);
  const missing = await call('fake-user-token', { event: 'idea_suggestion', data: {} });
  assert.equal(missing.status, 400);
  assert.deepEqual(await missing.json(), { error: 'missing_text' });
  assert.equal(sent(), 0);
});

test('prototype-style event names are rejected as unknown', async () => {
  for (const event of ['constructor', '__proto__', 'toString']) {
    assert.equal((await call('fake-user-token', { event })).status, 400, event);
  }
  assert.equal(sent(), 0);
});

test('admin-only event: 403 for a normal user, nothing is sent', async () => {
  const r = await call('fake-user-token', { event: 'support.admin_replied', data: { ticket_id: 't', agent_email: 'a@b.co' } });
  assert.equal(r.status, 403);
  assert.deepEqual(await r.json(), { error: 'forbidden' });
  assert.equal(sent(), 0);
});

test('oversized body: 413', async () => {
  const r = await call('fake-user-token', null, { raw: JSON.stringify({ event: 'idea_suggestion', data: { text: 'x'.repeat(9000) } }) });
  assert.equal(r.status, 413);
  assert.equal(sent(), 0);
});

test('valid event: 200, exactly one email through the helper with the admin key, values escaped', async () => {
  const r = await call('fake-user-token', { event: 'idea_suggestion', data: { text: '<b>רעיון</b>', agent_email: 'spoof@evil.example' } });
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: true });
  assert.equal(sent(), 1);
  const c = g.__rpcCalls[0];
  assert.equal(c.name, '_notify_owner_email');
  assert.equal(c.key, 'service-placeholder');
  assert.ok(c.args.p_subject.startsWith('PLTO: '));
  assert.equal(c.args.p_html.includes('<b>'), false);
  assert.ok(c.args.p_html.includes('&lt;b&gt;'));
  assert.ok(c.args.p_html.includes('agent@example.com'), 'identity comes from the session');
  assert.equal(c.args.p_html.includes('spoof@evil.example'), false, 'client supplied address is ignored');
});

test('admin may send the admin-only event', async () => {
  const before = sent();
  const r = await call('fake-admin-token', { event: 'support.admin_replied', data: { ticket_id: 't', agent_email: 'a@b.co', response: 'תשובה' } });
  assert.equal(r.status, 200);
  assert.equal(sent(), before + 1);
});

test('a failing helper gives 502 without details', async () => {
  g.__rpcError = { message: 'secret internal detail' };
  const r = await call('fake-user-token', { event: 'idea_suggestion', data: { text: 'x' } });
  g.__rpcError = null;
  assert.equal(r.status, 502);
  assert.equal(JSON.stringify(await r.json()).includes('secret'), false);
});

test('rate limit: 20 per hour per user, then 429', async () => {
  const statuses: number[] = [];
  for (let i = 0; i < 21; i++) statuses.push((await call('fake-rate-token', { event: 'idea_suggestion', data: { text: 'x' } })).status);
  assert.equal(statuses.filter((s) => s === 200).length, 20);
  assert.equal(statuses[20], 429);
});
