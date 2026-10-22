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
check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));

await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
