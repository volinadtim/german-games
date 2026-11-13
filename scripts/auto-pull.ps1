# Watches GitHub and pulls new commits automatically.
# Usage: powershell -ExecutionPolicy Bypass -File auto-pull.ps1 [-Dir C:\path] [-Interval 10]
param(
    [string]$Dir = "$env:USERPROFILE\german-games",
    [int]$Interval = 10,
    [string]$Repo = "https://github.com/volinadtim/german-games.git",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "german-games auto-pull"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git is not installed. Get it from https://git-scm.com/download/win" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path (Join-Path $Dir ".git"))) {
    Write-Host "Cloning $Repo -> $Dir" -ForegroundColor Cyan
    git clone $Repo $Dir
    if ($LASTEXITCODE -ne 0) { Read-Host "Clone failed. Press Enter to exit"; exit 1 }
}

# Godot asks "files are newer on disk" for open scripts on every pull.
# Turn on Editor Settings > Text Editor > Behavior > Files > Auto Reload Scripts on External Change.
function Enable-GodotAutoReload {
    $key = "text_editor/behavior/files/auto_reload_scripts_on_external_change"
    $files = @(Get-ChildItem -ErrorAction SilentlyContinue "$env:APPDATA\Godot\editor_settings-4*.tres")
    if (-not $files.Count) { return }
    $todo = @($files | Where-Object { -not (Select-String -Quiet -Path $_.FullName -Pattern "^$([regex]::Escape($key)) = true") })
    if (-not $todo.Count) { return }
    if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "godot*" }) {
        Write-Host "Godot is open: close it once and restart this script to turn on auto-reload of scripts" -ForegroundColor Yellow
        return
    }
    foreach ($f in $todo) {
        $lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($f.FullName))
        $i = $lines.FindIndex({ param($l) $l.StartsWith("$key = ") })
        if ($i -ge 0) { $lines[$i] = "$key = true" }
        else {
            $r = $lines.IndexOf("[resource]")
            if ($r -lt 0) { continue }
            $lines.Insert($r + 1, "$key = true")
        }
        [IO.File]::WriteAllLines($f.FullName, $lines, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Godot: auto-reload of changed scripts turned on ($($f.Name))" -ForegroundColor Green
    }
}
Enable-GodotAutoReload

Set-Location $Dir
Write-Host "Watching $Repo ($Branch) every $Interval s in $Dir. Close the window to stop." -ForegroundColor Cyan

while ($true) {
    git fetch --quiet origin $Branch 2>$null
    if ($LASTEXITCODE -eq 0) {
        $local  = (git rev-parse HEAD).Trim()
        $remote = (git rev-parse "origin/$Branch").Trim()
        if ($local -ne $remote) {
            $stamp = Get-Date -Format "HH:mm:ss"
            if (git status --porcelain) {
                Write-Host "[$stamp] Local changes found, stashing them" -ForegroundColor Yellow
                git stash push --include-untracked -m "auto-pull $stamp" | Out-Null
            }
            git checkout --quiet $Branch 2>$null
            git merge --ff-only --quiet "origin/$Branch"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$stamp] Fast-forward failed, resetting to origin/$Branch" -ForegroundColor Yellow
                git branch --quiet "backup-$(Get-Date -Format yyyyMMdd-HHmmss)" 2>$null
                git reset --hard --quiet "origin/$Branch"
            }
            Write-Host "[$stamp] Updated:" -ForegroundColor Green
            git log --oneline "$local..HEAD" 2>$null | Select-Object -First 10
            [console]::Beep(880, 150)
        }
    } else {
        Write-Host "[$(Get-Date -Format HH:mm:ss)] fetch failed (no internet?), retrying" -ForegroundColor DarkYellow
    }
    Start-Sleep -Seconds $Interval
}
