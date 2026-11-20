"""Сравнение снимка smoke (tests/smoke.gd) с baseline.json: печатает, что пропало или уменьшилось (>5%).
   python scripts/smoke_cmp.py <baseline.json> <stats.json>"""
import json, sys
sys.stdout.reconfigure(encoding="utf-8")
old = json.load(open(sys.argv[1], encoding='utf-8'))
new = json.load(open(sys.argv[2], encoding='utf-8'))
def walk(o, n, p):
    if isinstance(o, dict):
        for k in o:
            walk(o[k], n.get(k) if isinstance(n, dict) else None, p + '/' + k)
    elif isinstance(o, (int, float)):
        if not isinstance(n, (int, float)):
            print('пропало: %s (было %s)' % (p, o))
        elif n < o * 0.95 - 1:
            print('меньше: %s %s -> %s' % (p, o, n))
        elif n != o:
            print('  изменилось: %s %s -> %s' % (p, o, n))
walk(old, new, '')
