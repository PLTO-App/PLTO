// בדיקת מחולל הודעות ה-WhatsApp מתבניות (MsgTemplates + SmartWA): בלי קריאה ל-AI, מילוי פרטים,
// ניסוח ניטרלי, קלט לא מהימן, מסלול ההסכמה ותצוגה ב-390px. רצה עם Supabase מדומה.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const lib = await page.evaluate(() => {
  const invokes = [];
  sbClient.functions.invoke = (fn) => { invokes.push(fn); return Promise.resolve({ data: {}, error: null }); };
  window.__invokes = invokes;
  State.agent = { ...(State.agent || {}), name: 'דנה כהן' };
  State.tenant = { ...(State.tenant || {}), name: 'נכסי השרון' };
  const out = { bad: [], empty: [], total: 0 };
  // ניסוח מגדרי, מקומות מילוי שלא הוחלפו ותחילית שנצמדה ל-{about}
  const banned = /\[|\]|undefined|null|\/ת|\/י|שולח |שולחת |אתה |את\/ה|מעוניינ|בטוח |אלייך|בהחיפוש|בהפרויקט|בהפנייה/;
  for (const ind of ['realestate', 'interior', 'realestate_lawyer', 'other']) {
    localStorage.setItem('plto_industry', ind);
    for (const p of MsgTemplates.PURPOSES) for (const s of MsgTemplates.STYLES) {
      for (let v = 0; v < MsgTemplates.count(p.id, s.id); v++) {
        for (const lead of [{ name: 'יוסי לוי', desired_area: 'רעננה' }, { name: '' }, { name: '0501234567' }]) {
          const t = MsgTemplates.build({ purpose: p.id, style: s.id, variant: v, lead });
          out.total++;
          if (!t) out.empty.push(`${ind}/${p.id}/${s.id}/${v}`);
          if (banned.test(t) || /\n\n\n/.test(t)) out.bad.push(`${ind}/${p.id}/${s.id}/${v}: ${t}`);
        }
      }
    }
  }
  localStorage.setItem('plto_industry', 'realestate');
  out.personal = MsgTemplates.build({ purpose: 'intro', style: 'warm', lead: { name: 'יוסי לוי', desired_area: 'רעננה' } });
  out.noName = MsgTemplates.build({ purpose: 'followup', style: 'short', lead: { name: '0501234567' } });
  State.tenant.name = 'PLTO';
  out.latinBiz = MsgTemplates.build({ purpose: 'intro', style: 'pro', lead: { name: 'רון' } });
  State.tenant.name = 'נכסי השרון';
  localStorage.setItem('plto_industry', 'other');
  out.otherRef = MsgTemplates.build({ purpose: 'cold_referral', style: 'pro', variant: 1, lead: { name: 'רון' } });
  localStorage.setItem('plto_industry', 'realestate');
  out.variants = new Set([0, 1, 2].map(v => MsgTemplates.build({ purpose: 'proposal', style: 'warm', variant: v, lead: { name: 'רון' } }))).size;
  out.unknown = MsgTemplates.build({ purpose: 'nope', style: 'nope', lead: { name: 'רון' } });
  out.email = MsgTemplates.build({ purpose: 'intro', channel: 'email', lead: {} });
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  out.sugNew  = MsgTemplates.suggest({ stage: first, last_contact: null });
  out.sugCold = MsgTemplates.suggest({ stage: first, last_contact: iso(-30) });
  out.sugWarm = MsgTemplates.suggest({ stage: first, last_contact: iso(-2) });
  out.sugWon  = MsgTemplates.suggest({ stage: wonStageId(), last_contact: iso(-2) });
  return out;
});
check(lib.total > 400 && lib.empty.length === 0, `כל ${lib.total} הצירופים (תחום, מטרה, סגנון, גרסה, ליד) מחזירים טקסט`);
check(lib.bad.length === 0, 'אין ניסוח מגדרי, מקום מילוי שלא הוחלף או תחילית שבורה' + (lib.bad.length ? '\n   ' + lib.bad.slice(0, 5).join('\n   ') : ''));
check(/^היי יוסי/.test(lib.personal) && /כאן דנה מנכסי השרון\./.test(lib.personal) && /באזור רעננה/.test(lib.personal), 'שם פרטי, שם המשתמש, שם העסק ואזור נכנסים להודעה');
check(/^היי, /.test(lib.noName) && !/050/.test(lib.noName), 'מספר שנשמר כשם לא נכנס לפנייה');
check(/מ-PLTO/.test(lib.latinBiz) && /^שלום רון/.test(lib.latinBiz), 'שם עסק לועזי מקבל מקף, וסגנון מקצועי פותח ב"שלום"');
check(/להמלצה/.test(lib.otherRef) && !/לקנות או למכור/.test(lib.otherRef), 'בעסק כללי אין ניסוח נדל"ן');
check(lib.variants === 2, '"גרסה אחרת" מסתובבת בין הגרסאות');
check(!!lib.unknown && lib.email === '', 'מטרה לא מוכרת נופלת לברירת מחדל, וערוץ שלא מומש מחזיר ריק');
check(lib.sugNew === 'intro' && lib.sugCold === 'cold_referral' && lib.sugWarm === 'followup' && lib.sugWon === 'cold_referral', 'מטרה מומלצת לפי מצב הליד');

const ui = await page.evaluate(async () => {
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  const opened = []; window.open = (u) => { opened.push(u); return null; };
  const xss = '<img src=x onerror="window.__xss=1"> יוסי';
  State.leads = [
    { id: 'known', name: xss, phone: '050-1234567', stage: first, last_contact: iso(-2), tags: [], notes: '' },
    { id: 'fresh', name: 'מיכל', phone: '0527654321', stage: first, last_contact: null, tags: [], notes: '' },
  ];
  const out = {};
  SmartWA.open('known');
  const ta = document.getElementById('swa-text');
  out.modalOpen = !document.getElementById('modal-smart-wa').classList.contains('hidden');
  out.text0 = ta.value;
  out.imgs = document.querySelectorAll('#smart-wa-content img').length;
  out.activePurpose = document.querySelector('#smart-wa-content .swa-chip.active')?.textContent;
  SmartWA.pick('purpose', 'meeting');
  out.meeting = document.getElementById('swa-text').value;
  SmartWA.pick('style', 'short');
  out.short = document.getElementById('swa-text').value;
  out.savedStyle = localStorage.getItem('plto_wa_style');
  SmartWA.pick('purpose', "x');alert(1);//");
  out.afterBadPick = document.getElementById('swa-text').value === out.short;
  const before = document.getElementById('swa-text').value;
  SmartWA.another();
  out.anotherChanged = document.getElementById('swa-text').value !== before;
  document.getElementById('swa-text').value = 'נוסח שנערך ידנית';
  SmartWA.send();
  out.sentKnown = opened[0];
  const sheet = document.querySelector('#modal-smart-wa .modal-sheet');
  out.overflow = sheet.scrollWidth - sheet.clientWidth;
  out.docOverflow = document.documentElement.scrollWidth - window.innerWidth;
  out.chipHeights = [...document.querySelectorAll('#smart-wa-content .swa-chip')].map(b => b.getBoundingClientRect().height);
  closeModal('modal-smart-wa');

  SmartWA.open('fresh');
  out.freshPurpose = SmartWA._purpose;
  SmartWA.send();
  out.consentOpen = !document.getElementById('modal-wa-consent').classList.contains('hidden');
  out.openedBeforeConsent = opened.length;
  LeadDetail.confirmDirectWA();
  out.sentFresh = opened[1];
  closeModal('modal-smart-wa');
  // כניסה מהכרטיס בלי הודעה לא נושאת טקסט ישן
  LeadDetail.openDirectWA('fresh');
  LeadDetail.confirmDirectWA();
  out.directNoText = opened[2];
  LeadDetail._quickReply('fresh', 'closing');
  out.quick = opened[3];
  document.getElementById('wa-client-name').value = 'שירה';
  Tools.waTemplate('cold_referral');
  out.tools = document.getElementById('wa-preview').textContent;
  out.xss = window.__xss === 1;
  out.invokes = window.__invokes.slice();
  return out;
});
check(ui.modalOpen && /^היי <img/.test(ui.text0) && ui.imgs === 0 && !ui.xss, 'שם ליד עם HTML נכנס כטקסט בלבד, בלי הזרקה');
check(/פולואפ|מעקב/.test(ui.activePurpose || ''), 'ליד עם קשר אחרון לפני יומיים נפתח על "מעקב"');
check(/להיפגש|פגישה|לדבר/.test(ui.meeting) && ui.short.length < ui.meeting.length, 'בחירת מטרה וסגנון מחליפה את הנוסח');
check(ui.savedStyle === 'short', 'הסגנון שנבחר נשמר לפעם הבאה');
check(ui.afterBadPick, 'ערך מטרה לא מוכר נדחה');
check(ui.anotherChanged, '"גרסה אחרת" מחליפה נוסח בחלון');
check(ui.sentKnown === 'https://wa.me/972501234567?text=' + encodeURIComponent('נוסח שנערך ידנית'), 'שליחה לליד מוכר פותחת WhatsApp עם הנוסח הערוך');
check(ui.freshPurpose === 'intro' && ui.consentOpen && ui.openedBeforeConsent === 1, 'ליד בלי קשר קודם עובר קודם דרך אישור ההסכמה');
check(/^https:\/\/wa\.me\/972527654321\?text=/.test(ui.sentFresh || '') && decodeURIComponent(ui.sentFresh.split('text=')[1]).startsWith('היי מיכל'), 'אחרי האישור נפתח WhatsApp עם ההודעה');
check(ui.directNoText === 'https://wa.me/972527654321', 'כפתור WhatsApp ישיר לא גורר טקסט מהחלון הקודם');
check(/^https:\/\/wa\.me\/972527654321\?text=/.test(ui.quick || '') && /תודה על הפגישה/.test(decodeURIComponent(ui.quick)), 'תשובות מהירות בכרטיס עובדות דרך אותו מנוע');
check(/^היי שירה/.test(ui.tools) && /מה שלומך/.test(ui.tools), 'כרטיס התבניות במסך הכלים עובד דרך אותו מנוע');
check(ui.overflow <= 0 && ui.docOverflow <= 0, 'אין גלילה אופקית בחלון ב-390px');
check(ui.chipHeights.length === 9 && ui.chipHeights.every(h => h >= 44), 'כל כפתורי הבחירה בגובה 44px לפחות');
check(ui.invokes.length === 0, 'אין אף קריאה ל-Edge Function (ובפרט ל-ai-proxy)');
check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));

await page.evaluate(() => { SmartWA.open('known'); });
await page.screenshot({ path: process.env.SHOT || '/dev/null' }).catch(() => {});
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
