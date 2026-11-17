# Диспетчер TG-промптов без LLM-сессии.
# Ждёт промпт Германа -> Sonnet (low) выбирает зону/агента/продолжать или нет -> воркер `claude -p --agent ...`
# в своём worktree на зону (.claude\worktrees\disp-<зона>). Зоны работают параллельно, в одной зоне — очередь.
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
param(
    [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [int]$MaxCtx = 150000,
    [string]$Prompts = "C:\Users\volin\.config\atlas\prompts.ps1",
    [string]$Task = ""
)
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Utf8 = New-Object Text.UTF8Encoding $false
$OutputEncoding = $Utf8
$Claude = (Get-Command claude -ErrorAction Stop).Source
$Dir = Join-Path $Repo ".claude\dispatch"
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
$Zones = "slot","shop","items","player","enemy","ui","net","level","car","village","world","core","other"

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
    $script:Dirty = $true
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
    $wait = if ($Task) { "" } elseif ($sm) { "СТОП ($sm) — новые задачи не стартуют" } elseif ($job) { "слушаю TG…" } else { "" }
    $o.Add(("ДИСПЕТЧЕР  {0}   работают: {1}   в очереди: {2}   {3}" -f (Get-Date -Format "HH:mm:ss"), $run, $que, $wait))
    $o.Add((Cut ("КАЧЕСТВО  " + (Stats-Line)) $w))
    $o.Add("")
    $o.Add(("{0,-3} {1,-11} {2,-8} {3,-12} {4,-4} {5,-9} {6,6} {7,5} {8,6}  {9}" -f "#", "промпт", "зона", "модель", "реж", "статус", "время", "ктх", "`$", "задача / результат"))
    foreach ($q in @($Jobs | Select-Object -Last 15)) {
        $ctx = if ($q.ctx) { "{0}k" -f [int]($q.ctx / 1000) } else { "" }
        $cost = if ($q.cost) { "{0:N2}" -f $q.cost } else { "" }
        $info = if ($q.result) { $q.title + "  ->  " + $q.result } else { $q.title }
        $line = "{0,-3} {1,-11} {2,-8} {3,-12} {4,-4} {5,-9} {6,6} {7,5} {8,6}  {9}" -f $q.id, $q.at, $q.zone, (Who $q), $(if ($q.mode -eq "continue") { "прод" } else { "нов" }), $q.status, (Dur $q), $ctx, $cost, $info
        $o.Add((Cut $line $w))
    }
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
        }
    }
    $script:Stats = $st
}
function Stats-Line {
    (@(foreach ($m in $Stats.Keys) { $x = $Stats[$m]
        "{0}: {1} задач, {2} переделок ({3}%){4}, `${5:N2} + `${6:N2} на переделки" -f $m, $x.tasks, $x.redo, $x.pct, $(if ($m -eq "sonnet") { ", СЛОЖНО $($x.hard)" } else { "" }), $x.cost, $x.fixcost
    }) -join "   ·   ")
}

function Save-Jobs {
    $keep = @($Jobs | Select-Object -Last 40)
    $script:Jobs = New-Object System.Collections.ArrayList; foreach ($q in $keep) { [void]$Jobs.Add($q) }
    $rows = foreach ($q in $Jobs) { $c = $q.Clone(); $c.dur = Dur $q; $c }
    $o = [ordered]@{
        heartbeat = [DateTimeOffset]::Now.ToUnixTimeSeconds(); pid = $PID; listening = [bool]$job; stop = (Stop-Mode)
        seq = $Seq; stats = $Stats; jobs = @($rows)
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
        }
        Fix-Route $m $text
    }
    $res
}

function Fix-Route($r, [string]$text) {
    foreach ($k in "zone", "agent", "effort", "mode", "title", "part", "redo") { if (-not ($r.PSObject.Properties.Name -contains $k)) { $r | Add-Member -Force $k "" } }
    if ($Zones -notcontains $r.zone) { $r.zone = "other" }
    $r.agent = Norm-Agent $r.agent
    if ("sonnet", "opus" -notcontains $r.agent) { $r.agent = "opus" }
    if ($Efforts -notcontains $r.effort) { $r.effort = $(if ($r.agent -eq "sonnet") { "medium" } else { "high" }) }
    if (-not $r.title) { $r.title = Cut $(if ($r.part) { $r.part } else { $text }) 60 }
    $w = $State[$r.zone]
    if ($r.mode -ne "continue" -or -not $w -or -not $w.session -or $w.ctx -ge $MaxCtx -or (Norm-Agent $w.agent) -ne $r.agent) { $r.mode = "new" }
    $r
}

function Enqueue($zone, $agent, $effort, $mode, $text, $at, $title) {
    $script:Seq++
    $q = @{ id = $script:Seq; zone = $zone; agent = $agent; effort = $effort; mode = $mode; text = $text; at = $at; title = $title; status = "очередь" }
    [void]$Jobs.Add($q); $script:Dirty = $true; Save-Jobs
}

function Start-Worker($q) {
    $zone = $q.zone; $wt = Join-Path $Wts "disp-$zone"
    if (-not (Test-Path $wt)) { Run-Git -C $Repo fetch -q origin main; Run-Git -C $Repo worktree add -q --detach $wt origin/main }
    if (Test-Path (Join-Path $wt ".git")) {
        Run-Git -C $wt rebase --abort
        Run-Git -C $wt fetch -q origin main
        Run-Git -C $wt rebase -q --autostash origin/main
    } else { $q.status = "упал"; $q.result = "нет worktree"; $q.finished = (Get-Date).ToString("o"); Log "[$zone] не удалось создать worktree $wt"; return }
    $brief = if ($q.resume) {
        "Работу остановили ($($q.resume)). Продолжай свою задачу с того места, где остановился." +
        $(if (Test-Path (Join-Path $HandoffDir "$zone.md")) { " Твой handoff: $(Join-Path $HandoffDir "$zone.md")" } else { "" })
    } elseif ($q.mode -eq "continue") {
        "Новый промпт Германа ($($q.at)), продолжение твоей работы:`n$($q.text)"
    } else {
        "Правила — godot/eskiness/AGENTS.md. Время промпта: $($q.at). Задача Германа:`n$($q.text)"
    }
    $in = Join-Path $Dir "$zone.in.txt"; $out = Join-Path $Dir "$zone.out.json"; $err = Join-Path $Dir "$zone.err.txt"
    [IO.File]::WriteAllText($in, $brief, $Utf8)
    $q.agent = Norm-Agent $q.agent
    $a = @("-p", "--agent", $q.agent, "--output-format", "json", "--permission-mode", "bypassPermissions", "--strict-mcp-config", "--disable-slash-commands", "--settings", "`"$HooksFile`"")
    $sid = if ($q.resume -and $q.session) { $q.session } elseif ($q.mode -eq "continue" -and $State[$zone]) { $State[$zone].session } else { $null }
    if ($q.effort) { $a += @("--effort", $q.effort) }
    if ($sid) { $a += @("--resume", $sid) }
    # Скрытое отдельное окно: воркер не привязан к консоли диспетчера и переживает его закрытие.
    $proc = Start-Process -FilePath $Claude -ArgumentList $a -WorkingDirectory $wt -WindowStyle Hidden -PassThru `
        -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err
    $q.pid = $proc.Id; $q.pstart = $proc.StartTime.ToString("o"); $q.wt = $wt; $q.out = $out; $q.err = $err
    $q.status = "работает"; $q.started = (Get-Date).ToString("o"); $q.finished = $null; $q.session = $sid
    $Procs[$q.id] = $proc
    Save-Jobs
    Log ("[{0}] {1} {2}: {3}" -f $zone, (Who $q), $(if ($q.resume) { "возобновляет" } elseif ($q.mode -eq "continue") { "продолжает" } else { "новый" }), $q.title)
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

function Finish($q) {
    $Procs.Remove($q.id); $zone = $q.zone
    $q.finished = (Get-Date).ToString("o")
    $j = $null
    try { $j = [IO.File]::ReadAllText($q.out, $Utf8) | ConvertFrom-Json } catch {}
    if (-not $j) {
        $e = ""; try { $e = ([IO.File]::ReadAllText($q.err, $Utf8) -replace '\s+', ' ').Trim() } catch {}
        if (-not $q.session) { $q.session = Find-Sid $q }
        if ((Stop-Mode) -eq "kill") { $q.status = "прерван"; $q.result = "жёсткая остановка" ; Log "[$zone] воркер прерван (kill)" }
        else { $q.status = "упал"; $q.result = $e; Log "[$zone] воркер упал: $(Cut $e 300)" }
        Save-Jobs; return
    }
    $res = "$($j.result)".Trim()
    $ctx = Get-Ctx $q.wt $j.session_id
    $q.session = $j.session_id; $q.ctx = $ctx; $q.cost = $j.total_cost_usd; $q.result = (($res -split "`n")[0])
    $hf = Join-Path $HandoffDir "$zone.md"
    $handoff = (Test-Path $hf) -and ((Get-Item $hf).LastWriteTime -ge [DateTime]$q.started)
    $q.status = if ($j.is_error) { "ошибка" } elseif ($res -match '^\s*СЛОЖНО') { "СЛОЖНО" } elseif ($handoff -and (Stop-Mode)) { "пауза" } else { "готово" }
    $State[$zone] = @{ session = $j.session_id; agent = $q.agent; effort = $q.effort; ctx = $ctx; last = $q.title; at = $q.at }
    if ($q.status -ne "пауза") {
        Hist-Add @{ t = "done"; id = $q.id; at = $q.at; zone = $zone; agent = $q.agent; effort = $q.effort; cost = [double]$j.total_cost_usd; status = $q.status; fix_of = $q.fix_of; title = $q.title }
    }
    Save-State; Save-Jobs
    Log ("[{0}] {1}, ~{2}k, `${3:N2}: {4}" -f $zone, $q.status, [int]($ctx / 1000), $j.total_cost_usd, (($res -split "`n")[0]))
    if ($q.agent -eq "sonnet" -and $res -match '^\s*СЛОЖНО') {
        Log "[$zone] sonnet не справился — отдаю opus/high"
        Enqueue $zone "opus" "high" "new" $q.text $q.at $q.title
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
    $rs = @(Route $text)
    $many = $rs.Count -gt 1
    if ($many) { Log ("промпт {0} разбит на {1} задач(и)" -f $at, $rs.Count) }
    foreach ($r in $rs) {
        $t = if ($many -and $r.part) {
            "Полный промпт Германа (для контекста):`n$text`n`nТВОЯ ЧАСТЬ — сделай только её, остальные части параллельно делают другие агенты, их не трогай:`n$($r.part)"
        } else { $text }
        Log ("промпт {0} -> {1} / {2}/{4} / {3}: {5}" -f $at, $r.zone, $r.agent, $r.mode, $r.effort, $r.title)
        Enqueue $r.zone $r.agent $r.effort $r.mode $t $at $r.title
        $rid = 0; if ("$($r.redo)" -match '^\s*#?(\d+)\s*$') { $rid = [int]$matches[1] }
        if ($rid -and $rid -ne $Seq -and @($Hist | Where-Object { $_.t -eq "done" -and $_.id -eq $rid }).Count) {
            $Jobs[$Jobs.Count - 1].fix_of = $rid
            Hist-Add @{ t = "redo"; id = $rid; by = $Seq; at = $at }
            Log ("переделка: #{0} — жалоба на #{1}" -f $Seq, $rid)
            Save-Jobs
        }
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
# Первый запуск со статистикой — заводим историю из уже завершённых задач.
if (-not (Test-Path $HistFile)) {
    foreach ($q in @($Jobs | Where-Object { $_.status -in "готово", "СЛОЖНО", "ошибка" })) {
        Hist-Add @{ t = "done"; id = $q.id; at = $q.at; zone = $q.zone; agent = (Norm-Agent $q.agent); effort = $q.effort; cost = [double]$q.cost; status = $q.status; fix_of = $null; title = $q.title }
    }
}
$adopt = @($Jobs | Where-Object { $_.status -eq "работает" })
Log ("диспетчер запущен: {0}; подхватил работающих воркеров: {1}" -f $Repo, $adopt.Count)
if ($Task) { Handle $Task "--.-- --:--" }

while ($true) {
    $sm = Stop-Mode
    if (-not $Task -and -not $job) {
        $job = Start-Job -ScriptBlock { param($p) & $p "wait" "10" } -ArgumentList $Prompts
    }
    if ($job -and $job.State -ne "Running") {
        $raw = (Receive-Job $job 2>&1 | Out-String); Remove-Job $job -Force; $job = $null
        Handle $raw
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
    if (-not $sm) {
        foreach ($q in @($Jobs | Where-Object { $_.status -eq "очередь" })) {
            $busy = @($Jobs | Where-Object { $_.status -eq "работает" -and $_.zone -eq $q.zone }).Count
            $chat = Test-Path (Join-Path $Dir "chat-$($q.zone).lock")  # Герман сам в чате с агентом (TUI Ctrl+O)
            if (-not $busy -and -not $chat) { Start-Worker $q }
        }
    }
    if ($Task -and -not @($Jobs | Where-Object { $_.status -in "работает", "очередь" }).Count) { break }
    if (((Get-Date) - $LastSave).TotalSeconds -ge 3) { Save-Jobs; $LastSave = Get-Date }
    if ($Dirty -or ((Get-Date) - $LastShow).TotalSeconds -ge 5) { Show }
    Start-Sleep -Seconds 2
}
