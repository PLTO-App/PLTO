// מצלם צילומי מסך אמיתיים של PLTO Sales לדף הנחיתה, מתוך האפליקציה עצמה (index.html) ולא ממשק מומצא.
// הנתונים בדויים בבירור (שמות נפוצים, טלפונים 050-000000x, בלי אימיילים), והאפליקציה רצה מול Supabase מדומה.
// שימוש: OUT=<תיקייה> [CHART_JS=<נתיב ל-chart.umd.min.js>] node scripts/capture-landing-shots.mjs
// CHART_JS רק לצילום גרפים (בלעדיו ההארנס מדמה את Chart.js והגרף לא מצויר). הקובץ לא נכנס לריפו.
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { startHarness } from './lib/harness.mjs';

const OUT = process.env.OUT;
if (!OUT) { console.error('חסר OUT'); process.exit(1); }
mkdirSync(OUT, { recursive: true });
const CHART_JS = process.env.CHART_JS || null;

// כל מה שרץ בתוך הדף: זרע נתונים ועיצוב נקי (בלי באנר דמו וכפתורי הצפה)
function seed() {
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  State.isDemo = false;
  State.tenant = { id: '00000000-0000-4000-8000-000000000001', name: 'סטודיו אפק', plan: 'trial', industry: 'other', onboarding_completed: true, trial_ends_at: new Date(Date.now() + 25 * 864e5).toISOString() };
  State.agent = { name: 'מאיה', email: 'maya@example.com', initials: 'מ', role: 'מנהלת', rawRole: 'owner' };
  State.stages = [
    { id: 's1', name: 'ליד חדש',    color: '#94A3B8', order: 1 },
    { id: 's2', name: 'יצרנו קשר',  color: '#3B82F6', order: 2 },
    { id: 's3', name: 'הצעת מחיר',  color: '#F59E0B', order: 3 },
    { id: 's4', name: 'משא ומתן',   color: '#8B5CF6', order: 4 },
    { id: 's5', name: 'נסגר ✓',     color: '#10B981', order: 5, is_terminal: true, is_won: true },
  ];
  let n = 0;
  const L = (id, name, stage, score, value, source, last, next, created, extra = {}) => ({
    id, name, phone: '050-000000' + (++n % 10), phone2: '', email: '', source, stage, score, budget_min: 0, budget_max: value,
    desired_area: '', rooms: '', inspiration_url: '', tags: [], notes: '', last_contact: last === null ? null : iso(last), next_followup: next === null ? null : iso(next), created_at: iso(created), ...extra,
  });
  State.leads = [
    L('a', 'דנה כהן',        's2', 78, 18000, 'whatsapp', -6, -2, -20, { notes: 'ביקשה הצעה לשלושה שירותים. לחזור אליה עם הצעה מפורטת.' }),
    L('b', 'יוסי לוי',       's3', 82, 32000, 'referral', -2, 0, -9, { notes: 'קיבל הצעה ביום ראשון. מחכה לאישור של השותף שלו. כדאי לחזור אליו היום.', tags: ['הפניה'] }),
    L('c', 'רונית כץ',    's1', 60, 9000,  'facebook', null, null, 0),
    L('d', 'אבי דור',     's4', 90, 48000, 'website', -1, 2, -14),
    L('e', 'נועה ברק',       's2', 66, 8500,  'instagram', -4, -1, -15),
    L('f', 'עומר גל',    's1', 55, 7000,  'website', null, null, 0),
    L('g', 'מיכל רז',      's3', 71, 22000, 'call', -3, 1, -12),
    L('h', 'תומר שי',    's2', 58, 6500,  'whatsapp', -9, -5, -25),
    L('i', 'ליאת בר',    's4', 85, 41000, 'referral', -2, 0, -18),
    L('j', 'גיל רוזן',       's3', 74, 15500, 'facebook', -5, 3, -10),
    L('k', 'שירה מור',    's5', 80, 27000, 'referral', -7, null, -40),
    L('l', 'אלון נחום',     's5', 77, 12000, 'website', -12, null, -50),
    L('m', 'הילה קורן',      's2', 62, 9800,  'instagram', -1, 4, -6),
    L('n', 'רן סגל',         's1', 52, 5500,  'whatsapp', null, null, -1),
  ];
  State.tasks = [
    { id: 't1', title: 'לשלוח הצעה מעודכנת ליוסי לוי', type: 'whatsapp', lead_id: 'b', due: iso(0), done: false, priority: 'high', notes: '' },
    { id: 't2', title: 'לתאם שיחה עם ליאת בר', type: 'call', lead_id: 'i', due: iso(0), done: false, priority: 'medium', notes: '' },
    { id: 't3', title: 'לחזור לדנה כהן עם פירוט שירותים', type: 'call', lead_id: 'a', due: iso(1), done: false, priority: 'medium', notes: '' },
  ];
  State.activities = [
    { id: 'ac1', lead_id: 'b', type: 'call', content: 'שיחה קצרה. הוא אוהב את ההצעה ומחכה לאישור של השותף.', created_at: iso(-2) },
    { id: 'ac2', lead_id: 'b', type: 'whatsapp', content: 'נשלחה הצעת המחיר ב-WhatsApp.', created_at: iso(-4) },
    { id: 'ac3', lead_id: 'b', type: 'stage_change', content: 'עבר לשלב: הצעת מחיר', created_at: iso(-4) },
    { id: 'ac4', lead_id: 'b', type: 'call', content: 'שיחת היכרות. מחפש פתרון עד סוף החודש.', created_at: iso(-9) },
  ];
  State.lostLeads = [];
  document.head.appendChild(Object.assign(document.createElement('style'), {
    textContent: '#demo-banner,#support-fab-btn,#a11y-fab,#fab-btn,.support-fab,[data-a11y-btn],#toast-container,.toast,.act-ticker-strip{display:none!important}',
  }));
  // הסרגל הצדי נבנה בכניסה, ולכן מעדכנים אותו לנתוני הדוגמה
  const setTxt = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  setTxt('sidebar-tenant-name', State.tenant.name); setTxt('sidebar-agent-name', State.agent.name);
  setTxt('sidebar-agent-initials', State.agent.initials); setTxt('sidebar-agent-role', State.agent.role);
}

async function settle(page, ms = 1000) {
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  await page.waitForTimeout(ms);
}
async function shot(page, name) {
  await settle(page);
  await page.screenshot({ path: join(OUT, name + '.png') });
  console.log('✓', name);
}

// ── מובייל 390×844 @2x ──
{
  const h = await startHarness({ scale: 2, viewport: { width: 390, height: 844 }, chartJs: CHART_JS, fonts: true });
  const { page, errors } = h;
  await page.evaluate(seed);

  await page.evaluate(() => App.go('dashboard'));
  await shot(page, 'm1-today');

  await page.evaluate(() => App.go('pipeline'));
  await page.waitForTimeout(600);
  await page.evaluate(() => Pipeline.setTab('s2'));
  await shot(page, 'm2-pipeline');

  await page.evaluate(() => App.go('lead-detail', { currentLeadId: 'b' }));
  await page.waitForTimeout(500);
  await shot(page, 'm3-lead-info');
  await page.evaluate(() => { const b = [...document.querySelectorAll('.tab-btn')].find(x => x.textContent.includes('פעילות')); if (b) b.click(); });
  await shot(page, 'm3-lead-activity');

  await page.evaluate(() => { App.go('dashboard'); SmartWA.open('b', 'whatsapp'); });
  await shot(page, 'm4-messages');
  await page.evaluate(() => { closeModal('modal-smart-wa'); });

  await page.evaluate(() => App.go('analytics'));
  await page.waitForTimeout(1500);
  await shot(page, 'm5-analytics');

  await page.evaluate(() => {
    App.go('dashboard');
    LeadImport.open();
    LeadImport._headers = ['שם מלא', 'טלפון', 'מקור'];
    LeadImport._rows = [['נועם אביב', '050-0000001', 'פייסבוק'], ['הדס לביא', '050-0000002', 'אתר'], ['איתי רגב', '050-0000003', 'הפניה'], ['טל שחר', '050-0000004', 'וואטסאפ']];
    LeadImport._autoMap();
    LeadImport._step = 2;
    LeadImport._render();
  });
  await shot(page, 'm6-import-map');
  await page.evaluate(() => LeadImport.toPreview());
  await shot(page, 'm6-import-preview');

  console.log('שגיאות מובייל:', errors);
  await h.close();
}

// ── דסקטופ רחב 1920×1080 @2x: פייפליין (חמש עמודות בלי חיתוך שמות) ואנליטיקס ──
{
  const h = await startHarness({ scale: 2, viewport: { width: 1920, height: 1200 }, chartJs: CHART_JS, fonts: true });
  const { page, errors } = h;
  await page.evaluate(seed);

  await page.evaluate(() => App.go('pipeline'));
  await page.waitForTimeout(800);
  await shot(page, 'd1-pipeline');

  await page.evaluate(() => App.go('analytics'));
  await page.waitForTimeout(1500);
  await shot(page, 'd3-analytics');

  console.log('שגיאות דסקטופ רחב:', errors);
  await h.close();
}

// ── דסקטופ רגיל 1280×800 @2x: היום, כרטיס ליד וייבוא ──
{
  const h = await startHarness({ scale: 2, viewport: { width: 1280, height: 800 }, chartJs: CHART_JS, fonts: true });
  const { page, errors } = h;
  await page.evaluate(seed);

  await page.evaluate(() => App.go('dashboard'));
  await shot(page, 'd2-today');

  await page.evaluate(() => App.go('lead-detail', { currentLeadId: 'b' }));
  await page.waitForTimeout(500);
  await page.evaluate(() => { const b = [...document.querySelectorAll('.tab-btn')].find(x => x.textContent.includes('פעילות')); if (b) b.click(); });
  await shot(page, 'd4-lead');

  await page.evaluate(() => {
    App.go('dashboard');
    LeadImport.open();
    LeadImport._headers = ['שם מלא', 'טלפון', 'מקור'];
    LeadImport._rows = [['נועם אביב', '050-0000001', 'פייסבוק'], ['הדס לביא', '050-0000002', 'אתר'], ['איתי רגב', '050-0000003', 'הפניה'], ['טל שחר', '050-0000004', 'וואטסאפ']];
    LeadImport._autoMap();
    LeadImport._step = 2;
    LeadImport._render();
  });
  await shot(page, 'd5-import-map');

  console.log('שגיאות דסקטופ:', errors);
  await h.close();
}
