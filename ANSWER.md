# Ответ на промпт 14.11 17:07 МСК (@mehheehh)

> я ничего не понял, как и что мне сделать всё это (+ скрин: `git stash pop` → конфликт в jar.gd)

Ничего не потерялось. Разбираться самому не надо: **скопируй весь блок ниже целиком в то же окно PowerShell и нажми Enter**. Он сохранит всё как есть и отправит на GitHub в отдельные ветки `german-...`, а я сам соединю твои правки с игрой.

```
cd $env:USERPROFILE\german-games
git checkout -b german-now
git add -A
git commit -m "German: local changes"
$n = @(git stash list).Count
for ($i = 0; $i -lt $n; $i++) { git push origin "stash@{$i}:refs/heads/german-stash-$i" }
git push origin german-now
git checkout main
```

Потом снова запусти auto-pull так же, как раньше (двойной клик по `auto-pull.bat`). Писать `auto-pull` в PowerShell не надо, так он не запускается.

- Если в конце видно `-> german-now` и `-> german-stash-0`, всё ушло, напиши «готово».
- Если пишет **Permission denied / 403** или просит войти: у твоего GitHub нет прав на запись. Тогда пришли скрин, Тим добавит тебя в Collaborators.
