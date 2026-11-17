@echo off
rem TUI диспетчера: сессии воркеров, живая лента, контекст, ввод задач. Закрытие ни на что не влияет.
rem Репо находит сам через git (главный checkout, даже если запущен из worktree).
rem Запускается копия exe — пересборка не упирается в уже открытые окна TUI.
chcp 65001 >nul
cd /d "%~dp0..\.."
cargo build --release -q --manifest-path tools\disp-tui\Cargo.toml || exit /b 1
set "EXE=%TEMP%\disp-tui-%RANDOM%%RANDOM%.exe"
copy /y tools\disp-tui\target\release\disp-tui.exe "%EXE%" >nul
"%EXE%"
del "%EXE%" 2>nul
