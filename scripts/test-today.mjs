// בדיקת הלוגיקה של מסך "היום", הצעד הבא ו"לא נסגר". רצה על הממשק האמיתי עם Supabase מדומה.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const r = await page.evaluate(() => {
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  const won = wonStageId();
  const mk = (id, extra) => ({ id, name: 'ליד ' + id, phone: '0501234567', stage: first, source: 'call', budget_max: 0, tags: [], notes: '', last_contact: null, next_followup: null, created_at: iso(0), ...extra });
  State.tasks = [];
  State.leads = [
    mk('fresh', {}),                                                   // חדש, בלי מענה
    mk('imported', { tags: ['יובא מקובץ'], created_at: iso(-3) }),      // מיובא ולא טופל
    mk('overdue3', { next_followup: iso(-3), last_contact: iso(-5), created_at: iso(-20) }),
    mk('overdue10', { next_followup: iso(-10), last_contact: iso(-12), created_at: iso(-30) }),
    mk('due_today', { next_followup: iso(0), last_contact: iso(-2), created_at: iso(-9) }),
    mk('future', { next_followup: iso(4), last_contact: iso(-1), created_at: iso(-9) }),
    mk('nostep_old', { last_contact: iso(-20), created_at: iso(-60) }),  // בלי צעד הבא, קר
    mk('client_due', { stage: won, next_followup: iso(-1), created_at: iso(-90) }),
    mk('client_later', { stage: won, next_followup: iso(30), created_at: iso(-90) }),
    mk('task_only', { last_contact: iso(-1), created_at: iso(-9) }),
  ];
  State.tasks = [{ id: 'tk1', title: 'לשלוח הצעה', type: 'call', priority: 'medium', due: iso(0), done: false, lead_id: 'task_only', notes: '' }];
  const { g, imported } = Today.compute();
  const ids = k => g[k].map(x => x.lead.id).sort();
  Today.render();
  return {
    overdue: ids('overdue'), oldOverdue: ids('oldOverdue'), today: ids('today'), fresh: ids('fresh'),
    attention: ids('attention'), clients: ids('clients'), imported,
    html: document.getElementById('dash-today').innerText,
    taskStep: NextStep.dateOf(State.leads.find(l => l.id === 'task_only')),
    todayIso: iso(0),
  };
});
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
check(eq(r.fresh, ['fresh']), 'ליד חדש בלי מענה מופיע ב"חדשים"');
check(r.imported === 1 && !r.fresh.includes('imported'), 'ליד מיובא לא מציף: נספר בשורה מסכמת בלבד');
check(eq(r.overdue, ['overdue3']), 'באיחור של עד שבוע מוצג כשורה');
check(eq(r.oldOverdue, ['overdue10']) && /מעקב ישן אחד/.test(r.html), 'באיחור של יותר משבוע מוצג כשורה מסכמת');
check(eq(r.today, ['due_today', 'task_only']), 'מעקב להיום, וגם משימה פתוחה להיום, מופיעים ב"להיום"');
check(r.taskStep === r.todayIso, 'הצעד הבא נגזר ממשימה פתוחה כשאין תאריך בליד');
check(eq(r.attention, ['nostep_old']), 'ליד בלי צעד הבא וקר מופיע ב"דורשים תשומת לב"');
check(!r.attention.includes('future') && !r.today.includes('future') && !r.overdue.includes('future'), 'ליד עם צעד עתידי לא מופיע');
check(eq(r.clients, ['client_due']), 'לקוח שהגיע מועד לחזור אליו מופיע ב"שמירת קשר"');
check(/דורשים טיפול/.test(r.html) && /לידים מיובאים שעוד לא טופלו/.test(r.html), 'שורת המצב והערת הייבוא מוצגות');

// "לא נסגר": הליד יוצא מ-State.leads ועובר לרשימה נפרדת
const lost = await page.evaluate(async () => {
  State.isDemo = false;
  LostDeal._id = 'fresh';
  const before = State.leads.length;
  await LostDeal.save(0);
  return { before, after: State.leads.length, inLost: State.lostLeads.some(l => l.id === 'fresh'), inCompute: Today.compute().g.fresh.length };
});
check(lost.after === lost.before - 1 && lost.inLost && lost.inCompute === 0, '"לא נסגר" מוציא את הליד מהפייפליין ומחישוב היום');

// לא נשמר ציון קבוע: שורת ליד לא מציגה את הערך 50
const row = await page.evaluate(() => LeadRow.render(State.leads[0], { variant: 'row', idx: 0 }));
check(!/score-badge/.test(row) && /אין קשר מתועד|קשר:/.test(row), 'שורת ליד מציגה "קשר אחרון" ולא ציון קבוע');

check(errors.length === 0, 'אין שגיאות JS בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
console.log(failures ? failures + ' נכשלו' : 'הכל עבר');
process.exit(failures ? 1 : 0);
