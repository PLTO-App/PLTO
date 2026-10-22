// בדיקת מחוללי התוכן מתבניות (MsgTemplates + SmartWA): WhatsApp, אימייל ותסריט שיחה.
// בלי קריאה ל-AI, ניסוחים שסוכמו מילה במילה, ערכים חסרים, ניסוח ניטרלי, קלט לא מהימן, מסלול ההסכמה,
// mailto ו-tel, ותצוגה ב-390px ובדסקטופ. רצה עם Supabase מדומה.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };
const J = (...l) => l.join('\n');

const lib = await page.evaluate(() => {
  const invokes = [];
  sbClient.functions.invoke = (fn) => { invokes.push(fn); return Promise.resolve({ data: {}, error: null }); };
  window.__invokes = invokes;
  State.agent = { ...(State.agent || {}), name: 'דנה כהן' };
  State.tenant = { ...(State.tenant || {}), name: 'נכסי השרון' };
  const out = { bad: [], empty: [], total: 0, counts: {} };
  // ניסוח מגדרי, משתנה שלא נפתר, רווחים שבורים ותחילית שנצמדה ל-about
  const banned = /\{\{|\}\}|\[\[|\]\]|\[|\]|undefined|null|\/ת|\/י|את\/ה|שולח |שולחת |אתה |שתרצה|מדבר|אלייך|בהחיפוש|בהפרויקט|בהפנייה| ,| \.|^ | $/m;
  const leads = [{ name: 'יוסי לוי', desired_area: 'רעננה' }, { name: '' }, { name: '0501234567' }];
  for (const ind of ['realestate', 'interior', 'realestate_lawyer', 'other']) {
    localStorage.setItem('plto_industry', ind);
    for (const ch of MsgTemplates.CHANNELS) {
      out.counts[ch.id] = MsgTemplates.scenarios(ch.id).length;
      for (const sc of MsgTemplates.scenarios(ch.id)) for (const st of MsgTemplates.styles(ch.id, sc.id)) {
        for (let v = 0; v < MsgTemplates.count(ch.id, sc.id, st); v++) for (const lead of leads) for (const service of ['', 'ייעוץ ראשוני']) {
          const t = MsgTemplates.build({ channel: ch.id, purpose: sc.id, style: st, variant: v, lead, service });
          out.total++;
          if (!t) out.empty.push(`${ind}/${ch.id}/${sc.id}/${st}/${v}`);
          if (banned.test(t) || /\n\n\n/.test(t)) out.bad.push(`${ind}/${ch.id}/${sc.id}/${st}/${v}: ${t}`);
        }
      }
    }
  }
  localStorage.setItem('plto_industry', 'other');
  const full = { name: 'יוסי לוי' };
  const b = (channel, purpose, extra = {}) => MsgTemplates.build({ channel, purpose, lead: full, service: 'ייעוץ ראשוני', ...extra });
  out.t = {
    wa1: b('whatsapp', 'intro'), wa2: b('whatsapp', 'followup'), wa3: b('whatsapp', 'proposal'),
    em1: b('email', 'intro'), em2: b('email', 'quote'), em3: b('email', 'proposal'),
    sc1: b('script', 'intro'), sc2: b('script', 'needs'), sc3: b('script', 'objection'),
  };
  // ערכים חסרים: בלי שירות, בלי שם, בלי שם נציג ועסק
  out.noService = { wa1: b('whatsapp', 'intro', { service: '' }), wa2: b('whatsapp', 'followup', { service: '' }), wa3: b('whatsapp', 'proposal', { service: '' }),
                    em1: b('email', 'intro', { service: '' }), em2: b('email', 'quote', { service: '' }), sc1: b('script', 'intro', { service: '' }) };
  State.agent = { ...State.agent, name: '' }; State.tenant = { ...State.tenant, name: '' };
  out.noWho = { em1: b('email', 'intro', { lead: { name: '' }, service: '' }), sc1: b('script', 'intro', { lead: { name: '' }, service: '' }) };
  State.agent = { ...State.agent, name: 'דנה כהן' }; State.tenant = { ...State.tenant, name: 'PLTO' };
  out.latin = b('script', 'intro');
  State.tenant = { ...State.tenant, name: 'נכסי השרון' };
  out.unknown = MsgTemplates.build({ channel: 'whatsapp', purpose: 'nope', style: 'nope', lead: full });
  out.badChannel = MsgTemplates.build({ channel: 'nope', purpose: 'intro', lead: full });
  out.variants = new Set([0, 1].map(v => MsgTemplates.build({ channel: 'whatsapp', purpose: 'closing', style: 'warm', variant: v, lead: full }))).size;
  out.usesService = [MsgTemplates.usesService('whatsapp', 'intro', 'warm'), MsgTemplates.usesService('whatsapp', 'closing', 'warm'), MsgTemplates.usesService('script', 'objection', 'std')];
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  const sug = (ch, lead) => MsgTemplates.suggest(lead, ch);
  out.sug = [sug('whatsapp', { stage: first, last_contact: null }), sug('whatsapp', { stage: first, last_contact: iso(-30) }),
    sug('whatsapp', { stage: first, last_contact: iso(-2) }), sug('whatsapp', { stage: wonStageId(), last_contact: iso(-2) }),
    sug('email', { stage: first }), sug('script', { stage: first, last_contact: null }), sug('script', { stage: first, last_contact: iso(-2) })];
  return out;
});
check(lib.counts.whatsapp === 6 && lib.counts.email === 3 && lib.counts.script === 3, 'WhatsApp 6 תרחישים (3 שסוכמו ועוד 3 קיימים), אימייל 3, תסריט 3');
check(lib.total > 800 && lib.empty.length === 0, `כל ${lib.total} הצירופים (תחום, ערוץ, תרחיש, סגנון, גרסה, ליד, שירות) מחזירים טקסט`);
check(lib.bad.length === 0, 'אין משתנה לא פתור, ניסוח מגדרי, תחילית שבורה או רווח מיותר' + (lib.bad.length ? '\n   ' + lib.bad.slice(0, 4).join('\n   ') : ''));

const T = lib.t;
check(T.wa1 === J('היי יוסי, מה שלומך? 🙂', 'ראיתי שהשארת פרטים לגבי ייעוץ ראשוני ורציתי להבין קצת יותר מה חשוב לך, כדי שאוכל לכוון אותך לפתרון המתאים.', 'נוח לך שנדבר כאן או בשיחה קצרה בטלפון?'), 'WhatsApp 1: יצירת קשר ראשוני, נוסח שסוכם');
check(T.wa2 === J('היי יוסי, מה נשמע?', 'רציתי לחזור אליך לגבי ייעוץ ראשוני ולבדוק אם זה עדיין רלוונטי עבורך.', 'אם כן, אשמח לעזור לך להבין מה יכול להתאים לך 🙂'), 'WhatsApp 2: פולואפ בלי תשובה, נוסח שסוכם');
check(T.wa3 === J('היי יוסי, רציתי לבדוק אם יצא לך לעבור על ההצעה ששלחתי לגבי ייעוץ ראשוני.', 'חשוב לי להבין אם היא מתאימה למה שחיפשת, ואם יש משהו שכדאי שנחדד או נבדוק יחד.', 'מה דעתך?'), 'WhatsApp 3: מעקב אחרי הצעה, נוסח שסוכם');
check(T.em1 === J('נושא: בהמשך לפנייתך בנושא ייעוץ ראשוני', '', 'שלום יוסי,', '', 'בהמשך לפנייתך בנושא ייעוץ ראשוני, אשמח להבין קצת יותר על הצורך שלך ולבדוק כיצד נוכל לעזור.', '', 'המטרה היא להתאים לך פתרון רלוונטי, בהתאם למה שחשוב לך ולמה שמתאים לך.', '', 'אפשר להשיב למייל הזה עם כמה פרטים נוספים, או לתאם שיחה קצרה בזמן שנוח לך.', '', 'אשמח לשמוע ממך,', 'נכסי השרון'), 'אימייל 1: היכרות, נוסח שסוכם');
check(T.em2 === J('נושא: הצעת מחיר עבור ייעוץ ראשוני', '', 'שלום יוסי,', '', 'מצורפת הצעת המחיר עבור ייעוץ ראשוני, בהתאם למה שדיברנו עליו.', '', 'ההצעה מפרטת את השירות ואת התנאים הרלוונטיים. כדאי לעבור עליה בנחת, ואם יש שאלה או נקודה שכדאי לחדד, אשמח לעבור עליה יחד איתך.', '', 'אם הכול ברור ומתאים, נוכל לתאם את הצעד הבא ולהתקדם.', '', 'בברכה,', 'נכסי השרון'), 'אימייל 2: שליחת הצעה, נוסח שסוכם');
check(T.em3 === J('נושא: המשך לשיחה שלנו בנושא ייעוץ ראשוני', '', 'שלום יוסי,', '', 'רציתי לבדוק אם הספקת לעבור על הצעת המחיר ששלחתי בנושא ייעוץ ראשוני.', '', 'אשמח לדעת אם ההצעה עונה על הצרכים שלך, ואם נותרו שאלות או דברים שחשוב לך לברר לפני קבלת החלטה.', '', 'אפשר להשיב כאן למייל, ואשמח לעזור.', '', 'בברכה,', 'נכסי השרון'), 'אימייל 3: מעקב אחרי הצעה, נוסח שסוכם');
check(T.sc1 === J('פתיחה:', '"היי יוסי, כאן דנה מנכסי השרון. השארת פרטים לגבי ייעוץ ראשוני, ורציתי לדבר איתך כמה דקות כדי להבין מה בדיוק חשוב לך. זה זמן נוח?"', '', 'שאלות להמשך:', '- מה היית רוצה להשיג או לפתור?', '- מה הכי חשוב לך כשבוחרים שירות כזה?', '- האם כבר בדקת פתרונות נוספים?', '', 'מטרת השיחה: להבין את הצורך ולקבוע צעד המשך מוסכם, בלי למהר למכור לפני שמבינים את הלקוח.'), 'תסריט 1: שיחת היכרות, נוסח שסוכם');
check(T.sc2 === J('פתיחה:', '"כדי שאוכל להציע לך משהו שבאמת מתאים, אשמח להבין קצת יותר את המצב שלך ומה חשוב לך."', '', 'שאלות להמשך:', '- מה המצב כיום ומה היית רוצה לשנות?', '- מה האתגר המרכזי מבחינתך?', '- מה יגרום לך להרגיש שהפתרון הצליח?', '- האם יש מגבלת תקציב או לוח זמנים שחשוב לקחת בחשבון?', '', 'מעבר להצעה:', '"לפי מה שסיפרת, נראה שכדאי לבדוק את האפשרות המתאימה ביותר. אסביר לך איך זה יכול לעזור, ונראה יחד אם זה מתאים."'), 'תסריט 2: בירור צרכים, נוסח שסוכם (הפתרון נופל לטקסט חלופי כי אין לו מקור)');
check(T.sc3 === J('הלקוח: "זה יקר לי."', '', 'תגובה מוצעת:', '"מובן. כדי שאוכל לבדוק אם יש דרך להתאים את ההצעה, אפשר לשאול מה בעיקר מרגיש לך גבוה במחיר? האם מדובר בתקציב שתכננת, או בהשוואה להצעה אחרת?"', '', 'אם הלקוח משווה להצעה אחרת:', '"מובן. כדאי לבדוק גם מה כל הצעה כוללת, כדי שנשווה בין דברים דומים. מה חשוב לך במיוחד לקבל במסגרת השירות?"', '', 'מטרת השיחה: להבין את ההתנגדות האמיתית לפני שמציעים שינוי במחיר או בתנאים. אין להבטיח הנחות שלא אושרו.'), 'תסריט 3: התנגדות למחיר, נוסח שסוכם');

const NS = lib.noService;
check(NS.wa1.startsWith('היי יוסי, מה שלומך? 🙂\nראיתי שהשארת פרטים ורציתי להבין') && NS.wa2.includes('לגבי הפנייה שלך ולבדוק') && NS.wa3.startsWith('היי יוסי, רציתי לבדוק אם יצא לך לעבור על ההצעה ששלחתי.\n'), 'בלי שירות WhatsApp נשאר תקין וטבעי (קטע אופציונלי נשמט, או ניסוח חלופי)');
check(NS.em1.startsWith('נושא: בהמשך לפנייתך\n\nשלום יוסי,\n\nבהמשך לפנייתך, אשמח') && NS.em2.startsWith('נושא: הצעת מחיר\n') && NS.em2.includes('מצורפת הצעת המחיר, בהתאם'), 'בלי שירות האימייל נשאר תקין, גם בנושא');
check(NS.sc1.includes('"היי יוסי, כאן דנה מנכסי השרון. השארת פרטים, ורציתי'), 'בלי שירות התסריט נשאר תקין');
check(lib.noWho.em1.startsWith('נושא: בהמשך לפנייתך\n\nשלום,\n') && lib.noWho.em1.endsWith('אשמח לשמוע ממך,') && lib.noWho.sc1.includes('"היי, השארת פרטים'), 'בלי שם ליד, שם נציג ועסק: אין משתנה, סוגריים או שורה ריקה, והחתימה נשמטת');
check(/כאן דנה מ-PLTO\./.test(lib.latin), 'שם עסק לועזי מקבל מקף');
check(!!lib.unknown && lib.badChannel === '', 'תרחיש לא מוכר נופל לברירת מחדל, וערוץ לא מוכר מחזיר ריק');
check(lib.variants === 2, '"גרסה אחרת" מסתובבת בין הגרסאות');
check(lib.usesService[0] === true && lib.usesService[1] === false && lib.usesService[2] === false, 'שדה השירות מוצג רק לתבניות שמשתמשות בו');
check(JSON.stringify(lib.sug) === JSON.stringify(['intro', 'cold_referral', 'followup', 'cold_referral', 'intro', 'intro', 'needs']), 'תרחיש מומלץ לפי קשר אחרון ולקוח קיים בלבד, בלי הסקה משם השלב');

const ui = await page.evaluate(async () => {
  const iso = n => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  const opened = []; window.open = (u) => { opened.push(u); return null; };
  const mail = []; document.addEventListener('click', e => { const a = e.target.closest?.('a[href^="mailto:"]'); if (a) { mail.push(a.getAttribute('href')); e.preventDefault(); } }, true);
  const xss = '<img src=x onerror="window.__xss=1"> יוסי';
  State.leads = [
    { id: 'known', name: xss, phone: '050-1234567', email: 'yossi@example.com', stage: first, last_contact: iso(-2), tags: [], notes: '' },
    { id: 'fresh', name: 'מיכל', phone: '0527654321', email: '', stage: first, last_contact: null, tags: [], notes: '' },
  ];
  const toasts = []; const origToast = window.toast; window.toast = (m, t) => { toasts.push(m); };
  const out = {};
  const active = () => [...document.querySelectorAll('#smart-wa-content .swa-chip.active')].map(b => b.textContent.trim());
  const val = () => document.getElementById('swa-text').value;

  SmartWA.open('known');
  out.modalOpen = !document.getElementById('modal-smart-wa').classList.contains('hidden');
  out.title = document.querySelector('#modal-smart-wa .modal-header span')?.textContent;
  out.active0 = active();
  out.text0 = val();
  out.imgs = document.querySelectorAll('#smart-wa-content img').length;
  out.channels = [...document.querySelectorAll('.swa-channels .swa-chip')].map(b => b.textContent.trim());
  out.hasService = !!document.getElementById('swa-service');
  const svc = document.getElementById('swa-service');
  svc.value = 'ליווי בקניית דירה'; svc.dispatchEvent(new Event('input', { bubbles: true }));
  out.withService = val();
  // מעבר ערוץ שומר שירות, ובוחר תרחיש מומלץ לערוץ
  SmartWA.pick('channel', 'email');
  out.email = { text: val(), active: active(), svc: document.getElementById('swa-service')?.value, styles: document.querySelectorAll('#smart-wa-content .swa-chip').length };
  SmartWA.mail();
  out.mailHref = mail[0];
  SmartWA.pick('purpose', 'quote');
  out.quoteNote = document.querySelector('.swa-note').textContent;
  document.getElementById('swa-text').value = 'נושא: נושא ערוך\n\nגוף ערוך\nשורה שנייה';
  SmartWA.mail();
  out.mailEdited = mail[1];
  SmartWA.pick('channel', 'script');
  out.script = { text: val(), active: active(), tel: document.querySelector('#smart-wa-content a[href^="tel:"]')?.getAttribute('href'), spam: !!document.querySelector('#smart-wa-content .spam-law-notice') };
  SmartWA.pick('purpose', 'objection');
  out.objection = val().startsWith('הלקוח: "זה יקר לי."');
  SmartWA.pick('channel', 'whatsapp');
  out.waBack = { text: val(), active: active() };
  SmartWA.pick('purpose', 'meeting'); SmartWA.pick('style', 'short');
  out.savedStyle = localStorage.getItem('plto_wa_style');
  SmartWA.pick('channel', 'email'); SmartWA.pick('channel', 'whatsapp');
  out.styleAfterSwitch = active();
  SmartWA.pick('purpose', 'meeting');
  SmartWA.pick('purpose', "x');alert(1);//"); SmartWA.pick('style', 'nope'); SmartWA.pick('channel', 'nope');
  out.badPicksIgnored = SmartWA._channel === 'whatsapp' && SmartWA._purpose === 'meeting' && SmartWA._style === 'short';
  const before = val(); SmartWA.another();
  out.anotherChanged = val() !== before;
  document.getElementById('swa-text').value = 'נוסח שנערך ידנית';
  SmartWA.send();
  out.sentKnown = opened[0];
  // 390px
  const sheet = document.querySelector('#modal-smart-wa .modal-sheet');
  out.m390 = { sheet: sheet.scrollWidth - sheet.clientWidth, doc: document.documentElement.scrollWidth - window.innerWidth };
  SmartWA.pick('channel', 'script');
  out.m390s = { sheet: sheet.scrollWidth - sheet.clientWidth, doc: document.documentElement.scrollWidth - window.innerWidth };
  out.chipHeights = [...document.querySelectorAll('#smart-wa-content .swa-chip')].map(b => b.getBoundingClientRect().height);
  out.actionHeights = [...document.querySelectorAll('#smart-wa-content .btn')].map(b => b.getBoundingClientRect().height);
  closeModal('modal-smart-wa');

  // ליד בלי קשר קודם ובלי אימייל
  SmartWA.open('fresh');
  out.freshPurpose = SmartWA._purpose;
  SmartWA.send();
  out.consentOpen = !document.getElementById('modal-wa-consent').classList.contains('hidden');
  out.openedBeforeConsent = opened.length;
  LeadDetail.confirmDirectWA();
  out.sentFresh = opened[1];
  closeModal('modal-wa-consent');
  SmartWA.pick('channel', 'email');
  const t0 = toasts.length; SmartWA.mail();
  out.noEmailToast = toasts.slice(t0).some(m => /אין כתובת אימייל/.test(m)) && mail.length === 2;
  closeModal('modal-smart-wa');
  SmartWA.open('fresh', 'script');
  out.scriptOpen = SmartWA._channel === 'script' && SmartWA._purpose === 'intro';
  closeModal('modal-smart-wa');

  LeadDetail.openDirectWA('fresh');
  LeadDetail.confirmDirectWA();
  out.directNoText = opened[2];
  LeadDetail._quickReply('fresh', 'closing');
  out.quick = opened[3];
  document.getElementById('wa-client-name').value = 'שירה';
  Tools.waTemplate('cold_referral');
  out.tools = document.getElementById('wa-preview').textContent;

  // כניסה מתפריט "עוד"
  LeadDetail.more('known', document.body);
  out.menu = [...document.querySelectorAll('.as-item')].map(b => b.textContent.trim()).filter(t => /הודעת WhatsApp מוכנה|אימייל מוכן|תסריט שיחה/.test(t));
  window.toast = origToast;
  out.xss = window.__xss === 1;
  out.invokes = window.__invokes.slice();
  return out;
});
check(ui.modalOpen && /הודעות ותסריטים מוכנים/.test(ui.title) && ui.channels.length === 3, 'החלון נפתח עם שלושה ערוצים בתוך כרטיס הליד');
check(/^היי <img/.test(ui.text0) === false || ui.imgs === 0, 'שם ליד עם HTML לא נוצר כאלמנט');
check(ui.imgs === 0 && !ui.xss, 'שם ליד עם HTML נכנס כטקסט בלבד, בלי הזרקה');
check(ui.hasService && ui.withService.includes('לגבי ליווי בקניית דירה'), 'שדה השירות מעדכן את הנוסח');
check(ui.active0.some(t => /מעקב|פולואפ/.test(t)), 'ליד עם קשר אחרון לפני יומיים נפתח על פולואפ');
check(ui.email.active.some(t => /היכרות/.test(t)) && ui.email.text.startsWith('נושא: בהמשך לפנייתך בנושא ליווי בקניית דירה') && ui.email.svc === 'ליווי בקניית דירה', 'מעבר לאימייל שומר את השירות ובוחר את תרחיש ההיכרות');
check(ui.mailHref === 'mailto:yossi@example.com?subject=' + encodeURIComponent('בהמשך לפנייתך בנושא ליווי בקניית דירה') + '&body=' + encodeURIComponent(ui.email.text.split('\n').slice(2).join('\n').trim().replace(/\n/g, '\r\n')), 'פתיחה באימייל: כתובת, נושא וגוף נפרדים ותקינים');
check(/מצורפת ידנית/.test(ui.quoteNote), 'בתרחיש שליחת הצעה מוצגת הערה שההצעה מצורפת ידנית');
check(ui.mailEdited === 'mailto:yossi@example.com?subject=' + encodeURIComponent('נושא ערוך') + '&body=' + encodeURIComponent('גוף ערוך\r\nשורה שנייה'), 'נושא וגוף שנערכו ידנית נשמרים בפתיחה באימייל');
check(ui.script.active.some(t => /בירור/.test(t)) && ui.script.tel === 'tel:+972501234567' && !ui.script.spam, 'תסריט: ליד שכבר נוצר איתו קשר מקבל בירור צרכים, קישור חיוג תקין, בלי הודעת ספאם');
check(ui.objection, 'תסריט התנגדות למחיר נטען');
check(/^היי/.test(ui.waBack.text) && ui.waBack.active.length >= 2, 'חזרה ל-WhatsApp טוענת תרחיש מומלץ');
check(ui.savedStyle === 'short' && ui.styleAfterSwitch.some(t => /קצר/.test(t)), 'הסגנון נשמר וחוזר אחרי מעבר בין ערוצים');
check(ui.badPicksIgnored, 'ערכי ערוץ, מטרה וסגנון לא מוכרים נדחים');
check(ui.anotherChanged, '"גרסה אחרת" מחליפה נוסח');
check(ui.sentKnown === 'https://wa.me/972501234567?text=' + encodeURIComponent('נוסח שנערך ידנית'), 'שליחה לליד מוכר פותחת WhatsApp עם הנוסח הערוך');
check(ui.freshPurpose === 'intro' && ui.consentOpen && ui.openedBeforeConsent === 1, 'ליד בלי קשר קודם עובר קודם דרך אישור ההסכמה');
check(/^https:\/\/wa\.me\/972527654321\?text=/.test(ui.sentFresh || '') && decodeURIComponent(ui.sentFresh.split('text=')[1]).startsWith('היי מיכל'), 'אחרי האישור נפתח WhatsApp עם ההודעה');
check(ui.noEmailToast, 'ליד בלי אימייל מקבל הודעה ברורה ולא נפתח מייל');
check(ui.scriptOpen, 'פתיחה ישירה לתסריט עובדת');
check(ui.directNoText === 'https://wa.me/972527654321', 'כפתור WhatsApp ישיר לא גורר טקסט מהחלון הקודם');
check(/^https:\/\/wa\.me\/972527654321\?text=/.test(ui.quick || '') && /תודה על הפגישה/.test(decodeURIComponent(ui.quick)), 'תשובות מהירות בכרטיס עובדות דרך אותו מנוע');
check(/^היי שירה/.test(ui.tools) && /מה שלומך/.test(ui.tools), 'כרטיס התבניות במסך הכלים עובד דרך אותו מנוע');
check(ui.menu.length === 3, 'שלוש הכניסות מופיעות בתפריט "עוד" של הליד');
check(ui.m390.sheet <= 0 && ui.m390.doc <= 0 && ui.m390s.sheet <= 0 && ui.m390s.doc <= 0, 'אין גלילה אופקית ב-390px, גם בתסריט');
check(ui.chipHeights.every(h => h >= 44) && ui.actionHeights.every(h => h >= 44), 'כל כפתורי הבחירה והפעולה בגובה 44px לפחות');
check(ui.invokes.length === 0, 'אין אף קריאה ל-Edge Function (ובפרט ל-ai-proxy)');

// דסקטופ
await page.setViewportSize({ width: 1280, height: 800 });
const desk = await page.evaluate(() => {
  SmartWA.open('known', 'script');
  const sheet = document.querySelector('#modal-smart-wa .modal-sheet');
  const r = sheet.getBoundingClientRect();
  const ta = document.getElementById('swa-text');
  return { doc: document.documentElement.scrollWidth - window.innerWidth, w: Math.round(r.width), inView: r.left >= 0 && r.right <= window.innerWidth && r.bottom <= window.innerHeight + 1, dir: getComputedStyle(ta).direction, align: getComputedStyle(ta).textAlign };
});
check(desk.doc <= 0 && desk.inView && desk.dir === 'rtl' && desk.align === 'right', `דסקטופ: החלון בתוך המסך (${desk.w}px), RTL ויישור לימין, בלי גלילה אופקית`);
await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', '-desktop.png') }).catch(() => {});
await page.setViewportSize({ width: 390, height: 844 });
await page.evaluate(() => { SmartWA.open('known', 'email'); document.getElementById('swa-service').value = 'ליווי בקניית דירה'; SmartWA.setService('ליווי בקניית דירה'); });
await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', '-email.png') }).catch(() => {});
await page.evaluate(() => { SmartWA.pick('channel', 'script'); document.querySelector('#modal-smart-wa .modal-sheet').scrollTop = 0; });
await page.screenshot({ path: (process.env.SHOT || '/dev/null').replace('.png', '-script.png') }).catch(() => {});
check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));

await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
