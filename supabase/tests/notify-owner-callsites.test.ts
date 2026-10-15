// Checks that every notify-owner call in the site code only sends fields the
// function accepts, includes the required ones, and that no page posts to the
// owner webhook directly any more.
// Run: node --experimental-strip-types --test supabase/tests/notify-owner-callsites.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { EVENTS } from '../functions/notify-owner/validate.ts';

const root = new URL('../../', import.meta.url);
const pages = ['index.html', 'admin.html'].map((f) => [f, readFileSync(new URL(f, root), 'utf8')] as const);

function topLevelKeys(objSrc: string): string[] {
  // keys of a flat object literal: name: value, or shorthand name
  const keys: string[] = [];
  let depth = 0, cur = '';
  const parts: string[] = [];
  for (const ch of objSrc) {
    if ('([{'.includes(ch)) depth++;
    if (')]}'.includes(ch)) depth--;
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; } else cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  for (const p of parts) {
    const m = p.trim().match(/^([A-Za-z_]\w*)/);
    if (m) keys.push(m[1]);
  }
  return keys;
}

const calls: { page: string; event: string; keys: string[] }[] = [];
for (const [page, src] of pages) {
  const re = /functions\.invoke\('notify-owner', \{ body: \{ event: '([^']+)', data: \{([\s\S]*?)\} \} \}\)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src))) calls.push({ page, event: m[1], keys: topLevelKeys(m[2]) });
}

test('all five former webhook call sites now use notify-owner', () => {
  assert.deepEqual(calls.map((c) => c.event).sort(), [
    'full_service_request', 'idea_suggestion', 'support.admin_replied', 'support.needs_human', 'upgrade_request',
  ]);
});

test('call sites send only allowed fields and all required ones', () => {
  for (const c of calls) {
    const spec = EVENTS[c.event];
    assert.ok(spec, `unknown event ${c.event}`);
    for (const k of c.keys) assert.ok(k in spec.fields, `${c.page} ${c.event}: field "${k}" is dropped by the function`);
    for (const [k, f] of Object.entries(spec.fields)) {
      if (f.required) assert.ok(c.keys.includes(k), `${c.page} ${c.event}: required "${k}" is not sent`);
    }
  }
});

test('no direct requests to the owner webhook remain in site pages', () => {
  for (const [page, src] of pages) {
    assert.equal(/hook\.eu1\.make\.com\/[a-z0-9]{20,}/.test(src), false, `${page} still contains a webhook address`);
    assert.equal(src.includes('_UPGRADE_WEBHOOK'), false, `${page} still references _UPGRADE_WEBHOOK`);
  }
});
