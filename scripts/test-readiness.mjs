// בדיקת המוכנות להשקה (3.11.2026): טלפון לא תקין לא נשמר, אין "~~" כממלא מקום, ואין הבטחות לדברים
// שלא קיימים (AI כבוי, תזכורת סוף ניסיון שלא נשלחת, שמירת לידי דמו). רצה מול Supabase מדומה.
import { startHarness } from './lib/harness.mjs';
import { readFileSync } from 'node:fs';

const { page, errors, close } = await startHarness({ viewport: { width: 390, height: 844 } });
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

// 1. טלפון שהוזן ידנית
const v = await page.evaluate(() => ['abc', '050-1234567', '+972 50 123 4567', '(03) 555-1234', '12345', '050abc1234', ''].map(p => [p, phoneLooksValid(p)]));
check(JSON.stringify(v) === JSON.stringify([['abc', false], ['050-1234567', true], ['+972 50 123 4567', true], ['(03) 555-1234', true], ['12345', false], ['050abc1234', false], ['', false]]), 'phoneLooksValid: ספרות ותווי חיוג, 7 עד 15 ספרות');

const r = await page.evaluate(async () => {
  window.demoGuard = () => false;
  const inserts = [];
  const orig = DB.addLead;
  DB.addLead = async (l) => { inserts.push(l); return { ...l, id: 'x' }; };
  const toasts = [];
  const origToast = window.toast;
  window.toast = (m, t) => { toasts.push([m, t]); };
  openModal?.('modal-add-lead');
  document.getElementById('new-lead-name').value = 'בדיקה';
  document.getElementById('new-lead-phone').value = 'abc';
  document.getElementById('new-lead-notes').value = 'הערה';
  await addLead(true);
  window.toast = origToast; DB.addLead = orig;
  return { inserts: inserts.length, toasts };
});
check(r.inserts === 0 && r.toasts.some(([m, t]) => m === 'מספר הטלפון לא תקין' && t === 'error'), 'הוספת ליד עם טלפון "abc" נחסמת עם הודעה בעברית');

// 2. חבילות במסך התשלום: בלי "AI שיווקי מתקדם" כשה-AI כבוי
const plans = await page.evaluate(() => (typeof AI !== 'undefined' && !AI.ENABLED) ? Billing.renderPlansHTML?.() || document.body.innerHTML : null);
if (plans !== null) check(!/AI שיווקי מתקדם/.test(plans), 'מסך התשלום לא מציג "AI שיווקי מתקדם" כשה-AI כבוי');

// 3. טקסטים: בלי "~~", בלי הבטחות שלא מתקיימות, בלי שגיאות שנמצאו
const src = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const visible = src.split('\n').filter(l => !/^\s*\/\//.test(l)).join('\n');
check(!/~~/.test(visible), 'אין "~~" כממלא מקום ב-index.html');
check(!/~~/.test(readFileSync(new URL('../admin.html', import.meta.url), 'utf8')) && !/~~/.test(readFileSync(new URL('../sign.html', import.meta.url), 'utf8')), 'אין "~~" ב-admin.html וב-sign.html');
for (const [re, why] of [
  [/נשלח לך תזכורת|נשלח לך <strong>תזכורת/, 'תזכורת סוף ניסיון שלא נשלחת'],
  [/הרשמה תשמור אותם|לשמור אותם לצמיתות/, 'שמירת לידי דמו שלא קורית'],
  [/נציג AI עונה מיד, ואם/, 'נציג AI בתמיכה בלי תנאי'],
  [/הנחה לחבר/, 'הנחה לחבר שלא קיימת'],
  [/הסוכן החכם (יכתוב|מזהה)/, 'סוכן חכם כשה-AI כבוי'],
  [/מומלץ כשיש עמלה/, 'עמלה שחסומה'],
  [/נסיון/, 'שגיאת כתיב "נסיון"'],
  [/מינוי שנתי/, 'שגיאת כתיב "מינוי"'],
  [/מה היה התוצאה/, '"מה היה התוצאה"'],
  [/השתמש בـ/, 'ציווי בלשון זכר ותו ערבי'],
  [/PLTO Sales · מערכת/, 'נקודה אמצעית בכותרת מסך הכניסה'],
]) check(!re.test(src), 'אין ' + why);

check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
console.log(failures ? `\n${failures} בדיקות נכשלו` : '\nכל הבדיקות עברו');
process.exit(failures ? 1 : 0);
