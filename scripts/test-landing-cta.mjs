// סבב דף הנחיתה של 4.11.2026: הכותרת, בלי תגית ובלי לוגו כפול בפתיחה, טקסטי הכפתורים (כולם להרשמה ובשורה אחת),
// שורות האמון בשורה אחת, ומעברי גרדיאנט בין הסקשנים בלי קווי גבול. 390, 360 ו-1280px.
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
for (const [w, h] of [[390, 844], [360, 740], [1280, 800]]) {
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
      return { id: a.id, text: a.textContent.trim(), href: a.getAttribute('href'), lines, inside: b.left >= 0 && b.right <= innerWidth };
    });
    const oneLine = el => { const r = el.getClientRects(); return r.length === 1; };
    const bg = s => getComputedStyle(document.querySelector(s)).backgroundImage;
    return {
      h1: h1.innerText.replace(/\s+/g, ' ').trim(), highlight: h1.querySelector('.highlight')?.textContent.trim(),
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
  check(r.h1 === 'הלידים כבר אצלך עכשיו צריך להפוך אותם ללקוחות' && r.highlight === 'עכשיו צריך להפוך אותם ללקוחות', `${L} הכותרת הראשית (${r.h1})`);
  check(/לידים, משימות ומעקב במקום אחד/.test(r.sub) && /אף ליד לא נופל בין הכיסאות/.test(r.sub), `${L} הטקסט המשלים מדבר על לידים, משימות ומעקב`);
  check(r.heroImgs === 0 && !r.badge && r.navLogo, `${L} בפתיחה אין תגית ואין לוגו כפול, הלוגו רק בסרגל העליון`);
  const hero = r.ctas.find(c => c.id === 'hero-cta-btn'), others = r.ctas.filter(c => c.id !== 'hero-cta-btn');
  check(hero?.text === HERO_CTA, `${L} כפתור הפתיחה: "${hero?.text}"`);
  check(others.length === 3 && others.every(c => c.text === OTHER_CTA), `${L} שאר הכפתורים: "${OTHER_CTA}" (${others.map(c => c.text).join(' | ')})`);
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
