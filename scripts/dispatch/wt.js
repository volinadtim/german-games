#!/usr/bin/env node
// Менеджер worktree диспетчера. Только этот скрипт создаёт и удаляет worktree задач —
// и для dispatch.ps1 (disp-<зона>), и для субагентов Claude Code с isolation:"worktree" (хук WorktreeCreate).
//
//   node wt.js create <имя> [--blender] [--wait СЕК]  -> печатает путь; код 3 — лимит worktree занят
//                     [--uncounted] — не входит в лимит задач (копия «smoke» для проверки после пуша)
//   node wt.js release <имя|путь> [--delay СЕК]      -> задача закончена: удалить, если чистый и запушен
//   node wt.js reap [--hours 6]                      -> удалить законченные и брошенные чистые worktree
//   node wt.js blender                               -> подключить Blender/ в текущем worktree
//   node wt.js status
//   хуки Claude Code: hook-create | hook-remove | hook-subagent-stop | hook-guard (JSON на stdin)
//
// Правила:
//  - worktree лежат в <репо>/.claude/worktrees/<имя>, от свежего origin/main, sparse без /Blender/
//    (Blender ~1,6 ГБ; нужен — --blender, «[blender]»/«Blender» в задаче, или `node wt.js blender`);
//  - одновременно не больше max (по умолчанию 4) worktree задач; остальные ждут;
//  - удаляется только чистый worktree, все коммиты которого уже в origin (или их патчи в origin/main);
//    иначе остаётся, причина пишется в .claude/dispatch/dispatch.log;
//  - locked — не трогаем никогда;
//  - место: перед созданием проверяется свободное место на диске (minFreeGB) и общий размер worktree задач
//    (maxGB, жёсткий предел). Не хватает — сначала уборка (законченные, потом брошенные дольше 1 ч), потом ждём (код 3).
//    Неотслеживаемые *.uid (Godot создаёт сам) и удалённые ~временные файлы удалению не мешают.
// Настройки: <репо>/.claude/dispatch/wt-config.json {"max":4,"staleHours":6,"waitSec":1800,"minFreeGB":8,"maxGB":6,"patterns":[...]}
"use strict";
const fs = require("fs"), path = require("path"), cp = require("child_process");

const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
function git(args, cwd) {
  const r = cp.spawnSync("git", ["-c", "core.longpaths=true", ...args], { cwd, encoding: "utf8", windowsHide: true, maxBuffer: 64 << 20 });
  return { ok: r.status === 0, out: (r.stdout || "").trim(), err: (r.stderr || "").trim() };
}
const norm = p => path.resolve(p).replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();

// Корень основной копии — родитель общего .git (работает из любого worktree).
function mainRepo() {
  for (const d of [process.cwd(), __dirname]) {
    const r = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], d);
    if (r.ok && r.out) return path.dirname(path.resolve(r.out));
  }
  throw new Error("не git-репозиторий");
}
const REPO = mainRepo();
const WTS = path.join(REPO, ".claude", "worktrees");
const DISP = path.join(REPO, ".claude", "dispatch");
const ST = path.join(DISP, "wt");
const REG = path.join(ST, "reg");     // <имя>.json — worktree, созданные этим скриптом
const LOG = path.join(DISP, "dispatch.log");
fs.mkdirSync(REG, { recursive: true });

const CFG = Object.assign(
  { max: 4, staleHours: 6, waitSec: 1800, releaseDelaySec: 20, minFreeGB: 8, maxGB: 6, fullGB: 2.2, sparseGB: 0.2,
    patterns: ["^agent-", "^disp-", "^dispatcher-launch-"],     // какие чужие worktree считать брошенными задачами
    protect: ["dispatcher"] },                                    // не удалять никогда
  (() => { try { return JSON.parse(fs.readFileSync(path.join(DISP, "wt-config.json"), "utf8")); } catch { return {}; } })());
if (!CFG.protect.includes("smoke")) CFG.protect.push("smoke");   // постоянная копия проверки smoke.sh после пушей
if (process.env.WT_MAX) CFG.max = +process.env.WT_MAX;
if (process.env.WT_MIN_FREE_GB) CFG.minFreeGB = +process.env.WT_MIN_FREE_GB;
if (process.env.WT_MAX_GB) CFG.maxGB = +process.env.WT_MAX_GB;

let HOOK = false;
function log(s) {
  const d = new Date(), p = n => String(n).padStart(2, "0");
  const l = `${p(d.getDate())}.${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}  [wt] ${s}\n`;
  try { fs.appendFileSync(LOG, l); } catch {}
  if (!HOOK) process.stderr.write(l);
}

function lock(fn) {
  const L = path.join(ST, "lock");
  for (let i = 0; ; i++) {
    try { fs.mkdirSync(L); break; } catch {
      try { if (Date.now() - fs.statSync(L).mtimeMs > 300e3) { fs.rmdirSync(L); continue; } } catch {}
      if (i > 1500) throw new Error("wt lock занят");
      sleep(200);
    }
  }
  try { return fn(); } finally { try { fs.rmdirSync(L); } catch {} }
}

const regFile = n => path.join(REG, n + ".json");
function regGet(n) { try { return JSON.parse(fs.readFileSync(regFile(n), "utf8")); } catch { return null; } }
function regPut(n, o) { fs.writeFileSync(regFile(n), JSON.stringify(o)); }
function regAll() { return fs.readdirSync(REG).filter(f => f.endsWith(".json")).map(f => f.slice(0, -5)); }

// git worktree list --porcelain -> [{path, head, branch, locked}] только из .claude/worktrees
function worktrees() {
  const r = git(["worktree", "list", "--porcelain"], REPO);
  const res = []; let cur = null;
  for (const l of r.out.split(/\r?\n/)) {
    if (l.startsWith("worktree ")) { cur = { path: path.resolve(l.slice(9)) }; res.push(cur); }
    else if (!cur) continue;
    else if (l.startsWith("HEAD ")) cur.head = l.slice(5);
    else if (l.startsWith("branch ")) cur.branch = l.slice(7).replace(/^refs\/heads\//, "");
    else if (l.startsWith("locked")) cur.locked = l.slice(6).trim() || "locked";
  }
  return res.filter(w => norm(path.dirname(w.path)) === norm(WTS));
}
const nameOf = p => path.basename(p);

// Последнее касание: каталог, index/HEAD/логи в gitdir, транскрипты Claude для этого пути.
function lastTouch(wtPath) {
  let t = 0;
  const st = f => { try { t = Math.max(t, fs.statSync(f).mtimeMs); } catch {} };
  st(wtPath);
  const gd = git(["rev-parse", "--path-format=absolute", "--git-dir"], wtPath).out;
  if (gd) for (const f of ["index", "HEAD", "logs/HEAD", "ORIG_HEAD"]) st(path.join(gd, f));
  const proj = path.join(require("os").homedir(), ".claude", "projects", path.resolve(wtPath).replace(/[^A-Za-z0-9]/g, "-"));
  try { for (const f of fs.readdirSync(proj)) st(path.join(proj, f)); } catch {}
  return t;
}

// Пути, где сейчас работают воркеры dispatch.ps1 (jobs.json).
function runningJobPaths() {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(DISP, "jobs.json"), "utf8").replace(/^﻿/, ""));
    return new Set((j.jobs || []).filter(q => q.status === "работает" && q.wt).map(q => norm(q.wt)));
  } catch { return new Set(); }
}

let fetched = false;
function fetchMain() {
  if (fetched) return; fetched = true;
  const r = git(["fetch", "-q", "origin"], REPO);
  if (!r.ok) log("git fetch не прошёл: " + r.err.split("\n")[0]);
}

// Почему worktree нельзя удалять (или "" — можно).
function keepReason(w) {
  if (w.locked) return "locked: " + w.locked;
  if (!fs.existsSync(w.path)) return "";
  const gd = git(["rev-parse", "--path-format=absolute", "--git-dir"], w.path).out;
  for (const f of ["rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD"])
    if (gd && fs.existsSync(path.join(gd, f))) return "незавершённый " + f;
  const s = git(["status", "--porcelain", "--untracked-files=all"], w.path);
  if (!s.ok) return "git status не работает: " + s.err.split("\n")[0];
  // Мусор, который удалению не мешает: неотслеживаемые *.uid (Godot) и удалённые временные ~файлы (Ziva держит ~lib*.dll).
  const junk = x => /^\?\? .*\.uid"?$/.test(x) || /^D .*\/~[^\/]*"?$/.test(x);
  const l = s.out.split("\n").map(x => x.trim()).filter(x => x && !junk(x));
  if (l.length) { return `незакоммиченные изменения (${l.length}): ` + l.slice(0, 3).map(x => x.trim()).join(", "); }
  fetchMain();
  // Коммиты, которых нет ни в одной ветке origin; из них — те, чьего патча нет и в origin/main (после rebase хеши другие).
  const un = git(["rev-list", "HEAD", "--not", "--remotes=origin"], w.path).out.split("\n").filter(Boolean);
  if (un.length) {
    const ch = new Set(git(["cherry", "origin/main", "HEAD"], w.path).out.split("\n").filter(l => l.startsWith("+")).map(l => l.slice(2)));
    const lost = un.filter(c => ch.has(c));
    if (lost.length) return `незапушенные коммиты (${lost.length}): ` + lost.slice(0, 3).map(c => c.slice(0, 7)).join(" ");
  }
  return "";
}

function removeWt(w, why) {
  const reason = keepReason(w);
  if (reason) { log(`оставлен ${nameOf(w.path)}: ${reason}`); return false; }
  const r = git(["worktree", "remove", "--force", w.path], REPO);
  if (!r.ok && fs.existsSync(w.path)) {
    // «Filename too long» и т.п.: worktree чистый и запушен — удаляем каталог сами, потом prune.
    try { fs.rmSync("\\\\?\\" + w.path, { recursive: true, force: true, maxRetries: 3 }); } catch {}
    git(["worktree", "prune"], REPO);
  }
  if (fs.existsSync(w.path)) { log(`не удалось удалить ${nameOf(w.path)}: ${r.err.split("\n")[0]}`); return false; }
  git(["worktree", "prune"], REPO);
  if (w.branch && !["main", "dispatcher"].includes(w.branch)) {
    // -d сверяет с локальным main (он сильно отстаёт) — если не вышло, -D: коммиты уже проверены keepReason.
    if (!git(["branch", "-d", w.branch], REPO).ok) git(["branch", "-D", w.branch], REPO);
  }
  try { fs.unlinkSync(regFile(nameOf(w.path))); } catch {}
  log(`удалён ${nameOf(w.path)}${w.branch ? " (" + w.branch + ")" : ""} — ${why}`);
  return true;
}

// ---- место на диске ----
const GB = 2 ** 30;
function freeGB() { try { const s = fs.statfsSync(WTS); return s.bavail * s.bsize / GB; } catch { return Infinity; } }
function dirBytes(d) {
  let n = 0, es;
  try { es = fs.readdirSync(d, { withFileTypes: true }); } catch { return 0; }
  for (const e of es) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) n += dirBytes(p);
    else { try { n += fs.lstatSync(p).size; } catch {} }
  }
  return n;
}
const isTask = name => !CFG.protect.includes(name) && CFG.patterns.some(s => new RegExp(s).test(name));
// Общий размер worktree задач, созданных этим скриптом (agent-*, disp-*), ГБ. Чужие старые копии сюда не входят
// (иначе навсегда блокируют предел) — их место учитывает проверка свободного места на диске.
function tasksGB(all) {
  return worktrees().filter(w => isTask(nameOf(w.path)) && (all || regGet(nameOf(w.path)))).reduce((a, w) => a + dirBytes(w.path), 0) / GB;
}
// "" — место есть; иначе причина, почему создавать нельзя.
function spaceProblem(needGB) {
  const free = freeGB();
  if (free - needGB < CFG.minFreeGB) return `мало места на диске: свободно ${free.toFixed(1)} ГБ, нужно ${needGB.toFixed(1)} + запас ${CFG.minFreeGB} ГБ`;
  const used = tasksGB();
  if (used + needGB > CFG.maxGB) return `worktree задач занимают ${used.toFixed(1)} ГБ, предел ${CFG.maxGB} ГБ`;
  return "";
}
// Освободить место: законченные, потом брошенные дольше 1 ч (только чистые и запушенные). Вызывать под lock.
function makeRoom(needGB) {
  let why = spaceProblem(needGB);
  if (!why) return "";
  log(`${why} — уборка`);
  reapDone(); why = spaceProblem(needGB);
  if (why) { reapInner(1); why = spaceProblem(needGB); }
  return why;
}

// Сколько worktree задач занято: созданные нами, не законченные, существующие, тронутые за staleHours.
function activeCount() {
  const live = new Set(worktrees().map(w => norm(w.path)));
  let n = 0;
  for (const name of regAll()) {
    const r = regGet(name); if (!r || r.done || !r.counted) continue;
    const p = path.join(WTS, name);
    if (!live.has(norm(p))) { try { fs.unlinkSync(regFile(name)); } catch {} continue; }
    if (Date.now() - lastTouch(p) > CFG.staleHours * 3600e3) continue;
    n++;
  }
  return n;
}

let waitReason = "";
const wantBlender = text => /blender|блендер|\.blend\b/i.test(text || "");

function create(name, o) {
  if (!/^[A-Za-z0-9._-]+$/.test(name)) throw new Error("плохое имя worktree: " + name);
  const p = path.join(WTS, name);
  const counted = o.counted !== false;
  const deadline = Date.now() + (o.wait || 0) * 1000;
  for (;;) {
    const res = lock(() => {
      const ex = worktrees().find(w => norm(w.path) === norm(p));
      if (ex) {   // остался с прошлой задачи (например, с незакоммиченной работой) — используем его
        const r = regGet(name) || { created: Date.now() };
        Object.assign(r, { done: false, counted, reused: Date.now() }); regPut(name, r);
        log(`снова в работе ${name} (остался с прошлой задачи)`);
        // Старая полная копия, а Blender не нужен — убрать Blender/ (sparse), если там ничего не менялось.
        if (!o.blender && git(["config", "--worktree", "core.sparseCheckout"], p).out !== "true") {
          const s = git(["sparse-checkout", "set", "--no-cone", "/*", "!/Blender/"], p);
          log(`${name}: ${s.ok ? "Blender/ убран (sparse)" : "sparse не встал: " + s.err.split("\n")[0]}`);
        }
        return p;
      }
      if (fs.existsSync(p)) {
        if (fs.readdirSync(p).length) throw new Error(`${p} существует и это не worktree`);
        fs.rmdirSync(p);
      }
      if (counted) {
        reapDone();
        if (activeCount() >= CFG.max) { waitReason = `заняты все ${CFG.max} worktree`; return null; }
        const why = makeRoom(o.blender ? CFG.fullGB : CFG.sparseGB);
        if (why) { waitReason = why; return null; }
      }
      fetchMain();
      let branch = o.branch || null;
      if (branch && git(["rev-parse", "--verify", "-q", "refs/heads/" + branch], REPO).ok) branch = null;  // имя занято — detach
      const args = ["worktree", "add", "--no-checkout"];
      if (branch) args.push("--no-track", "-b", branch); else args.push("--detach");
      args.push(p, "origin/main");
      let r = git(args, REPO);
      if (!r.ok) throw new Error("git worktree add: " + r.err);
      if (!o.blender) {
        r = git(["sparse-checkout", "set", "--no-cone", "/*", "!/Blender/"], p);
        if (!r.ok) log(`${name}: sparse-checkout не встал (${r.err.split("\n")[0]}) — будет полная копия`);
      }
      r = git(["checkout", "-q", "-f", branch || "HEAD"], p);
      if (!r.ok) throw new Error("checkout: " + r.err);
      regPut(name, { created: Date.now(), branch, blender: !!o.blender, counted, by: o.by || "cli", done: false });
      log(`создан ${name} ${o.blender ? "с Blender" : "без Blender"}${branch ? ", ветка " + branch : ""}; занято ${activeCount()}/${CFG.max}`);
      return p;
    });
    if (res) return res;
    if (Date.now() >= deadline) return null;
    sleep(15000);
  }
}

// Задача закончена: пометить и удалить, если можно.
function release(target, delaySec) {
  if (delaySec) sleep(delaySec * 1000);
  const name = nameOf(path.resolve(WTS, target));
  return lock(() => {
    const r = regGet(name); if (r) { r.done = Date.now(); regPut(name, r); }
    const w = worktrees().find(x => norm(x.path) === norm(path.join(WTS, name)));
    if (!w) { try { fs.unlinkSync(regFile(name)); } catch {} return true; }
    if (CFG.protect.includes(name)) return false;
    return removeWt(w, "задача закончена");
  });
}

function reapDone() {
  for (const w of worktrees()) {
    const r = regGet(nameOf(w.path));
    if (r && r.done && !w.locked && !CFG.protect.includes(nameOf(w.path)) && keepReason(w) === "") removeWt(w, "задача закончена");
  }
}

// Очистка: законченные + брошенные (не тронуты > hours) чистые worktree задач.
function reap(hours) { return lock(() => reapInner(hours)); }
function reapInner(hours) {
  {
    git(["worktree", "prune"], REPO);
    const running = runningJobPaths();
    const me = norm(git(["rev-parse", "--show-toplevel"], process.cwd()).out || "-");
    const pats = CFG.patterns.map(s => new RegExp(s));
    let removed = 0, kept = 0;
    for (const w of worktrees()) {
      const name = nameOf(w.path), r = regGet(name);
      if (CFG.protect.includes(name) || norm(w.path) === me || running.has(norm(w.path))) continue;
      const age = (Date.now() - lastTouch(w.path)) / 3600e3;
      const done = r && r.done;
      const stale = age > hours && (r || pats.some(re => re.test(name)));
      if (!done && !stale) continue;
      if (w.locked) { log(`пропущен ${name}: locked`); kept++; continue; }
      if (removeWt(w, done ? "задача закончена" : `брошен ${age.toFixed(1)} ч`)) removed++; else kept++;
    }
    // Пустые каталоги без worktree (остатки неудачных удалений).
    const live = new Set(worktrees().map(w => norm(w.path)));
    for (const d of fs.readdirSync(WTS)) {
      const p = path.join(WTS, d);
      try { if (!live.has(norm(p)) && fs.statSync(p).isDirectory() && !fs.readdirSync(p).length) fs.rmdirSync(p); } catch {}
    }
    log(`очистка: удалено ${removed}, оставлено ${kept}`);
    return { removed, kept };
  }
}

function status() {
  const out = [];
  for (const w of worktrees()) {
    const r = regGet(nameOf(w.path));
    const age = ((Date.now() - lastTouch(w.path)) / 3600e3).toFixed(1);
    const sparse = git(["config", "--worktree", "core.sparseCheckout"], w.path).out === "true" ? "sparse" : "full";
    out.push(`${nameOf(w.path)}\t${w.branch || "detached"}\t${sparse}\t${age}ч\t${r ? (r.done ? "закончен" : "в работе") : "-"}${w.locked ? "\tlocked" : ""}`);
  }
  out.push(`занято ${activeCount()}/${CFG.max}; worktree задач ${tasksGB().toFixed(2)} из ${CFG.maxGB} ГБ (все копии ${tasksGB(true).toFixed(1)} ГБ); свободно на диске ${freeGB().toFixed(1)} ГБ (запас ${CFG.minFreeGB})`);
  return out.join("\n");
}

function readStdin() { try { return JSON.parse(fs.readFileSync(0, "utf8") || "{}"); } catch { return {}; } }
// Текст последнего вызова Agent в транскрипте родителя — чтобы понять, нужен ли Blender.
function lastAgentCall(tp) {
  try {
    const fd = fs.openSync(tp, "r"), size = fs.fstatSync(fd).size, n = Math.min(size, 2 << 20);
    const b = Buffer.alloc(n); fs.readSync(fd, b, 0, n, size - n); fs.closeSync(fd);
    const s = b.toString("utf8"), i = s.lastIndexOf('"name":"Agent","input":');
    return i < 0 ? "" : s.slice(i, i + 20000).split('"type":"tool_use"')[0];
  } catch { return ""; }
}

const argv = process.argv.slice(2), cmd = argv[0];
const opt = k => { const i = argv.indexOf(k); return i < 0 ? undefined : argv[i + 1]; };
try {
  switch (cmd) {
    case "create": {
      const p = create(argv[1], { blender: argv.includes("--blender"), wait: +(opt("--wait") || 0), branch: opt("--branch"), by: "dispatch", counted: !argv.includes("--uncounted") });
      if (!p) { console.log("ждёт: " + (waitReason || `заняты ${CFG.max} worktree`)); process.exit(3); }
      console.log(p); break;
    }
    case "release": release(argv[1], +(opt("--delay") || 0)); break;
    case "reap": { const r = reap(+(opt("--hours") || CFG.staleHours)); console.log(`удалено ${r.removed}, оставлено ${r.kept}`); break; }
    case "status": console.log(status()); break;
    case "size": console.log((dirBytes(path.resolve(WTS, argv[1] || ".")) / 2 ** 20).toFixed(1) + " МБ"); break;
    case "blender": {
      const top = git(["rev-parse", "--show-toplevel"], process.cwd()).out;
      const r = git(["sparse-checkout", "disable"], top);
      console.log(r.ok ? "Blender/ подключён" : r.err); break;
    }
    // ---- хуки Claude Code (.claude/settings.json) ----
    case "hook-create": {   // WorktreeCreate: {name, cwd, transcript_path} -> путь в stdout
      HOOK = true;
      const j = readStdin(), name = String(j.name || "agent-" + Date.now()).replace(/[^A-Za-z0-9._-]/g, "-");
      const task = /^agent-/.test(name);
      const p = create(name, {
        blender: wantBlender(lastAgentCall(j.transcript_path)), wait: task ? CFG.waitSec : 0,
        branch: task ? "worktree-" + name : "claude/" + name, counted: task, by: "hook",
      });
      if (!p) { process.stderr.write(`нет worktree дольше ${CFG.waitSec} с: ${waitReason}`); process.exit(2); }
      process.stdout.write(p + "\n"); break;
    }
    case "hook-remove": {   // WorktreeRemove: {worktree_path}
      HOOK = true; const j = readStdin();
      if (j.worktree_path) { log(`${nameOf(j.worktree_path)}: Claude Code просит удалить`); release(j.worktree_path, 0); }
      break;
    }
    case "hook-subagent-stop": {   // SubagentStop: {agent_id} -> отложенное удаление его worktree в фоне
      HOOK = true; const j = readStdin();
      const id = String(j.agent_id || ""); if (!id) break;
      const name = regAll().find(n => n === "agent-" + id || n.endsWith(id));
      if (!name) break;
      lock(() => { const r = regGet(name); if (r) { r.done = Date.now(); regPut(name, r); } });
      log(`${name}: субагент закончил, удаление через ${CFG.releaseDelaySec} с`);
      // Claude Code ещё смотрит в worktree после SubagentStop, поэтому удаляем с задержкой, отдельным процессом.
      // На Windows дочерние процессы хука живут в job-объекте Claude и умирают вместе с ним — запускаем через WMI.
      const args = [__filename, "release", name, "--delay", String(CFG.releaseDelaySec)];
      let ok = false;
      if (process.platform === "win32") {
        const line = [process.execPath, ...args].map(a => '"' + a + '"').join(" ").replace(/'/g, "''");
        const ps = `$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='${line}'; CurrentDirectory='${REPO.replace(/'/g, "''")}'}; exit $r.ReturnValue`;
        ok = cp.spawnSync("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps], { windowsHide: true, timeout: 20000 }).status === 0;
      }
      if (!ok) cp.spawn(process.execPath, args, { cwd: REPO, detached: true, stdio: "ignore", windowsHide: true }).unref();
      break;
    }
    case "hook-guard": {    // PreToolUse: агенты сами worktree не создают и не удаляют
      HOOK = true; const j = readStdin(), c = String((j.tool_input || {}).command || "");
      const bad = j.tool_name === "EnterWorktree" || /\bgit\b[^\n;&|]*\bworktree\s+(add|remove|move|prune)\b/.test(c);
      if (bad) process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny",
        permissionDecisionReason: "worktree создаёт и удаляет только диспетчер (node scripts/dispatch/wt.js). Работай в текущей папке." } }));
      break;
    }
    default:
      console.log(fs.readFileSync(__filename, "utf8").split("\n").slice(1, 11).map(l => l.replace(/^\/\/ ?/, "")).join("\n"));
  }
} catch (e) {
  log("ошибка " + cmd + ": " + e.message.split("\n")[0]);
  process.stderr.write(e.message + "\n"); process.exit(1);
}
