// Источники данных TUI — только чтение файлов, ни одного обращения к LLM:
//   ~/.claude/projects/<worktree disp-зона>/*.jsonl — транскрипты воркеров (живая лента, контекст)
//   <repo>/.claude/dispatch/jobs.json              — очередь/статусы/пульс диспетчера
//   <repo>/.claude/dispatch/dispatch.log           — лог диспетчера
use serde_json::Value;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

pub const MAX_ENTRIES: usize = 3000;

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    User,
    Text,
    Tool,
    Result,
    Err,
}

pub struct Entry {
    pub ts: String,
    pub kind: Kind,
    pub text: String,
}

pub struct Sess {
    pub zone: String,
    pub dir: PathBuf,
    pub file: Option<PathBuf>,
    offset: u64,
    partial: Vec<u8>,
    pub entries: Vec<Entry>,
    pub ctx: u64,
    pub model: String,
    pub title: String,
    pub agent: String,
    pub last_mod: Option<SystemTime>,
    pub sid: String,
}

impl Sess {
    pub fn new(zone: String, dir: PathBuf) -> Self {
        Sess {
            zone,
            dir,
            file: None,
            offset: 0,
            partial: vec![],
            entries: vec![],
            ctx: 0,
            model: String::new(),
            title: String::new(),
            agent: String::new(),
            last_mod: None,
            sid: String::new(),
        }
    }

    /// Дочитать новые строки самого свежего транскрипта зоны (инкрементально, по смещению).
    pub fn update(&mut self) {
        let newest = fs::read_dir(&self.dir)
            .ok()
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.path().extension().map_or(false, |x| x == "jsonl"))
            .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
            .max_by_key(|(t, _)| *t);
        let Some((mtime, path)) = newest else { return };
        if self.file.as_ref() != Some(&path) {
            let (z, d) = (self.zone.clone(), self.dir.clone());
            *self = Sess::new(z, d);
            self.sid = path.file_stem().unwrap_or_default().to_string_lossy().into();
            self.file = Some(path.clone());
        }
        self.last_mod = Some(mtime);
        let Ok(mut f) = fs::File::open(&path) else { return };
        let len = f.metadata().map(|m| m.len()).unwrap_or(0);
        if len < self.offset {
            self.offset = 0;
            self.partial.clear();
            self.entries.clear();
        }
        if len == self.offset {
            return;
        }
        if f.seek(SeekFrom::Start(self.offset)).is_err() {
            return;
        }
        let mut buf = Vec::new();
        if f.read_to_end(&mut buf).is_err() {
            return;
        }
        self.offset += buf.len() as u64;
        self.partial.extend_from_slice(&buf);
        let data = std::mem::take(&mut self.partial);
        let mut start = 0;
        for (i, b) in data.iter().enumerate() {
            if *b == b'\n' {
                if let Ok(v) = serde_json::from_slice::<Value>(&data[start..i]) {
                    self.parse(&v);
                }
                start = i + 1;
            }
        }
        self.partial = data[start..].to_vec();
        if self.entries.len() > MAX_ENTRIES {
            let cut = self.entries.len() - MAX_ENTRIES;
            self.entries.drain(..cut);
        }
    }

    fn push(&mut self, ts: &str, kind: Kind, text: String) {
        if !text.trim().is_empty() {
            self.entries.push(Entry { ts: ts.to_string(), kind, text });
        }
    }

    fn parse(&mut self, v: &Value) {
        let ts = msk_time(v["timestamp"].as_str().unwrap_or(""));
        match v["type"].as_str().unwrap_or("") {
            "ai-title" => self.title = s(&v["aiTitle"]),
            "agent-setting" => self.agent = s(&v["agentSetting"]),
            "assistant" => {
                let m = &v["message"];
                if let Some(model) = m["model"].as_str() {
                    self.model = model.to_string();
                }
                let u = &m["usage"];
                let ctx = u["input_tokens"].as_u64().unwrap_or(0)
                    + u["cache_read_input_tokens"].as_u64().unwrap_or(0)
                    + u["cache_creation_input_tokens"].as_u64().unwrap_or(0);
                if ctx > 0 {
                    self.ctx = ctx;
                }
                for c in m["content"].as_array().into_iter().flatten() {
                    match c["type"].as_str().unwrap_or("") {
                        "text" => self.push(&ts, Kind::Text, s(&c["text"])),
                        "tool_use" => {
                            let name = s(&c["name"]);
                            let d = tool_detail(&name, &c["input"]);
                            self.push(&ts, Kind::Tool, format!("{name}\u{1f}{d}"));
                        }
                        _ => {}
                    }
                }
            }
            "user" => {
                if v["isMeta"].as_bool() == Some(true) {
                    return;
                }
                let c = &v["message"]["content"];
                if let Some(t) = c.as_str() {
                    self.push(&ts, Kind::User, t.to_string());
                }
                for c in c.as_array().into_iter().flatten() {
                    match c["type"].as_str().unwrap_or("") {
                        "text" => self.push(&ts, Kind::User, s(&c["text"])),
                        "tool_result" => {
                            let text = match &c["content"] {
                                Value::String(t) => t.clone(),
                                Value::Array(a) => a
                                    .iter()
                                    .filter_map(|x| x["text"].as_str())
                                    .collect::<Vec<_>>()
                                    .join("\n"),
                                _ => String::new(),
                            };
                            let k = if c["is_error"].as_bool() == Some(true) { Kind::Err } else { Kind::Result };
                            self.push(&ts, k, if text.is_empty() { "(пусто)".into() } else { text });
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or("").to_string()
}

/// "2026-11-17T22:46:56.516Z" -> "01:46:56" (МСК = UTC+3).
fn msk_time(t: &str) -> String {
    if t.len() < 19 {
        return String::new();
    }
    let h: u32 = t[11..13].parse().unwrap_or(0);
    format!("{:02}{}", (h + 3) % 24, &t[13..19])
}

pub fn short_path(p: &str) -> String {
    let p = p.replace('\\', "/");
    if let Some(i) = p.find("/godot/") {
        return p[i + 1..].to_string();
    }
    let parts: Vec<&str> = p.rsplit('/').take(3).collect();
    parts.into_iter().rev().collect::<Vec<_>>().join("/")
}

fn tool_detail(name: &str, i: &Value) -> String {
    let g = |k: &str| i[k].as_str().map(|x| x.to_string());
    match name {
        "Bash" | "PowerShell" => match (g("description"), g("command")) {
            (Some(d), Some(c)) => format!("{d}  $ {c}"),
            (d, c) => d.or(c).unwrap_or_default(),
        },
        "Read" | "Edit" | "Write" | "MultiEdit" | "NotebookEdit" => g("file_path").map(|p| short_path(&p)).unwrap_or_default(),
        "Grep" | "Glob" => {
            let mut s = g("pattern").unwrap_or_default();
            if let Some(p) = g("path") {
                s += &format!("  in {}", short_path(&p));
            }
            s
        }
        _ => ["description", "prompt", "query", "url", "skill", "command"]
            .iter()
            .find_map(|k| g(k))
            .or_else(|| i.as_object()?.values().find_map(|v| v.as_str().map(|x| x.to_string())))
            .unwrap_or_default(),
    }
}

pub fn read_json(p: &Path) -> Option<Value> {
    let t = fs::read_to_string(p).ok()?;
    serde_json::from_str(t.trim_start_matches('\u{feff}')).ok()
}

pub fn tail_lines(p: &Path, n: usize) -> Vec<String> {
    let t = fs::read_to_string(p).unwrap_or_default();
    let mut out: Vec<String> = Vec::new();
    // строки лога, переносы внутри записи склеиваем
    for l in t.lines() {
        let starts = l.len() > 15 && l.as_bytes()[2] == b'.' && l.as_bytes()[5] == b' ';
        match out.last_mut() {
            Some(last) if !starts => {
                last.push(' ');
                last.push_str(l.trim());
            }
            _ => out.push(l.to_string()),
        }
    }
    let k = out.len().saturating_sub(n);
    out.split_off(k)
}
