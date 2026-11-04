// מסך התשלום אחרי סוף הניסיון, כשהתשלומים עוד לא פעילים (סבב הבדיקות של 4.11.2026, ממצאים 1 ו-2):
// "שמרו לי מקום" משאיר את המשתמש במסך עם אישור, שולח התראה אחת לבעלים, ולא מציג "ניסיון חינם" בכרטיסים.
import { startHarness } from './lib/harness.mjs';

let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const { page, errors, close } = await startHarness({ viewport: { width: 390, height: 844 } });

const r = await page.evaluate(async () => {
  const calls = [];
  sbClient.functions.invoke = (name, opts) => { calls.push({ name, event: opts?.body?.event }); return Promise.resolve({ data: {}, error: null }); };
  State.agent = Object.assign({}, State.agent, { email: 'someone@example.com' });
  State.tenant = Object.assign({}, State.tenant, {
    plan: 'trial',
    created_at: new Date(Date.now() - 50 * 864e5).toISOString(),
    trial_ends_at: new Date(Date.now() - 5 * 864e5).toISOString(),
  });
  const expired = Billing.isExpired();
  Billing.showPaywall();
  const visible = id => !document.getElementById(id).classList.contains('hidden');
  const cardsText = document.getElementById('paywall-plans-container').innerText;
  const btns = () => [...document.querySelectorAll('#paywall-plans-container button')];
  btns()[0].click();
  await new Promise(res => setTimeout(res, 300));
  const afterFirst = { paywall: visible('screen-paywall'), shell: visible('app-shell'), disabled: btns().every(b => b.disabled), note: document.getElementById('paywall-trial-note').textContent };
  Billing.openCheckout('pro');
  await new Promise(res => setTimeout(res, 300));
  return { expired, cardsText, afterFirst, ownerAlerts: calls.filter(c => c.name === 'notify-owner' && c.event === 'upgrade_request').length, paywallStill: visible('screen-paywall') };
});

check(r.expired, 'הניסיון מוגדר כמסתיים (מצב הבדיקה)');
check(!/ניסיון/.test(r.cardsText), 'בכרטיסי החבילות במסך התשלום אין "ניסיון חינם"');
check(r.afterFirst.paywall && !r.afterFirst.shell, 'אחרי "שמרו לי מקום" המשתמש נשאר במסך התשלום ולא נכנס לאפליקציה');
check(r.afterFirst.disabled, 'הכפתורים ננעלים אחרי הבקשה');
check(/קיבלנו את הבקשה לחבילת Solo/.test(r.afterFirst.note) && /24 שעות/.test(r.afterFirst.note), 'מוצג אישור במסך (' + r.afterFirst.note.trim() + ')');
check(r.ownerAlerts === 1, `נשלחה התראה אחת בלבד לבעלים, גם אחרי לחיצה נוספת (${r.ownerAlerts})`);
check(r.paywallStill, 'גם אחרי לחיצה נוספת המשתמש נשאר במסך התשלום');
check(errors.length === 0, 'אין שגיאות בדף' + (errors.length ? ': ' + errors.join(' | ') : ''));

await close();
console.log(failures ? `\n${failures} נכשלו` : '\nכל הבדיקות עברו');
process.exit(failures ? 1 : 0);
