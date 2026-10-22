// בדיקת שמירת התחום דרך RPC צר, התנהגות כשהמיגרציה עוד לא הוחלה, והאשף לפרופיל שירותים ועסקים.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const res = await page.evaluate(async () => {
  DB.tenantId = 't1'; State.isDemo = false;
  const calls = [];
  const out = {};
  const answer = r => { sbClient.rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve(r); }; };
  const warn = []; const origToast = window.toast; window.toast = (m, t) => { warn.push(m); };
  answer({ data: { industry: 'interior', onboarding_completed: true }, error: null });
  out.ok = await DB.updateIndustry('interior', true);
  out.state = { industry: State.tenant.industry, done: State.tenant.onboarding_completed };
  out.call = calls[0];
  answer({ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.set_tenant_industry' } });
  out.notApplied = await DB.updateIndustry('other');
  answer({ data: null, error: { code: 'P0001', message: 'industry_change_locked' } });
  out.locked = await DB.updateIndustry('realestate');
  answer({ data: null, error: { code: '22023', message: 'invalid_industry' } });
  out.invalid = await DB.updateIndustry('x');
  out.toasts = warn;
  // שמירה שנכשלה לא משנה את התחום המקומי
  localStorage.setItem('plto_industry', 'realestate_lawyer');
  answer({ data: null, error: { code: 'P0001', message: 'industry_change_locked' } });
  await Settings.setIndustry('realestate');
  out.localAfterLocked = localStorage.getItem('plto_industry');
  window.toast = origToast;
  return out;
});
check(res.ok.ok === true && res.state.industry === 'interior' && res.state.done === true, 'שמירה מוצלחת מעדכנת את מצב העסק');
check(res.call.fn === 'set_tenant_industry' && res.call.args.p_industry === 'interior' && res.call.args.p_complete_onboarding === true && Object.keys(res.call.args).length === 2, 'הקריאה שולחת רק תחום ודגל סיום הצטרפות');
check(res.notApplied.ok === true && res.notApplied.local === true, 'כשהמיגרציה עוד לא הוחלה, התחום נשאר מקומי בלי שגיאה למשתמש');
check(res.locked.ok === false && res.locked.locked === true, 'חסימת יציאה מתחום עו"ד מוחזרת כסירוב');
check(res.invalid.ok === false, 'ערך לא חוקי מוחזר ככישלון');
check(res.toasts.some(t => /דרך התמיכה/.test(t)) && res.toasts.some(t => /לא נשמר בשרת/.test(t)), 'המשתמש מקבל הודעה ברורה בשני המקרים');
check(res.localAfterLocked === 'realestate_lawyer', 'שמירה שנדחתה לא משנה את התחום המקומי');

const wiz = await page.evaluate(() => {
  localStorage.setItem('plto_industry', 'other');
  const step = Onboarding._steps[2];
  const html = step.render();
  Onboarding._applyStageTemplate('short');
  document.body.insertAdjacentHTML('beforeend', '<div id="t"><div id="ob-stages-list"></div></div>');
  Onboarding._applyStageTemplate('meeting');
  const names = [...document.querySelectorAll('#t .stage-name-input')].map(i => i.value);
  return { hasTemplates: /_applyStageTemplate\('quote'\)/.test(html) && /_applyStageTemplate\('short'\)/.test(html), names,
           label: getLabel('property'), propsOn: hasPropertiesModule(), ind: INDUSTRY_LABELS.other.stages };
});
check(wiz.hasTemplates, 'אשף הצטרפות לעסק כללי מציג תבניות תהליך מכירה');
check(JSON.stringify(wiz.names) === JSON.stringify(['פנייה נכנסה', 'נקבעה פגישה', 'הפגישה התקיימה', 'הצעה', 'נסגר ✓']), 'בחירת תבנית ממלאת את השלבים');
const mod = await page.evaluate(() => {
  State.tenant.industry = 'other'; localStorage.setItem('plto_industry', 'other');
  State.properties = [];
  const empty = hasPropertiesModule();
  State.properties = [{ id: 'p1', title: 'x' }];
  const withData = hasPropertiesModule();
  localStorage.setItem('plto_industry', 'realestate'); State.properties = [];
  return { empty, withData, realestate: hasPropertiesModule() };
});
check(mod.empty === false && mod.withData === true && mod.realestate === true, 'מודול הנכסים כבוי בעסק כללי בלי נתונים, נשאר פתוח כשיש נתונים, ופעיל בנדל"ן');
const noRe = await page.evaluate(() => { const o = INDUSTRY_LABELS.other; return [o.property, o.properties, o.agent, o.pipeline, ...o.stages].join(' '); });
check(!/נכס|סוכן|קונה|ביקור|חוזה/.test(noRe), 'בפרופיל הכללי אין מונחי נדל"ן');
check(errors.length === 0, 'אין שגיאות JS בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
console.log(failures ? failures + ' נכשלו' : 'הכל עבר');
process.exit(failures ? 1 : 0);
