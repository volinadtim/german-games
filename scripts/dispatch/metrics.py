#!/usr/bin/env python3
"""Метрики диспетчера без LLM (токены не тратит).

    python scripts/dispatch/metrics.py [--day 20.11] [--prompts N | --prompts-file F] [--skew 20]

Источники: .claude/dispatch/history.jsonl (задачи v1), dispatch.log, alive.log (пульс слушания), git log origin/main,
история промптов — только `prompts.ps1 last N` (не new: ничего не помечает прочитанным), результат кэшируется
в .claude/dispatch/prompts-last.txt.
Часы этого ПК спешат примерно на --skew минут (время коммитов и логов), время промптов — МСК с сервера.

Что считает:
  1. доля переделок по моделям (жалобы Германа, smoke-падения, СЛОЖНО, лимит $);
  2. файлы, которые правили 2+ задачи одновременно (v1 — по окнам задач; за день по git — коммиты в одном файле < 30 мин);
  3. время от промпта до пуша (v1 — created->finished; за день — промпт -> первый следующий коммит);
  4. дыры в слушании > 5 мин (alive.log; без него — промпты, на которые не было реакции > 5 мин);
  5. $ и контекст на задачу, использование лимита ($ задачи / --max-budget-usd, события «лимит Claude»).
"""
import argparse, json, os, re, subprocess, sys
from collections import defaultdict
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))


def git(*a, cwd=None):
    r = subprocess.run(["git", *a], cwd=cwd or HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout


REPO = os.path.dirname(os.path.abspath(git("rev-parse", "--path-format=absolute", "--git-common-dir").strip()))
DISP = os.path.join(REPO, ".claude", "dispatch")
SKIP = {"ANSWER.md", "godot/THE LEAK/CODEMAP.md"}
YEAR = datetime.now().year


def pct(a, b):
    return f"{100 * a / b:.0f}%" if b else "—"


def med(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else None


def fmt_min(m):
    return "—" if m is None else (f"{m:.0f} мин" if m < 120 else f"{m / 60:.1f} ч")


def iso(s):
    try:
        return datetime.fromisoformat(str(s)[:19])
    except Exception:
        return None


def ddmm(s):  # "20.11 14:05" -> datetime
    try:
        return datetime.strptime(f"{s} {YEAR}", "%d.%m %H:%M %Y")
    except Exception:
        return None


def load_hist():
    p = os.path.join(DISP, "history.jsonl")
    out = []
    if os.path.exists(p):
        for l in open(p, encoding="utf-8-sig"):
            l = l.strip()
            if l:
                try:
                    out.append(json.loads(l))
                except Exception:
                    pass
    return out


def load_prompts(a):
    cache = os.path.join(DISP, "prompts-last.txt")
    txt = ""
    if a.prompts_file:
        txt = open(a.prompts_file, encoding="utf-8-sig").read()
    elif a.prompts:
        ps = r"C:\Users\volin\.config\atlas\prompts.ps1"
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps, "last", str(a.prompts)],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        txt = r.stdout
        if txt.strip():
            open(cache, "w", encoding="utf-8").write(txt)
    elif os.path.exists(cache):
        txt = open(cache, encoding="utf-8-sig").read()
    res = []
    for m in re.finditer(r"^=== (\d\d\.\d\d \d\d:\d\d) МСК", txt, re.M):
        t = ddmm(m.group(1))
        if t:
            res.append(t)
    return sorted(res)


def commits(day):
    """Коммиты origin/main за день (по часам ПК): (время, хеш, модель, файлы, тема)."""
    d = datetime.strptime(f"{day}.{YEAR}", "%d.%m.%Y")
    out = git("log", "origin/main", f"--since={d:%Y-%m-%d} 00:00", f"--until={(d + timedelta(days=1)):%Y-%m-%d} 00:00",
              "--format=\x01%H\x02%cI\x02%(trailers:key=Co-Authored-By,valueonly,separator=;)\x02%s", "--name-only", cwd=REPO)
    res = []
    for blk in out.split("\x01")[1:]:
        head, _, names = blk.partition("\n")
        h, t, tr, s = (head.split("\x02", 3) + ["", "", "", ""])[:4]
        files = [f.strip() for f in names.split("\n") if f.strip()]
        mm = re.search(r"Claude (\w+)", tr)
        res.append((iso(t), h[:9], (mm.group(1).lower() if mm else "человек"), files, s))
    return sorted([c for c in res if c[0]], key=lambda c: c[0])


def section_v1(hist):
    done = [h for h in hist if h.get("t") == "done"]
    redo = {h.get("id") for h in hist if h.get("t") == "redo"}
    smoke_bad = [h for h in hist if h.get("t") == "smoke" and not h.get("ok")]
    print("== 1. Диспетчер v1 (history.jsonl): переделки, $, контекст, лимит")
    if not done:
        print("  задач в history.jsonl нет")
        return
    for m in ("sonnet", "opus"):
        mine = [h for h in done if h.get("agent") == m]
        if not mine:
            continue
        n = len(mine)
        r = sum(1 for h in mine if h.get("id") in redo)
        sb = sum(1 for h in smoke_bad if h.get("agent") == m)
        hard = sum(1 for h in mine if h.get("status") == "СЛОЖНО")
        bud = sum(1 for h in mine if h.get("status") == "бюджет")
        err = sum(1 for h in mine if h.get("status") in ("ошибка", "упал"))
        cost = [float(h.get("cost") or 0) for h in mine]
        ctx = [int(h.get("ctx") or 0) for h in mine if h.get("ctx")]
        use = [float(h.get("cost") or 0) / float(h["budget"]) for h in mine if h.get("budget")]
        print(f"  {m}: задач {n}, переделок по жалобе {r} ({pct(r, n)}), smoke✗ {sb}, СЛОЖНО {hard}, ошибок {err}, лимит$ {bud}")
        print(f"     $ на задачу: сред {sum(cost) / n:.2f}, медиана {med(cost):.2f}, макс {max(cost):.2f}, всего {sum(cost):.2f}"
              + (f"; контекст: медиана {med(ctx) // 1000}k, макс {max(ctx) // 1000}k" if ctx else "")
              + (f"; лимит $ использован: медиана {100 * med(use):.0f}%, макс {100 * max(use):.0f}%" if use else ""))
    waits = [(iso(h["started"]) - iso(h["created"])).total_seconds() / 60 for h in done if iso(h.get("created")) and iso(h.get("started"))]
    lead = [(iso(h["finished"]) - iso(h["created"])).total_seconds() / 60 for h in done if h.get("pushed") and iso(h.get("created")) and iso(h.get("finished"))]
    print(f"  промпт->пуш (v1): медиана {fmt_min(med(lead))}, макс {fmt_min(max(lead) if lead else None)} ({len(lead)} задач); ожидание в очереди: медиана {fmt_min(med(waits))}")
    merged = sum(int(h.get("merged") or 0) for h in done)
    print(f"  склеено промптов: {merged}; уточнений к работающей задаче: {sum(1 for h in done if h.get('cont_of') and not h.get('smoke_of'))};"
          f" повторных жалоб со скриншотом: {sum(1 for h in done if h.get('shot'))}")


def section_concurrent_v1(hist):
    print("== 2а. Файлы, которые правили 2+ задачи v1 одновременно (окна задач пересекаются)")
    tasks = []
    for h in hist:
        if h.get("t") == "done" and h.get("commits") and iso(h.get("started")) and iso(h.get("finished")):
            fs = set()
            for c in h["commits"]:
                fs |= {f for f in git("show", "--name-only", "--format=", c, cwd=REPO).split("\n") if f and f not in SKIP}
            tasks.append((iso(h["started"]), iso(h["finished"]), h["id"], fs))
    hits = defaultdict(set)
    for i, a in enumerate(tasks):
        for b in tasks[i + 1:]:
            if a[0] < b[1] and b[0] < a[1]:
                for f in a[3] & b[3]:
                    hits[f] |= {a[2], b[2]}
    if not hits:
        print("  нет" if tasks else "  нет данных (в history.jsonl нет задач с коммитами — поле commits пишет новая версия)")
    for f, ids in sorted(hits.items(), key=lambda x: -len(x[1]))[:15]:
        print(f"  {f}: задачи #{', #'.join(map(str, sorted(ids)))}")


def section_day(day, prompts, skew):
    cs = commits(day)
    print(f"== Базовая линия за {day} по git log origin/main (часы ПК, сдвиг -{skew} мин к МСК)")
    if not cs:
        print("  коммитов нет")
        return
    by = defaultdict(int)
    for c in cs:
        by[c[2]] += 1
    fixes = [c for c in cs if re.search(r"(?i)почин|исправ|верн|откат|не работ|сломал|fix|revert|баг", c[4])]
    print(f"  коммитов {len(cs)} ({', '.join(f'{k} {v}' for k, v in sorted(by.items()))}); похожих на починку/откат {len(fixes)} ({pct(len(fixes), len(cs))})")
    fb = defaultdict(int)
    for c in fixes:
        fb[c[2]] += 1
    if fb:
        print("    починки по модели автора: " + ", ".join(f"{k} {v} из {by[k]} ({pct(v, by[k])})" for k, v in sorted(fb.items())))
    # 2б: один файл — в разных коммитах с разницей < 30 мин (признак параллельной правки одного места)
    last = {}
    hits = defaultdict(set)
    for t, h, m, fs, s in cs:
        for f in fs:
            if f in SKIP:
                continue
            if f in last and (t - last[f][0]).total_seconds() < 1800 and last[f][1] != h:
                hits[f] |= {last[f][1], h}
            last[f] = (t, h)
    print(f"== 2б. Файлы, которые за {day} правили 2+ коммита с разницей < 30 мин: {len(hits)}")
    for f, hs in sorted(hits.items(), key=lambda x: -len(x[1]))[:12]:
        print(f"  {f}: {len(hs)} коммитов")
    # 3/4: промпт -> первый следующий коммит; промпты без реакции > 5 мин
    ct = [c[0].replace(tzinfo=None) - timedelta(minutes=skew) for c in cs]
    ps = [p for p in prompts if p.strftime("%d.%m") == day]
    if not ps:
        print("== 3. Промпт->пуш: нет истории промптов (запусти с --prompts 200 — читает prompts.ps1 last, ничего не помечает)")
        return
    lat = []
    for p in ps:
        nxt = [t for t in ct if t >= p]
        if nxt:
            lat.append((nxt[0] - p).total_seconds() / 60)
    hours = defaultdict(int)
    for p in ps:
        hours[p.hour] += 1
    print(f"== 3. Промпты за {day}: {len(ps)}, макс в час {max(hours.values())} (в {max(hours, key=hours.get)}:00 МСК)")
    print(f"  промпт -> первый следующий коммит: медиана {fmt_min(med(lat))}, 90% {fmt_min(sorted(lat)[int(len(lat) * .9)] if lat else None)}")
    # реакция: любая строка dispatch.log (создание worktree и т.п.) после промпта
    acts = []
    for l in open(os.path.join(DISP, "dispatch.log"), encoding="utf-8-sig", errors="replace"):
        m = re.match(r"(\d\d\.\d\d \d\d:\d\d):\d\d", l)
        if m:
            t = ddmm(m.group(1))
            if t:
                acts.append(t - timedelta(minutes=skew))
    acts.sort()
    slow = []
    for p in ps:
        nxt = [t for t in acts + ct if t >= p]
        if not nxt or (min(nxt) - p).total_seconds() > 300:
            slow.append((p, (min(nxt) - p).total_seconds() / 60 if nxt else None))
    print(f"== 4. Промпты без реакции > 5 мин за {day} (нет ни коммита, ни строки в dispatch.log): {len(slow)}")
    for p, m in slow[:10]:
        print(f"  {p:%H:%M} — реакция через {fmt_min(m)}")


def section_alive():
    p = os.path.join(DISP, "alive.log")
    print("== 4а. Дыры в слушании TG > 5 мин (alive.log, пишет dispatch.ps1 раз в минуту)")
    if not os.path.exists(p):
        print("  alive.log ещё нет (появится после запуска новой версии диспетчера)")
        return
    ts = [ddmm(l.strip()) for l in open(p, encoding="utf-8-sig") if l.strip()]
    ts = sorted(t for t in ts if t)
    gaps = [(a, b) for a, b in zip(ts, ts[1:]) if (b - a).total_seconds() > 300]
    print(f"  отметок {len(ts)}, дыр {len(gaps)}")
    for a, b in gaps[-10:]:
        print(f"  {a:%d.%m %H:%M} -> {b:%H:%M} ({fmt_min((b - a).total_seconds() / 60)})")


def section_limits():
    p = os.path.join(DISP, "dispatch.log")
    n = 0
    if os.path.exists(p):
        n = sum(1 for l in open(p, encoding="utf-8-sig", errors="replace") if "лимит Claude" in l and "снова в очереди" in l)
    print(f"== 5. Лимит сессии Claude: задач, вернувшихся в очередь из-за лимита: {n}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--day", default=datetime.now().strftime("%d.%m"))
    ap.add_argument("--prompts", type=int, default=0, help="прочитать prompts.ps1 last N")
    ap.add_argument("--prompts-file", default="")
    ap.add_argument("--skew", type=int, default=20, help="на сколько минут спешат часы ПК")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    git("fetch", "-q", "origin", "main", cwd=REPO)
    hist = load_hist()
    section_v1(hist)
    section_concurrent_v1(hist)
    section_alive()
    section_limits()
    section_day(a.day, load_prompts(a), a.skew)


if __name__ == "__main__":
    main()
