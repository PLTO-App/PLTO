// Runs the real ai-proxy handler (index.ts) in plain Node with the Deno server and the
// Supabase client replaced by stubs, and with fetch replaced by a spy. No request ever
// reaches a real provider, and no key is used. Verifies the AI_ENABLED kill switch.
// Run: node --experimental-strip-types --test supabase/tests/ai-proxy-kill-switch.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const dir = mkdtempSync(join(tmpdir(), 'ai-proxy-'));
writeFileSync(
  join(dir, 'index.ts'),
  readFileSync(new URL('../functions/ai-proxy/index.ts', import.meta.url), 'utf8')
    .replace("'https://deno.land/std@0.168.0/http/server.ts'", "'./stub_serve.ts'")
    .replace("'https://esm.sh/@supabase/supabase-js@2'", "'./stub_supabase.ts'"),
);
writeFileSync(join(dir, 'stub_serve.ts'), `export function serve(h: unknown) { (globalThis as any).__handler = h; }\n`);
writeFileSync(join(dir, 'stub_supabase.ts'), `
export function createClient() {
  (globalThis as any).__clientCreated++;
  return {
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } }, error: null }) },
    rpc: async (name: string) => { (globalThis as any).__rpcCalls.push(name); return { data: { allowed: true }, error: null }; },
  };
}
`);

const g = globalThis as any;
g.__clientCreated = 0;
g.__rpcCalls = [];
g.__fetchCalls = [];
g.fetch = async (url: string) => { g.__fetchCalls.push(String(url)); throw new Error('network is not allowed in this test'); };
const env: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_ANON_KEY: 'fake-anon', ANTHROPIC_API_KEY: 'fake-provider-key' };
g.Deno = { env: { get: (k: string) => env[k] } };

await import(pathToFileURL(join(dir, 'index.ts')).href);
const handler = g.__handler as (r: Request) => Promise<Response>;

const post = (headers: Record<string, string> = {}) =>
  handler(new Request('https://example.invalid/ai-proxy', {
    method: 'POST',
    headers: { origin: 'https://realestate.plto.app', 'content-type': 'application/json', ...headers },
    body: JSON.stringify({ type: 'marketing', messages: [{ role: 'user', content: 'x' }] }),
  }));

const untouched = () => {
  assert.equal(g.__fetchCalls.length, 0, 'provider fetch must not be called');
  assert.equal(g.__clientCreated, 0, 'no Supabase client may be created');
  assert.deepEqual(g.__rpcCalls, [], 'no quota counter may be touched');
};

test('without AI_ENABLED a fully valid authenticated request is blocked before auth, quota and provider', async () => {
  const res = await post({ authorization: 'Bearer fake-user-token' });
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: 'ai_disabled' });
  assert.equal(res.headers.get('access-control-allow-origin'), 'https://realestate.plto.app');
  untouched();
});

test('AI_ENABLED with any value other than exactly true keeps it blocked', async () => {
  for (const v of ['', 'false', 'TRUE', '1', 'yes']) {
    env.AI_ENABLED = v;
    const res = await post({ authorization: 'Bearer fake-user-token' });
    assert.equal(res.status, 503, `value "${v}"`);
  }
  untouched();
});

test('OPTIONS preflight still works while blocked', async () => {
  delete env.AI_ENABLED;
  const res = await handler(new Request('https://example.invalid/ai-proxy', { method: 'OPTIONS', headers: { origin: 'https://realestate.plto.app' } }));
  assert.equal(res.status, 200);
  untouched();
});

test('with AI_ENABLED=true the normal flow resumes (a request with no token is rejected as 401, still no provider call)', async () => {
  env.AI_ENABLED = 'true';
  const res = await post();
  assert.equal(res.status, 401);
  assert.equal(g.__fetchCalls.length, 0);
});
