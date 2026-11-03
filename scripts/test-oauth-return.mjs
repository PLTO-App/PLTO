// חזרה מ-Google OAuth: כניסה טרייה לא מנותקת בגלל בדיקת 30 הימים, והנתונים נטענים פעם אחת.
// רקע: משתמש חדש (בלי חותמת פעילות במכשיר) נותק מיד אחרי ההרשמה הראשונה וקיבל
// "שגיאה בטעינת הנתונים", כי INITIAL_SESSION הגיע לפני SIGNED_IN ונחשב session ישן.
// שימוש: node scripts/test-oauth-return.mjs
import { startHarness, SUPABASE_MOCK } from './lib/harness.mjs';

const SESSION = "{user:{id:'00000000-0000-0000-0000-0000000000aa',email:'new.user@example.com',user_metadata:{full_name:'New User'}}}";
const ORIGINAL = "onAuthStateChange: function(cb){ setTimeout(function(){ cb('INITIAL_SESSION',null); },50); return {data:{subscription:{unsubscribe:noop}}}; },";
const ORIGINAL_SIGNOUT = "signOut: function(){ return Promise.resolve({error:null}); },";

function mockWith(events) {
  if (!SUPABASE_MOCK.includes(ORIGINAL) || !SUPABASE_MOCK.includes(ORIGINAL_SIGNOUT)) throw new Error('harness mock changed, update this test');
  const fire = events.map((e, i) => `setTimeout(function(){ cb('${e}', ${SESSION}); }, ${50 + i * 10});`).join(' ');
  return SUPABASE_MOCK
    .replace(ORIGINAL, `onAuthStateChange: function(cb){ ${fire} return {data:{subscription:{unsubscribe:noop}}}; },`)
    .replace(ORIGINAL_SIGNOUT, "signOut: function(){ window.__signOuts = (window.__signOuts||0) + 1; return Promise.resolve({error:null}); },");
}

async function measure(page) {
  await page.waitForTimeout(1500);
  return page.evaluate(() => ({
    signOuts: window.__signOuts || 0,
    ensureCalls: (window.__sbCalls || []).filter(c => c.fn === 'ensure_agent_and_tenant').length,
    inApp: !document.getElementById('app-shell').classList.contains('hidden'),
    errorToast: [...document.querySelectorAll('.toast')].some(t => /שגיאה בטעינת הנתונים/.test(t.textContent)),
  }));
}

const results = [];
function check(name, got, want) {
  const ok = Object.entries(want).every(([k, v]) => got[k] === v);
  results.push({ name, ok, got });
}

// א. חזרה מ-Google, אין חותמת פעילות, INITIAL_SESSION לפני SIGNED_IN (התרחיש שנכשל בחי)
{
  const h = await startHarness({ demo: false, urlPath: '/#access_token=test&token_type=bearer', supabaseMock: mockWith(['INITIAL_SESSION', 'SIGNED_IN']) });
  check('א. OAuth, INITIAL_SESSION first: no sign-out, one load, in app', await measure(h.page), { signOuts: 0, ensureCalls: 1, inApp: true, errorToast: false });
  await h.close();
}
// ב. אותו מצב, SIGNED_IN לפני INITIAL_SESSION
{
  const h = await startHarness({ demo: false, urlPath: '/#access_token=test&token_type=bearer', supabaseMock: mockWith(['SIGNED_IN', 'INITIAL_SESSION']) });
  check('ב. OAuth, SIGNED_IN first: no sign-out, one load, in app', await measure(h.page), { signOuts: 0, ensureCalls: 1, inApp: true, errorToast: false });
  await h.close();
}
// ג. session ישן ששוחזר בלי חותמת פעילות: ההגנה הקיימת נשארת (ניתוק, בלי טעינה)
// ד. אותו דפדפן אחרי יציאה ל-Google: הסימון שנשמר לפני ההפניה מזהה חזרה טרייה גם בלי fragment
{
  const h = await startHarness({ demo: false, urlPath: '/', supabaseMock: mockWith(['INITIAL_SESSION']) });
  check('ג. stale restored session: signed out, not loaded', await measure(h.page), { signOuts: 1, ensureCalls: 0, inApp: false });
  await h.page.evaluate(() => localStorage.setItem('plto_oauth_pending', String(Date.now())));
  await h.page.reload({ waitUntil: 'domcontentloaded' });
  check('ד. pending flag only: no sign-out, one load, in app', await measure(h.page), { signOuts: 0, ensureCalls: 1, inApp: true, errorToast: false });
  check('ד. pending flag cleared after use', await h.page.evaluate(() => ({ cleared: localStorage.getItem('plto_oauth_pending') === null })), { cleared: true });
  if (h.errors.length) results.push({ name: 'JS errors', ok: false, got: h.errors });
  await h.close();
}

let failed = 0;
for (const r of results) {
  if (!r.ok) failed++;
  console.log(`${r.ok ? 'PASS' : 'FAIL'} ${r.name}${r.ok ? '' : ' ' + JSON.stringify(r.got)}`);
}
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
