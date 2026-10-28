// בדיקת שלב א של מצב המשחק (27.10.2026): תקופת צמיחה חינמית, XP על פעולות מכירה, אתגרים יומיים,
// שמירה לפי משתמש וגיבוי בשרת, ושורת ההתקדמות במסך היום. רצה על הממשק האמיתי עם Supabase מדומה.
// הבדיקה לא מוכיחה שהמיגרציות 129 ו-130 הורצו או שהשרת החי מתנהג כך.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

// ── תקופת צמיחה חינמית: בלי מסך תשלום, ניסיון או מחירים ──
const free = await page.evaluate(() => {
  const past = new Date(Date.now() - 40 * 864e5).toISOString();
  State.agent = { ...State.agent, email: 'user@example.com' };
  State.tenant = { ...State.tenant, plan: 'trial', trial_ends_at: past };
  const expiredTrial = Billing.isExpired();
  const isFree = Billing.isFree();
  const label = Billing.planLabel().text;
  Billing.renderTrialBanner();
  const banner = document.getElementById('trial-banner');
  const bannerHidden = !banner || banner.classList.contains('hidden') || !banner.innerHTML.trim();
  const annual = AnnualUpsell._isEligible();
  App.go('settings');
  // סעיפי ההגדרות מקופלים, ולכן נבדק כל הטקסט ולא רק הגלוי
  const settingsText = document.getElementById('screen-settings')?.textContent || '';
  const vis = el => !!el && el.getClientRects().length > 0 && getComputedStyle(el).display !== 'none';
  const mktgNav = vis(document.querySelector('#sidebar [data-screen="marketing"]'));
  App.go('marketing');
  const afterMarketing = State.screen;
  State.tenant = { ...State.tenant, plan: 'cancelled' };
  const cancelled = Billing.isExpired();
  // עסק שבוטל: מסך חסימה ניטרלי, בלי חבילות ומחירים
  Billing.showPaywall();
  const pw = document.getElementById('screen-paywall');
  const paywallText = pw.innerText;
  const paywallPlans = pw.querySelectorAll('.paywall-plan').length;
  pw.classList.add('hidden'); document.getElementById('app-shell').classList.remove('hidden');
  State.tenant = { ...State.tenant, plan: 'trial', trial_ends_at: past };
  // שאר המקומות שהציגו ניסיון או שדרוג
  App.go('settings');
  const daysLeftShown = /ימים נותרו בניסיון/.test(document.getElementById('screen-settings')?.textContent || '');
  const lb = AgencyLeaderboard._lockedHTML();
  return { expiredTrial, isFree, label, bannerHidden, annual, settingsText, mktgNav, afterMarketing, cancelled, paywallText, paywallPlans, daysLeftShown, lb };
});
check(!free.expiredTrial && free.isFree, 'ניסיון שפג לא נחסם בדפדפן, והעסק מוגדר כחינמי');
check(free.cancelled, 'עסק שבוטל נשאר חסום');
check(free.paywallPlans === 0 && !/₪|חבילה|תשלום מאובטח|ניסיון/.test(free.paywallText) && /לא פעיל/.test(free.paywallText), 'עסק שבוטל רואה מסך חסימה ניטרלי, בלי חבילות ומחירים');
check(!free.daysLeftShown, 'בהגדרות לא מוצגים "ימים נותרו בניסיון"');
check(!/שדרוג|openCheckout|₪/.test(free.lb), 'השוואת הצוות הנעולה בלי כפתור שדרוג');
check(free.label === 'חינם' && free.bannerHidden, 'אין באנר ספירה לאחור, והתוכנית מוצגת כ"חינם"');
check(!free.annual, 'מודעת המנוי השנתי לא מוצגת');
check(!/₪|ניסיון החינמי|מחירי השקה|בחירת תוכנית/.test(free.settingsText) && /חינמי/.test(free.settingsText), 'בהגדרות אין מחירים או ניסיון, יש שורת "השימוש חינמי"');
check(!/פעיל ומאובטח בצד השרת/.test(free.settingsText), 'בהגדרות ה-AI לא מוצג כפעיל כשהוא כבוי');
check(!free.mktgNav && free.afterMarketing === 'dashboard', 'תוסף השיווק בתשלום לא בתפריט ולא נגיש');

// ── שמירה לפי משתמש ומעבר מהמפתח הישן ──
const store = await page.evaluate(() => {
  localStorage.removeItem('plto_gamify_v2:agent-a'); localStorage.removeItem('plto_gamify_v2:agent-b');
  localStorage.setItem('plto_gamify_v2', JSON.stringify({ xp: 500, achievements: ['first_lead'], streak: 2 }));
  Gamify._d = null; DB.agentId = 'agent-a';
  const a = Gamify.get().xp;
  const legacyGone = localStorage.getItem('plto_gamify_v2') === null;
  const aSaved = JSON.parse(localStorage.getItem('plto_gamify_v2:agent-a') || '{}').xp;
  DB.agentId = 'agent-b';
  const b = Gamify.get().xp;
  Gamify.get().xp = 40; Gamify.save();
  DB.agentId = 'agent-a';
  const aAgain = Gamify.get().xp;
  localStorage.setItem('plto_gamify_v2:agent-c', '{not json');
  DB.agentId = 'agent-c';
  const broken = Gamify.get().xp;
  return { a, legacyGone, aSaved, b, aAgain, broken };
});
check(store.a === 500 && store.legacyGone && store.aSaved === 500, 'ה-XP מהמפתח הישן עובר למשתמש הראשון, והמפתח הישן נמחק');
check(store.b === 0 && store.aAgain === 500, 'משתמש אחר באותו דפדפן מתחיל מאפס, ולא דורס את הראשון');
check(store.broken === 0, 'נתון פגום ב-localStorage לא מפיל את המשחק');

// נתוני התקדמות לא מהימנים (localStorage או שרת) לא נכנסים כ-HTML
const xss = await page.evaluate(async () => {
  window.__pwned = 0;
  DB.agentId = 'agent-xss';
  localStorage.setItem('plto_gamify_v2:agent-xss', JSON.stringify({ xp: '50<img src=x onerror="window.__pwned=1">', streak: '<img src=x onerror="window.__pwned=1">', achievements: ['first_lead', { bad: 1 }], lastLogin: '<b>', acKeys: { send_message: ['a', 5] }, evil: '<script>' }));
  Gamify._d = null;
  const d = Gamify.get();
  const keys0 = JSON.stringify(d.acKeys?.send_message); // לפני האיפוס היומי שמתבצע ברינדור
  State.leads = Array.from({ length: 6 }, (_, i) => ({ id: 'x' + i, name: 'x', stage: State.stages[0].id, tags: [], created_at: new Date().toISOString().slice(0, 10) }));
  App.go('dashboard'); Gamify.renderWidget();
  // ההתקדמות מהשרת עוברת את אותו סינון
  const orig = sbClient.rpc;
  sbClient.rpc = () => Promise.resolve({ data: { data: { xp: 999, streak: '<img src=x onerror="window.__pwned=1">' } }, error: null });
  await Gamify.syncFromServer();
  sbClient.rpc = orig;
  Gamify.renderWidget();
  await new Promise(r => setTimeout(r, 200));
  return { xp: d.xp, streak: d.streak, ach: d.achievements, lastLogin: d.lastLogin, keys: keys0, evil: 'evil' in d, srvStreak: Gamify.get().streak, srvXp: Gamify.get().xp, pwned: window.__pwned, imgs: document.querySelectorAll('#gamify-streak img').length };
});
check(xss.streak === 0 && xss.srvStreak === 0 && xss.lastLogin === null && !xss.evil && JSON.stringify(xss.ach) === '["first_lead"]' && xss.keys === '["a"]', 'שדות ההתקדמות מסוננים לטיפוס הצפוי (מקומי ומהשרת)');
check(xss.srvXp === 999 && xss.pwned === 0 && xss.imgs === 0, 'ערך זדוני ב-streak לא מורץ כ-HTML');

// ── XP על פעולות מכירה, מגבלות וקונפטי ──
const xp = await page.evaluate(() => {
  DB.agentId = 'agent-x'; localStorage.removeItem('plto_gamify_v2:agent-x'); Gamify._d = null;
  Gamify._resetDaily(Gamify.get()); Gamify.get().dailyDone = new Date().toISOString().split('T')[0]; // אתגר היום לא מוסיף 80 XP באמצע המדידה
  State.leads = []; // הישג "פייפליין 100K" תלוי בלידים של הדמו ומוסיף XP שלא קשור לבדיקה
  const g = () => Gamify.get().xp;
  const out = {};
  let x0 = g(); Gamify.event('followup_done', { id: 'L1' }); out.follow = g() - x0;
  x0 = g(); Gamify.event('followup_done', { id: 'L1' }); out.followTwice = g() - x0;
  x0 = g(); Gamify.event('next_step', { id: 'L1' }); out.next = g() - x0;
  x0 = g(); Gamify.event('send_message', { id: 'L2' }); out.msg = g() - x0;
  x0 = g(); Gamify.event('lost_reason', { id: 'L3' }); out.lost = g() - x0;
  const old = new Date(Date.now() - 20 * 864e5).toISOString().slice(0, 10);
  x0 = g(); Gamify.contact('followup_done', { id: 'L4' }, old); out.cold = g() - x0;
  const recent = new Date(Date.now() - 3 * 864e5).toISOString().slice(0, 10);
  x0 = g(); Gamify.contact('followup_done', { id: 'L5' }, recent); out.notCold = g() - x0;
  x0 = g(); for (let i = 0; i < 20; i++) Gamify.event('send_message', { id: 'cap' + i }); out.capped = g() - x0;
  // מצב בלי משחק (עו"ד): XP נרשם בשקט, בלי קונפטי
  const prevTenant = State.tenant;
  State.tenant = { ...prevTenant, industry: 'realestate_lawyer' };
  document.getElementById('confetti-container').innerHTML = '';
  x0 = g(); Gamify.event('close_deal', { id: 'L9' }); out.silentXp = g() - x0;
  out.confetti = document.querySelectorAll('#confetti-container .confetti-piece').length;
  State.tenant = prevTenant;
  return out;
});
check(xp.follow === 12 && xp.followTwice === 0, 'פולואפ שטופל: +12 XP, פעם אחת ביום לכל ליד');
check(xp.next === 6 && xp.msg === 8 && xp.lost === 5, 'צעד הבא +6, הודעה מהתבניות +8, סיבת "לא נסגר" +5');
check(xp.cold === 42 && xp.notCold === 12, 'קשר עם ליד קפוא (14 ימים ומעלה) מוסיף 30 XP על הפולואפ');
check(xp.capped === 9 * 8, 'מגבלה יומית: עד 10 הודעות ביום מזכות ב-XP');
check(xp.silentXp === 200 && xp.confetti === 0, 'כשהמשחק כבוי: ה-XP נרשם בשקט ואין קונפטי');

// ── אתגרים יומיים: כל שמונה האתגרים מסתיימים מפעולה אמיתית ──
const ch = await page.evaluate(() => {
  const all = Gamify.DAILY_CHALLENGES.slice();
  const old = new Date(Date.now() - 20 * 864e5).toISOString().slice(0, 10);
  const doIt = {
    'ניצור קשר עם 3 לידים שלא קיבלו מענה השבוע': () => { Gamify.event('followup_done', { id: 'a' }); Gamify.event('send_message', { id: 'b' }); Gamify.event('log_activity', { id: 'c' }); },
    'נעדכן את השלב של ליד אחד לפחות': () => Gamify.event('advance_stage', { id: 'a' }),
    'נוסיף ליד חדש למערכת': () => Gamify.event('add_lead', { id: 'a' }),
    'נסגור 2 משימות פתוחות היום': () => { Gamify.event('complete_task'); Gamify.event('complete_task'); },
    'נכתוב הודעת פולואפ מוכנה מהתבניות': () => Gamify.event('send_message', { id: 'free:whatsapp' }),
    'נבדוק לידים קפואים ונחזיר אותם לפעולה': () => Gamify.contact('followup_done', { id: 'a' }, old),
    'נתעד את הפגישה האחרונה, נוסיף הערה ב-CRM': () => Gamify.event('log_activity', { id: 'a' }),
    'נתכנן 3 פולואפים לשבוע הבא': () => { Gamify.event('next_step', { id: 'a' }); Gamify.event('next_step', { id: 'b' }); Gamify.event('next_step', { id: 'c' }); },
  };
  const res = [];
  for (const text of all) {
    DB.agentId = 'agent-ch'; localStorage.removeItem('plto_gamify_v2:agent-ch'); Gamify._d = null;
    Gamify.DAILY_CHALLENGES = [text];
    const partial = Gamify.CHALLENGE_GOALS[text].count > 1;
    let midDone = null;
    if (partial) { (text.startsWith('ניצור קשר') ? () => Gamify.event('followup_done', { id: 'a' }) : text.startsWith('נסגור') ? () => Gamify.event('complete_task') : () => Gamify.event('next_step', { id: 'a' }))(); midDone = Gamify.getDailyChallenge().done; Gamify._d = null; localStorage.removeItem('plto_gamify_v2:agent-ch'); }
    doIt[text]();
    res.push({ text, done: Gamify.getDailyChallenge().done, midDone, has: !!doIt[text] });
  }
  Gamify.DAILY_CHALLENGES = all;
  return { res, count: all.length };
});
check(ch.count === 8 && ch.res.every(r => r.has), 'שמונת האתגרים הקיימים נשמרו');
for (const r of ch.res) check(r.done && r.midDone !== true, `אתגר מסתיים מפעולה אמיתית: ${r.text}`);

// ── גיבוי בשרת: אימוץ התקדמות גבוהה יותר, שמירה, ונפילה שקטה בלי המיגרציה ──
const srv = await page.evaluate(async () => {
  const calls = [];
  const orig = sbClient.rpc;
  DB.agentId = 'agent-s'; localStorage.removeItem('plto_gamify_v2:agent-s'); Gamify._d = null;
  Gamify.get().xp = 100; Gamify.save();
  sbClient.rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve(fn === 'get_my_progress' ? { data: { data: { xp: 900, streak: 5 } }, error: null } : { data: null, error: null }); };
  await Gamify.syncFromServer();
  const adopted = Gamify.get().xp, srvState = Gamify._srv;
  Gamify.get().xp += 10; Gamify._pushSoon(0);
  await new Promise(r => setTimeout(r, 60));
  const saved = calls.find(c => c.fn === 'save_my_progress');
  DB.agentId = 'agent-m'; Gamify._d = null;
  sbClient.rpc = (fn) => { calls.push({ fn }); return Promise.resolve({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } }); };
  Gamify.get().xp = 30; Gamify.save();
  await Gamify.syncFromServer();
  const offState = Gamify._srv, localKept = Gamify.get().xp;
  sbClient.rpc = orig;
  return { adopted, srvState, savedXp: saved?.args?.p_data?.xp, offState, localKept };
});
check(srv.adopted === 900 && srv.srvState === 'on', 'התקדמות גבוהה יותר מהשרת (מכשיר אחר) מאומצת');
check(srv.savedXp === 910, 'שמירה נשלחת לשרת עם ה-XP העדכני');
check(srv.offState === 'off' && srv.localKept === 30, 'בלי מיגרציה 130: נופל בשקט להתקדמות מקומית');

// מיזוג בין שני מכשירים: לא מאבדים הישגים ותביעת פרס שנעשו רק במכשיר הזה
const mrg = await page.evaluate(async () => {
  const calls = [];
  const orig = sbClient.rpc;
  DB.agentId = 'agent-merge'; localStorage.removeItem('plto_gamify_v2:agent-merge'); Gamify._d = null; Gamify._srv = null;
  const g = Gamify.get();
  Object.assign(g, { xp: 100, achievements: ['first_lead'], milestoneClaimed: [3000], dealsClosed: 4, leadsAdded: 2 });
  Gamify.save();
  sbClient.rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve(fn === 'get_my_progress'
    ? { data: { data: { xp: 900, streak: 5, achievements: ['leads_5'], milestoneClaimed: [], dealsClosed: 1, leadsAdded: 9 } }, error: null }
    : { data: null, error: null }); };
  await Gamify.syncFromServer();
  await new Promise(r => setTimeout(r, 60));
  const m = Gamify.get();
  const pushed = calls.find(c => c.fn === 'save_my_progress')?.args?.p_data;
  // אותו מצב בשני הצדדים: אין שליחה מיותרת לשרת
  calls.length = 0;
  sbClient.rpc = (fn, args) => { calls.push({ fn }); return Promise.resolve(fn === 'get_my_progress' ? { data: { data: JSON.parse(JSON.stringify(Gamify.get())) }, error: null } : { data: null, error: null }); };
  await Gamify.syncFromServer();
  await new Promise(r => setTimeout(r, 60));
  const idempotentPush = calls.some(c => c.fn === 'save_my_progress');
  sbClient.rpc = orig;
  return { xp: m.xp, ach: m.achievements.slice().sort(), claimed: m.milestoneClaimed, deals: m.dealsClosed, leads: m.leadsAdded, streak: m.streak, pushedAch: pushed && pushed.achievements.slice().sort(), idempotentPush };
});
check(mrg.xp === 900 && mrg.streak === 5, 'מיזוג: ה-XP והרצף נלקחים מהצד שהתקדם יותר');
check(JSON.stringify(mrg.ach) === '["first_lead","leads_5"]' && JSON.stringify(mrg.claimed) === '[3000]', 'מיזוג: הישגים ותביעת פרס משני המכשירים נשמרים');
check(mrg.deals === 4 && mrg.leads === 9, 'מיזוג: בספירות מצטברות נלקח הערך הגבוה');
check(JSON.stringify(mrg.pushedAch) === '["first_lead","leads_5"]', 'המצב הממוזג נשלח חזרה לשרת');
check(!mrg.idempotentPush, 'כשהמצב זהה בשני הצדדים לא נשלח כלום לשרת');

// ── שורת ההתקדמות במסך היום, 390px ──
const strip = await page.evaluate(() => {
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  const mk = id => ({ id, name: 'ליד ארוך מאוד בשם שלא נגמר ' + id, phone: '0501234567', stage: first, source: 'call', budget_max: 0, tags: [], notes: '', last_contact: null, next_followup: null, created_at: iso(0) });
  DB.agentId = 'agent-t'; localStorage.removeItem('plto_gamify_v2:agent-t'); Gamify._d = null;
  App.go('dashboard');
  State.leads = ['1', '2', '3'].map(mk);
  Today.render();
  const locked = document.getElementById('today-xp')?.innerText || '';
  State.leads = ['1', '2', '3', '4', '5', '6'].map(mk);
  Today.render();
  const el = document.getElementById('today-xp');
  const txt = el?.innerText || '';
  const before = txt;
  Gamify.event('followup_done', { id: '1' });
  const after = document.getElementById('today-xp')?.innerText || '';
  const btns = [...(el ? document.querySelectorAll('#today-xp button') : [])].map(b => Math.round(b.getBoundingClientRect().height));
  const cur = document.getElementById('today-xp');
  const overflow = document.documentElement.scrollWidth - innerWidth;
  const stripOverflow = cur ? cur.scrollWidth - cur.clientWidth : 0;
  const prevTenant = State.tenant;
  State.tenant = { ...prevTenant, industry: 'realestate_lawyer' };
  Today.render();
  const proHidden = !document.getElementById('today-xp');
  State.tenant = prevTenant;
  Today.render();
  return { locked, txt, before, after, btns, overflow, stripOverflow, proHidden, dir: getComputedStyle(document.getElementById('today-xp')).direction };
});
check(/עוד 2 לידים ונפתח המשחק/.test(strip.locked), 'לפני 5 לידים: השורה מראה כמה חסר לפתיחת המשחק');
check(/XP/.test(strip.txt) && /אתגר היום/.test(strip.txt), 'אחרי 5 לידים: דרגה, XP ואתגר היום במסך היום');
check(strip.before !== strip.after, 'השורה מתעדכנת מיד אחרי צבירת XP');
check(strip.btns.length === 2 && strip.btns.every(h => h >= 44), 'שני הכפתורים בשורה בגובה 44px לפחות');
check(strip.overflow <= 0 && strip.stripOverflow <= 1 && strip.dir === 'rtl', '390px: בלי גלישה אופקית, RTL');
check(strip.proHidden, 'כשהמשחק כבוי השורה לא מוצגת');
await page.locator('#dash-today').scrollIntoViewIfNeeded();
await page.screenshot({ path: process.env.SHOT || '/dev/null' }).catch(() => {});

check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
