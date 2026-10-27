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
// רשימות החבילות: רק יכולות פעילות, ובלי שינוי במבנה (3 חבילות, 5, 5 ו-4 שורות)
const plans = [...body.matchAll(/<ul class="plan-features">([\s\S]*?)<\/ul>/g)].map(m => [...m[1].matchAll(/<li>([^<]*)<\/li>/g)].map(x => x[1]));
check(plans.length === 3 && plans.every(l => !l.some(x => /AI/.test(x))), 'רשימות החבילות לא מבטיחות AI');
check(JSON.stringify(plans.map(l => l.length)) === JSON.stringify([5, 4, 3]), 'מבנה החבילות נשמר (5, 4 ו-3 שורות, אחרי הסרת תמיכה בעדיפות)');
check(/הודעות, אימיילים ותסריטי שיחה מוכנים/.test(plans[0].join('|')) && /יומן מהיר/.test(plans[0].join('|')), 'חבילת Solo מציגה את היכולות הקיימות שהחליפו את שתי ההבטחות');
const app = readFileSync(join(root, 'index.html'), 'utf-8');
check(!/עדיפות/.test(body) && !/20% הנחה/.test(body + app), 'אין הבטחה לתמיכה בעדיפות או ל-20% הנחה בהפניות, בדף ובאפליקציה');
check(/<title>PLTO Sales: /.test(html) && /<title>PLTO Sales: /.test(app) && /PLTO Sales · מערכת המכירות לעסקים/.test(app), 'המיתוג הגלוי PLTO Sales בכותרות הדף והאפליקציה ובמסך הכניסה');
const aiLeft = [...body.replace(/<!--[\s\S]*?-->/g, '').matchAll(/AI|בינה מלאכותית/g)].length;
check(aiLeft === 1 && /בינה מלאכותית/.test(faq), 'האזכור היחיד שנשאר בגוף הדף הוא השאלה הנפוצה שמסבירה שאין AI');

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
  check(r.navLinks.length === 5 && !r.navLinks.some(n => n.href === '#pricing') && r.navLinks.every(n => n.ok) && r.navLinks.some(n => n.text === 'מה עושים כל יום'), `${label}: קישורי התפריט מצביעים לסעיפים קיימים`);
  const hero = await page.evaluate(() => {
    const h = document.querySelector('.hero');
    const cta = document.getElementById('hero-cta-btn');
    const r = cta.getBoundingClientRect();
    const ctas = h.querySelectorAll('a[href^="https://realestate.plto.app"]').length;
    const vis = el => !!el && el.getClientRects().length > 0 && getComputedStyle(el).display !== 'none';
    return {
      ctaAboveFold: r.top >= 0 && r.bottom <= innerHeight, ctaText: cta.textContent.trim(), ctas,
      h1: h.querySelector('h1').innerText.replace(/\s+/g, ' ').trim(),
      points: h.querySelectorAll('.hero-points li').length,
      pointsAboveFold: [...h.querySelectorAll('.hero-points li')].every(li => li.getBoundingClientRect().bottom <= innerHeight),
      noPreviews: !h.querySelector('.vertical-previews, .vp-value'),
      addonHidden: [...document.querySelectorAll('.plan-addon, .marketing-section')].every(el => !vis(el)),
      plans: document.querySelectorAll('.plan-card').length,
      pricingHidden: !vis(document.getElementById('pricing')),
      // תקופת צמיחה חינמית: בטקסט הגלוי אין ניסיון, חבילות או מחיר חודשי
      paidText: (document.body.innerText.match(/ניסיון חינם|ימי ניסיון|\/חודש|לשדרג|חבילה בתשלום/g) || []),
    };
  });
  check(hero.ctaAboveFold && hero.ctas === 1 && hero.ctaText === 'מתחילים בחינם', `${label}: במסך הראשון כפתור אחד, גלוי בלי גלילה`);
  check(/הלידים כבר אצלך/.test(hero.h1) && hero.points === 3 && hero.pointsAboveFold && hero.noPreviews, `${label}: המסך הראשון קצר: כותרת, משפט, כפתור ושלוש נקודות`);
  check(hero.addonHidden && hero.plans >= 3 && hero.pricingHidden, `${label}: תוסף השיווק וסעיף התמחור מוסתרים, והחבילות נשארו בקוד לעתיד`);
  check(hero.paidText.length === 0, `${label}: אין בטקסט הגלוי ניסיון, מחיר חודשי או שדרוג` + (hero.paidText.length ? ': ' + hero.paidText.join(', ') : ''));
  if (w === 390) {
    await page.click('.nav-menu-btn');
    await page.click('#navMenuPanel a[href="#agents"]');
    await page.waitForTimeout(900);
    const y = await page.evaluate(() => Math.round(document.querySelector('#agents').getBoundingClientRect().top));
    check(Math.abs(y - 76) < 60, `${label}: הקישור "מה עושים כל יום" גולל לסעיף (top=${y})`);
    await page.locator('#agents').scrollIntoViewIfNeeded();
    await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', '-m.png') }).catch(() => {});
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
