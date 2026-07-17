// Syntax-checks every inline <script> block (no src=) in the given HTML
// file(s), one vm.Script compile per block. This mirrors how a browser's
// HTML tokenizer actually splits script content (it also terminates at the
// first literal "</script", regardless of JS string/comment context) — more
// accurate than guessing line ranges by hand, which broke once already (see
// CLAUDE.md, session 17/7/2026 QA notes).
const fs = require('fs');
const vm = require('vm');

const files = process.argv.slice(2);
if (!files.length) {
  console.error('שימוש: node qa/check_syntax.js index.html admin.html landing.html');
  process.exit(2);
}

let anyFail = false;

for (const file of files) {
  // Strip HTML comments first — index.html has doc comments that mention
  // "<script>" in prose (e.g. "placed before the main <script> block"),
  // which would otherwise be mistaken for a real opening tag and throw off
  // the block boundaries for everything after it.
  const html = fs.readFileSync(file, 'utf8').replace(/<!--[\s\S]*?-->/g, m => ' '.repeat(m.length));
  const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let m, count = 0, fail = 0;
  while ((m = re.exec(html))) {
    count++;
    const code = m[1];
    if (!code.trim()) continue;
    try {
      new vm.Script(code, { filename: `${file}#block${count}` });
    } catch (e) {
      fail++;
      anyFail = true;
      const offset = html.slice(0, m.index).split('\n').length;
      console.log(`❌ ${file} block #${count} (מתחיל בערך בשורה ${offset}): ${e.message}`);
    }
  }
  if (fail === 0) console.log(`✅ ${file} — ${count} בלוקי script, כולם תקינים`);
}

process.exit(anyFail ? 1 : 0);
