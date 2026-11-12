//! 应用状态机 + 动作执行（git / sudo darwin-rebuild / $EDITOR / 安装子菜单）。
//! 外部命令一律先 `Term::suspend()` 让出终端，保证 sudo、less、$EDITOR 能正常交互。

use std::env;
use std::fs;
use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use crate::install;
use crate::term::{Key, Term};
use crate::ui;

pub const REPO_DEFAULT: &str = "/etc/nix-darwin";

#[derive(Clone)]
pub struct FileItem {
    pub path: String,
}

pub struct MenuItem {
    pub label: &'static str,
}

pub const MENU: &[MenuItem] = &[
    MenuItem { label: "编辑配置 (全局搜索)" },
    MenuItem { label: "分类浏览编辑 (软件 / shell / system / ...)" },
    MenuItem { label: "rebuild (switch)" },
    MenuItem { label: "查看未提交改动" },
    MenuItem { label: "commit & push" },
    MenuItem { label: "rollback 上一代" },
    MenuItem { label: "安装软件 (nix / brew)" },
    MenuItem { label: "退出" },
];

pub const CATEGORIES: &[(&str, Option<&str>)] = &[
    ("安装软件 (packages / homebrew)", Some("@install")),
    ("shell", Some("modules/shell")),
    ("system", Some("modules/system")),
    ("programs", Some("modules/programs")),
    ("fixes", Some("modules/fixes")),
    ("overlays", Some("modules/overlays")),
    ("核心 (flake / lib / AGENTS)", Some("@core")),
    ("返回", None),
];

pub struct FilesState {
    pub title: String,
    /// 从哪个菜单项进来的（Esc 返回时用）。
    pub origin: usize,
    pub items: Vec<FileItem>,
    pub all: Vec<FileItem>,
    pub filter: String,
    pub sel: usize,
    pub scroll: usize,
}

pub struct TextView {
    pub title: String,
    pub lines: Vec<String>,
    pub scroll: usize,
}

pub struct InputState {
    pub prompt: String,
    pub buf: String,
}

pub enum ConfirmKind {
    Rollback,
    Rebuild,
}

pub struct ConfirmState {
    pub prompt: String,
    pub kind: ConfirmKind,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Focus {
    Results,
    Cart,
}

pub struct InstallState {
    pub query: String,
    pub results: Vec<install::Hit>,
    pub sel: usize,
    pub scroll: usize,
    pub cart: Vec<String>,
    pub status: String,
    pub pending: bool,
    /// (查询词, 结果通道) — 收到过期查询的结果时直接丢弃。
    pub rx: Option<(String, Receiver<Vec<install::Hit>>)>,
    pub last_query: String,
    pub dirty_at: Option<Instant>,
    pub brew: bool,
    pub brew_name: String,
    pub spinner: usize,
    /// 当前焦点：结果列表 / 已选列表（Ctrl-O 切换）。
    pub focus: Focus,
    pub cart_sel: usize,
}

impl InstallState {
    pub fn new() -> Self {
        InstallState {
            query: String::new(),
            results: Vec::new(),
            sel: 0,
            scroll: 0,
            cart: Vec::new(),
            status: String::from("输入关键词搜索 nixpkgs（可含空格）"),
            pending: false,
            rx: None,
            last_query: String::new(),
            dirty_at: None,
            brew: false,
            brew_name: String::new(),
            spinner: 0,
            focus: Focus::Results,
            cart_sel: 0,
        }
    }
}

pub enum Screen {
    Menu { sel: usize },
    Browse { sel: usize },
    Files(FilesState),
    Text(TextView),
    Input(InputState),
    Confirm(ConfirmState),
    Install(InstallState),
    Log(TextView),
}

pub struct App {
    pub repo: String,
    /// 启动动画进度：已显示的 logo 字符数（usize::MAX = 全显示）。
    pub logo_reveal: usize,
    pub branch: String,
    pub dirty: usize,
    pub screen: Screen,
    pub toast: String,
    pub menu: &'static [MenuItem],
}

impl App {
    pub fn new(repo: &str) -> Self {
        let mut app = App {
            repo: repo.to_string(),
            branch: String::from("?"),
            dirty: 0,
            screen: Screen::Menu { sel: 0 },
            logo_reveal: usize::MAX,
            toast: String::new(),
            menu: MENU,
        };
        app.refresh_status();
        app
    }

    fn refresh_status(&mut self) {
        self.branch = self.git(&["branch", "--show-current"]).trim().to_string();
        if self.branch.is_empty() {
            self.branch = String::from("detached");
        }
        self.dirty = self
            .git(&["status", "-s"])
            .lines()
            .filter(|l| !l.trim().is_empty())
            .count();
    }

    pub fn git(&self, args: &[&str]) -> String {
        Command::new("git")
            .arg("-C")
            .arg(&self.repo)
            .args(args)
            .stdin(Stdio::null())
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default()
    }

    // ── 启动动画：纯 ASCII，菜单与 logo 同屏，逐字揭示 ───────────────────
    pub fn splash(&mut self, term: &mut Term) {
        if term.h < 24 {
            self.logo_reveal = usize::MAX;
            return;
        }
        let total = ui::logo_total();
        let mut reveal = 0;
        while reveal < total {
            self.logo_reveal = reveal;
            let frame = ui::render(self, term.w, term.h);
            let _ = term.draw(&frame);
            std::thread::sleep(std::time::Duration::from_millis(5));
            reveal += 2;
        }
        self.logo_reveal = usize::MAX;
        let _ = term.draw(&ui::render(self, term.w, term.h));
        std::thread::sleep(std::time::Duration::from_millis(60));
    }

    // ── 按键分发 ────────────────────────────────────────────────────────────
    /// 返回 false 表示退出程序。
    pub fn handle(&mut self, key: Key, term: &mut Term) -> bool {
        self.toast.clear();
        let screen = std::mem::replace(&mut self.screen, Screen::Menu { sel: 0 });
        let next = match screen {
            Screen::Menu { sel } => self.step_menu(key, sel, term),
            Screen::Browse { sel } => self.step_browse(key, sel, term),
            Screen::Files(st) => self.step_files(key, st, term),
            Screen::Text(v) => self.step_text(key, v),
            Screen::Log(v) => self.step_text(key, v),
            Screen::Input(i) => self.step_input(key, i, term),
            Screen::Confirm(c) => self.step_confirm(key, c, term),
            Screen::Install(st) => self.step_install(key, st, term),
        };
        match next {
            Some(s) => {
                self.screen = s;
                true
            }
            None => false,
        }
    }

    fn step_menu(&mut self, key: Key, sel: usize, term: &mut Term) -> Option<Screen> {
        let n = MENU.len();
        match key {
            Key::Char('q') | Key::CtrlC => None,
            Key::Up | Key::Char('k') => Some(Screen::Menu { sel: (sel + n - 1) % n }),
            Key::Down | Key::Char('j') => Some(Screen::Menu { sel: (sel + 1) % n }),
            Key::Enter => match sel {
                0 => Some(Screen::Files(self.files_state("@all", "全局搜索 — *.nix", 0))),
                1 => Some(Screen::Browse { sel: 0 }),
                2 => {
                    self.do_rebuild(term);
                    Some(Screen::Menu { sel })
                }
                3 => {
                    self.do_diff(term);
                    Some(Screen::Menu { sel })
                }
                4 => Some(Screen::Input(InputState {
                    prompt: String::from("commit message"),
                    buf: String::new(),
                })),
                5 => Some(Screen::Confirm(ConfirmState {
                    prompt: String::from("确认 rollback 到上一代?"),
                    kind: ConfirmKind::Rollback,
                })),
                6 => Some(Screen::Install(InstallState::new())),
                _ => None,
            },
            _ => Some(Screen::Menu { sel }),
        }
    }

    fn step_browse(&mut self, key: Key, sel: usize, _term: &mut Term) -> Option<Screen> {
        let n = CATEGORIES.len();
        match key {
            Key::Char('q') | Key::Esc | Key::CtrlC => Some(Screen::Menu { sel: 1 }),
            Key::Up | Key::Char('k') => Some(Screen::Browse { sel: (sel + n - 1) % n }),
            Key::Down | Key::Char('j') => Some(Screen::Browse { sel: (sel + 1) % n }),
            Key::Enter => match CATEGORIES[sel].1 {
                None => Some(Screen::Menu { sel: 1 }),
                Some("@install") => Some(Screen::Install(InstallState::new())),
                Some(scope) => Some(Screen::Files(self.files_state(scope, scope, 1))),
            },
            _ => Some(Screen::Browse { sel }),
        }
    }

    fn step_files(&mut self, key: Key, mut st: FilesState, term: &mut Term) -> Option<Screen> {
        let visible_h = term.h.saturating_sub(4).max(1);
        match key {
            Key::CtrlC => return None,
            Key::Esc => return Some(Screen::Menu { sel: st.origin }),
            Key::Up => {
                st.sel = st.sel.saturating_sub(1);
                if st.sel < st.scroll {
                    st.scroll = st.sel;
                }
            }
            Key::Down => {
                if st.sel + 1 < st.items.len() {
                    st.sel += 1;
                }
                if st.sel >= st.scroll + visible_h {
                    st.scroll = st.sel + 1 - visible_h;
                }
            }
            Key::PageUp => {
                st.sel = st.sel.saturating_sub(10);
                st.scroll = st.scroll.saturating_sub(10);
            }
            Key::PageDown => {
                let last = st.items.len().saturating_sub(1);
                st.sel = (st.sel + 10).min(last);
                st.scroll = (st.scroll + 10).min(last);
            }
            Key::Backspace => {
                st.filter.pop();
                st.apply_filter();
            }
            Key::Char(c) => {
                st.filter.push(c);
                st.apply_filter();
            }
            Key::Enter => {
                if let Some(item) = st.items.get(st.sel).cloned() {
                    self.edit_file(term, &item.path);
                }
                return Some(Screen::Files(st));
            }
            _ => {}
        }
        Some(Screen::Files(st))
    }

    fn step_text(&mut self, key: Key, mut v: TextView) -> Option<Screen> {
        match key {
            Key::Char('q') | Key::Esc | Key::Enter => return Some(Screen::Menu { sel: 0 }),
            Key::CtrlC => return None,
            Key::Up | Key::Char('k') => v.scroll = v.scroll.saturating_sub(1),
            Key::Down | Key::Char('j') => v.scroll += 1,
            Key::PageUp => v.scroll = v.scroll.saturating_sub(10),
            Key::PageDown => v.scroll += 10,
            _ => {}
        }
        Some(Screen::Text(v))
    }

    fn step_input(&mut self, key: Key, mut i: InputState, term: &mut Term) -> Option<Screen> {
        match key {
            Key::CtrlC => None,
            Key::Esc => Some(Screen::Menu { sel: 4 }),
            Key::Enter => {
                let msg = i.buf.trim().to_string();
                if msg.is_empty() {
                    self.toast = String::from("commit message 为空");
                    return Some(Screen::Input(i));
                }
                Some(self.do_commit(term, &msg))
            }
            Key::Backspace => {
                i.buf.pop();
                Some(Screen::Input(i))
            }
            Key::Char(c) => {
                i.buf.push(c);
                Some(Screen::Input(i))
            }
            _ => Some(Screen::Input(i)),
        }
    }


    fn step_install(&mut self, key: Key, mut st: InstallState, term: &mut Term) -> Option<Screen> {
        let cart_rows = st.cart.len().min(5);
        let cart_block = if st.cart.is_empty() { 1 } else { cart_rows + 1 };
        let visible = term.h.saturating_sub(2 + 4 + cart_block).max(1);
        match key {
            Key::CtrlC => return None,
            Key::Esc => {
                if st.focus == Focus::Cart {
                    st.focus = Focus::Results;
                } else if st.brew {
                    st.brew = false;
                } else {
                    return Some(Screen::Menu { sel: 6 });
                }
            }
            Key::CtrlO => {
                if !st.brew {
                    st.focus = match st.focus {
                        Focus::Results => Focus::Cart,
                        Focus::Cart => Focus::Results,
                    };
                    st.cart_sel = st.cart_sel.min(st.cart.len().saturating_sub(1));
                }
            }
            Key::Right if !st.brew => {
                st.brew = true;
                st.focus = Focus::Results;
                st.dirty_at = None;
                return Some(Screen::Install(st));
            }
            Key::Left if st.brew => {
                st.brew = false;
                st.focus = Focus::Results;
                return Some(Screen::Install(st));
            }
            Key::CtrlB | Key::F2 => {
                st.brew = !st.brew;
                st.focus = Focus::Results;
                st.dirty_at = None;
                return Some(Screen::Install(st));
            }
            Key::Up if !st.brew => {
                if st.focus == Focus::Cart {
                    if st.cart_sel > 0 {
                        st.cart_sel -= 1;
                    } else {
                        // 已选列表顶部再按 ↑：回到结果列表
                        st.focus = Focus::Results;
                    }
                } else {
                    st.sel = st.sel.saturating_sub(1);
                    if st.sel < st.scroll {
                        st.scroll = st.sel;
                    }
                }
            }
            Key::Down if !st.brew => {
                if st.focus == Focus::Cart {
                    if st.cart_sel + 1 < st.cart.len() {
                        st.cart_sel += 1;
                    }
                } else if st.sel + 1 < st.results.len() {
                    st.sel += 1;
                    if st.sel >= st.scroll + visible {
                        st.scroll = st.sel + 1 - visible;
                    }
                } else if !st.cart.is_empty() {
                    // 结果列表末尾再按 ↓：进入已选列表（不需要任何 Ctrl 组合）
                    st.focus = Focus::Cart;
                    st.cart_sel = 0;
                }
            }
            Key::Tab if !st.brew => {
                if st.focus == Focus::Cart {
                    cart_remove(&mut st);
                } else if let Some(hit) = st.results.get(st.sel) {
                    let attr = hit.attr.clone();
                    if let Some(pos) = st.cart.iter().position(|c| c == &attr) {
                        st.cart.remove(pos);
                        st.cart_sel = st.cart_sel.min(st.cart.len().saturating_sub(1));
                    } else {
                        st.cart.push(attr);
                    }
                }
            }
            Key::Backspace => {
                if st.brew {
                    st.brew_name.pop();
                } else if st.focus == Focus::Cart {
                    cart_remove(&mut st);
                } else {
                    st.query.pop();
                    st.dirty_at = Some(Instant::now());
                }
            }
            Key::Char(c) => {
                if st.brew {
                    st.brew_name.push(c);
                } else if st.focus == Focus::Results {
                    st.query.push(c);
                    st.dirty_at = Some(Instant::now());
                }
                // 已选列表里不吞字符，避免误改搜索词
            }
            Key::Enter => {
                if st.brew {
                    return Some(self.do_brew(term, &st.brew_name));
                }
                if st.cart.is_empty() {
                    self.toast = String::from("先按 Tab 选中包");
                    return Some(Screen::Install(st));
                }
                return match self.write_packages(&st.cart) {
                    Ok(n) if n > 0 => Some(Screen::Confirm(ConfirmState {
                        prompt: format!("已写入 {} 个包到 packages.nix, 立即 rebuild?", n),
                        kind: ConfirmKind::Rebuild,
                    })),
                    Ok(_) => {
                        self.toast = String::from("这些包都已经声明过了");
                        Some(Screen::Install(st))
                    }
                    Err(e) => {
                        self.toast = e;
                        Some(Screen::Install(st))
                    }
                };
            }
            _ => {}
        }
        Some(Screen::Install(st))
    }

    /// 主循环每 ~100ms 调用一次：轮询搜索结果、做防抖、转 spinner。
    /// 返回 true 表示界面需要重绘。
    pub fn tick(&mut self) -> bool {
        let Screen::Install(st) = &mut self.screen else {
            return false;
        };
        st.spinner = st.spinner.wrapping_add(1);
        let mut changed = false;

        if let Some((tag, rx)) = st.rx.take() {
            match rx.try_recv() {
                Ok(hits) => {
                    st.pending = false;
                    st.last_query = tag.clone();
                    if tag == st.query {
                        st.results = hits;
                        st.sel = 0;
                        st.scroll = 0;
                        st.status = format!("{} 个结果（Tab 选中, Enter 写入）", st.results.len());
                    }
                    changed = true;
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => st.rx = Some((tag, rx)),
                Err(_) => {
                    st.pending = false;
                    changed = true;
                }
            }
        }

        if st.brew {
            return changed;
        }
        if st.query.trim().is_empty() {
            if !st.results.is_empty() || st.pending || !st.last_query.is_empty() {
                st.results.clear();
                st.sel = 0;
                st.scroll = 0;
                st.pending = false;
                st.last_query.clear();
                st.dirty_at = None;
                st.status = String::from("输入关键词搜索 nixpkgs（可含空格）");
                changed = true;
            }
            return changed;
        }
        if !st.pending && st.query != st.last_query {
            if let Some(t) = st.dirty_at {
                if t.elapsed() >= Duration::from_millis(300) {
                    st.rx = Some((st.query.clone(), install::search_async(st.query.clone())));
                    st.last_query = st.query.clone();
                    st.pending = true;
                    st.dirty_at = None;
                    st.status = String::from("searching ...");
                    changed = true;
                }
            }
        }
        changed
    }

    fn write_packages(&mut self, attrs: &[String]) -> Result<usize, String> {
        let path = format!("{}/modules/system/packages.nix", self.repo);
        let content = fs::read_to_string(&path).map_err(|e| format!("读 packages.nix 失败: {e}"))?;
        let (new, n) = install::insert_packages(&content, attrs)?;
        if n > 0 {
            fs::write(&path, new).map_err(|e| format!("写 packages.nix 失败: {e}"))?;
        }
        Ok(n)
    }

    fn do_brew(&mut self, term: &mut Term, raw: &str) -> Screen {
        let name = raw.trim().to_string();
        let mut log = vec![format!("$ brew install {}", name)];
        if name.is_empty() {
            log.push(String::from("名字为空"));
            return Screen::Log(TextView { title: String::from("brew"), lines: log, scroll: 0 });
        }
        let cask = install::brew_is_cask(&name);
        let _ = term.suspend();
        let status = if cask {
            Command::new("brew").args(["install", "--cask", &name]).status()
        } else {
            Command::new("brew").args(["install", &name]).status()
        };
        let _ = term.resume();
        match status {
            Ok(s) if s.success() => {
                log.push(format!("[{}] 安装完成", if cask { "cask" } else { "formula" }));
                let path = format!("{}/modules/system/homebrew.nix", self.repo);
                match fs::read_to_string(&path) {
                    Ok(content) => match install::insert_brew(&content, &name, cask) {
                        Ok((new, true)) => match fs::write(&path, new) {
                            Ok(_) => log.push(format!(
                                "已写入 homebrew.nix 的 {}",
                                if cask { "casks" } else { "brews" }
                            )),
                            Err(e) => log.push(format!("写 homebrew.nix 失败: {e}")),
                        },
                        Ok((_, false)) => log.push(String::from("homebrew.nix 里已有声明")),
                        Err(e) => log.push(e),
                    },
                    Err(e) => log.push(format!("读 homebrew.nix 失败: {e}")),
                }
            }
            Ok(s) => log.push(format!("[exit {:?}] 安装失败", s.code())),
            Err(e) => log.push(format!("brew 调用失败: {e}")),
        }
        Screen::Log(TextView { title: String::from("brew install"), lines: log, scroll: 0 })
    }

    fn step_confirm(&mut self, key: Key, c: ConfirmState, term: &mut Term) -> Option<Screen> {
        match key {
            Key::Char('y') | Key::Char('Y') => match c.kind {
                ConfirmKind::Rollback => {
                    self.do_rollback(term);
                    Some(Screen::Menu { sel: 5 })
                }
                ConfirmKind::Rebuild => {
                    self.do_rebuild(term);
                    Some(Screen::Menu { sel: 6 })
                }
            },
            Key::CtrlC => None,
            _ => Some(Screen::Menu { sel: 0 }),
        }
    }

    // ── 数据 ────────────────────────────────────────────────────────────────
    pub fn files_state(&self, scope: &str, title: &str, origin: usize) -> FilesState {
        let all = self.load_files(scope);
        FilesState {
            title: title.to_string(),
            origin,
            items: all.clone(),
            all,
            filter: String::new(),
            sel: 0,
            scroll: 0,
        }
    }

    fn load_files(&self, scope: &str) -> Vec<FileItem> {
        let out = match scope {
            "@all" => self.git(&["ls-files", "*.nix"]),
            "@core" => String::from("flake.nix\nmodules/lib.nix\nmodules/default.nix\nAGENTS.md\n"),
            dir => self.git(&["ls-files", dir]),
        };
        out.lines()
            .map(|l| l.trim())
            .filter(|l| !l.is_empty())
            .map(|l| FileItem { path: l.to_string() })
            .collect()
    }

    pub fn preview_lines(&self, sel: usize, items: &[FileItem]) -> Vec<String> {
        let Some(item) = items.get(sel) else {
            return Vec::new();
        };
        let full = format!("{}/{}", self.repo, item.path);
        let Ok(text) = fs::read_to_string(&full) else {
            return vec![String::from("<unreadable>")];
        };
        text.lines()
            .take(400)
            .enumerate()
            .map(|(i, l)| format!("{:>4} {}", i + 1, l.replace('\t', "  ")))
            .collect()
    }

    // ── 动作 ────────────────────────────────────────────────────────────────
    fn edit_file(&mut self, term: &mut Term, rel: &str) {
        let path = format!("{}/{}", self.repo, rel);
        let editor = env::var("EDITOR").unwrap_or_else(|_| String::from("nvim"));
        let mut parts = editor.split_whitespace();
        let Some(bin) = parts.next() else { return };
        let args: Vec<String> = parts.map(|s| s.to_string()).collect();
        let _ = term.suspend();
        let status = Command::new(bin)
            .args(&args)
            .arg(&path)
            .current_dir(&self.repo)
            .status();
        let _ = term.resume();
        match status {
            Ok(s) if s.success() => self.toast = format!("已编辑 {}", rel),
            _ => self.toast = format!("编辑器退出异常: {}", rel),
        }
        self.refresh_status();
    }

    fn do_rebuild(&mut self, term: &mut Term) {
        let _ = term.suspend();
        println!("\n  $ sudo darwin-rebuild switch --flake .#dok4ever-mac\n");
        let _ = std::io::stdout().flush();
        let status = Command::new("sudo")
            .args(["darwin-rebuild", "switch", "--flake", ".#dok4ever-mac"])
            .current_dir(&self.repo)
            .status();
        let _ = term.resume();
        match status {
            Ok(s) if s.success() => self.toast = String::from("rebuild ok - generation switched"),
            Ok(s) => self.toast = format!("rebuild failed (exit {:?})", s.code()),
            Err(e) => self.toast = format!("rebuild error: {e}"),
        }
        self.refresh_status();
    }

    fn do_rollback(&mut self, term: &mut Term) {
        let _ = term.suspend();
        let status = Command::new("sudo")
            .args(["darwin-rebuild", "switch", "--rollback"])
            .current_dir(&self.repo)
            .status();
        let _ = term.resume();
        match status {
            Ok(s) if s.success() => self.toast = String::from("rollback ok"),
            _ => self.toast = String::from("rollback failed"),
        }
    }

    fn do_diff(&mut self, term: &mut Term) {
        let _ = term.suspend();
        let status = Command::new("sh")
            .arg("-c")
            .arg("git --no-pager -c color.ui=always diff HEAD | less -R")
            .current_dir(&self.repo)
            .status();
        let _ = term.resume();
        if status.is_err() {
            self.toast = String::from("diff 打开失败");
        }
    }

    fn do_commit(&mut self, term: &mut Term, msg: &str) -> Screen {
        let _ = term.suspend();
        let mut log = Vec::new();
        let steps: [(&str, Vec<&str>); 4] = [
            ("git", vec!["add", "-A"]),
            ("git", vec!["commit", "-m", msg]),
            ("git", vec!["push"]),
            ("git", vec!["push", "gitea", "HEAD"]),
        ];
        for (bin, args) in steps.iter() {
            let out = Command::new(bin).args(args).current_dir(&self.repo).output();
            match out {
                Ok(o) => {
                    log.push(format!("$ {} {}", bin, args.join(" ")));
                    for line in String::from_utf8_lossy(&o.stdout).lines() {
                        log.push(format!("  {}", line));
                    }
                    for line in String::from_utf8_lossy(&o.stderr).lines() {
                        log.push(format!("  {}", line));
                    }
                    if !o.status.success() {
                        log.push(format!("  [exit {:?}]", o.status.code()));
                        break;
                    }
                }
                Err(e) => {
                    log.push(format!("$ {} -> {e}", bin));
                    break;
                }
            }
        }
        let _ = term.resume();
        self.refresh_status();
        Screen::Log(TextView {
            title: String::from("commit & push"),
            lines: log,
            scroll: 0,
        })
    }
}

/// 从已选列表移除当前项；空了就回到结果列表。
fn cart_remove(st: &mut InstallState) {
    if st.cart_sel < st.cart.len() {
        st.cart.remove(st.cart_sel);
    }
    if st.cart.is_empty() {
        st.focus = Focus::Results;
        st.cart_sel = 0;
    } else if st.cart_sel >= st.cart.len() {
        st.cart_sel = st.cart.len() - 1;
    }
}

impl FilesState {
    pub fn apply_filter(&mut self) {
        let needle = self.filter.to_lowercase();
        self.items = if needle.is_empty() {
            self.all.clone()
        } else {
            self.all
                .iter()
                .filter(|i| i.path.to_lowercase().contains(&needle))
                .cloned()
                .collect()
        };
        self.sel = 0;
        self.scroll = 0;
    }
}
