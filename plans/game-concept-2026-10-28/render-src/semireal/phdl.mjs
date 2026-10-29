import fs from 'node:fs'; import path from 'node:path';
const [,, root, kind, ...ids] = process.argv;
async function get(u, out) { fs.mkdirSync(path.dirname(out), { recursive: true }); if (fs.existsSync(out)) return; const r = await fetch(u); if (!r.ok) throw new Error(u + ' ' + r.status); fs.writeFileSync(out, Buffer.from(await r.arrayBuffer())); }
for (const id of ids) {
  try {
    const f = await (await fetch(`https://api.polyhaven.com/files/${id}`)).json();
    const info = await (await fetch(`https://api.polyhaven.com/info/${id}`)).json();
    fs.mkdirSync(`${root}/${kind}/${id}`, { recursive: true });
    fs.writeFileSync(`${root}/${kind}/${id}/info.json`, JSON.stringify({ name: info.name, authors: info.authors, type: info.type }));
    if (kind === 'models') {
      const g = f.gltf['1k'].gltf; await get(g.url, `${root}/models/${id}/${id}.gltf`);
      for (const [p, v] of Object.entries(g.include)) await get(v.url, `${root}/models/${id}/${p}`);
    } else {
      for (const [k, n] of [['Diffuse', 'diff'], ['Rough', 'rough'], ['nor_gl', 'nor']]) await get(f[k]['1k'].jpg.url, `${root}/tex/${id}/${n}.jpg`);
    }
    console.log('ok', id);
  } catch (e) { console.log('FAIL', id, e.message); }
}
