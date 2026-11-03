// doc.html: הדף שהלקוח פותח מקישור למסמך. הפונקציה document-share מדומה כאן, ולכן הבדיקה לא מוכיחה
// שהקישור החי עובד. היא בודקת שהדף מעביר לקישור החתום רק כשהתשובה תקינה, ומציג הודעה בעברית בכל מצב אחר,
// בלי לכתוב ל-HTML שום דבר מהכתובת או מהשרת, ובלי גלישה לרוחב ב-360px.
import { startHarness } from './lib/harness.mjs';

const { ctx, BASE, close } = await startHarness({ viewport: { width: 360, height: 740 }, demo: false });
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const FN = 'https://scyfywvzoogfrlalgftv.supabase.co/functions/v1/document-share';
const TOKEN = 'cd'.repeat(32);
const SIGNED = 'https://scyfywvzoogfrlalgftv.supabase.co/storage/v1/object/sign/lead-documents/t/l/1_a.pdf?token=short';

let reply = { status: 200, body: { url: SIGNED } };
const calls = [];
await ctx.route(`${FN}**`, r => {
  calls.push(r.request().url());
  return r.fulfill({ status: reply.status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(reply.body) });
});
await ctx.route('**/storage/v1/object/sign/**', r => r.fulfill({ status: 200, contentType: 'application/pdf', headers: { 'content-disposition': 'attachment; filename="a.pdf"' }, body: '%PDF-1.4' }));

async function open(q) {
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
  const navs = [];
  page.on('request', req => { if (req.isNavigationRequest()) navs.push(req.url()); });
  await page.goto(BASE + '/doc.html' + q, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(400);
  const state = await page.evaluate(() => ({
    title: document.getElementById('doc-title').textContent,
    text: document.getElementById('doc-text').textContent,
    action: document.getElementById('doc-action').hidden ? '' : document.getElementById('doc-action').textContent,
    overflow: document.scrollingElement.scrollWidth > innerWidth,
    html: document.body.innerHTML,
    dir: document.documentElement.dir,
  }));
  return { page, errors, navs, state };
}

// 1. טוקן תקין: מעבר לקישור החתום, והודעה שהמסמך מוכן
reply = { status: 200, body: { url: SIGNED } };
let r = await open('?t=' + TOKEN);
check(calls.at(-1) === `${FN}?t=${TOKEN}`, 'הדף פונה לפונקציה עם הטוקן');
check(r.navs.includes(SIGNED), 'טוקן תקין: מעבר לקישור החתום');
check(r.state.title === 'המסמך מוכן' && r.state.action === 'הורדת המסמך', 'טוקן תקין: "המסמך מוכן" וכפתור הורדה חוזרת');
check(r.state.dir === 'rtl' && !r.state.overflow, 'RTL ובלי גלישה לרוחב ב-360px');
check(r.errors.length === 0, 'בלי שגיאות קונסולה' + (r.errors.length ? ': ' + r.errors.join(' | ') : ''));
const before = calls.length;
await r.page.click('#doc-action');
await r.page.waitForTimeout(300);
check(calls.length === before + 1, 'כפתור ההורדה מבקש קישור חתום חדש');
await r.page.close();

// 2. טוקן שפג, בוטל או לא קיים
reply = { status: 404, body: { error: 'unavailable' } };
r = await open('?t=' + TOKEN);
check(r.state.title === 'הקישור לא זמין' && /פג או שהוא בוטל/.test(r.state.text) && r.state.action === '', 'טוקן לא זמין: הודעה בעברית בלי כפתור');
check(!r.navs.some(u => u.includes('/object/sign/')), 'טוקן לא זמין: אין מעבר לקובץ');
await r.page.close();

// 3. טוקן בפורמט שגוי: לא פונים לשרת בכלל, ושום דבר מהכתובת לא נכתב לדף
const n = calls.length;
r = await open('?t=<img src=x onerror=alert(1)>');
check(calls.length === n, 'טוקן בפורמט שגוי: אין פנייה לשרת');
check(r.state.title === 'הקישור לא זמין' && !/onerror|<img/.test(r.state.html), 'טוקן בפורמט שגוי: הודעה קבועה, בלי תוכן מהכתובת');
await r.page.close();
r = await open('');
check(r.state.title === 'הקישור לא זמין', 'בלי טוקן: "הקישור לא זמין"');
await r.page.close();

// 4. הגבלת קצב ושגיאת שרת: הודעה וכפתור לניסיון נוסף
reply = { status: 429, body: { error: 'rate_limited' } };
r = await open('?t=' + TOKEN);
check(r.state.title === 'יותר מדי ניסיונות' && r.state.action === 'ניסיון נוסף', 'הגבלת קצב: הודעה וכפתור ניסיון נוסף');
await r.page.close();
reply = { status: 500, body: { error: 'error' } };
r = await open('?t=' + TOKEN);
check(r.state.title === 'משהו השתבש' && r.state.action === 'ניסיון נוסף', 'שגיאת שרת: הודעה וכפתור ניסיון נוסף');
reply = { status: 200, body: { url: SIGNED } };
await r.page.click('#doc-action');
await r.page.waitForTimeout(400);
check(await r.page.evaluate(() => document.getElementById('doc-title').textContent) === 'המסמך מוכן', 'ניסיון נוסף אחרי שגיאה מצליח');
await r.page.close();

// 5. תשובה תקינה עם כתובת שאינה קישור חתום של האחסון: לא עוברים אליה
reply = { status: 200, body: { url: 'https://evil.example/phish' } };
r = await open('?t=' + TOKEN);
check(!r.navs.some(u => u.includes('evil.example')) && r.state.title === 'משהו השתבש', 'כתובת זרה בתשובה: אין מעבר אליה');
await r.page.close();

await close();
console.log(failures ? `\n${failures} בדיקות נכשלו` : '\nכל הבדיקות עברו');
process.exit(failures ? 1 : 0);
