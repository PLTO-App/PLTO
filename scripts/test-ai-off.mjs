// בדיקת מצב "AI כבוי": במרכז הכלים ובכרטיס הליד אין כלי שנראה פעיל ולא עובד, הכניסות הישנות
// מחוברות למחוללי התבניות, ושום פעולה לא שולחת בקשה ל-ai-proxy. רצה עם Supabase מדומה.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const r = await page.evaluate(async () => {
  const invokes = [];
  sbClient.functions.invoke = (fn) => { invokes.push(fn); return Promise.resolve({ data: {}, error: { message: 'x' } }); };
  const opened = []; window.open = (u) => { opened.push(u); return null; };
  const mail = []; document.addEventListener('click', e => { const a = e.target.closest?.('a[href^="mailto:"]'); if (a) { mail.push(a.getAttribute('href')); e.preventDefault(); } }, true);
  const vis = el => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
  const out = {};
  out.flag = { enabled: AI.ENABLED, cls: document.documentElement.classList.contains('ai-off') };

  // מרכז כלים
  App.go('tools');
  const tools = document.getElementById('screen-tools');
  const cards = [...tools.querySelectorAll('.tool-card')];
  out.cards = cards.map(c => ({ title: c.querySelector('.tool-card-title')?.textContent.trim(), visible: vis(c), ai: c.hasAttribute('data-ai') }));
  out.visibleAiText = cards.filter(vis).filter(c => /AI/.test(c.textContent)).map(c => c.querySelector('.tool-card-title')?.textContent.trim());
  out.oldIds = ['script-btn', 'email-btn', 'script-result', 'email-result'].filter(id => document.getElementById(id));
  out.header = tools.querySelector('.tools-header-strip').textContent;
  out.tile = [...document.querySelectorAll('.dash-feat-tile-label')].map(e => e.innerText.replace(/\s+/g, ' ').trim());
  // כל כפתור נראה במרכז הכלים שמפעיל פונקציה: בודקים שהיעד קיים
  out.deadHandlers = [...tools.querySelectorAll('[onclick]')].filter(vis).map(e => e.getAttribute('onclick'))
    .filter(h => { const m = h.match(/^([A-Za-z]+)\.([A-Za-z_]+)\(/); return m && typeof (0, eval)(m[1])?.[m[2]] !== 'function'; });

  // כניסות חדשות ממרכז הכלים, בלי ליד
  const toolBtn = t => [...tools.querySelectorAll('.tool-card')].find(c => c.querySelector('.tool-card-title')?.textContent.includes(t)).querySelector('button');
  toolBtn('תסריטי שיחה').click();
  out.script = { open: !document.getElementById('modal-smart-wa').classList.contains('hidden'), ch: SmartWA._channel, hasName: !!document.getElementById('swa-name'), noTel: !document.querySelector('#smart-wa-content a[href^="tel:"]'), text: document.getElementById('swa-text').value.split('\n')[0] };
  const nm = document.getElementById('swa-name'); nm.value = 'שירה'; nm.dispatchEvent(new Event('input', { bubbles: true }));
  out.scriptNamed = document.getElementById('swa-text').value.includes('"היי שירה');
  closeModal('modal-smart-wa');
  toolBtn('אימיילים').click();
  const nm2 = document.getElementById('swa-name'); nm2.value = 'שירה'; nm2.dispatchEvent(new Event('input', { bubbles: true }));
  const t = document.getElementById('swa-text').value;
  out.email = { ch: SmartWA._channel, named: t.includes('שלום שירה,') };
  SmartWA.mail();
  out.mailHref = mail[0];
  SmartWA.pick('channel', 'whatsapp');
  SmartWA.send();
  out.waFree = opened[0];
  closeModal('modal-smart-wa');

  // כרטיס ליד
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  State.leads = [{ id: 'k', name: 'יוסי', phone: '050-1234567', email: 'y@example.com', stage: first, last_contact: null, tags: [], notes: '', score: 50 }];
  State.isDemo = false;
  App.go('lead-detail', { currentLeadId: 'k' });
  const detail = document.getElementById('lead-detail-content');
  const tabs = [...detail.querySelectorAll('.tab-btn')].filter(vis).map(b => b.textContent.trim());
  out.tabs = tabs;
  out.aiPanelVisible = vis(document.getElementById('tab-ai')) || [...detail.querySelectorAll('.ai-panel button')].some(vis);

  // AI.call נחסם בדפדפן בלי בקשה לשרת
  let msg = ''; try { await AI.call([{ role: 'user', content: 'x' }], 10); } catch (e) { msg = e.message; }
  out.callMsg = msg;
  out.invokes = invokes.slice();
  out.challenge = Gamify.DAILY_CHALLENGES.filter(c => /AI/.test(c));
  out.challengeAction = typeof Gamify.CHALLENGE_ACTIONS['נכתוב הודעת פולואפ מוכנה מהתבניות'];
  return out;
});
check(r.flag.enabled === false && r.flag.cls, 'דגל ה-AI בדפדפן כבוי ומסמן את הדף (ai-off), בהתאמה למתג בשרת');
const shown = r.cards.filter(c => c.visible).map(c => c.title);
check(shown.length >= 4 && ['תבניות WhatsApp', 'תסריטי שיחה מוכנים', 'אימיילים מוכנים'].every(t => shown.some(x => x.includes(t))), 'במרכז הכלים נשארו רק כרטיסים שאינם AI, שלושה מהם מחוללי התבניות: ' + shown.join(' | '));
check(r.cards.filter(c => c.ai).every(c => !c.visible) && r.cards.some(c => c.ai), 'כרטיס הצעת המחיר מבוסס ה-AI מוסתר');
check(r.visibleAiText.length === 0, 'אף כרטיס נראה במרכז הכלים לא מציג כלי AI' + (r.visibleAiText.length ? ': ' + r.visibleAiText.join(', ') : ''));
check(r.oldIds.length === 0, 'הטפסים הישנים של תסריט ואימייל (AI) הוסרו');
check(!/AI|הסוכן יכול/.test(r.header), 'כותרת מרכז הכלים לא מבטיחה AI');
check(r.tile.some(t => /מרכז\s*כלים/.test(t)) && !r.tile.includes('כלי AI'), 'האריח בדף הבית נקרא "מרכז כלים" (' + r.tile.join(' | ') + ')');
check(r.deadHandlers.length === 0, 'כל כפתור נראה במרכז הכלים מצביע על פונקציה קיימת' + (r.deadHandlers.length ? ': ' + r.deadHandlers.join(', ') : ''));
check(r.script.open && r.script.ch === 'script' && r.script.hasName && r.script.noTel && /פתיחה/.test(r.script.text), 'כרטיס התסריטים פותח את מחולל התסריטים בלי ליד (שדה שם, בלי חיוג)');
check(r.scriptNamed, 'שם שהוקלד בחלון נכנס לתסריט');
check(r.email.ch === 'email' && r.email.named, 'כרטיס האימיילים פותח את מחולל האימיילים, והשם נכנס');
check(r.mailHref && r.mailHref.startsWith('mailto:?subject='), 'בלי ליד נפתח אימייל בלי כתובת נמען');
check(r.waFree && r.waFree.startsWith('https://wa.me/?text='), 'בלי ליד נפתח WhatsApp עם הנוסח והנמען נבחר שם');
check(!r.tabs.some(t => /AI/.test(t)) && r.tabs.length >= 4 && !r.aiPanelVisible, 'בכרטיס הליד לשונית ה-AI ופעולותיה מוסתרות');
check(/מושבתים/.test(r.callMsg), 'AI.call נחסם עם הודעה ברורה');
check(r.invokes.length === 0, 'אין אף בקשה ל-ai-proxy או לפונקציית Edge אחרת');
check(r.challenge.length === 0 && r.challengeAction === 'function', 'אתגר יומי לא מפנה ל-AI');
// ── שאר הכניסות: תמיכה, יומן מהיר, מוטיבציה, עמוד הזמנה, פרסים, ייבוא, שיווק, רעיונות ──
const o = await page.evaluate(async () => {
  const invokes = [];
  sbClient.functions.invoke = (fn, a) => { invokes.push(fn); return Promise.resolve({ data: {}, error: null }); };
  const toasts = []; const origToast = window.toast; window.toast = (m) => { toasts.push(m); };
  const vis = el => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
  const out = {};
  const first = State.stages.slice().sort((a, b) => a.order - b.order)[0].id;
  State.isDemo = false;
  State.leads = [
    { id: 'a', name: 'אבי לוי', phone: '0501111111', stage: first, last_contact: null, tags: [], notes: '', score: 50 },
    { id: 'b', name: 'אבי כהן', phone: '0502222222', stage: first, last_contact: null, tags: [], notes: '', score: 50 },
    { id: 'c', name: 'מיכל ברק', phone: '0503333333', stage: first, last_contact: null, tags: [], notes: '', score: 50, next_followup: '2020-01-01' },
  ];

  // תמיכה
  openModal('modal-support');
  const sup = document.getElementById('modal-support');
  out.supportText = sup.innerText;
  document.getElementById('support-msg-input').value = 'יש לי בעיה בייצוא';
  await Support.submit();
  out.supportToast = toasts.some(m => /הפנייה התקבלה/.test(m));
  out.supportInvokes = invokes.slice();
  closeModal('modal-support');

  // יומן מהיר
  openModal('modal-quicklog');
  const ql = document.getElementById('modal-quicklog');
  out.qlText = ql.innerText;
  const addActs = []; const origAdd = DB.addActivity, origUpd = DB.updateLead;
  DB.addActivity = async a => { addActs.push(a); return { id: 'x', ...a, created_at: '2026-10-22' }; }; DB.updateLead = async () => ({});
  const before = JSON.stringify(localStorage.getItem('plto_ai_v1'));
  const ask = t => { document.getElementById('ql-input').value = t; QuickLog.process(); };
  ask('שוחחתי עם מיכל ברק, מעוניינת לראות עוד נכסים');
  out.qlOne = { confirm: vis(document.getElementById('ql-state-confirm')), lead: QuickLog._leadId, preview: document.getElementById('ql-activity-preview').textContent };
  await QuickLog.confirm();
  out.qlSaved = { content: addActs[0]?.content, type: addActs[0]?.type, limitsUntouched: JSON.stringify(localStorage.getItem('plto_ai_v1')) === before };
  QuickLog._resetToInput(true);
  ask('דיברתי עם אבי היום על התקציב');
  out.qlMany = { pick: vis(document.getElementById('ql-state-pick')), rows: document.querySelectorAll('#ql-pick-list .ql-lead-pick-row').length };
  QuickLog._resetToInput(true);
  ask('לאבי לוי יש בקשה חדשה להצעה');
  out.qlPrefix = QuickLog._leadId;
  QuickLog._resetToInput(true);
  const t0 = toasts.length; ask('שיחה עם מישהו שלא קיים במערכת בכלל');
  out.qlNone = { toast: toasts.slice(t0).some(m => /לא זוהה שם של ליד/.test(m)), input: vis(document.getElementById('ql-state-input')) };
  DB.addActivity = origAdd; DB.updateLead = origUpd;
  closeModal('modal-quicklog');

  // מוטיבציה
  const mt = document.getElementById('motivation-text');
  const msgs = new Set();
  for (let i = 0; i < 8; i++) { await MotivationAgent.generate(); msgs.add(mt.textContent); }
  out.motiv = { n: msgs.size, sample: [...msgs], coolHidden: document.getElementById('motivation-cooldown').classList.contains('hidden'), btnEnabled: !document.getElementById('motivation-btn').disabled };

  // עמוד הזמנה מהפניה, בלי AI
  LeadReferral._token = 'tok';
  const rpc = []; sbClient.rpc = (fn, a) => { rpc.push({ fn, a }); return Promise.resolve({ data: { slug: 'abc' }, error: null }); };
  document.body.insertAdjacentHTML('beforeend', '<button id="lref-page-btn"></button><div id="lref-page-link"></div><div id="lref-page-result" class="hidden"></div>');
  if (!document.getElementById('lref-vertical')) document.body.insertAdjacentHTML('beforeend', '<select id="lref-vertical"><option value="realestate">x</option></select>');
  await PageBuilder.generateFromReferral();
  out.page = rpc.find(r => r.fn === 'create_client_page')?.a;

  // פרסים: פרס AI לא נרשם כמומש
  const ms = Gamify.MILESTONES.find(m => m.action);
  const d = Gamify.get(); const claimedBefore = (d.milestoneClaimed || []).length;
  Gamify._pendingMilestone = ms; Gamify.claimMilestone();
  out.reward = { claimedAfter: (Gamify.get().milestoneClaimed || []).length - claimedBefore, toast: toasts.some(m => /אינו זמין כרגע/.test(m)) };
  d.xp = 99999; Gamify.save?.(); Gamify.renderStore();
  out.storeNoBtn = [...document.querySelectorAll('#xps-grid .xps-card.xps-unlocked')].some(c => /AI/.test(c.querySelector('.xps-card-desc')?.textContent || '') && c.querySelector('.xps-claim-btn')) === false;

  // ייבוא
  LeadImport.open();
  const imp = document.getElementById('import-modal-body').innerText;
  out.importText = imp;
  out.importImgBtn = !!document.getElementById('import-image-input');

  // שיווק
  App.go('marketing');
  const mk = document.getElementById('screen-marketing');
  const gens = [...mk.querySelectorAll('.mktg-card .tool-btn-primary')];
  out.mk = { n: gens.length, allDisabled: gens.every(b => b.disabled && /מושבת/.test(b.textContent)), banner: /מושבתים זמנית/.test(mk.innerText), fullService: !!mk.querySelector('.mktg-fs-btn'), usage: !!mk.querySelector('.mktg-usage-counter') };
  await Marketing.genOffer(); await Marketing.genPost(); await Marketing.genCampaign();

  // רעיונות
  Roadmap.fetch = async () => [{ title: 'ייצוא לידים לקובץ אקסל', description: 'הורדת כל הלידים לקובץ' }];
  out.dup = [await Roadmap.checkDuplicate('אפשרות ייצוא לידים לקובץ אקסל'), await Roadmap.checkDuplicate('חיבור ליומן גוגל לתיאום פגישות אוטומטי')];

  // כותרות ותוויות
  out.proHub = document.getElementById('screen-pro').innerText;
  window.toast = origToast;
  out.aiInvokes = invokes.filter(f => f === 'ai-proxy').length;
  return out;
});
check(!/AI עונה|סוכן התמיכה שלך|התשובה יכולה לפעמים/.test(o.supportText) && /הפנייה מגיעה ישירות לצוות/.test(o.supportText), 'צ\'אט התמיכה לא מבטיח מענה AI ומציג שהפנייה מגיעה לצוות');
check(o.supportToast && o.supportInvokes.filter(f => f === 'ai-proxy').length === 0 && o.supportInvokes.includes('notify-owner'), 'שליחת פנייה: אישור ברור למשתמש, בלי AI, והצוות מקבל התראה');
check(!/AI/.test(o.qlText) && /המשך לבחירת הליד/.test(o.qlText), 'היומן המהיר לא מציג AI ומציג את הצעד המקומי');
check(o.qlOne.confirm && o.qlOne.lead === 'c' && /מיכל ברק/.test(o.qlOne.preview), 'יומן מהיר: ליד אחד מזוהה לפי שם ומוצג לאישור');
check(o.qlSaved.type === 'note' && /^שוחחתי עם מיכל ברק/.test(o.qlSaved.content || '') && o.qlSaved.limitsUntouched, 'יומן מהיר: הטקסט נשמר כפי שנכתב כהערה, בלי לצרוך מכסת AI');
check(o.qlMany.pick && o.qlMany.rows === 2, 'יומן מהיר: כמה לידים תואמים מציגים בחירה ידנית');
check(o.qlPrefix === 'a', 'יומן מהיר: שם עם אות קידומת מזוהה ("לאבי לוי")');
check(o.qlNone.toast && o.qlNone.input, 'יומן מהיר: בלי שם ליד בטקסט מתקבלת הודעה ברורה והטקסט נשמר');
check(o.motiv.n >= 3 && o.motiv.sample.every(m => m && !/מייצר|המשך כך/.test(m)) && o.motiv.coolHidden && o.motiv.btnEnabled, 'מוטיבציה: מסרים מקומיים משתנים, ניטרליים, בלי קירור ובלי מכסה');
check(o.page && /^הזמנה ל-PLTO מאת/.test(o.page.p_headline) && !/[\/]ה|[\/]י/.test(o.page.p_headline + o.page.p_body_text) && o.page.p_cta_label === 'הצטרפות ל-PLTO', 'עמוד הזמנה נוצר מתבנית קבועה וניטרלית, בלי AI');
check(o.reward.claimedAfter === 0 && o.reward.toast && o.storeNoBtn, 'פרס שנוצר ב-AI לא נרשם כמומש וחנות הפרסים לא מציגה כפתור מימוש');
check(!/AI|בינה מלאכותית/.test(o.importText) && /מושבת זמנית/.test(o.importText) && !o.importImgBtn, 'ייבוא לידים: זיהוי מתמונה מוצג כמושבת, וייבוא מקובץ נשאר');
check(o.mk.n === 3 && o.mk.allDisabled && o.mk.banner && o.mk.fullService && !o.mk.usage, 'שיווק: שלושת הכלים מושבתים בבירור, בקשת שירות מלא נשארת פעילה');
check(o.dup[0] === true && o.dup[1] === false, 'בדיקת רעיון כפול עובדת מקומית ושמרנית');
check(!/בינה מלאכותית/.test(o.proHub) && /ניתוח וחיזוי/.test(o.proHub), 'מרכז ה-PRO לא מציג כותרת בינה מלאכותית');
check(o.aiInvokes === 0, 'אף אחת מהפעולות לא שלחה בקשה ל-ai-proxy');

check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));

await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
