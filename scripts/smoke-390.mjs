// בדיקת עשן מקומית ב-390px: נכנסת למצב דמו ועוברת על מסכי האפליקציה. בודקת שגיאות JS,
// גלישה אופקית, חפיפה בין כפתורים צפים ונראות כפתור ההוספה.
// שימוש: node scripts/smoke-390.mjs [תיקיית צילומי מסך]
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { startHarness } from './lib/harness.mjs';

const shotsDir = process.argv[2] || '';
if (shotsDir) mkdirSync(shotsDir, { recursive: true });
const { page, errors, close } = await startHarness();

const FAB_EXPECTED = new Set(['dashboard', 'pipeline', 'leads', 'properties', 'tasks']);
const SCREENS = ['dashboard', 'pipeline', 'leads', 'lead-detail', 'properties', 'tasks', 'calendar', 'analytics', 'partners', 'tools', 'settings'];

const results = [];
for (const screen of SCREENS) {
  const before = errors.length;
  await page.evaluate(s => {
    if (s === 'lead-detail') App.go('lead-detail', { currentLeadId: State.leads[0]?.id });
    else App.go(s);
  }, screen);
  await page.waitForTimeout(500);
  const m = await page.evaluate(() => ({
    scrollW: document.documentElement.scrollWidth,
    innerW: window.innerWidth,
    // אלמנט מחוץ למסך נחשב ליקוי רק אם אין לו אב עם גלילה אופקית מכוונת (רצועות KPI, טאבים וכד')
    wide: [...document.querySelectorAll('.screen:not(.hidden) *')]
      .filter(e => {
        const r = e.getBoundingClientRect();
        if (r.width === 0 || (r.right <= window.innerWidth + 1 && r.left >= -1)) return false;
        for (let p = e.parentElement; p && !p.classList.contains('screen'); p = p.parentElement) {
          if (/(auto|scroll|hidden)/.test(getComputedStyle(p).overflowX)) return false;
        }
        return true;
      })
      .slice(0, 3).map(e => (e.id ? '#' + e.id : e.className && typeof e.className === 'string' ? '.' + e.className.split(' ')[0] : e.tagName)),
  }));
  const overflow = m.scrollW > m.innerW;
  // כפתורים צפים: כפתור ההוספה רק במסכים המיועדים, ושום זוג לא חופף
  const floats = await page.evaluate(() => {
    const rects = ['#fab-btn', '#support-fab-btn', '#a11y-fab']
      .map(sel => { const e = document.querySelector(sel); if (!e || getComputedStyle(e).display === 'none') return null; const r = e.getBoundingClientRect(); return { sel, l: r.left, r: r.right, t: r.top, b: r.bottom }; })
      .filter(Boolean);
    const overlaps = [];
    for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
      const a = rects[i], b = rects[j];
      if (a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b) overlaps.push(a.sel + ' מול ' + b.sel);
    }
    return { fab: rects.some(r => r.sel === '#fab-btn'), overlaps };
  });
  const fabWrong = floats.fab !== FAB_EXPECTED.has(screen);
  results.push({ screen, overflow, wide: m.wide, newErrors: errors.length - before, floatIssues: [...floats.overlaps, ...(fabWrong ? [floats.fab ? 'כפתור הוספה לא צריך להופיע' : 'כפתור הוספה חסר'] : [])] });
  if (shotsDir) await page.screenshot({ path: join(shotsDir, `${screen}.png`) });
}

await close();

let bad = 0;
for (const r of results) {
  const flags = [];
  if (r.overflow) flags.push('גלישה אופקית בדף');
  if (r.wide.length) flags.push(`אלמנטים מחוץ למסך: ${r.wide.join(', ')}`);
  if (r.newErrors) flags.push(`${r.newErrors} שגיאות JS`);
  if (r.floatIssues.length) flags.push(`כפתורים צפים: ${r.floatIssues.join(', ')}`);
  if (flags.length) bad++;
  console.log(`${flags.length ? '✗' : '✓'} ${r.screen}${flags.length ? ': ' + flags.join(' | ') : ''}`);
}
if (errors.length) console.log('\nשגיאות:\n' + [...new Set(errors)].map(e => '  ' + e).join('\n'));
console.log(`\n${results.length - bad}/${results.length} מסכים נקיים`);
process.exit(bad || errors.length ? 1 : 0);
