// World builders for the concept stills. Units: restaurant pack scale (1u ~ 0.75m).
import { THREE, model, place, character, textTex } from '/render/common.js';

export const CITY = 6.4; // city pack -> restaurant scale
const std = (color, rough = 0.8, extra = {}) => new THREE.MeshStandardMaterial({ color, roughness: rough, ...extra });
const mesh = (g, m, x = 0, y = 0, z = 0) => { const o = new THREE.Mesh(g, m); o.position.set(x, y, z); o.castShadow = o.receiveShadow = true; return o; };

export function tree(scale = 1, tint = 0x5fae4f) {
  const g = new THREE.Group();
  g.add(mesh(new THREE.CylinderGeometry(0.18, 0.28, 2.6, 10), std(0x7a5236, 0.9), 0, 1.3, 0));
  const leaf = std(tint, 0.85, { flatShading: true });
  [[0, 3.4, 0, 1.5], [0.8, 3.0, 0.3, 1.0], [-0.7, 3.1, -0.3, 1.1], [0.1, 4.2, 0.1, 1.0], [-0.3, 3.0, 0.8, 0.9]].forEach(([x, y, z, r]) =>
    g.add(mesh(new THREE.IcosahedronGeometry(r, 1), leaf, x, y, z)));
  g.scale.setScalar(scale); return g;
}

export function planter(x, z, color = 0xe07a5f) {
  const g = new THREE.Group(); g.position.set(x, 0, z);
  g.add(mesh(new THREE.CylinderGeometry(0.45, 0.35, 0.7, 16), std(color, 0.7), 0, 0.35, 0));
  const leaf = std(0x4f9d4a, 0.8, { flatShading: true });
  for (let i = 0; i < 5; i++) g.add(mesh(new THREE.IcosahedronGeometry(0.35, 0), leaf, Math.cos(i) * 0.2, 0.9 + (i % 2) * 0.2, Math.sin(i) * 0.2));
  return g;
}

// ---- cakes ----
export function cake({ tiers = 2, base = 0xf7d6e0, cream = 0xffffff, accent = 0xff6b8b, r = 0.45, h = 0.32, dino = false, candles = 0 } = {}) {
  const g = new THREE.Group(); let y = 0;
  g.add(mesh(new THREE.CylinderGeometry(r * 1.3, r * 1.3, 0.04, 32), std(0xf2f2f2, 0.2, { metalness: 0.4 }), 0, 0.02, 0)); y = 0.04;
  for (let t = 0; t < tiers; t++) {
    const rr = r * (1 - t * 0.28);
    g.add(mesh(new THREE.CylinderGeometry(rr, rr, h, 40), std(base, 0.55), 0, y + h / 2, 0));
    const ring = mesh(new THREE.TorusGeometry(rr, 0.035, 10, 40), std(cream, 0.4), 0, y + h, 0); ring.rotation.x = Math.PI / 2; g.add(ring);
    for (let i = 0; i < 12; i++) { const a = i / 12 * Math.PI * 2; g.add(mesh(new THREE.SphereGeometry(0.035, 10, 8), std(accent, 0.3), Math.cos(a) * rr * 0.98, y + h * 0.45, Math.sin(a) * rr * 0.98)); }
    y += h;
  }
  if (dino) {
    const v = mesh(new THREE.ConeGeometry(0.28, 0.42, 20), std(0x6b3e26, 0.6), 0, y + 0.21, 0); g.add(v);
    g.add(mesh(new THREE.SphereGeometry(0.1, 12, 8), std(0xff5a1f, 0.3, { emissive: 0xff4400, emissiveIntensity: 1.2 }), 0, y + 0.42, 0));
    for (const [x, z, s] of [[0.32, 0.1, 1], [-0.3, 0.15, 0.8]]) {
      const d = new THREE.Group(); d.position.set(x, y, z); d.scale.setScalar(s);
      const dm = std(0x58c26b, 0.5);
      d.add(mesh(new THREE.CapsuleGeometry(0.06, 0.12, 6, 10), dm, 0, 0.1, 0)); d.children.at(-1).rotation.z = Math.PI / 2;
      d.add(mesh(new THREE.CapsuleGeometry(0.03, 0.14, 6, 8), dm, -0.06, 0.2, 0)); d.children.at(-1).rotation.z = -0.4;
      d.add(mesh(new THREE.SphereGeometry(0.05, 10, 8), dm, -0.1, 0.29, 0));
      g.add(d);
    }
  }
  for (let i = 0; i < candles; i++) {
    const a = i / candles * Math.PI * 2, rr = r * 0.5;
    g.add(mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.18, 8), std(0x7fc8ff, 0.4), Math.cos(a) * rr, y + 0.09, Math.sin(a) * rr));
    g.add(mesh(new THREE.SphereGeometry(0.025, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd36b }), Math.cos(a) * rr, y + 0.21, Math.sin(a) * rr));
  }
  return g;
}

export function displayCase(x, z, w = 3.6) {
  const g = new THREE.Group(); g.position.set(x, 0, z);
  g.add(mesh(new THREE.BoxGeometry(w, 1.0, 1.2), std(0xf3e9dc, 0.6), 0, 0.5, 0));
  g.add(mesh(new THREE.BoxGeometry(w + 0.1, 0.06, 1.3), std(0x8a5a3b, 0.5), 0, 1.03, 0));
  const glass = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.05, transmission: 0.9, thickness: 0.05, transparent: true, opacity: 0.25 });
  g.add(mesh(new THREE.BoxGeometry(w, 0.9, 1.1), glass, 0, 1.5, 0)); g.children.at(-1).castShadow = false;
  const cakes = [
    cake({ tiers: 2, base: 0xf7d6e0, accent: 0xff6b8b }),
    cake({ tiers: 1, base: 0x6b3e26, cream: 0xf5e6c8, accent: 0xd94f4f, r: 0.38 }),
    cake({ tiers: 3, base: 0xfff3d6, accent: 0xf5b83d, r: 0.4, h: 0.22 }),
  ];
  cakes.forEach((c, i) => { c.position.set((i - 1) * (w / 3.2), 1.06, 0); c.scale.setScalar(0.8); g.add(c); });
  return g;
}

export function pendant(x, y, z, color = 0xf5b83d) {
  const g = new THREE.Group(); g.position.set(x, y, z);
  g.add(mesh(new THREE.CylinderGeometry(0.01, 0.01, 1.2, 4), std(0x222222), 0, 0.6, 0));
  const shade = mesh(new THREE.ConeGeometry(0.35, 0.35, 24, 1, true), std(color, 0.5, { side: THREE.DoubleSide }), 0, 0, 0); g.add(shade);
  g.add(mesh(new THREE.SphereGeometry(0.1, 12, 8), new THREE.MeshStandardMaterial({ color: 0xfff2c9, emissive: 0xffd889, emissiveIntensity: 3 }), 0, -0.12, 0));
  const l = new THREE.PointLight(0xffc98a, 6, 9, 1.6); l.position.y = -0.3; l.castShadow = false; g.add(l);
  return g;
}

// Striped awning
function awning(w) {
  const c = document.createElement('canvas'); c.width = 512; c.height = 64; const x = c.getContext('2d');
  for (let i = 0; i < 8; i++) { x.fillStyle = i % 2 ? '#FFF7EC' : '#FF7A59'; x.fillRect(i * 64, 0, 64, 64); }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  const g = new THREE.Group();
  const top = mesh(new THREE.PlaneGeometry(w, 1.8), new THREE.MeshStandardMaterial({ map: t, side: THREE.DoubleSide, roughness: 0.9 }));
  top.rotation.x = -Math.PI / 2 + 0.45; top.position.set(0, 0, 0.8); g.add(top);
  // scalloped edge
  for (let i = 0; i < 16; i++) { const s = mesh(new THREE.SphereGeometry(w / 32, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), std(i % 2 ? 0xfff7ec : 0xff7a59, 0.9)); s.rotation.x = Math.PI; s.position.set(-w / 2 + w / 32 + i * w / 16, -0.39, 1.62); s.scale.set(1, 0.8, 0.3); g.add(s); }
  return g;
}

/**
 * Bakery at origin. Front faces +z. Floor 12 x 8 (x -6..6, z -4..4).
 * opts.cutaway: remove front wall + roof for interior views.
 */
export async function bakery(scene, { cutaway = false, night = false } = {}) {
  const g = new THREE.Group(); scene.add(g);
  for (const x of [-4, 0, 4]) for (const z of [-2, 2]) await place(g, 'rest', 'floor_kitchen', x, -0.48, z);
  // back wall
  await place(g, 'rest', 'wall', -4, 0, -4.25); await place(g, 'rest', 'wall_decorated', 0, 0, -4.25); await place(g, 'rest', 'wall', 4, 0, -4.25);
  for (const z of [-2, 2]) { await place(g, 'rest', 'wall', -6.25, 0, z, Math.PI / 2); await place(g, 'rest', cutaway ? 'wall_half' : 'wall_window_open', 6.25, 0, z, Math.PI / 2); }
  if (!cutaway) {
    await place(g, 'rest', 'wall_window_open', -4, 0, 4.25); await place(g, 'rest', 'wall_doorway', 0, 0, 4.25); await place(g, 'rest', 'wall_window_open', 4, 0, 4.25);
    const roof = mesh(new THREE.BoxGeometry(13.4, 0.5, 9.4), std(0x8b5e4a, 0.8), 0, 4.25, 0); g.add(roof);
    const trim = mesh(new THREE.BoxGeometry(13.8, 0.25, 9.8), std(0xfff7ec, 0.7), 0, 4.0, 0); g.add(trim);
    const aw = awning(12.4); aw.position.set(0, 3.55, 4.5); g.add(aw);
    const signT = await textTex('העוגות של נועה', { w: 1400, h: 300, font: '900 150px Heebo', bg: '#0F1F3D', fg: '#F5B83D', sub: 'אפייה ביתית · עוגות בהזמנה', subFont: '700 60px Heebo' });
    const sign = mesh(new THREE.PlaneGeometry(5.6, 1.2), new THREE.MeshStandardMaterial({ map: signT, roughness: 0.5, emissive: night ? 0xffffff : 0x000000, emissiveMap: night ? signT : null, emissiveIntensity: night ? 0.9 : 0 }), 0, 4.95, 4.72);
    g.add(sign);
    const signBack = mesh(new THREE.BoxGeometry(5.8, 1.4, 0.15), std(0x0f1f3d, 0.6), 0, 4.95, 4.62); g.add(signBack);
    g.add(planter(-2.4, 5.3)); g.add(planter(2.4, 5.3, 0xf5b83d));
    const mat = mesh(new THREE.BoxGeometry(1.6, 0.04, 0.9), std(0x2563eb, 0.9), 0, 0.03, 5.0); g.add(mat);
    // window glow & cakes visible
    const glowM = new THREE.MeshStandardMaterial({ color: 0xfff1d0, emissive: 0xffd28a, emissiveIntensity: night ? 0.7 : 0.25, transparent: true, opacity: night ? 0.45 : 0.18 });
    for (const x of [-4, 4]) { const w = mesh(new THREE.PlaneGeometry(2.4, 1.6), glowM, x, 2.2, 4.0); w.castShadow = false; g.add(w); }
  }
  // interior
  await place(g, 'rest', 'kitchencounter_straight_A_backsplash', -3, 0, -3.2);
  await place(g, 'rest', 'kitchencounter_sink_backsplash', -1, 0, -3.2);
  await place(g, 'rest', 'stove_multi_countertop', 1, 0, -3.2);
  await place(g, 'rest', 'oven', 3.2, 0, -3.2);
  await place(g, 'rest', 'fridge_A_decorated', 5.0, 0, -3.1);
  await place(g, 'rest', 'kitchencabinet', -3, 0, -4.0); await place(g, 'rest', 'kitchencabinet', -1, 0, -4.0);
  await place(g, 'rest', 'shelf_papertowel_decorated', 1, 0, -4.0);
  await place(g, 'furn', 'shelf_B_large_decorated', -5.95, 1.8, 0.2, Math.PI / 2, 1.2);
  await place(g, 'furn', 'shelf_B_small_decorated', -5.95, 2.9, 0.2, Math.PI / 2, 1.2);
  g.add(displayCase(-1.6, -0.4, 4.2));
  await place(g, 'rest', 'table_round_A_small_decorated', 3.6, 0, 1.6, 0, 0.9);
  await place(g, 'rest', 'chair_A', 3.6, 0, 2.9, Math.PI, 1.0);
  await place(g, 'rest', 'chair_A', 4.9, 0, 1.6, -Math.PI / 2, 1.0);
  await place(g, 'furn', 'rug_oval_B', 1.6, 0.02, 2.3, 0, 0.9);
  await place(g, 'furn', 'cactus_medium_A', -5.2, 0, 3.2, 0, 0.9);
  await place(g, 'furn', 'pictureframe_large_A', 5.95, 2.4, -0.6, -Math.PI / 2, 1.3);
  for (const x of [-3.6, 1.4]) g.add(pendant(x, 3.6, 0.4));
  g.add(pendant(3.6, 3.4, 1.6, 0x2563eb));
  return g;
}

export async function street(scene, { night = false, people = true, far = false } = {}) {
  const g = new THREE.Group(); scene.add(g);
  // sidewalk
  g.add(mesh(new THREE.BoxGeometry(90, 0.2, 5.5), std(0xd9d2c5, 0.95), 0, 0.0, 7.3));
  const curb = mesh(new THREE.BoxGeometry(90, 0.25, 0.3), std(0xbfb6a8, 0.9), 0, 0.02, 10.05); g.add(curb);
  // road (city tiles scaled)
  for (let i = -3; i <= 3; i++) await place(g, 'city', 'road_straight', i * 2 * CITY, -0.08, 10.2 + CITY, Math.PI / 2, CITY);
  // neighbours
  const nb = [['building_C', -14.5, 0], ['building_F', 14.5, 0], ['building_H', -27, 0], ['building_B', 27, 0]];
  for (const [n, x, ry] of nb) await place(g, 'city', n + '_withoutBase', x, 0, -1.6, ry, CITY);
  // street furniture
  for (const x of [-9, 9, -21, 21]) await place(g, 'city', 'streetlight', x, 0, 9.6, Math.PI / 2, CITY * 0.95);
  await place(g, 'city', 'bench', -6.2, 0, 8.6, 0, CITY * 0.9);
  await place(g, 'city', 'trash_A', 7.4, 0, 9.0, 0, CITY);
  await place(g, 'city', 'firehydrant', 11.5, 0, 9.3, 0, CITY);
  await place(g, 'city', 'car_taxi', -10, 0, 13.6, Math.PI / 2, CITY);
  await place(g, 'city', 'car_sedan', 12, 0, 17.6, -Math.PI / 2, CITY);
  await place(g, 'city', 'car_hatchback', 25, 0, 13.6, Math.PI / 2, CITY);
  for (const x of [-8, 8, -20, 20]) { const t = tree(0.95, x > 0 ? 0x62b04f : 0x4fa35a); t.position.set(x, 0, 8.4); g.add(t); }
  for (const x of [-12, 12]) { const t = tree(1.1); t.position.set(x, 0, 24); g.add(t); }
  // far side buildings
  if (far) for (const [n, x] of [['building_A', -16], ['building_D', -3], ['building_E', 10], ['building_G', 23]]) await place(g, 'city', n + '_withoutBase', x, 0, 30, Math.PI, CITY);
  if (far) g.add(mesh(new THREE.BoxGeometry(90, 0.2, 5.5), std(0xd9d2c5, 0.95), 0, 0, 24.8));
  await place(g, 'rest', 'table_round_A_small', -4.3, 0.1, 6.9, 0, 0.75);
  await place(g, 'rest', 'chair_A', -5.5, 0.1, 6.9, Math.PI / 2, 0.85); await place(g, 'rest', 'chair_A', -3.1, 0.1, 6.9, -Math.PI / 2, 0.85);
  await place(g, 'city', 'car_stationwagon', -26, 0, 17.6, -Math.PI / 2, CITY);
  await place(g, 'city', 'road_straight_crossing', 2 * CITY, -0.07, 10.2 + CITY, Math.PI / 2, CITY);
  if (night) for (const x of [-9, 9, -21, 21]) { const l = new THREE.PointLight(0xffc27a, 30, 14, 1.8); l.position.set(x - 1.4, 5.8, 9.6); g.add(l); g.add(mesh(new THREE.SphereGeometry(0.22, 12, 8), new THREE.MeshBasicMaterial({ color: 0xffe2a8 }), x - 1.45, 5.75, 9.6)); }
  if (people) {
    const ppl = [
      { skin: 0xc68a5e, hair: 0x1d1d1d, hairStyle: 'short', shirt: 0x2563eb, pants: 0x3a3a3a, pos: [-11, 7.2], ry: Math.PI / 2, armL: [0.4, 0, 0.1], armR: [-0.4, 0, -0.1] },
      { skin: 0xf0c8a8, hair: 0xb5651d, hairStyle: 'long', shirt: 0x3ccb9a, pants: 0x2b3a55, dress: true, pos: [9.5, 7.8], ry: -Math.PI / 2, armL: [-0.3, 0, 0.1], armR: [0.3, 0, -0.1] },
      { skin: 0x8d5a3b, hair: 0x2a1a10, hairStyle: 'curly', shirt: 0xf5b83d, pants: 0x4a4a6a, pos: [-17, 8.1], ry: 0.4 },
    ];
    for (const p of ppl) { const c = character(p); c.scale.setScalar(1.3); c.position.set(p.pos[0], 0.1, p.pos[1]); c.rotation.y = p.ry; g.add(c); }
  }
  return g;
}

export function people(defs) {
  return defs.map(d => { const c = character(d); c.scale.setScalar(1.3 * (d.h || 1)); c.position.set(...d.pos); c.rotation.y = d.ry || 0; return c; });
}

// Main cast
export const NOA = { skin: 0xe8b996, hair: 0x3b2417, hairStyle: 'bun', shirt: 0xfff7ec, pants: 0x2b3a55, apron: 0xff7a59, earrings: 0xf5b83d };
export const RONIT = { skin: 0xf2cdb0, hair: 0xc9a06a, hairStyle: 'long', shirt: 0x2563eb, pants: 0xe8e1d4, shoes: 0xffffff, glasses: false };
export const SHIRA = { skin: 0xd9a47c, hair: 0xb8b8b8, hairStyle: 'curly', shirt: 0x7a4fd1, pants: 0x3a3a3a, glasses: true };
