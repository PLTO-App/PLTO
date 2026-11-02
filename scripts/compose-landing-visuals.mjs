// בונה את התמונות המעוצבות לדף הנחיתה מצילומי המסך האמיתיים (פלט של capture-landing-shots.mjs).
// כל תמונה היא מסגרת ניטרלית (פחם וכסף) סביב צילום מסך אמיתי, בלי ממשק מומצא. הפלט PNG שקוף ב-@2x,
// והמרה ל-AVIF ו-WebP נעשית בנפרד (scripts/export-landing-images.py).
// שימוש: RAW=<תיקיית צילומים> OUT=<תיקיית פלט> node scripts/compose-landing-visuals.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const RAW = resolve(process.env.RAW || '');
const OUT = resolve(process.env.OUT || '');
if (!process.env.RAW || !process.env.OUT) { console.error('חסר RAW או OUT'); process.exit(1); }
mkdirSync(OUT, { recursive: true });
async function loadChromium() {
  try { return (await import('playwright')).chromium; } catch (_) {
    return (await import('/opt/node22/lib/node_modules/playwright/index.mjs')).chromium;
  }
}

// פלטה בלבד: נייבי, פחם, שנהב, כסף, שמפניה
const CSS = `
:root{--navy:#101A2B;--charcoal:#17191D;--ivory:#F5F5F3;--silver:#A6A9AE;--champagne:#B69A62}
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:transparent}
.stage{position:relative}
.win{position:absolute;background:var(--charcoal);border-radius:14px;border:1px solid rgba(166,169,174,.38);overflow:hidden}
.win .bar{height:24px;display:flex;align-items:center;gap:6px;padding:0 12px;background:var(--charcoal);border-bottom:1px solid rgba(166,169,174,.18)}
.win .bar i{width:7px;height:7px;border-radius:50%;background:rgba(166,169,174,.45)}
.win .scr{display:block;width:100%;overflow:hidden;background:var(--ivory)}
.win .scr img{display:block;width:100%;height:100%;object-fit:cover;object-position:top}
.phone{position:absolute;background:var(--charcoal);border-radius:46px;border:1px solid rgba(166,169,174,.45);padding:10px;transform-origin:top left}
.phone .scr{width:390px;height:844px;border-radius:36px;overflow:hidden;background:var(--ivory)}
.phone .scr img{display:block;width:100%;height:100%;object-fit:cover;object-position:top}
.dark .win,.dark .phone{box-shadow:0 34px 64px rgba(0,0,0,.45),0 6px 14px rgba(0,0,0,.30)}
.light .win,.light .phone{box-shadow:0 30px 56px rgba(16,26,43,.26),0 5px 12px rgba(16,26,43,.14)}
`;

const img = name => pathToFileURL(join(RAW, name + '.png')).href;
const win = (name, left, top, w) => {
  const h = Math.round(w * 10 / 16);
  return `<div class="win" style="left:${left}px;top:${top}px;width:${w}px"><div class="bar"><i></i><i></i><i></i></div><div class="scr" style="height:${h}px"><img src="${img(name)}" alt=""></div></div>`;
};
// טלפון: מסך 390×844 בקנה מידה s
const phone = (name, left, top, s) => `<div class="phone" style="left:${left}px;top:${top}px;transform:scale(${s})"><div class="scr"><img src="${img(name)}" alt=""></div></div>`;
const phoneBox = s => ({ w: Math.round((390 + 22) * s), h: Math.round((844 + 22) * s) });

const jobs = [];
// גיבור, למחשב: חלון פייפליין עם טלפון "היום" חופף
jobs.push({ file: 'hero-d', w: 800, h: 540, theme: 'dark', html: win('d1-pipeline', 140, 28, 640) + phone('m1-today', 8, 150, 0.44) });
// גיבור, למובייל: טלפון "היום" בלבד
{ const s = 0.78, b = phoneBox(s); jobs.push({ file: 'hero-m', w: b.w + 40, h: b.h + 44, theme: 'dark', html: phone('m1-today', 20, 14, s) }); }
// ארבעת השלבים: חלון (מחשב) וטלפון (מובייל), בגוון אחיד
const steps = [
  ['s1-import',    'd5-import-map', 'm6-import-map'],
  ['s2-pipeline',  'd1-pipeline',   'm2-pipeline'],
  ['s3-today',     'd2-today',      'm4-messages'],
  ['s4-analytics', 'd3-analytics',  'm5-analytics'],
];
for (const [name, d, m] of steps) {
  jobs.push({ file: name + '-d', w: 780, h: 520, theme: 'light', html: win(d, 24, 18, 732) });
  const s = 0.78, b = phoneBox(s);
  jobs.push({ file: name + '-m', w: b.w + 40, h: b.h + 44, theme: 'light', html: phone(m, 20, 14, s) });
}
// חלופות לבחירה בגיליון: כרטיס ליד (מובייל ודסקטופ) ו"היום" בטלפון
{ const s = 0.78, b = phoneBox(s);
  jobs.push({ file: 'alt-lead-m', w: b.w + 40, h: b.h + 44, theme: 'light', html: phone('m3-lead-activity', 20, 14, s) });
  jobs.push({ file: 'alt-today-m', w: b.w + 40, h: b.h + 44, theme: 'light', html: phone('m1-today', 20, 14, s) });
  jobs.push({ file: 'alt-lead-d', w: 780, h: 520, theme: 'light', html: win('d4-lead', 24, 18, 732) }); }

const browser = await (await loadChromium()).launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ deviceScaleFactor: 2 });
for (const j of jobs) {
  const page = await ctx.newPage();
  await page.setViewportSize({ width: j.w, height: j.h });
  const htmlPath = join(OUT, '_' + j.file + '.html');
  writeFileSync(htmlPath, `<!doctype html><meta charset="utf-8"><style>${CSS}</style><body class="${j.theme}"><div class="stage" style="width:${j.w}px;height:${j.h}px">${j.html}</div>`);
  await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'load' });
  await page.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth > 0));
  await page.screenshot({ path: join(OUT, j.file + '.png'), omitBackground: true, clip: { x: 0, y: 0, width: j.w, height: j.h } });
  console.log('✓', j.file, j.w * 2 + '×' + j.h * 2);
  await page.close();
}

// תמונת שיתוף (OG) 1200×630: בנויה מצילום מסך אמיתי + לוגו + הכותרת
{
  const page = await ctx.newPage();
  await page.setViewportSize({ width: 1200, height: 630 });
  const b = phoneBox(0.8);
  const html = `<!doctype html><meta charset="utf-8"><link href="https://fonts.googleapis.com/css2?family=Rubik:wght@500;700&display=swap" rel="stylesheet"><style>${CSS}
  body{width:1200px;height:630px;background:linear-gradient(160deg,#101A2B 0%,#101A2B 55%,#17191D 100%);font-family:Rubik,Heebo,sans-serif;direction:rtl;color:#F5F5F3;position:relative;overflow:hidden}
  .logo{position:absolute;top:56px;right:72px;font-size:34px;font-weight:700;letter-spacing:.5px}
  .tag{position:absolute;top:128px;right:72px;display:flex;align-items:center;gap:12px;font-size:20px;color:#B69A62;font-weight:500}
  .tag:before{content:"";width:40px;height:1px;background:#B69A62}
  h1{position:absolute;top:188px;right:72px;width:640px;font-size:60px;line-height:1.14;font-weight:700}
  h1 em{font-style:normal;color:#B69A62}
  p{position:absolute;bottom:64px;right:72px;font-size:26px;color:#A6A9AE}
  .phone{box-shadow:0 30px 60px rgba(0,0,0,.45)}</style><body class="dark">
  <div class="logo">PLTO</div><div class="tag">PLTO Sales</div>
  <h1>הלידים כבר אצלך.<br>עכשיו הופכים אותם ללקוחות <em>משלמים</em>.</h1>
  <p>מערכת המכירות לעסקים</p>
  ${phone('m1-today', 70, 60, 0.8)}</body>`;
  const p = join(OUT, '_og.html'); writeFileSync(p, html);
  await page.goto(pathToFileURL(p).href, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth > 0));
  await page.screenshot({ path: join(OUT, 'og.png'), clip: { x: 0, y: 0, width: 1200, height: 630 } });
  console.log('✓ og 1200×630 (@2x)');
  await page.close();
}
await browser.close();
