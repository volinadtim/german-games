# Watches GitHub and pulls new commits automatically.
# Local changes are NOT hidden in stash any more: when GitHub has something new, they are committed
# ("German: local changes ...") and pushed to main together with the update. If they clash with the update,
# they go to a separate branch german-<date> on GitHub (Tim merges it) and the folder is reset to main.
# push.bat (-Once) does the same right now, without waiting.
# Usage: powershell -ExecutionPolicy Bypass -File auto-pull.ps1 [-Dir C:\path] [-Interval 10] [-Once]
param(
    [string]$Dir = "$env:USERPROFILE\german-games",
    [int]$Interval = 10,
    [switch]$Once,
    [string]$Repo = "https://github.com/volinadtim/german-games.git",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Continue"
# git on Windows asks "Unlink of file '...' failed. Should I try again? (y/n)" when Godot holds a file open,
# and the window hangs forever. Answer "no" automatically and never prompt.
$env:GIT_ASK_YESNO = "false"
$env:GIT_TERMINAL_PROMPT = "0"
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
    # Where Godot keeps editor settings: %APPDATA%\Godot, or editor_data next to the exe
    # (self-contained / portable / scoop builds).
    $dirs = New-Object System.Collections.Generic.List[string]
    $dirs.Add("$env:APPDATA\Godot")
    $exes = @()
    $exes += @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "godot*" } | ForEach-Object { $_.Path })
    $exes += @(Get-Command -ErrorAction SilentlyContinue godot*.exe | ForEach-Object { $_.Source })
    $exes += @(Get-ChildItem -ErrorAction SilentlyContinue "$env:USERPROFILE\Desktop\*.lnk", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\*.lnk", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\*\*.lnk" |
        Where-Object { $_.Name -like "*godot*" } |
        ForEach-Object { (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).TargetPath })
    foreach ($e in $exes) { if ($e) { $d = Split-Path -Parent $e; $dirs.Add("$d\editor_data"); $dirs.Add($d) } }
    $dirs.Add("$env:USERPROFILE\scoop\persist\godot\editor_data")
    # Steam: Godot is self-contained there, settings in steamapps\common\Godot Engine\editor_data
    $steam = $null
    try { $steam = (Get-ItemProperty -ErrorAction Stop "HKCU:\Software\Valve\Steam").SteamPath } catch {}
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($steam, "${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        if (-not $s -or -not (Test-Path $s)) { continue }
        $libs.Add($s)
        $vdf = Join-Path $s "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $libs.Add(($_.Matches[0].Groups[1].Value -replace '\\\\', '\')) }
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        Get-ChildItem -ErrorAction SilentlyContinue -Directory (Join-Path $l "steamapps\common") |
            Where-Object { $_.Name -like "*Godot*" } |
            ForEach-Object { $dirs.Add("$($_.FullName)\editor_data") }
    }
    $files = @($dirs | Select-Object -Unique | ForEach-Object { Get-ChildItem -ErrorAction SilentlyContinue "$_\editor_settings-4*.tres" } | Sort-Object FullName -Unique)
    if (-not $files.Count) {
        Write-Host "Godot settings not found (open Godot once, then restart this script). Or turn on by hand: Editor Settings > Text Editor > Behavior > Files > Auto Reload Scripts on External Change" -ForegroundColor Yellow
        return
    }
    $todo = @($files | Where-Object { -not (Select-String -Quiet -Path $_.FullName -Pattern "^$([regex]::Escape($key)) = true") })
    if (-not $todo.Count) {
        Write-Host "Godot: auto-reload of changed scripts is already on ($(($files | ForEach-Object { $_.FullName }) -join ', '))" -ForegroundColor Green
        return
    }
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
        Write-Host "Godot: auto-reload of changed scripts turned on ($($f.FullName))" -ForegroundColor Green
    }
}
Enable-GodotAutoReload

Set-Location $Dir

# Is a Godot editor (or a game started from it) open with a project from this folder?
# Updating files under an open editor broke a scene once, so we wait until it is closed.
function Get-GodotOpen {
    $root = ((Resolve-Path $Dir).Path -replace '/', '\').TrimEnd('\').ToLower()
    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "godot*" })
    foreach ($p in $procs) {
        $cl = "$($p.CommandLine)"
        if (-not $cl) { return "Godot (pid $($p.ProcessId), its folder is unknown)" }   # cannot read it -> be careful
        if (($cl -replace '/', '\').ToLower().Contains($root)) { return "Godot (pid $($p.ProcessId))" }
    }
    # Opened from the project manager: the command line has no path, but the editor holds .godot\editor files.
    foreach ($p in $procs) {
        if ("$($p.CommandLine)" -match '(?i)--path|\.godot\b|project\.godot') { continue }
        foreach ($lock in @(Get-ChildItem -ErrorAction SilentlyContinue "$Dir\godot\*\.godot\editor\project_metadata.cfg")) {
            if (((Get-Date) - $lock.LastWriteTime).TotalHours -lt 12) { return "Godot project manager/editor (pid $($p.ProcessId))" }
        }
    }
    return $null
}
$script:WarnedOpen = $false

# Commit local changes and send everything to GitHub. Clash with the update -> separate branch german-<date>.
function Sync-Local([string]$stamp) {
    if (git status --porcelain) {
        Write-Host "[$stamp] Local changes found, committing them" -ForegroundColor Yellow
        git add -A
        git commit --quiet -m "German: local changes $stamp"
    }
    $ahead = [int](git rev-list --count "origin/$Branch..HEAD")
    if ($ahead -eq 0) {
        git merge --ff-only --quiet "origin/$Branch"
        return
    }
    git rebase --quiet "origin/$Branch" 2>$null
    $ok = $LASTEXITCODE -eq 0
    if ($ok) {
        git push --quiet origin "HEAD:$Branch"
        $ok = $LASTEXITCODE -eq 0
        if ($ok) { Write-Host "[$stamp] Your changes are on GitHub (main)" -ForegroundColor Green; return }
    } else {
        git rebase --abort 2>$null
    }
    $br = "german-$(Get-Date -Format yyyyMMdd-HHmmss)"
    git push --quiet origin "HEAD:refs/heads/$br"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$stamp] Your changes clash with the update: saved on GitHub as branch $br, Tim will merge it" -ForegroundColor Yellow
        git branch --quiet "backup-$(Get-Date -Format yyyyMMdd-HHmmss)" 2>$null
        git reset --hard --quiet "origin/$Branch"
    } else {
        Write-Host "[$stamp] Push failed (no access to GitHub?). Your changes stay here in a local commit." -ForegroundColor Red
    }
}

git checkout --quiet $Branch 2>$null
if ($Once) {
    $open = Get-GodotOpen
    if ($open) { Write-Host "$open is open with this project. Close Godot first, then run again." -ForegroundColor Red; exit 1 }
    git fetch --quiet origin $Branch
    Sync-Local (Get-Date -Format "HH:mm:ss")
    exit 0
}

Write-Host "Watching $Repo ($Branch) every $Interval s in $Dir. Close the window to stop." -ForegroundColor Cyan

while ($true) {
    git fetch --quiet origin $Branch 2>$null
    if ($LASTEXITCODE -eq 0) {
        $local  = (git rev-parse HEAD).Trim()
        $remote = (git rev-parse "origin/$Branch").Trim()
        $open = if ($local -ne $remote) { Get-GodotOpen } else { $null }
        if ($open) {
            if (-not $script:WarnedOpen) {
                $n = (git rev-list --count "HEAD..origin/$Branch" 2>$null)
                Write-Host "[$(Get-Date -Format HH:mm:ss)] UPDATE WAITING ($n new commits): $open is open with this project." -ForegroundColor Yellow
                Write-Host "    Close Godot (save your work first) - the update will be pulled right after." -ForegroundColor Yellow
                [console]::Beep(440, 300)
                $script:WarnedOpen = $true
            }
        } elseif ($local -ne $remote) {
            $script:WarnedOpen = $false
            $stamp = Get-Date -Format "HH:mm:ss"
            Sync-Local $stamp
            Write-Host "[$stamp] Updated:" -ForegroundColor Green
            git log --oneline "$local..HEAD" 2>$null | Select-Object -First 10
            [console]::Beep(880, 150)
        }
    } else {
        Write-Host "[$(Get-Date -Format HH:mm:ss)] fetch failed (no internet?), retrying" -ForegroundColor DarkYellow
    }
    Start-Sleep -Seconds $Interval
}
