// 阶段 0 的占位页面：一块面板、一个不动的小人、两个开关。
// 在浏览器里直接打开也能看（没有外壳时，开关只改页面上的样子）。

const tauri = window.__TAURI__;
const invoke = tauri ? tauri.core.invoke : async (cmd, args) => {
  if (cmd === 'get_state') return mock;
  if (cmd === 'set_capture_hidden') mock.capture_hidden = args.on;
  if (cmd === 'set_autostart') mock.autostart = args.on;
};
const mock = { version: '0.0.1', capture_hidden: false, autostart: false, hotkey_ok: true, tray_ok: true, focus_count: 0, scale: window.devicePixelRatio, x: 0, y: 0 };

const $ = (id) => document.getElementById(id);

// ───────── 小人：按 Mac 版的 38 格坐标画，白线加深色描边 ─────────
let cheering = false;

function drawCheer() {
  const cv = $('cheer'), dpr = window.devicePixelRatio || 1, side = 96;
  cv.width = cv.height = Math.round(side * dpr);
  const g = cv.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, side, side);
  const u = side / 38, sw = Math.pow(u, 0.85);
  const ink = '#ededed', halo = '#2b2b2b', accent = 'rgb(230,115,107)';
  const p = cheering
    ? { a: 33, leg: 3.4, hop: 0.9, spin: 1 }
    : { a: -32, leg: 2.8, hop: 1.8, spin: 0 };
  g.lineCap = g.lineJoin = 'round';
  const stroke = (path, w, color) => {
    g.lineWidth = (w + 1.5) * sw; g.strokeStyle = halo; g.stroke(path);
    g.lineWidth = w * sw; g.strokeStyle = color; g.stroke(path);
  };

  // 躯干和腿
  const hipY = 21.6 + p.hop, body = new Path2D();
  body.moveTo(19 * u, (14.4 + p.hop) * u); body.lineTo(19 * u, hipY * u);
  for (const s of [-1, 1]) {
    const ax = 19 + s * p.leg, ay = 30.4;
    body.moveTo(19 * u, hipY * u); body.lineTo(ax * u, ay * u);
    body.lineTo((ax + s * Math.cos(1) * 1.7) * u, (ay + Math.sin(1) * 1.7) * u);
  }
  stroke(body, 2.2, ink);

  // 脑袋：实心圆，五官刻在上面
  const hc = { x: 19, y: 10.4 + p.hop }, hr = 5.4;
  const head = new Path2D(); head.arc(hc.x * u, hc.y * u, hr * u, 0, Math.PI * 2);
  g.lineWidth = 1.5 * sw; g.strokeStyle = halo; g.stroke(head);
  g.fillStyle = ink; g.fill(head);
  g.strokeStyle = g.fillStyle = '#1a1a1a'; g.lineWidth = 1.05 * sw;
  for (const s of [-1, 1]) {
    const ex = hc.x + s * 2.35, ey = hc.y - 2.3;
    g.beginPath(); g.moveTo((ex - 1.05) * u, ey * u); g.lineTo((ex + 1.05) * u, ey * u); g.stroke();   // 平眉毛
    g.beginPath(); g.arc(ex * u, ey * u, 0.85 * u, 0, Math.PI); g.fill();                              // 挂在眉毛下面的半颗豆子
  }
  g.beginPath(); g.moveTo((hc.x - 0.9) * u, (hc.y + 2.75) * u); g.lineTo((hc.x + 0.9) * u, (hc.y + 2.75) * u); g.stroke();

  // 手臂和花球：画在脑袋前面
  const arms = new Path2D(), star = new Path2D();
  for (const s of [-1, 1]) {
    const sh = { x: 19 + s, y: 17.4 + p.hop }, a = p.a * Math.PI / 180, full = 10;
    let h = { x: sh.x + s * Math.cos(a) * full, y: sh.y - Math.sin(a) * full };
    const gx = h.x - hc.x, gy = h.y - hc.y, gd = Math.hypot(gx, gy), keep = 9.4;      // 花球挨着脸颊但不盖到脸上
    if (gd < keep) h = { x: hc.x + gx / gd * keep, y: hc.y + gy / gd * keep };
    const al = Math.hypot(h.x - sh.x, h.y - sh.y);
    const bend = Math.sqrt(Math.max(0, full * full - al * al)) / 2 * 0.95;
    const e = {
      x: (sh.x + h.x) / 2 + s * 0.92 * bend + s * 0.5 * Math.sin(a),
      y: (sh.y + h.y) / 2 + 0.39 * bend + 0.5 + 1.2 * Math.abs(Math.cos(a)),
    };
    arms.moveTo(sh.x * u, sh.y * u); arms.bezierCurveTo(e.x * u, e.y * u, e.x * u, e.y * u, h.x * u, h.y * u);
    for (let k = 0; k < 3; k++) {
      const t = (k + p.spin * s) * Math.PI / 3, len = 2.8 * u;
      star.moveTo(h.x * u - Math.cos(t) * len, h.y * u - Math.sin(t) * len);
      star.lineTo(h.x * u + Math.cos(t) * len, h.y * u + Math.sin(t) * len);
    }
  }
  stroke(arms, 2.2, ink);
  stroke(star, 2.0, accent);
}

// ───────── 告诉外壳哪些地方「有内容」：这些矩形之外，鼠标会点穿到后面的窗口 ─────────
function reportRects() {
  const rects = ['panel', 'cheer'].map((id) => {
    const r = $(id).getBoundingClientRect();
    return [r.left, r.top, r.width, r.height];
  });
  invoke('set_hit_rects', { rects });
}

// ───────── 状态 ─────────
async function refresh() {
  const s = await invoke('get_state');
  $('ver').textContent = s.version;
  $('capture').setAttribute('aria-checked', String(s.capture_hidden));
  $('autostart').setAttribute('aria-checked', String(s.autostart));
  // 最下面一行小字是给排查问题用的，测试时截图带上它
  const ok = (good, label) => good ? `${label} ✓` : `<span class="bad">${label} ✗</span>`;
  const parts = [
    `缩放 ${Math.round(s.scale * 100)}%`,
    s.focus_count ? `<span class="bad">被激活 ${s.focus_count} 次</span>` : '被激活 0 次',
    ok(s.hotkey_ok, '快捷键'),
    ok(s.tray_ok, '托盘'),
    `${s.x}, ${s.y}`,
  ];
  $('diag').innerHTML = parts.join(' · ');
}

async function flip(id, cmd) {
  const on = $(id).getAttribute('aria-checked') !== 'true';
  try { await invoke(cmd, { on }); } catch (e) { $('diag').innerHTML = `<span class="bad">${String(e)}</span>`; return; }
  refresh();
}

$('capture').addEventListener('click', () => flip('capture', 'set_capture_hidden'));
$('autostart').addEventListener('click', () => flip('autostart', 'set_autostart'));
$('hide').addEventListener('click', () => invoke('hide_window'));
$('quit').addEventListener('click', () => invoke('quit'));
$('cheer').addEventListener('click', () => { cheering = !cheering; drawCheer(); });

// 按住面板空白处拖动（按钮上不算）
$('panel').addEventListener('pointerdown', (e) => {
  if (e.button !== 0 || e.target.closest('button')) return;
  invoke('start_drag');
});
window.addEventListener('contextmenu', (e) => e.preventDefault());   // 不要浏览器自带的右键菜单

window.addEventListener('resize', () => { drawCheer(); reportRects(); });
matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`).addEventListener('change', () => { drawCheer(); reportRects(); refresh(); });
if (tauri) tauri.event.listen('shell-changed', refresh);

drawCheer();
reportRects();
refresh();
