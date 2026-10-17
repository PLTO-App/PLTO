// בדיקת עשן מקומית ב-390px: טוענת את index.html עם Supabase מדומה, נכנסת למצב דמו
// ועוברת על מסכי האפליקציה. בודקת שגיאות JS, בקשות שנכשלו וגלישה אופקית.
// שימוש: node scripts/smoke-390.mjs [תיקיית צילומי מסך]
// זו לא הוכחה שהאינטגרציות החיות עובדות, הנתונים מדומים.
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const shotsDir = process.argv[2] || '';
if (shotsDir) mkdirSync(shotsDir, { recursive: true });

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  ({ chromium } = await import('/opt/node22/lib/node_modules/playwright/index.mjs'));
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.txt': 'text/plain' };
const server = http.createServer((req, res) => {
  const path = decodeURIComponent(req.url.split('?')[0]);
  const file = join(root, path === '/' ? 'index.html' : path);
  if (!file.startsWith(root) || !existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' });
  res.end(readFileSync(file));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${server.address().port}`;

const SUPABASE_MOCK = `
(function(){
  var noop = function(){};
  var chain = function(){
    var c = {
      select:function(){return c;}, eq:function(){return c;}, neq:function(){return c;},
      order:function(){return c;}, limit:function(){return c;}, in:function(){return c;},
      is:function(){return c;}, gte:function(){return c;}, lte:function(){return c;},
      filter:function(){return c;}, single:function(){return c;}, maybeSingle:function(){return c;},
      insert:function(){return c;}, update:function(){return c;},
      delete:function(){return c;}, upsert:function(){return c;},
      url:{href:''},
      then:function(r,j){ return Promise.resolve({data:[],error:null}).then(r,j); },
      catch:function(j){ return Promise.resolve({data:[],error:null}).catch(j); },
    };
    return c;
  };
  var mockClient = {
    auth:{
      getSession: function(){ return Promise.resolve({data:{session:null},error:null}); },
      getUser: function(){ return Promise.resolve({data:{user:null},error:null}); },
      onAuthStateChange: function(cb){ setTimeout(function(){ cb('INITIAL_SESSION',null); },50); return {data:{subscription:{unsubscribe:noop}}}; },
      signInWithOAuth: function(){ return Promise.resolve({data:{},error:null}); },
      signInWithPassword: function(){ return Promise.resolve({data:{session:null,user:null},error:null}); },
      signOut: function(){ return Promise.resolve({error:null}); },
    },
    from: function(){ return chain(); },
    rpc: function(){ return chain(); },
    storage:{ from: function(){ return { upload:function(){ return Promise.resolve({data:{},error:null}); }, getPublicUrl:function(){ return {data:{publicUrl:''}}; } }; } },
    functions:{ invoke: function(){ return Promise.resolve({data:{},error:null}); } },
    channel: function(){ var ch={on:function(){return ch;},subscribe:function(){return ch;}}; return ch; },
    removeChannel: noop,
  };
  window.supabase = { createClient: function(){ return mockClient; } };
})();
`;
const CHART_MOCK = `window.Chart=function(){this.destroy=function(){};this.data={datasets:[]};this.update=function(){};};window.Chart.register=function(){};`;

const SCREENS = ['dashboard', 'pipeline', 'leads', 'lead-detail', 'properties', 'tasks', 'calendar', 'analytics', 'partners', 'tools', 'settings'];

const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({ locale: 'he-IL', viewport: { width: 390, height: 844 } });
await ctx.route('**cdn.jsdelivr.net**supabase**', r => r.fulfill({ contentType: 'application/javascript; charset=utf-8', body: SUPABASE_MOCK }));
await ctx.route('**cdn.jsdelivr.net**chart.js**', r => r.fulfill({ contentType: 'application/javascript; charset=utf-8', body: CHART_MOCK }));
// שאר הבקשות החיצוניות (גופנים, אנליטיקס, תמונות) נחסמות כדי שהבדיקה לא תלויה ברשת
await ctx.route(url => !url.href.startsWith(BASE) && !/cdn\.jsdelivr\.net/.test(url.href), r => r.abort());
// SRI נמחק מהעותק שמוגש לדפדפן כדי שהמוק לא ייחסם
await ctx.route(`${BASE}/`, async r => {
  const res = await r.fetch();
  const body = (await res.text()).replace(/\s+integrity="[^"]*"/g, '').replace(/\s+crossorigin="[^"]*"/g, '');
  await r.fulfill({ response: res, body });
});

const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(`console: ${m.text().slice(0, 160)}`); });

await page.goto(BASE, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => typeof App !== 'undefined' && typeof App.loginDemo === 'function', null, { timeout: 15000 });
await page.evaluate(() => { App.loginDemo(); State.isDemo = false; });
await page.waitForSelector('#app-shell:not(.hidden)', { timeout: 10000 });
// ניווט בין מסכים בלי הנעילה של מצב הדמו. הנתונים מקומיים, וכתיבות הולכות למוק.
await page.evaluate(() => { State.isDemo = false; });
await page.waitForTimeout(800);

const results = [];
for (const screen of SCREENS) {
  const before = errors.length;
  await page.evaluate(s => {
    if (s === 'lead-detail') App.go('lead-detail', { currentLeadId: State.leads[0]?.id });
    else App.go(s);
  }, screen);
  await page.waitForTimeout(500);
  const m = await page.evaluate(() => ({
    scrollW: document.documentElement.scrollWidth,
    innerW: window.innerWidth,
    // אלמנט מחוץ למסך נחשב ליקוי רק אם אין לו אב עם גלילה אופקית מכוונת (רצועות KPI, טאבים וכד')
    wide: [...document.querySelectorAll('.screen:not(.hidden) *')]
      .filter(e => {
        const r = e.getBoundingClientRect();
        if (r.width === 0 || (r.right <= window.innerWidth + 1 && r.left >= -1)) return false;
        for (let p = e.parentElement; p && !p.classList.contains('screen'); p = p.parentElement) {
          if (/(auto|scroll|hidden)/.test(getComputedStyle(p).overflowX)) return false;
        }
        return true;
      })
      .slice(0, 3).map(e => (e.id ? '#' + e.id : e.className && typeof e.className === 'string' ? '.' + e.className.split(' ')[0] : e.tagName)),
  }));
  const overflow = m.scrollW > m.innerW;
  results.push({ screen, overflow, wide: m.wide, newErrors: errors.length - before });
  if (shotsDir) await page.screenshot({ path: join(shotsDir, `${screen}.png`) });
}

await browser.close();
server.close();

let bad = 0;
for (const r of results) {
  const flags = [];
  if (r.overflow) flags.push('גלישה אופקית בדף');
  if (r.wide.length) flags.push(`אלמנטים מחוץ למסך: ${r.wide.join(', ')}`);
  if (r.newErrors) flags.push(`${r.newErrors} שגיאות JS`);
  if (flags.length) bad++;
  console.log(`${flags.length ? '✗' : '✓'} ${r.screen}${flags.length ? ': ' + flags.join(' | ') : ''}`);
}
if (errors.length) console.log('\nשגיאות:\n' + [...new Set(errors)].map(e => '  ' + e).join('\n'));
console.log(`\n${results.length - bad}/${results.length} מסכים נקיים`);
process.exit(bad || errors.length ? 1 : 0);
