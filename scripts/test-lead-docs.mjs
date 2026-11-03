// מסמכי לקוח: בלי קישורים ציבוריים קבועים, פתיחה פנימית בקישור חתום קצר, שיתוף חיצוני (7 ימים, ביטול)
// או פנימי בלבד, ומחיקה שמוחקת קודם את הקובץ מהאחסון. רצה עם Supabase מדומה שמתעד כל קריאה,
// ולכן היא לא מוכיחה שהאחסון והפונקציה החיים עובדים (את זה בודקים מקומית מול Postgres ובחי אחרי פריסה).
import { startHarness } from './lib/harness.mjs';
import { readFileSync } from 'node:fs';

const { page, errors, close } = await startHarness({ viewport: { width: 390, height: 844 } });
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const TOKEN = 'ab'.repeat(32);

// Supabase מדומה בתוך הדף
await page.evaluate((TOKEN) => {
  const log = window.__log = [];
  const resp = (data, error = null) => Promise.resolve({ data, error });
  window.__fail = {};
  const docs = [{ id: 'doc-1', lead_id: 'lead-1', tenant_id: 't-a', file_name: 'חוזה <b>bold</b>.pdf', file_path: 't-a/lead-1/1_contract.pdf', created_at: new Date().toISOString() }];
  const shares = [
    { id: 'sh-1', created_at: new Date().toISOString(), expires_at: new Date(Date.now() + 5 * 864e5).toISOString(), revoked_at: null, access_count: 2 },
    { id: 'sh-2', created_at: new Date().toISOString(), expires_at: new Date(Date.now() + 5 * 864e5).toISOString(), revoked_at: new Date().toISOString(), access_count: 0 },
  ];
  const query = (table) => {
    const q = { table, op: 'select', filters: [] };
    const c = {
      select(cols) { if (q.op === 'select') q.cols = cols; return c; },
      insert(row) { q.op = 'insert'; q.row = row; return c; },
      update(row) { q.op = 'update'; q.row = row; return c; },
      delete() { q.op = 'delete'; return c; },
      eq(k, v) { q.filters.push([k, v]); return c; },
      order() { return c; }, limit() { return c; },
      single() { q.single = true; return c; },
      then(r, j) {
        log.push({ kind: 'db', ...q });
        let out;
        if (window.__fail[table + ':' + q.op]) out = resp(null, { message: 'forced failure' });
        else if (table === 'lead_documents' && q.op === 'select') out = resp(docs);
        else if (table === 'lead_document_shares' && q.op === 'select') out = resp(shares);
        else if (q.op === 'insert') out = resp({ id: 'new-id', ...q.row, created_at: new Date().toISOString() });
        else out = resp(null);
        return out.then(r, j);
      },
    };
    return c;
  };
  sbClient.from = (t) => query(t);
  sbClient.rpc = (fn, args) => {
    log.push({ kind: 'rpc', fn, args });
    if (fn === 'create_document_share') return resp({ id: 'sh-new', token: TOKEN, expires_at: new Date(Date.now() + 7 * 864e5).toISOString() });
    if (fn === 'revoke_document_share') return resp(true);
    return resp(null);
  };
  sbClient.storage = { from: (bucket) => ({
    upload: (path) => { log.push({ kind: 'storage', op: 'upload', bucket, path }); return resp({ path }); },
    remove: (paths) => { log.push({ kind: 'storage', op: 'remove', bucket, paths }); return window.__fail['storage:remove'] ? resp(null, { message: 'x' }) : resp(paths.map(name => ({ name }))); },
    createSignedUrl: (path, ttl) => { log.push({ kind: 'storage', op: 'sign', bucket, path, ttl }); return resp({ signedUrl: 'https://signed.example/' + path + '?token=short' }); },
    getPublicUrl: (path) => { log.push({ kind: 'storage', op: 'public', bucket, path }); return { data: { publicUrl: 'https://public/' + path } }; },
  }) };
  State.isDemo = false;
  DB.tenantId = 't-a';
  DB.agentId = 'agent-a';
  State.leads = [{ id: 'lead-1', name: 'דנה כהן', email: 'dana@example.com', phone: '0501234567' }];
  window.confirm = () => true;
  window.__opened = [];
  window.open = (u) => { const w = { location: { href: u }, closed: false, close() { this.closed = true; } }; window.__opened.push(w); return w; };
  window.__copied = [];
  Object.defineProperty(navigator, 'clipboard', { value: { writeText: (t) => { window.__copied.push(t); return Promise.resolve(); } }, configurable: true });
  if (!document.getElementById('docs-list')) { const d = document.createElement('div'); d.id = 'docs-list'; document.body.appendChild(d); }
}, TOKEN);

const step = (fn, arg) => page.evaluate(fn, arg);
const log = () => page.evaluate(() => window.__log.splice(0));

// 1. רשימה
await step(() => LeadDocs.load('lead-1'));
let r = await step(() => {
  const el = document.getElementById('docs-list');
  return { html: el.innerHTML, bold: !!el.querySelector('b'), links: [...el.querySelectorAll('a[href]')].map(a => a.getAttribute('href')), text: el.innerText };
});
let l = await log();
check(!r.bold && /חוזה &lt;b&gt;bold/.test(r.html), 'שם הקובץ מוצג כטקסט (escaped)');
check(r.links.length === 0 && !/public/.test(r.html), 'אין קישור קבוע לקובץ ברשימה');
check(/שיתוף/.test(r.text) && !/שליחה למייל הליד/.test(r.text), 'במקום "שליחה למייל" יש "שיתוף", שמאפשר לבחור את סוג השיתוף');
check(l.some(x => x.kind === 'db' && x.table === 'lead_documents' && /file_path/.test(x.cols) && !/file_url/.test(x.cols)), 'הטעינה מבקשת file_path ולא file_url');

// 2. העלאה
await step(async () => {
  const file = new File(['%PDF'], 'הסכם שכירות.pdf', { type: 'application/pdf' });
  await LeadDocs.upload('lead-1', { files: [file], value: 'x' });
});
l = await log();
const up = l.find(x => x.op === 'upload'), ins = l.find(x => x.kind === 'db' && x.op === 'insert' && x.table === 'lead_documents');
check(up && up.bucket === 'lead-documents' && /^t-a\/lead-1\/\d+_/.test(up.path), 'הקובץ עולה לתיקיית העסק והליד');
check(ins && ins.row.file_path === up.path && !('file_url' in ins.row), 'השורה במסד שומרת את נתיב הקובץ, בלי קישור ציבורי');
check(!l.some(x => x.op === 'public'), 'אין קריאה ל-getPublicUrl');

await step(async () => { window.__fail['lead_documents:insert'] = true; await LeadDocs.upload('lead-1', { files: [new File(['x'], 'a.pdf', { type: 'application/pdf' })], value: 'x' }); window.__fail = {}; });
l = await log();
const up2 = l.find(x => x.op === 'upload'), rm2 = l.find(x => x.op === 'remove');
check(rm2 && rm2.paths[0] === up2.path, 'אם השמירה במסד נכשלה, הקובץ שהועלה נמחק מיד');

// 3. פתיחה פנימית
await step(() => LeadDocs.load('lead-1'));
await log();
r = await step(async () => { await LeadDocs.open('doc-1', 'lead-1'); return window.__opened.map(w => w.location.href); });
l = await log();
const sign = l.find(x => x.op === 'sign');
check(sign && sign.path === 't-a/lead-1/1_contract.pdf' && sign.ttl === 60, 'פתיחה פנימית: קישור חתום ל-60 שניות');
check(r[r.length - 1] === 'https://signed.example/t-a/lead-1/1_contract.pdf?token=short', 'החלון שנפתח בלחיצה מקבל את הקישור החתום');

// 4. חלון השיתוף
r = await step(async () => {
  LeadDocs.openShare('doc-1', 'lead-1');
  await new Promise(res => setTimeout(res, 50));
  const m = document.getElementById('modal-doc-share');
  const body = document.getElementById('doc-share-body');
  return {
    visible: !m.classList.contains('hidden'),
    text: body.innerText,
    list: document.getElementById('doc-share-list').innerText,
    revokeBtns: document.querySelectorAll('#doc-share-list button').length,
    overflow: document.documentElement.scrollWidth - innerWidth,
    small: [...m.querySelectorAll('button')].filter(b => b.getClientRects().length && b.getBoundingClientRect().height < 44 && !b.classList.contains('modal-close')).map(b => b.textContent.trim()),
  };
});
check(r.visible, 'חלון השיתוף נפתח');
check(/קישור מאובטח ללקוח/.test(r.text) && /7 ימים/.test(r.text) && /לבטל/.test(r.text), 'אפשרות 1: קישור מאובטח ללקוח, 7 ימים, אפשר לבטל');
check(/פנימי בלבד/.test(r.text) && /מחוברים בעסק שלך/.test(r.text), 'אפשרות 2: פנימי בלבד, למשתמשים מחוברים בעסק');
check(/פעיל עד/.test(r.list) && /נפתח 2 פעמים/.test(r.list) && /בוטל/.test(r.list) && r.revokeBtns === 1, 'רשימת הקישורים: פעיל עם כפתור ביטול, ובוטל בלי כפתור');
check(r.overflow <= 0, 'אין גלישה לרוחב ב-390px');
check(r.small.length === 0, 'כפתורי החלון בגובה 44px לפחות' + (r.small.length ? ': ' + r.small.join(', ') : ''));

// 5. יצירת קישור חיצוני
await log();
r = await step(async () => { await LeadDocs.createExternal(); await new Promise(res => setTimeout(res, 50)); return { val: document.getElementById('doc-share-link')?.value, text: document.getElementById('doc-share-body').innerText }; });
l = await log();
const cr = l.find(x => x.kind === 'rpc' && x.fn === 'create_document_share');
check(cr && cr.args.p_document_id === 'doc-1', 'יצירת קישור קוראת ל-create_document_share עם המסמך');
check(r.val === `${new URL(page.url()).origin}/doc.html?t=${TOKEN}`, 'הקישור ללקוח מפנה לדף doc.html באתר עם הטוקן, בלי נתיב הקובץ');
check(/בתוקף עד/.test(r.text) && /מוצג רק עכשיו/.test(r.text), 'מוצג תוקף, ושהקישור מוצג פעם אחת');
await step(() => LeadDocs.copyShareLink());
r = await step(() => window.__copied.slice(-1)[0]);
check(r && r.endsWith(TOKEN), 'העתקת הקישור ללקוח');

// 6. ביטול
await log();
await step(async () => { await LeadDocs.revoke('sh-1'); });
l = await log();
check(l.some(x => x.kind === 'rpc' && x.fn === 'revoke_document_share' && x.args.p_share_id === 'sh-1'), 'ביטול קישור קורא ל-revoke_document_share');
check(!l.some(x => x.op === 'remove' || (x.kind === 'db' && x.op === 'delete')), 'ביטול קישור לא מוחק את המסמך או את הקובץ');

// 7. פנימי בלבד
await step(() => LeadDocs.copyInternal());
r = await step(() => window.__copied.slice(-1)[0]);
check(/\?s=lead-detail&lead=lead-1$/.test(r) && !/document-share|token|t-a\//.test(r), 'קישור פנימי: לכרטיס הליד בלבד, בלי טוקן ובלי נתיב קובץ');

// 8. מחיקה
await log();
await step(async () => { window.__fail['storage:remove'] = true; await LeadDocs.delete('doc-1', 'lead-1'); window.__fail = {}; });
l = await log();
check(l.some(x => x.op === 'remove') && !l.some(x => x.kind === 'db' && x.op === 'delete'), 'אם מחיקת הקובץ נכשלה, השורה לא נמחקת (אין מסמך שנראה מחוק וקובץ שנשאר)');
await step(async () => { await LeadDocs.delete('doc-1', 'lead-1'); });
l = await log();
const iRm = l.findIndex(x => x.op === 'remove'), iDel = l.findIndex(x => x.kind === 'db' && x.op === 'delete' && x.table === 'lead_documents');
check(iRm >= 0 && iDel > iRm && l[iRm].paths[0] === 't-a/lead-1/1_contract.pdf', 'מחיקת מסמך: קודם הקובץ מהאחסון, ואז השורה');

// 9. מקור
const src = readFileSync(new URL('../index.html', import.meta.url), 'utf-8');
const ld = src.slice(src.indexOf('const LeadDocs = {'), src.indexOf('\n};\n', src.indexOf('const LeadDocs = {')));
check(!/getPublicUrl|file_url|Make\.trigger/.test(ld), 'במודול המסמכים אין getPublicUrl, file_url או שליחה דרך Make');

check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
