/* LTS 3D Replay — standalone viewer embedded by ltsviz.write3DHtml.
 *
 * Renders the aligned simulation/reality runs as animated 3D cars on the
 * reference track. Payload contract (window.LTS_SCENE), produced by
 * ltsviz.buildScene3D:
 *   meta   : { title, simFile, realFile, simLabel, realLabel, createdAt,
 *              axisName, axisUnit, duration, samples, hasReal,
 *              attitudeEstimated, warnings[], metrics{} }
 *   track  : { hasTrack, x[], y[], s[], width, left[], right[], closed }
 *   sim    : { t[], x[], y[], h[], v[], th[], br[], st[], la[], lo[],
 *              roll[], pitch[] }
 *   real   : same as sim, or []
 *
 * Coordinate map: MATLAB (x, y) -> three (x, -y as z), y up. A MATLAB
 * heading h (CCW from +x) equals the car group's rotation.y; the car model
 * is built nose along local +x.
 */
(function () {
  'use strict';

  var S = window.LTS_SCENE || null;

  function $(id) { return document.getElementById(id); }

  function fatal(msg) {
    $('fatalMsg').textContent = msg;
    $('fatal').hidden = false;
    $('loading').hidden = true;
    throw new Error(msg);
  }

  if (typeof THREE === 'undefined') {
    fatal('The three.js library did not load. Reports embed a local copy of ' +
      'three.min.js; if it was stripped out, open this file with internet ' +
      'access so the CDN fallback can load.');
  }
  if (!S || !S.sim || !S.sim.x || S.sim.x.length < 2) {
    fatal('This report carries no replay payload. Regenerate it with ' +
      'ltsviz.render3D or ltsviz.visualizeCorrelation.');
  }

  // ------------------------------------------------------------------ setup

  var COL = {
    sim: 0x4f8cff, real: 0xff5964,
    asphalt: 0x2b3038, edge: 0xf2f4f8, ground: 0x10141d, cone: 0xff7a1a
  };
  var WHEEL_R = 0.23;   // [m] FSAE 10" slick radius
  var COMET = 160;      // samples in the comet trail

  var sim = S.sim;
  var real = (S.real && S.real.x && S.real.x.length > 1) ? S.real : null;
  var N = sim.x.length;
  var t0 = num(sim.t[0], 0);
  var t1 = num(sim.t[N - 1], N - 1);
  var span = Math.max(1e-9, t1 - t0);
  var isTime = S.meta.axisUnit !== 'm';

  function num(v, alt) { return (typeof v === 'number' && isFinite(v)) ? v : alt; }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
  function angLerp(a, b, t) {
    var d = b - a;
    d = ((d + Math.PI) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) - Math.PI;
    return a + d * t;
  }
  function fmtSpan(v) {
    if (!isTime) return v.toFixed(1) + ' m';
    var m = Math.floor(v / 60), s = v - m * 60;
    return m + ':' + (s < 10 ? '0' : '') + s.toFixed(1);
  }
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function isFiniteNum(v) { return typeof v === 'number' && isFinite(v); }

  // Sample a run at a fractional index (arrays are pre-sanitized in MATLAB).
  function sample(run, i) {
    var i0 = clamp(Math.floor(i), 0, run.x.length - 1);
    var i1 = clamp(i0 + 1, 0, run.x.length - 1);
    var f = clamp(i - i0, 0, 1);
    return {
      x: lerp(run.x[i0], run.x[i1], f),
      z: lerp(-run.y[i0], -run.y[i1], f),
      h: angLerp(run.h[i0], run.h[i1], f),
      v: lerp(num(run.v[i0], 0), num(run.v[i1], 0), f),
      th: lerp(num(run.th[i0], 0), num(run.th[i1], 0), f),
      br: lerp(num(run.br[i0], 0), num(run.br[i1], 0), f),
      st: lerp(num(run.st[i0], 0), num(run.st[i1], 0), f),
      la: lerp(num(run.la[i0], 0), num(run.la[i1], 0), f),
      roll: lerp(num(run.roll[i0], 0), num(run.roll[i1], 0), f),
      pitch: lerp(num(run.pitch[i0], 0), num(run.pitch[i1], 0), f),
      t: lerp(num(run.t[i0], t0), num(run.t[i1], t0), f)
    };
  }

  // ------------------------------------------------------------- three scene

  var canvas = $('view');
  var renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true });
  } catch (e) {
    fatal('WebGL is unavailable in this browser, so the 3D scene cannot render.');
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.outputEncoding = THREE.sRGBEncoding;

  var scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0b0f16);
  var camera = new THREE.PerspectiveCamera(55, 1, 0.1, 5000);

  var trackDef = buildTrackDef();
  var bounds = computeBounds();
  var diag = Math.max(20, Math.hypot(bounds.max.x - bounds.min.x,
    bounds.max.z - bounds.min.z));
  scene.fog = new THREE.Fog(0x0b0f16, diag * 1.5, diag * 5);
  buildEnvironment();
  var trackCones = buildTrackMesh(trackDef);

  function buildTrackDef() {
    var d = S.track || {};
    var pts = [];
    if (d.hasTrack && d.x && d.x.length > 1) {
      for (var i = 0; i < d.x.length; i++) pts.push([num(d.x[i], 0), num(d.y[i], 0)]);
    } else {
      var step = Math.max(1, Math.floor(N / 1500));
      for (var j = 0; j < N; j += step) pts.push([sim.x[j], sim.y[j]]);
      pts.push([sim.x[N - 1], sim.y[N - 1]]);
      d = { width: 3, closed: false };
    }
    var w = num(d.width, 3) || 3;
    var hasL = d.left && d.left.length === pts.length;
    var hasR = d.right && d.right.length === pts.length;
    var halfL = [], halfR = [];
    for (var k = 0; k < pts.length; k++) {
      halfL.push(hasL ? clamp(num(d.left[k], w / 2), 0.5, 30) : w / 2);
      halfR.push(hasR ? clamp(num(d.right[k], w / 2), 0.5, 30) : w / 2);
    }
    return { pts: pts, halfL: halfL, halfR: halfR, closed: !!d.closed };
  }

  function computeBounds() {
    var b = { min: { x: 1e9, z: 1e9 }, max: { x: -1e9, z: -1e9 } };
    for (var i = 0; i < trackDef.pts.length; i++) {
      var x = trackDef.pts[i][0], z = -trackDef.pts[i][1];
      b.min.x = Math.min(b.min.x, x); b.max.x = Math.max(b.max.x, x);
      b.min.z = Math.min(b.min.z, z); b.max.z = Math.max(b.max.z, z);
    }
    if (b.min.x > b.max.x) { b.min = { x: -10, z: -10 }; b.max = { x: 10, z: 10 }; }
    return b;
  }

  function center() {
    return new THREE.Vector3((bounds.min.x + bounds.max.x) / 2, 0,
      (bounds.min.z + bounds.max.z) / 2);
  }

  function buildEnvironment() {
    var c = center();
    scene.add(new THREE.HemisphereLight(0x9fb4d8, 0x141a26, 1.0));
    var sun = new THREE.DirectionalLight(0xfff3e0, 1.18);
    sun.position.set(c.x + diag * 0.5, diag * 0.8, c.z - diag * 0.35);
    sun.target.position.copy(c);
    sun.castShadow = true;
    var s = diag * 0.85;
    sun.shadow.camera.left = -s; sun.shadow.camera.right = s;
    sun.shadow.camera.top = s; sun.shadow.camera.bottom = -s;
    sun.shadow.camera.near = 1; sun.shadow.camera.far = diag * 3;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0006;
    scene.add(sun); scene.add(sun.target);

    var ground = new THREE.Mesh(
      new THREE.CircleGeometry(diag * 2.2, 64),
      new THREE.MeshStandardMaterial({ color: COL.ground, roughness: 1, metalness: 0 }));
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(c.x, -0.02, c.z);
    ground.receiveShadow = true;
    scene.add(ground);

    var gsize = Math.ceil(diag * 2.4 / 10) * 10;
    var grid = new THREE.GridHelper(gsize, Math.max(4, gsize / 10), 0x28324a, 0x1a2233);
    grid.position.set(c.x, -0.01, c.z);
    grid.material.transparent = true;
    grid.material.opacity = 0.35;
    scene.add(grid);
  }

  // Per-point unit tangents (three coords) and MATLAB-left normals.
  // three forward = (cos h, -sin h); MATLAB-left of travel = (fz, -fx).
  function trackFrames(def) {
    var n = def.pts.length;
    var tan = [], nor = [];
    for (var i = 0; i < n; i++) {
      var a = def.closed ? def.pts[(i - 1 + n) % n] : def.pts[Math.max(0, i - 1)];
      var b = def.closed ? def.pts[(i + 1) % n] : def.pts[Math.min(n - 1, i + 1)];
      var dx = b[0] - a[0], dy = b[1] - a[1];
      var len = Math.hypot(dx, dy) || 1;
      var fx = dx / len, fz = -dy / len;
      tan.push([fx, fz]);
      nor.push([fz, -fx]);
    }
    return { tan: tan, nor: nor };
  }

  function buildTrackMesh(def) {
    var group = new THREE.Group();
    var n = def.pts.length;
    if (n < 2) return null;
    var fr = trackFrames(def);
    var i;

    // Asphalt ribbon.
    var pos = new Float32Array(n * 2 * 3);
    for (i = 0; i < n; i++) {
      var p = def.pts[i], m = fr.nor[i];
      pos[i * 6 + 0] = p[0] + m[0] * def.halfL[i];
      pos[i * 6 + 1] = 0.02;
      pos[i * 6 + 2] = -p[1] + m[1] * def.halfL[i];
      pos[i * 6 + 3] = p[0] - m[0] * def.halfR[i];
      pos[i * 6 + 4] = 0.02;
      pos[i * 6 + 5] = -p[1] - m[1] * def.halfR[i];
    }
    var idx = [];
    var segs = def.closed ? n : n - 1;
    for (var s = 0; s < segs; s++) {
      var a = s, b = (s + 1) % n;
      idx.push(a * 2, a * 2 + 1, b * 2, a * 2 + 1, b * 2 + 1, b * 2);
    }
    var up = new Float32Array(n * 2 * 3);
    for (i = 0; i < n * 2; i++) up[i * 3 + 1] = 1;
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(up, 3));
    geo.setIndex(idx);
    var asphalt = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
      color: COL.asphalt, roughness: 0.96, metalness: 0 }));
    asphalt.receiveShadow = true;
    group.add(asphalt);

    // Edge lines just inside the cone line.
    function edgeLine(side, inset) {
      var arr = new Float32Array(n * 3);
      for (var e = 0; e < n; e++) {
        var pe = def.pts[e], me = fr.nor[e];
        var half = (side > 0 ? def.halfL[e] : def.halfR[e]) - inset;
        arr[e * 3] = pe[0] + me[0] * half * side;
        arr[e * 3 + 1] = 0.05;
        arr[e * 3 + 2] = -pe[1] + me[1] * half * side;
      }
      var g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(arr, 3));
      return new THREE.Line(g, new THREE.LineBasicMaterial({
        color: COL.edge, transparent: true, opacity: 0.7 }));
    }
    group.add(edgeLine(1, 0.15));
    group.add(edgeLine(-1, 0.15));

    // Start / finish checker strip across the track.
    var start = new THREE.Group();
    start.position.set(def.pts[0][0], 0.045, -def.pts[0][1]);
    start.rotation.y = Math.atan2(fr.tan[0][1], fr.tan[0][0]);
    var across = def.halfL[0] + def.halfR[0];
    var cols = Math.max(6, Math.round(across / 0.5));
    var cell = across / cols;
    var cellGeo = new THREE.PlaneGeometry(0.55, cell);
    for (var r = 0; r < 2; r++) {
      for (var c2 = 0; c2 < cols; c2++) {
        var q = new THREE.Mesh(cellGeo, new THREE.MeshStandardMaterial({
          color: ((r + c2) % 2 === 0) ? 0xe8e8e8 : 0x141414, roughness: 0.9 }));
        q.rotation.x = -Math.PI / 2;
        q.position.set(0.28 + r * 0.55, 0, -across / 2 + def.halfR[0] + cell * (c2 + 0.5));
        start.add(q);
      }
    }
    group.add(start);

    // Corner cones down both edges.
    var cones = null;
    var trackLen = 0;
    for (i = 1; i < n; i++) trackLen += Math.hypot(
      def.pts[i][0] - def.pts[i - 1][0], def.pts[i][1] - def.pts[i - 1][1]);
    var perSide = Math.max(2, Math.floor(trackLen / 7));
    cones = new THREE.InstancedMesh(
      new THREE.ConeGeometry(0.11, 0.34, 8),
      new THREE.MeshStandardMaterial({ color: COL.cone, roughness: 0.55 }),
      perSide * 2);
    cones.castShadow = true;
    var mtx = new THREE.Matrix4();
    var placed = 0, acc = 3.5;
    for (i = 1; i < n && placed < perSide * 2; i++) {
      acc += Math.hypot(def.pts[i][0] - def.pts[i - 1][0],
        def.pts[i][1] - def.pts[i - 1][1]);
      if (acc < 7) continue;
      acc -= 7;
      var mc = fr.nor[i], px = def.pts[i][0], pz = -def.pts[i][1];
      cones.setMatrixAt(placed++, mtx.makeTranslation(
        px + mc[0] * (def.halfL[i] + 0.55), 0, pz + mc[1] * (def.halfL[i] + 0.55)));
      if (placed < perSide * 2) {
        cones.setMatrixAt(placed++, mtx.makeTranslation(
          px - mc[0] * (def.halfR[i] + 0.55), 0, pz - mc[1] * (def.halfR[i] + 0.55)));
      }
    }
    for (var z2 = placed; z2 < perSide * 2; z2++) {
      cones.setMatrixAt(z2, mtx.makeTranslation(0, -10, 0));
    }
    cones.instanceMatrix.needsUpdate = true;
    group.add(cones);

    scene.add(group);
    return cones;
  }

  // ------------------------------------------------------------------- cars

  var simCar = buildCar(COL.sim, false, 'SIM');
  var realCar = real ? buildCar(COL.real, true, 'REAL') : null;
  scene.add(simCar.root);
  if (realCar) scene.add(realCar.root);

  function makeLabel(text, colorCss) {
    var c = document.createElement('canvas');
    c.width = 128; c.height = 40;
    var g = c.getContext('2d');
    g.fillStyle = 'rgba(10,14,22,0.78)';
    g.strokeStyle = colorCss;
    g.lineWidth = 3;
    if (g.roundRect) { g.beginPath(); g.roundRect(4, 4, 120, 32, 8); g.fill(); g.stroke(); }
    else { g.fillRect(4, 4, 120, 32); g.strokeRect(4, 4, 120, 32); }
    g.fillStyle = colorCss;
    g.font = '700 19px system-ui, Segoe UI, sans-serif';
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, 64, 21);
    var spr = new THREE.Sprite(new THREE.SpriteMaterial({
      map: new THREE.CanvasTexture(c), depthTest: true }));
    spr.scale.set(1.5, 0.47, 1);
    spr.position.y = 1.25;
    return spr;
  }

  function buildCar(color, ghost, label) {
    var root = new THREE.Group();
    var tilt = new THREE.Group(); // roll/pitch without lifting the wheels
    root.add(tilt);

    function mat(opts) {
      var m = new THREE.MeshStandardMaterial({
        color: opts.color,
        roughness: opts.rough !== undefined ? opts.rough : 0.5,
        metalness: opts.metal !== undefined ? opts.metal : 0.15
      });
      if (ghost) { m.transparent = true; m.opacity = 0.55; m.depthWrite = false; }
      return m;
    }
    function box(w, h, d, x, y, z, m) {
      var mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
      mesh.position.set(x, y, z);
      mesh.castShadow = true;
      return mesh;
    }

    var bodyMat = mat({ color: color, rough: 0.34, metal: 0.2 });
    var darkMat = mat({ color: 0x14171c, rough: 0.7, metal: 0.1 });
    var frameMat = mat({ color: 0x2a2f38, rough: 0.4, metal: 0.6 });

    tilt.add(box(1.42, 0.16, 0.56, 0.02, 0.33, 0, bodyMat));            // tub
    tilt.add(box(1.30, 0.03, 0.60, 0.00, 0.14, 0, darkMat));            // floor
    tilt.add(box(0.78, 0.20, 0.20, -0.05, 0.31, 0.35, bodyMat));        // sidepods
    tilt.add(box(0.78, 0.20, 0.20, -0.05, 0.31, -0.35, bodyMat));
    var nose = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.17, 0.55, 6), bodyMat);
    nose.rotation.z = -Math.PI / 2;
    nose.position.set(0.98, 0.30, 0);
    nose.castShadow = true;
    tilt.add(nose);

    tilt.add(box(0.30, 0.035, 1.14, 1.20, 0.17, 0, darkMat));           // front wing
    tilt.add(box(0.34, 0.13, 0.03, 1.20, 0.22, 0.57, bodyMat));
    tilt.add(box(0.34, 0.13, 0.03, 1.20, 0.22, -0.57, bodyMat));

    var hoop = new THREE.Mesh(
      new THREE.TorusGeometry(0.17, 0.028, 8, 18, Math.PI), frameMat);
    hoop.position.set(-0.34, 0.42, 0);
    hoop.castShadow = true;
    tilt.add(hoop);
    var helmet = new THREE.Mesh(new THREE.SphereGeometry(0.105, 16, 12),
      mat({ color: 0xe8edf5, rough: 0.25 }));
    helmet.position.set(-0.16, 0.52, 0);
    helmet.castShadow = true;
    tilt.add(helmet);

    tilt.add(box(0.30, 0.035, 1.02, -1.02, 0.74, 0, darkMat));          // rear wing
    tilt.add(box(0.36, 0.16, 0.03, -1.02, 0.68, 0.51, bodyMat));
    tilt.add(box(0.36, 0.16, 0.03, -1.02, 0.68, -0.51, bodyMat));
    tilt.add(box(0.05, 0.34, 0.05, -1.02, 0.50, 0, frameMat));

    // Wheels: cylinder axis pre-rotated onto local z (the axle direction).
    var wheels = { spin: [], steer: [] };
    var tireGeoF = new THREE.CylinderGeometry(WHEEL_R, WHEEL_R, 0.16, 18);
    var tireGeoR = new THREE.CylinderGeometry(WHEEL_R, WHEEL_R, 0.24, 18);
    var rimGeoF = new THREE.CylinderGeometry(WHEEL_R * 0.55, WHEEL_R * 0.55, 0.166, 12);
    var rimGeoR = new THREE.CylinderGeometry(WHEEL_R * 0.55, WHEEL_R * 0.55, 0.246, 12);
    tireGeoF.rotateX(Math.PI / 2); tireGeoR.rotateX(Math.PI / 2);
    rimGeoF.rotateX(Math.PI / 2); rimGeoR.rotateX(Math.PI / 2);
    var tireMat = mat({ color: 0x0e1013, rough: 0.95, metal: 0 });
    var rimMat = mat({ color: 0x8a939f, rough: 0.3, metal: 0.85 });

    function wheel(x, z, front) {
      var pivot = new THREE.Group();
      pivot.position.set(x, WHEEL_R, z);
      var spinGrp = new THREE.Group();
      var tire = new THREE.Mesh(front ? tireGeoF : tireGeoR, tireMat);
      tire.castShadow = true;
      spinGrp.add(tire);
      spinGrp.add(new THREE.Mesh(front ? rimGeoF : rimGeoR, rimMat));
      pivot.add(spinGrp);
      root.add(pivot);
      wheels.spin.push(spinGrp);
      if (front) wheels.steer.push(pivot);
    }
    wheel(0.78, 0.56, true); wheel(0.78, -0.56, true);
    wheel(-0.78, 0.58, false); wheel(-0.78, -0.58, false);

    var label3d = makeLabel(label, ghost ? '#ff8b93' : '#8db6ff');
    tilt.add(label3d);

    return { root: root, tilt: tilt, wheels: wheels, label: label3d, angle: 0 };
  }

  // ----------------------------------------------------------------- trails

  function fullLine(run, color) {
    var arr = new Float32Array(run.x.length * 3);
    for (var i = 0; i < run.x.length; i++) {
      arr[i * 3] = run.x[i]; arr[i * 3 + 1] = 0.05; arr[i * 3 + 2] = -run.y[i];
    }
    var g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(arr, 3));
    return new THREE.Line(g, new THREE.LineBasicMaterial({
      color: color, transparent: true, opacity: 0.4 }));
  }
  var simPathLine = fullLine(sim, COL.sim);
  var realPathLine = real ? fullLine(real, COL.real) : null;
  scene.add(simPathLine);
  if (realPathLine) scene.add(realPathLine);

  function CometTrail(colorHex) {
    this.pos = new Float32Array(COMET * 3);
    this.col = new Float32Array(COMET * 3);
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.col, 3));
    this.base = new THREE.Color(colorHex);
    this.fadeTo = new THREE.Color(0x0b0f16);
    this.line = new THREE.Line(geo, new THREE.LineBasicMaterial({
      vertexColors: true, transparent: true, opacity: 0.95 }));
    this.line.frustumCulled = false;
    scene.add(this.line);
  }
  CometTrail.prototype.reset = function () {
    this.line.geometry.setDrawRange(0, 0);
  };
  CometTrail.prototype.update = function (run, idx, hx, hz) {
    var head = Math.floor(idx);
    var count = Math.min(COMET, head + 2); // history samples + live head point
    var start = Math.max(0, head - (count - 2));
    var pts = [];
    for (var i = start; i <= head; i++) {
      if (isFinite(run.x[i]) && isFinite(run.y[i])) pts.push([run.x[i], -run.y[i]]);
    }
    pts.push([hx, hz]);
    if (pts.length < 2) { this.reset(); return; }
    if (pts.length > COMET) pts = pts.slice(pts.length - COMET);
    var m = pts.length;
    for (var j = 0; j < m; j++) {
      this.pos[j * 3] = pts[j][0];
      this.pos[j * 3 + 1] = 0.06;
      this.pos[j * 3 + 2] = pts[j][1];
      var f = 1 - j / (m - 1); // 1 at head
      var c = this.fadeTo.clone().lerp(this.base, 0.12 + 0.88 * f * f);
      this.col[j * 3] = c.r; this.col[j * 3 + 1] = c.g; this.col[j * 3 + 2] = c.b;
    }
    this.line.geometry.setDrawRange(0, m);
    this.line.geometry.attributes.position.needsUpdate = true;
    this.line.geometry.attributes.color.needsUpdate = true;
  };
  var simComet = new CometTrail(COL.sim);
  var realComet = real ? new CometTrail(COL.real) : null;

  // --------------------------------------------------------------- playback

  var player = { idx: 0, playing: true, rate: 1, loop: true };
  var camMode = 'orbit';
  var showTrail = true;

  function setPlaying(on) {
    player.playing = on;
    $('playIconPlay').style.display = on ? 'none' : '';
    $('playIconPause').style.display = on ? '' : 'none';
    $('playBtn').setAttribute('aria-label', on ? 'Pause' : 'Play');
  }
  function seekIndex(i) { player.idx = clamp(i, 0, N - 1); }
  function spanToIdx(units) { return units / span * (N - 1); }

  // ---------------------------------------------------------------- cameras

  var orbit = {
    target: center(), radius: diag * 0.95, theta: -Math.PI / 4,
    phi: 1.02, drag: 0, x: 0, y: 0
  };
  var chase = { dist: 7.5, height: 2.7 };
  var smoothPos = new THREE.Vector3();
  var smoothLook = new THREE.Vector3();
  var smoothInit = false;

  function carPos(car) {
    return new THREE.Vector3(car.root.position.x, 0, car.root.position.z);
  }
  function carFwd(car) {
    return new THREE.Vector3(Math.cos(car.angle), 0, -Math.sin(car.angle));
  }

  function setCamera(mode, keepTarget) {
    camMode = mode;
    smoothInit = false;
    if (mode === 'orbit' && !keepTarget) {
      orbit.target.copy(carPos(simCar));
      orbit.radius = clamp(diag * 0.18, 35, 80);
    }
    var btns = document.querySelectorAll('#camBox button');
    for (var i = 0; i < btns.length; i++) {
      btns[i].classList.toggle('active', btns[i].getAttribute('data-cam') === mode);
    }
    toast(mode.charAt(0).toUpperCase() + mode.slice(1) + ' camera');
  }

  function approach(desiredPos, desiredLook, k, upVec) {
    if (!smoothInit) {
      smoothPos.copy(desiredPos); smoothLook.copy(desiredLook); smoothInit = true;
    }
    smoothPos.lerp(desiredPos, k);
    smoothLook.lerp(desiredLook, k);
    camera.up.copy(upVec);
    camera.position.copy(smoothPos);
    camera.lookAt(smoothLook);
  }

  function updateCamera(dt) {
    var p = carPos(simCar), f = carFwd(simCar);
    var k = 1 - Math.exp(-dt * 5);
    if (camMode === 'orbit') {
      var sp = Math.sin(orbit.phi), cp = Math.cos(orbit.phi);
      camera.up.set(0, 1, 0);
      camera.position.set(
        orbit.target.x + orbit.radius * sp * Math.cos(orbit.theta),
        orbit.target.y + orbit.radius * cp,
        orbit.target.z + orbit.radius * sp * Math.sin(orbit.theta));
      camera.lookAt(orbit.target);
    } else if (camMode === 'chase') {
      approach(p.clone().addScaledVector(f, -chase.dist).setY(chase.height),
        p.clone().addScaledVector(f, 3.5).setY(0.6), k, new THREE.Vector3(0, 1, 0));
    } else if (camMode === 'cockpit') {
      camera.position.copy(p.clone().addScaledVector(f, -0.15).setY(0.95));
      camera.up.set(0, 1, 0).applyAxisAngle(f, simCar.tilt.rotation.x * 0.8);
      camera.lookAt(p.clone().addScaledVector(f, 14).setY(0.4));
    } else { // top
      approach(p.clone().setY(clamp(diag * 0.18, 32, 70)), p,
        1 - Math.exp(-dt * 4), new THREE.Vector3(0, 0, -1));
    }
  }

  canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  canvas.addEventListener('pointerdown', function (e) {
    orbit.drag = (e.button === 2 || e.shiftKey) ? 2 : 1;
    orbit.x = e.clientX; orbit.y = e.clientY;
    try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
  });
  canvas.addEventListener('pointermove', function (e) {
    if (!orbit.drag) return;
    var dx = e.clientX - orbit.x, dy = e.clientY - orbit.y;
    orbit.x = e.clientX; orbit.y = e.clientY;
    if (camMode !== 'orbit') setCamera('orbit');
    if (orbit.drag === 1) {
      orbit.theta -= dx * 0.005;
      orbit.phi = clamp(orbit.phi - dy * 0.005, 0.08, Math.PI / 2 - 0.03);
    } else {
      // Screen-right in orbit view is (sin0, 0, -cos0); view forward is its
      // 90-degree rotation. Drag moves the target against the drag.
      var kk = orbit.radius * 0.0011;
      var right = new THREE.Vector3(Math.sin(orbit.theta), 0, -Math.cos(orbit.theta));
      var fwd = new THREE.Vector3(Math.cos(orbit.theta), 0, Math.sin(orbit.theta)).negate();
      orbit.target.addScaledVector(right, -dx * kk);
      orbit.target.addScaledVector(fwd, -dy * kk);
      orbit.target.x = clamp(orbit.target.x, bounds.min.x - diag, bounds.max.x + diag);
      orbit.target.z = clamp(orbit.target.z, bounds.min.z - diag, bounds.max.z + diag);
    }
  });
  window.addEventListener('pointerup', function () { orbit.drag = 0; });
  canvas.addEventListener('wheel', function (e) {
    e.preventDefault();
    var f = Math.exp(e.deltaY * 0.0011);
    if (camMode === 'orbit') orbit.radius = clamp(orbit.radius * f, 4, diag * 4);
    else if (camMode === 'chase') chase.dist = clamp(chase.dist * f, 3, 40);
  }, { passive: false });

  // ------------------------------------------------------------------- HUD

  var lastDt = 1 / 60;

  function applyState() {
    var i = player.idx;
    var s = sample(sim, i);
    var r = real ? sample(real, i) : null;

    simCar.root.position.set(s.x, 0, s.z);
    simCar.root.rotation.y = s.h;
    simCar.angle = s.h;
    simCar.tilt.rotation.x = s.roll;
    simCar.tilt.rotation.z = s.pitch;
    spinWheels(simCar, s.v, s.st);
    if (showTrail) simComet.update(sim, i, s.x, s.z); else simComet.reset();

    if (realCar && r) {
      realCar.root.position.set(r.x, 0, r.z);
      realCar.root.rotation.y = r.h;
      realCar.angle = r.h;
      realCar.tilt.rotation.x = r.roll;
      realCar.tilt.rotation.z = r.pitch;
      spinWheels(realCar, r.v, r.st);
      if (showTrail) realComet.update(real, i, r.x, r.z); else realComet.reset();
    }

    $('speedVal').textContent = Math.max(0, s.v).toFixed(0);
    $('thFill').style.width = (clamp(s.th, 0, 1) * 100).toFixed(1) + '%';
    $('brFill').style.width = (clamp(s.br, 0, 1) * 100).toFixed(1) + '%';
    $('steerGlyph').style.transform =
      'rotate(' + (-s.st * 180 / Math.PI * 4.5).toFixed(1) + 'deg)';
    $('latGVal').textContent = s.la.toFixed(2);
    if (r) {
      $('deltaPathVal').textContent =
        Math.hypot(s.x - r.x, s.z - r.z).toFixed(2);
    }
    $('timeNow').textContent = fmtSpan(Math.max(0, s.t - t0));
    $('scrubber').value = Math.round(i / (N - 1) * 1000);
    drawCharts(i / (N - 1));
  }

  function spinWheels(car, vKmh, steer) {
    var dSpin = (vKmh / 3.6) / WHEEL_R * lastDt;
    for (var w = 0; w < car.wheels.spin.length; w++) {
      car.wheels.spin[w].rotation.z -= dSpin;
    }
    // Exaggerate the road-wheel angle ~1.5x so it reads at replay speed.
    var steerVis = clamp(steer * 1.5, -0.6, 0.6);
    for (var p = 0; p < car.wheels.steer.length; p++) {
      car.wheels.steer[p].rotation.y = steerVis;
    }
  }

  // ---------------------------------------------------------------- charts

  function makeChart(canvasEl, series, unit) {
    var info = { canvas: canvasEl, ctx: canvasEl.getContext('2d'),
      series: series, unit: unit, max: 1, w: 0, h: 0 };
    var mx = 0;
    for (var s = 0; s < series.length; s++) {
      var arr = series[s].run[series[s].key];
      var scale = series[s].scale || 1;
      for (var i = 0; i < arr.length; i++) {
        var v = num(arr[i], 0) * scale;
        if (v > mx) mx = v;
      }
    }
    info.max = Math.max(1, mx * 1.08);
    resizeChart(info);
    canvasEl.addEventListener('pointerdown', function (e) {
      seekFromEvent(info, e); chartDrag = info;
    });
    canvasEl.addEventListener('pointermove', function (e) {
      if (chartDrag === info) seekFromEvent(info, e);
    });
    return info;
  }
  var chartDrag = null;
  window.addEventListener('pointerup', function () { chartDrag = null; });

  function resizeChart(info) {
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var w = info.canvas.clientWidth || 300, h = info.canvas.clientHeight || 86;
    info.canvas.width = Math.round(w * dpr);
    info.canvas.height = Math.round(h * dpr);
    info.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    info.w = w; info.h = h;
  }
  function seekFromEvent(info, e) {
    var rect = info.canvas.getBoundingClientRect();
    seekIndex(clamp((e.clientX - rect.left) / rect.width, 0, 1) * (N - 1));
  }
  function drawChart(info, cursorF) {
    var ctx = info.ctx, w = info.w, h = info.h;
    if (w === 0) { resizeChart(info); return; }
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#0d1119';
    ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = '#1b2433';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (var g = 1; g <= 3; g++) {
      var gy = Math.round(h * g / 4) + 0.5;
      ctx.moveTo(0, gy); ctx.lineTo(w, gy);
    }
    ctx.stroke();
    for (var s = 0; s < info.series.length; s++) {
      var spec = info.series[s];
      var arr = spec.run[spec.key];
      var n = arr.length, scale = spec.scale || 1;
      ctx.strokeStyle = spec.color;
      ctx.lineWidth = 1.6;
      ctx.setLineDash(spec.dash ? [5, 4] : []);
      ctx.beginPath();
      for (var i = 0; i < n; i++) {
        var x = i / (n - 1) * w;
        var y = h - 3 - clamp(num(arr[i], 0) * scale / info.max, 0, 1) * (h - 10);
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.stroke();
      ctx.setLineDash([]);
    }
    var cx = cursorF * w;
    ctx.fillStyle = 'rgba(255,209,102,0.10)';
    ctx.fillRect(0, 0, cx, h);
    ctx.strokeStyle = '#ffd166';
    ctx.lineWidth = 1.4;
    ctx.beginPath(); ctx.moveTo(cx + 0.5, 0); ctx.lineTo(cx + 0.5, h); ctx.stroke();
    ctx.fillStyle = '#5d6a7e';
    ctx.font = '10px system-ui, Segoe UI, sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText(Math.round(info.max) + ' ' + info.unit, 6, 11);
  }

  var chartSpeed = makeChart($('chartSpeed'), [
    { run: sim, key: 'v', color: '#4f8cff' }
  ].concat(real ? [{ run: real, key: 'v', color: '#ff5964', dash: true }] : []),
    'km/h');
  var chartInputs = makeChart($('chartInputs'), [
    { run: sim, key: 'th', color: '#3fd68f', scale: 100 },
    { run: sim, key: 'br', color: '#ff5964', scale: 100 }
  ].concat(real ? [
    { run: real, key: 'th', color: '#7bd8ab', scale: 100, dash: true },
    { run: real, key: 'br', color: '#ff9aa1', scale: 100, dash: true }
  ] : []), '%');

  function drawCharts(cursorF) {
    drawChart(chartSpeed, cursorF);
    drawChart(chartInputs, cursorF);
  }

  // ------------------------------------------------------------- UI wiring

  var title = S.meta.title || 'LTS 3D Replay';
  $('title').textContent = title;
  document.title = title + ' — LTSViz';
  $('files').innerHTML =
    '<b>' + esc(S.meta.simLabel || 'Simulation') + '</b> ' + esc(S.meta.simFile || '') +
    (S.meta.hasReal
      ? ' &nbsp;·&nbsp; <b>' + esc(S.meta.realLabel || 'Reality') + '</b> ' +
        esc(S.meta.realFile || '')
      : ' &nbsp;·&nbsp; reality run not supplied');

  var chips = [];
  if (S.meta.metrics) {
    var mm = S.meta.metrics;
    if (isFiniteNum(mm.path_error_mean_m)) {
      chips.push(['mean Δpath', mm.path_error_mean_m.toFixed(2) + ' m']);
    }
    if (isFiniteNum(mm.path_error_max_m)) {
      chips.push(['max Δpath', mm.path_error_max_m.toFixed(2) + ' m']);
    }
    if (isFiniteNum(mm.speed_delta_mean_mps)) {
      chips.push(['mean Δv', mm.speed_delta_mean_mps.toFixed(2) + ' m/s']);
    }
  }
  chips.push(['run', fmtSpan(span)]);
  var chipHost = $('metricChips');
  for (var c = 0; c < chips.length; c++) {
    var el = document.createElement('span');
    el.className = 'chip';
    el.innerHTML = chips[c][0] + ' <b>' + esc(chips[c][1]) + '</b>';
    chipHost.appendChild(el);
  }

  $('timeTotal').textContent = '/ ' + fmtSpan(span);
  if (!S.meta.attitudeEstimated) $('noteAttitude').style.display = 'none';
  if (!real) {
    $('tgReal').style.display = 'none';
    $('deltaPathChip').style.display = 'none';
  }

  $('playBtn').addEventListener('click', function () { setPlaying(!player.playing); });
  $('backBtn').addEventListener('click', function () {
    seekIndex(player.idx - spanToIdx(2));
  });
  $('fwdBtn').addEventListener('click', function () {
    seekIndex(player.idx + spanToIdx(2));
  });
  $('scrubber').addEventListener('input', function (e) {
    seekIndex(e.target.value / 1000 * (N - 1));
  });
  $('rateSel').addEventListener('change', function (e) { player.rate = +e.target.value; });
  $('loopBtn').addEventListener('click', function () {
    player.loop = !player.loop;
    this.classList.toggle('active', player.loop);
  });
  $('loopBtn').classList.add('active');

  $('tgSim').addEventListener('change', function (e) {
    simCar.root.visible = e.target.checked;
  });
  $('tgReal').addEventListener('change', function (e) {
    if (realCar) realCar.root.visible = e.target.checked;
  });
  $('tgTrail').addEventListener('change', function (e) {
    showTrail = e.target.checked;
    simPathLine.visible = showTrail;
    if (realPathLine) realPathLine.visible = showTrail;
  });
  $('tgCones').addEventListener('change', function (e) {
    if (trackCones) trackCones.visible = e.target.checked;
  });
  $('tgLabels').addEventListener('change', function (e) {
    simCar.label.visible = e.target.checked;
    if (realCar) realCar.label.visible = e.target.checked;
  });

  var camBtns = document.querySelectorAll('#camBox button');
  for (var b = 0; b < camBtns.length; b++) {
    camBtns[b].addEventListener('click', function () {
      setCamera(this.getAttribute('data-cam'));
    });
  }
  $('helpBtn').addEventListener('click', function () { $('help').hidden = !$('help').hidden; });
  $('helpClose').addEventListener('click', function () { $('help').hidden = true; });
  $('help').addEventListener('click', function (e) {
    if (e.target === this) $('help').hidden = true;
  });

  window.addEventListener('keydown', function (e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
    switch (e.key) {
      case ' ': e.preventDefault(); setPlaying(!player.playing); break;
      case 'ArrowLeft':
        e.preventDefault();
        seekIndex(player.idx - spanToIdx(e.shiftKey ? 10 : 2));
        break;
      case 'ArrowRight':
        e.preventDefault();
        seekIndex(player.idx + spanToIdx(e.shiftKey ? 10 : 2));
        break;
      case 'ArrowUp': e.preventDefault(); bumpRate(1); break;
      case 'ArrowDown': e.preventDefault(); bumpRate(-1); break;
      case 'c': case 'C': cycleCamera(); break;
      case 'r': case 'R': seekIndex(0); break;
      case 'l': case 'L': $('loopBtn').click(); break;
      case 't': case 'T': $('tgTrail').checked = !$('tgTrail').checked; $('tgTrail').dispatchEvent(new Event('change')); break;
      case '?': case 'h': case 'H': $('help').hidden = !$('help').hidden; break;
    }
  });

  function cycleCamera() {
    var modes = ['orbit', 'chase', 'cockpit', 'top'];
    setCamera(modes[(modes.indexOf(camMode) + 1) % modes.length]);
  }
  function bumpRate(dir) {
    var steps = [0.25, 0.5, 1, 2, 4];
    var cur = clamp(steps.indexOf(player.rate) + dir, 0, steps.length - 1);
    player.rate = steps[cur];
    $('rateSel').value = String(player.rate);
    toast(player.rate + '× speed');
  }

  var toastTimer = null;
  function toast(msg) {
    var t = $('toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.classList.remove('show'); }, 1400);
  }

  // ---------------------------------------------------------------- resize

  function resize() {
    var w = $('main').clientWidth, h = $('main').clientHeight;
    if (w === 0 || h === 0) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    resizeChart(chartSpeed);
    resizeChart(chartInputs);
  }
  window.addEventListener('resize', resize);

  // ------------------------------------------------------------------ loop

  var clock = new THREE.Clock();
  var firstFrame = true;

  function frame() {
    requestAnimationFrame(frame);
    var dt = clock.getDelta();
    lastDt = Math.min(dt, 0.1);
    if (player.playing) {
      var i = player.idx + lastDt * player.rate * (N - 1) / span;
      if (i > N - 1) {
        if (player.loop) {
          i -= (N - 1) * Math.ceil((i - (N - 1)) / (N - 1));
        } else { i = N - 1; setPlaying(false); }
      }
      player.idx = i;
    }
    applyState();
    updateCamera(lastDt);
    renderer.render(scene, camera);
    if (firstFrame) {
      firstFrame = false;
      var l = $('loading');
      l.style.opacity = '0';
      setTimeout(function () { l.hidden = true; }, 450);
    }
  }

  resize();
  applyState();
  // Deep links: ?t=42.5 seeks to a moment, ?cam=chase|cockpit|top|orbit
  // picks the camera, ?rate=0.5 sets speed, ?play=0 starts paused.
  var q = {};
  try {
    window.location.search.replace(/[?&]([^=&]+)=([^&]*)/g, function (_, k, v) {
      q[decodeURIComponent(k)] = decodeURIComponent(v);
    });
  } catch (e) { /* ignore malformed query */ }
  if (q.t !== undefined && isFinite(+q.t)) {
    seekIndex((clamp(+q.t, 0, span) / span) * (N - 1));
  }
  if (q.rate !== undefined && isFinite(+q.rate) && +q.rate > 0) {
    player.rate = +q.rate;
    var opts = $('rateSel').options;
    for (var oi = 0; oi < opts.length; oi++) {
      opts[oi].selected = String(player.rate) === opts[oi].value;
    }
  }
  applyState();
  // Open on the grid with the car filling the frame; drag or press Orbit
  // for the circuit overview.
  orbit.target.copy(carPos(simCar));
  orbit.radius = clamp(diag * 0.4, 26, 90);
  var cam0 = (q.cam && ['orbit', 'chase', 'cockpit', 'top'].indexOf(q.cam) >= 0) ?
    q.cam : 'chase';
  setCamera(cam0, true);
  setPlaying(q.play !== '0');
  frame();
})();
