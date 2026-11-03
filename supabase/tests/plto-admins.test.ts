// Owner checks in the Edge Functions go by verified user id, the same list as _is_plto_admin()
// (migration 130), and the retired shared mailbox can no longer be connected.
// Run: node --experimental-strip-types --test supabase/tests/plto-admins.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { isPltoAdmin, PLTO_ADMIN_USER_IDS } from '../functions/_shared/plto-admins.ts';

const read = (p: string) => readFileSync(new URL(p, import.meta.url), 'utf8');

test('isPltoAdmin accepts only the owner ids', () => {
  for (const id of PLTO_ADMIN_USER_IDS) assert.equal(isPltoAdmin(id), true);
  for (const v of ['', 'info@plto.app', 'elgrablidudu@gmail.com', null, undefined, 'e47fc732-cbc6-44da-afb6-910703a308f1']) {
    assert.equal(isPltoAdmin(v as string), false, String(v));
  }
});

test('the id list matches migration 130', () => {
  const mig = read('../migrations/130_admin_check_by_uid.sql');
  const ids = [...mig.matchAll(/'([0-9a-f-]{36})'/g)].map(m => m[1]).sort();
  assert.deepEqual([...PLTO_ADMIN_USER_IDS].sort(), ids);
});

test('gmail-proxy decides access by user id, with no email list', () => {
  const src = read('../functions/gmail-proxy/index.ts');
  assert.match(src, /isPltoAdmin\(user\.id\)/);
  assert.doesNotMatch(src, /ADMIN_EMAILS/);
});

test('notify-owner has no email-based admin list', () => {
  assert.doesNotMatch(read('../functions/notify-owner/validate.ts'), /ADMIN_EMAILS|@plto\.app|@gmail\.com/);
});

test('gmail-oauth-callback is disabled: 410 and no token storage', async () => {
  const src = read('../functions/gmail-oauth-callback/index.ts');
  assert.doesNotMatch(src, /gmail_tokens|oauth2|refresh_token|createClient/);
  let handler: (() => Response) | undefined;
  (globalThis as any).Deno = { serve: (h: () => Response) => { handler = h; } };
  await import('../functions/gmail-oauth-callback/index.ts');
  const res = handler!();
  assert.equal(res.status, 410);
  assert.match(await res.text(), /הושבת/);
});
