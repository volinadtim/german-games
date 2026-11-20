#!/usr/bin/env bash
# Пересобрать превью расстановки THE LEAK (без окна): scenes/props/preview/*.tscn и scenes/locations/preview/* —
# модели объектов и мест для редактора. Сцены мест scenes/locations/<место>.tscn (метки) НЕ перезаписываются:
# их правят руками в редакторе. Создать заново из текущего кода — scripts/bake-places.sh --force (осторожно).
P="godot/THE LEAK"
cd "$(git rev-parse --show-toplevel)" || exit 1
OV="$P/override.cfg"
[ -f "$OV" ] && { echo "в $P уже есть override.cfg — убери его"; exit 1; }
printf '[application]\n\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="THE LEAK smoke"\n' >"$OV"
LOG=$(mktemp); trap 'rm -f "$OV" "$LOG"' EXIT
( timeout 200 godot --headless --path "$P" --fixed-fps 60 res://tests/tools/bake_places.tscn -- "$@" >"$LOG" 2>&1; true ) 2>/dev/null
grep -E "^BAKE|SMOKE FAIL|SCRIPT ERROR|Parse Error" "$LOG" | tail -40
grep -q "SMOKE FAIL\|SCRIPT ERROR\|Parse Error" "$LOG" && exit 1
exit 0
