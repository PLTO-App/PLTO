// Shared rendering helpers for concept stills (not product code).
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

export { THREE };

const PACK = { city: 'City-Builder-Bits', rest: 'Restaurant-Bits', furn: 'Furniture-Bits' };
const loader = new GLTFLoader();
const cache = new Map();

export async function model(pack, name) {
  const key = pack + '/' + name;
  if (!cache.has(key)) cache.set(key, loader.loadAsync(`/dl/kaykit/${PACK[pack]}/${name}.gltf`));
  const g = await cache.get(key);
  const o = g.scene.clone(true);
  o.traverse(m => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; } });
  return o;
}

export async function place(parent, pack, name, x, y, z, ry = 0, s = 1) {
  const o = await model(pack, name);
  o.position.set(x, y, z); o.rotation.y = ry; o.scale.setScalar(s);
  parent.add(o); return o;
}

export function setup({ w = 390, h = 844, dpr = 2, bg = 0xbfe3ff, exposure = 1.0 } = {}) {
  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setPixelRatio(dpr); renderer.setSize(w, h);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = exposure;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  document.getElementById('stage').appendChild(renderer.domElement);
  const scene = new THREE.Scene(); scene.background = new THREE.Color(bg);
  return { renderer, scene, w, h };
}

export async function env(renderer, scene, intensity = 0.6) {
  const tex = await new RGBELoader().loadAsync('/dl/hdri_1k.hdr');
  const pm = new THREE.PMREMGenerator(renderer);
  scene.environment = pm.fromEquirectangular(tex).texture;
  scene.environmentIntensity = intensity;
  tex.dispose();
}

export function sun(scene, { color = 0xfff1d6, intensity = 2.6, pos = [12, 18, 8], size = 14, target = [0, 0, 0] } = {}) {
  const d = new THREE.DirectionalLight(color, intensity);
  d.position.set(...pos); d.target.position.set(...target); scene.add(d.target);
  d.castShadow = true; d.shadow.mapSize.set(2048, 2048);
  Object.assign(d.shadow.camera, { left: -size, right: size, top: size, bottom: -size, near: 0.5, far: 80 });
  d.shadow.bias = -0.0004; d.shadow.normalBias = 0.02; d.shadow.radius = 3;
  scene.add(d); return d;
}

export async function render({ renderer, scene, camera, w, h }, { ao = true, bloom = 0 } = {}) {
  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  if (ao) { const g = new GTAOPass(scene, camera, w, h); g.updateGtaoMaterial({ radius: 0.5, distanceFallOff: 1, thickness: 1, scale: 1.2 }); g.blendIntensity = 0.85; composer.addPass(g); }
  if (bloom) composer.addPass(new UnrealBloomPass(new THREE.Vector2(w, h), bloom, 0.5, 0.82));
  composer.addPass(new OutputPass());
  composer.render();
}

// ---------- Hebrew canvas texture (signs) ----------
export async function textTex(lines, { w = 1024, h = 256, bg = '#0F1F3D', fg = '#F5B83D', font = '900 120px Heebo', sub = null, subFont = '700 54px Heebo', subColor = '#FFF7EC', radius = 40 } = {}) {
  await document.fonts.load(font); if (sub) await document.fonts.load(subFont);
  const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d');
  if (bg) { x.fillStyle = bg; x.beginPath(); x.roundRect(0, 0, w, h, radius); x.fill(); }
  x.direction = 'rtl'; x.textAlign = 'center'; x.textBaseline = 'middle';
  x.fillStyle = fg; x.font = font; x.fillText(lines, w / 2, sub ? h * 0.4 : h / 2);
  if (sub) { x.fillStyle = subColor; x.font = subFont; x.fillText(sub, w / 2, h * 0.78); }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t;
}

// ---------- Stylized procedural character ----------
const std = (color, rough = 0.7, extra = {}) => new THREE.MeshStandardMaterial({ color, roughness: rough, ...extra });

function cap(r, l, mat) { const m = new THREE.Mesh(new THREE.CapsuleGeometry(r, l, 8, 16), mat); m.castShadow = m.receiveShadow = true; return m; }
function ball(r, mat, ws = 24) { const m = new THREE.Mesh(new THREE.SphereGeometry(r, ws, ws), mat); m.castShadow = m.receiveShadow = true; return m; }

function limb(len, r, mat, handMat, endR) {
  // pivot at top, hangs down -Y
  const g = new THREE.Group();
  const upper = cap(r, len * 0.5, mat); upper.position.y = -len * 0.3; g.add(upper);
  const lower = cap(r * 0.88, len * 0.45, mat); lower.position.y = -len * 0.72; g.add(lower);
  if (handMat) { const hnd = ball(endR, handMat); hnd.position.y = -len - endR * 0.4; hnd.scale.set(1, 1.15, 0.8); g.add(hnd); }
  return g;
}

function mouthCurve(kind) {
  // returns points in face space (x right, y up), z handled by caller
  const pts = [];
  for (let i = 0; i <= 16; i++) {
    const t = i / 16, x = (t - 0.5) * 0.085;
    let y = 0;
    const u = 1 - Math.pow(2 * t - 1, 2);
    if (kind === 'smile') y = -u * 0.02;
    else if (kind === 'big') y = -u * 0.028;
    else if (kind === 'unsure') y = (t - 0.5) * 0.02 + Math.sin(t * Math.PI * 2) * 0.004;
    else if (kind === 'frown') y = u * 0.015;
    pts.push(new THREE.Vector3(x, y, 0));
  }
  return new THREE.CatmullRomCurve3(pts);
}

export function character(o = {}) {
  const {
    skin = 0xe8b996, hair = 0x3b2417, hairStyle = 'bun', shirt = 0xff7a59, pants = 0x2b3a55, shoes = 0x2a2a2a,
    apron = null, expr = 'smile', brows = 0, armL = [0, 0, 0.12], armR = [0, 0, -0.12], headTilt = [0, 0, 0],
    lean = 0, height = 1, dress = false, glasses = false, earrings = null,
  } = o;
  const root = new THREE.Group();
  const body = new THREE.Group(); root.add(body); body.rotation.x = lean;
  const S = std(skin, 0.55), H = std(hair, 0.6), T = std(shirt, 0.8), P = std(pants, 0.85), SH = std(shoes, 0.5);
  const L = 0.56, hipY = L + 0.1, torsoY = hipY + 0.25, shY = torsoY + 0.15, headY = torsoY + 0.47, HS = 1.55;
  for (const sx of [-1, 1]) {
    const leg = limb(L, 0.085, dress ? S : P, null); leg.position.set(sx * 0.1, hipY - 0.02, 0); body.add(leg);
    const shoe = cap(0.075, 0.1, SH); shoe.rotation.x = Math.PI / 2; shoe.position.set(sx * 0.1, 0.07, 0.05); body.add(shoe);
  }
  const hips = cap(0.17, 0.06, dress ? T : P); hips.scale.set(1.15, 1, 0.85); hips.position.y = hipY; body.add(hips);
  if (dress) { const sk = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.32, 0.36, 24, 1, true), std(shirt, 0.8, { side: THREE.DoubleSide })); sk.position.y = hipY - 0.12; sk.castShadow = true; body.add(sk); }
  const torso = cap(0.19, 0.2, T); torso.scale.set(1.1, 1, 0.82); torso.position.y = torsoY; body.add(torso);
  const collar = new THREE.Mesh(new THREE.TorusGeometry(0.075, 0.022, 8, 20), std(new THREE.Color(shirt).multiplyScalar(0.85), 0.8)); collar.rotation.x = Math.PI / 2; collar.position.y = torsoY + 0.24; body.add(collar);
  if (apron) {
    const ap = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.5, 0.025), std(apron, 0.9)); ap.position.set(0, hipY + 0.1, 0.165); ap.castShadow = true; body.add(ap);
    const bib = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.18, 0.025), std(apron, 0.9)); bib.position.set(0, torsoY + 0.1, 0.16); body.add(bib);
    const pocket = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.08, 0.03), std(new THREE.Color(apron).multiplyScalar(0.8), 0.9)); pocket.position.set(0, hipY + 0.02, 0.18); body.add(pocket);
  }
  const neck = cap(0.05, 0.05, S); neck.position.y = torsoY + 0.27; body.add(neck);
  const head = new THREE.Group(); head.position.y = headY; head.rotation.set(...headTilt); head.scale.setScalar(HS); body.add(head);
  const skull = ball(0.135, S, 32); skull.scale.set(0.98, 1.0, 0.96); head.add(skull);
  for (const sx of [-1, 1]) { const ear = ball(0.03, S); ear.position.set(sx * 0.13, 0, 0); ear.scale.set(0.5, 1, 0.8); head.add(ear); }
  const nose = ball(0.02, S); nose.position.set(0, -0.018, 0.13); nose.scale.set(0.9, 0.9, 0.9); head.add(nose);
  const white = std(0xffffff, 0.3), iris = std(0x2a1a10, 0.2);
  const eyeOpen = expr === 'surprised' ? 1.3 : expr === 'big' ? 0.75 : 1;
  for (const sx of [-1, 1]) {
    const e = ball(0.028, white); e.position.set(sx * 0.048, 0.02, 0.11); e.scale.set(0.9, eyeOpen * 1.1, 0.6); head.add(e);
    const p = ball(0.018, iris); p.position.set(sx * 0.047, 0.019, 0.126); p.scale.set(0.9, eyeOpen * 1.1, 0.6); head.add(p);
    const gl = ball(0.006, std(0xffffff, 0.1, { emissive: 0xffffff, emissiveIntensity: 0.6 })); gl.position.set(sx * 0.042, 0.028, 0.134); head.add(gl);
    const b = new THREE.Mesh(new THREE.CapsuleGeometry(0.007, 0.036, 4, 8), std(new THREE.Color(hair).multiplyScalar(0.7), 0.6));
    b.rotation.z = Math.PI / 2 + sx * (brows * 0.35); b.position.set(sx * 0.05, 0.068 + (expr === 'surprised' ? 0.014 : 0), 0.118); head.add(b);
    const cheek = ball(0.022, std(0xff8a8a, 0.8, { transparent: true, opacity: 0.35 })); cheek.position.set(sx * 0.074, -0.032, 0.105); cheek.scale.set(1, 0.6, 0.3); head.add(cheek);
  }
  if (expr === 'surprised') {
    const m = new THREE.Mesh(new THREE.TorusGeometry(0.014, 0.006, 8, 20), std(0x6b2a2a, 0.5)); m.position.set(0, -0.062, 0.122); m.scale.set(1, 1.3, 1); head.add(m);
  } else {
    const kind = expr === 'neutral' ? 'unsure' : expr;
    const m = new THREE.Mesh(new THREE.TubeGeometry(mouthCurve(kind), 24, 0.0055, 8), std(0x7a2e2e, 0.5)); m.position.set(0, -0.058, 0.124); head.add(m);
    if (expr === 'big') { const t = new THREE.Mesh(new THREE.SphereGeometry(0.03, 16, 8, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), std(0x5a1f1f, 0.5)); t.position.set(0, -0.06, 0.116); t.scale.set(1.2, 0.7, 0.5); head.add(t); }
  }
  if (glasses) {
    for (const sx of [-1, 1]) { const r = new THREE.Mesh(new THREE.TorusGeometry(0.03, 0.004, 8, 24), std(0x222222, 0.3)); r.position.set(sx * 0.048, 0.02, 0.138); head.add(r); }
    const br = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.004, 0.004), std(0x222222)); br.position.set(0, 0.025, 0.14); head.add(br);
  }
  if (earrings) for (const sx of [-1, 1]) { const e = ball(0.01, std(earrings, 0.2, { metalness: 0.8 })); e.position.set(sx * 0.133, -0.04, 0.01); head.add(e); }
  // hair
  const capG = new THREE.SphereGeometry(0.148, 32, 24, 0, Math.PI * 2, 0, Math.PI * 0.58);
  const hc = new THREE.Mesh(capG, H); hc.scale.set(0.98, 1.1, 1.05); hc.rotation.x = hairStyle === 'long' ? -0.42 : -0.22; hc.position.set(0, 0.016, -0.008); hc.castShadow = true; head.add(hc);
  if (hairStyle === 'bun') { const bun = ball(0.07, H); bun.position.set(0, 0.13, -0.09); head.add(bun); const fr = ball(0.05, H); fr.position.set(-0.06, 0.1, 0.09); fr.scale.set(1.4, 0.5, 0.6); head.add(fr); }
  if (hairStyle === 'long') { const back = cap(0.12, 0.16, H); back.position.set(0, -0.09, -0.06); back.scale.set(1.15, 1, 0.6); head.add(back); for (const sx of [-1, 1]) { const s = cap(0.045, 0.14, H); s.position.set(sx * 0.12, -0.08, 0.02); head.add(s); } }
  if (hairStyle === 'curly') { for (let i = 0; i < 14; i++) { const a = (i / 14) * Math.PI * 2; const c = ball(0.045, H, 12); c.position.set(Math.cos(a) * 0.11, 0.07 + Math.sin(i) * 0.02, Math.sin(a) * 0.1 - 0.02); head.add(c); } }
  if (hairStyle === 'short') { hc.scale.set(1, 1.02, 1.02); }
  // arms (pivot at shoulder). arm = [forward raise, twist, sideways]
  for (const [sx, a] of [[1, armL], [-1, armR]]) {
    const arm = limb(0.46, 0.06, T, S, 0.05); arm.position.set(sx * 0.225, shY, 0);
    arm.rotation.order = 'ZXY'; arm.rotation.set(-a[0], a[1], a[2]); body.add(arm);
  }
  root.scale.setScalar(height);
  root.userData.head = head;
  return root;
}

// Soft ring marker under the active character (own design)
export function marker(color = 0x3ccb9a) {
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.38, 0.025, 12, 48), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9 }));
  ring.rotation.x = Math.PI / 2; ring.position.y = 0.02; g.add(ring);
  const disc = new THREE.Mesh(new THREE.CircleGeometry(0.38, 48), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.18 }));
  disc.rotation.x = -Math.PI / 2; disc.position.y = 0.015; g.add(disc);
  return g;
}

export function ground(scene, color = 0x9bd27a, size = 200) {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), std(color, 1));
  m.rotation.x = -Math.PI / 2; m.receiveShadow = true; scene.add(m); return m;
}

// project a world point to CSS px for UI anchoring
export function toScreen(v, camera, w, h) {
  const p = v.clone().project(camera);
  return { x: (p.x * 0.5 + 0.5) * w, y: (-p.y * 0.5 + 0.5) * h };
}
