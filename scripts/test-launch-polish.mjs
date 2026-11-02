// תיקוני בדיקת ההשקה (2.11.2026): כפתורים צפים, כיווניות, "שווי צינור", escaping,
// טיפוגרפיה בהגדרות, תרגום שגיאות, שלב הקליטה בלי AI וניסוח ניטרלי בכפתורים.
// שימוש: node scripts/test-launch-polish.mjs
import { startHarness } from './lib/harness.mjs';

const results = [];
const check = (name, ok, got) => results.push({ name, ok: !!ok, got });

// --- מסך הכניסה: כפתור הנגישות לא יושב על הטופס ---
{
  const h = await startHarness({ demo: false });
  const r = await h.page.evaluate(() => {
    const fab = document.getElementById('a11y-fab').getBoundingClientRect();
    const hits = [...document.querySelectorAll('#screen-login button, #screen-login a, #screen-login input')]
      .filter(e => { const b = e.getBoundingClientRect(); return b.width && b.height && !(b.right <= fab.left || b.left >= fab.right || b.bottom <= fab.top || b.top >= fab.bottom); })
      .map(e => e.textContent.trim().slice(0, 30) || e.id || e.tagName);
    return { visible: getComputedStyle(document.getElementById('a11y-fab')).display !== 'none', overlaps: hits };
  });
  check('login: a11y button visible and not covering the form', r.visible && r.overlaps.length === 0, r);
  await h.close();
}

const { page, errors, close } = await startHarness();

// --- כפתורים צפים: גלויים במסך הבית, מוסתרים כשחלון פתוח ---
{
  await page.evaluate(() => App.go('dashboard'));
  await page.waitForTimeout(400);
  const shown = await page.evaluate(() => ({
    a11y: getComputedStyle(document.getElementById('a11y-fab')).display,
    support: getComputedStyle(document.getElementById('support-fab-btn')).display,
  }));
  check('dashboard: floating buttons visible when no window is open', shown.a11y !== 'none' && shown.support !== 'none', shown);
  await page.evaluate(() => { localStorage.removeItem('onboarding_done'); Onboarding.show(); });
  await page.waitForTimeout(300);
  const hidden = await page.evaluate(() => ({
    a11y: getComputedStyle(document.getElementById('a11y-fab')).display,
    support: getComputedStyle(document.getElementById('support-fab-btn')).display,
  }));
  check('window open: floating buttons hidden', hidden.a11y === 'none' && hidden.support === 'none', hidden);

  // --- שלב הקליטה האחרון: בלי "סוכן" ובלי הבטחת AI, והשם עובר escape ---
  const ob = await page.evaluate(() => {
    Onboarding._data.agentName = '<img src=x onerror="window.__xss=1">דנה';
    Onboarding._step = Onboarding._steps.length - 1; Onboarding._renderStep();
    const t = document.getElementById('modal-onboarding').textContent;
    return { agent: /הסוכן שלך|אני מנטר|\bAI\b/.test(t), img: !!document.querySelector('#ob-body img') };
  });
  check('onboarding last step: no AI agent promise, name escaped', !ob.agent && !ob.img, ob);
  await page.evaluate(() => { document.getElementById('modal-onboarding').classList.add('hidden'); localStorage.setItem('onboarding_done', '1'); });
}

// --- שורת הסיכום במסך הבית: כל מספר צמוד למילים שלו ---
{
  await page.evaluate(() => { State.leads.forEach((l, i) => { if (i < 3) l.budget_max = 1000000; }); App.go('dashboard'); });
  await page.waitForTimeout(400);
  const r = await page.evaluate(() => {
    const st = document.querySelector('.today-status');
    if (!st) return { missing: true };
    const parts = [...st.querySelectorAll('.ts-part')];
    // ב-RTL כל חלק צריך להופיע מימין לחלק שאחריו
    const rects = parts.map(p => p.getBoundingClientRect());
    const ordered = rects.every((r, i) => i === 0 || rects[i - 1].top < r.top - 2 || rects[i - 1].left >= r.right - 1);
    return { parts: parts.length, isolate: parts.every(p => getComputedStyle(p).unicodeBidi === 'isolate'), ordered };
  });
  check('today status: parts isolated and in reading order', !r.missing && r.parts >= 2 && r.isolate && r.ordered, r);
}

// --- "שווי צינור": אף נתיב לא נשאר ריק ---
{
  const empty = [];
  await page.evaluate(() => { const c = document.getElementById('dash-chart-container'); if (c) c.style.display = ''; });
  for (let t = 0; t < 6; t++) {
    const v = await page.evaluate(() => [...document.querySelectorAll('.pipeline-flow-track')].map(tr => {
      const r = tr.getBoundingClientRect();
      if (!r.width) return null;
      return [...tr.querySelectorAll('.pipeline-flow-chip')].filter(c => { const b = c.getBoundingClientRect(); return b.right > r.left + 5 && b.left < r.right - 5; }).length;
    }));
    v.forEach((n, i) => { if (n === 0) empty.push(`lane ${i} at ${t * 1.2}s`); });
    await page.waitForTimeout(1200);
  }
  const lanes = await page.evaluate(() => document.querySelectorAll('.pipeline-flow-track').length);
  check('pipeline flow: no lane goes empty', lanes > 0 && empty.length === 0, { lanes, empty });
}

// --- escaping: שם שלב בחלון השידור ושם נכס בבחירת הנכס ---
{
  const r = await page.evaluate(async () => {
    window.__xss = 0;
    State.stages[0].name = '<img src=x onerror="window.__xss=1">שלב';
    ProHub._openBroadcast();
    await new Promise(r => setTimeout(r, 300));
    const injected = !!document.querySelector('.modal-overlay:not(.hidden) img[src="x"]');
    document.querySelectorAll('.modal-overlay:not(.hidden)').forEach(m => m.classList.add('hidden'));
    return { injected, fired: window.__xss };
  });
  check('broadcast window: stage name is escaped', !r.injected && !r.fired, r);
}

// --- טיפוגרפיה בהגדרות ---
{
  await page.evaluate(() => App.go('settings'));
  await page.waitForTimeout(400);
  const r = await page.evaluate(() => {
    const t = getComputedStyle(document.querySelector('.settings-section-title'));
    const sub = document.querySelector('.settings-row-sub');
    return { size: parseFloat(t.fontSize), spacing: t.letterSpacing, transform: t.textTransform, sub: sub ? parseFloat(getComputedStyle(sub).fontSize) : null };
  });
  check('settings: readable section titles', r.size >= 15 && (r.spacing === 'normal' || r.spacing === '0px') && r.transform === 'none' && (r.sub === null || r.sub >= 14), r);
}

// --- תרגום שגיאות ---
{
  const r = await page.evaluate(() => ({
    net: heError('TypeError: Failed to fetch'),
    pwd: heError('שגיאה: Password should be at least 6 characters'),
    code: heError('שגיאה: rate_limited'),
    upload: heError('שגיאה בהעלאה: The object exceeded the maximum allowed size'),
    raw: heError('Internal Server Error'),
    he: heError('נוצלה המכסה היומית'),
  }));
  const allHe = Object.values(r).every(v => /[֐-׿]/.test(v) && !/[A-Za-z]{4,}/.test(v));
  check('heError: every technical English error becomes Hebrew', allHe && r.he === 'נוצלה המכסה היומית' && r.pwd.includes('6'), r);
  const shown = await page.evaluate(() => { toast('שגיאה: Failed to fetch', 'error'); const t = [...document.querySelectorAll('.toast')].pop(); return t.textContent; });
  check('toast(error) shows Hebrew', /[֐-׿]/.test(shown) && !/fetch/i.test(shown), shown);
}

// --- ניסוח ניטרלי: אין ציווי בזכר בכפתורים ובתוויות הגלויות ---
{
  const BAD = /(^|[\s"'(])(סגור|שלח|חזור|דלג|נסה שוב|שמור|ערוך|הסתר|הצג עוד|התקן|העתק קישור|קבל את הליד|הצטרף לשיתוף|הצע רעיון|בטל מועמדות|הגש מועמדות|העבר שלב|מתחבר\.\.\.|יוצר חשבון)(?=$|[\s"'.,!?)])/;
  const SCREENS = ['dashboard', 'pipeline', 'leads', 'lead-detail', 'properties', 'tasks', 'calendar', 'analytics', 'partners', 'tools', 'settings'];
  const found = [];
  for (const s of SCREENS) {
    const hits = await page.evaluate(([s, src]) => {
      const re = new RegExp(src);
      if (s === 'lead-detail') App.go('lead-detail', { currentLeadId: State.leads[0]?.id }); else App.go(s);
      return [...document.querySelectorAll('button, a, [role=button], [aria-label], [title], option')]
        .flatMap(e => [e.textContent.trim(), e.getAttribute('aria-label') || '', e.getAttribute('title') || ''])
        .filter(t => t && t.length < 40 && re.test(t));
    }, [s, BAD.source]);
    hits.forEach(t => found.push(`${s}: ${t}`));
  }
  // כפתור הסגירה שנוסף אוטומטית לכל חלון
  const modalClose = await page.evaluate(() => [...document.querySelectorAll('.modal-close, .pwa-close')].map(b => b.getAttribute('aria-label')).filter(a => a && a !== 'סגירה'));
  check('neutral wording on visible buttons and labels', found.length === 0 && modalClose.length === 0, { found: [...new Set(found)].slice(0, 15), modalClose });
}

if (errors.length) check('no JS errors', false, errors);
await close();

let failed = 0;
for (const r of results) {
  if (!r.ok) failed++;
  console.log(`${r.ok ? 'PASS' : 'FAIL'} ${r.name}${r.ok ? '' : ' ' + JSON.stringify(r.got)}`);
}
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
