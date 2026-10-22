// מוודא שאין קריאת .catch() ישירות על builder של supabase-js (rpc או from).
// ב-supabase-js 2.x ה-builder תומך ב-then בלבד, ובקריאה ל-catch נזרקת TypeError לפני שהבקשה נשלחת.
// התיקון הנכון: .then(ok, fail), או await בתוך try/catch.
// הרצה: node --experimental-strip-types --test <path>   (PLTO_ROOT אופציונלי)
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const root = process.env.PLTO_ROOT ?? new URL('../../', import.meta.url).pathname;
const pages = readdirSync(root).filter((f) => f.endsWith('.html'));

// מחזיר את האינדקס שאחרי הסוגריים הסוגרים התואמים, או -1
function skipBalanced(src: string, open: number): number {
  let depth = 0, quote = '';
  for (let i = open; i < src.length; i++) {
    const ch = src[i];
    if (quote) { if (ch === '\\') i++; else if (ch === quote) quote = ''; continue; }
    if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
    if (ch === '(') depth++;
    if (ch === ')' && --depth === 0) return i + 1;
  }
  return -1;
}

export function findBuilderCatch(src: string): number[] {
  const hits: number[] = [];
  const start = /\b(?:sbClient|supabase|client)\s*\.\s*(?:rpc|from)\s*\(/g;
  let m: RegExpExecArray | null;
  while ((m = start.exec(src))) {
    let i = skipBalanced(src, m.index + m[0].length - 1);
    // עוברים על שרשרת השיטות: .select(...).eq(...)...
    while (i > 0) {
      const next = /^\s*\.\s*(\w+)\s*\(/.exec(src.slice(i));
      if (!next) break;
      if (next[1] === 'catch') { hits.push(src.slice(0, m.index).split('\n').length); break; }
      if (next[1] === 'then') break; // then(ok, fail) תקין, והתוצאה כבר Promise אמיתי
      i = skipBalanced(src, i + next[0].length - 1);
    }
  }
  return hits;
}

test('המזהה תופס את התבנית השגויה ולא תופס את התקינה', () => {
  assert.equal(findBuilderCatch("sbClient.rpc('x', { a: f(1) }).catch(() => {});").length, 1);
  assert.equal(findBuilderCatch("sbClient.from('t').select('*').eq('a', 1).catch(() => {});").length, 1);
  assert.equal(findBuilderCatch("await sbClient.rpc('x').catch(() => {});").length, 1);
  assert.equal(findBuilderCatch("sbClient.rpc('x').then(() => {}).catch(() => {});").length, 0);
  assert.equal(findBuilderCatch("sbClient.rpc('x').then(() => {}, () => {});").length, 0);
  assert.equal(findBuilderCatch("try { await sbClient.rpc('x'); } catch (_) {}").length, 0);
  assert.equal(findBuilderCatch("sbClient.functions.invoke('x').catch(() => {});").length, 0);
});

for (const file of pages) {
  test(`${file}: אין .catch() ישירות על builder של supabase`, () => {
    const lines = findBuilderCatch(readFileSync(join(root, file), 'utf8'));
    assert.deepEqual(lines, [], `${file}: .catch() על builder בשורות ${lines.join(', ')}. יש להשתמש ב-.then(ok, fail)`);
  });
}
