// סימולציה דטרמיניסטית של קצב ההתקדמות (28.10.2026). לא חלק מה-CI ולא נוגעת בקוד המוצר.
// משווה את חוקי ה-XP הנוכחיים לחוקי "איכות" מוצעים, על ארבעה פרופילי שימוש (קל, רגיל, אינטנסיבי, לוחץ-על-הכול),
// ומראה כמה ימים לוקח להגיע לכל דרגה בסולם מוצע. המספרים הם הנחות על התנהגות, לא מדידה של משתמשים אמיתיים,
// והם נועדו לדון בהם עם הבעלים לפני שמשנים משהו.
//
// הרצה: node scripts/sim-levels.mjs

// נתוני יום ממוצע לכל פרופיל. r = שיעור הפעולות הרלוונטיות (ליד שהגיע זמן המעקב שלו או שלא דיברו איתו 3 ימים ומעלה),
// c = שיעור המעקבים מול ליד קפוא (14 ימים ומעלה), rn = שיעור "צעד הבא" שהיה באמת חסר,
// ra = שיעור קידומי השלב על לידים אמיתיים (עם קשר מתועד), rt = שיעור המשימות שנוצרו מראש ולא רק כדי לסמן,
// rl = שיעור הלידים החדשים שהגיעו אחר כך לקשר ראשון.
const PROFILES = {
  'קל':       { pActive: 5/7, newLeads: 0.5, fu: 2,  ns: 2,  msg: 2,  adv: 0.5, tasks: 1, ai: 0, log: 1,  deals: 0.04, lost: 0.1, r: 0.8,  c: 0.10, rn: 0.8, ra: 0.9, rt: 0.9, rl: 0.9, habit: { clear: 0.2, nextAll: 0.2, fast: 0.4, week: 0.2 } },
  'רגיל':     { pActive: 6/7, newLeads: 1.5, fu: 6,  ns: 5,  msg: 5,  adv: 2,   tasks: 3, ai: 1, log: 3,  deals: 0.12, lost: 0.3, r: 0.8,  c: 0.10, rn: 0.8, ra: 0.9, rt: 0.9, rl: 0.9, habit: { clear: 0.5, nextAll: 0.4, fast: 0.6, week: 0.6 } },
  'אינטנסיבי':{ pActive: 1,   newLeads: 4,   fu: 12, ns: 10, msg: 8,  adv: 5,   tasks: 6, ai: 2, log: 6,  deals: 0.30, lost: 0.8, r: 0.8,  c: 0.10, rn: 0.8, ra: 0.9, rt: 0.9, rl: 0.9, habit: { clear: 0.7, nextAll: 0.6, fast: 0.8, week: 0.9 } },
  // משתמש שלוחץ על הכול כדי לצבור נקודות: לידים ריקים, תיעוד אין-סופי, העתקת נוסחים, בלי עבודה אמיתית
  'לוחץ על הכול': { pActive: 1, newLeads: 10, fu: 15, ns: 15, msg: 10, adv: 8, tasks: 8, ai: 3, log: 50, deals: 0, lost: 5, r: 0.05, c: 0, rn: 0.05, ra: 0.1, rt: 0.1, rl: 0.2, habit: { clear: 0, nextAll: 0, fast: 0, week: 0 } },
};

const XP = { add_lead: 15, advance: 25, close: 200, task: 12, ai: 8, log: 10, login: 8, cold: 30, fu: 12, ns: 6, msg: 8, lost: 5 };
const CAP = { fu: 15, ns: 15, msg: 10, lost: 5, newLeads: 10, tasks: 8, ai: 3 };
const m = Math.min;

// חוקים נוכחיים
function dayCurrent(p) {
  return p.pActive * (
    m(p.newLeads, CAP.newLeads) * XP.add_lead + p.adv * XP.advance + p.deals * XP.close + m(p.tasks, CAP.tasks) * XP.task +
    m(p.ai, CAP.ai) * XP.ai + p.log * XP.log + XP.login + m(p.fu, CAP.fu) * XP.fu + m(p.fu, CAP.fu) * p.c * XP.cold +
    m(p.ns, CAP.ns) * XP.ns + m(p.msg, CAP.msg) * XP.msg + m(p.lost, CAP.lost) * XP.lost
  );
}

// חוקי איכות מוצעים: מעקב, הודעה וצעד הבא מלאים רק כשהם רלוונטיים (רבע מהערך אחרת),
// תיעוד פעילות עד 5 ביום, ליד חדש מעל 5 ביום שווה שליש, תקרה רכה על XP של יצירת קשר, ובונוסי הרגלים.
const SOFT_CAP = 250;      // תקרה רכה ל-XP של יצירת קשר ביום
const DAY_SOFT_CAP = 400;  // תקרה רכה ל-XP כולל ביום (מעליה רבע מהערך)
const IRR = 0.1;           // שיעור הערך שנשאר לפעולה לא רלוונטית
function dayProposed(p) {
  const fuN = m(p.fu, CAP.fu), nsN = m(p.ns, CAP.ns), msgN = m(p.msg, CAP.msg);
  const part = (n, full, r) => n * (full * r + full * IRR * (1 - r));
  let contact = part(fuN, XP.fu, p.r) + fuN * p.c * XP.cold * p.r + part(nsN, XP.ns, p.rn) + part(msgN, XP.msg, p.r) + m(p.log, 5) * XP.log * (p.r > 0.5 ? 1 : IRR);
  if (contact > SOFT_CAP) contact = SOFT_CAP + (contact - SOFT_CAP) * 0.25;
  const soft = (full, r) => full * r + full * IRR * (1 - r);
  // ליד חדש: רבע ביצירה, שלושה רבעים כשיש קשר ראשון מתועד. מעל 5 ביום: שליש
  const leadFull = m(p.newLeads, 5) * XP.add_lead + m(m(p.newLeads, 10) - 5, 5) * (XP.add_lead / 3);
  const leads = leadFull * 0.25 + leadFull * 0.75 * p.rl;
  const habits = 40 * p.habit.clear + 30 * p.habit.nextAll + 20 * m(p.newLeads, 5) * p.habit.fast + (100 / 7) * p.habit.week;
  const total = (leads + soft(p.adv * XP.advance, p.ra) + p.deals * XP.close + soft(m(p.tasks, CAP.tasks) * XP.task, p.rt) + m(p.ai, CAP.ai) * XP.ai + XP.login + contact + m(p.lost, CAP.lost) * XP.lost + habits);
  const capped = total > DAY_SOFT_CAP ? DAY_SOFT_CAP + (total - DAY_SOFT_CAP) * 0.25 : total;
  return p.pActive * capped;
}

// סולמות. המספרים הם הצעה לדיון, והשמות הם מציינים עד שייקבעו.
const CURRENT = [0, 50, 150, 350, 800];
const TARGET_DAYS = [0, 1, 3, 7, 14, 30, 60, 110, 180, 280]; // ימי יעד למשתמש רגיל להגיע לדרגה 1..10
const nice = (x) => x < 200 ? Math.round(x / 25) * 25 : x < 2000 ? Math.round(x / 50) * 50 : x < 10000 ? Math.round(x / 250) * 250 : Math.round(x / 500) * 500;

const reg = PROFILES['רגיל'];
const regDay = dayProposed(reg);
const LADDER = TARGET_DAYS.map((d, i) => i === 0 ? 0 : nice(d * regDay));

const daysTo = (xpPerDay, threshold) => xpPerDay <= 0 ? Infinity : Math.ceil(threshold / xpPerDay);
const fmt = (n) => n === Infinity ? '—' : String(n);

console.log('XP ליום (ממוצע, כולל ימים בלי פעילות)');
console.log('פרופיל'.padEnd(16), 'נוכחי'.padStart(8), 'מוצע'.padStart(8), 'יחס מוצע/נוכחי'.padStart(18));
for (const [name, p] of Object.entries(PROFILES)) {
  const c = dayCurrent(p), q = dayProposed(p);
  console.log(name.padEnd(16), c.toFixed(0).padStart(8), q.toFixed(0).padStart(8), (q / c).toFixed(2).padStart(18));
}
const lazy = dayProposed(PROFILES['לוחץ על הכול']), regP = regDay, regC = dayCurrent(reg);
console.log(`\nלוחץ על הכול מול משתמש רגיל: נוכחי ${(dayCurrent(PROFILES['לוחץ על הכול']) / regC).toFixed(2)}x, מוצע ${(lazy / regP).toFixed(2)}x`);

console.log('\nסולם מוצע (XP מצטבר לכל דרגה) והימים להגעה לדרגה');
console.log('דרגה'.padEnd(6), 'סף XP'.padStart(8), ...Object.keys(PROFILES).map(n => n.padStart(14)));
LADDER.forEach((t, i) => {
  console.log(String(i + 1).padEnd(6), String(t).padStart(8), ...Object.values(PROFILES).map(p => fmt(daysTo(dayProposed(p), t)).padStart(14)));
});

console.log('\nהסולם הנוכחי (5 דרגות) תחת החוקים הנוכחיים: ימים להגעה');
CURRENT.forEach((t, i) => console.log(String(i + 1).padEnd(6), String(t).padStart(8), ...Object.values(PROFILES).map(p => fmt(daysTo(dayCurrent(p), t)).padStart(14))));

// אבני דרך של ערכות: לכל ערכה "חגיגה" בדרגה שבה היא נפתחת בהקשר (הערכות עצמן פתוחות לכולם)
const PACK_AT = { followup: 2, opening: 3, process: 4, needs: 5, objections: 6, trust: 7, referrals: 8, closing: 9, routine: 10 };
console.log('\nימים עד חגיגת הערכה בדרגה שבה היא מוצעת (משתמש רגיל, הסולם המוצע)');
for (const [pack, lvl] of Object.entries(PACK_AT)) console.log(pack.padEnd(12), `דרגה ${lvl}`.padEnd(10), String(daysTo(regP, LADDER[lvl - 1])).padStart(5), 'ימים');
