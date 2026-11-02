// בדיקת דף הנחיתה הממוקד (שלושה סקשנים): תוכן ואמיתות הטענות, תמונות, כפתורי הרשמה,
// תקינות ב-390px, 768px ו-1280px (גלישה, גודל טקסט, כפתור הרשמה בלי גלילה) וקונסולה נקייה.
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
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.txt': 'text/plain' };
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
  await page.goto(`${BASE}/landing.html`, { waitUntil: 'load' });
  await page.waitForTimeout(600);
  return { page, ctx, errors };
}

// ── תוכן ──
const html = readFileSync(join(root, 'landing.html'), 'utf-8');
const app = readFileSync(join(root, 'index.html'), 'utf-8');
const head = html.slice(0, html.indexOf('</head>'));
const body = html.slice(html.indexOf('<body')).replace(/<script[\s\S]*?<\/script>/g, '').replace(/<!--[\s\S]*?-->/g, '');
const text = body.replace(/<[^>]*>/g, ' ').replace(/&quot;/g, '"');

check(/<title>PLTO Sales: /.test(head), 'כותרת הדף עם המיתוג PLTO Sales');
check(!/\bAI\b|בינה מלאכותית|חכם/.test(text + head.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<script[\s\S]*?<\/script>/g, '')), 'אין הבטחות AI או "חכם" בדף ובתיאורי ה-SEO');
check(!/עדיפות|20% הנחה|עמלה|₪|שקל/.test(text), 'אין טענות שאין להן מימוש (תמיכה בעדיפות, הנחת הפניה, עמלה) ואין מחירים בדף');
check(!/מאסטר|סוכנים חכמים|סוכן תמיכה|סוכן מוטיבציה|תוסף השיווק/.test(text), 'אין עוד טענות על סוכנים, תוסף שיווק או יכולות שהוסרו');
const sections = body.match(/<section\b/g) || [];
check(sections.length === 3, `בדיוק שלושה סקשנים (${sections.length})`);
check(/id="features"/.test(body) && /id="who"/.test(body) && /class="hero"/.test(body), 'שלושת הסקשנים: גיבור, מה עושים כל יום, למי זה מתאים');
// כל יכולת שמוצגת בדף קיימת באפליקציה
check(/const Today = \{/.test(app) && /\['overdue',\s+'באיחור'\]/.test(app) && /\['today',\s+'להיום'\]/.test(app) && /חדשים בלי מענה/.test(app), 'מסך "היום" באפליקציה כולל באיחור, להיום וחדשים בלי מענה');
check(/const SmartWA = \{/.test(app) && /פנייה ראשונה/.test(app) && /אחרי הצעת מחיר/.test(app) && /openFree\('script'\)/.test(app) && /openFree\('email'\)/.test(app), 'הודעות WhatsApp, אימיילים ותסריטי שיחה קיימים באפליקציה, כולל המטרות שהדף מציין');
check(/LeadImport\.open\(\)/.test(app) && /ייבוא לידים מקובץ/.test(app), 'ייבוא לידים מקובץ קיים באפליקציה');
check(/לא נסגר/.test(app) && /NextStep/.test(app), '"לא נסגר" והצעד הבא קיימים באפליקציה');
// תמונות: קיימות, עם alt ומידות
const imgs = [...body.matchAll(/<img\b[^>]*>/g)].map(m => m[0]);
check(imgs.length >= 2, `יש צילומי מסך בדף (${imgs.length})`);
check(imgs.every(i => /alt="[^"]{12,}"/.test(i) && /width="\d+"/.test(i) && /height="\d+"/.test(i)), 'לכל תמונה יש alt תיאורי, רוחב וגובה (מונע קפיצות פריסה)');
check(imgs.every(i => { const s = /src="([^"]+)"/.exec(i)?.[1]; return s && existsSync(join(root, s)); }), 'כל קבצי התמונות קיימים בריפו');
check(/נתוני דוגמה/.test(text), 'צילומי המסך מסומנים כנתוני דוגמה');
check(!/[א-ת]\/[א-ת]|\([א-ת]+\/[א-ת]+\)/.test(text), 'אין ניסוח עם לוכסן מגדרי');
// ניסוח ניטרלי מגדרית: בלי פנייה בגוף שני ביחיד או ברבים מוטה ובלי שמות תפקיד בלשון זכר רבים
const gendered = text.match(/בעצמכ[םן]|\bשלו\b|\bשלה\b|\bאתה\b|\bהזן\b|\bבחר\b|\bשלח\b|סוכני נדל|עורכי דין|בעלי עסקים|יועצים|ללקוח שסוגר/g);
check(!gendered, 'הטקסט ניטרלי מגדרית' + (gendered ? ': ' + [...new Set(gendered)].join(', ') : ''));
const meta = head.match(/(?:content|alt)="[^"]*"/g)?.join(' ') || '';
check(!/בעצמכ[םן]|\bשלו\b|סוכני נדל|עורכי דין/.test(meta), 'תיאורי ה-SEO וה-alt ניטרליים מגדרית');
check(!/[→←]/.test(text), 'אין חצים דקורטיביים בטקסט');
check(/privacy-policy\.html/.test(body) && /info@plto\.app/.test(body), 'קישור למדיניות פרטיות והצהרת נגישות בדף');
const aiTier = readFileSync(join(root, '.github/workflows/deploy.yml'), 'utf-8');
check(/cp -r icons /.test(aiTier), 'תיקיית icons (ובה תמונות הדף) מועתקת בפריסה');

for (const [w, h, label] of [[390, 844, 'נייד 390px'], [768, 1024, 'טאבלט 768px'], [1280, 800, 'דסקטופ 1280px']]) {
  const { page, ctx, errors } = await open(w, h);
  const r = await page.evaluate(() => {
    const doc = document.documentElement;
    const ctas = [...document.querySelectorAll('a.btn-primary, a.nav-cta')].map(a => a.getAttribute('href'));
    const hero = document.getElementById('hero-cta-btn').getBoundingClientRect();
    const tiny = [...document.querySelectorAll('main p, main h1, main h2, main h3, main li, .phone-cap')].filter(e => parseFloat(getComputedStyle(e).fontSize) < 13).length;
    const smallTargets = [...document.querySelectorAll('a.btn-primary, a.nav-cta, .nav-a11y-btn')].filter(e => { const b = e.getBoundingClientRect(); return b.height < 44; }).length;
    const imgsOk = [...document.querySelectorAll('img')].every(i => i.complete && i.naturalWidth > 0);
    const phones = [...document.querySelectorAll('.phone')].map(p => { const b = p.getBoundingClientRect(); return b.left >= 0 && b.right <= innerWidth; });
    return { overflowX: doc.scrollWidth - innerWidth, ctas, heroBottom: hero.bottom, vh: innerHeight, tiny, smallTargets, imgsOk, phonesInside: phones.every(Boolean), dir: getComputedStyle(document.body).direction };
  });
  check(r.overflowX <= 0, `${label}: אין גלישה אופקית`);
  check(r.dir === 'rtl', `${label}: כיוון RTL`);
  check(r.heroBottom <= r.vh, `${label}: כפתור ההרשמה הראשי נראה בלי גלילה`);
  check(r.ctas.length >= 4 && r.ctas.every(h => h === 'https://realestate.plto.app'), `${label}: כל כפתורי ההרשמה מצביעים למערכת (${r.ctas.length})`);
  check(r.smallTargets === 0, `${label}: כל כפתורי ההנעה בגובה 44px לפחות`);
  check(r.tiny === 0, `${label}: אין טקסט קטן מ-13px`);
  check(r.imgsOk && r.phonesInside, `${label}: צילומי המסך נטענו ונכנסים במסך`);
  await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 400) { scrollTo(0, y); await new Promise(r => setTimeout(r, 150)); } });
  await page.waitForTimeout(600);
  const faded = await page.evaluate(() => [...document.querySelectorAll('.fade-up')].filter(e => !e.classList.contains('visible')).length);
  check(faded === 0, `${label}: אנימציית הכניסה בגלילה מציגה את כל הרכיבים (${faded} נשארו מוסתרים)`);
  check(errors.length === 0, `${label}: אין שגיאות בקונסולה${errors.length ? ' ' + errors.join(' | ') : ''}`);
  await ctx.close();
}

// ניגודיות טקסט (4.5:1, או 3:1 לטקסט גדול) במצב רגיל ובמצב נגישות, ובמובייל ובדסקטופ
const CONTRAST = () => {
  const parse = s => { const m = s.match(/rgba?\(([^)]+)\)/); if (!m) return null; const a = m[1].split(',').map(Number); return { r: a[0], g: a[1], b: a[2], a: a.length > 3 ? a[3] : 1 }; };
  const lum = ({ r, g, b }) => { const f = v => { v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }; return .2126 * f(r) + .7152 * f(g) + .0722 * f(b); };
  const over = (t, b) => ({ r: t.r * t.a + b.r * (1 - t.a), g: t.g * t.a + b.g * (1 - t.a), b: t.b * t.a + b.b * (1 - t.a), a: 1 });
  const grad = bi => { const m = [...bi.matchAll(/rgba?\([^)]+\)/g)].map(x => parse(x[0])); if (!m.length) return null; const n = m.length; return { r: m.reduce((a, c) => a + c.r, 0) / n, g: m.reduce((a, c) => a + c.g, 0) / n, b: m.reduce((a, c) => a + c.b, 0) / n, a: 1 }; };
  const bgOf = el => {
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e); const c = parse(cs.backgroundColor);
      if (c && c.a > 0) layers.push(c);
      if (c && c.a === 1) break;
      if (cs.backgroundImage.includes('gradient')) { const g = grad(cs.backgroundImage); if (g) { layers.push(g); break; } }
    }
    let acc = layers.length ? layers[layers.length - 1] : { r: 255, g: 255, b: 255, a: 1 };
    if (acc.a < 1) acc = over(acc, { r: 255, g: 255, b: 255, a: 1 });
    for (let i = layers.length - 2; i >= 0; i--) acc = over(layers[i], acc);
    return acc;
  };
  const bad = [];
  document.querySelectorAll('main *, footer *, nav *').forEach(el => {
    if (![...el.childNodes].some(n => n.nodeType === 3 && /[A-Za-zא-ת0-9@]/.test(n.textContent))) return;
    const cs = getComputedStyle(el); if (cs.visibility === 'hidden' || cs.display === 'none' || +cs.opacity === 0) return;
    const bg = bgOf(el); const fg = over(parse(cs.color), bg);
    const l1 = lum(fg), l2 = lum(bg); const ratio = (Math.max(l1, l2) + .05) / (Math.min(l1, l2) + .05);
    const size = parseFloat(cs.fontSize), bold = +cs.fontWeight >= 700; const need = (size >= 24 || (size >= 18.66 && bold)) ? 3 : 4.5;
    if (ratio < need) bad.push(`${el.textContent.trim().slice(0, 24)} (${ratio.toFixed(2)})`);
  });
  return bad;
};
for (const [w, h, label] of [[390, 844, 'נייד 390px'], [1280, 800, 'דסקטופ 1280px']]) {
  const { page, ctx } = await open(w, h);
  await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 400) { scrollTo(0, y); await new Promise(r => setTimeout(r, 60)); } scrollTo(0, 0); });
  await page.waitForTimeout(500);
  let bad = await page.evaluate(CONTRAST);
  check(!bad.length, `${label}: ניגודיות הטקסט תקינה במצב רגיל${bad.length ? ': ' + bad.join(' | ') : ''}`);
  await page.evaluate(() => toggleA11y());
  await page.waitForTimeout(300);
  bad = await page.evaluate(CONTRAST);
  check(!bad.length, `${label}: ניגודיות הטקסט תקינה במצב נגישות${bad.length ? ': ' + bad.join(' | ') : ''}`);
  const ov = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  check(ov <= 0, `${label}: אין גלישה אופקית במצב נגישות`);
  const foot = await page.evaluate(() => [...document.querySelectorAll('.footer-links a')].filter(a => a.getBoundingClientRect().height < 44).length);
  check(foot === 0, `${label}: קישורי הפוטר בגובה 44px לפחות`);
  await ctx.close();
}
// reduced motion: אף אנימציה אינסופית לא רצה
{
  const ctx = await browser.newContext({ locale: 'he-IL', viewport: { width: 390, height: 844 }, reducedMotion: 'reduce' });
  await ctx.route(url => !url.href.startsWith(BASE), r => r.abort());
  const page = await ctx.newPage();
  await page.goto(`${BASE}/landing.html`, { waitUntil: 'load' });
  await page.waitForTimeout(800);
  const running = await page.evaluate(() => document.getAnimations().filter(a => a.playState === 'running' && a.effect.getComputedTiming().iterations === Infinity).map(a => a.animationName || a.constructor.name));
  check(running.length === 0, `במצב reduced motion אין אנימציה אינסופית שרצה${running.length ? ': ' + running.join(', ') : ''}`);
  await ctx.close();
}

// הקלקה על כפתור ההרשמה נשלחת למעקב ההמרות עם שם הסקשן, בלי p_tenant_id
{
  const { page, ctx } = await open(390, 844);
  const sent = [];
  await ctx.route('**/rest/v1/rpc/track_funnel_event', r => { sent.push(JSON.parse(r.request().postData() || '{}')); r.fulfill({ status: 204, body: '' }); });
  await ctx.route('https://realestate.plto.app/**', r => r.fulfill({ status: 200, contentType: 'text/html', body: '<html></html>' }));
  await page.click('#hero-cta-btn');
  await page.waitForTimeout(500);
  check(sent.length === 1 && sent[0].p_event_name === 'landing_cta_click' && sent[0].p_event_data?.section === 'hero' && !('p_tenant_id' in sent[0]), `קליק על כפתור הגיבור נרשם כ-landing_cta_click עם section=hero (נשלחו: ${sent.length})`);
  await ctx.close();
}

await browser.close();
server.close();
console.log(failures ? failures + ' נכשלו' : 'כל הבדיקות עברו');
process.exit(failures ? 1 : 0);
