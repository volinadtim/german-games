#!/usr/bin/env bash
# Проверка Godot-проекта без шума: печатает OK или только ошибки (не больше 40 строк).
#   scripts/gd-check.sh [путь-к-проекту=godot/eskiness] [--import]
# --import — сначала переимпорт ресурсов (нужно после добавления моделей/текстур/звуков).
P="${1:-godot/eskiness}"; [ "$P" = "--import" ] && { P=godot/eskiness; IMP=1; }
[ "${2:-}" = "--import" ] && IMP=1
LOG=$(mktemp)
[ -n "${IMP:-}" ] && timeout 300 godot --headless --path "$P" --import >/dev/null 2>&1
timeout 150 godot --headless --path "$P" --quit-after 120 >"$LOG" 2>&1
ERR=$(grep -E -A1 "SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Invalid" "$LOG" | grep -v '^--$' | awk '!seen[$0]++' | head -40)
rm -f "$LOG"
if [ -z "$ERR" ]; then echo OK; else echo "$ERR"; exit 1; fi
