#!/usr/bin/env bash
# Проверка запуска игры без окна (~30–60 с): бункер, деревня, лагерь у озера, город, инвентарь, магазин, настройки, сплитскрин.
#   scripts/smoke.sh [проект=godot/THE LEAK] [--compare | --baseline]
# Печатает OK или список ошибок (SCRIPT ERROR / Failed to load / Parse Error / нет пола / падение по Y); код выхода 0/1.
#   --compare  — заодно сравнить снимок (узлы, коллизии, предметы, символы, товары) с <проект>/tests/baseline.json
#   --baseline — записать текущий снимок в <проект>/tests/baseline.json
# Сейвы и settings.cfg игрока не трогаются: на время прогона override.cfg переключает user:// в папку «THE LEAK smoke».
P="godot/THE LEAK"; MODE=""
for a in "$@"; do case "$a" in --compare) MODE=compare;; --baseline) MODE=baseline;; *) P="$a";; esac; done
cd "$(git rev-parse --show-toplevel)" || exit 1
[ -f "$P/tests/smoke.tscn" ] || { echo "нет $P/tests/smoke.tscn"; exit 1; }
[ -d "$P/.godot" ] || timeout 300 godot --headless --path "$P" --import >/dev/null 2>&1
OV="$P/override.cfg"
if [ -f "$OV" ]; then echo "в $P уже есть override.cfg — убери его (smoke.sh создаёт свой)"; exit 1; fi
printf '[application]\n\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="THE LEAK smoke"\n' >"$OV"
LOG=$(mktemp); trap 'rm -f "$OV" "$LOG"' EXIT
( timeout 120 godot --headless --path "$P" --fixed-fps 60 res://tests/smoke.tscn >"$LOG" 2>&1; true ) 2>/dev/null   # на выходе Godot иногда падает — не важно, итог по «SMOKE DONE»
ERR=$(grep -E -A1 "SCRIPT ERROR|Parse Error|ERROR:|Failed to load|SMOKE FAIL" "$LOG" | grep -v '^--$' | awk '!seen[$0]++' | head -40)
grep -q "SMOKE DONE" "$LOG" || ERR="$ERR"$'\n'"smoke не дошёл до конца (вылет или зависание): $(tail -5 "$LOG")"
STATS=$(grep '^SMOKE STATS ' "$LOG" | head -1 | sed 's/^SMOKE STATS //')
BASE="$P/tests/baseline.json"
CMP=""
if [ "$MODE" = baseline ] && [ -n "$STATS" ]; then
  printf '%s' "$STATS" | python -c "import json,sys; json.dump(json.load(sys.stdin), open(sys.argv[1],'w',encoding='utf-8'), ensure_ascii=False, indent=1, sort_keys=True)" "$BASE"
  echo "baseline записан: $BASE"
elif [ "$MODE" = compare ] && [ -n "$STATS" ]; then
  printf '%s' "$STATS" >"$LOG.json"
  CMP=$(python scripts/smoke_cmp.py "$BASE" "$LOG.json"); rm -f "$LOG.json"
  [ -n "$CMP" ] && echo "$CMP"
  echo "$CMP" | grep -qE '^(пропало|меньше)' && ERR="$ERR"$'\n'"снимок меньше baseline (см. выше)"
fi
ERR=$(echo "$ERR" | sed '/^$/d')
if [ -z "$ERR" ]; then echo OK; else echo "$ERR"; exit 1; fi
