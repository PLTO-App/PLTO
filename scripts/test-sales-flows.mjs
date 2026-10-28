// בדיקת פעולות המכירה האמיתיות בשני מצבי העבודה (28.10.2026). הפעולות מופעלות דרך פונקציות הממשק עצמן
// (הוספת ליד, העברת שלב, סגירת עסקה, צעד הבא, ליד שלא נסגר, טיפול ב"היום", משימה, תיעוד שיחה, שליחת נוסח),
// עם שכבת הנתונים מדומה. נבדק שכל פעולה מתבצעת ומעדכנת את הנתונים בשני המצבים, ש-XP נרשם בשניהם,
// ושבמצב מקצועי אין הודעת XP, "+XP" צף, קונפטי, חלון עליית דרגה או אבן דרך. לא נוגע ב-Supabase אמיתי.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const run = (mode) => page.evaluate(async (mode) => {
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  DB.agentId = 'flows-' + mode; DB.tenantId = 'tf'; localStorage.removeItem('plto_gamify_v2:flows-' + mode); Gamify._d = null; Gamify._srv = 'off';
  State.isDemo = false;
  State.agent = { ...State.agent, role: 'owner' };
  State.tenant = { ...State.tenant, industry: 'other', plan: 'trial', whatsapp_number: '' };
  State.leads = [];
  Gamify.setMode(mode);
  const d0 = Gamify.get(); d0.dailyDone = new Date().toISOString().split('T')[0];
  const stages = State.stages.slice().sort((a, b) => a.order - b.order);
  const won = stages.find(s => isWonStage(s.id));
  const mid = stages.find(s => !isWonStage(s.id) && s.id !== stages[0].id);
  const old = new Date(Date.now() - 20 * 864e5).toISOString().slice(0, 10);
  State.leads = [
    { id: 'f1', name: 'לקוח א', phone: '0501111111', stage: stages[0].id, tags: [], created_at: old, last_contact: old, next_followup: today() },
    { id: 'f2', name: 'לקוח ב', phone: '0502222222', stage: stages[0].id, tags: [], created_at: old, last_contact: old },
    { id: 'f3', name: 'לקוח ג', phone: '0503333333', stage: stages[0].id, tags: [], created_at: old, last_contact: old },
    { id: 'f4', name: 'לקוח ד', phone: '0504444444', stage: stages[0].id, tags: [], created_at: old, last_contact: old },
  ];
  State.tasks = [{ id: 'tk1', lead_id: 'f2', title: 'חזרה ללקוח ב', type: 'call', priority: 'medium', due: today(), done: false }];
  State.activities = [];
  // שכבת נתונים מדומה: כל כתיבה מצליחה
  let seq = 0;
  const stub = {
    addLead: async (l) => ({ ...l, id: 'new' + (++seq), stage: stages[0].id, tags: [], created_at: today() }),
    updateLead: async () => ({}), moveLead: async () => ({}),
    addTask: async (t) => ({ ...t, id: 'tn' + (++seq), done: false }), updateTask: async () => ({}),
    addActivity: async (a) => ({ ...a, id: 'a' + (++seq), created_at: today() }),
  };
  const orig = {}; for (const k in stub) { orig[k] = DB[k]; DB[k] = stub[k]; }
  const origMake = { n: Make.newLead, s: Make.stageChanged, t: Make.taskDone }; Make.newLead = Make.stageChanged = Make.taskDone = () => {};
  const toasts = []; const origToast = window.toast; window.toast = (m, t) => { toasts.push(String(m)); };
  const origSave = SaveAnim.success; SaveAnim.success = (cb) => { try { cb && cb(); } catch (_) {} };

  const d = () => Gamify.get();
  const res = {};
  const step = async (name, fn) => {
    const x0 = d().xp; const t0 = toasts.length;
    try { await fn(); } catch (e) { res[name] = { err: String(e) }; return; }
    await wait(60);
    res[name] = { gained: d().xp - x0, toasts: toasts.slice(t0) };
  };

  await step('add_lead', async () => {
    document.getElementById('new-lead-name').value = 'ליד חדש';
    document.getElementById('new-lead-phone').value = '0505555555';
    document.getElementById('new-lead-notes').value = 'הערה';
    await addLead(true);
    res.leadAdded = State.leads.some(l => l.name === 'ליד חדש');
  });
  await step('advance_stage', async () => { await moveLeadActual('f2', mid.id); res.advanced = State.leads.find(l => l.id === 'f2').stage === mid.id; });
  await step('close_deal', async () => { await moveLeadActual('f3', won.id); res.closed = State.leads.find(l => l.id === 'f3').stage === won.id; });
  await step('followup_today', async () => { await Today.done('f1'); res.followed = State.leads.find(l => l.id === 'f1').last_contact === today(); });
  await step('task_done', async () => { await toggleTask('tk1'); res.taskDone = State.tasks.find(t => t.id === 'tk1').done; });
  await step('next_step', async () => { NextStep.ask('f1'); await NextStep._save(new Date(Date.now() + 2 * 864e5).toISOString().slice(0, 10)); res.nextSet = !!State.leads.find(l => l.id === 'f1').next_followup; });
  await step('lost_deal', async () => { LostDeal.ask('f4'); await LostDeal.save(0); res.lost = !State.leads.some(l => l.id === 'f4') && State.lostLeads.some(l => l.id === 'f4'); });
  await step('quick_log', async () => { CallLog._leadId = 'f2'; await CallLog.log('talked'); res.logged = State.activities.some(a => a.lead_id === 'f2' && a.type === 'call'); });
  await step('template_message', async () => { SmartWA._leadId = 'f2'; SmartWA._award(); });
  // תוצאות רעש: כל מה שהמשתמש היה רואה
  res.noise = {
    floats: document.querySelectorAll('.xp-float').length,
    confetti: document.querySelectorAll('#confetti-container .confetti-piece, #confetti-container .champagne-pop').length,
    levelup: document.getElementById('levelup-overlay').classList.contains('show'),
    milestone: document.getElementById('milestone-overlay').classList.contains('show'),
    ach: document.getElementById('achievement-toast').classList.contains('show'),
    xpToasts: toasts.filter(t => /XP|דרגה|הישג|רצף/.test(t)),
  };
  res.total = d().xp;
  if (mode === 'pro') { Gamify.setMode('game'); await wait(50); }
  res.totalAfterReturn = d().xp; res.ach = JSON.stringify(d().achievements); res.counters = { leads: d().leadsAdded, follow: d().followupsDone, deals: d().dealsClosed };

  for (const k in orig) DB[k] = orig[k];
  Make.newLead = origMake.n; Make.stageChanged = origMake.s; Make.taskDone = origMake.t;
  window.toast = origToast; SaveAnim.success = origSave;
  return res;
}, mode);

const game = await run('game');
if (process.env.DBG) console.log(game.ach);
const pro = await run('pro');
if (process.env.DBG) console.log(pro.ach);

for (const [label, r] of [['משחק', game], ['מקצועי', pro]]) {
  check(r.leadAdded, `(${label}) הוספת ליד: הליד נוסף לרשימה`);
  check(r.advanced && r.closed, `(${label}) העברת שלב וסגירת עסקה: השלבים התעדכנו`);
  check(r.followed && r.taskDone, `(${label}) טיפול בליד ב"היום" וסימון משימה: הנתונים התעדכנו`);
  check(r.nextSet, `(${label}) צעד הבא: נקבע תאריך מעקב`);
  check(r.lost, `(${label}) ליד שלא נסגר: יצא מהפייפליין ונשמר ברשימת הלא-נסגרו`);
  check(r.logged, `(${label}) תיעוד שיחה מהיר: נרשם בפעילות`);
  const errs = Object.entries(r).filter(([, v]) => v && v.err);
  check(errs.length === 0, `(${label}) אין חריגות באף פעולה` + (errs.length ? ': ' + JSON.stringify(errs) : ''));
  for (const k of ['add_lead', 'advance_stage', 'close_deal', 'followup_today', 'task_done', 'next_step', 'lost_deal', 'quick_log', 'template_message']) {
    check(r[k] && r[k].gained > 0, `(${label}) ${k}: XP נרשם (${r[k] && r[k].gained})`);
  }
  check(r.counters.leads >= 1 && r.counters.deals >= 1 && r.counters.follow >= 1, `(${label}) ספירות הליבה (לידים, עסקאות, מעקבים) נרשמו`);
}
check(pro.total <= game.total && pro.totalAfterReturn === game.total, `אותו רצף פעולות מניב אותו XP בשני המצבים: מצב מקצועי ${pro.total}, אחרי חזרה למשחק ${pro.totalAfterReturn} (הישגים מוענקים בחזרה), מצב משחק ${game.total}`);
check(pro.noise.floats === 0 && pro.noise.confetti === 0 && !pro.noise.levelup && !pro.noise.milestone && !pro.noise.ach, 'מצב מקצועי: אין "+XP" צף, קונפטי, עליית דרגה, אבן דרך או הישג');
check(pro.noise.xpToasts.length === 0, 'מצב מקצועי: אף הודעה לא מזכירה XP, דרגה, הישג או רצף' + (pro.noise.xpToasts.length ? ': ' + pro.noise.xpToasts.join(' | ') : ''));
check(Object.values(pro).every(v => !v || !v.toasts || v.toasts.every(t => !/XP/.test(t))), 'מצב מקצועי: הודעות הפעולות עצמן נשארות בלי XP');
check(game.noise.floats > 0, 'מצב משחק: מופיע "+XP" צף (הבדיקה מזהה שהמשחק פעיל)');
check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
