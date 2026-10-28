const { chromium } = require('playwright');
(async () => {
  const [url, out, w = 390, h = 844, dpr = 2] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: +dpr });
  p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.log('console:', m.text().slice(0, 300)); });
  p.on('pageerror', e => console.log('pageerror:', e.message));
  await p.goto('http://127.0.0.1:8765' + url);
  await p.waitForFunction(() => window.__ready === true, null, { timeout: 240000 });
  await p.waitForTimeout(300);
  const o = await p.evaluate(() => window.__out); if (o) console.log(o);
  if (out !== '-') await p.screenshot({ path: out, type: out.endsWith('.jpg') ? 'jpeg' : 'png', quality: out.endsWith('.jpg') ? 88 : undefined });
  await b.close();
})();
