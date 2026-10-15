// Checks the owner email rendering, that notify-owner no longer talks to Make,
// and that the daily digest migration sends counts only.
// Run: node --experimental-strip-types --test supabase/tests/notify-owner-validate.test.ts supabase/tests/notify-owner-callsites.test.ts supabase/tests/notify-owner-render.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { renderEmail, escapeHtml } from '../functions/notify-owner/render.ts';
import { EVENTS, buildPayload } from '../functions/notify-owner/validate.ts';

const root = new URL('../../', import.meta.url);
const read = (p: string) => readFileSync(new URL(p, root), 'utf8');

test('escapeHtml escapes the five dangerous characters', () => {
  assert.equal(escapeHtml(`<a href="x">&'`), '&lt;a href=&quot;x&quot;&gt;&amp;&#39;');
});

test('every allowed event renders a subject and a body', () => {
  for (const event of Object.keys(EVENTS)) {
    const { subject, html } = renderEmail({ event, ticket_id: 't1', name: 'דנה', phone: '050', text: 'x' });
    assert.ok(subject.startsWith('PLTO: '), `${event} subject`);
    assert.ok(html.includes('dir="rtl"'), `${event} html`);
  }
});

test('user supplied values are escaped in the body and flattened in the subject', () => {
  const evil = '<img src=x onerror=alert(1)>';
  const { subject, html } = renderEmail({
    event: 'full_service_request', name: `${evil}\nBcc: x@example.com`, phone: '1', need: `${evil}\nשורה שנייה`,
  });
  assert.equal(html.includes('<img'), false);
  assert.ok(html.includes('&lt;img'));
  assert.ok(html.includes('<br>'));
  assert.equal(/[\r\n]/.test(subject), false);
});

test('fields that are not part of the event are not printed', () => {
  const { html } = renderEmail({ event: 'idea_suggestion', text: 'רעיון', secret_field: 'nope' });
  assert.equal(html.includes('nope'), false);
});

test('a payload built by buildPayload renders end to end', () => {
  const r = buildPayload({ event: 'upgrade_request', data: { plan_name: 'Pro', plan_price: '349' } }, { email: 'a@b.co' });
  assert.ok(r.ok);
  if (r.ok) assert.ok(renderEmail(r.payload).subject.includes('Pro'));
});

test('notify-owner has no Make webhook dependency', () => {
  const src = read('supabase/functions/notify-owner/index.ts');
  assert.equal(/MAKE_OWNER_WEBHOOK_URL|hook\.eu1\.make\.com|Deno\.env\.get\('MAKE/.test(src), false);
  assert.ok(src.includes('_notify_owner_email'));
});

test('the digest migration sends counts only, through Resend, without Make', () => {
  const sql = read('supabase/migrations/122_digest_counts_only_via_resend.sql');
  const code = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  assert.ok(code.includes('_notify_owner_email'));
  assert.equal(/net\.http_post|make\.com|vault\./i.test(code), false, 'no webhook or vault lookup');
  assert.equal(/\bl\.name\b|\bl\.phone\b|\bt\.name\b/.test(code), false, 'no lead names, phones or tenant names');
  assert.ok(code.includes('REVOKE EXECUTE ON FUNCTION public.send_daily_lead_digest() FROM PUBLIC, anon, authenticated'));
});
