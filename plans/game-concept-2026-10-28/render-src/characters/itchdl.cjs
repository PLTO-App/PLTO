const { chromium } = require('playwright');
(async () => {
  const [page_url, upload_id, out] = process.argv.slice(2);
  const b = await chromium.launch(); const ctx = await b.newContext({ acceptDownloads: true }); const p = await ctx.newPage();
  await p.goto(page_url);
  await p.click('a.download_btn, .buy_btn, a:has-text("Download Now")');
  await p.locator('a:has-text("No thanks")').first().click({ timeout: 20000 });
  await p.waitForTimeout(4000); console.log('at', p.url()); await p.screenshot({ path: out + '.png' }); console.log((await p.content()).match(/upload_id[^>]{0,80}/g));
  await p.waitForSelector(`a[data-upload_id="${upload_id}"]`, { timeout: 30000 });
  const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 120000 }), p.click(`a[data-upload_id="${upload_id}"]`)]);
  console.log('url', dl.url().slice(0, 80)); await dl.saveAs(out); console.log('saved'); await b.close();
})().catch(e => { console.log('ERR', e.message); process.exit(1); });
