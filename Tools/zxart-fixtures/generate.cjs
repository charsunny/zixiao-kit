#!/usr/bin/env node
// ZXArt parity harness — runs the ORIGINAL LingDong- JavaScript headlessly (node:vm + a
// minimal DOM/canvas shim) and dumps fixtures that the Swift port is tested against.
//
//   node Tools/zxart-fixtures/generate.cjs            # writes Tests/ZixiaoArtTests/Fixtures/zxart/*.json
//   ZXART_SRC=/path/to/clones node ...                # reuse existing clones
//
// Sources are pinned to exact commits (MIT, (c) 2018 Lingdong Huang):
//   https://github.com/LingDong-/shan-shui-inf  @ 9f754d2b2e73495db7883d4d4055a7b0903b0454
//   https://github.com/LingDong-/nonflowers     @ 03b653d220f16c6bed7ea9c7edc852f7e91846cb
//
// What is dumped per seed:
//   (a) the PRNG: integer state after seeding + the first 64 outputs (exact doubles)
//   (b) Perlin samples (table lazily filled from the PRNG exactly like the originals)
//   (c) geometry: every polygon the original emits for a set of primitives / generators,
//       in DRAW order (shan-shui returns SVG strings; `poly` is replaced by a recorder that
//       returns a token, so the final string gives the paint order), plus the PRNG state
//       afterwards (proves identical random consumption). Big cases are summarised by
//       counts + weighted checksums; small ones keep every point.

"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { execSync } = require("child_process");

const SHAN_SHA = "9f754d2b2e73495db7883d4d4055a7b0903b0454";
const FLOW_SHA = "03b653d220f16c6bed7ea9c7edc852f7e91846cb";
const SEEDS = ["1", "42", "2026"];

const repoRoot = path.resolve(__dirname, "..", "..");
const outDir = path.join(repoRoot, "Tests", "ZixiaoArtTests", "Fixtures", "zxart");
const srcRoot = process.env.ZXART_SRC || "/tmp/zxart-src";

function ensureClone(name, sha) {
  const dir = path.join(srcRoot, name);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(srcRoot, { recursive: true });
    execSync(`git clone -q https://github.com/LingDong-/${name} ${dir}`);
  }
  try {
    execSync(`git -C ${dir} cat-file -e ${sha}^{commit}`, { stdio: "ignore" });
  } catch (e) {
    execSync(`git -C ${dir} fetch -q --unshallow || git -C ${dir} fetch -q origin`);
  }
  execSync(`git -C ${dir} checkout -q ${sha}`);
  return dir;
}

// ---------------------------------------------------------------------------------------
// shims

function makeElement() {
  const el = {
    style: {}, innerHTML: "", value: "", children: [],
    setAttribute() {}, addEventListener() {}, appendChild(c) { this.children.push(c); return c; },
    scrollTo() {},
  };
  return el;
}

let ctxCounter = 0;
function makeCanvas() {
  const canvas = { width: 300, height: 150, style: {} };
  const ctx = {
    canvas, __id: ctxCounter++, globalCompositeOperation: "source-over",
    _fill: null, paperSum: 0, paperCount: 0, paperFirst: [],
    beginPath() {}, moveTo() {}, lineTo() {}, fill() {}, stroke() {}, fillText() {},
    fillRect() {}, drawImage() {},
    getImageData(x, y, w, h) { return { data: [] }; },
    putImageData() {},
  };
  Object.defineProperty(ctx, "fillStyle", { configurable: true,
    get() { return this._fill; },
    set(v) { this._fill = v; },
  });
  canvas.getContext = () => ctx;
  canvas.toDataURL = () => "";
  return canvas;
}

function makeSandbox(seed) {
  const sb = {
    console: { log() {}, warn() {}, error() {} },
    btoa: (s) => Buffer.from(s, "latin1").toString("base64"),
    setTimeout() {},
    Date,
  };
  sb.window = sb;
  sb.self = sb;
  sb.location = { href: "http://localhost/index.html?seed=" + seed };
  sb.window.location = sb.location;
  sb.document = {
    getElementById: () => makeElement(),
    addEventListener() {},
    createElement: (tag) => (tag === "canvas" ? makeCanvas() : makeElement()),
    getElementsByTagName: () => [makeElement()],
    body: makeElement(),
  };
  return vm.createContext(sb);
}

// ---------------------------------------------------------------------------------------
// shan-shui

function shanScripts(dir) {
  const html = fs.readFileSync(path.join(dir, "index.html"), "utf8");
  const blocks = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  // 0 PRNG, 1 seed-from-url, 2 PerlinNoise, 3 PolyTools, 4 Util, 5 generators + planner
  return blocks.slice(0, 6);
}

function shanContext(scripts, seed) {
  const ctx = makeSandbox(seed);
  for (const s of scripts) vm.runInContext(s, ctx);
  // Recorder: poly() returns a token; the final string gives paint order.
  ctx.__polys = [];
  ctx.poly = function (plist, args) {
    args = args || {};
    const xof = args.xof !== undefined ? args.xof : 0;
    const yof = args.yof !== undefined ? args.yof : 0;
    const fil = args.fil !== undefined ? args.fil : "rgba(0,0,0,0)";
    const str = args.str !== undefined ? args.str : fil;
    const wid = args.wid !== undefined ? args.wid : 0;
    const id = ctx.__polys.length;
    ctx.__polys.push({ p: plist.map((v) => [v[0] + xof, v[1] + yof]), f: fil, s: str, w: wid });
    return "\u0001" + id + "\u0002";
  };
  vm.runInContext(`Math.seed(${JSON.stringify(seed)});`, ctx);
  return ctx;
}

function ordered(ctx, canv) {
  if (typeof canv !== "string") return [];
  const ids = [...canv.matchAll(/\u0001(\d+)\u0002/g)].map((m) => +m[1]);
  return ids.map((i) => ctx.__polys[i]);
}

function summarize(polys, keep) {
  let np = 0, sx = 0, sy = 0, wsum = 0, k = 0;
  const styles = {};
  polys.forEach((poly, i) => {
    const key = poly.f + "|" + poly.s + "|" + poly.w;
    styles[key] = (styles[key] || 0) + 1;
    for (const v of poly.p) {
      const x = +v[0], y = +v[1];
      np += 1; sx += x; sy += y;
      k += 1;
      wsum += ((k % 1000) + 1) * (x + 2 * y) + (i % 97) * x;
    }
  });
  const out = { n: polys.length, np, sx, sy, wsum, styles };
  if (keep === "all") out.polys = polys;
  else out.head = polys.slice(0, keep), out.tail = polys.slice(Math.max(0, polys.length - 2));
  return out;
}

// PRNG: outputs as exact strings (Number#toString is round-trip exact; JSONSerialization is not)
// plus the integer states (< 2^53, exact in any JSON parser).
function dumpPrng(out, c) {
  const r = vm.runInContext("(function(){var a=[],s=[];for(var i=0;i<64;i++){a.push(String(Prng.next()));s.push(Prng.s)}return [a,s]})()", c);
  out.prng = r[0];
  out.prngStates = r[1];
}

function sinePts(n, x0, y0, dx, amp) {
  const pts = [];
  for (let i = 0; i < n; i++) pts.push([x0 + i * dx, y0 + Math.sin(i * 0.4) * amp]);
  return pts;
}

function shanFixtures(dir, seed) {
  const scripts = shanScripts(dir);
  const out = { source: "shan-shui-inf@" + SHAN_SHA, seed };

  // (a) PRNG
  {
    const c = shanContext(scripts, seed);
    out.intSeed = vm.runInContext("Prng.s", c);
    dumpPrng(out, c);
  }
  // (b) noise (table filled from the PRNG on first call)
  {
    const c = shanContext(scripts, seed);
    out.noise = vm.runInContext(`(function(){
      var pts=[[0,0,0],[0.5,0,0],[1.25,3.5,0],[-7.3,2.2,0.5],[123.456,0.5,3],[10.01,20.02,30.03],
               [3000.5,12.5,0],[0.013,0.027,7],[55.5,-66.25,1.5],[1e5+0.3,2.7,0]];
      for (var i=0;i<22;i++) pts.push([i*0.37, i*0.11, (i%3)*0.9]);
      return pts.map(function(p){return [p[0],p[1],p[2],Noise.noise(p[0],p[1],p[2])]});
    })()`, c);
    out.prngAfterNoise = vm.runInContext("Prng.s", c);
  }

  // (c) geometry cases — each in a fresh context seeded with `seed`
  const cases = [
    ["stroke", "all", (c) => c.stroke(sinePts(30, 50, 100, 7, 12), { wid: 3 })],
    ["stroke_fun", "all", (c) => c.stroke(sinePts(12, 10, 10, 5, 3), { wid: 1.5, noi: 0, out: 0, col: "rgba(100,100,100,0.4)", fun: (x) => Math.cos(x * Math.PI / 2) })],
    ["blob", "all", (c) => c.blob(100, 120, { len: 40, wid: 10, ang: 0.3 })],
    ["texture", 3, (c) => {
      const pl = [];
      for (let j = 0; j < 10; j++) { pl.push([]); for (let i = 0; i < 50; i++) { const x = (i / 50 - 0.5) * Math.PI; pl[j].push([x / Math.PI * 300 * (1 - j / 10), -Math.cos(x) * 200 * (1 - j / 10)]); } }
      return c.texture(pl, { xof: 300, yof: 400, tex: 60, sha: 2 });
    }],
    ["tree01", 4, (c) => c.Tree.tree01(200, 400, {})],
    ["tree02", 4, (c) => c.Tree.tree02(200, 400, {})],
    ["tree03", 4, (c) => c.Tree.tree03(200, 400, { hei: 80 })],
    ["tree04", 4, (c) => c.Tree.tree04(200, 400, {})],
    ["tree05", 4, (c) => c.Tree.tree05(200, 400, { hei: 150 })],
    ["tree06", 4, (c) => c.Tree.tree06(200, 400, { hei: 90 })],
    ["tree07", 4, (c) => c.Tree.tree07(200, 400, {})],
    ["tree08", 4, (c) => c.Tree.tree08(200, 400, {})],
    ["rock", 3, (c) => c.Mount.rock(200, 400, 5, { wid: 40, hei: 30, sha: 2 })],
    ["mountain", 3, (c) => c.Mount.mountain(300, 500, 7)],
    ["flatMount", 3, (c) => c.Mount.flatMount(300, 600, 3, { wid: 700, hei: 100, cho: 0.6 })],
    ["distMount", 3, (c) => c.Mount.distMount(0, 300, 11, { hei: 150, len: 1000 })],
    ["arch01", 3, (c) => c.Arch.arch01(300, 400, 0.5, { wid: 180, hei: 90, per: 0.5 })],
    ["arch02", 3, (c) => c.Arch.arch02(300, 400, 0, { sto: 2, rot: 0.3, sty: 3, wid: 60 })],
    ["arch03", 3, (c) => c.Arch.arch03(300, 400, 0, { sto: 5 })],
    ["arch04", 3, (c) => c.Arch.arch04(300, 400, 0, { sto: 2 })],
    ["boat01", 3, (c) => c.Arch.boat01(300, 400, 0.5, { sca: 0.6, fli: true })],
    ["man", "all", (c) => c.Man.man(100, 200, { sca: 0.5 })],
    ["water", 3, (c) => c.water(300, 500, 2)],
    ["tower", 2, (c) => c.Arch.transmissionTower01(300, 500, 0)],
    // The original first screen: chunkloader + chunkrender for the default 3000px window.
    ["scene", 3, (c) => { c.chunkloader(0, 3000); c.chunkrender(0, 3000); return c.MEM.canv; }],
  ];
  out.cases = {};
  for (const [name, keep, fn] of cases) {
    const c = shanContext(scripts, seed);
    const canv = fn(c);
    const polys = ordered(c, canv);
    out.cases[name] = Object.assign(summarize(polys, keep), { prngAfter: vm.runInContext("Prng.s", c) });
  }
  // pure helpers (no randomness)
  {
    const c = shanContext(scripts, seed);
    out.pure = {
      div: c.div([[0, 0], [10, 5], [13, -4]], 4),
      bezmh: c.bezmh([[0, 0], [10, 20], [30, 5], [40, 40]], 2),
      triangulate: vm.runInContext(`PolyTools.triangulate([[0,0],[100,0],[120,60],[60,110],[-10,70]],{area:300,convex:true,optimize:false})`, c),
      triangulateOpt: vm.runInContext(`PolyTools.triangulate([[0,0],[100,0],[50,30],[100,80],[0,80]],{area:500,convex:false,optimize:true})`, c),
    };
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// nonflowers

function flowContext(src, seed) {
  const ctx = makeSandbox(seed);
  ctxCounter = 0;
  vm.runInContext(src, ctx);
  ctx.vizParams = function () {};
  // Paper checksum: wrap the paper() canvas to see every texel colour.
  ctx.__polys = [];
  const origPolygon = ctx.polygon;
  ctx.polygon = function (args) {
    args = args || {};
    const xof = args.xof !== undefined ? args.xof : 0;
    const yof = args.yof !== undefined ? args.yof : 0;
    const pts = args.pts !== undefined ? args.pts : [];
    const col = args.col !== undefined ? args.col : "black";
    const fil = args.fil !== undefined ? args.fil : true;
    const str = args.str !== undefined ? args.str : !fil;
    const layer = args.ctx !== undefined ? args.ctx.__id : -1;
    ctx.__polys.push({ p: pts.map((v) => [v[0] + xof, v[1] + yof]), c: col, f: !!fil, s: !!str, l: layer });
  };
  vm.runInContext(`Math.seed(${JSON.stringify(seed)});`, ctx);
  return ctx;
}

function flowSummary(polys, keep) {
  let np = 0, sx = 0, sy = 0, wsum = 0, k = 0;
  const cols = {};
  const layers = {};
  polys.forEach((poly, i) => {
    cols[poly.c] = (cols[poly.c] || 0) + 1;
    layers[poly.l] = (layers[poly.l] || 0) + 1;
    for (const v of poly.p) {
      const x = +v[0], y = +v[1];
      np += 1; sx += x; sy += y; k += 1;
      wsum += ((k % 1000) + 1) * (x + 2 * y) + (i % 97) * x;
    }
  });
  const out = { n: polys.length, np, sx, sy, wsum, colorCount: Object.keys(cols).length, layers };
  // colour checksum: sum of parsed rgba components weighted by index
  let csum = 0;
  polys.forEach((poly, i) => {
    const m = /rgba\((\d+),(\d+),(\d+),([\d.]+)\)/.exec(poly.c);
    if (m) csum += ((i % 101) + 1) * (+m[1] + 2 * +m[2] + 3 * +m[3] + 1000 * +m[4]);
  });
  out.csum = csum;
  if (keep === "all") out.polys = polys;
  else out.head = polys.slice(0, keep), out.tail = polys.slice(Math.max(0, polys.length - 2));
  return out;
}

function paperChecksum(ctx, col, tex, spr) {
  // Re-implements nothing: calls the original paper() and intercepts fillStyle strings.
  let sum = 0, count = 0;
  const first = [];
  const origCreate = ctx.document.createElement;
  ctx.document.createElement = (tag) => {
    const cv = origCreate(tag);
    if (tag === "canvas") {
      const c2d = cv.getContext("2d");
      Object.defineProperty(c2d, "fillStyle", { configurable: true,
        set(v) {
          const m = /rgba\((-?\d+),(-?\d+),(-?\d+),([\d.]+)\)/.exec(v);
          const r = +m[1], g = +m[2], b = +m[3];
          count += 1;
          sum += ((count % 1000) + 1) * (r + 3 * g + 7 * b);
          if (first.length < 8) first.push([r, g, b]);
        },
        get() { return ""; },
      });
    }
    return cv;
  };
  vm.runInContext(`paper({col:${JSON.stringify(col)},tex:${tex},spr:${spr}})`, ctx);
  ctx.document.createElement = origCreate;
  return { sum, count, first, prngAfter: vm.runInContext("Prng.s", ctx) };
}

function flowFixtures(dir, seed) {
  const src = fs.readFileSync(path.join(dir, "main.js"), "utf8");
  const out = { source: "nonflowers@" + FLOW_SHA, seed };
  {
    const c = flowContext(src, seed);
    out.intSeed = vm.runInContext("Prng.s", c);
    dumpPrng(out, c);
  }
  // Full page sequence: makeBG() paper, then generate(): paper, coin, woody/herbal(genParams()).
  {
    const c = flowContext(src, seed);
    out.paperBG = paperChecksum(c, [1, 0.99, 0.9], 10, 0);
    out.paperCanvas = paperChecksum(c, [0.98, 0.91, 0.74], 20, 1);
    const coin = vm.runInContext("Math.random()", c);
    out.woody = coin <= 0.5;
    const PAR = vm.runInContext("genParams()", c);
    const samples = (f, two) => { const a = []; for (let i = 0; i <= 10; i++) a.push(two ? f(i / 10, 0.5) : f(i / 10)); return a; };
    const par = {};
    for (const k of Object.keys(PAR)) {
      const v = PAR[k];
      if (typeof v === "function") par[k] = samples(v, k === "flowerOpenCurve");
      else par[k] = v;
    }
    out.params = par;
    out.prngAfterParams = vm.runInContext("Prng.s", c);
    c.__polys.length = 0;
    const plant = out.woody ? c.woody({ ctx: c.CTX, xof: 300, yof: 550, PAR }) : c.herbal({ ctx: c.CTX, xof: 300, yof: 600, PAR });
    out.plant = Object.assign(flowSummary(c.__polys, 6), { prngAfter: vm.runInContext("Prng.s", c) });
  }
  // Primitives in fresh contexts
  // Arguments must be built INSIDE the context: main.js defines Array.prototype.x/.y/.z there,
  // and arrays from Node's own realm would not have them.
  const prim = [
    ["leaf", "all", `leaf({ctx:CTX, xof:300, yof:300, len:60, seg:12, vei:[1,3], rot:[1.1,0.4,0]})`],
    ["leafFlo", "all", `leaf({ctx:CTX, flo:true, xof:200, yof:200, len:30, seg:10, vei:[0], rot:[0.3,-0.7,1.2],
        col:{min:[340,0.4,0.9,1],max:[20,0.1,1,0.8]}, cof:function(x){return sigmoid(x,8)},
        wid:function(x){return Math.sin(x*Math.PI)*12}, ben:function(x){return [x<0.3?6:1,0,0]}})`],
    ["stem", "all", `stem({ctx:CTX, xof:300, yof:500, len:120, seg:10, rot:[Math.PI/2,0,0.4]})`],
    ["branch", 6, `JSON.parse(JSON.stringify(branch({ctx:CTX, xof:300, yof:500, len:200, seg:20, wid:1, twi:4, dep:2, frk:4})))`],
  ];
  out.cases = {};
  for (const [name, keep, fn] of prim) {
    const c = flowContext(src, seed);
    c.__polys.length = 0;
    const ret = vm.runInContext(fn, c);
    const s = flowSummary(c.__polys, keep);
    if (name === "branch") s.ret = ret.map((b) => [b[0], b[1].length, b[1][b[1].length - 1]]);
    out.cases[name] = Object.assign(s, { prngAfter: vm.runInContext("Prng.s", c) });
  }
  {
    const c = flowContext(src, seed);
    out.pure = {
      toeuler: [[1, 0, 0], [0, 1, 0], [0.3, -0.5, 0.8], [-0.2, 0.9, 0.1]].map((v) => vm.runInContext(`v3.toeuler(${JSON.stringify(v)})`, c)),
      rotvec: vm.runInContext(`v3.roteuler([1,2,3],[0.3,-0.2,1.1])`, c),
      hsv: [[0, 0.5, 0.5, 1], [123.4, 0.3, 0.9, 0.7], [359.9, 1, 1, 0.25], [200, 0.05, 0.4, 1]].map((a) => vm.runInContext(`hsv(${a.join(",")})`, c)),
      lerpHue: [[10, 350, 0.3], [100, 200, 0.5], [340, 20, 0.75]].map((a) => vm.runInContext(`lerpHue(${a.join(",")})`, c)),
    };
  }
  return out;
}

// ---------------------------------------------------------------------------------------

function main() {
  const shanDir = ensureClone("shan-shui-inf", SHAN_SHA);
  const flowDir = ensureClone("nonflowers", FLOW_SHA);
  fs.mkdirSync(outDir, { recursive: true });
  for (const seed of SEEDS) {
    const t0 = Date.now();
    const s = shanFixtures(shanDir, seed);
    fs.writeFileSync(path.join(outDir, `shanshui-${seed}.json`), JSON.stringify(s));
    const f = flowFixtures(flowDir, seed);
    fs.writeFileSync(path.join(outDir, `nonflowers-${seed}.json`), JSON.stringify(f));
    console.log(`seed ${seed}: scene polys=${s.cases.scene.n} plant polys=${f.plant.n} woody=${f.woody} (${Date.now() - t0} ms)`);
  }
}

main();
