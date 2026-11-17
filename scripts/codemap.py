# -*- coding: utf-8 -*-
"""Карта кода Godot-игры без LLM: файл -> строки, extends, описание; функции/сигналы/константы со строкой и ## описанием.

    python scripts/codemap.py [godot/eskiness]   -> godot/eskiness/CODEMAP.md (в git не кладём, строится заново)

Агент не листает код в поисках места, а делает `grep -n -i "<слово>" godot/eskiness/CODEMAP.md`
и сразу читает нужные строки (Read с offset/limit). Номера строк — на момент генерации.
"""
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else 'godot/eskiness'
FUNC = re.compile(r'^(static\s+)?func\s+(\w+)\s*\(([^)]*)\)')
SIG = re.compile(r'^signal\s+(\w+)')
CONST = re.compile(r'^const\s+([A-Z_][A-Z0-9_]*)\b')
EXT = re.compile(r'^extends\s+(.+)')


def short_args(a):
    a = re.sub(r'\s*:\s*[\w\[\]\.]+', '', a)      # типы
    a = re.sub(r'\s*:?=\s*[^,]+', '', a)           # значения по умолчанию
    return re.sub(r'\s+', ' ', a).strip()


files = []
for d, dirs, fs in os.walk(root):
    dirs[:] = [x for x in dirs if not x.startswith('.') and x != 'addons']
    for f in fs:
        if f.endswith('.gd'):
            files.append(os.path.join(d, f))
files.sort()

out = ['# Карта кода (сгенерировано scripts/codemap.py — не править руками)',
       '# Ищи: grep -n -i "<слово>" CODEMAP.md  ->  читай нужные строки файла (Read offset/limit), а не весь файл.',
       '# Формат: ## файл (N стр.) [extends] — описание;  затем  <файл>:<строка> <имя>(<аргументы>) — описание из ## над функцией. Пути от godot/eskiness/.', '']
total_funcs = 0
for path in files:
    rel = os.path.relpath(path, root).replace('\\', '/')
    lines = open(path, encoding='utf-8', errors='ignore').read().splitlines()
    ext, desc = '', ''
    for ln in lines[:12]:
        m = EXT.match(ln)
        if m:
            ext = m.group(1).strip().replace('"res://scripts/', '"').replace('res://scripts/', '')
        elif ln.startswith('#') and not desc:
            desc = ln.lstrip('#').strip()
    head = f'## {rel} ({len(lines)} стр.)'
    if ext:
        head += f' extends {ext}'
    if desc:
        head += f' — {desc[:140]}'
    out.append(head)
    items = []
    for i, ln in enumerate(lines):
        doc = ''
        j = i - 1
        while j >= 0 and lines[j].startswith('##'):
            doc = lines[j].lstrip('#').strip() + (' ' + doc if doc else ''); j -= 1
        m = FUNC.match(ln)
        if m:
            total_funcs += 1
            items.append(f'{rel}:{i+1} {m.group(2)}({short_args(m.group(3))})' + (f' — {doc[:120]}' if doc else ''))
            continue
        m = SIG.match(ln) or CONST.match(ln)
        if m:
            kind = 'signal' if ln.startswith('signal') else 'const'
            items.append(f'{rel}:{i+1} {kind} {m.group(1)}' + (f' — {doc[:100]}' if doc else ''))
    out.extend(items)
    out.append('')

dst = os.path.join(root, 'CODEMAP.md')
open(dst, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print(f'{dst}: {len(files)} файлов, {total_funcs} функций, {len(out)} строк')
