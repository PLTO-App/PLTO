import fs from 'node:fs'; import path from 'node:path';
const S = process.argv[2];
const packs = { 'City-Builder-Bits':'kaykit_city_builder_bits', 'Restaurant-Bits':'kaykit_restaurant_bits', 'Furniture-Bits':'kaykit_furniture_bits' };
let total = 0;
for (const [p, dir] of Object.entries(packs)) {
  const j = JSON.parse(fs.readFileSync(`${S}/assets-meta/${p}.json`, 'utf8'));
  const files = j.files.filter(f => f.name.startsWith(`/addons/${dir}/Assets/gltf/`));
  for (const f of files) {
    const out = path.join(S, 'dl/kaykit', p, path.basename(f.name));
    if (fs.existsSync(out)) continue;
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const r = await fetch(`https://cdn.jsdelivr.net/gh/KayKit-Game-Assets/KayKit-${p}-1.0@main${f.name}`);
    if (!r.ok) { console.log('fail', f.name, r.status); continue; }
    const b = Buffer.from(await r.arrayBuffer()); fs.writeFileSync(out, b); total += b.length;
  }
  console.log(p, files.length);
}
console.log('MB', (total/1e6).toFixed(1));
