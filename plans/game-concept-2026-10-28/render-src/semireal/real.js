// Semi-realistic bakery (concept still). Assets: Poly Haven CC0 models + PBR textures. Units: 1u ~ 0.7m.
import { THREE, setup, env, sun, render, ground, marker, textTex } from '/render/common.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const q = new URLSearchParams(location.search);
const view = q.get('v') || 'wide', who = q.get('who') || 'mh', NOA_FILE = '/render/chars/noa_mh.glb';
const U = 1.43;                       // metres -> world units
const gl = new GLTFLoader(), texL = new THREE.TextureLoader(), mcache = new Map(), tcache = new Map();

function tex(id, kind, srgb = false) {
  const k = id + kind; if (!tcache.has(k)) { const t = texL.load(`/render/ph/tex/${id}/${kind}.jpg`); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; if (srgb) t.colorSpace = THREE.SRGBColorSpace; tcache.set(k, t); } return tcache.get(k);
}
// PBR material from a Poly Haven texture. tile = world size of one texture repeat (UVs are world-space, see worldUV).
function pbr(id, { tint = 0xffffff, rough = 1, nScale = 1, tile = 1.5 } = {}) {
  const m = new THREE.MeshStandardMaterial({ map: tex(id, 'diff', true), roughnessMap: tex(id, 'rough'), normalMap: tex(id, 'nor'), color: tint, roughness: rough, metalness: 0 });
  m.normalScale.set(nScale, nScale); m.userData.tile = tile; return m;
}
// painted surface: flat colour with the real surface's roughness + normal detail
function painted(id, color, { rough = 0.55, nScale = 0.5, tile = 2.2 } = {}) {
  const m = new THREE.MeshStandardMaterial({ color, roughnessMap: tex(id, 'rough'), normalMap: tex(id, 'nor'), roughness: rough, metalness: 0 });
  m.normalScale.set(nScale, nScale); m.userData.tile = tile; return m;
}
function worldUV(geo, tile) { // box-projected UVs in world units
  geo.computeVertexNormals(); const p = geo.attributes.position, n = geo.attributes.normal, uv = geo.attributes.uv;
  for (let i = 0; i < p.count; i++) { const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i)); let u, v;
    if (ay >= ax && ay >= az) { u = p.getX(i); v = p.getZ(i); } else if (ax >= az) { u = p.getZ(i); v = p.getY(i); } else { u = p.getX(i); v = p.getY(i); }
    uv.setXY(i, u / tile, v / tile); } uv.needsUpdate = true; return geo;
}
function box(w, h, d, mat, x, y, z, parent) { const g = worldUV(new THREE.BoxGeometry(w, h, d), mat.userData.tile || 1); const m = new THREE.Mesh(g, mat); m.position.set(x, y, z); m.castShadow = m.receiveShadow = true; parent.add(m); return m; }
async function model(id, { s = 1, x = 0, y = 0, z = 0, ry = 0, parent, tint } = {}) {
  if (!mcache.has(id)) mcache.set(id, gl.loadAsync(`/render/ph/models/${id}/${id}.gltf`));
  const o = (await mcache.get(id)).scene.clone(true);
  o.traverse(m => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; if (tint) { m.material = m.material.clone(); m.material.color.multiply(new THREE.Color(tint)); } } });
  const g = new THREE.Group(); g.add(o); g.scale.setScalar(s * U); g.position.set(x, y, z); g.rotation.y = ry; parent.add(g); return g;
}
const glassMat = new THREE.MeshPhysicalMaterial({ color: 0xcfe9f5, roughness: 0.04, metalness: 0, transparent: true, opacity: 0.07, envMapIntensity: 0.7, depthWrite: false });
const flat = (c, r = 0.7, extra = {}) => new THREE.MeshStandardMaterial({ color: c, roughness: r, ...extra });

// ---------- scene ----------
const ctx = setup({ bg: 0x9bd27a, exposure: 1.02 });
const { scene } = ctx;
await env(ctx.renderer, scene, 0.42);
ground(scene, 0x9bd27a).position.y = -0.32;
scene.add(new THREE.HemisphereLight(0xfff1de, 0x8a7a5a, 0.3));
sun(scene, { pos: [11, 16, 12], size: 16, intensity: 3.2, color: 0xffe2b8 });
const W = new THREE.Group(); scene.add(W);

const woodFloor = pbr('wood_floor', { tint: 0xfff3dc, tile: 2.6, nScale: 0.6 });
const tileWall = pbr('square_tiled_wall', { tint: 0x35b7a6, tile: 1.6, nScale: 0.8 });
const plaster = painted('plastered_wall_04', 0xf3bf9a, { rough: 0.9, nScale: 0.7, tile: 3.0 });
const marble = pbr('terrazzo_tiles', { tint: 0xffffff, tile: 4.5, nScale: 0.4 });
const cabWood = painted('kitchen_wood', 0x2fb3a2, { rough: 0.5, nScale: 0.5 });   // painted teal cabinets
const cabCoral = painted('kitchen_wood', 0xff7a59, { rough: 0.5, nScale: 0.5 });
const cabCream = painted('kitchen_wood', 0xf7e4cc, { rough: 0.55, nScale: 0.5 });
const trim = flat(0xfff6ea, 0.55);

// floor
box(12.6, 0.3, 8.6, woodFloor, 0, -0.15, 0, W);

// walls: back (z=-4.25), left (x=-6.25), right half-height (x=6.25)
function wallRun(len, h, mat1, mat2, x, z, ry, tileH = 1.65) {
  const g = new THREE.Group(); g.position.set(x, 0, z); g.rotation.y = ry; W.add(g);
  box(len, tileH, 0.5, mat1, 0, tileH / 2, 0, g);
  if (h > tileH) box(len, h - tileH, 0.5, mat2, 0, tileH + (h - tileH) / 2, 0, g);
  box(len, 0.12, 0.6, trim, 0, tileH, 0.02, g);              // chair rail
  box(len, 0.28, 0.58, trim, 0, 0.14, 0.02, g);              // skirting
  if (h > tileH) box(len, 0.22, 0.62, trim, 0, h - 0.11, 0.02, g); // crown
  return g;
}
wallRun(13.2, 4.2, tileWall, plaster, 0, -4.25, 0);
wallRun(8.6, 4.2, tileWall, plaster, -6.25, 0, Math.PI / 2);
wallRun(8.6, 1.65, tileWall, plaster, 6.25, 0, Math.PI / 2);

// window in the left wall (frame + bright sky card behind)
{ const g = new THREE.Group(); g.position.set(-5.97, 2.5, 1.3); W.add(g);
  const sky = new THREE.Mesh(new THREE.PlaneGeometry(2.2, 1.7), new THREE.MeshBasicMaterial({ color: 0xcfeaff })); sky.rotation.y = Math.PI / 2; sky.position.x = -0.04; g.add(sky);
  const fm = flat(0xfff6ea, 0.5);
  for (const [w, h, y, z] of [[0.12, 0.14, 0.9, 0], [0.12, 0.14, -0.9, 0]]) box(w, h, 2.5, fm, 0, y, z, g);
  for (const z of [-1.2, 0, 1.2]) box(0.12, 1.9, 0.1, fm, 0, 0, z, g);
  box(0.12, 0.1, 2.4, fm, 0, 0, 0, g);
  box(0.3, 0.1, 2.7, fm, 0.1, -0.98, 0, g); }

// ---------- kitchen run along the back wall ----------
const cabY = 1.28;
function cabinet(x, w, z = -3.5, d = 1.0, tint) {
  const mat = tint || cabWood;
  box(w, cabY, d, mat, x, cabY / 2, z, W); box(w + 0.06, 0.07, d + 0.08, marble, x, cabY + 0.035, z + 0.02, W);
  const nd = Math.max(1, Math.round(w / 1.0)); // door seams + knobs
  for (let i = 0; i < nd; i++) { const cx = x - w / 2 + (i + 0.5) * w / nd; box(0.03, cabY * 0.8, 0.03, flat(0x8a4a30, 0.6), cx - w / nd / 2 + 0.01, cabY / 2, z + d / 2 + 0.01, W);
    const kn = new THREE.Mesh(new THREE.SphereGeometry(0.05, 12, 8), flat(0xf0b44c, 0.25, { metalness: 0.85 })); kn.position.set(cx + 0.18, cabY * 0.78, z + d / 2 + 0.05); kn.castShadow = true; W.add(kn); }
}
cabinet(-4.9, 2.4); cabinet(-2.5, 2.4); cabinet(2.55, 2.0, -3.5, 1.0, cabCoral);
cabinet(-0.65, 1.3); cabinet(1.18, 0.86);
await model('electric_stove', { s: 1.1, x: 0.35, y: 0, z: -3.45, ry: 0, parent: W });
// hood
{ const hd = new THREE.Group(); hd.position.set(0.35, 0, -3.7); W.add(hd);
  const steel = flat(0xcfd3d8, 0.28, { metalness: 0.9 });
  const cone = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.95, 0.8, 4, 1, true), steel); cone.rotation.y = Math.PI / 4; cone.scale.set(1, 1, 0.8); cone.position.y = 3.55; cone.castShadow = true; hd.add(cone);
  box(0.4, 1.0, 0.4, steel, 0, 4.4 - 0.2, -0.1, hd); }
// upper cabinets + shelves
box(2.4, 1.3, 0.6, cabCream, -3.7, 3.25, -3.7, W);
box(2.0, 0.1, 0.55, cabWood, 3.0, 3.1, -3.72, W);
box(2.0, 0.1, 0.55, cabWood, 3.0, 2.4, -3.72, W);

// ---------- props on the counters ----------
const top = cabY + 0.07;
await model('vintage_electric_kettle', { x: 1.45, y: top + 0.0, z: -3.45, ry: 2.5, s: 1.0, parent: W });
await model('brass_pot_01', { x: 0.2, y: 1.37, z: -3.4, parent: W, s: 1.0 });
await model('pot_enamel_01', { x: -4.2, y: top, z: -3.5, ry: 0.6, s: 1.3, parent: W });
await model('wooden_cutting_board', { x: -3.3, y: top, z: -3.4, ry: 0.15, s: 1.4, parent: W });
await model('croissant', { x: -3.45, y: top + 0.06, z: -3.38, ry: 0.5, s: 1.6, parent: W });
await model('croissant', { x: -3.1, y: top + 0.06, z: -3.42, ry: 2.2, s: 1.6, parent: W });
await model('wooden_bowl_01', { x: -2.2, y: top, z: -3.45, s: 1.3, parent: W });
await model('lemon', { x: -2.2, y: top + 0.14, z: -3.45, s: 1.6, parent: W });
await model('lemon', { x: -2.12, y: top + 0.1, z: -3.5, ry: 1, s: 1.6, parent: W });
await model('ceramic_vase_01', { x: -5.7, y: top, z: -3.7, s: 1.2, parent: W });
await model('metal_jug', { x: 2.2, y: top, z: -3.7, s: 1.3, parent: W });
await model('tea_set_01', { x: 3.1, y: top, z: -3.45, ry: 0.1, s: 1.2, parent: W });
await model('wicker_basket_01', { x: 3.0, y: 2.5, z: -3.7, s: 1.4, parent: W });
await model('croissant', { x: 3.0, y: 2.62, z: -3.7, s: 1.7, parent: W });
await model('carrot_cake', { x: 3.5, y: 3.2, z: -3.72, s: 1.5, parent: W });
await model('vintage_cabinet_01', { x: 5.0, y: 0, z: -3.65, ry: 0, s: 0.85, parent: W }); // corner dresser, right of the fridge position

// ---------- display island (same place as the stylized version) ----------
{ const g = new THREE.Group(); g.position.set(-1.6, 0, -0.4); W.add(g);
  box(4.2, 1.22, 1.2, cabCream, 0, 0.61, 0, g);
  box(4.3, 0.08, 1.3, marble, 0, 1.26, 0, g);
  box(4.3, 0.1, 1.4, flat(0xff7a59, 0.5), 0, 0.05, 0, g);
  const gl2 = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.86, 1.05), glassMat); gl2.position.set(-1.05, 1.74, 0); g.add(gl2);

  for (const sx of [-2.07, -0.03]) for (const sz of [-0.52, 0.52]) box(0.04, 0.9, 0.04, flat(0xfff6ea, 0.4), sx, 1.74, sz, g);
  await model('strawberry_chocolate_cake', { x: -1.6, y: 1.31, z: 0, s: 1.5, parent: g });
  await model('carrot_cake', { x: -0.6, y: 1.31, z: 0, s: 1.5, parent: g });
  await model('croissant', { x: -1.1, y: 1.52, z: 0.18, s: 1.7, parent: g });
  // second-level shelf with croissants on a board
  await model('wooden_cutting_board', { x: -1.1, y: 1.46, z: 0.0, s: 1.25, parent: g });
  await model('wicker_basket_01', { x: 1.7, y: 1.3, z: 0.15, s: 1.5, parent: g });
  await model('croissant', { x: 1.7, y: 1.42, z: 0.15, ry: 1, s: 1.7, parent: g });
  await model('croissant', { x: 1.95, y: 1.4, z: 0.0, ry: 3, s: 1.7, parent: g });
}
// the cake Noa is decorating (same spot as before: x=-0.4 on the counter edge)
await model('carrot_cake', { x: -0.45, y: 1.3, z: -0.2, s: 2.0, parent: W });

// ---------- seating area ----------
await model('round_wooden_table_01', { x: 3.6, y: 0, z: 1.6, s: 0.8, parent: W, tint: 0xffe2c8 });
await model('painted_wooden_chair_01', { x: 3.6, y: 0, z: 2.85, ry: Math.PI, s: 1.15, parent: W, tint: 0x53d6c5 });
await model('painted_wooden_chair_01', { x: 4.95, y: 0, z: 1.6, ry: -Math.PI / 2, s: 1.15, parent: W, tint: 0xffb36b });
await model('tea_set_01', { x: 3.6, y: 1.16, z: 1.6, ry: 0.3, s: 0.8, parent: W });
await model('standing_chalkboard_01', { x: 5.4, y: 0, z: 3.2, ry: -2.5, s: 1.1, parent: W });
await model('potted_plant_02', { x: -5.2, y: 0, z: 3.2, ry: 1.2, s: 1.35, parent: W });
await model('planter_box_01', { x: -5.2, y: 0.0, z: -0.8, ry: Math.PI / 2, s: 1.3, parent: W });
await model('fancy_picture_frame_01', { x: 0.0, y: 3.1, z: -3.97, s: 1.5, parent: W });
await model('fancy_picture_frame_01', { x: -5.97, y: 3.4, z: -1.6, ry: Math.PI / 2, s: 1.3, parent: W });
await model('wooden_display_shelves_01', { x: -5.6, y: 0, z: 1.0 + 0.9, ry: Math.PI / 2, s: 1.35, parent: W }); // wall display unit
// rug (own procedural art: woven stripes)
{ const c = document.createElement('canvas'); c.width = 512; c.height = 512; const x = c.getContext('2d'); const cols = ['#ff7a59', '#fff6ea', '#35b7a6', '#f5b83d'];
  for (let i = 0; i < 16; i++) { x.fillStyle = cols[i % 4]; x.fillRect(0, i * 32, 512, 32); } x.fillStyle = 'rgba(255,255,255,.08)'; for (let i = 0; i < 512; i += 4) x.fillRect(i, 0, 2, 512);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  const r = new THREE.Mesh(new THREE.BoxGeometry(3.2, 0.04, 2.0), new THREE.MeshStandardMaterial({ map: t, roughness: 1 })); r.position.set(1.6, 0.02, 2.3); r.receiveShadow = true; W.add(r); }

// ---------- lights ----------
function pendant(x, z, y = 3.6, col = 0xffc24d) {
  const g = new THREE.Group(); g.position.set(x, 0, z); W.add(g);
  const m = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 4.2 - y, 6), flat(0x222222)); m.position.y = (4.2 + y) / 2; g.add(m);
  const sh = new THREE.Mesh(new THREE.SphereGeometry(0.42, 28, 14, 0, Math.PI * 2, 0, Math.PI * 0.55), flat(col, 0.35, { metalness: 0.3, side: THREE.DoubleSide })); sh.position.y = y; sh.castShadow = true; g.add(sh);
  const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.14, 16, 12), new THREE.MeshStandardMaterial({ color: 0xfff2c9, emissive: 0xffd889, emissiveIntensity: 4 })); bulb.position.set(0, y - 0.1, 0); g.add(bulb);
  const l = new THREE.PointLight(0xffc98a, 9, 11, 1.7); l.position.y = y - 0.3; g.add(l);
}
pendant(-2.6, -0.4); pendant(-0.2, -0.4); pendant(3.6, 1.6, 3.5, 0x35b7a6);

// ---------- Noa ----------
let noa = null;
if (who === 'mh') { noa = (await gl.loadAsync(NOA_FILE)).scene; noa.traverse(m => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; const mt = m.material; const cut = /hair|ponytail|eyebrow|eyelash|high-poly|eye/i.test(m.name + mt.name); mt.transparent = false; mt.depthWrite = true; mt.alphaTest = cut ? 0.5 : 0; mt.side = cut ? THREE.DoubleSide : THREE.FrontSide; mt.needsUpdate = true; } }); }
if (noa) { noa.scale.setScalar(1.6); noa.position.set(-0.4, 0.02, -1.75); noa.rotation.y = 0.45; scene.add(noa); }
const mk = marker(); mk.position.set(-0.4, 0.03, -1.75); mk.scale.setScalar(1.3); scene.add(mk);

// ---------- chalkboard text ----------
// (rendered after we know where the board face is: placed as a small plane in front of the model)
{ const t = await textTex('העוגה של היום', { w: 640, h: 360, bg: null, fg: '#FFF6EA', font: '900 70px Heebo', sub: 'הר געש · 320 ₪', subFont: '700 54px Heebo', subColor: '#F5B83D' });
  const p = new THREE.Mesh(new THREE.PlaneGeometry(0.95, 0.53), new THREE.MeshBasicMaterial({ map: t, transparent: true })); p.position.set(5.4, 1.62, 3.2); p.rotation.y = -2.5 + Math.PI; p.name = 'chalk'; p.userData.skip = true; W.add(p); window.__chalk = p; }

// ---------- camera (identical to the stylized scene) ----------
const cam = new THREE.PerspectiveCamera(view === 'wide' ? 34 : 22, ctx.w / ctx.h, 0.05, 200);
if (view === 'wide') { cam.position.set(7.5, 12.5, 15.5); cam.lookAt(-0.6, 0.6, 0.2); } else { cam.position.set(1.6, 3.1, 3.4); cam.lookAt(-0.45, 1.85, -1.75); }
ctx.camera = cam;
const b = new THREE.Box3().setFromObject(noa || W); window.__out = 'noa bbox ' + b.min.toArray().map(v => v.toFixed(2)) + ' / ' + b.max.toArray().map(v => v.toFixed(2));
await render(ctx, { ao: true, bloom: 0.25 });
let tris = 0; const seen = new Set(); scene.traverse(m => { if (m.isMesh && m.visible) { const g = m.geometry; tris += (g.index ? g.index.count : g.attributes.position.count) / 3; } });
window.__out += ' | scene_tris ' + Math.round(tris) + ' | tris ' + ctx.renderer.info.render.triangles + ' | textures ' + ctx.renderer.info.memory.textures + ' | geometries ' + ctx.renderer.info.memory.geometries + ' | calls ' + ctx.renderer.info.render.calls;
window.__ready = true;
