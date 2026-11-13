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
