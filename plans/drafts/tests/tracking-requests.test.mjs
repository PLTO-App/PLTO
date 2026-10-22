// Verifies that tracking RPCs are really sent, with a Supabase mock that behaves like the real builder
// (thenable, no .catch). Usage: node tracking-requests.test.mjs <root>
import { startHarness } from '../../../scripts/lib/harness.mjs';
// יעד סופי: scripts/test-tracking-requests.mjs (והנתיב ל-harness יהיה ./lib/harness.mjs)
const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };
await page.evaluate(() => { window.__sbCalls = []; });
const threw = await page.evaluate(() => { try { FunnelTracker.track('stage2_probe', { a: 1 }); return null; } catch (e) { return e.message; } });
await page.waitForTimeout(200);
const calls = await page.evaluate(() => window.__sbCalls.filter(c => c.fn === 'track_funnel_event'));
check(calls.length === 1 && calls[0].args.p_event_name === 'stage2_probe', 'FunnelTracker.track שולח track_funnel_event (נשלחו: ' + calls.length + ')');
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
