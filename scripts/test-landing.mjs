// בדיקת דף הנחיתה: אין הבטחות AI מחוץ לרשימות החבילות ולתוסף השיווק (שנשארו להחלטה נפרדת),
// הסעיף "מה עושים כל יום" מציג רק יכולות קיימות, והדף תקין ב-390px ובדסקטופ (גלישה, קישורים, ניווט, קונסולה).
import http from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
async function loadChromium() {
  try { return (await import('playwright')).chromium; } catch (_) {
    return (await import('/opt/node22/lib/node_modules/playwright/index.mjs')).chromium;
  }
}
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.txt': 'text/plain' };
const server = http.createServer((req, res) => {
  const path = decodeURIComponent(req.url.split('?')[0]);
  const file = join(root, path === '/' ? 'landing.html' : path);
  if (!file.startsWith(root) || !existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' });
  res.end(readFileSync(file));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${server.address().port}`;
const browser = await (await loadChromium()).launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

async function open(width, height) {
  const ctx = await browser.newContext({ locale: 'he-IL', viewport: { width, height } });
  await ctx.route(url => !url.href.startsWith(BASE), r => r.abort());
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|ERR_FAILED|net::/.test(m.text())) errors.push(`console: ${m.text().slice(0, 160)}`); });
  await page.goto(`${BASE}/landing.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(600);
  return { page, ctx, errors };
}

// תוכן
const html = readFileSync(join(root, 'landing.html'), 'utf-8');
const body = html.slice(html.indexOf('<body'));
const strip = t => t.replace(/<script[\s\S]*?<\/script>/g, m => m); // הסקריפט נשאר: שם נמצאים נתוני החלונית
const agents = body.slice(body.indexOf('id="agents"'), body.indexOf('id="industries"'));
check(!/AI|בינה מלאכותית|חכם/.test(agents.replace(/ההודעות והתסריטים/g, '')), 'סעיף "מה עושים כל יום" לא מבטיח AI או "חכם"');
check((agents.match(/class="agent-card"/g) || []).length === 5, 'בסעיף חמישה כרטיסים, באותו מבנה');
check(/מסך "היום"/.test(agents) && /הודעות WhatsApp מוכנות/.test(agents) && /אימיילים ותסריטי שיחה/.test(agents) && /יומן מהיר/.test(agents), 'הסעיף מתאר את מסך "היום", ההודעות, האימיילים והתסריטים והיומן המהיר');
check(!/סוכן התמיכה|בכל שעה|סוכן המוטיבציה|סוכן השיווק|כותב הצעות/.test(body), 'אין עוד טענות על סוכן תמיכה, מוטיבציה או שיווק');
const head = html.slice(0, html.indexOf('</head>'));
check(!/עוזר AI|AI/.test(head.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<script[\s\S]*?<\/script>/g, '')), 'תיאורי ה-SEO וה-OG לא מזכירים AI');
const faq = body.slice(body.indexOf('id="faq"'), body.indexOf('id="trust-section"'));
check(!/AI אמיתי/.test(faq) && /תבניות שנכתבו מראש/.test(faq), 'השאלה הנפוצה על AI הוחלפה בתשובה מדויקת');
// מה שנשאר בכוונה (החלטה נפרדת): רשימות החבילות ותוסף השיווק
const left = [...body.matchAll(/AI|בינה מלאכותית/g)].length;
console.log(`ℹ️ ${left} אזכורי AI/בינה מלאכותית בגוף הדף: שניים ברשימות החבילות (שנשארו להחלטה נפרדת) ואחד בשאלה הנפוצה שמסבירה שאין AI`);

for (const [w, h, label] of [[390, 844, 'נייד 390px'], [1280, 800, 'דסקטופ 1280px']]) {
  const { page, ctx, errors } = await open(w, h);
  const r = await page.evaluate(() => {
    const doc = document.documentElement;
    const cards = [...document.querySelectorAll('#agents .agent-card')];
    const overflowing = cards.filter(c => c.scrollWidth > c.clientWidth + 1).length;
    const ctas = [...document.querySelectorAll('a.btn-primary, a.nav-cta, a.plan-btn, a.btn-marketing')].map(a => a.getAttribute('href'));
    const navLinks = [...document.querySelectorAll('#navMenuPanel a[href^="#"]')].map(a => ({ href: a.getAttribute('href'), ok: !!document.querySelector(a.getAttribute('href')), text: a.textContent.trim() }));
    const small = [...document.querySelectorAll('#agents .agent-desc, #agents .agent-title')].filter(e => parseFloat(getComputedStyle(e).fontSize) < 13).length;
    return { overflowX: doc.scrollWidth - innerWidth, overflowing, ctas, navLinks, small, dir: getComputedStyle(document.body).direction, cards: cards.length };
  });
  check(r.overflowX <= 0, `${label}: אין גלישה אופקית`);
  check(r.cards === 5 && r.overflowing === 0 && r.small === 0, `${label}: חמשת הכרטיסים נקראים בלי חיתוך וגודל הטקסט תקין`);
  check(r.dir === 'rtl', `${label}: כיוון RTL`);
  check(r.ctas.length >= 6 && r.ctas.every(h => h && h.startsWith('https://realestate.plto.app')), `${label}: כל כפתורי ההרשמה מצביעים למערכת (${r.ctas.length})`);
  check(r.navLinks.length === 6 && r.navLinks.every(n => n.ok) && r.navLinks.some(n => n.text === 'מה עושים כל יום'), `${label}: קישורי התפריט מצביעים לסעיפים קיימים`);
  if (w === 390) {
    await page.click('.nav-menu-btn');
    await page.click('#navMenuPanel a[href="#agents"]');
    await page.waitForTimeout(900);
    const y = await page.evaluate(() => Math.round(document.querySelector('#agents').getBoundingClientRect().top));
    check(Math.abs(y - 76) < 60, `${label}: הקישור "מה עושים כל יום" גולל לסעיף (top=${y})`);
    await page.locator('#agents').scrollIntoViewIfNeeded();
    await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', '-m.png') }).catch(() => {});
    // חלוניות התחום ושאלה נפוצה
    await page.evaluate(() => openVpModal('realestate'));
    const items = await page.evaluate(() => [...document.querySelectorAll('#vpModalList li')].map(l => l.textContent));
    check(items.length === 3 && !items.some(t => /AI/.test(t)), `${label}: חלונית התחום תקינה ובלי AI`);
  } else {
    await page.locator('#agents').scrollIntoViewIfNeeded();
    await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', '-d.png') }).catch(() => {});
  }
  check(errors.length === 0, `${label}: אין שגיאות בקונסולה` + (errors.length ? ': ' + errors.join(' | ') : ''));
  await ctx.close();
}
await browser.close(); server.close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
