// Tests the public document link handler behind doc.html (supabase/functions/document-share/handler.ts) in plain Node,
// with the database and storage replaced by stubs. The token rules themselves (hash, expiry, revoke,
// tenant checks) are in migration 133 and were tested against a local Postgres replica.
// Run: node --experimental-strip-types --test supabase/tests/document-share.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { handle, makeLimiter, TOKEN_RE, type Deps } from '../functions/document-share/handler.ts';

const TOKEN = 'a'.repeat(64);
const req = (q: string, init: RequestInit = {}) => new Request('https://x.supabase.co/functions/v1/document-share' + q, init);

function deps(over: Partial<Deps> = {}) {
  const calls = { resolve: [] as string[], sign: [] as string[] };
  const d: Deps = {
    allow: () => true,
    async resolve(t) { calls.resolve.push(t); return t === TOKEN ? { file_path: 'tenant/lead/1_a.pdf', file_name: 'חוזה <b>.pdf' } : null; },
    async sign(p) { calls.sign.push(p); return 'https://x.supabase.co/storage/v1/object/sign/lead-documents/' + p + '?token=signed'; },
    ...over,
  };
  return { d, calls };
}

test('a valid token returns a short signed URL as JSON, with no-store, no-referrer and CORS for the site', async () => {
  const { d, calls } = deps();
  const res = await handle(req('?t=' + TOKEN, { headers: { origin: 'https://sales.plto.app' } }), d);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type') || '', /^application\/json/);
  const body = await res.json();
  assert.match(body.url, /\/object\/sign\/lead-documents\/tenant\/lead\/1_a\.pdf\?token=signed$/);
  assert.equal(res.headers.get('cache-control'), 'no-store');
  assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(res.headers.get('access-control-allow-origin'), 'https://sales.plto.app');
  assert.deepEqual(calls.sign, ['tenant/lead/1_a.pdf']);
});

test('the function never serves HTML (the supabase.co gateway would show it as raw text)', async () => {
  for (const [q, d] of [['?t=' + TOKEN, deps().d], ['?t=' + 'b'.repeat(64), deps().d], ['?t=x', deps().d]] as const) {
    const res = await handle(req(q), d);
    assert.match(res.headers.get('content-type') || '', /^application\/json/, q);
    assert.doesNotMatch(await res.text(), /<html|<!DOCTYPE/i, q);
  }
});

test('an unknown origin gets the main site in CORS, not a wildcard', async () => {
  const res = await handle(req('?t=' + TOKEN, { headers: { origin: 'https://evil.example' } }), deps().d);
  assert.equal(res.headers.get('access-control-allow-origin'), 'https://realestate.plto.app');
});

test('unknown, revoked or expired token: the same 404 code, nothing is signed', async () => {
  const { d, calls } = deps();
  const res = await handle(req('?t=' + 'b'.repeat(64)), d);
  assert.equal(res.status, 404);
  assert.deepEqual(await res.json(), { error: 'unavailable' });
  assert.equal(calls.sign.length, 0);
});

test('malformed token is rejected before touching the database', async () => {
  for (const q of ['', '?t=', '?t=abc', '?t=' + 'A'.repeat(64), '?t=' + 'a'.repeat(65), '?t=' + 'a'.repeat(63) + '%27']) {
    const { d, calls } = deps();
    const res = await handle(req(q), d);
    assert.equal(res.status, 404, q);
    assert.equal(calls.resolve.length, 0, q);
  }
});

test('the response never echoes request or file data', async () => {
  const { d } = deps({ async resolve() { return null; } });
  const res = await handle(req('?t=<script>alert(1)</script>'), d);
  assert.doesNotMatch(await res.text(), /<script|alert/);
});

test('only GET', async () => {
  for (const method of ['POST', 'HEAD', 'PUT']) {
    const { d, calls } = deps();
    const res = await handle(req('?t=' + TOKEN, { method }), d);
    assert.equal(res.status, 405, method);
    assert.equal(calls.resolve.length, 0, method);
  }
});

test('rate limit by address returns 429 without resolving', async () => {
  const { d, calls } = deps({ allow: () => false });
  const res = await handle(req('?t=' + TOKEN, { headers: { 'x-forwarded-for': '1.2.3.4' } }), d);
  assert.equal(res.status, 429);
  assert.equal(calls.resolve.length, 0);
  let t = 0; const allow = makeLimiter(2, 1000, () => t);
  assert.deepEqual([allow('ip'), allow('ip'), allow('ip')], [true, true, false]);
  t = 1001; assert.equal(allow('ip'), true);
});

test('database or storage failure gives a generic 500, never a URL', async () => {
  const a = await handle(req('?t=' + TOKEN), deps({ async resolve() { throw new Error('db down: secret detail'); } }).d);
  assert.equal(a.status, 500);
  assert.deepEqual(await a.json(), { error: 'error' });
  const b = await handle(req('?t=' + TOKEN), deps({ async sign() { return null; } }).d);
  assert.equal(b.status, 500);
});

test('token format matches what create_document_share issues (32 random bytes, hex)', () => {
  assert.ok(TOKEN_RE.test(TOKEN));
  const mig = readFileSync(new URL('../migrations/133_lead_document_shares.sql', import.meta.url), 'utf8');
  assert.match(mig, /encode\(extensions\.gen_random_bytes\(32\), 'hex'\)/);
  assert.match(mig, /p_token !~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(mig, /interval '7 days'/);
});

test('the entry point uses the service key only server side and signs for 60 seconds', () => {
  const src = readFileSync(new URL('../functions/document-share/index.ts', import.meta.url), 'utf8');
  assert.match(src, /resolve_document_share/);
  assert.match(src, /createSignedUrl\(path, 60/);
  assert.doesNotMatch(src, /getPublicUrl/);
});
