import { THREE, setup, env, sun, render, ground, character, marker, toScreen, place, model } from '/render/common.js';
import { bakery, street, NOA, RONIT, SHIRA, CITY, tree, cake, people } from '/render/world.js';

const q = new URLSearchParams(location.search);
const S = q.get('s'), RAW = q.has('raw');
const UI = document.getElementById('ui');
const CH = 1.55; // character scale inside the restaurant-scale world

function skyTex(top, mid, bottom) {
  const c = document.createElement('canvas'); c.width = 4; c.height = 512; const x = c.getContext('2d');
  const g = x.createLinearGradient(0, 0, 0, 512); g.addColorStop(0, top); g.addColorStop(0.55, mid); g.addColorStop(1, bottom);
  x.fillStyle = g; x.fillRect(0, 0, 4, 512); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
function cast(def, x, z, ry, extra = {}) { const c = character({ ...def, ...extra }); c.scale.setScalar(CH); c.position.set(x, 0.02, z); c.rotation.y = ry; return c; }
const hud = (coins = '1,240', day = 'יום 3 · 10:30', rep = '4.6') => `<div class="hud"><div class="pill gold"><span class="ic">🪙</span>${coins}</div><div class="pill"><span class="ic">☀️</span>${day}</div><div class="pill"><span class="ic">⭐</span>${rep}</div></div>`;
const dock = `<div class="dock"><div class="dbtn"><div class="c">🗺️</div>שכונה</div><div class="dbtn"><div class="c">📦</div>מלאי</div><div class="dbtn main"><div class="c">🧁</div>לאפות</div><div class="dbtn"><div class="c">💰</div>קופה</div><div class="dbtn"><div class="c">🎯</div>משימות</div></div>`;
const TAG = '<div class="tag">הדמיית קונספט · רינדור בזמן אמת · לא גרפיקה סופית</div>';
const at = (v, cam, ctx) => { const p = toScreen(new THREE.Vector3(...v), cam, ctx.w, ctx.h); p.x = Math.min(330, Math.max(60, p.x)); return p; };

async function interior(ctx, { night = false } = {}) {
  await env(ctx.renderer, ctx.scene, 0.45);
  ground(ctx.scene, 0x9bd27a);
  ctx.scene.add(new THREE.HemisphereLight(0xfff4e6, 0x8a7a5a, 0.55));
  sun(ctx.scene, { pos: [10, 18, 14], size: 16, intensity: 2.2, color: 0xfff0d8 });
  await bakery(ctx.scene, { cutaway: true });
  // dino cake being decorated on the counter top
  const dc = cake({ tiers: 1, base: 0x7a4a2e, cream: 0xf5e6c8, accent: 0x58c26b, r: 0.42, h: 0.34, dino: true }); dc.position.set(-0.4, 1.09, -0.15); ctx.scene.add(dc);
}

const scenes = {
  // 1. Entry screen: golden hour on the street
  async '1'() {
    const ctx = setup({ exposure: 1.05 });
    ctx.scene.background = skyTex('#3b4f9a', '#f08a6b', '#ffcf8a');
    ctx.scene.fog = new THREE.Fog(0xf3a07a, 45, 120);
    await env(ctx.renderer, ctx.scene, 0.35);
    ground(ctx.scene, 0x7fae62);
    ctx.scene.add(new THREE.HemisphereLight(0xffc6a0, 0x50406a, 0.55));
    sun(ctx.scene, { pos: [-30, 9, 18], size: 40, intensity: 3.0, color: 0xffa86b });
    await bakery(ctx.scene, { night: true });
    await street(ctx.scene, { night: true, people: false });
    ctx.scene.add(cast(NOA, 1.9, 5.2, 0.5, { expr: 'big', armR: [2.7, 0, -0.3] }));
    ctx.scene.add(cast(SHIRA, -6.2, 8.4, 0.6, { expr: 'smile' }));
    const cam = new THREE.PerspectiveCamera(46, ctx.w / ctx.h, 0.1, 300); cam.position.set(7, 3.2, 27); cam.lookAt(-0.5, 5.2, 3);
    ctx.camera = cam; await render(ctx, { bloom: 0.55 });
    if (!RAW) UI.innerHTML = `<div class="title"><span class="logo">PLTO</span><h1>הרחוב<br><em>שלי</em></h1><p>לפתוח עסק. לבנות שם. לגדול.</p></div>
      <div class="cta"><div class="btn">להתחיל לשחק</div><div class="btn sec2">המשך מהמקום שעצרת<small>העוגות של נועה · יום 3</small></div></div>${TAG}`;
  },
  // 2. Overview of the business and its surroundings
  async '2'() {
    const ctx = setup({ bg: 0xbfe3ff });
    ctx.scene.background = skyTex('#7cc4ff', '#bfe3ff', '#e8f6ff');
    await env(ctx.renderer, ctx.scene, 0.5);
    ground(ctx.scene, 0x92cc72);
    ctx.scene.add(new THREE.HemisphereLight(0xdff1ff, 0x8a7a5a, 0.6));
    sun(ctx.scene, { pos: [18, 26, 22], size: 34, intensity: 2.9 });
    await bakery(ctx.scene, {}); await street(ctx.scene, {});
    const r = cast(RONIT, 3.4, 7.2, -2.4, { expr: 'smile', armL: [0.5, 0, 0.15], armR: [-0.5, 0, -0.15] }); ctx.scene.add(r);
    ctx.scene.add(cast(SHIRA, -6.2, 8.5, 0.3, { expr: 'smile' }));
    const cam = new THREE.PerspectiveCamera(42, ctx.w / ctx.h, 0.1, 300); cam.position.set(13, 15.5, 33); cam.lookAt(0.5, 2.6, 5.5);
    ctx.camera = cam; await render(ctx);
    if (!RAW) {
      const p = at([0, 6.6, 4.6], cam, ctx), rp = at([5.5, 4.2, 7.4], cam, ctx);
      UI.innerHTML = hud() + `<div class="pin" style="left:${p.x}px;top:${p.y}px"><div class="b"><span class="dot"></span>העוגות של נועה <small>פתוח</small></div><div class="t"></div></div>
      <div class="thought" style="left:${rp.x}px;top:${rp.y}px">🎂<span style="font-size:14px">?</span></div>` + dock + TAG;
    }
  },
  // 3. The player character inside the business
  async '3'() {
    const ctx = setup({ bg: 0x9bd27a });
    await interior(ctx);
    const n = cast(NOA, -0.4, -1.75, 0.45, { expr: 'smile', armL: [1.0, 0, 0.25], armR: [1.15, 0, -0.2], headTilt: [0.12, 0, 0] }); ctx.scene.add(n);
    const m = marker(); m.position.set(-0.4, 0.03, -1.75); m.scale.setScalar(1.3); ctx.scene.add(m);
    const cam = new THREE.PerspectiveCamera(34, ctx.w / ctx.h, 0.1, 200); cam.position.set(7.5, 12.5, 15.5); cam.lookAt(-0.6, 0.6, 0.2);
    ctx.camera = cam; await render(ctx);
    if (!RAW) {
      const tp = at([-0.4, 4.6, -1.75], cam, ctx);
      UI.innerHTML = hud() + `<div class="thought" style="left:${tp.x}px;top:${tp.y}px"><div class="ring"><span>🌋</span></div><span style="font-size:13px">הר געש · 70%</span></div>
      <div class="card"><div class="avatar">👩‍🍳</div><div style="flex:1"><h3>נועה</h3><div class="sub">אופה · פותחת עסק ראשון</div><div class="chips"><span class="chip">🎨 יצירתית</span><span class="chip">😅 קצת לחוצה</span></div></div>
      <div class="bars"><div class="bar">🔋 אנרגיה<i><b style="width:72%;background:linear-gradient(90deg,#3CCB9A,#2EB886)"></b></i></div><div class="bar">😊 מצב רוח<i><b style="width:85%;background:linear-gradient(90deg,#FFD27A,#F5B83D)"></b></i></div><div class="bar">⭐ שם טוב<i><b style="width:46%;background:linear-gradient(90deg,#60A5FA,#2563EB)"></b></i></div></div></div>` + TAG;
    }
  },
  // 4. A customer walks in
  async '4'() {
    const ctx = setup({ bg: 0x9bd27a });
    await interior(ctx);
    ctx.scene.add(cast(NOA, -0.4, -1.75, 0.0, { expr: 'big', armR: [2.6, 0, -0.35], armL: [0.3, 0, 0.15] }));
    ctx.scene.add(cast(RONIT, 1.4, 3.1, -1.25, { expr: 'big', brows: 0.15, armL: [0.4, 0, 2.3], armR: [0.4, 0, -0.2] }));
    const cam = new THREE.PerspectiveCamera(36, ctx.w / ctx.h, 0.1, 200); cam.position.set(-6.5, 9.5, 13.5); cam.lookAt(0.6, 1.2, 0.8);
    ctx.camera = cam; await render(ctx);
    if (!RAW) {
      const rp = at([1.4, 4.5, 3.1], cam, ctx), np = at([-0.4, 4.5, -1.75], cam, ctx);
      UI.innerHTML = hud('1,240', 'יום 3 · 10:42') + `<div class="toast">🔔 לקוחה חדשה נכנסה</div>
      <div class="thought" style="left:${rp.x}px;top:${rp.y}px">🦖🎂<span style="font-size:13px">דחוף!</span></div>
      <div class="thought" style="left:${np.x}px;top:${np.y}px;font-size:18px">😃</div>
      <div class="card"><div class="avatar" style="background:linear-gradient(180deg,#C7DBFF,#7AA7FF)">🙋‍♀️</div><div style="flex:1"><h3>רונית</h3><div class="sub">אמא לשלושה · יום הולדת בעוד 10 ימים</div><div class="chips"><span class="chip">⏱ ממהרת</span><span class="chip">🦖 הבן מת על דינוזאורים</span></div></div>
      <div class="bars"><div class="bar">❤️ אמון<i><b style="width:50%;background:linear-gradient(90deg,#ff7a8a,#ff4d6d)"></b></i></div><div class="bar">😊 מצב רוח<i><b style="width:78%;background:linear-gradient(90deg,#FFD27A,#F5B83D)"></b></i></div></div></div>` + TAG;
    }
  },
  // 5. Conversation with choices
  async '5'() {
    const ctx = setup({ bg: 0xbfe3ff, exposure: 1.1 });
    ctx.scene.background = skyTex('#7cc4ff', '#bfe3ff', '#e8f6ff');
    await env(ctx.renderer, ctx.scene, 0.7); ground(ctx.scene, 0x92cc72);
    ctx.scene.add(new THREE.HemisphereLight(0xfff4e6, 0x8a7a5a, 0.9));
    sun(ctx.scene, { pos: [10, 18, 24], size: 30, intensity: 2.6 });
    await bakery(ctx.scene, {}); await street(ctx.scene, { people: true });
    const fill = new THREE.PointLight(0xffe2c0, 18, 14, 1.5); fill.position.set(0.5, 3.6, 1.5); ctx.scene.add(fill);
    const dc = cake({ tiers: 1, base: 0x7a4a2e, cream: 0xf5e6c8, accent: 0x58c26b, r: 0.42, h: 0.34, dino: true }); dc.position.set(0.1, 1.09, -0.2); ctx.scene.add(dc);
    ctx.scene.add(cast(NOA, -0.9, -1.75, 0.45, { expr: 'smile', armL: [0.5, 0, 0.2], armR: [0.6, 0, -0.2] }));
    ctx.scene.add(cast(RONIT, 1.1, 1.3, -2.6, { expr: 'unsure', brows: -0.45, armL: [0.15, 0, 0.65], armR: [2.0, 0.5, -0.6], headTilt: [0, 0, 0.12] }));
    const cam = new THREE.PerspectiveCamera(50, ctx.w / ctx.h, 0.1, 200); cam.position.set(-2.3, 2.75, -2.0); cam.lookAt(1.1, 2.15, 1.4);
    ctx.camera = cam; await render(ctx);
    if (!RAW) {
      UI.innerHTML = `<div class="shade"></div>` + `<div class="hud"><div class="pill"><span class="ic">🙋‍♀️</span>רונית</div><div class="pill meter">❤️ אמון<i><b></b></i></div><div class="pill gold">🌋 320 ₪</div></div>
      <div class="speech" style="bottom:262px;--tail:62%"><span class="who">רונית</span>חברה שלחה לי עוגה של "הדר עוגות" ב־120 ₪.<br>למה אצלך זה כמעט פי שלוש? 🤔</div>
      <div class="choices">
        <div class="choice"><span class="n">🔍</span>"בואי נבדוק שאנחנו משווים אותו דבר. העוגה שם לעשרים ילדים?"</div>
        <div class="choice"><span class="n">🏷️</span>"אין בעיה, אעשה לך ב־120."</div>
        <div class="choice"><span class="n">🛡️</span>"העוגות שלי איכותיות יותר. אני לא מתחרה במחירים."</div>
      </div>` + TAG;
    }
  },
  // 6. Business management, game style
  async '6'() {
    const ctx = setup({ bg: 0x9bd27a });
    await interior(ctx);
    ctx.scene.add(cast(NOA, -0.4, -1.75, 0, { expr: 'smile' }));
    const cam = new THREE.PerspectiveCamera(34, ctx.w / ctx.h, 0.1, 200); cam.position.set(7.5, 12.5, 15.5); cam.lookAt(-0.6, 0.6, 0.2);
    ctx.camera = cam; await render(ctx);
    if (!RAW) {
      document.querySelector('#stage canvas').style.filter = 'blur(5px) brightness(0.55)';
      UI.innerHTML = hud() + `<div class="panel"><div class="close">✕</div><h2>💰 הקופה של העסק</h2>
        <div class="big">🪙 1,240 <small>בקופה</small></div>
        <div class="flow"><div>הכנסות היום<b style="color:#3CCB9A">+540</b></div><div>הוצאות היום<b style="color:#FF7A59">‎-185</b></div><div>רווח<b style="color:#F5B83D">+355</b></div></div>
        <div class="sec">השבוע שלך <span>יום 3 מתוך 7</span></div>
        <div class="week"><div style="height:40%"><span>א</span></div><div style="height:62%"><span>ב</span></div><div class="t" style="height:88%"><span>היום</span></div><div style="height:6%;opacity:.35"><span>ד</span></div><div style="height:6%;opacity:.35"><span>ה</span></div></div>
        <div class="sec" style="margin-top:20px">מלאי <span>חסר שוקולד למחר</span></div>
        <div class="grid">
          <div class="slot"><div class="e">🌾</div><div class="q">×6</div><div class="l">קמח</div></div>
          <div class="slot"><div class="e">🥚</div><div class="q">×12</div><div class="l">ביצים</div></div>
          <div class="slot low"><div class="e">🍫</div><div class="q">×1</div><div class="l">שוקולד</div></div>
          <div class="slot"><div class="e">🧈</div><div class="q">×4</div><div class="l">חמאה</div></div>
          <div class="slot"><div class="e">🍓</div><div class="q">×8</div><div class="l">תותים</div></div>
          <div class="slot"><div class="e">📦</div><div class="q">×3</div><div class="l">קופסאות</div></div>
          <div class="slot"><div class="e">🕯️</div><div class="q">×20</div><div class="l">נרות</div></div>
          <div class="slot"><div class="e">🦖</div><div class="q">×5</div><div class="l">דינוזאורים</div></div>
        </div>
        <div class="sec" style="margin-top:14px">שדרוג הבא</div>
        <div class="up"><div class="e">🔥</div><div><h4>תנור כפול</h4><p>עוד 2 עוגות ביום, פחות לחץ בערב</p></div><div class="buy">🪙 800</div></div>
      </div>` + TAG;
    }
  },
  // 7. The wider business neighbourhood (isometric, city scale)
  async '7'() {
    const ctx = setup({ bg: 0xbfe3ff });
    ctx.scene.background = skyTex('#9bd0ff', '#d7eeff', '#f3fbff');
    await env(ctx.renderer, ctx.scene, 0.5);
    ground(ctx.scene, 0x8fc96d, 400);
    ctx.scene.add(new THREE.HemisphereLight(0xdff1ff, 0x8a7a5a, 0.65));
    const sunL = sun(ctx.scene, { pos: [14, 22, 10], size: 14, intensity: 2.8, color: 0xffe8c8 });
    const G = new THREE.Group(); ctx.scene.add(G);
    const N = 4, layout = {};
    const road = (x, z) => layout[`${x},${z}`] = 'road';
    for (let i = -N; i <= N; i++) { road(i, 0); road(0, i); road(i, -4); road(-4, i); road(i, 4); road(4, i); }
    for (let x = -N; x <= N; x++) for (let z = -N; z <= N; z++) {
      const k = `${x},${z}`, px = x * 2, pz = z * 2;
      if (layout[k] === 'road') {
        const onX = z === 0 || Math.abs(z) === 4, onZ = x === 0 || Math.abs(x) === 4;
        await place(G, 'city', onX && onZ ? 'road_junction' : 'road_straight', px, 0, pz, onX && !onZ ? Math.PI / 2 : 0);
      } else await place(G, 'city', 'base', px, 0, pz);
    }
    const B = [['building_C', 1, 1], ['building_F', -2, 1], ['building_H', 2, -2], ['building_A', -2, 2], ['building_D', 3, 1], ['building_G', -3, -2], ['building_E', 1, -3], ['building_B', -2, 3], ['building_C', -1, -3], ['building_E', 3, 2], ['building_A', 2, -3], ['building_D', -3, 3]];
    for (const [n, x, z] of B) await place(G, 'city', n + '_withoutBase', x * 2, 0.1, z * 2, (x + z) % 2 ? 0 : Math.PI / 2);
    const bk = new THREE.Group(); await bakery(bk, {}); bk.scale.setScalar(1 / CITY * 1.3); bk.position.set(-2, 0.1, -2.6); G.add(bk);
    const lockMat = new THREE.MeshStandardMaterial({ color: 0xcfc6b5, roughness: 1 });
    const locked = [[2, 2], [1, 3], [-3, 1], [3, -1]];
    for (const [x, z] of locked) {
      const p = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.06, 1.7), lockMat); p.position.set(x * 2, 0.12, z * 2); p.receiveShadow = true; G.add(p);
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.35, 0.04), new THREE.MeshStandardMaterial({ color: 0x8a5a3b })); post.position.set(x * 2, 0.3, z * 2); G.add(post);
      const sg = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.22, 0.03), new THREE.MeshStandardMaterial({ color: 0xf5b83d })); sg.position.set(x * 2, 0.45, z * 2); sg.castShadow = true; G.add(sg);
    }
    for (const [x, z] of [[3, 3], [-3, -3], [3, -3], [-1, -1], [-1, 2], [1, -1], [-3, 2], [2, 1]]) for (let i = 0; i < 3; i++) { const t = tree(0.11 + i * 0.015, i % 2 ? 0x5fae4f : 0x4c9e55); t.position.set(x * 2 + Math.cos(i * 2) * 0.5, 0.1, z * 2 + Math.sin(i * 2) * 0.5); G.add(t); }
    for (const [n, x, z, r] of [['car_taxi', 0.4, -3.2, 0], ['car_sedan', -0.4, 4.1, Math.PI], ['car_hatchback', 3.7, 0.4, Math.PI / 2], ['car_stationwagon', -4.6, -0.4, -Math.PI / 2], ['car_police', 0.4, 5.6, 0], ['car_sedan', 5.6, 8.4, -Math.PI / 2], ['car_taxi', -8.4, 2.6, 0]]) await place(G, 'city', n, x, 0.1, z, r);
    for (const [x, z] of [[-0.9, -0.9], [0.9, 0.9], [-0.9, 2.9], [2.9, -0.9], [-0.9, -6.9], [6.9, 0.9]]) await place(G, 'city', 'streetlight', x, 0.1, z, 0);
    const w = 8.6, h = w * ctx.h / ctx.w;
    const cam = new THREE.OrthographicCamera(-w, w, h, -h, 0.1, 200); cam.position.set(16, 17, 16); cam.lookAt(-0.6, 0, -0.6); cam.zoom = 1.35; cam.updateProjectionMatrix();
    ctx.camera = cam; await render(ctx, { ao: true });
    if (!RAW) {
      const lab = (v, txt, cls = '') => { const p = at(v, cam, ctx); return `<div class="label ${cls}" style="left:${p.x}px;top:${p.y}px">${txt}</div>`; };
      UI.innerHTML = hud('1,240', 'שבוע 2 · שכונת הגפן') +
        lab([-2, 1.6, -2.6], '🧁 העוגות של נועה', 'me') + lab([2, 3.2, 2], '☕ קפה פינה') + lab([6, 2.6, 2], '✂️ מספרה של אבי') + lab([4, 3.4, -4], '🏪 מכולת הרחוב') + lab([-2, 2.6, -6], '💐 פרחים') +
        locked.map(([x, z]) => lab([x * 2, 0.7, z * 2], '🔒 מגרש פנוי', 'lock')).join('') +
        `<div class="mapbar"><div class="avatar" style="width:46px;height:46px;font-size:22px">🏘️</div><div class="prog"><h3>שכונת הגפן</h3><p>5 עסקים פעילים · 4 מגרשים מחכים לך</p><i><b></b></i></div></div>` + TAG;
    }
  },
  // Style comparison: same bakery block, isometric orthographic
  async 'iso'() {
    const ctx = setup({ bg: 0xbfe3ff });
    ctx.scene.background = skyTex('#9bd0ff', '#d7eeff', '#f3fbff');
    await env(ctx.renderer, ctx.scene, 0.5); ground(ctx.scene, 0x92cc72);
    ctx.scene.add(new THREE.HemisphereLight(0xdff1ff, 0x8a7a5a, 0.6));
    sun(ctx.scene, { pos: [18, 26, 22], size: 34, intensity: 2.9 });
    await bakery(ctx.scene, { cutaway: true }); await street(ctx.scene, {});
    ctx.scene.add(cast(NOA, -0.4, -1.75, 0.3, { expr: 'smile' }));
    ctx.scene.add(cast(RONIT, 1.2, 2.6, Math.PI + 0.4, { expr: 'smile' }));
    const w = 12, h = w * ctx.h / ctx.w;
    const cam = new THREE.OrthographicCamera(-w, w, h, -h, 0.1, 300); cam.position.set(30, 30, 30); cam.lookAt(1, 0, 3); cam.zoom = 1.55; cam.updateProjectionMatrix();
    ctx.camera = cam; await render(ctx);
    if (!RAW) UI.innerHTML = TAG;
  },
};

await scenes[S]();
window.__ready = true;
