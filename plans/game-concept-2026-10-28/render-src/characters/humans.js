import { THREE, setup, env, sun, render, ground, marker, toScreen } from '/render/common.js';
import { bakery, cake, NOA } from '/render/world.js';
import { character } from '/render/common.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
const q = new URLSearchParams(location.search);
const file = q.get('f'), view = q.get('v') || 'wide', scale = +(q.get('sc') || 1.333), ry = +(q.get('ry') || 0.45);
const ctx = setup({ bg: 0x9bd27a });
await env(ctx.renderer, ctx.scene, 0.45);
ground(ctx.scene, 0x9bd27a);
ctx.scene.add(new THREE.HemisphereLight(0xfff4e6, 0x8a7a5a, 0.55));
sun(ctx.scene, { pos: [10, 18, 14], size: 16, intensity: 2.2, color: 0xfff0d8 });
await bakery(ctx.scene, { cutaway: true });
const dc = cake({ tiers: 1, base: 0x7a4a2e, cream: 0xf5e6c8, accent: 0x58c26b, r: 0.42, h: 0.34, dino: true }); dc.position.set(-0.4, 1.09, -0.15); ctx.scene.add(dc);
const h = file === 'toy' ? character({ ...NOA, expr: 'smile' }) : (await new GLTFLoader().loadAsync(file)).scene; h.traverse(m => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; if (m.material) { const mt = m.material; const cut = /hair|ponytail|bob|braid|afro|long0|short0|eyebrow|eyelash|high-poly|low-poly|eye/i.test(m.name + mt.name); mt.transparent = false; mt.depthWrite = true; mt.alphaTest = cut ? 0.5 : 0; mt.side = cut ? THREE.DoubleSide : THREE.FrontSide; if (!cut) mt.alphaMap = null; mt.needsUpdate = true; } } });
h.scale.setScalar(scale); h.position.set(-0.4, 0.02, -1.75); h.rotation.y = ry; ctx.scene.add(h);
const m = marker(); m.position.set(-0.4, 0.03, -1.75); m.scale.setScalar(1.3); ctx.scene.add(m);
const b = new THREE.Box3().setFromObject(h); window.__out = 'bbox ' + b.min.toArray().map(v => v.toFixed(2)) + ' / ' + b.max.toArray().map(v => v.toFixed(2));
const cam = new THREE.PerspectiveCamera(view === 'wide' ? 34 : 22, ctx.w / ctx.h, 0.05, 200);
if (view === 'wide') { cam.position.set(7.5, 12.5, 15.5); cam.lookAt(-0.6, 0.6, 0.2); }
else { cam.position.set(1.6, 3.1, 3.4); cam.lookAt(-0.45, 1.85, -1.75); }
ctx.camera = cam; await render(ctx);
window.__ready = true;
