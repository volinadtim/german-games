# -*- coding: utf-8 -*-
"""Сколько воркеры диспетчера перечитывают одно и то же. Токены не тратит: только читает транскрипты.

    python scripts/dispatch/reread.py            # все воркеры (транскрипты disp-*)
    python scripts/dispatch/reread.py --last 20  # только последние 20 сессий

Что считает:
  * по каждой сессии — сколько строк кода прочитано, сколько из них повторно (в этой же сессии),
    сколько ушло на «ритуал» (git pull, wc -l, AGENTS.md…), стартовый контекст и кэш;
  * по всем сессиям — какие файлы/строки читают снова и снова разные агенты,
    и какие команды повторяются в начале каждой сессии.
Чтение = Read (offset/limit), а также cat / sed -n 'a,bp' / head / tail в Bash. grep считается отдельно (поиск).
Токены оценены грубо: символы / 3.
"""
import json, glob, os, re, sys, collections

BASE = os.path.expanduser('~/.claude/projects')
PAT = BASE + '/C--Users-volin-Documents-Web-german-games--claude-worktrees-disp-*/*.jsonl'
RITUAL = [('git pull', r'git pull'), ('git log/status', r'git (log|status)'), ('wc -l', r'\bwc -l'),
          ('AGENTS.md', r'AGENTS\.md'), ('ANSWER.md', r'ANSWER\.md'), ('ls', r'(^|[;&|]\s*)ls\b')]


def rel(p):
    p = p.replace('\\', '/')
    m = re.search(r'(godot/[^\s\'"]+|scripts/[^\s\'"]+|rust/[^\s\'"]+|[A-Z]+\.md)$', p)
    r = m.group(1) if m else p.split('/')[-1]
    # из godot/eskiness агенты пишут пути от scripts/ — приводим к одному виду
    if r.startswith('scripts/') and r.endswith(('.gd', '.tscn', '.gdshader')):
        r = 'godot/eskiness/' + r
    return r


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return '\n'.join(c.get('text', '') for c in content if isinstance(c, dict))
    return ''


def bash_reads(cmd, cwd_rel):
    """Чтения файлов из bash-команды: [(файл, начало, конец)] (конец=None — весь файл/неизвестно)."""
    out = []
    for part in re.split(r'&&|;|\|\||\n', cmd):
        part = part.strip()
        m = re.match(r"sed -n ['\"]?(\d+),(\d+)p['\"]? (\S+)", part)
        if m:
            out.append((m.group(3), int(m.group(1)), int(m.group(2)))); continue
        m = re.match(r"(cat|head|tail)\b(?: -n ?\d+| -\d+)* (\S+\.(?:gd|md|tscn|json|cfg|ps1|sh|rs|toml))", part)
        if m:
            out.append((m.group(2), 1, None))
    return [(cwd_rel + '/' + f if cwd_rel and not f.startswith(('/', 'godot', 'scripts')) else f, a, b) for f, a, b in out]


def scan(path):
    s = dict(file=path, zone=re.search(r'disp-([a-z]+)', path).group(1), model='', turns=0, first_ctx=0,
             first_cache_read=0, cread=0, cwrite=0, out=0, reads=[], greps=0, ritual=collections.Counter(),
             ritual_chars=0, read_chars=0, first_cmds=[], items=[])
    tools = {}
    seen = set()
    cwd_rel = ''
    for line in open(path, encoding='utf-8', errors='ignore'):
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get('message') or {}
        if d.get('type') == 'assistant':
            for c in m.get('content') or []:
                if isinstance(c, dict) and c.get('type') == 'tool_use':
                    tools[c['id']] = (c['name'], c.get('input', {}))
                    if c['name'] in ('Bash', 'PowerShell') and len(s['first_cmds']) < 3:
                        s['first_cmds'].append(c['input'].get('command', '')[:70])
            if m.get('id') in seen or not m.get('usage'):
                continue
            seen.add(m.get('id'))
            u = m['usage']
            s['model'] = s['model'] or (m.get('model') or '').replace('claude-', '')
            ctx = (u.get('input_tokens') or 0) + (u.get('cache_read_input_tokens') or 0) + (u.get('cache_creation_input_tokens') or 0)
            if s['turns'] == 0:
                s['first_ctx'] = ctx; s['first_cache_read'] = u.get('cache_read_input_tokens') or 0
            s['turns'] += 1
            s['cread'] += u.get('cache_read_input_tokens') or 0
            s['cwrite'] += (u.get('cache_creation_input_tokens') or 0) + (u.get('input_tokens') or 0)
            s['out'] += u.get('output_tokens') or 0
            s['items'].append(('ответы/мысли модели', u.get('output_tokens') or 0, s['turns']))
        elif d.get('type') == 'user' and isinstance(m.get('content'), list):
            for c in m['content']:
                if not (isinstance(c, dict) and c.get('type') == 'tool_result'):
                    continue
                name, inp = tools.get(c.get('tool_use_id'), ('?', {}))
                txt = text_of(c.get('content'))
                cat = 'чтение кода' if name == 'Read' else 'правки' if name in ('Edit', 'Write') else 'прочее'
                if name in ('Bash', 'PowerShell'):
                    cmd0 = inp.get('command', '')
                    cat = ('ритуал' if any(re.search(rx, cmd0, re.M) for _, rx in RITUAL) else
                           'чтение кода' if bash_reads(cmd0, '') else 'grep/поиск' if re.search(r'grep', cmd0) else
                           'проверка/пуш' if re.search(r'gd-check|ship\.sh', cmd0) else 'прочие команды')
                s['items'].append((cat, len(txt) // 3 + len(json.dumps(inp, ensure_ascii=False)) // 3, s['turns']))
                if name == 'Read':
                    f = rel(inp.get('file_path', ''))
                    n = len(txt.splitlines())
                    a = int(inp.get('offset') or 1)
                    s['reads'].append((f, a, a + max(n, 1) - 1, 'Read'))
                    s['read_chars'] += len(txt)
                elif name in ('Bash', 'PowerShell'):
                    cmd = inp.get('command', '')
                    md = re.search(r'cd ([^;&\n]+)', cmd)
                    if md:
                        cwd_rel = rel(md.group(1).strip().strip('"'))
                        cwd_rel = cwd_rel if cwd_rel.startswith(('godot', 'scripts')) else ''
                    if re.search(r'\bgrep\b', cmd):
                        s['greps'] += 1
                    hit = False
                    for k, rx in RITUAL:
                        if re.search(rx, cmd, re.M):
                            s['ritual'][k] += 1; hit = True
                    if hit:
                        s['ritual_chars'] += len(txt)
                    for f, a, b in bash_reads(cmd, cwd_rel):
                        if b is None:
                            b = a + max(len(txt.splitlines()), 1) - 1
                        s['reads'].append((rel(f), a, b, 'bash'))
                        s['read_chars'] += len(txt)
    return s


def overlap_lines(reads):
    """Сколько строк прочитано всего и сколько из них — повторно."""
    by = collections.defaultdict(list)
    for f, a, b, _ in reads:
        by[f].append((a, b))
    total = again = 0
    per_file = {}
    for f, rs in by.items():
        cnt = collections.Counter()
        for a, b in rs:
            for i in range(a, b + 1):
                cnt[i] += 1
        t = sum(cnt.values()); r = sum(v - 1 for v in cnt.values())
        total += t; again += r; per_file[f] = (len(rs), t, r)
    return total, again, per_file


def main():
    files = sorted(glob.glob(PAT), key=os.path.getmtime)
    if '--last' in sys.argv:
        files = files[-int(sys.argv[sys.argv.index('--last') + 1]):]
    sess = [scan(f) for f in files]
    sess = [s for s in sess if s['turns']]
    print(f'Сессий воркеров: {len(sess)}\n')
    print(f"{'зона':8} {'модель':10} {'шаг':>4} {'старт':>6} {'кэш@старт':>9} {'чит.стр':>7} {'повтор':>7} {'ритуал':>7} {'grep':>4}  файлов")
    tot_lines = tot_again = 0
    for s in sess:
        t, r, pf = overlap_lines(s['reads'])
        tot_lines += t; tot_again += r
        rit = sum(s['ritual'].values())
        print(f"{s['zone']:8} {s['model'][:10]:10} {s['turns']:>4} {s['first_ctx']//1000:>5}k {s['first_cache_read']//1000:>8}k {t:>7} {r:>7} {rit:>7} {s['greps']:>4}  {len(pf)}")
    print(f'\nВсего прочитано строк: {tot_lines}, из них повторно внутри своей же сессии: {tot_again} ({100*tot_again//max(tot_lines,1)}%)')

    # между сессиями: файлы и строки, которые читают снова и снова разные агенты
    cross = collections.defaultdict(lambda: collections.Counter())
    readers = collections.defaultdict(set)
    for i, s in enumerate(sess):
        for f, a, b, _ in s['reads']:
            readers[f].add(i)
            for ln in range(a, b + 1):
                cross[f][ln] += 1
    print('\nФайлы, которые читают разные сессии (топ 15):')
    print(f"{'сессий':>6} {'строк всего':>11} {'уникальных':>10}  файл")
    rows = sorted(cross.items(), key=lambda kv: -sum(kv[1].values()))[:15]
    for f, c in rows:
        print(f"{len(readers[f]):>6} {sum(c.values()):>11} {len(c):>10}  {f}")
    all_lines = sum(sum(c.values()) for c in cross.values()); uniq = sum(len(c) for c in cross.values())
    print(f'\nПо всем сессиям: прочитано {all_lines} строк, уникальных {uniq} — каждая строка кода в среднем прочитана {all_lines/max(uniq,1):.1f} раза.')

    rc = collections.Counter(); rchars = 0
    for s in sess:
        rc.update(s['ritual']); rchars += s['ritual_chars']
    print('\nРитуал (одинаковые команды почти в каждой сессии):')
    for k, v in rc.most_common():
        print(f'  {k:16} {v:4} раз, в среднем {v/len(sess):.1f} на сессию')
    print(f'  вывод ритуала в контексте: ~{rchars//3//1000}k токенов на все сессии (~{rchars//3//max(len(sess),1)} на сессию), и он перечитывается каждым следующим шагом')

    # Во что реально обходится каждый кусок контекста: его токены × сколько шагов он ещё перечитывается.
    eff = collections.Counter()
    for s in sess:
        eff['стартовый контекст'] += s['first_ctx'] * s['turns']
        for cat, tok, at in s['items']:
            eff[cat] += tok * max(s['turns'] - at, 0)
    tot = sum(eff.values())
    print('\nКуда уходит перечитывание контекста (токены × оставшиеся шаги):')
    for k, v in eff.most_common():
        print(f'  {k:22} {v/1e6:6.1f}M  {100*v/max(tot,1):4.0f}%')
    tr = sum(s['cread'] for s in sess); tw = sum(s['cwrite'] for s in sess); to = sum(s['out'] for s in sess)
    print(f'\nТокены воркеров: чтение кэша {tr/1e6:.1f}M, запись в кэш/без кэша {tw/1e6:.1f}M, вывод {to/1e6:.2f}M')
    print(f"Старт сессии: в среднем {sum(s['first_ctx'] for s in sess)//len(sess)//1000}k, из них из кэша {sum(s['first_cache_read'] for s in sess)//len(sess)//1000}k")


if __name__ == '__main__':
    main()
