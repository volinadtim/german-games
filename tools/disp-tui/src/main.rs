// TUI диспетчера в стиле Gemini CLI: сессии воркеров слева, живая лента выбранной справа,
// контекст каждого агента, ввод задач и команд снизу. Только смотрит файлы — LLM не трогает,
// закрытие/перезапуск TUI ни на что не влияет.
//
//   cargo run --release --manifest-path tools/disp-tui/Cargo.toml        (или scripts\dispatch\tui.bat)
mod data;

use data::{read_json, short_path, tail_lines, Kind, Sess};
use ratatui::crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style, Stylize};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, BorderType, Borders, Paragraph, Wrap};
use ratatui::Frame;
use serde_json::Value;
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
    banner: bool,
    toast: Option<(String, Instant)>,
    jobs: Value,
    log: Vec<String>,
    tick: usize,
    quit: bool,
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
            banner: true,
            toast: None,
            jobs: Value::Null,
            log: vec![],
            tick: 0,
            quit: false,
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
            "/banner" => self.banner = !self.banner,
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
            t if t.starts_with('/') => self.toast("команды: /stop (мягко) /kill (жёстко) /resume /status /banner /q"),
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
            KeyCode::Char('b') if m.contains(KeyModifiers::CONTROL) => self.banner = !self.banner,
            KeyCode::Char('o') if m.contains(KeyModifiers::CONTROL) => self.open_chat(),
            KeyCode::Up | KeyCode::BackTab => self.sel = (self.sel + n - 1) % n,
            KeyCode::Down | KeyCode::Tab => self.sel = (self.sel + 1) % n,
            KeyCode::PageUp => *self.scroll.entry(zone).or_default() += 15,
            KeyCode::PageDown => {
                let s = self.scroll.entry(zone).or_default();
                *s = s.saturating_sub(15);
            }
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

fn lerp(a: Color, b: Color, t: f32) -> Color {
    if let (Color::Rgb(r1, g1, b1), Color::Rgb(r2, g2, b2)) = (a, b) {
        let f = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t) as u8;
        Color::Rgb(f(r1, r2), f(g1, g2), f(b1, b2))
    } else {
        a
    }
}

fn grad(t: f32) -> Color {
    if t < 0.5 { lerp(PINK, VIOLET, t * 2.0) } else { lerp(VIOLET, CYAN, (t - 0.5) * 2.0) }
}

const FONT: &[(char, [&str; 5])] = &[
    ('>', ["█   ", " █  ", "  █ ", " █  ", "█   "]),
    ('D', ["████ ", "█   █", "█   █", "█   █", "████ "]),
    ('I', ["███", " █ ", " █ ", " █ ", "███"]),
    ('S', [" ████", "█    ", " ███ ", "    █", "████ "]),
    ('P', ["████ ", "█   █", "████ ", "█    ", "█    "]),
    ('A', [" ███ ", "█   █", "█████", "█   █", "█   █"]),
    ('T', ["█████", "  █  ", "  █  ", "  █  ", "  █  "]),
    ('C', [" ████", "█    ", "█    ", "█    ", " ████"]),
    ('H', ["█   █", "█   █", "█████", "█   █", "█   █"]),
];

fn banner_lines() -> Vec<Line<'static>> {
    let rows: Vec<String> = (0..5)
        .map(|r| {
            ">DISPATCH"
                .chars()
                .map(|c| FONT.iter().find(|(k, _)| *k == c).map(|(_, g)| format!("{} ", g[r])).unwrap_or_default())
                .collect()
        })
        .collect();
    let w = rows[0].chars().count().max(1) as f32;
    rows.iter()
        .map(|row| {
            Line::from(
                row.chars()
                    .enumerate()
                    .map(|(i, ch)| {
                        if ch == ' ' {
                            Span::raw(" ")
                        } else {
                            Span::styled("█", Style::new().fg(grad(i as f32 / w)))
                        }
                    })
                    .collect::<Vec<_>>(),
            )
        })
        .collect()
}

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
    let show_banner = app.banner && area.height >= 30;
    let [top, mid, inp, status] = Layout::vertical([
        Constraint::Length(if show_banner { 8 } else { 0 }),
        Constraint::Min(5),
        Constraint::Length(3),
        Constraint::Length(1),
    ])
    .areas(area);

    if show_banner {
        let mut l = vec![Line::raw("")];
        l.extend(banner_lines());
        l.push(Line::from(vec![
            Span::styled(" ↑↓/Tab", Style::new().fg(CYAN)),
            Span::styled(" сессии · ", Style::new().fg(DIM)),
            Span::styled("PgUp/PgDn", Style::new().fg(CYAN)),
            Span::styled(" прокрутка · ", Style::new().fg(DIM)),
            Span::styled("Enter", Style::new().fg(CYAN)),
            Span::styled(" задача диспетчеру · ", Style::new().fg(DIM)),
            Span::styled("/stop /kill /resume", Style::new().fg(CYAN)),
            Span::styled(" · ", Style::new().fg(DIM)),
            Span::styled("Ctrl+O", Style::new().fg(CYAN)),
            Span::styled(" чат с агентом · Ctrl+B баннер · Ctrl+Q выход", Style::new().fg(DIM)),
        ]));
        f.render_widget(Paragraph::new(l), top);
    }

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
        let agent = s.agent.trim_start_matches("gd-");
        let zs = if sel { Style::new().fg(Color::White).bold() } else { Style::new().fg(Color::Gray) };
        l.push(Line::from(vec![mark(sel), dot, Span::raw(" "), Span::styled(format!("{:<9}", s.zone), zs), Span::styled(agent.to_string(), Style::new().fg(DIM))]));
        let mut g = vec![mark(sel), Span::raw("  ")];
        g.extend(gauge(s.ctx, 14));
        l.push(Line::from(g));
    }
    let b = Block::new().borders(Borders::ALL).border_type(BorderType::Rounded).border_style(Style::new().fg(DIM)).title(" сессии ");
    f.render_widget(Paragraph::new(l).block(b), area);
}

fn feed_block(title: Line<'static>) -> Block<'static> {
    Block::new().borders(Borders::ALL).border_type(BorderType::Rounded).border_style(Style::new().fg(VIOLET)).title(title)
}

fn render_scrolled(f: &mut Frame, app: &App, key: &str, text: Text, block: Block, area: Rect) {
    let p = Paragraph::new(text).wrap(Wrap { trim: false });
    let inner_w = area.width.saturating_sub(2);
    let inner_h = area.height.saturating_sub(2) as usize;
    let total = p.line_count(inner_w);
    let back = *app.scroll.get(key).unwrap_or(&0) as usize;
    let max = total.saturating_sub(inner_h);
    let y = max.saturating_sub(back);
    let mut block = block;
    if back > 0 {
        block = block.title_bottom(Line::styled(format!(" ↑ прокрутка {} · End — к хвосту ", back.min(max)), Style::new().fg(YELLOW)).right_aligned());
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
        Span::styled(format!("· {} · {} · ", s.agent, model), Style::new().fg(DIM)),
        Span::styled(format!("ctx {}k/{}k", s.ctx / 1000, WINDOW / 1000), Style::new().fg(ctx_color(s.ctx))),
    ];
    if !s.title.is_empty() {
        title.push(Span::styled(format!(" · {} ", cut(&s.title, 60)), Style::new().fg(Color::White)));
    }
    render_scrolled(f, app, &s.zone, Text::from(lines), feed_block(Line::from(title)), area);
}

fn draw_dispatcher(f: &mut Frame, app: &App, area: Rect) {
    let mut lines: Vec<Line> = vec![];
    let jobs = app.jobs();
    if jobs.is_empty() {
        lines.push(Line::styled("  задач в jobs.json нет (или диспетчер старой версии) — ниже лог", Style::new().fg(DIM)));
    } else {
        lines.push(Line::styled(
            format!("  {:<3} {:<11} {:<8} {:<9} {:<11} {:>6} {:>5} {:>6}  задача → результат", "#", "промпт", "зона", "агент", "статус", "время", "ктх", "$"),
            Style::new().fg(DIM),
        ));
        for j in jobs.iter().rev().take(25).collect::<Vec<_>>().into_iter().rev() {
            let st = j["status"].as_str().unwrap_or("");
            let c = match st {
                "работает" => GREEN,
                "очередь" | "пауза" => YELLOW,
                "упал" | "ошибка" | "прерван" | "СЛОЖНО" => RED,
                _ => Color::Gray,
            };
            let ctx = j["ctx"].as_u64().map(|x| format!("{}k", x / 1000)).unwrap_or_default();
            let cost = j["cost"].as_f64().map(|x| format!("{x:.2}")).unwrap_or_default();
            let res = j["result"].as_str().unwrap_or("");
            let title = j["title"].as_str().unwrap_or("");
            lines.push(Line::from(vec![
                Span::styled(
                    format!(
                        "  {:<3} {:<11} {:<8} {:<9} ",
                        j["id"].as_u64().unwrap_or(0),
                        cut(j["at"].as_str().unwrap_or(""), 11),
                        j["zone"].as_str().unwrap_or(""),
                        j["agent"].as_str().unwrap_or("")
                    ),
                    Style::new().fg(Color::Gray),
                ),
                Span::styled(format!("{:<11} ", st), Style::new().fg(c)),
                Span::styled(format!("{:>6} {:>5} {:>6}  ", j["dur"].as_str().unwrap_or(""), ctx, cost), Style::new().fg(DIM)),
                Span::raw(cut(title, 70)),
                Span::styled(if res.is_empty() { String::new() } else { format!(" → {}", cut(res, 120)) }, Style::new().fg(DIM)),
            ]));
        }
    }
    lines.push(Line::raw(""));
    lines.push(Line::styled("  ЛОГ", Style::new().fg(VIOLET).bold()));
    for l in &app.log {
        let c = if l.contains("упал") || l.contains("ошибка") || l.contains("прерван") { RED } else { Color::Gray };
        lines.push(Line::styled(format!("  {l}"), Style::new().fg(c)));
    }
    let (st, col) = app.disp_state();
    let title = Line::from(vec![
        Span::styled(" диспетчер ", Style::new().fg(PINK).bold()),
        Span::styled(format!("· {st} "), Style::new().fg(col)),
    ]);
    render_scrolled(f, app, "", Text::from(lines), feed_block(title), area);
}

fn draw_input(f: &mut Frame, app: &App, area: Rect) {
    let b = Block::new().borders(Borders::ALL).border_type(BorderType::Rounded).border_style(Style::new().fg(CYAN));
    let inner = b.inner(area);
    let line = if app.input.is_empty() {
        Line::from(vec![Span::styled("> ", Style::new().fg(PINK).bold()), Span::styled("Задача для диспетчера или /stop /kill /resume /status", Style::new().fg(DIM))])
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
    let mut last = Instant::now();
    let res = (|| -> std::io::Result<()> {
        while !app.quit {
            term.draw(|f| draw(f, &app))?;
            if event::poll(Duration::from_millis(120))? {
                if let Event::Key(k) = event::read()? {
                    if k.kind == KeyEventKind::Press {
                        app.key(k.code, k.modifiers);
                    }
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
    ratatui::restore();
    res
}
