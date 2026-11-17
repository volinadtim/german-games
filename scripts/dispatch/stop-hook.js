// PostToolUse-хук воркеров диспетчера. Обычно молчит (ноль токенов в контекст агента).
// Если есть <dispatch>/stop.flag со словом "stop" (мягкая остановка) — один раз на сессию
// говорит агенту доделать или оставить handoff.
const fs = require("fs"), path = require("path");
const dir = process.argv[2];
let flag = "";
try { flag = fs.readFileSync(path.join(dir, "stop.flag"), "utf8").trim(); } catch { process.exit(0); }
if (flag !== "stop") process.exit(0);
let input = "";
process.stdin.on("data", d => input += d);
process.stdin.on("end", () => {
  let sid = "x", cwd = process.cwd();
  try { const j = JSON.parse(input); sid = j.session_id || sid; cwd = j.cwd || cwd; } catch {}
  const mark = path.join(dir, "soft-notified", sid);
  if (fs.existsSync(mark)) process.exit(0);
  fs.mkdirSync(path.dirname(mark), { recursive: true });
  fs.writeFileSync(mark, "");
  const m = /disp-([a-z]+)/.exec(cwd.replace(/\\/g, "/"));
  const handoff = path.join(dir, "handoff", (m ? m[1] : "other") + ".md");
  const reason =
    "МЯГКАЯ ОСТАНОВКА разработки. Если до конца задачи осталось немного — доделай, проверь и закоммить+запушь как обычно. " +
    "Иначе дойди до ближайшей рабочей точки (код компилируется), закоммить и запушь её, затем запиши handoff в " + handoff +
    " (что сделано, что осталось, следующий шаг, важные файлы) и заверши работу коротким ответом.";
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
});
