// כל עוד ה-AI כבוי, הצעת המנוי השנתי (שמוכרת שיווק AI) לא מוצגת באף כניסה, ואין בקוד הבטחות ישנות
// ל-14 יום ניסיון או לתוכן AI בחנות ה-XP. רצה עם Supabase מדומה.
import { startHarness } from './lib/harness.mjs';
import { readFileSync } from 'node:fs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const r = await page.evaluate(async () => {
  State.isDemo = false;
  const gd = Gamify.get();
  gd.streak = 20; gd.dayCount = 20;
  const out = { aiEnabled: AI.ENABLED };
  out.eligible = AnnualUpsell._isEligible();
  let wrap = document.getElementById('dash-growth-card-wrap');
  if (!wrap) { wrap = document.createElement('div'); wrap.id = 'dash-growth-card-wrap'; document.body.appendChild(wrap); }
  localStorage.removeItem('plto_growth_card_v1');
  Dashboard.renderGrowthCard();
  out.card = wrap.textContent;
  AnnualUpsell.tryShow('streak_10');
  await new Promise(res => setTimeout(res, 2600));   // ההצעה נפתחת אחרי השהיה של 1.8 שניות
  out.modal = !!document.querySelector('.aum-saving-card, .aum-roi-card');
  return out;
});
check(r.aiEnabled === false, 'ה-AI כבוי בדפדפן');
check(r.eligible === false, 'משתמש עם רצף של 20 יום לא זכאי להצעת המנוי השנתי');
check(!/חסוך|שיווק AI|1,858/.test(r.card), 'כרטיס הבית לא מציע מנוי שנתי עם שיווק AI');
check(r.modal === false, 'חלון ההצעה לא נפתח');

const tour = await page.evaluate(() => { GuidedTour._cachedSteps = null; return GuidedTour._getSteps().map(x => x.title + ' ' + x.text).join(' | '); });
check(!/סוכן השיווק|כותב בשבילך/.test(tour), 'סיור ההיכרות לא מבטיח "סוכן שיווק" שכותב תוכן כשה-AI כבוי');

const src = readFileSync(new URL('../index.html', import.meta.url), 'utf-8');
check(!/14 יום ניסיון/.test(src), 'אין עוד אזכור של 14 יום ניסיון (הניסיון הוא 30 יום)');
check(!/בתוכן AI שימושי/.test(src), 'חנות ה-XP והסיור לא מבטיחים תוכן AI (הפרסים הם ערכות מכירה כתובות)');
check(!/label: 'תיבת דואר'/.test(src) && !/data-screen="email"/.test(src), 'תיבת הדואר לא מופיעה בתפריט הצד ובתפריט "עוד"');
check(/NOT_RESTORABLE = new Set\([^)]*'email'/.test(src), 'קישור ישיר (?s=email) לא פותח את מסך תיבת הדואר');
check(/💚 יש עניין\|💚 מעוניין/.test(src), 'קריאת תגובת הלקוח מקבלת גם את התווית הישנה השמורה במסד');

check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
