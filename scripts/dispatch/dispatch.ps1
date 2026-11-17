# Диспетчер TG-промптов без LLM-сессии.
# Ждёт промпт Германа -> Haiku выбирает зону/агента/продолжать или нет -> воркер `claude -p --agent ...`
# в своём worktree на зону (.claude\worktrees\disp-<зона>). Зоны работают параллельно, в одной зоне — очередь.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dispatch\dispatch.ps1            # слушать TG
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dispatch\dispatch.ps1 -Task "…"  # одна задача без TG (по-настоящему правит и пушит!)
#
# Нужно: `claude` залогинен в терминале (claude, затем /login). Одновременно не держать сессию-слушателя в приложении —
# оба помечают промпты прочитанными. Лог и состояние: .claude\dispatch\ (не в git). Ctrl+C — стоп (воркеры доработают сами).
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
New-Item -ItemType Directory -Force $Dir, $Wts | Out-Null
$StateFile = Join-Path $Dir "state.json"
$LogFile = Join-Path $Dir "dispatch.log"
$Zones = "slot","shop","items","player","enemy","ui","net","level","car","village","world","core","other"

function Log([string]$s) {
    $l = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm:ss"), $s
    Write-Host $l
    [IO.File]::AppendAllText($LogFile, $l + "`n", $Utf8)
}
function Run-Git { & git @args *> $null }

function Load-State {
    $s = @{}
    if (Test-Path $StateFile) {
        $o = [IO.File]::ReadAllText($StateFile, $Utf8) | ConvertFrom-Json
        foreach ($p in $o.PSObject.Properties) { $h = @{}; foreach ($q in $p.Value.PSObject.Properties) { $h[$q.Name] = $q.Value }; $s[$p.Name] = $h }
    }
    $s
}
function Save-State { [IO.File]::WriteAllText($StateFile, ($State | ConvertTo-Json -Depth 5), $Utf8) }

# Размер контекста сессии воркера — по последнему ответу в её транскрипте.
function Get-Ctx([string]$wt, [string]$sid) {
    $f = Join-Path $env:USERPROFILE (".claude\projects\" + ($wt -replace '[^A-Za-z0-9]', '-') + "\$sid.jsonl")
    if (-not (Test-Path $f)) { return 0 }
    $line = Get-Content $f -Tail 80 -Encoding UTF8 | Where-Object { $_ -match '"cache_read_input_tokens"' } | Select-Object -Last 1
    if (-not $line) { return 0 }
    try { $u = ($line | ConvertFrom-Json).message.usage; return [int]($u.input_tokens + $u.cache_read_input_tokens + $u.cache_creation_input_tokens) } catch { return 0 }
}

function Route([string]$text) {
    $lines = foreach ($z in $State.Keys) {
        $w = $State[$z]; "- {0}: {1}, контекст ~{2}k, последняя задача {3}: {4}" -f $z, $w.agent, [int]($w.ctx / 1000), $w.at, $w.last
    }
    if (-not $lines) { $lines = "(агентов ещё нет)" }
    $p = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "router.md"), $Utf8).Replace("{{STATE}}", ($lines -join "`n")).Replace("{{TASK}}", $text)
    $out = $p | & $Claude -p --model haiku --output-format text --tools Read --strict-mcp-config --no-session-persistence --disable-slash-commands 2>$null | Out-String
    $r = $null
    if ($out -match '\{[\s\S]*\}') { try { $r = $matches[0] | ConvertFrom-Json } catch {} }
    if (-not $r) { Log "роутер не ответил JSON ($($out.Trim()) ) — беру gd-worker/other/new"; $r = [pscustomobject]@{ zone = "other"; agent = "gd-worker"; mode = "new"; title = $text.Substring(0, [Math]::Min(60, $text.Length)) } }
    if ($Zones -notcontains $r.zone) { $r.zone = "other" }
    if ("gd-quick", "gd-worker" -notcontains $r.agent) { $r.agent = "gd-worker" }
    $w = $State[$r.zone]
    if ($r.mode -ne "continue" -or -not $w -or -not $w.session -or $w.ctx -ge $MaxCtx -or $w.agent -ne $r.agent) { $r.mode = "new" }
    $r
}

function Enqueue($zone, $agent, $mode, $text, $at, $title) {
    [void]$Queue.Add(@{ zone = $zone; agent = $agent; mode = $mode; text = $text; at = $at; title = $title })
}

function Start-Worker($q) {
    $zone = $q.zone; $wt = Join-Path $Wts "disp-$zone"
    if (-not (Test-Path $wt)) { Run-Git -C $Repo fetch -q origin main; Run-Git -C $Repo worktree add -q --detach $wt origin/main }
    if (Test-Path (Join-Path $wt ".git")) {
        Run-Git -C $wt rebase --abort
        Run-Git -C $wt fetch -q origin main
        Run-Git -C $wt rebase -q --autostash origin/main
    } else { Log "[$zone] не удалось создать worktree $wt"; return }
    $brief = if ($q.mode -eq "continue") {
        "Новый промпт Германа ($($q.at)), продолжение твоей работы:`n$($q.text)"
    } else {
        "Правила — godot/eskiness/AGENTS.md. Время промпта: $($q.at). Задача Германа:`n$($q.text)"
    }
    $in = Join-Path $Dir "$zone.in.txt"; $out = Join-Path $Dir "$zone.out.json"; $err = Join-Path $Dir "$zone.err.txt"
    [IO.File]::WriteAllText($in, $brief, $Utf8)
    $a = @("-p", "--agent", $q.agent, "--output-format", "json", "--permission-mode", "bypassPermissions", "--strict-mcp-config")
    if ($q.mode -eq "continue") { $a += @("--resume", $State[$zone].session) }
    $proc = Start-Process -FilePath $Claude -ArgumentList $a -WorkingDirectory $wt -NoNewWindow -PassThru `
        -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err
    $Running[$zone] = @{ proc = $proc; out = $out; err = $err; wt = $wt; q = $q }
    Log ("[{0}] {1} {2}: {3}" -f $zone, $q.agent, $(if ($q.mode -eq "continue") { "продолжает" } else { "новый" }), $q.title)
}

function Finish($zone) {
    $r = $Running[$zone]; $Running.Remove($zone); $q = $r.q
    $j = $null
    try { $j = [IO.File]::ReadAllText($r.out, $Utf8) | ConvertFrom-Json } catch {}
    if (-not $j) {
        $e = ([IO.File]::ReadAllText($r.err, $Utf8) -replace '\s+', ' ').Trim()
        Log "[$zone] воркер упал: $($e.Substring(0, [Math]::Min(300, $e.Length)))"; return
    }
    $res = "$($j.result)".Trim()
    $ctx = Get-Ctx $r.wt $j.session_id
    $State[$zone] = @{ session = $j.session_id; agent = $q.agent; ctx = $ctx; last = $q.title; at = $q.at }
    Save-State
    Log ("[{0}] готово, ~{1}k, `${2:N2}: {3}" -f $zone, [int]($ctx / 1000), $j.total_cost_usd, (($res -split "`n")[0]))
    if ($q.agent -eq "gd-quick" -and $res -match '^\s*СЛОЖНО') {
        Log "[$zone] gd-quick не справился — отдаю gd-worker"
        Enqueue $zone "gd-worker" "new" $q.text $q.at $q.title
    }
}

function Handle([string]$raw) {
    $at = ""; $body = @()
    foreach ($l in ($raw -split "`r?`n")) {
        if ($l -match '^=== (\d\d\.\d\d \d\d:\d\d) МСК') { $at = $matches[1]; continue }
        if ($l.Trim()) { $body += $l }
    }
    $text = ($body -join "`n").Trim()
    if (-not $text -or $text -eq "новых промптов нет") { return }
    if (-not $at) { $at = "?" }
    $r = Route $text
    Log ("промпт {0} -> {1} / {2} / {3}" -f $at, $r.zone, $r.agent, $r.mode)
    Enqueue $r.zone $r.agent $r.mode $text $at $r.title
}

$State = Load-State
$Running = @{}
$Queue = New-Object System.Collections.ArrayList
Log "диспетчер запущен: $Repo"
if ($Task) { Handle ("=== --.-- --:-- МСК`n" + $Task) }

$job = $null
while ($true) {
    if (-not $Task -and -not $job) {
        $job = Start-Job -ScriptBlock { param($p) & $p "wait" "10" } -ArgumentList $Prompts
    }
    if ($job -and $job.State -ne "Running") {
        $raw = (Receive-Job $job 2>&1 | Out-String); Remove-Job $job -Force; $job = $null
        Handle $raw
    }
    foreach ($z in @($Running.Keys)) { if ($Running[$z].proc.HasExited) { Finish $z } }
    foreach ($q in @($Queue)) {
        if (-not $Running.ContainsKey($q.zone)) { $Queue.Remove($q); Start-Worker $q }
    }
    if ($Task -and $Running.Count -eq 0 -and $Queue.Count -eq 0) { break }
    Start-Sleep -Seconds 3
}
