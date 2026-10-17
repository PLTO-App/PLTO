// מדידת זמן רינדור של הפייפליין והרשימה עם נפח גדול של לידים ומשימות (Supabase מדומה).
// שימוש: node scripts/perf-render.mjs [leads] [tasks]
// להשוואה לגרסה אחרת: PLTO_ROOT=/נתיב/לתיקייה/עם/index.html node scripts/perf-render.mjs
import { startHarness } from './lib/harness.mjs';

const N = Number(process.argv[2]) || 500;
const T = Number(process.argv[3]) || 300;
const { page, close } = await startHarness({ root: process.env.PLTO_ROOT || undefined });

const res = await page.evaluate(({ N, T }) => {
  const stages = State.stages;
  State.leads = Array.from({ length: N }, (_, i) => ({
    id: 'p' + i, name: 'ליד ' + i, phone: '050-' + String(1000000 + i), phone2: '', email: '', stage: stages[i % stages.length].id,
    source: 'other', budget_min: 100000 + i, budget_max: 200000 + i, desired_area: 'עיר ' + (i % 30), score: i % 100,
    lead_role: 'buyer', notes: '', tags: [], created_at: today(), last_contact: null,
  }));
  State.tasks = Array.from({ length: T }, (_, i) => ({ id: 'tk' + i, title: 'משימה ' + i, type: 'call', priority: 'medium', due: addDays(i % 9 - 3), done: false, lead_id: 'p' + (i % N), notes: '' }));
  const median = a => a.sort((x, y) => x - y)[Math.floor(a.length / 2)];
  const time = (fn, runs = 7) => { const t = []; for (let i = 0; i < runs; i++) { const s = performance.now(); fn(); t.push(performance.now() - s); } return Math.round(median(t) * 10) / 10; };
  const out = {};
  App.go('pipeline');
  out.pipelineRenderMs = time(() => Pipeline.render());
  out.pipelineSearchMs = time(() => Pipeline.search('ליד 4'));
  Pipeline.search('');
  App.go('leads');
  out.leadsRenderMs = time(() => Leads.render());
  out.leadsSearchMs = time(() => Leads.search('ליד 4'));
  Leads.search('');
  out.domNodesPipeline = (App.go('pipeline'), document.querySelectorAll('#pipeline-board *').length);
  out.domNodesLeads = (App.go('leads'), document.querySelectorAll('#leads-list-container *').length);
  return out;
}, { N, T });

console.log(`לידים: ${N}, משימות: ${T}, ויוופורט 390px`);
console.log(JSON.stringify(res, null, 1));
await close();
