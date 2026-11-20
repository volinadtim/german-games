# Диспетчер TG-промптов без LLM-сессии.
# Ждёт промпт Германа -> Sonnet (low) выбирает зону/агента/продолжать или нет -> воркер `claude -p --agent ...`
# в своём worktree на зону (.claude\worktrees\disp-<зона>). Зоны работают параллельно, в одной зоне — очередь.
# Worktree создаёт и удаляет только scripts\dispatch\wt.js: sparse без Blender/, создаётся под задачу и
# удаляется сразу после неё (если чистый и запушен), не больше -MaxWt одновременно, очистка брошенных при старте и раз в 30 мин.
# Место: wt.js не создаёт worktree, если на диске меньше minFreeGB или все worktree задач больше maxGB — сначала убирает,
# потом задача ждёт в очереди (не падает). Лимит сессии Claude («hit your session limit») — не ошибка: задача
# возвращается в очередь как продолжение, новые воркеры не стартуют 15 мин.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dispatch\dispatch.ps1            # слушать TG
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dispatch\dispatch.ps1 -Task "…"  # одна задача без TG (по-настоящему правит и пушит!)
#
# Воркеры — отдельные скрытые процессы: закрытие/перезапуск диспетчера их НЕ трогает, он только перестаёт
# слушать TG. При следующем запуске он подхватывает работающих воркеров и очередь из .claude\dispatch\jobs.json.
# Остановка разработки — отдельной командой: scripts\dispatch\ctl.ps1 stop|kill|resume|status
#   stop   — мягкая: новые задачи не стартуют, работающим воркерам хук говорит «доделай или оставь handoff»;
#   kill   — жёсткая: убить воркеров сразу; resume — снять стоп и продолжить паузы/прерванные.
# Задачи можно класть и без TG: файл .claude\dispatch\inbox\*.txt (так делает TUI — tools\disp-tui).
#
# Надёжность — кодом, а не правилами для модели:
#  - склейка: новый промпт ждёт -HoldSec (150 с); промпты той же зоны за это время (и пока задача не началась)
#    склеиваются в одну задачу, последний главнее. Уточнение/жалоба к работающей задаче (роутер: refines) —
#    продолжением той же сессии воркера после её завершения;
#  - после каждого пуша воркера — scripts/smoke.sh на свежем main в постоянной sparse-копии «smoke», по очереди.
#    Упало — бисект по коммитам с последнего зелёного main, виновному воркеру — продолжение с текстом ошибки
#    (не больше 2 раз на задачу); чужой коммит — только статус;
#  - повторная жалоба на задачу — в брифе разрешён один прогон игры со скриншотом;
#  - лимит $ на задачу (--max-budget-usd), очередь зоны > 3 — предупреждение;
#  - статусы Герману: .claude\dispatch\status.md + TUI (отправка в TG закрыта: ключ atlas только на чтение).
# Сухой прогон (ничего не правит и не пушит, своя папка .claude\dispatch-dry, роутер настоящий):
#   dispatch.ps1 -DryRun -TestPrompts файл    # строки «секунда|текст промпта»
param(
    [string]$Repo = "",
    [int]$MaxCtx = 150000,
    [int]$MaxWt = 0,          # лимит worktree задач; 0 — из .claude\dispatch\wt-config.json (по умолчанию 4)
    [string]$Prompts = "C:\Users\volin\.config\atlas\prompts.ps1",
    [string]$Task = "",
    [int]$HoldSec = 150,           # сколько держать новый промпт ради склейки с поправками
    [double]$BudgetSonnet = 1.5,   # $ на задачу: sonnet по истории 0.05–0.85
    [double]$BudgetOpus = 6,       # opus по истории 0.3–5.5 (90% ниже 5.5)
    [double]$BudgetOpusX = 12,     # opus xhigh/max (сеть на много файлов — до 12.3)
    [switch]$DryRun,
    [string]$TestPrompts = "",
    [int]$DrySec = 25,             # сухой прогон: сколько «работает» воркер
    [switch]$Plain                 # без живой таблицы: строки лога в stdout (для сухих прогонов)
)
$ErrorActionPreference = "Continue"
# Основная копия (а не worktree, из которого запущен скрипт) — там .claude\dispatch и .claude\worktrees.
if (-not $Repo) { $Repo = Split-Path -Parent (Resolve-Path (& git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir)).Path }
$WtJs = Join-Path $PSScriptRoot "wt.js"
if ($MaxWt -gt 0) { $env:WT_MAX = "$MaxWt" }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Utf8 = New-Object Text.UTF8Encoding $false
$OutputEncoding = $Utf8
$Claude = (Get-Command claude -ErrorAction Stop).Source
$Dir = Join-Path $Repo $(if ($DryRun) { ".claude\dispatch-dry" } else { ".claude\dispatch" })
if ($DryRun) { Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue }
$Wts = Join-Path $Repo ".claude\worktrees"
$Inbox = Join-Path $Dir "inbox"
$HandoffDir = Join-Path $Dir "handoff"
New-Item -ItemType Directory -Force $Dir, $Wts, $Inbox, $HandoffDir | Out-Null
$StateFile = Join-Path $Dir "state.json"
$JobsFile = Join-Path $Dir "jobs.json"
$HistFile = Join-Path $Dir "history.jsonl"   # все завершённые задачи и переделки — для статистики качества по моделям
$LogFile = Join-Path $Dir "dispatch.log"
$FlagFile = Join-Path $Dir "stop.flag"
$HooksFile = Join-Path $Dir "hooks.json"
$StatusFile = Join-Path $Dir "status.md"    # статусы для Германа (в TG отправить нельзя — ключ только на чтение)
$SmokeFile = Join-Path $Dir "smoke.json"    # последний зелёный main и очередь проверок
$GitBash = Join-Path (Split-Path (Split-Path (Split-Path (& git --exec-path)))) "bin\bash.exe"   # не WSL-ный bash
$Zones = "slot","shop","items","weapons","player","enemy","controls","ui","net","level","car","village","lake","city","world","core","other"
$ProbeOnly = $false     # после паузы по лимиту — сначала одна задача, остальные после её успеха
$HoldUntil = $null      # лимит сессии Claude — до этого времени новые воркеры не стартуют
$WtRetryAt = Get-Date   # worktree не создался (лимит/место) — следующая попытка не раньше
$WtWhy = ""
function Limit-Hit([string]$s) { $s -match '(?i)hit your (session|usage|weekly) limit|usage limit reached|limit .{0,3}resets' }

# Хук воркеров: после каждого инструмента проверяет stop.flag (мягкая остановка) — см. stop-hook.js.
$hookCmd = 'node "{0}" "{1}"' -f (Join-Path $PSScriptRoot "stop-hook.js"), $Dir
# Минимальный стартовый контекст воркеров (~6k вместо ~11k): без CLAUDE.md (всё нужное — в AGENTS.md),
# без авто-памяти, без git-инструкций (отправка — ship.sh), без списка skills (--disable-slash-commands), без MCP.
$env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1"
$hooks = @{
    includeGitInstructions = $false; autoMemoryEnabled = $false; claudeMdExcludes = @("**/CLAUDE.md")
    hooks = @{ PostToolUse = @(@{ matcher = "*"; hooks = @(@{ type = "command"; command = $hookCmd }) }) }
}
[IO.File]::WriteAllText($HooksFile, ($hooks | ConvertTo-Json -Depth 8), $Utf8)

function Log([string]$s) {
    $l = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm:ss"), $s
    [IO.File]::AppendAllText($LogFile, $l + "`n", $Utf8)
    [void]$LogTail.Add($l); while ($LogTail.Count -gt 8) { $LogTail.RemoveAt(0) }
    if ($Plain) { Write-Host $l }
    $script:Dirty = $true
}

# Статус для Германа: status.md (новые сверху, 300 строк) + notes в jobs.json (TUI) + лог.
# В TG не уходит: ключ atlas — scopes ["comms:read space=games/prompts"]; для отправки нужен ключ с правом записи.
function Status([string]$s) {
    $l = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm"), $s
    $old = @(); if (Test-Path $StatusFile) { $old = @([IO.File]::ReadAllLines($StatusFile, $Utf8) | Where-Object { $_ -and $_ -notmatch '^#' }) }
    $head = "# Статусы диспетчера (новые сверху). В Telegram не отправляются: ключ atlas только на чтение."
    [IO.File]::WriteAllLines($StatusFile, [string[]](@($head, $l) + @($old | Select-Object -First 300)), $Utf8)
    [void]$Notes.Add($l); while ($Notes.Count -gt 30) { $Notes.RemoveAt(0) }
    Log "СТАТУС: $s"
}

# Сводка раз в час: промпты, готово, переделки, сбои, очередь, $.
function Hour-Summary {
    $since = (Get-Date).AddMinutes(-60)
    $fin = @($Jobs | Where-Object { $_.finished -and [DateTime]$_.finished -ge $since })
    $ok = @($fin | Where-Object { $_.status -eq "готово" }).Count
    $bad = @($fin | Where-Object { $_.status -in "упал", "ошибка", "бюджет", "СЛОЖНО" }).Count
    $redo = @($fin | Where-Object { $_.fix_of }).Count
    $sm = @($fin | Where-Object { $_.smoke -eq "упал" }).Count
    $cost = 0.0; foreach ($q in $fin) { $cost += [double]$q.cost }
    $qd = @($Jobs | Where-Object { $_.status -eq "очередь" }); $rn = @($Jobs | Where-Object { $_.status -eq "работает" }).Count
    if (-not ($script:Prompts1h + $fin.Count + $qd.Count + $rn)) { return }
    $zones = ($qd | Group-Object zone | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ", "
    Status ("сводка за час: промптов {0}, готово {1}, переделок {2}, сбоев {3}, smoke✗ {4}, работают {5}, в очереди {6}{7}, `${8:N2}" -f `
        $script:Prompts1h, $ok, $redo, $bad, $sm, $rn, $qd.Count, $(if ($zones) { " ($zones)" } else { "" }), $cost)
    $script:Prompts1h = 0
}

function Cut([string]$s, [int]$n) { $s = ($s -replace '[\r\n\t]+', ' ').TrimEnd(); if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + "…" } else { $s } }
function Stop-Mode { if (Test-Path $FlagFile) { ([IO.File]::ReadAllText($FlagFile)).Trim() } else { "" } }
function Dur($q) {
    if (-not $q.started) { return "" }
    $end = if ($q.finished) { [DateTime]$q.finished } else { Get-Date }
    "{0:mm\:ss}" -f ($end - [DateTime]$q.started)
}

# Живая таблица в консоли (подробный вид — в TUI).
function Show {
    $w = [Math]::Max(80, [Console]::WindowWidth - 1)
    $o = New-Object System.Collections.Generic.List[string]
    $run = @($Jobs | Where-Object { $_.status -eq "работает" }).Count
    $que = @($Jobs | Where-Object { $_.status -eq "очередь" }).Count
    $sm = Stop-Mode
    $wait = if ($Task) { "" } elseif ($sm) { "СТОП ($sm) — новые задачи не стартуют" } elseif ($HoldUntil) { "ЛИМИТ Claude — пауза до $($HoldUntil.ToString('HH:mm'))" } elseif ($job) { "слушаю TG…" } else { "" }
    if ($WtWhy -and $que) { $wait += "   worktree: $WtWhy" }
    if ($Smoke.proc) { $wait += "   smoke: $($Smoke.phase) $(Short $Smoke.sha)" } elseif ($SmokeSt.last) { $wait += "   smoke: $($SmokeSt.last)" }
    $o.Add(("ДИСПЕТЧЕР  {0}   работают: {1}   в очереди: {2}   {3}" -f (Get-Date -Format "HH:mm:ss"), $run, $que, $wait))
    $o.Add((Cut ("КАЧЕСТВО  " + (Stats-Line)) $w))
    $o.Add("")
    $o.Add(("{0,-3} {1,-11} {2,-8} {3,-13} {4,-4} {5,-9} {6,6} {7,5} {8,6}  {9}" -f "#", "промпт", "зона", "модель", "реж", "статус", "время", "ктх", "`$", "задача / результат"))
    foreach ($q in @($Jobs | Select-Object -Last 15)) {
        $ctx = if ($q.ctx) { "{0}k" -f [int]($q.ctx / 1000) } else { "" }
        $cost = if ($q.cost) { "{0:N2}" -f $q.cost } else { "" }
        $info = if ($q.result) { $q.title + "  ->  " + $q.result } else { $q.title }
        $line = "{0,-3} {1,-11} {2,-8} {3,-13} {4,-4} {5,-9} {6,6} {7,5} {8,6}  {9}" -f $q.id, $q.at, $q.zone, (Who $q), $(if ($q.mode -eq "continue") { "прод" } else { "нов" }), $q.status, (Dur $q), $ctx, $cost, $info
        $o.Add((Cut $line $w))
    }
    $o.Add("")
    $o.Add("СТАТУСЫ (для Германа, .claude\dispatch\status.md):")
    foreach ($l in @($Notes | Select-Object -Last 6)) { $o.Add((Cut ("  " + $l) $w)) }
    $o.Add("")
    $o.Add("ЛОГ:")
    foreach ($l in $LogTail) { $o.Add((Cut ("  " + $l) $w)) }
    $o.Add("")
    $o.Add("Ctrl+C — перестать слушать (воркеры продолжат).  Стоп: scripts\dispatch\ctl.ps1 stop | kill | resume")
    Clear-Host
    foreach ($l in $o) { Write-Host $l }
    $script:Dirty = $false
    $script:LastShow = Get-Date
}
# «opus/high» — модель воркера и уровень размышлений.
function Who($q) { if ($q.effort) { "$($q.agent)/$($q.effort)" } else { "$($q.agent)" } }
$Efforts = "low", "medium", "high", "xhigh", "max"
function Norm-Agent([string]$a) { switch ($a) { "gd-worker" { "opus" } "gd-quick" { "sonnet" } default { $a } } }
function Run-Git { & git @args *> $null }

function Load-Map([string]$file) {
    $s = @{}
    if (Test-Path $file) {
        $o = [IO.File]::ReadAllText($file, $Utf8) | ConvertFrom-Json
        foreach ($p in $o.PSObject.Properties) { $h = @{}; foreach ($q in $p.Value.PSObject.Properties) { $h[$q.Name] = $q.Value }; $s[$p.Name] = $h }
    }
    $s
}
function Save-State { [IO.File]::WriteAllText($StateFile, ($State | ConvertTo-Json -Depth 5), $Utf8) }

# jobs.json — вся очередь/история/работающие воркеры + пульс диспетчера; читает TUI.
function Load-Hist {
    $l = New-Object System.Collections.ArrayList
    if (Test-Path $HistFile) { foreach ($x in [IO.File]::ReadAllLines($HistFile, $Utf8)) { if ($x.Trim()) { try { [void]$l.Add(($x | ConvertFrom-Json)) } catch {} } } }
    ,$l
}
function Hist-Add($h) {
    $o = [pscustomobject]$h
    [IO.File]::AppendAllText($HistFile, (ConvertTo-Json -InputObject $o -Compress -Depth 4) + "`n", $Utf8)
    [void]$Hist.Add($o); Calc-Stats
}
# Статистика по моделям: задач, переделок (Герман пожаловался на результат), СЛОЖНО, $ на задачи и $ на переделки.
function Calc-Stats {
    $done = @($Hist | Where-Object { $_.t -eq "done" })
    $byId = @{}; foreach ($d in $done) { $byId["$($d.id)"] = $d }
    $redone = @{}; foreach ($r in @($Hist | Where-Object { $_.t -eq "redo" })) { $redone["$($r.id)"] = $true }
    $st = [ordered]@{}
    foreach ($m in "sonnet", "opus") {
        $mine = @($done | Where-Object { $_.agent -eq $m })
        $redo = @($mine | Where-Object { $redone["$($_.id)"] }).Count
        $fix = 0.0; foreach ($d in $done) { if ($d.fix_of -and $byId["$($d.fix_of)"] -and $byId["$($d.fix_of)"].agent -eq $m) { $fix += [double]$d.cost } }
        $cost = 0.0; foreach ($d in $mine) { $cost += [double]$d.cost }
        $st[$m] = [ordered]@{
            tasks = $mine.Count; redo = $redo; pct = $(if ($mine.Count) { [int](100 * $redo / $mine.Count) } else { 0 })
            hard = @($mine | Where-Object { $_.status -eq "СЛОЖНО" }).Count; cost = [Math]::Round($cost, 2); fixcost = [Math]::Round($fix, 2)
            smoke = @($Hist | Where-Object { $_.t -eq "smoke" -and -not $_.ok -and $_.agent -eq $m }).Count
            budget = @($mine | Where-Object { $_.status -eq "бюджет" }).Count
        }
    }
    $script:Stats = $st
}
function Stats-Line {
    (@(foreach ($m in $Stats.Keys) { $x = $Stats[$m]
        "{0}: {1} задач, {2} переделок ({3}%){4}, smoke✗ {7}, бюджет✗ {8}, `${5:N2} + `${6:N2} на переделки" -f $m, $x.tasks, $x.redo, $x.pct, $(if ($m -eq "sonnet") { ", СЛОЖНО $($x.hard)" } else { "" }), $x.cost, $x.fixcost, $x.smoke, $x.budget
    }) -join "   ·   ")
}

function Save-Jobs {
    $keep = @($Jobs | Select-Object -Last 40)
    $script:Jobs = New-Object System.Collections.ArrayList; foreach ($q in $keep) { [void]$Jobs.Add($q) }
    $now = Get-Date
    $rows = foreach ($q in $Jobs) {
        $c = $q.Clone(); $c.dur = Dur $q
        if ($q.status -eq "очередь" -and $q.hold_until) { $h = [DateTime]$q.hold_until; $c.held = $now -lt $h; $c.hold = $h.ToString("HH:mm:ss") }
        $c
    }
    $o = [ordered]@{
        heartbeat = [DateTimeOffset]::Now.ToUnixTimeSeconds(); pid = $PID; listening = [bool]$job; stop = (Stop-Mode)
        seq = $Seq; stats = $Stats; jobs = @($rows); notes = @($Notes); dry = [bool]$DryRun
        smoke = [ordered]@{ busy = [bool]$Smoke.proc; phase = $Smoke.phase; sha = $Smoke.sha; pending = @($SmokeQ).Count; green = $SmokeSt.green; last = $SmokeSt.last }
    }
    $tmp = "$JobsFile.tmp"
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $o -Depth 6), $Utf8)
    try { Move-Item -Force $tmp $JobsFile -ErrorAction Stop } catch { Copy-Item -Force $tmp $JobsFile }
}
function Load-Jobs {
    $l = New-Object System.Collections.ArrayList
    if (-not (Test-Path $JobsFile)) { return ,$l }
    try { $o = [IO.File]::ReadAllText($JobsFile, $Utf8) | ConvertFrom-Json } catch { return ,$l }
    $script:Seq = [int]$o.seq
    foreach ($j in @($o.jobs)) { $h = @{}; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value }; [void]$l.Add($h) }
    ,$l
}

function Proj-Dir([string]$wt) { Join-Path $env:USERPROFILE (".claude\projects\" + ($wt -replace '[^A-Za-z0-9]', '-')) }
# Размер контекста сессии воркера — по последнему ответу в её транскрипте.
function Get-Ctx([string]$wt, [string]$sid) {
    $f = Join-Path (Proj-Dir $wt) "$sid.jsonl"
    if (-not (Test-Path $f)) { return 0 }
    $line = Get-Content $f -Tail 80 -Encoding UTF8 | Where-Object { $_ -match '"cache_read_input_tokens"' } | Select-Object -Last 1
    if (-not $line) { return 0 }
    try { $u = ($line | ConvertFrom-Json).message.usage; return [int]($u.input_tokens + $u.cache_read_input_tokens + $u.cache_creation_input_tokens) } catch { return 0 }
}
# Сессия работающего воркера — самый свежий транскрипт в его worktree, начатый после старта.
function Find-Sid($q) {
    $d = Proj-Dir $q.wt
    if (-not (Test-Path $d)) { return $null }
    $f = Get-ChildItem $d -Filter *.jsonl | Where-Object { $_.LastWriteTime -ge ([DateTime]$q.started).AddSeconds(-5) } | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($f) { $f.BaseName } else { $null }
}

# Последние задачи для роутера — чтобы он узнал жалобу на одну из них («не работает», «верни как было»).
function Recent-Tasks {
    $l = @($Hist | Where-Object { $_.t -eq "done" } | Select-Object -Last 12 | ForEach-Object { "- #{0} {1} [{2}] {3}: {4}" -f $_.id, $_.at, $_.zone, $_.agent, $_.title })
    $l += @($Jobs | Where-Object { $_.status -in "работает", "очередь" } | ForEach-Object { "- #{0} {1} [{2}] {3}: {4} (ещё делается)" -f $_.id, $_.at, $_.zone, $_.agent, $_.title })
    if ($l.Count) { $l -join "`n" } else { "(задач ещё не было)" }
}

function Route([string]$text) {
    $lines = foreach ($z in $State.Keys) {
        $w = $State[$z]; "- {0}: {1}/{5}, контекст ~{2}k, последняя задача {3}: {4}" -f $z, $w.agent, [int]($w.ctx / 1000), $w.at, $w.last, $w.effort
    }
    if (-not $lines) { $lines = "(агентов ещё нет)" }
    $p = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "router.md"), $Utf8).Replace("{{STATE}}", ($lines -join "`n")).Replace("{{RECENT}}", (Recent-Tasks)).Replace("{{TASK}}", $text)
    $out = $p | & $Claude -p --model sonnet --effort low --output-format text --tools Read --strict-mcp-config --no-session-persistence --disable-slash-commands --settings $HooksFile 2>$null | Out-String
    $items = @()
    if ($out -match '\[[\s\S]*\]') { try { $j = $matches[0] | ConvertFrom-Json; $items = @($j) } catch {} }
    if (-not $items.Count -and $out -match '\{[\s\S]*?\}') { try { $j = $matches[0] | ConvertFrom-Json; $items = @($j) } catch {} }
    if (-not $items.Count) {
        Log "роутер не ответил JSON ($(Cut $out 200)) — беру opus/high/other/new"
        $items = @([pscustomobject]@{ zone = "other"; agent = "opus"; effort = "high"; mode = "new"; title = (Cut $text 60); part = "" })
    }
    $items = @(foreach ($r in $items) { Fix-Route $r $text })
    # Несколько задач в одной зоне — одному воркеру (иначе он дважды читает те же файлы).
    $res = foreach ($g in ($items | Group-Object zone)) {
        $rs = @($g.Group)
        if ($rs.Count -eq 1) { $rs[0]; continue }
        $m = [pscustomobject]@{
            zone = $g.Name; agent = $(if (@($rs.agent) -contains "opus") { "opus" } else { "sonnet" })
            effort = ($Efforts | Where-Object { @($rs.effort) -contains $_ } | Select-Object -Last 1)
            mode = $(if (@($rs | Where-Object { $_.mode -ne "continue" }).Count) { "new" } else { "continue" })
            title = (Cut ((@($rs.title)) -join "; ") 60); part = ((@($rs.part) | Where-Object { $_ }) -join "`n")
            redo = (@($rs.redo) | Where-Object { $_ } | Select-Object -First 1)
            refines = (@($rs.refines) | Where-Object { $_ } | Select-Object -First 1)
        }
        Fix-Route $m $text
    }
    $res
}

function Fix-Route($r, [string]$text) {
    foreach ($k in "zone", "agent", "effort", "mode", "title", "part", "redo", "refines") { if (-not ($r.PSObject.Properties.Name -contains $k)) { $r | Add-Member -Force $k "" } }
    if ($Zones -notcontains $r.zone) { $r.zone = "other" }
    $r.agent = Norm-Agent $r.agent
    if ("sonnet", "opus" -notcontains $r.agent) { $r.agent = "opus" }
    if ($Efforts -notcontains $r.effort) { $r.effort = $(if ($r.agent -eq "sonnet") { "medium" } else { "high" }) }
    if (-not $r.title) { $r.title = Cut $(if ($r.part) { $r.part } else { $text }) 60 }
    $w = $State[$r.zone]
    if ($r.mode -ne "continue" -or -not $w -or -not $w.session -or $w.ctx -ge $MaxCtx -or (Norm-Agent $w.agent) -ne $r.agent) { $r.mode = "new" }
    # Уточнение или жалоба к задаче, которая ещё работает/ждёт: та же зона и модель, продолжение её сессии.
    $ref = 0; foreach ($v in $r.refines, $r.redo) { if (-not $ref -and "$v" -match '^\s*#?(\d+)\s*$') { $ref = [int]$matches[1] } }
    $live = if ($ref) { $Jobs | Where-Object { $_.id -eq $ref -and $_.status -in "работает", "очередь" } | Select-Object -First 1 }
    if ($live) {
        $r.zone = $live.zone; $r.agent = Norm-Agent $live.agent; $r.mode = "continue"
        # ещё не началась — склейка с ней (у неё тот же cont_of); работает — продолжение её сессии после неё
        $r | Add-Member -Force cont_of $(if ($live.status -eq "очередь") { $live.cont_of } else { $live.id })
        if ("$($r.redo)" -match '\d') { $r | Add-Member -Force complaint $live.id }   # жалоба на ещё не сданную задачу — учёт по цепочке
        $r.redo = $null
    }
    $r
}

function Enqueue($zone, $agent, $effort, $mode, $text, $at, $title) {
    $script:Seq++
    $q = @{ id = $script:Seq; zone = $zone; agent = $agent; effort = $effort; mode = $mode; text = $text; at = $at; title = $title; status = "очередь"
        created = (Get-Date).ToString("o") }
    [void]$Jobs.Add($q); $script:Dirty = $true; Save-Jobs
    $q
}
# Лимит $ на задачу по модели и уровню.
function Budget($q) { if ($q.agent -eq "sonnet") { $BudgetSonnet } elseif ($q.effort -in "xhigh", "max") { $BudgetOpusX } else { $BudgetOpus } }
# Повторная жалоба: один прогон игры со скриншотом (в остальных задачах скриншоты запрещены правилами агента).
$ShotRule = "ИСКЛЮЧЕНИЕ для этой задачи: Герман жалуется на это уже повторно — ОДИН раз разрешено запустить игру и посмотреть скриншот " +
    "нужного места: окно за экраном, кадры пишет сам Godot, например " +
    "`godot --path `"godot/THE LEAK`" --position -4000,-4000 --resolution 1280x720 --fixed-fps 10 --write-movie `"`$TEMP/shot.png`" --quit-after 300` " +
    "(кадры shot00000NNN.png — смотри последний через Read; нужное место — через чит/сцену). Больше одного прогона не делай."

# wt.js: create -> путь (код 3 — лимит занят, задача ждёт в очереди), release — удалить после задачи, reap — очистка.
function Wt { $o = & node $WtJs @args 2>$null; $script:WtCode = $LASTEXITCODE; ($o | Select-Object -Last 1) }
function Start-Worker($q) {
    $zone = $q.zone
    if ($DryRun) { return (Start-DryWorker $q) }
    $wa = @("create", "disp-$zone"); if ($q.text -match '(?i)blender|блендер|\.blend\b') { $wa += "--blender" }
    $wt = Wt @wa
    if ($WtCode -ne 0 -or -not $wt -or -not (Test-Path (Join-Path $wt ".git"))) {
        # Лимит worktree, нет места или git упал — задача не падает, ждёт в очереди; повтор через 30 с (при ошибке — 2 мин).
        $why = if ($WtCode -eq 3) { "$wt" -replace '^ждёт:\s*', '' } else { "не создан disp-$zone ($wt)" }
        $script:WtRetryAt = (Get-Date).AddSeconds($(if ($WtCode -eq 3 -and $why -match '^заняты') { 30 } else { 120 }))
        $script:WtWhy = $why; $script:WtCode = 3
        $key = $why -replace '[\d.,]+', '#'   # одна причина с другими цифрами — не спамить лог
        if ($q.waitwt -ne $key) { $q.waitwt = $key; Log "[$zone] ждёт worktree: $why" }
        return
    }
    $q.waitwt = $null; $script:WtWhy = ""
    Run-Git -C $wt rebase --abort
    Run-Git -C $wt fetch -q origin main
    Run-Git -C $wt rebase -q --autostash origin/main
    # Свежая карта кода (файл:строка функция — описание): агент ищет по ней, а не листает код.
    try { & python (Join-Path $wt "scripts\codemap.py") (Join-Path $wt "godot\THE LEAK") *> $null } catch {}
    # С чего начали (для поиска своих пушей) и список своих пушей от ship.sh — с нуля.
    $q.base = (& git -C $wt rev-parse HEAD 2>$null | Select-Object -First 1)
    $shipped = (& git -C $wt rev-parse --path-format=absolute --git-path shipped 2>$null | Select-Object -First 1)
    if ($shipped) { Remove-Item -Force $shipped -ErrorAction SilentlyContinue }
    $brief = Make-Brief $q
    $in = Join-Path $Dir "$zone.in.txt"; $out = Join-Path $Dir "$zone.out.json"; $err = Join-Path $Dir "$zone.err.txt"
    [IO.File]::WriteAllText($in, $brief, $Utf8)
    $q.agent = Norm-Agent $q.agent
    $a = @("-p", "--agent", $q.agent, "--output-format", "json", "--permission-mode", "bypassPermissions", "--strict-mcp-config", "--disable-slash-commands", "--settings", "`"$HooksFile`"")
    $sid = Pick-Sid $q
    if ($q.effort) { $a += @("--effort", $q.effort) }
    if ($sid) { $a += @("--resume", $sid) }
    $q.budget = Budget $q; $a += @("--max-budget-usd", ("{0}" -f $q.budget).Replace(",", "."))
    # Скрытое отдельное окно: воркер не привязан к консоли диспетчера и переживает его закрытие.
    $proc = Start-Process -FilePath $Claude -ArgumentList $a -WorkingDirectory $wt -WindowStyle Hidden -PassThru `
        -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err
    $q.pid = $proc.Id; $q.pstart = $proc.StartTime.ToString("o"); $q.wt = $wt; $q.out = $out; $q.err = $err
    $q.status = "работает"; $q.started = (Get-Date).ToString("o"); $q.finished = $null; $q.session = $sid
    $Procs[$q.id] = $proc
    Save-Jobs
    Log ("[{0}] {1} {2}: {3}" -f $zone, (Who $q), $(if ($q.resume) { "возобновляет" } elseif ($q.mode -eq "continue") { "продолжает" } else { "новый" }), $q.title)
}
# Сессия, которую продолжает задача: своя (лимит/стоп), задачи-родителя (уточнение, smoke), последняя в зоне.
function Pick-Sid($q) {
    if ($q.resume -and $q.session) { return $q.session }
    if ($q.cont_of) { $p = $Jobs | Where-Object { $_.id -eq $q.cont_of } | Select-Object -First 1; if ($p -and $p.session) { return $p.session } }
    if ($q.mode -eq "continue" -and $State[$q.zone]) { return $State[$q.zone].session }
    $null
}
function Make-Brief($q) {
    $zone = $q.zone
    $b = if ($q.resume) {
        "Работу остановили ($($q.resume)). Продолжай свою задачу с того места, где остановился." +
        $(if (Test-Path (Join-Path $HandoffDir "$zone.md")) { " Твой handoff: $(Join-Path $HandoffDir "$zone.md")" } else { "" })
    } elseif ($q.smoke_of) {
        $q.text
    } elseif ($q.cont_of) {
        "Герман уточнил задачу #$($q.cont_of), которую ты только что делал ($($q.at)). Доделай по уточнению (оно главнее прошлого текста):`n$($q.text)"
    } elseif ($q.mode -eq "continue") {
        "Новый промпт Германа ($($q.at)), продолжение твоей работы:`n$($q.text)"
    } else {
        "Время промпта: $($q.at). Задача Германа:`n$($q.text)"
    }
    if ($q.shot) { $b += "`n`n$ShotRule" }
    $b
}
function Alive($q) {
    $p = $Procs[$q.id]
    if (-not $p) {
        try { $p = Get-Process -Id $q.pid -ErrorAction Stop } catch { return $false }
        if ($q.pstart -and [Math]::Abs(($p.StartTime - [DateTime]$q.pstart).TotalSeconds) -gt 2) { return $false }
        $Procs[$q.id] = $p
    }
    try { $p.Refresh() } catch {}
    -not $p.HasExited
}

# Задача кончилась — worktree удаляется, если чистый и запушен; иначе остаётся (причина в логе от wt.js).
function Release-Wt($q) { if ($q.wt -and -not $DryRun) { [void](Wt release $q.wt) } }
# Свои пуши воркера: ship.sh дописывает хеш каждого отправленного коммита в <gitdir>\shipped.
function Get-Pushed($q) {
    if ($DryRun) { return @($q.dryc | Where-Object { $_ }) }
    if (-not $q.wt -or -not (Test-Path $q.wt)) { return @() }
    $f = (& git -C $q.wt rev-parse --path-format=absolute --git-path shipped 2>$null | Select-Object -First 1)
    if (-not $f -or -not (Test-Path $f)) { return @() }
    @([IO.File]::ReadAllLines($f) | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9a-f]{40}$' })
}
# «Что проверить» для Германа — раздел ANSWER.md, который записал этот коммит (заголовок «## ЧЧ:ММ — <сообщение коммита>»).
function Get-Answer($q, [string]$sha) {
    if ($DryRun -or -not $sha) { return "" }
    $subj = (& git -C $Repo log -1 --format=%s $sha 2>$null | Select-Object -First 1)
    $lines = @(& git -C $Repo show "${sha}:ANSWER.md" 2>$null)
    $on = $false; $b = @()
    foreach ($l in $lines) {
        if ($l -match '^## ') { if ($on) { break }; $on = $subj -and $l.Contains($subj); continue }
        if ($on -and $l.Trim()) { $b += $l.Trim() }
    }
    ($b -join " ")
}
function Finish($q) {
    $Procs.Remove($q.id); $zone = $q.zone
    $q.finished = (Get-Date).ToString("o")
    $j = $null
    if ($DryRun) { $j = Dry-Result $q } else { try { $j = [IO.File]::ReadAllText($q.out, $Utf8) | ConvertFrom-Json } catch {} }
    if (-not $j) {
        $e = ""; try { $e = ([IO.File]::ReadAllText($q.err, $Utf8) -replace '\s+', ' ').Trim() } catch {}
        if (-not $q.session) { $q.session = Find-Sid $q }
        if ((Stop-Mode) -eq "kill") { $q.status = "прерван"; $q.result = "жёсткая остановка" ; Log "[$zone] воркер прерван (kill)" }
        elseif (Limit-Hit $e) { Requeue-Limit $q $e }
        else { $q.status = "упал"; $q.result = $e; Log "[$zone] воркер упал: $(Cut $e 300)"; Status "✗ #$($q.id) [$zone] воркер упал: $(Cut $e 200)" }
        Save-Jobs; Release-Wt $q; return
    }
    $res = "$($j.result)".Trim()
    if ($j.is_error -and (Limit-Hit $res)) {
        if ($j.session_id) { $q.session = $j.session_id }
        $q.cost = $j.total_cost_usd; Requeue-Limit $q $res; Save-Jobs; Release-Wt $q; return
    }
    $ctx = if ($DryRun) { 0 } else { Get-Ctx $q.wt $j.session_id }
    $q.session = $j.session_id; $q.ctx = $ctx; $q.cost = $j.total_cost_usd; $q.result = (($res -split "`n")[0])
    $hf = Join-Path $HandoffDir "$zone.md"
    $handoff = (Test-Path $hf) -and ((Get-Item $hf).LastWriteTime -ge [DateTime]$q.started)
    # --max-budget-usd кончился: claude отвечает is_error с subtype error_max_budget_usd
    $budget = $j.is_error -and ("$($j.subtype)" -match '(?i)budget' -or $res -match '(?i)budget')
    $q.status = if ($budget) { "бюджет" } elseif ($j.is_error) { "ошибка" } elseif ($res -match '^\s*СЛОЖНО') { "СЛОЖНО" } elseif ($handoff -and (Stop-Mode)) { "пауза" } else { "готово" }
    $pushed = @(Get-Pushed $q)
    if ($pushed.Count) { $q.commits = $pushed; $q.smoke = "ждёт" }
    $answer = if ($pushed.Count) { Get-Answer $q $pushed[-1] } else { "" }
    $script:ProbeOnly = $false
    $State[$zone] = @{ session = $j.session_id; agent = $q.agent; effort = $q.effort; ctx = $ctx; last = $q.title; at = $q.at }
    if ($q.status -ne "пауза") {
        Hist-Add @{ t = "done"; id = $q.id; at = $q.at; zone = $zone; agent = $q.agent; effort = $q.effort; cost = [double]$j.total_cost_usd; status = $q.status
            fix_of = $q.fix_of; title = $q.title; ctx = $ctx; budget = $q.budget; created = $q.created; started = $q.started; finished = $q.finished
            pushed = $pushed.Count; commits = @($pushed); merged = [int]$q.merged; cont_of = $q.cont_of; smoke_of = $q.smoke_of; shot = [bool]$q.shot }
    }
    Save-State; Save-Jobs; Release-Wt $q
    Log ("[{0}] {1}, ~{2}k, `${3:N2}: {4}" -f $zone, $q.status, [int]($ctx / 1000), $j.total_cost_usd, (($res -split "`n")[0]))
    if ($q.status -eq "готово" -and $pushed.Count) {
        [void]$SmokeQ.Add($q.id); Save-Smoke
        Status ("✓ готово #{0} [{1}] {2} — проверь: {3}" -f $q.id, $zone, $q.title, $(if ($answer) { Cut $answer 400 } else { Cut $q.result 300 }))
    } elseif ($q.status -eq "готово") {
        Status ("готово #{0} [{1}] {2}, но пуша нет: {3}" -f $q.id, $zone, $q.title, (Cut $q.result 200))
    } elseif ($budget) {
        Status ("⚠ #{0} [{1}] остановлен по лимиту `${2} на задачу (потрачено `${3:N2}): {4}. Продолжить — промпт «продолжи»" -f $q.id, $zone, $q.budget, [double]$j.total_cost_usd, $q.title)
    } elseif ($q.status -eq "ошибка") {
        Status ("✗ #{0} [{1}] ошибка: {2}" -f $q.id, $zone, (Cut $q.result 200))
    }
    # ship.sh вернул «конфликт в коде», а воркер не переделал сам — один раз отдаём ему же переделку на свежем main.
    if (-not $pushed.Count -and $res -match 'КОНФЛИКТ В КОДЕ' -and -not $q.conflict_of) {
        $n = Enqueue $zone $q.agent $q.effort "continue" ("ship.sh: конфликт в коде со свежим main, ничего не отправлено. Переделай задачу на свежем main " +
            "(git fetch -q origin main && git reset -q --hard origin/main, правки заново по свежему коду), маркеры конфликта не править. Задача была:`n" + $q.text) $q.at $q.title
        $n.cont_of = $q.id; $n.conflict_of = $q.id; Save-Jobs
        Log "[$zone] #$($q.id) упёрся в конфликт — #$($n.id) переделка на свежем main"
    }
    if ($q.agent -eq "sonnet" -and $res -match '^\s*СЛОЖНО') {
        Log "[$zone] sonnet не справился — отдаю opus/high"
        $n = Enqueue $zone "opus" "high" "new" $q.text $q.at $q.title; $n.fix_of = $q.fix_of; $n.shot = $q.shot
    }
}

# ---- проверка после пуша: scripts/smoke.sh на свежем main, по очереди, с бисектом виновного коммита ----
function Save-Smoke {
    $o = [ordered]@{ green = $SmokeSt.green; last = $SmokeSt.last; queue = @($SmokeQ) }
    [IO.File]::WriteAllText($SmokeFile, (ConvertTo-Json -InputObject $o -Depth 4), $Utf8)
}
function Short([string]$sha) { if ($sha.Length -gt 9) { $sha.Substring(0, 9) } else { $sha } }
function Main-Head {
    if ($DryRun) { return $DryChain[$DryChain.Count - 1] }
    Run-Git -C $Repo fetch -q origin main
    (& git -C $Repo rev-parse origin/main | Select-Object -First 1)
}
# Коммиты (g, m] по первому родителю, старые первыми.
function Chain([string]$g, [string]$m) {
    if ($DryRun) {
        $i = if ($g) { $DryChain.IndexOf($g) } else { -1 }; $k = $DryChain.IndexOf($m)
        if ($i + 1 -gt $k) { return @() }; return @($DryChain[($i + 1)..$k])
    }
    $range = if ($g) { "$g..$m" } else { $m }
    @(& git -C $Repo rev-list --reverse --first-parent $range 2>$null)
}
function Parent-Of([string]$sha) {
    if ($DryRun) { $i = $DryChain.IndexOf($sha); if ($i -gt 0) { return $DryChain[$i - 1] } else { return "" } }
    (& git -C $Repo rev-parse "$sha~1" 2>$null | Select-Object -First 1)
}
function Order-Of([string]$sha) { if ($DryRun) { $DryChain.IndexOf($sha) } else { [int](& git -C $Repo rev-list --count $sha 2>$null | Select-Object -First 1) } }
function Smoke-Run([string]$sha) {
    $o = Join-Path $Dir "smoke.out.txt"; Remove-Item -Force $o, "$o.err" -ErrorAction SilentlyContinue
    if ($DryRun) {
        $bad = if (Dry-IsBad $sha) { 1 } else { 0 }
        $p = Start-Process powershell -ArgumentList "-NoProfile", "-Command", "Start-Sleep 3; if ($bad) { 'SCRIPT ERROR: dry-run broken at $sha'; exit 1 } else { 'OK' }" `
            -RedirectStandardOutput $o -WindowStyle Hidden -PassThru
    } else {
        if (-not $script:SmokeWt -or -not (Test-Path (Join-Path "$script:SmokeWt" ".git"))) {
            $script:SmokeWt = Wt create smoke --uncounted
            if ($WtCode -ne 0 -or -not (Test-Path (Join-Path "$SmokeWt" ".git"))) { Log "smoke: копия не создана ($SmokeWt) — проверка позже"; $script:SmokeWt = $null; return $false }
        }
        $p = Start-Process $GitBash -ArgumentList "`"$SmokeSh`"", "`"$SmokeWt`"", $sha -WindowStyle Hidden -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
    }
    $null = $p.Handle   # без этого PS 5.1 теряет ExitCode
    $Smoke.proc = $p; $Smoke.sha = $sha; $Smoke.started = Get-Date; $script:Dirty = $true
    $true
}
function Smoke-Tick {
    if ($Smoke.proc) {
        $p = $Smoke.proc; if (-not $p.HasExited) { return }
        $p.WaitForExit(); $ok = $p.ExitCode -eq 0; $Smoke.proc = $null
        $o = Join-Path $Dir "smoke.out.txt"
        $txt = ""; try { $txt = ([IO.File]::ReadAllText($o, $Utf8)).Trim() } catch {}
        if (-not $txt) { try { $txt = ([IO.File]::ReadAllText("$o.err", $Utf8)).Trim() } catch {} }
        Smoke-Step $ok $txt
        return
    }
    if (-not $SmokeQ.Count) { return }   # $SmokeWait едут только вместе с новым пушем (main ещё сломан)
    $Smoke.ids = @($SmokeQ) + @($SmokeWait); $SmokeQ.Clear(); $SmokeWait.Clear(); Save-Smoke
    $Smoke.m = Main-Head; $Smoke.phase = "main"
    Log ("smoke: проверяю свежий main {0} после #{1}" -f (Short $Smoke.m), ($Smoke.ids -join ", #"))
    if (-not (Smoke-Run $Smoke.m)) { foreach ($i in $Smoke.ids) { [void]$SmokeQ.Add($i) }; $Smoke.phase = "" }
}
function Next-Bisect { $Smoke.mid = [int][Math]::Floor(($Smoke.lo + $Smoke.hi) / 2); [void](Smoke-Run $Smoke.list[$Smoke.mid]) }
function Smoke-Step([bool]$ok, [string]$txt) {
    switch ($Smoke.phase) {
        "main" {
            $SmokeSt.last = "{0} {1} {2}" -f (Get-Date -Format "HH:mm"), (Short $Smoke.m), $(if ($ok) { "OK" } else { "УПАЛ" })
            if ($ok) { Smoke-Ok $Smoke.m; return }
            $Smoke.err = $txt
            $g = $SmokeSt.green; $Smoke.gknown = [bool]$g
            if (-not $g) {   # зелёного ещё не было — от родителя самого раннего своего коммита
                $own = @(foreach ($i in $Smoke.ids) { ($Jobs | Where-Object { $_.id -eq $i } | Select-Object -First 1).commits }) | Where-Object { $_ }
                $first = $own | Sort-Object { Order-Of $_ } | Select-Object -First 1
                $g = if ($first) { Parent-Of $first } else { "" }
            }
            $Smoke.g = $g; $Smoke.list = @(Chain $g $Smoke.m); $Smoke.lo = -1; $Smoke.hi = $Smoke.list.Count - 1
            Log ("smoke: main {0} упал — ищу виновный коммит среди {1}" -f (Short $Smoke.m), $Smoke.list.Count)
            if ($Smoke.hi -le 0) { Smoke-Found; return }
            $Smoke.phase = "bisect"; Next-Bisect
        }
        "bisect" {
            if ($ok) { $Smoke.lo = $Smoke.mid } else { $Smoke.hi = $Smoke.mid; $Smoke.err = $txt }
            if ($Smoke.hi - $Smoke.lo -gt 1) { Next-Bisect } else { Smoke-Found }
        }
        "base" {
            if ($ok) { Smoke-Blame $Smoke.list[0]; return }
            Status ("✗ smoke: main был сломан ещё до проверяемых задач (уже на {0}) — никому не возвращаю: {1}" -f (Short $Smoke.g), (Cut $Smoke.err 300))
            foreach ($i in $Smoke.ids) { $x = $Jobs | Where-Object { $_.id -eq $i } | Select-Object -First 1; if ($x) { $x.smoke = "?" } }
            $Smoke.phase = ""; Save-Jobs
        }
    }
}
function Smoke-Found {
    if ($Smoke.hi -lt 0) { Status "✗ smoke упал, но коммитов для поиска нет: $(Cut $Smoke.err 300)"; $Smoke.phase = ""; return }
    if ($Smoke.hi -eq 0 -and -not $Smoke.gknown -and $Smoke.g) { $Smoke.phase = "base"; [void](Smoke-Run $Smoke.g); return }
    Smoke-Blame $Smoke.list[$Smoke.hi]
}
function Smoke-Ok([string]$m) {
    $SmokeSt.green = $m
    foreach ($i in $Smoke.ids) {
        $x = $Jobs | Where-Object { $_.id -eq $i } | Select-Object -First 1; if (-not $x) { continue }
        $x.smoke = "OK"
        Hist-Add @{ t = "smoke"; id = $x.id; ok = $true; zone = $x.zone; agent = $x.agent; sha = $m; smoke_of = $x.smoke_of }
        if ($x.smoke_of) { Status "✓ smoke: после починки #$($x.id) игра снова грузится (задача #$($x.smoke_of))" }
    }
    Log ("smoke: OK на {0}" -f (Short $m)); $Smoke.phase = ""; Save-Smoke; Save-Jobs
}
function Smoke-Blame([string]$b) {
    $Smoke.phase = ""
    $idx = [array]::IndexOf($Smoke.list, $b)
    if ($idx -gt 0) { $SmokeSt.green = $Smoke.list[$idx - 1] } elseif ($Smoke.g) { $SmokeSt.green = $Smoke.g }
    $own = $Jobs | Where-Object { @($_.commits) -contains $b } | Select-Object -Last 1
    $err = Cut $Smoke.err 1500
    foreach ($i in $Smoke.ids) {
        $x = $Jobs | Where-Object { $_.id -eq $i } | Select-Object -First 1; if (-not $x) { continue }
        $pos = @($x.commits | ForEach-Object { [array]::IndexOf($Smoke.list, $_) })
        $x.smoke = if ($own -and $x.id -eq $own.id) { "упал" } elseif (@($pos | Where-Object { $_ -ge 0 -and $_ -lt $idx }).Count -eq $pos.Count) { "OK" } else { "?" }
    }
    if (-not $own) {
        $subj = if ($DryRun) { $b } else { (& git -C $Repo log -1 --format="%h %s" $b 2>$null | Select-Object -First 1) }
        Hist-Add @{ t = "smoke"; id = 0; ok = $false; sha = $b; foreign = $true; err = (Cut $Smoke.err 300) }
        Status ("✗ smoke: игра не грузится после коммита не от воркеров диспетчера ({0}) — никому не возвращаю: {1}" -f $subj, (Cut $Smoke.err 300))
        Save-Smoke; Save-Jobs; return
    }
    foreach ($i in $Smoke.ids) { $x = $Jobs | Where-Object { $_.id -eq $i } | Select-Object -First 1; if ($x -and $x.smoke -eq "?") { $x.smoke = "ждёт починки main"; [void]$SmokeWait.Add($i) } }
    $root = if ($own.smoke_of) { $own.smoke_of } else { $own.id }
    $fixing = $Jobs | Where-Object { $_.fix_smoke -eq $b -and $_.status -in "очередь", "работает" } | Select-Object -First 1
    if ($fixing) { Log ("smoke: {0} всё ещё сломан, починка уже идёт (#{1})" -f (Short $b), $fixing.id); Save-Smoke; Save-Jobs; return }
    Hist-Add @{ t = "smoke"; id = $own.id; ok = $false; zone = $own.zone; agent = $own.agent; sha = $b; root = $root; err = (Cut $Smoke.err 300) }
    $tries = @($Jobs | Where-Object { $_.smoke_of -eq $root }).Count
    if ($tries -ge 2) {
        Status ("✗ smoke: после #{0} [{1}] игра всё ещё не грузится, 2 починки не помогли — нужен человек: {2}" -f $root, $own.zone, (Cut $Smoke.err 300))
        Save-Smoke; Save-Jobs; return
    }
    $t = "Проверка после твоего пуша (scripts/smoke.sh на свежем main) упала, виновен твой коммит $(Short $b) (задача #$($own.id)):`n$err`n`n" +
        "Почини это продолжением своей задачи, потом снова ship.sh. Игру сам не запускай — после пуша проверка повторится автоматически.`nЗадача была:`n$($own.text)"
    $n = Enqueue $own.zone $own.agent $own.effort "continue" $t $own.at ("smoke: " + $own.title)
    $n.cont_of = $own.id; $n.smoke_of = $root; $n.fix_smoke = $b; Save-Jobs
    Status ("✗ после #{0} [{1}] игра не грузится (smoke, коммит {2}) — вернул тому же воркеру, #{3}: {4}" -f $own.id, $own.zone, (Short $b), $n.id, (Cut $Smoke.err 200))
    Save-Smoke
}

# ---- сухой прогон: воркер — пауза на -DrySec, «пуш» — фальшивый коммит в цепочке $DryChain ----
function Start-DryWorker($q) {
    $q.agent = Norm-Agent $q.agent
    [IO.File]::WriteAllText((Join-Path $Dir "$($q.zone).in.txt"), (Make-Brief $q), $Utf8)
    $sid = Pick-Sid $q; $q.budget = Budget $q
    $proc = Start-Process powershell -ArgumentList "-NoProfile", "-Command", "Start-Sleep $DrySec" -WindowStyle Hidden -PassThru
    $q.pid = $proc.Id; $q.pstart = $proc.StartTime.ToString("o"); $q.wt = $null
    $q.status = "работает"; $q.started = (Get-Date).ToString("o"); $q.finished = $null; $q.session = $sid
    $Procs[$q.id] = $proc; Save-Jobs
    Log ("[{0}] {1} {2}{3}: {4}" -f $q.zone, (Who $q), $(if ($q.cont_of) { "продолжает #$($q.cont_of)" } elseif ($q.mode -eq "continue") { "продолжает" } else { "новый" }), $(if ($sid) { " (сессия $sid)" } else { "" }), $q.title)
}
function Dry-Result($q) {
    if ($q.text -match '#budget' -and -not $q.smoke_of) {
        return [pscustomobject]@{ is_error = $true; subtype = "error_max_budget_usd"; result = ""; session_id = "dry-$($q.id)"; total_cost_usd = $q.budget }
    }
    $c = "d{0:D4}" -f $q.id; [void]$DryChain.Add($c); $q.dryc = @($c)
    if ($q.text -match '#smokefail' -and -not $q.smoke_of) { $DryBad[$c] = $true }
    if ($q.fix_smoke) { $DryFix[$c] = $q.fix_smoke }
    [pscustomobject]@{ is_error = $false; result = "$c — (сухой прогон) ничего не правил"; session_id = "dry-$($q.id)"; total_cost_usd = 0.1 }
}
function Dry-IsBad([string]$sha) {
    $k = $DryChain.IndexOf($sha); $broken = @{}
    for ($i = 0; $i -le $k; $i++) { $c = $DryChain[$i]; if ($DryBad[$c]) { $broken[$c] = $true }; if ($DryFix[$c]) { $broken.Remove($DryFix[$c]) } }
    $broken.Count -gt 0
}

# ---- промпт: роутер, склейка, уточнения, жалобы ----
$Efforts2 = @{ low = 0; medium = 1; high = 2; xhigh = 3; max = 4 }
function Zone-Line([string]$zone) {
    $qd = @($Jobs | Where-Object { $_.status -eq "очередь" -and $_.zone -eq $zone }).Count
    $rn = $Jobs | Where-Object { $_.status -eq "работает" -and $_.zone -eq $zone } | Select-Object -First 1
    "в очереди зоны $qd" + $(if ($rn) { ", сейчас работает #$($rn.id)" } else { "" })
}
function Check-Zone([string]$zone) {
    $qd = @($Jobs | Where-Object { $_.status -eq "очередь" -and $_.zone -eq $zone }).Count
    if ($qd -gt 3 -and $qd -gt [int]$ZoneWarn[$zone]) { Status "⚠ зона $zone`: в очереди $qd задач — дальше будут ждать долго" }
    $ZoneWarn[$zone] = $qd
}
# Первая задача цепочки: идём по fix_of / cont_of / smoke_of назад (задачи из jobs.json и history.jsonl).
function Root-Of([int]$id) {
    for ($k = 0; $k -lt 30; $k++) {
        $x = $Jobs | Where-Object { $_.id -eq $id } | Select-Object -Last 1
        if (-not $x) { $x = $Hist | Where-Object { $_.t -eq "done" -and $_.id -eq $id } | Select-Object -Last 1 }
        if (-not $x) { break }
        $n = 0; foreach ($v in $x.fix_of, $x.cont_of, $x.smoke_of) { if (-not $n -and "$v" -match '^\d+$') { $n = [int]$v } }
        if (-not $n -or $n -eq $id) { break }
        $id = $n
    }
    $id
}
function Merge-Into($m, $r, [string]$t, [string]$at) {
    $m.text = "$($m.text)`n`n--- Герман дописал в $at (это главнее: при противоречии делай по этому) ---`n$t"
    if ($r.agent -eq "opus") { $m.agent = "opus" }
    if ([int]$Efforts2[$r.effort] -gt [int]$Efforts2["$($m.effort)"]) { $m.effort = $r.effort }
    if ($r.mode -ne "continue" -and -not $m.cont_of) { $m.mode = "new" }
    if (-not $m.at0) { $m.at0 = $m.at }; $m.at = $at
    $m.title = Cut "$($m.title); $($r.title)" 70
    $m.merged = [int]$m.merged + 1
    if ($HoldSec -gt 0) {
        $c0 = if ($m.created) { [DateTime]$m.created } else { Get-Date }
        $cap = $c0.AddSeconds(3 * $HoldSec); $h = (Get-Date).AddSeconds($HoldSec)
        if ($h -gt $cap) { $h = $cap }; $m.hold_until = $h.ToString("o")
    }
}
function Handle([string]$raw, [string]$defAt = "?") {
    $at = ""; $body = @()
    foreach ($l in ($raw -split "`r?`n")) {
        if ($l -match '^=== (\d\d\.\d\d \d\d:\d\d) МСК') { $at = $matches[1]; continue }
        if ($l.Trim()) { $body += $l }
    }
    $text = ($body -join "`n").Trim()
    if (-not $text -or $text -eq "новых промптов нет") { return }
    if (-not $at) { $at = $defAt }
    $script:Prompts1h++
    $rs = @(Route $text)
    $many = $rs.Count -gt 1
    if ($many) { Log ("промпт {0} разбит на {1} задач(и)" -f $at, $rs.Count) }
    foreach ($r in $rs) {
        $t = if ($many -and $r.part) {
            "Полный промпт Германа (для контекста):`n$text`n`nТВОЯ ЧАСТЬ — сделай только её, остальные части параллельно делают другие агенты, их не трогай:`n$($r.part)"
        } else { $text }
        $co = if ($r.PSObject.Properties.Name -contains "cont_of") { $r.cont_of } else { $null }
        Log ("промпт {0} -> {1} / {2}/{4} / {3}: {5}{6}" -f $at, $r.zone, $r.agent, $r.mode, $r.effort, $r.title, $(if ($co) { " (уточнение к #$co)" } else { "" }))
        # Жалоба на готовую задачу; повторная (жалоба уже была или это была переделка) — разрешить скриншот.
        $rid = 0; if ("$($r.redo)" -match '^\s*#?(\d+)\s*$') { $rid = [int]$matches[1] }
        $done = if ($rid) { $Hist | Where-Object { $_.t -eq "done" -and $_.id -eq $rid } | Select-Object -Last 1 }
        if (-not $done) { $rid = 0 }
        if (-not $rid -and $r.PSObject.Properties.Name -contains "complaint") { $rid = [int]$r.complaint }
        # повторная: по этой же цепочке задач (переделки, уточнения, починки) жалоба уже была
        $root = if ($rid) { Root-Of $rid } else { 0 }
        $again = $rid -and @($Hist | Where-Object { $_.t -eq "redo" -and ($(if ($_.root) { [int]$_.root } else { Root-Of ([int]$_.id) }) -eq $root) }).Count
        # Склейка: задача этой зоны, которая ещё не началась (не возобновление и не починка smoke).
        $m = $Jobs | Where-Object { $_.status -eq "очередь" -and $_.zone -eq $r.zone -and -not $_.resume -and -not $_.smoke_of -and -not $_.conflict_of -and
            "$($_.cont_of)" -eq "$co" -and [int]$_.merged -lt 6 } | Select-Object -Last 1
        if ($m) {
            Merge-Into $m $r $t $at; $q = $m
            $hold = if ($m.hold_until) { " старт не раньше " + ([DateTime]$m.hold_until).ToString("HH:mm:ss") } else { "" }
            Status ("принято {0}: склеено с #{1} [{2}] ({3} промпт(а)), {4}{5}" -f $at, $m.id, $m.zone, ([int]$m.merged + 1), (Zone-Line $m.zone), $hold)
        } else {
            $q = Enqueue $r.zone $r.agent $r.effort $r.mode $t $at $r.title
            if ($co) { $q.cont_of = $co }
            if ($HoldSec -gt 0) { $q.hold_until = (Get-Date).AddSeconds($HoldSec).ToString("o") }
            Status ("принято {0}: #{1} «{2}» — зона {3}, {4}{5}, {6}" -f $at, $q.id, $r.title, $r.zone, (Who $q), $(if ($co) { ", уточнение к #$co (тому же воркеру после него)" } else { "" }), (Zone-Line $r.zone))
        }
        if ($rid -and $rid -ne $q.id) {
            if (-not $q.fix_of) { $q.fix_of = $rid }
            Hist-Add @{ t = "redo"; id = $rid; by = $q.id; at = $at; again = [bool]$again; root = $root }
            if ($again) { $q.shot = $true }
            Log ("переделка: #{0} — жалоба на #{1}{2}" -f $q.id, $rid, $(if ($again) { " (повторная — разрешён скриншот)" } else { "" }))
        }
        Check-Zone $q.zone
        Save-Jobs
    }
}

# resume: снять стоп, поставить паузы/прерванные обратно в очередь как продолжение их сессии.
function Do-Resume {
    foreach ($q in @($Jobs | Where-Object { $_.status -in "пауза", "прерван" })) {
        $why = if ($q.status -eq "пауза") { "мягкая остановка" } else { "жёсткая остановка" }
        $q.status = "возобновлён"
        $script:Seq++
        [void]$Jobs.Add(@{ id = $script:Seq; zone = $q.zone; agent = (Norm-Agent $q.agent); effort = $q.effort; mode = "continue"; text = $q.text; at = $q.at
            title = $q.title; status = "очередь"; resume = $why; session = $q.session })
    }
    Save-Jobs
}

$State = Load-Map $StateFile
$Hist = Load-Hist
$Stats = $null; Calc-Stats
$Procs = @{}
$LogTail = New-Object System.Collections.ArrayList
$Seq = 0; $Dirty = $true; $LastShow = Get-Date; $LastSave = Get-Date
$job = $null
$Jobs = Load-Jobs
$Notes = New-Object System.Collections.ArrayList
try { foreach ($n in @(([IO.File]::ReadAllText($JobsFile, $Utf8) | ConvertFrom-Json).notes)) { if ($n) { [void]$Notes.Add("$n") } } } catch {}
$ZoneWarn = @{}; $Prompts1h = 0; $LastSummary = Get-Date; $LastAlive = (Get-Date).AddMinutes(-5)
$AliveFile = Join-Path $Dir "alive.log"     # раз в минуту, пока слушаем TG, — для метрики «дыры в слушании»
# smoke: очередь задач с пушами, последний зелёный main, текущая проверка (один процесс за раз)
$SmokeQ = New-Object System.Collections.ArrayList
$SmokeWait = New-Object System.Collections.ArrayList   # пуши, которые не проверить, пока main сломан чужой/известной ошибкой
$SmokeSt = @{ green = ""; last = "" }
try { $o = [IO.File]::ReadAllText($SmokeFile, $Utf8) | ConvertFrom-Json; $SmokeSt.green = "$($o.green)"; $SmokeSt.last = "$($o.last)"; foreach ($i in @($o.queue)) { if ($i) { [void]$SmokeQ.Add([int]$i) } } } catch {}
$Smoke = @{ proc = $null; phase = ""; sha = "" }
$SmokeWt = $null
$SmokeSh = Join-Path $Dir "smoke-run.sh"
[IO.File]::WriteAllText($SmokeSh, @'
#!/usr/bin/env bash
# Запускается диспетчером: smoke.sh на заданном коммите в постоянной копии «smoke». $1 — копия, $2 — коммит.
cd "$1" || exit 1
git fetch -q origin main >/dev/null 2>&1
rm -f "godot/THE LEAK/override.cfg"
git checkout -q -f --detach "$2" || { echo "checkout $2 не вышел"; exit 1; }
git clean -qfd >/dev/null 2>&1
if [ -f scripts/smoke.sh ]; then bash scripts/smoke.sh
else echo "(scripts/smoke.sh на этом коммите нет — проверка gd-check)"; bash scripts/gd-check.sh "godot/THE LEAK"; fi
'@.Replace("`r`n", "`n"), $Utf8)
$DryChain = New-Object System.Collections.ArrayList; $DryBad = @{}; $DryFix = @{}
if ($Task) { $HoldSec = 0 }
# Тестовые промпты для сухого прогона: «секунда|текст».
$TestQ = New-Object System.Collections.ArrayList; $T0 = Get-Date
if ($TestPrompts) {
    foreach ($l in [IO.File]::ReadAllLines((Resolve-Path $TestPrompts), $Utf8)) {
        if ($l -match '^\s*(\d+)\s*\|(.+)$') { [void]$TestQ.Add(@{ sec = [int]$matches[1]; text = $matches[2].Replace("
", "`n").Trim() }) }
    }
}
# Первый запуск со статистикой — заводим историю из уже завершённых задач.
if (-not (Test-Path $HistFile)) {
    foreach ($q in @($Jobs | Where-Object { $_.status -in "готово", "СЛОЖНО", "ошибка" })) {
        Hist-Add @{ t = "done"; id = $q.id; at = $q.at; zone = $q.zone; agent = (Norm-Agent $q.agent); effort = $q.effort; cost = [double]$q.cost; status = $q.status; fix_of = $null; title = $q.title }
    }
}
$adopt = @($Jobs | Where-Object { $_.status -eq "работает" })
if (-not $DryRun) { [void](Wt reap) }; $LastReap = Get-Date   # очистка брошенных worktree при старте
Log ("диспетчер запущен: {0}; подхватил работающих воркеров: {1}" -f $Repo, $adopt.Count)
if ($Task) { Handle $Task "--.-- --:--" }

while ($true) {
    $sm = Stop-Mode
    if (-not $Task -and -not $DryRun -and -not $job) {
        $job = Start-Job -ScriptBlock { param($p) & $p "wait" "10" } -ArgumentList $Prompts
    }
    if ($job -and $job.State -ne "Running") {
        $raw = (Receive-Job $job 2>&1 | Out-String); Remove-Job $job -Force; $job = $null
        Handle $raw
    }
    if ($job -and ((Get-Date) - $LastAlive).TotalSeconds -ge 60) { [IO.File]::AppendAllText($AliveFile, (Get-Date -Format "dd.MM HH:mm") + "`n", $Utf8); $LastAlive = Get-Date }
    while ($TestQ.Count -and ((Get-Date) - $T0).TotalSeconds -ge $TestQ[0].sec) {
        $tp = $TestQ[0]; $TestQ.RemoveAt(0); Handle $tp.text ("20.11 " + (Get-Date -Format "HH:mm"))
    }
    foreach ($f in @(Get-ChildItem $Inbox -Filter *.txt -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $t = [IO.File]::ReadAllText($f.FullName, $Utf8); Remove-Item $f.FullName -Force
        if ($t.Trim() -eq "/resume") { Log "resume из TUI"; Do-Resume; continue }
        Handle $t "TUI"
    }
    if (Test-Path (Join-Path $Dir "resume.req")) { Remove-Item (Join-Path $Dir "resume.req") -Force; Log "resume"; Do-Resume }
    foreach ($q in @($Jobs | Where-Object { $_.status -eq "работает" })) {
        if (-not (Alive $q)) { Finish $q }
        elseif (-not $q.session -and ((Get-Date) - [DateTime]$q.started).TotalSeconds -gt 10) { $q.session = Find-Sid $q; if ($q.session) { Save-Jobs } }
    }
    if ($HoldUntil -and (Get-Date) -ge $HoldUntil) { $HoldUntil = $null; $ProbeOnly = $true; Log "пауза по лимиту Claude кончилась — пробую одну задачу"; $Dirty = $true }
    if (-not $sm -and -not $HoldUntil -and (Get-Date) -ge $WtRetryAt) {
        foreach ($q in @($Jobs | Where-Object { $_.status -eq "очередь" })) {
            if ($q.hold_until -and (Get-Date) -lt [DateTime]$q.hold_until) { continue }   # ждём поправок Германа (склейка)
            $busy = @($Jobs | Where-Object { $_.status -eq "работает" -and $_.zone -eq $q.zone }).Count
            $chat = Test-Path (Join-Path $Dir "chat-$($q.zone).lock")  # Герман сам в чате с агентом (TUI Ctrl+O)
            if ($ProbeOnly -and @($Jobs | Where-Object { $_.status -eq "работает" }).Count) { break }
            if (-not $busy -and -not $chat) { $script:WtCode = 0; Start-Worker $q; if ($WtCode -eq 3) { break } }
        }
    }
    Smoke-Tick
    if (((Get-Date) - $LastSummary).TotalMinutes -ge 60) { Hour-Summary; $LastSummary = Get-Date }
    if (($Task -or $DryRun) -and -not $TestQ.Count -and -not @($Jobs | Where-Object { $_.status -in "работает", "очередь" }).Count -and -not $Smoke.proc -and -not $SmokeQ.Count) {
        if ($DryRun) { Hour-Summary }; Save-Jobs; break
    }
    if (-not $DryRun -and ((Get-Date) - $LastReap).TotalMinutes -ge 30) { [void](Wt reap); $LastReap = Get-Date }
    if (((Get-Date) - $LastSave).TotalSeconds -ge 3) { Save-Jobs; $LastSave = Get-Date }
    if (-not $Plain -and ($Dirty -or ((Get-Date) - $LastShow).TotalSeconds -ge 5)) { Show }
    Start-Sleep -Seconds 2
}
