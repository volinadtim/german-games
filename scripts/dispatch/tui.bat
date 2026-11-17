@echo off
rem TUI диспетчера: сессии воркеров, живая лента, контекст, ввод задач. Закрытие ни на что не влияет.
rem Репо находит сам через git (главный checkout, даже если запущен из worktree).
chcp 65001 >nul
cd /d "%~dp0..\.."
cargo run --release -q --manifest-path tools\disp-tui\Cargo.toml
