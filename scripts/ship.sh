#!/usr/bin/env bash
# Коммит -> pull --rebase -> gd-check (уже ПОСЛЕ слияния со свежим main) -> push. Печатает одну строку: хеш и заголовок.
#   scripts/ship.sh "сообщение" [файлы...]      (без файлов — git add -A)
# Модель в Co-Authored-By: переменная SHIP_MODEL (по умолчанию "Claude Opus 5.5").
#   ANSWER="что сделано; что проверить" ANSWER_AT="ЧЧ:ММ" scripts/ship.sh ...  — заодно раздел сверху в ANSWER.md
# Проверяется то, что реально уйдёт в main: свой коммит поверх свежего origin/main. Если main сдвинулся,
# пока шла проверка, — rebase и проверка заново (до 4 раз).
# Коды выхода:
#   0 — отправлено;  1 — gd-check нашёл ошибки (коммит снят, правки остались в файлах);
#   3 — конфликт в коде при rebase: rebase отменён, ничего не отправлено — ПЕРЕДЕЛАЙ задачу на свежем main
#       (git fetch -q origin main && git reset -q --hard origin/main, правки заново), маркеры конфликта не править;
#   4 — push не прошёл.
MSG="$1"; shift
cd "$(git rev-parse --show-toplevel)" || exit 1
if [ $# -gt 0 ]; then git add -- "$@"; else git add -A; fi
# проекты Godot, затронутые коммитом: поднимаемся от файла до папки с project.godot
PROJS=$(git diff --cached --name-only | grep '^godot/' | while IFS= read -r f; do
  d=$(dirname "$f"); while [ "$d" != "." ] && [ "$d" != "godot" ] && [ ! -f "$d/project.godot" ]; do d=$(dirname "$d"); done
  [ -f "$d/project.godot" ] && echo "$d"; done | sort -u)
git diff --cached --quiet && { echo "нечего отправлять: нет изменений"; exit 1; }
if [ -n "${ANSWER:-}" ]; then
  { printf '## %s — %s\n\n%s\n\n' "${ANSWER_AT:-??:??}" "$MSG" "$ANSWER"; cat ANSWER.md 2>/dev/null; } > ANSWER.md.tmp && mv ANSWER.md.tmp ANSWER.md
  git add ANSWER.md
fi
git commit -q -m "$MSG" -m "Co-Authored-By: ${SHIP_MODEL:-Claude Opus 5.5} <noreply@anthropic.com>" >/dev/null 2>&1 || { echo "коммит не создан"; exit 1; }
in_rebase() { [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; }
# свой коммит снять, правки оставить в файлах (ANSWER.md вернуть, чтобы раздел не задвоился при повторе)
uncommit() { git reset -q --soft HEAD~1; git reset -q; git checkout -q HEAD -- ANSWER.md 2>/dev/null; }
for i in 1 2 3 4; do
  if ! git pull -q --rebase origin main >/dev/null 2>&1; then
    # конфликт только в ANSWER.md — склеиваем обе версии и продолжаем
    while in_rebase && [ "$(git diff --name-only --diff-filter=U)" = "ANSWER.md" ]; do
      T=$(mktemp -d)
      git show :2:ANSWER.md >"$T/a2" 2>/dev/null; git show :1:ANSWER.md >"$T/a1" 2>/dev/null; git show :3:ANSWER.md >"$T/a3" 2>/dev/null
      git merge-file --union -p "$T/a3" "$T/a1" "$T/a2" >ANSWER.md; rm -rf "$T"; git add ANSWER.md
      GIT_EDITOR=true git rebase --continue >/dev/null 2>&1 || true
    done
    if in_rebase; then
      FILES=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
      git rebase --abort >/dev/null 2>&1
      echo "КОНФЛИКТ В КОДЕ: переделай задачу на свежем main (ничего не отправлено). Файлы: $FILES"
      echo "  git fetch -q origin main && git reset -q --hard origin/main  — потом правки заново и снова ship.sh; маркеры конфликта не править"
      exit 3
    fi
  fi
  BASE=$(git rev-parse HEAD~1)
  # проверка того, что уйдёт в main: свой коммит уже поверх свежего main
  while IFS= read -r P; do
    [ -z "$P" ] && continue
    if ! OUT=$(bash scripts/gd-check.sh "$P" 2>&1); then
      uncommit; echo "НЕ ОТПРАВЛЕНО — gd-check ($P) после слияния со свежим main:"; echo "$OUT"
      echo "(если ошибка в файлах, которых ты не трогал, — main уже сломан чужим коммитом; напиши это в ответе)"
      exit 1
    fi
  done <<< "$PROJS"
  # пока шла проверка, main мог сдвинуться — тогда rebase и проверка заново
  git fetch -q origin main >/dev/null 2>&1
  [ "$(git rev-parse origin/main)" != "$BASE" ] && continue
  git push -q origin HEAD:main >/dev/null 2>&1 && { git log --oneline -1; exit 0; }
done
echo "push не прошёл 4 раза (main всё время двигался)"; exit 4
