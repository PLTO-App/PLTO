// QA offline smoke test — admin.html
// Run with: NODE_PATH=/opt/node22/lib/node_modules node qa/qa_admin.js
const { chromium } = require('playwright');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail: detail || '' });
  console.log((ok ? '✅' : '❌'), name, detail ? '— ' + detail : '');
}

(async () => {
  const browser = await chromium.launch();
  const consoleErrors = [];
  const pageErrors = [];
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', err => pageErrors.push(err.message));
  await page.route('**/*', route => route.request().url().startsWith('file://') ? route.continue() : route.abort());

  await context.addInitScript(() => {
    window.supabase = {
      createClient() {
        return {
          auth: {
            getSession: async () => ({ data: { session: null }, error: null }),
            getUser: async () => ({ data: { user: null }, error: null }),
            onAuthStateChange(cb) { setTimeout(() => cb('INITIAL_SESSION', null), 5); return { data: { subscription: { unsubscribe() {} } } }; },
            signInWithPassword: async () => ({ data: {}, error: { message: 'not logged' } }),
          },
          from() { return { select() { return this; }, eq() { return this; }, order() { return this; }, then(r) { return r({ data: [], error: null }); } }; },
          rpc() { return Promise.resolve({ data: [], error: null }); },
        };
      }
    };
  });

  try {
    await page.goto('file://' + path.join(ROOT, 'admin.html'), { waitUntil: 'load', timeout: 20000 });
    await page.waitForTimeout(1200);

    const bodyText = await page.evaluate(() => document.body.innerText.length);
    record('admin.html נטען עם תוכן', bodyText > 0, `${bodyText} תווים`);

    const noHScroll = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 2);
    record('אין גלילה אופקית ב-390px', noHScroll);

    const loginGuardPresent = await page.evaluate(() => {
      return typeof ADMIN_EMAILS !== 'undefined' && Array.isArray(ADMIN_EMAILS) && ADMIN_EMAILS.length > 0;
    });
    record('ADMIN_EMAILS guard מוגדר', loginGuardPresent);

    const hasLidersRef = await page.evaluate(() => document.body.innerText.includes('Liders') || document.body.innerText.includes('לידרס'));
    record('אין אזכור "Liders" גלוי בדף', !hasLidersRef);

    record('אין page errors', pageErrors.length === 0, pageErrors.slice(0, 5).join(' | '));
    const realConsoleErrors = consoleErrors.filter(e => !/service.?worker|ServiceWorker|Failed to load resource|net::ERR/i.test(e));
    record('אין שגיאות קונסולה חריגות', realConsoleErrors.length === 0, realConsoleErrors.slice(0, 5).join(' | '));
  } catch (e) {
    record('טעינת admin.html', false, e.message);
  }

  await browser.close();
  const failed = results.filter(r => !r.ok);
  console.log(`\n=== סיכום admin.html: ${results.length - failed.length}/${results.length} עברו ===`);
  process.exit(failed.length ? 1 : 0);
})();
