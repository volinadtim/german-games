@echo off
rem TUI диспетчера: сессии воркеров, живая лента, контекст, ввод задач. Закрытие ни на что не влияет.
chcp 65001 >nul
cargo run --release -q --manifest-path "%~dp0..\..\tools\disp-tui\Cargo.toml" -- --repo "%~dp0..\.."
