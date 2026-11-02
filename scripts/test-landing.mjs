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
