// Verifies that tracking RPCs are really sent, with a Supabase mock that behaves like the real builder
// (thenable, no .catch). Usage: node tracking-requests.test.mjs <root>
import { startHarness } from './lib/harness.mjs';
const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };
await page.evaluate(() => { window.__sbCalls = []; });
const threw = await page.evaluate(() => { try { FunnelTracker.track('stage2_probe', { a: 1 }); return null; } catch (e) { return e.message; } });
await page.waitForTimeout(200);
const calls = await page.evaluate(() => window.__sbCalls.filter(c => c.fn === 'track_funnel_event'));
check(calls.length === 1 && calls[0].args.p_event_name === 'stage2_probe', 'FunnelTracker.track שולח track_funnel_event (נשלחו: ' + calls.length + ')');
check(calls.length === 1 && !('p_tenant_id' in calls[0].args), 'מבקר לפני התחברות (State.tenant הוא עסק הדמו t1): לא נשלח p_tenant_id, כי השרת גוזר אותו');
await page.evaluate(() => { window.__sbCalls = []; });
const loggedIn = await page.evaluate(async () => {
  State.tenant = { id: '5b0e9d3a-7c11-4f6e-9a52-0d1f3c8e7a10', name: 'עסק בדיקה', plan: 'trial' };
  FunnelTracker.track('upgrade_intent', { plan: 'pro' });
  FunnelTracker.track('signup_completed', { method: 'email' });
  await new Promise(r => setTimeout(r, 200));
  return window.__sbCalls.filter(c => c.fn === 'track_funnel_event').map(c => ({ name: c.args.p_event_name, keys: Object.keys(c.args).sort(), data: c.args.p_event_data, sid: c.args.p_session_id }));
});
check(loggedIn.length === 2 && loggedIn.every(c => !c.keys.includes('p_tenant_id')), 'משתמש מחובר: שני אירועים נשלחו בלי p_tenant_id (נשלחו: ' + loggedIn.length + ')');
check(loggedIn.every(c => c.keys.join() === 'p_event_data,p_event_name,p_session_id' && typeof c.sid === 'string' && c.sid.length >= 8 && c.sid.length <= 64), 'הפרמטרים תואמים לחתימה החדשה, ואורך session_id בטווח 8 עד 64');
check(loggedIn[0]?.data?.plan === 'pro' && loggedIn[1]?.data?.method === 'email', 'נתוני האירוע נשמרו');
await page.evaluate(() => { window.__sbCalls = []; });
const trackerErr = await page.evaluate(async () => {
  try {
    const p = sbClient.rpc('mark_lead_tracker_messages_read', { p_lead_id: 'x' });
    return typeof p.catch;
  } catch (e) { return 'threw: ' + e.message; }
});
check(trackerErr === 'undefined', 'המוק מתנהג כמו הספרייה האמיתית: ל-rpc() אין catch (' + trackerErr + ')');
check(!errors.some(e => /catch is not a function/.test(e)), 'אין שגיאות "catch is not a function" בקונסולה');
await close();
console.log(failures ? failures + ' נכשלו' : 'הכל עבר');
process.exit(failures ? 1 : 0);
