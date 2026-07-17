// QA offline smoke test — landing.html
// Run with: NODE_PATH=/opt/node22/lib/node_modules node qa/qa_landing.js
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
  for (const width of [390, 1440]) {
    const consoleErrors = [];
    const pageErrors = [];
    const context = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await context.newPage();
    page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
    page.on('pageerror', err => pageErrors.push(err.message));
    await page.route('**/*', route => route.request().url().startsWith('file://') ? route.continue() : route.abort());

    try {
      await page.goto('file://' + path.join(ROOT, 'landing.html'), { waitUntil: 'load', timeout: 20000 });
      await page.waitForTimeout(1200);

      const h1 = await page.evaluate(() => document.querySelector('h1')?.innerText || '');
      record(`[${width}px] H1 נטען`, h1.length > 5, h1.slice(0, 50));

      const noHScroll = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 6);
      record(`[${width}px] אין גלילה אופקית`, noHScroll);

      const ctaBtn = await page.$('#hero-cta-btn');
      record(`[${width}px] כפתור CTA hero קיים`, !!ctaBtn);

      const hasLidersRef = await page.evaluate(() => document.body.innerText.includes('Liders') || document.body.innerText.includes('לידרס'));
      record(`[${width}px] אין אזכור "Liders" גלוי`, !hasLidersRef);

      const realConsoleErrors = consoleErrors.filter(e => !/service.?worker|ServiceWorker|Failed to load resource|net::ERR|googletagmanager|google-analytics/i.test(e));
      record(`[${width}px] אין page errors`, pageErrors.length === 0, pageErrors.slice(0, 5).join(' | '));
      record(`[${width}px] אין שגיאות קונסולה חריגות`, realConsoleErrors.length === 0, realConsoleErrors.slice(0, 5).join(' | '));
    } catch (e) {
      record(`[${width}px] טעינת landing.html`, false, e.message);
    }
    await context.close();
  }
  await browser.close();
  const failed = results.filter(r => !r.ok);
  console.log(`\n=== סיכום landing.html: ${results.length - failed.length}/${results.length} עברו ===`);
  process.exit(failed.length ? 1 : 0);
})();
