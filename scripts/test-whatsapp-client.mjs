// בדיקת צד הלקוח של התראות WhatsApp (28.10.2026): הדפדפן שולח רק סוג אירוע וערכים קטנים, בלי מספר ובלי טקסט חופשי,
// שמירת המספר מאומתת (נייד ישראלי בלבד), והודעות השגיאה ברורות. רצה על הממשק האמיתי עם Supabase מדומה,
// ואף בקשה לא יוצאת החוצה. לא מוכיחה שהפונקציה בשרת מתנהגת כך: זה נבדק ב-supabase/tests/twilio-whatsapp-guard.test.ts.
import { startHarness } from './lib/harness.mjs';

const { page, errors, close } = await startHarness();
let failures = 0;
const check = (ok, msg) => { console.log((ok ? '✓ ' : '✗ ') + msg); if (!ok) failures++; };

const r = await page.evaluate(async () => {
  const out = {};
  const invokes = [];
  const rpcs = [];
  const origInvoke = sbClient.functions.invoke, origRpc = sbClient.rpc;
  let invokeResult = { data: { success: true }, error: null };
  sbClient.functions.invoke = (name, opts) => { invokes.push({ name, body: opts && opts.body }); return Promise.resolve(typeof invokeResult === 'function' ? invokeResult() : invokeResult); };
  let rpcResult = { data: null, error: null };
  sbClient.rpc = (fn, args) => { rpcs.push({ fn, args }); return Promise.resolve(rpcResult); };
  const toasts = [];
  const origToast = window.toast; window.toast = (m, t) => { toasts.push({ m, t }); };

  // נרמול נייד ישראלי
  out.norm = ['050-123-4567', '0501234567', '+972 50 123 4567', '972501234567', '00972501234567', '501234567', '0201234567', '+15551234567', 'abc', '', null]
    .map(v => Twilio.normalizeMobile(v));

  // בלי מספר שמור: שום בקשה לא יוצאת
  State.tenant = { ...State.tenant, whatsapp_number: '' };
  localStorage.removeItem('whatsapp_number');
  Twilio.notifyNewLead({ name: 'דנה' }); Twilio.notifyStageChanged({ name: 'דנה' }, 'הצעה'); Twilio.notifyTaskDue(['a']); Twilio.notifyColdLeads(['a']);
  out.noNumberCalls = invokes.length;

  // עם מספר: האירועים והערכים הקטנים בלבד
  State.tenant = { ...State.tenant, whatsapp_number: '0501234567' };
  await Twilio.notifyNewLead({ name: 'דנה', phone: '0509999999', notes: 'סודי', budget_max: 5000000 });
  await Twilio.notifyStageChanged({ name: 'דנה', phone: '0509999999' }, 'הצעה');
  await Twilio.notifyStageChanged({ name: 'דנה' }, 'עסקה נסגרה');
  await Twilio.notifyTaskDue(['משימה סודית א', 'ב', 'ג']);
  await Twilio.notifyColdLeads(['לקוח א', 'לקוח ב']);
  out.bodies = invokes.map(i => i.body);
  out.names = invokes.map(i => i.name);
  out.leak = JSON.stringify(invokes.map(i => i.body)).match(/0509999999|סודי|5000000|\+972|message|"to"/g);

  // תוצאות שגיאה מהשרת: הקוד מגיע מגוף התשובה
  invokes.length = 0;
  invokeResult = () => ({ data: null, error: { context: { json: async () => ({ error: 'whatsapp_disabled' }) } } });
  out.disabled = await Twilio.send('test', {});
  invokeResult = () => ({ data: null, error: { context: { json: async () => { throw new Error('not json'); } } } });
  out.unparsable = await Twilio.send('test', {});
  invokeResult = { data: { success: true }, error: null };
  State.isDemo = true; out.demo = await Twilio.send('test', {}); State.isDemo = false;
  out.texts = ['whatsapp_disabled', 'limit_reached', 'no_number', 'invalid_number', 'forbidden', 'unauthorized', 'x'].map(c => Twilio.errorText(c));

  // כפתור הבדיקה
  toasts.length = 0; invokes.length = 0;
  invokeResult = () => ({ data: null, error: { context: { json: async () => ({ error: 'whatsapp_disabled' }) } } });
  await Twilio.test();
  out.testDisabled = { toast: toasts[toasts.length - 1], calls: invokes.length };
  toasts.length = 0; invokes.length = 0;
  invokeResult = { data: { success: true }, error: null };
  await Twilio.test();
  out.testOk = { toast: toasts[toasts.length - 1], body: invokes[0] && invokes[0].body };
  State.tenant = { ...State.tenant, whatsapp_number: '123' };
  toasts.length = 0; invokes.length = 0;
  await Twilio.test();
  out.testBadNumber = { toast: toasts[toasts.length - 1], calls: invokes.length };
  State.tenant = { ...State.tenant, whatsapp_number: '0501234567' };

  // שמירת המספר
  toasts.length = 0; rpcs.length = 0;
  DB.tenantId = 'tenant-1';
  await Make.setWhatsApp('123');
  out.setBad = { rpcs: rpcs.length, toast: toasts[toasts.length - 1] };
  rpcs.length = 0; toasts.length = 0;
  await Make.setWhatsApp(' 050-123-4567 ');
  out.setOk = { rpc: rpcs[0], saved: State.tenant.whatsapp_number, local: localStorage.getItem('whatsapp_number'), toast: toasts[toasts.length - 1] };
  rpcs.length = 0; toasts.length = 0;
  rpcResult = { data: null, error: { code: '42501', message: 'insufficient permissions' } };
  State.tenant.whatsapp_number = '0509999999';
  await Make.setWhatsApp('0501234567');
  out.setForbidden = { toast: toasts[toasts.length - 1], unchanged: State.tenant.whatsapp_number === '0509999999', local: localStorage.getItem('whatsapp_number') };
  toasts.length = 0;
  rpcResult = { data: null, error: { code: '22023', message: 'invalid_whatsapp_number' } };
  await Make.setWhatsApp('0501234567');
  out.setServerInvalid = toasts[toasts.length - 1];
  toasts.length = 0;
  rpcResult = { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.update_tenant_integrations' } };
  await Make.setWhatsApp('0501234567');
  out.setNoMigration = { toast: toasts[toasts.length - 1], saved: State.tenant.whatsapp_number };

  sbClient.functions.invoke = origInvoke; sbClient.rpc = origRpc; window.toast = origToast;
  DB.tenantId = null;
  return out;
});

check(JSON.stringify(r.norm) === JSON.stringify(['+972501234567', '+972501234567', '+972501234567', '+972501234567', '+972501234567', null, null, null, null, null, null]), 'נרמול נייד ישראלי: תקין מתקבל בפורמט אחיד, והשאר נדחה');
check(r.noNumberCalls === 0, 'בלי מספר שמור: אף התראה לא יוצאת לשרת');
check(r.names.length === 5 && r.names.every(n => n === 'twilio-whatsapp'), 'חמש ההתראות עוברות דרך הפונקציה twilio-whatsapp');
check(JSON.stringify(r.bodies.map(b => b.event)) === JSON.stringify(['new_lead', 'stage_changed', 'deal_closed', 'tasks_due', 'cold_leads']), 'סוגי האירועים: ליד חדש, מעבר שלב, עסקה נסגרה, משימות, לידים קרים');
check(r.bodies[0].data.name === 'דנה' && r.bodies[3].data.count === 3 && r.bodies[4].data.count === 2 && r.bodies[1].data.stage === 'הצעה', 'הערכים הקטנים בלבד: שם, שלב וספירה');
check(!r.leak, 'לא יוצאים מהדפדפן מספר טלפון, הערות, תקציב, כותרות משימות, יעד או טקסט חופשי' + (r.leak ? ': ' + r.leak.join(',') : ''));
check(r.disabled.ok === false && r.disabled.error === 'whatsapp_disabled', 'קוד שגיאה מגוף התשובה: whatsapp_disabled');
check(r.unparsable.ok === false && r.unparsable.error === 'unknown' && r.demo.ok === false && r.demo.error === 'demo', 'תשובה שאי אפשר לפענח וגם דמו: בלי קריסה ובלי שליחה');
check(r.texts.slice(0, 6).every(t => t && !/[\/]|\bhttp/.test(t)) && /כבויה/.test(r.texts[0]) && /מגבלת/.test(r.texts[1]) && /נייד ישראלי/.test(r.texts[2]) && r.texts[6].includes('נכשלה'), 'הודעות שגיאה ברורות בעברית, בלי סלשים');
check(r.testDisabled.calls === 1 && /כבויה/.test(r.testDisabled.toast.m) && r.testDisabled.toast.t === 'info', 'כפתור הבדיקה כשהשרת כבוי: הודעה ברורה ולא שגיאה');
check(r.testOk.body.event === 'test' && /✅/.test(r.testOk.toast.m), 'כפתור הבדיקה: נשלח אירוע test בלבד');
check(r.testBadNumber.calls === 0 && /נייד ישראלי/.test(r.testBadNumber.toast.m), 'מספר שמור לא תקין: הבדיקה נעצרת בדפדפן עם הסבר');
check(r.setBad.rpcs === 0 && /נייד ישראלי/.test(r.setBad.toast.m), 'שמירת מספר לא תקין נעצרת בדפדפן');
check(r.setOk.rpc.fn === 'update_tenant_integrations' && r.setOk.rpc.args.p_whatsapp_number === '+972501234567' && r.setOk.saved === '+972501234567' && r.setOk.local === '+972501234567', 'שמירה: נשלח מספר בפורמט אחיד, ונשמר בעסק ובמקום');
check(/רק הבעלים/.test(r.setForbidden.toast.m) && r.setForbidden.unchanged && r.setForbidden.local === '+972501234567', 'אין הרשאה: הודעה ברורה, והמספר לא "נשמר" בשקר');
check(/נייד ישראלי/.test(r.setServerInvalid.m), 'דחייה של השרת על מספר לא תקין מוצגת למשתמש');
check(/נשמר/.test(r.setNoMigration.toast.m) && r.setNoMigration.saved === '0509999999', 'בלי מיגרציה 132 בסביבה: נשמר מקומית כמו עד היום, בלי לשנות את העסק');
check(errors.length === 0, 'אין שגיאות בקונסולה' + (errors.length ? ': ' + errors.join(' | ') : ''));
await close();
if (failures) { console.log(`\n${failures} בדיקות נכשלו`); process.exit(1); }
console.log('\nכל הבדיקות עברו');
