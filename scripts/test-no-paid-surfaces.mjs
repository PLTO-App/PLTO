// בדיקת רגרסיה (28.10.2026): בתקופת הצמיחה החינמית אין במערכת מחירים, הצעות שדרוג, פרסום מוצר בתשלום או הבטחות ניסיון,
// בשום מסך ובשום מצב עבודה, גם לעסק שתקופת הניסיון שלו הסתיימה וגם לעסק שבוטל. במצב מקצועי אין גם שפת משחק.
// רצה על הממשק האמיתי עם Supabase מדומה. בודקת טקסט גלוי בלבד, ולא מחליפה בדיקה ידנית של תבניות המייל של Supabase Auth.
import { startHarness } from './lib/harness.mjs';
import { readFileSync } from 'node:fs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const run = (mode, plan) => page.evaluate(async ({ mode, plan }) => {
  DB.agentId = 'nps'; DB.tenantId = 't'; localStorage.removeItem('plto_gamify_v2:nps'); Gamify._d = null; Gamify._srv = 'off';
  State.agent = { ...State.agent, email: 'user@example.com', role: 'owner' };
  State.tenant = { ...State.tenant, plan, trial_ends_at: new Date(Date.now() - 40 * 864e5).toISOString(), industry: 'other' };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  State.leads = Array.from({ length: 6 }, (_, i) => ({ id: 'n' + i, name: 'ליד ' + i, phone: '0501234567', stage: first, tags: [], created_at: new Date().toISOString().slice(0, 10) }));
  Gamify.setMode(mode);
  const BAD = /₪\s?\d{2,3}(?:,\d{3})?\s*(\/|ל)?\s*(חודש|שנה)|מחירי? השקה|(?<![א-ת])מנוי(?![א-ת])|שדרוג|שדרג|חבילת (Solo|צוות|סוכנות|בסיס)|חבילה בתשלום|ניסיון חינם|ימי ניסיון|יום ניסיון|נסיון חינמי|תוסף|שיווק AI|\bPRO\b|פרימיום|premium|PayMe|Grow\b|סליקה|לרכישה|תשלום מאובטח|ניסיון החינמי/i;
  const GAME = /XP|דרגה|רמה:|אתגר יומי|אתגר היום|רצף|ימים רצופים|הישג|🏆|חנות/;
  const visibleText = (root) => {
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); let t = ''; let n;
    while ((n = w.nextNode())) {
      const el = n.parentElement; if (!el) continue;
      let ok = true;
      for (let e = el; e && e !== root.parentElement; e = e.parentElement) { const cs = getComputedStyle(e); if (cs.display === 'none' || cs.visibility === 'hidden') { ok = false; break; } }
      if (ok) t += n.nodeValue + ' ';
    }
    return t;
  };
  const ctx = (t, re) => { const r = []; const rx = new RegExp(re.source, re.flags.includes('i') ? 'gi' : 'g'); let x; while ((x = rx.exec(t)) && r.length < 3) r.push(t.slice(Math.max(0, x.index - 30), x.index + 40).replace(/\s+/g, ' ')); return r; };
  const out = [];
  for (const sc of ['dashboard', 'pipeline', 'leads', 'tasks', 'calendar', 'analytics', 'recent-activity', 'tools', 'properties', 'partners', 'pro', 'referral', 'xp-store', 'email', 'settings', 'marketing']) {
    try { App.go(sc); } catch (e) { out.push({ sc, err: String(e) }); continue; }
    await new Promise(r => setTimeout(r, 100));
    const t = visibleText(document.getElementById('app-shell'));
    out.push({ sc, bad: ctx(t, BAD), game: ctx(t, GAME) });
  }
  // חלונות שנפתחים מהכלים והתפריטים
  const modals = [];
  for (const id of ['modal-sales-library', 'modal-add-lead']) {
    const el = document.getElementById(id); if (!el) continue;
    el.classList.remove('hidden'); el.style.display = el.style.display || '';
    const t = visibleText(el); modals.push({ id, bad: ctx(t, BAD) });
    el.classList.add('hidden');
  }
  return { out, modals };
}, { mode, plan });

for (const plan of ['trial', 'cancelled', 'basic']) {
  for (const mode of ['game', 'pro']) {
    const r = await run(mode, plan);
    const bad = r.out.filter(x => x.err || x.bad.length).concat(r.modals.filter(x => x.bad.length));
    check(bad.length === 0, `אין מחירים, שדרוג, מנוי או ניסיון בשום מסך (תוכנית ${plan}, מצב ${mode === 'game' ? 'משחק' : 'מקצועי'})` + (bad.length ? ': ' + JSON.stringify(bad) : ''));
    if (mode === 'pro') {
      const g = r.out.filter(x => x.game.length && x.sc !== 'xp-store');
      check(g.length === 0, `במצב מקצועי אין שפת משחק בשום מסך (תוכנית ${plan})` + (g.length ? ': ' + JSON.stringify(g) : ''));
      const xs = r.out.find(x => x.sc === 'xp-store');
      check(xs && xs.game.every(s => /מצב מקצועי/.test(s) || /חנות ה-XP שייכת למצב משחק/.test(s)), `מסך חנות ה-XP במצב מקצועי מציג רק הסבר על המצב (תוכנית ${plan})`);
    }
  }
}

// שמירה על מקורות סטטיים: שום מחיר או שדרוג בטקסט גלוי של דף הנחיתה, ואין כפתורי הצטרפות לניסיון בקוד הממשק
const landing = readFileSync(new URL('../landing.html', import.meta.url), 'utf8');
const idx = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
check(!/הצטרפו לנסיון חינמי|פתיחת חשבון ניסיון|14 יום ניסיון/.test(idx), 'בקוד הממשק אין נוסחי "נסיון חינמי", "חשבון ניסיון" או "14 יום ניסיון"');
check(!/פיצ.רים PRO|פיצ.ר PRO/.test(idx), 'בקוד הממשק אין תוויות "PRO" למשתמש');
check(!/יש לשדרג לתוסף/.test(idx), 'בקוד הממשק אין הודעת "יש לשדרג לתוסף"');
check(/<section[^>]*id="pricing"[^>]*hidden|<section[^>]*hidden[^>]*id="pricing"/.test(landing), 'אזור התמחור בדף הנחיתה נשאר מוסתר');

check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
