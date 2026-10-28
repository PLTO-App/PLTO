// בדיקת מצב משחק ומצב מקצועי וספריית המכירה (28.10.2026). רצה על הממשק האמיתי עם Supabase מדומה, בשני המצבים,
// ב-390px וב-1280px. לא נבדק בטלפון אמיתי ולא מול ה-DB החי.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

// הכנה: משתמש אמיתי (לא דמו) עם 6 לידים, XP נקי, ומעקב אחרי הודעות
await page.evaluate(() => {
  window.__toasts = [];
  const orig = window.toast; window.toast = (m, t, d) => { window.__toasts.push(String(m)); };
  DB.agentId = 'agent-modes'; DB.tenantId = 'tenant-modes';
  localStorage.removeItem('plto_gamify_v2:agent-modes');
  Gamify._d = null; Gamify._srv = 'off';
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  State.leads = Array.from({ length: 6 }, (_, i) => ({ id: 'm' + i, name: 'ליד ' + i, phone: '0501234567', stage: first, tags: [], created_at: new Date().toISOString().slice(0, 10) }));
  State.tenant = { ...State.tenant, industry: 'other' };
  Gamify.applyMode();
});

const vis = sel => page.evaluate(s => { const els = [...document.querySelectorAll(s)]; return els.length > 0 && els.every(e => e.getClientRects().length > 0 && getComputedStyle(e).display !== 'none'); }, sel);
const hidden = sel => page.evaluate(s => { const els = [...document.querySelectorAll(s)]; return els.length === 0 || els.every(e => getComputedStyle(e).display === 'none'); }, sel);
const overflowX = () => page.evaluate(() => document.documentElement.scrollWidth - innerWidth);

// ── ברירת מחדל ──
const def = await page.evaluate(() => {
  const r = {};
  r.game = Gamify.mode();
  State.tenant = { ...State.tenant, industry: 'realestate_lawyer' }; r.lawyer = Gamify.mode();
  Gamify.get().mode = 'game'; r.lawyerChoosesGame = Gamify.mode();
  delete Gamify.get().mode;
  State.tenant = { ...State.tenant, industry: 'other' };
  Gamify.get().mode = 'garbage'; r.garbage = Gamify.mode(); delete Gamify.get().mode;
  r.demo = (() => { State.isDemo = true; const m = Gamify.mode(); State.isDemo = false; return m; })();
  return r;
});
check(def.game === 'game', 'ברירת מחדל: מצב משחק');
check(def.lawyer === 'pro' && def.lawyerChoosesGame === 'game', 'לעו"ד ברירת המחדל מקצועי, ובחירה מפורשת במשחק מנצחת');
check(def.garbage === 'game' && def.demo === 'game', 'ערך לא תקין נופל לברירת המחדל, ובדמו לא נקרא מצב שמור');

// ── מצב משחק: הכול מוצג ──
await page.setViewportSize({ width: 1280, height: 900 });
await page.evaluate(() => { App.go('dashboard'); Gamify.renderWidget(); });
check(await vis('#gamify-widget') && await vis('#sidebar [data-screen="xp-store"]') && await vis('#today-xp'), 'מצב משחק, דסקטופ: ווידג\'ט, פריט "חנות XP" ושורת ההתקדמות מוצגים');
check(await page.evaluate(() => !document.documentElement.classList.contains('pro-mode')), 'אין מחלקת pro-mode במצב משחק');

// ── מעבר למצב מקצועי ──
const before = await page.evaluate(() => { const d = Gamify.get(); d.xp = 500; d.streak = 4; d.achievements = ['first_lead']; Gamify.save(); return { xp: d.xp, streak: d.streak }; });
await page.evaluate(() => { document.querySelector('.gamify-mode-link').click(); });
check(await page.evaluate(() => Gamify.mode() === 'pro' && document.documentElement.classList.contains('pro-mode') && Gamify.get().mode === 'pro' && Gamify.get().modeAt > 0), 'לחיצה על "מעבר למצב מקצועי" בווידג\'ט מחליפה מצב ושומרת עם חותמת זמן');
check(await hidden('#gamify-widget') && await hidden('#sidebar [data-screen="xp-store"]') && await hidden('#sidebar-level-badge') && await hidden('#motivation-card'), 'מצב מקצועי, דסקטופ: ווידג\'ט, "חנות XP", תג דרגה וכרטיס מוטיבציה מוסתרים');
check(await page.evaluate(() => !document.getElementById('today-xp')), 'שורת ההתקדמות לא מוצגת במסך היום');
check(await vis('#sidebar [data-screen="tools"]') && await vis('#sidebar [data-screen="pipeline"]') && await vis('#dash-today'), 'יכולות המכירה (פייפליין, כלים, מסך היום) נשארות');
const kept = await page.evaluate(() => ({ xp: Gamify.get().xp, streak: Gamify.get().streak, ach: Gamify.get().achievements }));
check(kept.xp === before.xp && kept.streak === before.streak && kept.ach.includes('first_lead'), 'ההתקדמות נשמרת במעבר למצב מקצועי');

// ── במצב מקצועי: ה-XP ממשיך להירשם בשקט, בלי שום חגיגה או הודעת XP ──
const quiet = await page.evaluate(async () => {
  window.__toasts.length = 0;
  document.getElementById('confetti-container').innerHTML = '';
  const d = Gamify.get();
  d.milestoneClaimed = []; d.dailyDone = null;
  const x0 = d.xp;
  Gamify.event('add_lead', { id: 'q1' });
  Gamify.event('followup_done', { id: 'q1' });
  Gamify.event('close_deal', { id: 'q2' });
  Gamify.event('advance_stage', { id: 'q3' });
  d.xp = 60000; Gamify.checkMilestones();
  d.xp = 500 + 15 + 12 + 200 + 25;
  floatXP(300);
  await new Promise(r => setTimeout(r, 1400));
  // זיכוי הפניות (היה לא מגודר)
  const orig = sbClient.rpc;
  sbClient.rpc = (fn) => Promise.resolve({ data: 2, error: null });
  Referral._data(); await Referral.pullPendingXp(); await LeadReferral.pullPendingXp();
  sbClient.rpc = orig;
  localStorage.removeItem('plto_ref_claimed'); localStorage.setItem('plto_inbound_ref', 'abc'); Referral.claimWelcomeBonus();
  await new Promise(r => setTimeout(r, 2700));
  localStorage.removeItem('plto_inbound_ref');
  return {
    gained: d.xp - x0 > 0,
    floats: document.querySelectorAll('.xp-float').length,
    confetti: document.querySelectorAll('#confetti-container .confetti-piece, #confetti-container .champagne-pop').length,
    levelup: document.getElementById('levelup-overlay').classList.contains('show'),
    milestone: document.getElementById('milestone-overlay').classList.contains('show'),
    ach: document.getElementById('achievement-toast').classList.contains('show'),
    xpToasts: window.__toasts.filter(t => /XP/.test(t)),
    otherToasts: window.__toasts.filter(t => /הצטרפו|התקבלו/.test(t)),
    leadsAdded: d.leadsAdded, followups: d.followupsDone,
  };
});
check(quiet.gained && quiet.leadsAdded >= 1 && quiet.followups === 1, 'במצב מקצועי ה-XP והספירות ממשיכים להירשם');
check(quiet.floats === 0 && quiet.confetti === 0 && !quiet.levelup && !quiet.milestone && !quiet.ach, 'במצב מקצועי אין "+XP" צף, קונפטי, עלייה ברמה, אבן דרך או הישג');
check(quiet.xpToasts.length === 0, 'במצב מקצועי אין הודעת XP, גם לא בזיכוי הפניות ובבונוס כניסה' + (quiet.xpToasts.length ? ': ' + quiet.xpToasts.join(' | ') : ''));
check(quiet.otherToasts.length >= 2, 'הודעות ההפניה עצמן (בלי XP) עדיין מוצגות');

// ── מסכים וטקסטים במצב מקצועי ──
const proScreens = await page.evaluate(() => {
  const r = {};
  App.go('xp-store');
  const s = document.getElementById('screen-xp-store');
  const shown = el => !!el && getComputedStyle(el).display !== 'none' && el.getClientRects().length > 0;
  r.storeNote = shown(s.querySelector('[data-pro]')) && /מצב מקצועי פעיל/.test(s.innerText);
  r.storeGridHidden = !shown(document.getElementById('xps-grid')) && !shown(s.querySelector('.xps-header'));
  r.storeButtons = [...s.querySelectorAll('[data-pro] button')].map(b => b.textContent.trim());
  App.go('referral');
  const rf = document.getElementById('screen-referral');
  r.refXp = [...rf.querySelectorAll('.ref-reward-row')].some(shown) || /XP/.test([...rf.querySelectorAll('.ref-header-sub')].map(e => e.innerText).join(' '));
  App.go('settings');
  const st = document.getElementById('screen-settings');
  r.settingsXp = /\+300 XP/.test(st.innerText);
  const chips = [...st.querySelectorAll('#settings-mode-row .qe-chip')];
  r.chips = chips.map(c => ({ t: c.textContent.trim(), active: c.classList.contains('active'), pressed: c.getAttribute('aria-pressed'), h: Math.round(c.getBoundingClientRect().height) }));
  r.sub = st.querySelector('#settings-mode-row .settings-row-sub').textContent;
  return r;
});
check(proScreens.storeNote && proScreens.storeGridHidden && proScreens.storeButtons.length === 2, 'חנות XP במצב מקצועי: הודעה עם שני כפתורים, בלי החנות עצמה');
check(!proScreens.refXp, 'מסך ההפניות במצב מקצועי: בלי הבטחות XP');
check(!proScreens.settingsXp, 'ההגדרות במצב מקצועי: בלי "+300 XP"');
check(proScreens.chips.length === 2 && proScreens.chips[1].active && proScreens.chips[1].pressed === 'true' && proScreens.chips[0].pressed === 'false' && /מקצועי/.test(proScreens.sub), 'ההגדרות: שורת "מצב עבודה" משקפת את המצב המקצועי');
check(proScreens.chips.every(c => c.h >= 44), 'בחירת המצב בהגדרות: שני הכפתורים בגובה 44px לפחות');

// ── חזרה למשחק: הישגים שהושגו ברקע מוצגים, והכול חוזר ──
const back = await page.evaluate(() => {
  const d = Gamify.get();
  d.achievements = []; d.leadsAdded = 6; d.xp = 500;
  document.querySelectorAll('#settings-mode-row .qe-chip')[0].click();
  return { mode: Gamify.mode(), ach: Gamify.get().achievements.slice(), cls: document.documentElement.classList.contains('pro-mode'), xp: Gamify.get().xp >= 500 };
});
check(back.mode === 'game' && !back.cls && back.xp, 'חזרה למשחק מהגדרות: המצב והמחלקה מתעדכנים וה-XP נשמר');
check(back.ach.includes('first_lead') && back.ach.includes('leads_5'), 'חזרה למשחק: הישגים שהושגו במצב מקצועי מוענקים');
check(await vis('#sidebar [data-screen="xp-store"]') || await page.evaluate(() => { App.go('dashboard'); return !!document.getElementById('today-xp'); }), 'אחרי החזרה השכבה חוזרת');

// ── הנתונים לא מהימנים, מיזוג בין מכשירים ──
const merge = await page.evaluate(() => {
  const r = {};
  const s1 = Gamify._sanitize({ mode: '<img src=x onerror=1>', modeAt: 'x', xp: 5 });
  r.badMode = s1.mode === undefined && s1.modeAt === undefined;
  const a = { xp: 100, mode: 'pro', modeAt: 1000 }, b = { xp: 900, mode: 'game', modeAt: 2000 };
  r.laterWins = Gamify._merge(a, b).mode === 'game' && Gamify._merge(b, a).mode === 'game';
  const c = { xp: 900, mode: 'game', modeAt: 1000 }, d = { xp: 100, mode: 'pro', modeAt: 3000 };
  r.laterBeatsHigherXp = Gamify._merge(c, d).mode === 'pro' && Gamify._merge(c, d).xp === 900;
  r.onlyOneHasMode = Gamify._merge({ xp: 5 }, { xp: 3, mode: 'pro', modeAt: 10 }).mode === 'pro';
  r.neither = Gamify._merge({ xp: 5 }, { xp: 3 }).mode === undefined;
  return r;
});
check(merge.badMode, 'מצב לא תקין מהשרת או מהדפדפן מסונן (אין HTML)');
check(merge.laterWins && merge.laterBeatsHigherXp && merge.onlyOneHasMode && merge.neither, 'מיזוג בין מכשירים: המצב שנבחר אחרון מנצח, בלי קשר ל-XP');
const persisted = await page.evaluate(async () => {
  Gamify.setMode('pro');
  const calls = [];
  const orig = sbClient.rpc;
  sbClient.rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve({ data: fn === 'get_my_progress' ? { data: { xp: 1, mode: 'game', modeAt: 5 } } : null, error: null }); };
  Gamify._srv = 'on'; Gamify._pushSoon(0);
  await new Promise(r => setTimeout(r, 60));
  const pushed = calls.find(c => c.fn === 'save_my_progress')?.args?.p_data;
  await Gamify.syncFromServer(); // השרת מציע game בחותמת ישנה, ולכן pro מקומי נשאר
  const stillPro = Gamify.mode() === 'pro';
  sbClient.rpc = orig; Gamify._srv = 'off';
  Gamify._d = null;
  return { pushedMode: pushed && pushed.mode, stillPro, reloaded: Gamify.get().mode };
});
check(persisted.pushedMode === 'pro' && persisted.stillPro && persisted.reloaded === 'pro', 'הבחירה נשמרת בדפדפן ונשלחת לשרת, ובחירה ישנה מהשרת לא דורסת אותה');

// ── ספריית המכירה ──
const lib = await page.evaluate(() => {
  const r = {};
  const run = (label) => {
    const out = {};
    SalesLibrary.open();
    const m = document.getElementById('modal-sales-library');
    out.open = !m.classList.contains('hidden');
    const items = [...m.querySelectorAll('.sl-item')];
    out.count = items.length;
    out.heights = items.map(i => Math.round(i.getBoundingClientRect().height));
    out.caps = [...m.querySelectorAll('.sl-cap')].map(e => e.textContent);
    out.text = m.innerText;
    items[3].click();
    const rg = document.getElementById('modal-reward-gen');
    out.packOpen = !rg.classList.contains('hidden');
    out.packTitle = document.getElementById('reward-gen-title').textContent;
    out.packLen = document.getElementById('reward-gen-out').textContent.length;
    out.noteHidden = getComputedStyle(document.getElementById('reward-gen-note')).display === 'none';
    out.genBtnHidden = document.getElementById('reward-gen-btn').style.display === 'none';
    out.stillBehind = !m.classList.contains('hidden');
    closeModal('modal-reward-gen'); closeModal('modal-sales-library');
    return out;
  };
  Gamify.get().xp = 0; Gamify.get().milestoneClaimed = [];
  r.pro0 = (Gamify.setMode('pro'), run('pro'));
  Gamify.setMode('game');
  r.game0 = run('game');
  r.packsInStore = Gamify.MILESTONES.every(m => !!RewardPack.PACKS[m.pack]);
  r.unknown = (() => { RewardPack.openById('__proto__'); RewardPack.openById('constructor'); RewardPack.openById('nope'); return document.getElementById('modal-reward-gen').classList.contains('hidden'); })();
  return r;
});
for (const [name, o] of [['מצב מקצועי', lib.pro0], ['מצב משחק', lib.game0]]) {
  check(o.open && o.count === 9, `ספרייה (${name}): תשע הערכות, גם עם 0 XP (אין נעילה לפי דרגה)`);
  check(o.packOpen && o.packLen > 200 && o.genBtnHidden && o.noteHidden && o.stillBehind, `ספרייה (${name}): לחיצה פותחת ערכה במצב קריאה, בלי הערת הסוכן, והספרייה נשארת מאחור`);
  check(o.heights.every(h => h >= 44), `ספרייה (${name}): כל כרטיס בגובה 44px לפחות`);
}
check(lib.pro0.caps.length === 0 && !/XP/.test(lib.pro0.text), 'ספרייה במצב מקצועי: בלי שורות XP או אבני דרך');
check(lib.game0.caps.length === 9 && lib.game0.caps.every(c => /אבן דרך/.test(c)), 'ספרייה במצב משחק: שורת אבן דרך ליד כל ערכה, ללא נעילה');
check(lib.packsInStore && lib.unknown, 'כל תשע הערכות קיימות, ומזהה לא מוכר (כולל __proto__) לא פותח כלום');

// ── כניסות לספרייה: כרטיס במרכז הכלים, תפריט צד, תפריט "עוד" ──
const entries = await page.evaluate(() => {
  const r = {};
  App.go('tools');
  const card = document.querySelector('#screen-tools .tool-card');
  r.firstCard = /ספריית מכירה/.test(card.innerText);
  card.querySelector('button').click();
  r.cardOpens = !document.getElementById('modal-sales-library').classList.contains('hidden');
  closeModal('modal-sales-library');
  document.querySelector('#sidebar .nav-item[onclick*="SalesLibrary"]').click();
  r.sidebarOpens = !document.getElementById('modal-sales-library').classList.contains('hidden');
  closeModal('modal-sales-library');
  return r;
});
check(entries.firstCard && entries.cardOpens && entries.sidebarOpens, 'כניסות לספרייה: כרטיס ראשון במרכז הכלים ופריט בתפריט הצד');
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(200);
await page.click('#bottom-nav .bottom-nav-item[data-screen="more"]');
const sheetGame = await page.locator('#action-sheet .as-item').allTextContents();
await page.keyboard.press('Escape');
await page.evaluate(() => { document.getElementById('action-sheet')?.classList.remove('open'); Gamify.setMode('pro'); });
await page.click('#bottom-nav .bottom-nav-item[data-screen="more"]');
const sheetPro = await page.locator('#action-sheet .as-item').allTextContents();
check(sheetGame.some(t => t.includes('ספריית מכירה')) && sheetGame.some(t => t.includes('חנות XP')), 'תפריט "עוד" במצב משחק: ספריית מכירה וחנות XP');
check(sheetPro.some(t => t.includes('ספריית מכירה')) && !sheetPro.some(t => t.includes('חנות XP')), 'תפריט "עוד" במצב מקצועי: ספריית מכירה בלי חנות XP');
await page.keyboard.press('Escape');

// ── סיור ההדרכה ──
const tour = await page.evaluate(() => {
  GuidedTour._cachedSteps = null;
  const pro = GuidedTour._getSteps().some(s => s.target === '#gamify-widget');
  Gamify.setMode('game'); GuidedTour._cachedSteps = null;
  const game = GuidedTour._getSteps().some(s => s.target === '#gamify-widget');
  return { pro, game };
});
check(!tour.pro && tour.game, 'סיור ההדרכה: שלב המשחק רק במצב משחק');

// ── מובייל 390px, שני המצבים: בלי גלישה אופקית ──
for (const mode of ['game', 'pro']) {
  await page.evaluate(m => { Gamify.setMode(m); closeModal('modal-sales-library'); }, mode);
  const widths = [];
  for (const screen of ['dashboard', 'settings', 'xp-store', 'tools', 'referral']) {
    await page.evaluate(sc => App.go(sc), screen);
    await page.waitForTimeout(150);
    widths.push([screen, await overflowX()]);
  }
  await page.evaluate(() => SalesLibrary.open());
  await page.waitForTimeout(150);
  widths.push(['library', await overflowX()]);
  const lm = await page.evaluate(() => { const m = document.querySelector('#modal-sales-library .modal'); return { scrollable: m.scrollHeight >= m.clientHeight, w: m.getBoundingClientRect().width <= innerWidth }; });
  await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', `-${mode}.png`) }).catch(() => {});
  await page.evaluate(() => closeModal('modal-sales-library'));
  check(widths.every(([, w]) => w <= 0) && lm.w, `390px, מצב ${mode === 'game' ? 'משחק' : 'מקצועי'}: בלי גלישה אופקית בדשבורד, הגדרות, חנות, כלים, הפניות והספרייה` + (widths.some(([, w]) => w > 0) ? ': ' + JSON.stringify(widths) : ''));
}
check(await page.evaluate(() => getComputedStyle(document.body).direction === 'rtl'), 'כיוון RTL');
check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
