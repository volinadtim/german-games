// TUI диспетчера в стиле Gemini CLI: сессии воркеров слева, живая лента выбранной справа,
// контекст каждого агента, ввод задач и команд снизу. Только смотрит файлы — LLM не трогает,
// закрытие/перезапуск TUI ни на что не влияет.
//
//   cargo run --release --manifest-path tools/disp-tui/Cargo.toml        (или scripts\dispatch\tui.bat)
mod data;

use data::{read_json, short_path, tail_lines, Kind, Sess};
use ratatui::crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style, Stylize};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, BorderType, Borders, Padding, Paragraph, Wrap};
use ratatui::Frame;
use serde_json::Value;
use std::cell::Cell;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const WINDOW: u64 = 200_000; // окно контекста
const ROTATE: u64 = 150_000; // после этого диспетчер берёт нового агента

const PINK: Color = Color::Rgb(244, 114, 182);
const VIOLET: Color = Color::Rgb(167, 139, 250);
const CYAN: Color = Color::Rgb(103, 232, 249);
const DIM: Color = Color::Rgb(110, 110, 125);
const GREEN: Color = Color::Rgb(134, 239, 172);
const YELLOW: Color = Color::Rgb(253, 224, 71);
const RED: Color = Color::Rgb(248, 113, 113);

struct App {
    repo: PathBuf,
    ddir: PathBuf,
    proj_root: PathBuf,
    prefix: String,
    sessions: Vec<Sess>,
    sel: usize, // 0 — диспетчер, 1.. — сессии
    input: Vec<char>,
    cur: usize,
    scroll: HashMap<String, u16>, // строк от низа; 0 — следить за хвостом
    toast: Option<(String, Instant)>,
    jobs: Value,
    log: Vec<String>,
    tick: usize,
    quit: bool,
    list_area: Cell<Rect>,  // где нарисован список сессий (для клика мышью)
    max_scroll: Cell<u16>,  // сколько строк можно прокрутить вверх в текущей ленте
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn mangle(p: &str) -> String {
    p.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect()
}

fn find_repo() -> PathBuf {
    let args: Vec<String> = std::env::args().collect();
    if let Some(i) = args.iter().position(|a| a == "--repo") {
        if let Some(p) = args.get(i + 1) {
            return PathBuf::from(p);
        }
    }
    let out = std::process::Command::new("git")
        .args(["rev-parse", "--path-format=absolute", "--git-common-dir"])
        .output();
    if let Ok(o) = out {
        let s = String::from_utf8_lossy(&o.stdout).trim().replace('/', "\\");
        if let Some(parent) = PathBuf::from(s).parent() {
            if parent.join(".git").exists() {
                return parent.to_path_buf();
            }
        }
    }
    std::env::current_dir().unwrap_or_default()
}

impl App {
    fn new() -> Self {
        let repo = find_repo();
        let home = std::env::var("USERPROFILE").or_else(|_| std::env::var("HOME")).unwrap_or_default();
        let wt = repo.join(".claude").join("worktrees").join("disp-");
        App {
            ddir: repo.join(".claude").join("dispatch"),
            prefix: mangle(&wt.to_string_lossy()),
            proj_root: PathBuf::from(home).join(".claude").join("projects"),
            repo,
            sessions: vec![],
            sel: 0,
            input: vec![],
            cur: 0,
            scroll: HashMap::new(),
            toast: None,
            jobs: Value::Null,
            log: vec![],
            tick: 0,
            quit: false,
            list_area: Cell::new(Rect::default()),
            max_scroll: Cell::new(0),
        }
    }

    fn refresh(&mut self) {
        if let Ok(rd) = std::fs::read_dir(&self.proj_root) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                if let Some(zone) = name.strip_prefix(&self.prefix) {
                    if !zone.is_empty() && !self.sessions.iter().any(|s| s.zone == zone) {
                        self.sessions.push(Sess::new(zone.to_string(), e.path()));
                    }
                }
            }
        }
        let sel_zone = self.sel_zone();
        self.sessions.sort_by(|a, b| a.zone.cmp(&b.zone));
        if let Some(z) = sel_zone {
            self.sel = 1 + self.sessions.iter().position(|s| s.zone == z).unwrap_or(0);
        }
        for s in &mut self.sessions {
            s.update();
        }
        if let Some(j) = read_json(&self.ddir.join("jobs.json")) {
            self.jobs = j;
        }
        self.log = tail_lines(&self.ddir.join("dispatch.log"), 200);
    }

    fn sel_zone(&self) -> Option<String> {
        if self.sel == 0 { None } else { self.sessions.get(self.sel - 1).map(|s| s.zone.clone()) }
    }

    /// Уровень размышлений последней задачи зоны (low/medium/high/xhigh/max).
    fn effort(&self, zone: &str) -> String {
        self.jobs().iter().rev().find(|j| j["zone"].as_str() == Some(zone)).and_then(|j| j["effort"].as_str()).unwrap_or("").to_string()
    }

    fn jobs(&self) -> Vec<&Value> {
        self.jobs["jobs"].as_array().map(|a| a.iter().collect()).unwrap_or_default()
    }

    /// Работающая задача зоны (по jobs.json; для старого диспетчера — по пустому <зона>.out.json).
    fn running(&self, s: &Sess) -> Option<String> {
        if self.jobs.is_object() {
            return self
                .jobs()
                .into_iter()
                .find(|j| j["status"] == "работает" && j["zone"] == s.zone.as_str())
                .map(|j| j["title"].as_str().unwrap_or("").to_string());
        }
        let out = self.ddir.join(format!("{}.out.json", s.zone));
        let empty = std::fs::metadata(&out).map(|m| m.len() == 0).unwrap_or(false);
        let fresh = s.last_mod.and_then(|t| t.elapsed().ok()).map_or(false, |d| d.as_secs() < 600);
        (empty && fresh).then(|| s.title.clone())
    }

    fn disp_state(&self) -> (String, Color) {
        if !self.jobs.is_object() {
            return ("старая версия (нет jobs.json)".into(), YELLOW);
        }
        let age = now().saturating_sub(self.jobs["heartbeat"].as_u64().unwrap_or(0));
        let stop = self.jobs["stop"].as_str().unwrap_or("");
        if age > 20 {
            ("не запущен".into(), DIM)
        } else if stop == "stop" {
            ("мягкий СТОП".into(), YELLOW)
        } else if stop == "kill" {
            ("жёсткий СТОП".into(), RED)
        } else {
            ("слушает TG".into(), GREEN)
        }
    }

    fn toast(&mut self, s: impl Into<String>) {
        self.toast = Some((s.into(), Instant::now()));
    }

    fn submit(&mut self) {
        let text: String = self.input.iter().collect();
        let text = text.trim().to_string();
        self.input.clear();
        self.cur = 0;
        if text.is_empty() {
            return;
        }
        match text.as_str() {
            "/q" | "/quit" | "/exit" => self.quit = true,
            "/stop" | "/kill" | "/resume" | "/status" => {
                let ctl = self.repo.join("scripts").join("dispatch").join("ctl.ps1");
                let out = std::process::Command::new("powershell")
                    .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
                    .arg(&ctl)
                    .arg(&text[1..])
                    .output();
                match out {
                    Ok(o) => {
                        let s = String::from_utf8_lossy(&o.stdout).trim().replace("\r\n", " · ").replace('\n', " · ");
                        self.toast(if s.is_empty() { String::from_utf8_lossy(&o.stderr).trim().to_string() } else { s });
                    }
                    Err(e) => self.toast(format!("ctl.ps1: {e}")),
                }
            }
            t if t.starts_with('/') => self.toast("команды: /stop (мягко) /kill (жёстко) /resume /status /q"),
            _ => {
                let inbox = self.ddir.join("inbox");
                let _ = std::fs::create_dir_all(&inbox);
                let ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0);
                match std::fs::write(inbox.join(format!("{ms}.txt")), text.as_bytes()) {
                    Ok(_) => {
                        let (st, _) = self.disp_state();
                        self.toast(if st == "не запущен" || st.starts_with("старая") {
                            format!("задача в inbox — диспетчер {st}, возьмёт после запуска")
                        } else {
                            "задача отправлена диспетчеру".to_string()
                        });
                    }
                    Err(e) => self.toast(format!("не записал inbox: {e}")),
                }
            }
        }
    }

    /// Ctrl+O: открыть интерактивный чат с агентом выбранной зоны (`claude --resume <сессия>`) в новом окне.
    /// Пока окно открыто, лежит chat-<зона>.lock — диспетчер не стартует воркеров этой зоны.
    fn open_chat(&mut self) {
        let Some(s) = self.sel.checked_sub(1).and_then(|i| self.sessions.get(i)) else {
            return self.toast("выбери сессию агента (↑↓), потом Ctrl+O");
        };
        if self.running(s).is_some() {
            return self.toast("агент сейчас работает — дождись конца задачи или /stop, потом Ctrl+O");
        }
        if s.sid.is_empty() {
            return self.toast("у зоны нет сессии");
        }
        let wt = self.repo.join(".claude").join("worktrees").join(format!("disp-{}", s.zone));
        let lock = self.ddir.join(format!("chat-{}.lock", s.zone));
        let agent = if s.agent.is_empty() { String::new() } else { format!(" --agent {}", s.agent) };
        let script = format!(
            "echo chat> \"{lock}\" & claude --resume {sid}{agent} & del \"{lock}\"",
            lock = lock.display(),
            sid = s.sid
        );
        let r = std::process::Command::new("cmd")
            .args(["/c", "start", &format!("чат {}", s.zone), "cmd", "/c", &script])
            .current_dir(&wt)
            .spawn();
        let msg = match r {
            Ok(_) => format!("открыл чат с агентом {} — пока окно открыто, диспетчер эту зону не трогает", s.zone),
            Err(e) => format!("не открыл чат: {e}"),
        };
        self.toast(msg);
    }

    /// Прокрутка ленты: d > 0 — вверх (к старому), d < 0 — вниз; 0 от низа = следить за хвостом.
    fn scroll_by(&mut self, d: i32) {
        let zone = self.sel_zone().unwrap_or_default();
        let max = self.max_scroll.get() as i32;
        let s = self.scroll.entry(zone).or_default();
        *s = (*s as i32 + d).clamp(0, max) as u16;
    }

    fn mouse(&mut self, kind: MouseEventKind, x: u16, y: u16) {
        match kind {
            MouseEventKind::ScrollUp => self.scroll_by(3),
            MouseEventKind::ScrollDown => self.scroll_by(-3),
            MouseEventKind::Down(MouseButton::Left) => {
                // клик по списку слева: 2 строки на диспетчер, пустая, дальше по 2 строки на сессию
                let a = self.list_area.get();
                if x < a.x || x >= a.right() || y <= a.y || y + 1 >= a.bottom() {
                    return;
                }
                let r = (y - a.y - 1) as usize;
                if r < 2 {
                    self.sel = 0;
                } else if r >= 3 && (r - 3) / 2 < self.sessions.len() {
                    self.sel = (r - 3) / 2 + 1;
                }
            }
            _ => {}
        }
    }

    fn key(&mut self, code: KeyCode, m: KeyModifiers) {
        let n = self.sessions.len() + 1;
        let zone = self.sel_zone().unwrap_or_default();
        match code {
            KeyCode::Char('c') | KeyCode::Char('q') if m.contains(KeyModifiers::CONTROL) => {
                if code == KeyCode::Char('c') && !self.input.is_empty() {
                    self.input.clear();
                    self.cur = 0;
                } else {
                    self.quit = true;
                }
            }
            KeyCode::Char('o') if m.contains(KeyModifiers::CONTROL) => self.open_chat(),
            KeyCode::Up => self.sel = (self.sel + n - 1) % n,
            KeyCode::Down => self.sel = (self.sel + 1) % n,
            KeyCode::PageUp => self.scroll_by(15),
            KeyCode::PageDown => self.scroll_by(-15),
            KeyCode::End if self.input.is_empty() => {
                self.scroll.insert(zone, 0);
            }
            KeyCode::Home => self.cur = 0,
            KeyCode::End => self.cur = self.input.len(),
            KeyCode::Left => self.cur = self.cur.saturating_sub(1),
            KeyCode::Right => self.cur = (self.cur + 1).min(self.input.len()),
            KeyCode::Backspace if self.cur > 0 => {
                self.cur -= 1;
                self.input.remove(self.cur);
            }
            KeyCode::Delete if self.cur < self.input.len() => {
                self.input.remove(self.cur);
            }
            KeyCode::Esc => {
                self.input.clear();
                self.cur = 0;
            }
            KeyCode::Enter => self.submit(),
            KeyCode::Char(c) if !m.contains(KeyModifiers::CONTROL) => {
                self.input.insert(self.cur, c);
                self.cur += 1;
            }
            _ => {}
        }
    }
}

// ---------- отрисовка ----------

fn ctx_color(ctx: u64) -> Color {
    if ctx >= ROTATE { RED } else if ctx >= 100_000 { YELLOW } else { GREEN }
}

fn gauge(ctx: u64, cells: usize) -> Vec<Span<'static>> {
    let filled = ((ctx as f64 / WINDOW as f64) * cells as f64).round().min(cells as f64) as usize;
    vec![
        Span::styled("▰".repeat(filled), Style::new().fg(ctx_color(ctx))),
        Span::styled("▱".repeat(cells - filled), Style::new().fg(DIM)),
        Span::styled(format!(" {:>3}k", ctx / 1000), Style::new().fg(ctx_color(ctx))),
    ]
}

const SPIN: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

fn cut(s: &str, n: usize) -> String {
    let s: String = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if s.chars().count() > n {
        s.chars().take(n.saturating_sub(1)).collect::<String>() + "…"
    } else {
        s
    }
}

fn draw(f: &mut Frame, app: &App) {
    let area = f.area();
    let [mid, inp, status] = Layout::vertical([
        Constraint::Min(5),
        Constraint::Length(3),
        Constraint::Length(1),
    ])
    .areas(area);

    let [left, right] = Layout::horizontal([Constraint::Length(32), Constraint::Min(20)]).areas(mid);
    draw_list(f, app, left);
    if app.sel == 0 {
        draw_dispatcher(f, app, right);
    } else if let Some(s) = app.sessions.get(app.sel - 1) {
        draw_session(f, app, s, right);
    }
    draw_input(f, app, inp);
    draw_status(f, app, status);
}

fn draw_list(f: &mut Frame, app: &App, area: Rect) {
    let mut l: Vec<Line> = vec![];
    let (st, col) = app.disp_state();
    let mark = |sel: bool| if sel { Span::styled("▌", Style::new().fg(PINK)) } else { Span::raw(" ") };
    l.push(Line::from(vec![
        mark(app.sel == 0),
        Span::styled("◆ диспетчер", Style::new().fg(VIOLET).add_modifier(Modifier::BOLD)),
    ]));
    l.push(Line::from(vec![mark(app.sel == 0), Span::styled(format!("  {st}"), Style::new().fg(col))]));
    l.push(Line::raw(""));
    for (i, s) in app.sessions.iter().enumerate() {
        let sel = app.sel == i + 1;
        let run = app.running(s);
        let dot = if run.is_some() {
            Span::styled(SPIN[app.tick % SPIN.len()], Style::new().fg(GREEN))
        } else {
            Span::styled("○", Style::new().fg(DIM))
        };
        let eff = app.effort(&s.zone);
        let agent = if eff.is_empty() { s.agent.trim_start_matches("gd-").to_string() } else { format!("{}/{}", s.agent.trim_start_matches("gd-"), eff) };
        let zs = if sel { Style::new().fg(Color::White).bold() } else { Style::new().fg(Color::Gray) };
        l.push(Line::from(vec![mark(sel), dot, Span::raw(" "), Span::styled(format!("{:<9}", s.zone), zs), Span::styled(agent, Style::new().fg(DIM))]));
        let mut g = vec![mark(sel), Span::raw("  ")];
        g.extend(gauge(s.ctx, 14));
        l.push(Line::from(g));
    }
    let b = Block::new().borders(Borders::ALL).border_type(BorderType::Rounded).border_style(Style::new().fg(DIM)).title(" сессии ");
    app.list_area.set(area);
    f.render_widget(Paragraph::new(l).block(b), area);
}

// Лента без рамки: на месте рамки пустое поле той же ширины, заголовок — в верхней строке.
fn feed_block(title: Line<'static>) -> Block<'static> {
    Block::new().padding(Padding::new(1, 1, 0, 1)).title(title)
}

fn render_scrolled(f: &mut Frame, app: &App, key: &str, text: Text, block: Block, area: Rect) {
    let p = Paragraph::new(text).wrap(Wrap { trim: false });
    let inner = block.inner(area);
    let total = p.line_count(inner.width);
    let max = total.saturating_sub(inner.height as usize);
    app.max_scroll.set(max.min(u16::MAX as usize) as u16);
    let back = (*app.scroll.get(key).unwrap_or(&0) as usize).min(max);
    let y = max - back;
    let mut block = block;
    if back > 0 {
        block = block.title(Line::styled(format!(" ↑ прокрутка {back} · End — к хвосту "), Style::new().fg(YELLOW)).right_aligned());
    }
    f.render_widget(p.block(block).scroll((y.min(u16::MAX as usize) as u16, 0)), area);
}

fn draw_session(f: &mut Frame, app: &App, s: &Sess, area: Rect) {
    let mut lines: Vec<Line> = vec![];
    let tsw = |ts: &str| Span::styled(format!("{} ", ts.get(..5).unwrap_or("")), Style::new().fg(DIM));
    for e in &s.entries {
        match e.kind {
            Kind::User => {
                for (i, t) in e.text.lines().take(12).enumerate() {
                    let pre = if i == 0 { tsw(&e.ts) } else { Span::raw("      ") };
                    lines.push(Line::from(vec![pre, Span::styled(if i == 0 { "› " } else { "  " }, Style::new().fg(PINK).bold()), Span::styled(t.to_string(), Style::new().fg(PINK))]));
                }
                lines.push(Line::raw(""));
            }
            Kind::Text => {
                for (i, t) in e.text.lines().enumerate() {
                    let pre = if i == 0 { tsw(&e.ts) } else { Span::raw("      ") };
                    lines.push(Line::from(vec![pre, Span::styled(if i == 0 { "✦ " } else { "  " }, Style::new().fg(VIOLET)), Span::raw(t.to_string())]));
                }
            }
            Kind::Tool => {
                let (name, d) = e.text.split_once('\u{1f}').unwrap_or((&e.text, ""));
                lines.push(Line::from(vec![
                    tsw(&e.ts),
                    Span::styled("⏺ ", Style::new().fg(CYAN)),
                    Span::styled(name.to_string(), Style::new().fg(CYAN).bold()),
                    Span::styled(format!("  {}", cut(d, 300)), Style::new().fg(Color::Gray)),
                ]));
            }
            Kind::Result | Kind::Err => {
                let n = e.text.lines().count();
                let first = cut(e.text.lines().find(|l| !l.trim().is_empty()).unwrap_or(""), 200);
                let more = if n > 1 { format!("  (+{} стр.)", n - 1) } else { String::new() };
                let c = if e.kind == Kind::Err { RED } else { DIM };
                lines.push(Line::from(vec![Span::raw("      "), Span::styled(format!("  ⎿ {first}{more}"), Style::new().fg(c))]));
            }
        }
    }
    if lines.is_empty() {
        lines.push(Line::styled("  (транскрипт пуст)", Style::new().fg(DIM)));
    }
    if let Some(t) = app.running(s) {
        lines.push(Line::raw(""));
        lines.push(Line::from(vec![
            Span::styled(format!("  {} ", SPIN[app.tick % SPIN.len()]), Style::new().fg(GREEN)),
            Span::styled(format!("работает: {}", cut(&t, 120)), Style::new().fg(GREEN).italic()),
        ]));
    }
    let model = s.model.trim_start_matches("claude-");
    let mut title = vec![
        Span::styled(format!(" {} ", s.zone), Style::new().fg(PINK).bold()),
        Span::styled(format!("· {} · {} · размышления {} · ", s.agent, model, { let e = app.effort(&s.zone); if e.is_empty() { "?".to_string() } else { e } }), Style::new().fg(DIM)),
        Span::styled(format!("ctx {}k/{}k", s.ctx / 1000, WINDOW / 1000), Style::new().fg(ctx_color(s.ctx))),
    ];
    if !s.title.is_empty() {
        title.push(Span::styled(format!(" · {} ", cut(&s.title, 60)), Style::new().fg(Color::White)));
    }
    render_scrolled(f, app, &s.zone, Text::from(lines), feed_block(Line::from(title)), area);
}

fn status_style(st: &str) -> (Color, &'static str) {
    match st {
        "работает" => (GREEN, "●"),
        "очередь" => (YELLOW, "◌"),
        "пауза" => (YELLOW, "‖"),
        "готово" | "возобновлён" => (CYAN, "✓"),
        "упал" | "ошибка" | "прерван" | "СЛОЖНО" => (RED, "✗"),
        _ => (Color::Gray, "·"),
    }
}

fn draw_dispatcher(f: &mut Frame, app: &App, area: Rect) {
    let mut lines: Vec<Line> = vec![];
    let jobs = app.jobs();
    let width = area.width.saturating_sub(2) as usize;

    // сводка
    let count = |st: &[&str]| jobs.iter().filter(|j| st.contains(&j["status"].as_str().unwrap_or(""))).count();
    let cost: f64 = jobs.iter().filter_map(|j| j["cost"].as_f64()).sum();
    let chip = |n: usize, label: &str, c: Color| {
        vec![
            Span::styled(format!(" {n} "), Style::new().fg(Color::Black).bg(c).bold()),
            Span::styled(format!(" {label}   "), Style::new().fg(c)),
        ]
    };
    let mut sum = vec![];
    sum.extend(chip(count(&["работает"]), "работают", GREEN));
    sum.extend(chip(count(&["очередь", "пауза"]), "ждут", YELLOW));
    sum.extend(chip(count(&["готово", "возобновлён"]), "готово", CYAN));
    sum.extend(chip(count(&["упал", "ошибка", "прерван", "СЛОЖНО"]), "сбой", RED));
    sum.push(Span::styled(format!("${cost:.2} за {} задач", jobs.len()), Style::new().fg(DIM)));
    lines.push(Line::from(sum));
    lines.push(Line::raw(""));

    if jobs.is_empty() {
        lines.push(Line::styled("задач пока нет (или диспетчер старой версии)", Style::new().fg(DIM)));
    }
    // карточки промптов, новые внизу — как в чате
    for j in jobs.iter().rev().take(30).collect::<Vec<_>>().into_iter().rev() {
        let st = j["status"].as_str().unwrap_or("");
        let (c, icon) = status_style(st);
        let g = |k: &str| j[k].as_str().unwrap_or("").to_string();
        lines.push(Line::styled("─".repeat(width), Style::new().fg(Color::Rgb(55, 55, 65))));
        let mut head = vec![
            Span::styled(format!(" {icon} {} ", st.to_uppercase()), Style::new().fg(Color::Black).bg(c).bold()),
            Span::styled(format!("  #{}  ", j["id"].as_u64().unwrap_or(0)), Style::new().fg(Color::White).bold()),
            Span::styled(format!("{}  ", g("at")), Style::new().fg(DIM)),
            Span::styled(g("zone"), Style::new().fg(PINK).bold()),
            Span::styled(
                format!(" · {}{} · {}", g("agent"), if g("effort").is_empty() { String::new() } else { format!("/{}", g("effort")) }, if j["resume"].is_string() { "возобновление" } else if g("mode") == "continue" { "продолжение" } else { "новый" }),
                Style::new().fg(DIM),
            ),
        ];
        let mut meta = vec![];
        if !g("dur").is_empty() {
            meta.push(format!("⏱ {}", g("dur")));
        }
        if let Some(x) = j["ctx"].as_u64() {
            meta.push(format!("ctx {}k", x / 1000));
        }
        if let Some(x) = j["cost"].as_f64() {
            meta.push(format!("${x:.2}"));
        }
        if !meta.is_empty() {
            head.push(Span::styled(format!("   {}", meta.join("  ")), Style::new().fg(DIM)));
        }
        lines.push(Line::from(head));
        lines.push(Line::from(vec![Span::styled("   ", Style::new()), Span::styled(g("title"), Style::new().fg(Color::White).bold())]));
        let text = g("text");
        for t in text.lines().filter(|l| !l.trim().is_empty()).take(6) {
            lines.push(Line::from(vec![Span::styled("   │ ", Style::new().fg(VIOLET)), Span::styled(t.to_string(), Style::new().fg(Color::Gray))]));
        }
        let (rc, rt) = match st {
            "работает" => (GREEN, format!("{} работает…", SPIN[app.tick % SPIN.len()])),
            "очередь" => (YELLOW, "ждёт, пока освободится агент зоны".to_string()),
            _ => (if c == RED { RED } else { Color::Rgb(160, 200, 170) }, g("result")),
        };
        if !rt.is_empty() {
            lines.push(Line::from(vec![Span::styled("   ╰ ", Style::new().fg(rc)), Span::styled(rt, Style::new().fg(rc))]));
        }
        lines.push(Line::raw(""));
    }

    lines.push(Line::styled("─".repeat(width), Style::new().fg(Color::Rgb(55, 55, 65))));
    lines.push(Line::styled("ЛОГ", Style::new().fg(VIOLET).bold()));
    for l in app.log.iter().rev().take(10).collect::<Vec<_>>().into_iter().rev() {
        let c = if l.contains("упал") || l.contains("ошибка") || l.contains("прерван") { RED } else { DIM };
        lines.push(Line::styled(l.clone(), Style::new().fg(c)));
    }
    let (st, col) = app.disp_state();
    let title = Line::from(vec![
        Span::styled(" диспетчер ", Style::new().fg(PINK).bold()),
        Span::styled(format!("· {st}"), Style::new().fg(col)),
    ]);
    render_scrolled(f, app, "", Text::from(lines), feed_block(title), area);
}

fn draw_input(f: &mut Frame, app: &App, area: Rect) {
    let b = Block::new().borders(Borders::ALL).border_type(BorderType::Rounded).border_style(Style::new().fg(CYAN));
    let inner = b.inner(area);
    let line = if app.input.is_empty() {
        Line::from(vec![Span::styled("> ", Style::new().fg(PINK).bold()), Span::styled("задача диспетчеру · /stop /kill /resume · ↑↓ сессии · колесо — прокрутка · Ctrl+O чат · Ctrl+Q выход", Style::new().fg(DIM))])
    } else {
        // горизонтальная прокрутка, чтобы курсор был виден
        let w = inner.width.saturating_sub(3) as usize;
        let start = app.cur.saturating_sub(w);
        let s: String = app.input[start..].iter().take(w + 1).collect();
        Line::from(vec![Span::styled("> ", Style::new().fg(PINK).bold()), Span::raw(s)])
    };
    f.render_widget(Paragraph::new(line).block(b), area);
    let w = inner.width.saturating_sub(3) as usize;
    let cx = inner.x + 2 + (app.cur - app.cur.saturating_sub(w)) as u16;
    f.set_cursor_position((cx.min(inner.right().saturating_sub(1)), inner.y));
}

fn draw_status(f: &mut Frame, app: &App, area: Rect) {
    if let Some((t, at)) = &app.toast {
        if at.elapsed() < Duration::from_secs(8) {
            f.render_widget(Paragraph::new(Line::styled(format!(" {t}"), Style::new().fg(YELLOW))), area);
            return;
        }
    }
    let run = app.sessions.iter().filter(|s| app.running(s).is_some()).count();
    let total: u64 = app.sessions.iter().filter(|s| app.running(s).is_some()).map(|s| s.ctx).sum();
    let queue = app.jobs().iter().filter(|j| j["status"] == "очередь").count();
    let (st, col) = app.disp_state();
    let repo = short_path(&app.repo.to_string_lossy());
    let left = Line::from(vec![
        Span::styled(format!(" {repo} "), Style::new().fg(CYAN)),
        Span::styled("(main)", Style::new().fg(DIM)),
    ]);
    let right = Line::from(vec![
        Span::styled(st, Style::new().fg(col)),
        Span::styled(format!("  ·  работают {run}"), Style::new().fg(GREEN)),
        Span::styled(format!("  ·  очередь {queue}"), Style::new().fg(YELLOW)),
        Span::styled(format!("  ·  ctx активных {}k ", total / 1000), Style::new().fg(VIOLET)),
    ])
    .right_aligned();
    f.render_widget(Paragraph::new(left), area);
    f.render_widget(Paragraph::new(right), area);
}

fn main() -> std::io::Result<()> {
    let mut app = App::new();
    app.refresh();
    let mut term = ratatui::init();
    let _ = ratatui::crossterm::execute!(std::io::stdout(), EnableMouseCapture);
    let mut last = Instant::now();
    let res = (|| -> std::io::Result<()> {
        while !app.quit {
            term.draw(|f| draw(f, &app))?;
            if event::poll(Duration::from_millis(120))? {
                match event::read()? {
                    Event::Key(k) if k.kind == KeyEventKind::Press => app.key(k.code, k.modifiers),
                    Event::Mouse(m) => app.mouse(m.kind, m.column, m.row),
                    _ => {}
                }
            }
            if last.elapsed() >= Duration::from_millis(1000) {
                app.refresh();
                app.tick += 1;
                last = Instant::now();
            }
        }
        Ok(())
    })();
    let _ = ratatui::crossterm::execute!(std::io::stdout(), DisableMouseCapture);
    ratatui::restore();
    res
}
