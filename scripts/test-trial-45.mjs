// תקופת הניסיון של 45 יום (4.11.2026): ההרשמה במסד, הטקסטים באפליקציה ובדף הנחיתה, ופס הניסיון שסופר לפי האורך
// האמיתי של הניסיון של כל עסק (עסק ישן של 30 יום נשאר "מתוך 30"). רצה עם Supabase מדומה, ולכן לא מוכיחה את המסד החי.
import { startHarness } from './lib/harness.mjs';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = f => readFileSync(join(root, f), 'utf-8');
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

// ── המסד: ההרשמה יוצרת ניסיון של 45 יום, ושום דבר אחר בפונקציה לא השתנה ──
const mig = read('supabase/migrations/134_trial_45_days.sql');
check(/'trial', now\(\) \+ interval '45 days'/.test(mig), 'מיגרציה 134: עסק חדש נוצר עם ניסיון של 45 יום מרגע ההרשמה');
check(/ALTER COLUMN trial_ends_at SET DEFAULT \(now\(\) \+ interval '45 days'\)/.test(mig), 'מיגרציה 134: ברירת המחדל של העמודה היא 45 יום');
check(!/UPDATE\s+(public\.)?tenants/i.test(mig), 'מיגרציה 134 לא משנה עסקים קיימים');
check(/REVOKE EXECUTE[^;]+FROM anon;/.test(mig) && /GRANT\s+EXECUTE[^;]+TO authenticated;/.test(mig), 'מיגרציה 134 שומרת על ההרשאות (לא anon, כן authenticated)');
const body = f => (read(f).match(/CREATE OR REPLACE FUNCTION public\.ensure_agent_and_tenant[\s\S]*?\n\$\$;/) || [''])[0].split('\n').filter(l => !/^\s*--/.test(l)).join('\n');
check(body('supabase/migrations/109_signup_utm_attribution.sql').replace("interval '30 days'", "interval '45 days'") === body('supabase/migrations/134_trial_45_days.sql'),
  'גוף הפונקציה זהה ל-109 מלבד משך הניסיון');

// ── טקסטים: אין "30 יום" שמתאר את הניסיון. 30 יום של שמירת נתונים, תוקף הזמנה ותוקף הצעת מחיר נשארים ──
const TRIAL_30 = /30 (יום|ימים|ימי)[^<'"`\n]{0,12}(ניסיון|חינם|בחינם)|(ניסיון|חינם)[^<'"`\n]{0,14}\b30 (יום|ימים)|ל-30 יום|מתוך 30|30 ימים על חשבוננו|לנסות 30 יום|חינם 30 יום/;
for (const f of ['index.html', 'landing.html', 'sign.html', 'admin.html']) {
  const lines = read(f).split('\n').map((l, i) => [i + 1, l]).filter(([, l]) => TRIAL_30.test(l) && !/^\s*\/\//.test(l.trim()));
  check(lines.length === 0, `${f}: אין טקסט של 30 יום ניסיון` + (lines.length ? ': ' + lines.map(([n, l]) => `${n}: ${l.trim().slice(0, 70)}`).join(' | ') : ''));
}
const app = read('index.html'), landing = read('landing.html');
check((landing.match(/45 ימים חינם, ללא כרטיס אשראי/g) || []).length === 3, 'דף הנחיתה: תיאורי ה-SEO אומרים 45 ימים');
check(/45 יום חינם, מוכן תוך דקה/.test(landing) && /45 ימים על חשבוננו/.test(landing), 'דף הנחיתה: 45 יום בגיבור ובסגירה');
check(/🎁 45 יום ניסיון בחינם, ללא כרטיס אשראי/.test(app), 'מסך ההרשמה: 45 יום ניסיון בחינם');
check(/ניסיון חינמי של 45 יום ניתן לכל חשבון חדש[^<]*לאחר 45 יום יידרש מנוי/.test(app), 'תנאי השימוש: 45 יום');
check(/RETENTION_DAYS: 30,/.test(app) && /הנתונים נשמרים <strong>30 יום נוספים<\/strong>/.test(app), 'שמירת הנתונים אחרי הניסיון לא השתנתה (30 יום)');

// ── פס הניסיון ושער קישור הגיוס, בדפדפן ──
const { page, errors, close } = await startHarness();
const r = await page.evaluate(() => {
  const day = 864e5, now = Date.now();
  const iso = ms => new Date(ms).toISOString();
  const banner = document.getElementById('trial-banner') || Object.assign(document.body.appendChild(document.createElement('div')), { id: 'trial-banner' });
  const run = tenant => {
    State.tenant = { id: 't', plan: 'trial', ...tenant };
    Billing.renderTrialBanner();
    const fill = banner.querySelector('.trial-bar-fill');
    return { text: banner.textContent.replace(/\s+/g, ' '), pct: fill ? parseFloat(fill.style.width) : null, total: Billing.trialTotalDays(), start: Billing.trialStartMs() };
  };
  return {
    fresh: run({ created_at: iso(now), trial_ends_at: iso(now + 45 * day) }),
    mid: run({ created_at: iso(now - 20 * day), trial_ends_at: iso(now + 25 * day) }),
    old30: run({ created_at: iso(now - 10 * day), trial_ends_at: iso(now + 20 * day) }),
    noCreated: run({ trial_ends_at: iso(now + 45 * day) }),
    extended: run({ created_at: iso(now), trial_ends_at: iso(now + 400 * day) }),
    trialDays: Billing.TRIAL_DAYS, now,
  };
});
check(r.trialDays === 45, 'Billing.TRIAL_DAYS הוא 45');
check(/45 ימים/.test(r.fresh.text) && /מתוך 45/.test(r.fresh.text) && r.fresh.pct === 100, `עסק חדש: "45 ימים", "מתוך 45", הפס מלא (${r.fresh.pct}%)`);
check(/25 ימים/.test(r.mid.text) && /מתוך 45/.test(r.mid.text) && r.mid.pct === 56, `אחרי 20 יום: 25 ימים מתוך 45, ${r.mid.pct}%`);
check(/מתוך 30/.test(r.old30.text) && r.old30.pct === 67 && r.old30.pct <= 100, `עסק ישן של 30 יום נשאר "מתוך 30" (${r.old30.pct}%)`);
check(r.noCreated.total === 45 && /מתוך 45/.test(r.noCreated.text), 'בלי תאריך הרשמה: נופל ל-45');
check(Math.abs(r.noCreated.start - (r.now)) < 5000, 'בלי תאריך הרשמה: תחילת הניסיון מחושבת מ-45 יום לפני הסיום');
check(r.extended.text.trim() === '' , 'ניסיון שהוארך מעבר לשנה: הפס מוסתר כמו קודם');
check(Math.abs(r.mid.start - (r.now - 20 * 864e5)) < 5000, 'תחילת הניסיון לפי תאריך ההרשמה (בשביל קישור הגיוס אחרי 20 יום)');
check(errors.length === 0, 'אין שגיאות בדף' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
console.log(failures ? `\n${failures} נכשלו` : '\nכל הבדיקות עברו');
process.exit(failures ? 1 : 0);
