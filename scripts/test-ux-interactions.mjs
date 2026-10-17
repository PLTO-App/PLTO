// בדיקות אינטראקציה בדפדפן (מגע אמיתי דרך CDP) לתפריט הפעולות, ה-swipe, ביטול המחיקה,
// העדכון המהיר והסינון. כל כתיבה ל-DB מוחלפת בתיעוד קריאות, ולכן הבדיקה לא נוגעת בנתונים חיים.
// שימוש: node scripts/test-ux-interactions.mjs
import { startHarness } from './lib/harness.mjs';

const { page, ctx, errors, close } = await startHarness({ touch: true });
const cdp = await ctx.newCDPSession(page);

const fails = [];
let passed = 0;
function check(name, ok, detail = '') {
  if (ok) { passed++; console.log(`✓ ${name}`); } else { fails.push(name); console.log(`✗ ${name}${detail ? ': ' + detail : ''}`); }
}

async function touch(points) {
  const [first, ...rest] = points;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: first[0], y: first[1] }] });
  for (const [x, y, wait] of rest) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] });
    if (wait) await page.waitForTimeout(wait);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}
async function swipe(x1, y1, x2, y2, steps = 10) {
  const pts = [[x1, y1]];
  for (let i = 1; i <= steps; i++) pts.push([x1 + ((x2 - x1) * i) / steps, y1 + ((y2 - y1) * i) / steps, 8]);
  await touch(pts);
  await page.waitForTimeout(350);
}
const center = async sel => {
  const b = await page.locator(sel).first().boundingBox();
  return { x: b.x + b.width / 2, y: b.y + b.height / 2, b };
};

// החלפת כתיבות ה-DB בתיעוד קריאות
await page.evaluate(() => {
  window.__calls = [];
  window.__failDelete = false;
  DB.deleteLead = async id => { window.__calls.push(['deleteLead', id]); if (window.__failDelete) throw new Error('boom'); };
  DB.moveLead = async (id, s) => { window.__calls.push(['moveLead', id, s]); };
  DB.addTask = async t => { window.__calls.push(['addTask', t.lead_id, t.type, t.due]); return { id: 't' + Math.random(), title: t.title, type: t.type, priority: t.priority, due: t.due, done: false, lead_id: t.lead_id, notes: '' }; };
  DB.addActivity = async a => { window.__calls.push(['addActivity', a.lead_id, a.type]); return { id: 'a' + Math.random(), lead_id: a.lead_id, type: a.type, content: a.content, created_at: today() }; };
  App.go('pipeline');
  // לידים מוסתרים בדמו ללא כתיבה אמיתית, ולכן מוסיפים ליד עם שם עוין לבדיקת XSS
  State.leads.unshift({ id: 'xss1', name: '<img src=x onerror="window.__xss=1">', phone: '050-1112233', phone2: '', email: '', stage: State.stages[0].id, source: 'other', budget_min: 0, budget_max: 0, desired_area: '', score: 50, lead_role: 'buyer', notes: '', tags: [], created_at: today() });
  Pipeline._activeStage = State.stages[0].id;
  Pipeline.render();
});
await page.waitForTimeout(400);

const firstRow = '#pipeline-board .kanban-col.tab-active .sw-row';
const rowIdOf = () => page.evaluate(sel => document.querySelector(sel).dataset.lpLead, firstRow);

// XSS
check('שם ליד עם HTML מוצג כטקסט ולא מורץ', await page.evaluate(() => window.__xss === undefined && !!document.querySelector('.lr-name') && document.querySelector('.lr-name').textContent.includes('<img')));

// תפריט פעולות: פתיחה, מקלדת, Esc
const moreSel = `${firstRow} .lr-more`;
await page.focus(moreSel);
await page.keyboard.press('Enter');
await page.waitForSelector('#action-sheet .as-item');
check('תפריט ⋯ נפתח עם פריטים', (await page.locator('#action-sheet .as-item').count()) >= 7);
check('הפריט הראשון בפוקוס', await page.evaluate(() => document.activeElement.classList.contains('as-item')));
await page.keyboard.press('ArrowDown');
check('חץ למטה מזיז את הפוקוס', await page.evaluate(() => document.activeElement.dataset.i === '1'));
await page.keyboard.press('Escape');
check('Esc סוגר את התפריט', (await page.locator('#action-sheet').count()) === 0);
check('הפוקוס חוזר לכפתור ⋯', await page.evaluate(sel => document.activeElement === document.querySelector(sel), moreSel));
check('כל פריטי התפריט בגובה 44px לפחות', await (async () => {
  await page.click(moreSel);
  const hs = await page.locator('#action-sheet .as-item').evaluateAll(els => els.map(e => e.getBoundingClientRect().height));
  await page.keyboard.press('Escape');
  return hs.every(h => h >= 44);
})());

// swipe: גרירה ימינה חושפת את מגש התקשורת, ולחיצה על התוכן סוגרת בלי לנווט
const leadId = await rowIdOf();
let c = await center(`${firstRow} .sw-content`);
await swipe(c.x - 40, c.y, c.x + 120, c.y);
check('swipe ימינה פותח את המגש', await page.evaluate(sel => document.querySelector(sel).classList.contains('sw-open'), firstRow));
check('המגש גלוי ובו כפתורי WhatsApp ושיחה', await page.evaluate(sel => {
  const t = document.querySelector(sel + ' .sw-tray-left'); return !!t && getComputedStyle(t).visibility === 'visible' && t.querySelectorAll('.sw-act').length === 2;
}, firstRow));
await page.touchscreen.tap(c.x + 60, c.y - 10);
await page.waitForTimeout(350);
check('לחיצה על התוכן כשהמגש פתוח סוגרת אותו', await page.evaluate(sel => !document.querySelector(sel).classList.contains('sw-open'), firstRow));
check('ולא מנווטת לכרטיס הליד', await page.evaluate(() => State.screen === 'pipeline'));

// swipe שמאלה: מעקב
c = await center(`${firstRow} .sw-content`);
await swipe(c.x + 40, c.y, c.x - 140, c.y);
check('swipe שמאלה פותח את מגש המעקב והשלב', await page.evaluate(sel => document.querySelector(sel).classList.contains('sw-open') && document.querySelector(sel).querySelectorAll('.sw-tray-right .sw-act').length === 2, firstRow));
await page.evaluate(sel => document.querySelector(sel).querySelector('.sw-tray-right .sw-act').click(), firstRow);
await page.waitForSelector('#modal-quick-edit:not(.hidden) .qe-chip');
check('לחיצה על "מעקב" פותחת את חלון העדכון המהיר', await page.locator('#qe-title').textContent().then(t => t.includes('קביעת מעקב')));
const tasksBefore = await page.evaluate(() => State.tasks.length);
await page.locator('#modal-quick-edit .qe-chip', { hasText: 'מחר' }).click();
await page.waitForTimeout(300);
const addTask = await page.evaluate(() => window.__calls.filter(x => x[0] === 'addTask'));
check('מעקב למחר נוצר כמשימה מסוג call עם התאריך הנכון', addTask.length === 1 && addTask[0][2] === 'call' && addTask[0][3] === new Date(Date.now() + 86400000).toISOString().slice(0, 10) && addTask[0][1] === leadId, JSON.stringify(addTask));
check('המשימה נוספה ל-State', (await page.evaluate(() => State.tasks.length)) === tasksBefore + 1);
check('החלון נסגר', await page.evaluate(() => document.getElementById('modal-quick-edit').classList.contains('hidden')));

// שלב הבא מהמגש
const stageBefore = await page.evaluate(id => State.leads.find(l => l.id === id).stage, leadId);
await page.evaluate(sel => { const r = document.querySelector(sel); SwipeRow._set(r, r.querySelector('.sw-content'), -152); }, firstRow);
await page.evaluate(sel => document.querySelector(sel).querySelectorAll('.sw-tray-right .sw-act')[1].click(), firstRow);
await page.waitForTimeout(400);
const mv = await page.evaluate(() => window.__calls.filter(x => x[0] === 'moveLead'));
const nextStage = await page.evaluate(id => State.leads.find(l => l.id === id).stage, leadId);
check('"שלב הבא" מעביר ליד לשלב העוקב ושומר', mv.length === 1 && nextStage !== stageBefore && mv[0][2] === nextStage, JSON.stringify(mv));

// גלילה אנכית לא פותחת מגש
await page.evaluate(() => { Pipeline._activeStage = State.stages[0].id; Pipeline.render(); });
c = await center(`${firstRow} .sw-content`);
await swipe(c.x, c.y + 20, c.x + 20, c.y - 60);
check('תנועה אנכית לא פותחת את המגש', await page.evaluate(sel => !document.querySelector(sel).classList.contains('sw-open'), firstRow));

// לחיצה ארוכה פותחת את אותו תפריט
c = await center(`${firstRow} .sw-content`);
await touch([[c.x, c.y], [c.x + 1, c.y, 700]]);
await page.waitForTimeout(100);
check('לחיצה ארוכה פותחת את תפריט הפעולות', (await page.locator('#action-sheet .as-item').count()) >= 7);
await page.keyboard.press('Escape');

// מצב נגישות מבטל swipe
await page.evaluate(() => { State.isAccessibleMode = true; });
c = await center(`${firstRow} .sw-content`);
await swipe(c.x - 40, c.y, c.x + 120, c.y);
check('במצב נגישות ה-swipe מבוטל', await page.evaluate(sel => !document.querySelector(sel).classList.contains('sw-open'), firstRow));
await page.evaluate(() => { State.isAccessibleMode = false; });

// מחיקה עם ביטול
await page.evaluate(() => { Pipeline._activeStage = State.stages[0].id; Pipeline.render(); });
const delId = await rowIdOf();
const leadsBefore = await page.evaluate(() => State.leads.length);
await page.click(`${firstRow} .lr-more`);
await page.locator('#action-sheet .as-item', { hasText: 'מחיקה' }).click();
await page.waitForSelector('.toast-undo-btn');
check('המחיקה מסירה את הליד מיד מהמסך', (await page.evaluate(() => State.leads.length)) === leadsBefore - 1);
check('השרת עדיין לא נקרא בזמן חלון הביטול', (await page.evaluate(() => window.__calls.filter(x => x[0] === 'deleteLead').length)) === 0);
await page.locator('.toast-undo-btn').click();
check('ביטול מחזיר את הליד', (await page.evaluate(() => State.leads.length)) === leadsBefore);
check('ובלי קריאת מחיקה לשרת', (await page.evaluate(() => window.__calls.filter(x => x[0] === 'deleteLead').length)) === 0);
await page.evaluate(() => { Pipeline._activeStage = State.stages[0].id; Pipeline.render(); });
await page.click(`${firstRow} .lr-more`);
await page.locator('#action-sheet .as-item', { hasText: 'מחיקה' }).click();
await page.waitForSelector('.toast-undo-btn');
await page.evaluate(() => Undo.flush());
await page.waitForTimeout(200);
check('בלי ביטול המחיקה מגיעה לשרת פעם אחת', (await page.evaluate(() => window.__calls.filter(x => x[0] === 'deleteLead').length)) === 1);
// כשל במחיקה מחזיר את הליד
await page.evaluate(() => { window.__failDelete = true; Pipeline._activeStage = State.stages[0].id; Pipeline.render(); });
const n2 = await page.evaluate(() => State.leads.length);
await page.click(`${firstRow} .lr-more`);
await page.locator('#action-sheet .as-item', { hasText: 'מחיקה' }).click();
await page.evaluate(() => Undo.flush());
await page.waitForTimeout(300);
check('כשל במחיקה מחזיר את הליד ומציג שגיאה', (await page.evaluate(() => State.leads.length)) === n2 && (await page.locator('.toast-error').count()) > 0);
await page.evaluate(() => { window.__failDelete = false; });

// הערה מהירה
await page.evaluate(() => { Pipeline._activeStage = State.stages[0].id; Pipeline.render(); });
await page.click(`${firstRow} .lr-more`);
await page.locator('#action-sheet .as-item', { hasText: 'הוספת הערה' }).click();
await page.waitForSelector('#qe-note');
await page.click('#qe-note-save');
check('הערה ריקה לא נשמרת', (await page.evaluate(() => window.__calls.filter(x => x[0] === 'addActivity').length)) === 0);
await page.fill('#qe-note', 'התקשרתי, ביקש הצעה');
await page.click('#qe-note-save');
await page.waitForTimeout(300);
check('הערה נשמרת כפעילות מסוג note', (await page.evaluate(() => window.__calls.filter(x => x[0] === 'addActivity' && x[2] === 'note').length)) === 1);

// סינון: פריטי keepOpen נשארים פתוחים והצ'יפ מופיע ונמחק
await page.evaluate(() => App.go('leads'));
await page.waitForTimeout(300);
const total = await page.locator('#leads-list-container .sw-row').count();
await page.click('#leads-filter-btn');
await page.locator('#action-sheet .as-item', { hasText: 'מעקב באיחור' }).click();
check('התפריט נשאר פתוח אחרי בחירת סינון', (await page.locator('#action-sheet').count()) === 1);
await page.keyboard.press('Escape');
const filtered = await page.locator('#leads-list-container .sw-row').count();
check('הסינון מצמצם את הרשימה', filtered < total, `${total} -> ${filtered}`);
check('מופיע צ\'יפ סינון פעיל', (await page.locator('#leads-role-filter .lf-chip').count()) === 1);
await page.locator('#leads-role-filter .lf-chip').click();
check('לחיצה על הצ\'יפ מנקה את הסינון', (await page.locator('#leads-list-container .sw-row').count()) === total);
await page.click('#leads-filter-btn');
await page.locator('#action-sheet .as-item', { hasText: 'ציון גבוה' }).click();
await page.keyboard.press('Escape');
const scores = await page.locator('#leads-list-container .score-badge').allTextContents();
const nums = scores.map(Number);
check('מיון לפי ציון מסדר מהגבוה לנמוך', nums.every((v, i) => i === 0 || nums[i - 1] >= v), scores.join(','));
check('בחירת המיון נשמרת', await page.evaluate(() => LeadFilters.sort() === 'score'));
await page.evaluate(() => LeadFilters.setSort('created'));

// כרטיס ליד: תפריט עוד ושינוי שלב
await page.evaluate(() => App.go('lead-detail', { currentLeadId: State.leads[1].id }));
await page.waitForTimeout(300);
check('בכותרת הכרטיס שלושה כפתורי פעולה לכל היותר', (await page.locator('.lead-detail-actions .lead-action-btn').count()) <= 3);
await page.click('.lead-detail-actions .lead-action-btn[aria-haspopup="menu"]');
check('תפריט "עוד" כולל שינוי שלב ועריכה', await page.locator('#action-sheet .as-item', { hasText: 'שינוי שלב' }).count() === 1 && await page.locator('#action-sheet .as-item', { hasText: 'עריכת פרטים' }).count() === 1);
await page.keyboard.press('Escape');
await page.locator('.lead-detail-header button[aria-label^="שינוי שלב"]').click();
check('צ\'יפ השלב בכותרת פותח בחירת שלב', await page.locator('#modal-quick-edit:not(.hidden) .qe-chip').count() >= 2);
await page.evaluate(() => closeModal('modal-quick-edit'));


// ניווט תחתון: חמישה פריטים ותפריט "עוד"
await page.evaluate(() => App.go('dashboard'));
await page.waitForTimeout(300);
check('בניווט התחתון חמישה פריטים', (await page.locator('#bottom-nav .bottom-nav-item').count()) === 5);
check('הפריטים בניווט בגובה 44px לפחות', await page.locator('#bottom-nav .bottom-nav-item').evaluateAll(els => els.every(e => e.getBoundingClientRect().height >= 44)));
await page.click('#bottom-nav .bottom-nav-item[data-screen="more"]');
const moreLabels = await page.locator('#action-sheet .as-item').allTextContents();
check('תפריט "עוד" כולל את כל המסכים שירדו מהניווט', ['לוח שנה', 'שיתופי פעולה', 'אנליטיקס', 'מרכז כלים', 'שירותי שיווק', 'תיבת דואר', 'הגדרות'].every(l => moreLabels.some(t => t.includes(l))), moreLabels.join('|'));
await page.locator('#action-sheet .as-item', { hasText: 'הגדרות' }).click();
await page.waitForTimeout(300);
check('בחירה בתפריט "עוד" מנווטת למסך', await page.evaluate(() => State.screen === 'settings'));
check('פריט "עוד" מסומן כפעיל במסך שאינו בניווט', await page.locator('#bottom-nav .bottom-nav-item[data-screen="more"].active').count() === 1);

// הגדרות: קבוצות מתקפלות
check('בהגדרות רק קבוצה אחת פתוחה בהתחלה', await page.locator('#settings-body .settings-section.sc-open').count() === 1);
await page.locator('#settings-body .settings-section:not(.sc-open) .sc-toggle').first().focus();
await page.keyboard.press('Enter');
check('מקש Enter פותח קבוצה', await page.locator('#settings-body .settings-section.sc-open').count() === 2);
await page.evaluate(() => Settings.render());
check('מצב הפתיחה נשמר אחרי רענון המסך', await page.locator('#settings-body .settings-section.sc-open').count() === 2);

// דשבורד: משימות לפני כרטיס ה-AI, והכלים מקופלים במובייל
await page.evaluate(() => { Dashboard._moreInit = false; App.go('dashboard'); });
await page.waitForTimeout(300);
const order = await page.evaluate(() => {
  const y = id => document.getElementById(id).getBoundingClientRect().top + scrollY;
  return { tasks: y('dash-tasks'), kpi: y('kpi-row'), ai: y('dash-ai-briefing') };
});
check('בדשבורד המשימות הדחופות מעל כרטיס ה-AI', order.tasks < order.ai && order.kpi < order.ai, JSON.stringify(order));
check('כלים והישגים מקופלים במובייל', await page.evaluate(() => !document.getElementById('dash-more').open));
check('סיור מודרך פותח את הקבוצה המקופלת כשהיעד בתוכה', await page.evaluate(() => {
  const w = document.getElementById('gamify-widget'); const det = w.closest('details');
  if (!det) return false;
  det.open = false; GuidedTour._cachedSteps = [{ target: '#gamify-widget', emoji: '', title: 't', text: 't' }]; GuidedTour._step = 0; GuidedTour._render();
  const ok = det.open; GuidedTour.done && GuidedTour.done(false); return ok;
}));

// משימות: swipe, דחייה ומחיקה עם ביטול
await page.evaluate(() => { document.getElementById('tour-overlay')?.remove(); document.getElementById('tour-tooltip')?.remove(); App.go('tasks'); });
await page.waitForTimeout(400);
const taskRow = '#tasks-list .sw-row';
check('במשימות אין כפתור מחיקה גלוי', await page.locator('#tasks-list .quick-del-btn').count() === 0);
check('תיבת הסימון בגודל לחיצה של 44px', await page.locator(`${taskRow} .task-check`).first().evaluate(e => { const r = e.getBoundingClientRect(); return r.width >= 44 && r.height >= 44; }));
const tid = await page.evaluate(sel => document.querySelector(sel).dataset.lpTask, taskRow);
await page.evaluate(() => { window.__calls = []; DB.updateTask = async (id, u) => { window.__calls.push(['updateTask', id, JSON.stringify(u)]); }; DB.deleteTask = async id => { window.__calls.push(['deleteTask', id]); }; });
let tc = await center(`${taskRow} .sw-content`);
await swipe(tc.x - 40, tc.y, tc.x + 130, tc.y);
check('swipe במשימה חושף "בוצע" ו"למחר"', await page.evaluate(sel => { const r = document.querySelector(sel); return r.classList.contains('sw-open') && r.querySelectorAll('.sw-tray-left .sw-act').length === 2; }, taskRow));
await page.evaluate(sel => document.querySelectorAll(sel)[0].querySelectorAll('.sw-tray-left .sw-act')[1].click(), taskRow);
await page.waitForTimeout(300);
const defer = await page.evaluate(() => window.__calls.filter(x => x[0] === 'updateTask'));
check('דחייה למחר שומרת תאריך של מחר', defer.length === 1 && defer[0][1] === tid && JSON.parse(defer[0][2]).due === new Date(Date.now() + 86400000).toISOString().slice(0, 10), JSON.stringify(defer));
await page.evaluate(sel => { const r = document.querySelector(sel); if (r) r.querySelector('.lr-more').click(); }, `#tasks-list .sw-row[data-lp-task="${tid}"]`);
await page.locator('#action-sheet .as-item', { hasText: 'מחיקה' }).click();
await page.waitForSelector('.toast-undo-btn');
check('מחיקת משימה מסירה אותה מיד וממתינה לביטול', await page.evaluate(id => !State.tasks.some(t => t.id === id) && window.__calls.every(x => x[0] !== 'deleteTask'), tid));
await page.locator('.toast-undo-btn').click();
check('ביטול מחזיר את המשימה', await page.evaluate(id => State.tasks.some(t => t.id === id), tid));

// שותפים: כל הטאבים בשורה אחת והבאנר מקופל
await page.evaluate(() => App.go('partners'));
await page.waitForTimeout(300);
check('טאבי שיתופי הפעולה בשורה אחת', await page.locator('.partners-tab').evaluateAll(els => els.every(e => e.getBoundingClientRect().height <= 56)));
check('באנר ההסבר מקופל', await page.evaluate(() => !document.querySelector('.partners-howto').open));

// נכסים: תפריט במקום ✕ גלוי
await page.evaluate(() => App.go('properties'));
await page.waitForTimeout(300);
check('בכרטיסי הנכסים אין כפתור מחיקה גלוי', await page.locator('#properties-grid .quick-del-btn').count() === 0);
check('כותרת הנכסים לא גולשת', await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));

check('אין שגיאות JS', errors.length === 0, errors.join(' | '));
await close();
console.log(`\n${passed} עברו, ${fails.length} נכשלו`);
process.exit(fails.length ? 1 : 0);
