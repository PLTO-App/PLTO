// Run: node --experimental-strip-types --test supabase/tests/notify-owner-validate.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPayload, makeLimiter, EVENTS, MAX_BODY_BYTES } from '../functions/notify-owner/validate.ts';

const agent = { email: 'Agent@Example.com' };
const admin = { email: 'info@plto.app' };

test('rejects non-object and unknown events', () => {
  for (const bad of [null, 'x', 5, {}, { event: 5 }, { event: 'deal.closed' }, { event: '__proto__' }, { event: 'toString' }]) {
    const r = buildPayload(bad, agent);
    assert.equal(r.ok, false);
    assert.equal((r as { status: number }).status, 400);
  }
});

test('support.needs_human: allowed fields only, email from the session', () => {
  const r = buildPayload({
    event: 'support.needs_human',
    data: { ticket_id: 'abc', message: 'hi', agent_email: 'spoof@evil.test', is_admin: 'yes', tenant_name: 'T' },
  }, agent);
  assert.equal(r.ok, true);
  const p = (r as { payload: Record<string, string> }).payload;
  assert.equal(p.event, 'support.needs_human');
  assert.equal(p.agent_email, 'agent@example.com');
  assert.equal(p.is_admin, undefined);
  assert.equal(p.message, 'hi');
});

test('required fields are enforced', () => {
  const r = buildPayload({ event: 'support.needs_human', data: { message: 'x' } }, agent);
  assert.equal(r.ok, false);
  assert.equal((r as { error: string }).error, 'missing_ticket_id');
  assert.equal(buildPayload({ event: 'full_service_request', data: { name: 'a' } }, agent).ok, false);
  assert.equal(buildPayload({ event: 'idea_suggestion', data: {} }, agent).ok, false);
});

test('admin-only event: forbidden for a normal user, allowed for an admin, keeps the ticket owner address', () => {
  const data = { ticket_id: '1', agent_email: 'owner@client.test', response: 'ok' };
  const denied = buildPayload({ event: 'support.admin_replied', data }, agent);
  assert.equal(denied.ok, false);
  assert.equal((denied as { status: number }).status, 403);
  const ok = buildPayload({ event: 'support.admin_replied', data }, admin);
  assert.equal(ok.ok, true);
  assert.equal((ok as { payload: Record<string, string> }).payload.agent_email, 'owner@client.test');
  assert.equal(buildPayload({ event: 'support.admin_replied', data }, { email: null }).ok, false);
});

test('values are trimmed and truncated to the field limit', () => {
  const r = buildPayload({ event: 'idea_suggestion', data: { text: '  ' + 'x'.repeat(5000) + '  ', category: 'c' } }, agent);
  assert.equal(r.ok, true);
  assert.equal((r as { payload: Record<string, string> }).payload.text.length, EVENTS.idea_suggestion.fields.text.max);
});

test('non-string values are ignored, numbers are stringified', () => {
  const r = buildPayload({ event: 'upgrade_request', data: { plan: 12, plan_name: { a: 1 }, tenant_id: ['x'] } }, agent);
  assert.equal(r.ok, true);
  const p = (r as { payload: Record<string, string> }).payload;
  assert.equal(p.plan, '12');
  assert.equal(p.plan_name, undefined);
  assert.equal(p.tenant_id, undefined);
});

test('limiter allows N per window and resets after it', () => {
  let t = 0;
  const allow = makeLimiter(3, 1000, () => t);
  assert.deepEqual([allow('u'), allow('u'), allow('u'), allow('u')], [true, true, true, false]);
  assert.equal(allow('other'), true);
  t = 1001;
  assert.equal(allow('u'), true);
});

test('body cap constant is sane', () => {
  assert.equal(MAX_BODY_BYTES, 8192);
});
