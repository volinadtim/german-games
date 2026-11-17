#!/usr/bin/env bash
# Коммит + pull --rebase + push в main одной командой. Печатает одну строку: хеш и заголовок.
#   scripts/ship.sh "сообщение" [файлы...]      (без файлов — git add -A)
# Модель в Co-Authored-By: переменная SHIP_MODEL (по умолчанию "Claude Opus 5.5").
MSG="$1"; shift
if [ $# -gt 0 ]; then git add -- "$@"; else git add -A; fi
git commit -q -m "$MSG" -m "Co-Authored-By: ${SHIP_MODEL:-Claude Opus 5.5} <noreply@anthropic.com>" >/dev/null 2>&1
for i in 1 2 3; do
  if ! git pull -q --rebase origin main >/dev/null 2>&1; then
    # конфликт только в ANSWER.md — склеиваем обе версии и продолжаем
    while [ "$(git diff --name-only --diff-filter=U)" = "ANSWER.md" ]; do
      git show :2:ANSWER.md >/tmp/a2 2>/dev/null; git show :1:ANSWER.md >/tmp/a1 2>/dev/null; git show :3:ANSWER.md >/tmp/a3 2>/dev/null
      git merge-file --union -p /tmp/a3 /tmp/a1 /tmp/a2 >ANSWER.md; git add ANSWER.md
      GIT_EDITOR=true git rebase --continue >/dev/null 2>&1 && break
    done
    [ -d .git/rebase-merge ] || [ -d "$(git rev-parse --git-path rebase-merge)" ] || { git push -q origin HEAD:main >/dev/null 2>&1 && { git log --oneline -1; exit 0; }; continue; }
    echo "КОНФЛИКТ при rebase, разреши и запусти снова:"; git diff --name-only --diff-filter=U; exit 1
  fi
  git push -q origin HEAD:main >/dev/null 2>&1 && { git log --oneline -1; exit 0; }
done
echo "push не прошёл 3 раза"; exit 1
