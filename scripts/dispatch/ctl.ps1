# Управление разработкой диспетчера (работает и без запущенного диспетчера):
#   ctl.ps1 stop    — мягкая остановка: новые задачи не стартуют; воркеры доделывают или оставляют handoff
#   ctl.ps1 kill    — жёсткая: убить работающих воркеров сейчас
#   ctl.ps1 resume  — снять стоп; паузы/прерванные продолжат свои сессии
#   ctl.ps1 status  — кто работает
param([Parameter(Position = 0)][ValidateSet("stop", "kill", "resume", "status")][string]$Cmd = "status",
      [string]$Repo = "")
if (-not $Repo) { $Repo = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Utf8 = New-Object Text.UTF8Encoding $false
$Dir = Join-Path $Repo ".claude\dispatch"
$Flag = Join-Path $Dir "stop.flag"
New-Item -ItemType Directory -Force $Dir | Out-Null
$jobs = @()
try { $jobs = @(([IO.File]::ReadAllText((Join-Path $Dir "jobs.json"), $Utf8) | ConvertFrom-Json).jobs) } catch {}
$run = @($jobs | Where-Object { $_.status -eq "работает" })

switch ($Cmd) {
    "stop" { [IO.File]::WriteAllText($Flag, "stop", $Utf8); "мягкая остановка: работающих $($run.Count) — доделают или оставят handoff в .claude\dispatch\handoff\" }
    "kill" {
        [IO.File]::WriteAllText($Flag, "kill", $Utf8)
        foreach ($q in $run) { & taskkill /T /F /PID $q.pid 2>&1 | Out-Null; "убит [$($q.zone)] pid $($q.pid): $($q.title)" }
        "жёсткая остановка: убито $($run.Count)"
    }
    "resume" {
        Remove-Item -Force $Flag, (Join-Path $Dir "soft-notified") -Recurse -ErrorAction SilentlyContinue
        [IO.File]::WriteAllText((Join-Path $Dir "resume.req"), "", $Utf8)
        "стоп снят; паузы/прерванные продолжатся, когда диспетчер запущен"
    }
    "status" {
        $f = if (Test-Path $Flag) { [IO.File]::ReadAllText($Flag).Trim() } else { "нет" }
        "стоп: $f"
        foreach ($q in $run) { "работает [$($q.zone)] $($q.agent) pid $($q.pid): $($q.title)" }
    }
}
