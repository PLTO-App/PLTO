// QA offline smoke test — index.html
// Stubs window.supabase with an in-memory fake backend so the app can run
// fully client-side without network access. Run with:
//   NODE_PATH=/opt/node22/lib/node_modules node qa/qa_index.js
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

  await page.route('**/*', route => {
    const url = route.request().url();
    if (url.startsWith('file://')) return route.continue();
    return route.abort();
  });

  const filePath = 'file://' + path.join(ROOT, 'index.html');

  // Inject a fake supabase client BEFORE any app script runs.
  await context.addInitScript(() => {
    const FAKE_TENANT_ID = 'tnt-1';
    const FAKE_USER_ID = 'usr-1';
    let leads = [];
    let properties = [];
    let leadSeq = 1;

    const fakeSession = {
      access_token: 'faketoken',
      user: { id: FAKE_USER_ID, email: 'qa@example.com', user_metadata: {} }
    };

    function tableHandler(table) {
      return {
        select() { return this; },
        insert(rows) { this._insert = Array.isArray(rows) ? rows : [rows]; return this; },
        update(vals) { this._update = vals; return this; },
        eq() { return this; },
        order() { return this; },
        limit() { return this; },
        single() {
          if (table === 'leads' && this._insert) {
            const row = { id: 'lead-' + (leadSeq++), tenant_id: FAKE_TENANT_ID, ...this._insert[0] };
            leads.push(row);
            return Promise.resolve({ data: row, error: null });
          }
          return Promise.resolve({ data: null, error: null });
        },
        then(resolve) {
          if (table === 'leads') return resolve({ data: leads, error: null });
          if (table === 'properties') return resolve({ data: properties, error: null });
          return resolve({ data: [], error: null });
        }
      };
    }

    window.supabase = {
      createClient() {
        return {
          auth: {
            getSession: async () => ({ data: { session: fakeSession }, error: null }),
            getUser: async () => ({ data: { user: fakeSession.user }, error: null }),
            onAuthStateChange(cb) {
              setTimeout(() => cb('INITIAL_SESSION', fakeSession), 10);
              return { data: { subscription: { unsubscribe() {} } } };
            },
            signInWithPassword: async () => ({ data: { session: fakeSession, user: fakeSession.user }, error: null }),
            signUp: async () => ({ data: { session: fakeSession, user: fakeSession.user }, error: null }),
            signInWithOAuth: async () => ({ data: {}, error: null }),
            signOut: async () => ({ error: null }),
            resetPasswordForEmail: async () => ({ data: {}, error: null }),
          },
          from(table) { return tableHandler(table); },
          rpc(fn) {
            const okEmpty = Promise.resolve({ data: [], error: null });
            if (fn === 'get_my_tenant') return Promise.resolve({ data: { id: FAKE_TENANT_ID, industry: 'realestate', plan: 'pro' }, error: null });
            if (fn === 'list_roadmap_items_with_votes') return okEmpty;
            if (fn === 'get_agent_leaderboard') return Promise.resolve({ data: null, error: { message: 'plan_upgrade_required' } });
            if (fn === 'check_and_increment_ai_usage') return Promise.resolve({ data: { allowed: true, remaining: 5, limit: 10 }, error: null });
            if (fn === 'get_lead_image_import_quota') return Promise.resolve({ data: { remaining: 2, limit: 2 }, error: null });
            return okEmpty;
          },
          functions: { invoke: async () => ({ data: {}, error: null }) },
          storage: {
            from() {
              return {
                upload: async () => ({ data: { path: 'fake.jpg' }, error: null }),
                getPublicUrl: () => ({ data: { publicUrl: 'https://example.com/fake.jpg' } })
              };
            }
          },
          channel() { return { on() { return this; }, subscribe() { return this; } }; }
        };
      }
    };
  });

  try {
    await page.goto(filePath, { waitUntil: 'load', timeout: 20000 });
    await page.waitForTimeout(1500);

    // 1. Core modules defined (TDZ regression guard). Checked via global scope
    // eval, NOT window[name] — top-level `const`/`let` modules never attach
    // to window, so window[name] gives false negatives for most of this list.
    const modules = ['App', 'Team', 'ProHub', 'Marketing', 'Referral', 'OppBoard',
      'AgentInvite', 'InjectionGuard', 'LeadReferral', 'Support', 'Roadmap',
      'DealChecklist', 'AgencyLeaderboard', 'ABEngine', 'AppLock', 'LeadImport',
      'FeatureGate', 'Gamify', 'GuidedTour', 'AnnualUpsell'];
    const modResults = await page.evaluate((names) => {
      return names.map(n => { try { return [n, eval('typeof ' + n) !== 'undefined']; } catch (e) { return [n, false]; } });
    }, modules);
    for (const [name, ok] of modResults) record(`מודול ${name} מוגדר`, ok);

    // 2. Login screen visible, no crash
    const loginVisible = await page.evaluate(() => {
      const el = document.getElementById('screen-login');
      return el && !el.classList.contains('hidden');
    });
    record('מסך כניסה מוצג', loginVisible);

    // 3. No horizontal scroll at 390px on login screen
    const noHScroll = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 2);
    record('אין גלילה אופקית ב-390px (מסך כניסה)', noHScroll);

    // 4. escapeHtml smoke test
    const xssBlocked = await page.evaluate(() => {
      if (typeof escapeHtml !== 'function') return null;
      const out = escapeHtml('<img src=x onerror=alert(1)>');
      return !out.includes('<img');
    });
    record('escapeHtml חוסם XSS', xssBlocked === true, xssBlocked === null ? 'הפונקציה לא נגישה גלובלית' : '');

    // 5. Page/console errors. ServiceWorker can't register under file:// (no
    // origin) — that's expected here and works fine under https:// in prod,
    // so it's filtered out rather than treated as a real regression signal.
    const realPageErrors = pageErrors.filter(e => !/ServiceWorker/i.test(e));
    record('אין page errors', realPageErrors.length === 0, realPageErrors.slice(0, 5).join(' | '));
    const realConsoleErrors = consoleErrors.filter(e =>
      !/service.?worker|ServiceWorker|Failed to load resource|net::ERR/i.test(e));
    record('אין שגיאות קונסולה חריגות', realConsoleErrors.length === 0, realConsoleErrors.slice(0, 5).join(' | '));

  } catch (e) {
    record('טעינת index.html', false, e.message);
  }

  await browser.close();

  const failed = results.filter(r => !r.ok);
  console.log(`\n=== סיכום index.html: ${results.length - failed.length}/${results.length} עברו ===`);
  process.exit(failed.length ? 1 : 0);
})();
