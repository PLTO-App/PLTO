// סבבי דף הנחיתה של 4.11.2026: הכותרת (לבנה, שתי שורות בדיוק, העליונה מעט גדולה יותר), בלי תגית ובלי לוגו כפול בפתיחה,
// טקסטי הכפתורים (כולם להרשמה ובשורה אחת, בתפריט "כאן מתחילים"), בלי כפתור מצב נגישות בדף (הוא באפליקציה) והצהרת הנגישות רק מהפוטר,
// מיקרו-קופי גדול יותר, שורות האמון בשורה אחת, ומעברי גרדיאנט בין הסקשנים בלי קווי גבול. 320, 360, 390, 768 ו-1280px.
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
const TYPES = { '.html': 'text/html; charset=utf-8', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg' };
const server = http.createServer((req, res) => {
  const f = join(root, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'landing.html' : decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(root) || !existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TYPES[extname(f)] || 'application/octet-stream' }); res.end(readFileSync(f));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${server.address().port}`;
const browser = await (await loadChromium()).launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const HERO_CTA = 'הלידים שלך מחכים במסך הבא';
const OTHER_CTA = 'מתחילים לעשות סדר בעסק';
const NAV_CTA = 'כאן מתחילים';
for (const [w, h] of [[320, 640], [360, 740], [390, 844], [768, 1024], [1280, 800]]) {
  const ctx = await browser.newContext({ locale: 'he-IL', viewport: { width: w, height: h } });
  await ctx.route(u => !u.href.startsWith(BASE), r => r.abort());
  const page = await ctx.newPage();
  await page.goto(`${BASE}/landing.html`, { waitUntil: 'load' });
  await page.waitForTimeout(400);
  const r = await page.evaluate(() => {
    const h1 = document.querySelector('.hero h1');
    const ctas = [...document.querySelectorAll('a.btn-primary, a.nav-cta')].map(a => {
      const cs = getComputedStyle(a), b = a.getBoundingClientRect();
      const lines = Math.round((b.height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom) - parseFloat(cs.borderTopWidth) - parseFloat(cs.borderBottomWidth)) / parseFloat(cs.lineHeight === 'normal' ? parseFloat(cs.fontSize) * 1.2 : cs.lineHeight));
      return { id: a.id, nav: !!a.closest('nav'), text: a.textContent.trim(), href: a.getAttribute('href'), lines, inside: b.left >= 0 && b.right <= innerWidth };
    });
    const oneLine = el => { const r = el.getClientRects(); return r.length === 1; };
    const bg = s => getComputedStyle(document.querySelector(s)).backgroundImage;
    const tw = e => { const r = document.createRange(); r.selectNodeContents(e); return r.getBoundingClientRect(); };
    const l1 = h1.querySelector('.hero-l1'), l2 = h1.querySelector('.hero-l2');
    const lineTops = new Set([...h1.querySelectorAll('span')].flatMap(s => [...s.getClientRects()].map(r => Math.round(r.top))));
    const px = sel => parseFloat(getComputedStyle(document.querySelector(sel)).fontSize);
    const a11yBtn = document.querySelector('[data-a11y-btn]');
    return {
      h1: h1.innerText.replace(/\s+/g, ' ').trim(), highlight: h1.querySelector('.highlight')?.textContent.trim() ?? null,
      h1Lines: lineTops.size, l1Inside: tw(l1).left >= 0 && tw(l1).right <= innerWidth, l2Inside: tw(l2).left >= 0 && tw(l2).right <= innerWidth,
      colors: [getComputedStyle(l1).color, getComputedStyle(l2).color], sizes: [parseFloat(getComputedStyle(l1).fontSize), parseFloat(getComputedStyle(l2).fontSize)],
      navA11y: !!document.querySelector('nav [data-a11y-btn], nav .nav-a11y-btn'),
      a11yBtns: document.querySelectorAll('[data-a11y-btn]').length,
      closingEndsWithTrust: document.querySelector('.closing-actions')?.lastElementChild?.classList.contains('closing-micro') === true,
      statementHidden: document.getElementById('a11y-statement')?.hidden === true && !!document.getElementById('a11y-statement')?.closest('footer'),
      microPx: { cap: px('.phone-cap'), trust: px('.hero-trust'), closing: px('.closing-micro'), footLink: px('.footer-links a'), footCopy: px('.footer-copy') },
      sub: document.querySelector('.hero-sub').textContent.trim(),
      heroImgs: document.querySelectorAll('.hero-text img').length, badge: !!document.querySelector('.hero-badge'),
      navLogo: !!document.querySelector('nav .nav-logo'), ctas,
      trust: [...document.querySelectorAll('.hero-trust span')].map(s => ({ t: s.textContent, one: oneLine(s) })),
      micro: { t: document.querySelector('.closing-micro').textContent, one: oneLine(document.querySelector('.closing-micro')) },
      closingP: document.querySelector('.closing > p').textContent.trim(),
      grads: ['.hero', '.feat-section', '.closing'].map(s => (bg(s).match(/linear-gradient/g) || []).length),
      featBorders: getComputedStyle(document.getElementById('features')).borderTopWidth + ' ' + getComputedStyle(document.getElementById('features')).borderBottomWidth,
      overflow: document.documentElement.scrollWidth - innerWidth,
    };
  });
  const L = `${w}px:`;
  check(r.h1 === 'הלידים כבר אצלך עכשיו הגיע הזמן להפוך אותם ללקוחות', `${L} הכותרת הראשית (${r.h1})`);
  check(r.h1Lines === 2 && r.l1Inside && r.l2Inside, `${L} הכותרת בשתי שורות בדיוק, ושתיהן בתוך המסך (${r.h1Lines})`);
  check(r.colors.every(c => c === 'rgb(255, 255, 255)') && r.highlight === null, `${L} הכותרת לבנה כולה, בלי הדגשה בצבע (${r.colors.join(' / ')})`);
  check(r.sizes[0] > r.sizes[1] && r.sizes[0] / r.sizes[1] <= 1.35, `${L} השורה העליונה מעט גדולה יותר (${r.sizes.map(n => n.toFixed(1)).join(' / ')})`);
  check(!r.navA11y && r.a11yBtns === 0, `${L} אין כפתור מצב נגישות בדף`);
  check(r.closingEndsWithTrust && r.statementHidden, `${L} הסקשן האחרון נגמר בשורת האמון, והצהרת הנגישות מוסתרת בפוטר`);
  check(r.microPx.cap >= 15 && r.microPx.trust >= 18 && r.microPx.closing >= 16 && r.microPx.footLink >= 15 && r.microPx.footCopy >= 14, `${L} מיקרו-קופי גדול יותר (${JSON.stringify(r.microPx)})`);
  check(/לידים, משימות ומעקב במקום אחד/.test(r.sub) && /אף ליד לא נופל בין הכיסאות/.test(r.sub), `${L} הטקסט המשלים מדבר על לידים, משימות ומעקב`);
  check(r.heroImgs === 0 && !r.badge && r.navLogo, `${L} בפתיחה אין תגית ואין לוגו כפול, הלוגו רק בסרגל העליון`);
  const hero = r.ctas.find(c => c.id === 'hero-cta-btn'), nav = r.ctas.find(c => c.nav), others = r.ctas.filter(c => c.id !== 'hero-cta-btn' && !c.nav);
  check(hero?.text === HERO_CTA, `${L} כפתור הפתיחה: "${hero?.text}"`);
  check(nav?.text === NAV_CTA, `${L} כפתור התפריט העליון: "${nav?.text}"`);
  check(others.length === 2 && others.every(c => c.text === OTHER_CTA), `${L} כפתורי ההמרה באמצע ובתחתית: "${OTHER_CTA}" (${others.map(c => c.text).join(' | ')})`);
  check(r.ctas.every(c => c.href === 'https://realestate.plto.app'), `${L} כל הכפתורים מובילים להרשמה`);
  check(r.ctas.every(c => c.lines === 1 && c.inside), `${L} כל כפתור בשורה אחת ובתוך המסך (${r.ctas.map(c => c.lines).join(',')})`);
  check(r.trust.length === 2 && r.trust[1].t === 'בלי כרטיס אשראי, בלי התחייבות' && r.trust.every(t => t.one), `${L} שורת האמון בגיבור: "בלי כרטיס אשראי, בלי התחייבות" בשורה אחת`);
  check(/45 יום חינם/.test(r.trust[0]?.t || ''), `${L} 45 יום חינם בגיבור`);
  check(r.micro.t === 'בלי כרטיס אשראי, בלי התחייבות' && r.micro.one, `${L} מתחת לכפתור הסגירה: אותה שורה, בשורה אחת`);
  check(/^45 ימים על חשבוננו\./.test(r.closingP) && !/כרטיס אשראי/.test(r.closingP), `${L} פסקת הסגירה: 45 ימים, בלי לחזור על שורת האמון`);
  check(r.grads[0] >= 1 && r.grads[1] >= 2 && r.grads[2] >= 2, `${L} מעברי גרדיאנט בין הסקשנים (${r.grads.join(',')})`);
  check(r.featBorders === '0px 0px', `${L} בלי קווי גבול סביב סקשן התכונות`);
  check(r.overflow <= 0, `${L} אין גלישה אופקית`);
  await ctx.close();
}
await browser.close(); server.close();
console.log(failures ? `\n${failures} נכשלו` : '\nכל הבדיקות עברו');
process.exit(failures ? 1 : 0);
