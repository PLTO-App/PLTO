// Harness משותף לבדיקות הדפדפן: שרת סטטי מקומי, Supabase מדומה בלי תלות ברשת, כניסה למצב דמו.
// הנתונים מדומים, ולכן הבדיקות לא מוכיחות שהאינטגרציות החיות עובדות.
import http from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const defaultRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

async function loadChromium() {
  try { return (await import('playwright')).chromium; } catch (_) {
    return (await import('/opt/node22/lib/node_modules/playwright/index.mjs')).chromium;
  }
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.txt': 'text/plain' };

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
    rpc: function(name,args){ var c = chain(); var t = c.then; c.then = function(r,j){ (window.__sbCalls = window.__sbCalls || []).push({fn:name,args:args}); return t(r,j); }; return c; },
    storage:{ from: function(){ return { upload:function(){ return Promise.resolve({data:{},error:null}); }, getPublicUrl:function(){ return {data:{publicUrl:''}}; } }; } },
    functions:{ invoke: function(){ return Promise.resolve({data:{},error:null}); } },
    channel: function(){ var ch={on:function(){return ch;},subscribe:function(){return ch;}}; return ch; },
    removeChannel: noop,
  };
  window.supabase = { createClient: function(){ return mockClient; } };
})();
`;
const CHART_MOCK = `window.Chart=function(){this.destroy=function(){};this.data={datasets:[]};this.update=function(){};};window.Chart.register=function(){};`;


export async function startHarness({ touch = false, root = defaultRoot } = {}) {
  const chromium = await loadChromium();
  const server = http.createServer((req, res) => {
    const path = decodeURIComponent(req.url.split('?')[0]);
    const file = join(root, path === '/' ? 'index.html' : path);
    if (!file.startsWith(root) || !existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' });
    res.end(readFileSync(file));
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const BASE = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const ctx = await browser.newContext({ locale: 'he-IL', viewport: { width: 390, height: 844 }, hasTouch: touch, isMobile: touch });
  await ctx.route('**cdn.jsdelivr.net**supabase**', r => r.fulfill({ contentType: 'application/javascript; charset=utf-8', body: SUPABASE_MOCK }));
  await ctx.route('**cdn.jsdelivr.net**chart.js**', r => r.fulfill({ contentType: 'application/javascript; charset=utf-8', body: CHART_MOCK }));
  await ctx.route(url => !url.href.startsWith(BASE) && !/cdn\.jsdelivr\.net/.test(url.href), r => r.abort());
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
  await page.evaluate(() => {
    State.isDemo = false;
    // כפתור התמיכה מוצג רק אחרי כניסה אמיתית, ולכן מדמים אותה
    document.getElementById('support-fab-btn')?.classList.remove('hidden');
  });
  await page.waitForTimeout(800);
  return { page, ctx, errors, browser, close: async () => { await browser.close(); server.close(); } };
}
