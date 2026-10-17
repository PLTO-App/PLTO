// בדיקת תחביר לבלוקי ה-<script> הפנימיים בקבצי ה-HTML של האתר.
// הקוד לא מורץ, רק מנותח. שימוש: node scripts/check-inline-js.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const files = readdirSync(root).filter(f => f.endsWith('.html')).sort();
const SCRIPT_RE = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
const JS_TYPES = new Set(['', 'text/javascript', 'application/javascript']);

let blocks = 0;
let failures = 0;

for (const file of files) {
  // הערות HTML עשויות להכיל את הטקסט <script>, ולכן מרוקנים אותן ושומרים את מספרי השורות.
  const html = readFileSync(join(root, file), 'utf8')
    .replace(/<!--[\s\S]*?-->/g, c => c.replace(/[^\n]/g, ' '));
  for (const m of html.matchAll(SCRIPT_RE)) {
    const attrs = m[1];
    if (/\bsrc\s*=/.test(attrs)) continue;
    const type = (attrs.match(/\btype\s*=\s*["']?([^"'\s>]+)/i)?.[1] || '').toLowerCase();
    if (type === 'module') continue;
    if (!JS_TYPES.has(type)) continue;
    const code = m[2];
    if (!code.trim()) continue;
    // השורה שבה מתחיל הקוד בקובץ ה-HTML, כדי ששגיאה תצביע על מיקום אמיתי.
    const startLine = html.slice(0, m.index + m[0].indexOf('>') + 1).split('\n').length;
    blocks++;
    try {
      new vm.Script(code, { filename: file, lineOffset: startLine - 1 });
    } catch (e) {
      failures++;
      console.error(`${file}: ${e.name}: ${e.message}`);
      const at = String(e.stack || '').split('\n').find(l => l.startsWith(file + ':'));
      if (at) console.error('  ' + at);
    }
  }
}

console.log(`נבדקו ${blocks} בלוקים ב-${files.length} קבצים, ${failures} שגיאות`);
process.exit(failures ? 1 : 0);
