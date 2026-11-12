//! 纯函数渲染层：给定 App 状态与尺寸，产出一帧文本行。
//! 边框/标记一律 ASCII；中文按 2 列宽计算，保证对齐。

use crate::app::{App, Screen};

pub const REV: &str = "\x1b[7m";
pub const DIM: &str = "\x1b[2m";
pub const BOLD: &str = "\x1b[1m";
pub const RESET: &str = "\x1b[0m";
pub const CYAN: &str = "\x1b[36m";

/// 启动横幅：5 行 ASCII logo + 中文 tagline，纯 7-bit 字符。
pub const LOGO: [&str; 5] = [
    " _   _  __  __  ____",
    "| \\ | | \\ \\/ / |  _ \\",
    "|  \\| |  \\  /  | | | |",
    "| |\\  |  /  \\  | |_| |",
    "|_| \\_| /_/\\_\\ |____/",
];
pub const TAGLINE: &str = "nix-darwin control deck";
/// logo 区块占用的行数（5 logo + 空行 + tagline + 空行）
pub const LOGO_ROWS: usize = 8;

/// 已显示多少个字符；`usize::MAX` 表示全部显示。
pub fn logo_rows(reveal: usize) -> Vec<String> {
    let mut rows = Vec::with_capacity(LOGO_ROWS);
    let mut left = reveal;
    for line in LOGO.iter() {
        let n = line.chars().count().min(left);
        let mut s = String::from("  ");
        s.extend(line.chars().take(n));
        rows.push(s);
        left = left.saturating_sub(line.chars().count());
    }
    rows.push(String::new());
    let n = TAGLINE.chars().count().min(left);
    rows.push(format!("  {}", TAGLINE.chars().take(n).collect::<String>()));
    rows.push(String::new());
    rows
}

pub fn logo_total() -> usize {
    LOGO.iter().map(|l| l.chars().count()).sum::<usize>() + TAGLINE.chars().count()
}

/// 一个字符占几列（CJK / emoji 算 2 列）。
pub fn cw(c: char) -> usize {
    let u = c as u32;
    if u < 0x20 || (0x7f..0xa0).contains(&u) {
        0
    } else if (0x1100..=0x115f).contains(&u)
        || (0x2e80..=0xa4cf).contains(&u)
        || (0xac00..=0xd7a3).contains(&u)
        || (0xf900..=0xfaff).contains(&u)
        || (0xfe30..=0xfe4f).contains(&u)
        || (0xff00..=0xff60).contains(&u)
        || (0xffe0..=0xffe6).contains(&u)
        || (0x1f300..=0x1f64f).contains(&u)
        || (0x1f900..=0x1f9ff).contains(&u)
        || (0x20000..=0x3fffd).contains(&u)
    {
        2
    } else {
        1
    }
}

pub fn width(s: &str) -> usize {
    s.chars().map(cw).sum()
}

pub fn fit(s: &str, w: usize) -> String {
    let mut out = String::new();
    let mut used = 0;
    for c in s.chars() {
        let c = if c == '\t' { ' ' } else { c };
        let n = cw(c);
        if used + n > w {
            break;
        }
        out.push(c);
        used += n;
    }
    out
}

pub fn pad(s: &str, w: usize) -> String {
    let mut out = fit(s, w);
    let used = width(&out);
    out.push_str(&" ".repeat(w.saturating_sub(used)));
    out
}

pub fn render(app: &App, w: usize, h: usize) -> Vec<String> {
    let mut lines: Vec<String> = Vec::with_capacity(h);
    lines.push(header(app, w));
    let body_h = h.saturating_sub(2);
    match &app.screen {
        Screen::Menu { sel } => menu(app, *sel, w, body_h, &mut lines),
        Screen::Browse { sel } => browse(*sel, w, body_h, &mut lines),
        Screen::Files(st) => files(app, st, w, body_h, &mut lines),
        Screen::Text(v) | Screen::Log(v) => text(v, w, body_h, &mut lines),
        Screen::Input(i) => input(i, w, body_h, &mut lines),
        Screen::Confirm(c) => confirm(c, w, body_h, &mut lines),
        Screen::Install(st) => install(st, w, body_h, &mut lines),
    }
    while lines.len() < h.saturating_sub(1) {
        lines.push(String::new());
    }
    footer(app, w, h, &mut lines);
    lines
}

fn header(app: &App, w: usize) -> String {
    let right = format!("[{}]  {} dirty", app.branch, app.dirty);
    let mut left = format!(" nxd  {}", app.repo);
    if width(&left) + width(&right) + 1 > w {
        left = fit(&left, w.saturating_sub(width(&right) + 1));
    }
    let used = width(&left) + width(&right);
    let gap = w.saturating_sub(used).max(1);
    let mut s = String::new();
    s.push_str(BOLD);
    s.push_str(&left);
    s.push_str(RESET);
    s.push_str(&" ".repeat(gap));
    s.push_str(DIM);
    s.push_str(&right);
    s.push_str(RESET);
    s.push_str(&" ".repeat(w.saturating_sub(used + gap)));
    s
}

fn rule(w: usize) -> String {
    "-".repeat(w)
}

fn menu(app: &App, sel: usize, w: usize, body_h: usize, out: &mut Vec<String>) {
    let show_logo = body_h >= LOGO_ROWS + app.menu.len() + 2;
    if show_logo {
        for row in logo_rows(app.logo_reveal) {
            out.push(format!("{}{}{}", CYAN, pad(&row, w), RESET));
        }
    }
    out.push(pad(&rule(w), w));
    for (i, item) in app.menu.iter().enumerate() {
        let marker = if i == sel { ">" } else { " " };
        let line = format!(" {}  {}", marker, item.label);
        out.push(if i == sel {
            format!("{}{}{}", REV, pad(&line, w), RESET)
        } else {
            pad(&line, w)
        });
    }
}

fn browse(sel: usize, w: usize, _body_h: usize, out: &mut Vec<String>) {
    out.push(pad(" 分类浏览 — 选一个目录（Esc 返回）", w));
    out.push(pad(&rule(w), w));
    for (i, (name, _)) in crate::app::CATEGORIES.iter().enumerate() {
        let line = format!(" {}  {}", if i == sel { ">" } else { " " }, name);
        out.push(if i == sel {
            format!("{}{}{}", REV, pad(&line, w), RESET)
        } else {
            pad(&line, w)
        });
    }
}

fn files(app: &App, st: &crate::app::FilesState, w: usize, body_h: usize, out: &mut Vec<String>) {
    let head = format!("{}  |  筛选: {}", st.title, st.filter);
    out.push(format!("{}{}{}", DIM, pad(&head, w), RESET));
    out.push(pad(&rule(w), w));

    let left_max = w.saturating_sub(12).max(18);
    let left_w = (w * 34 / 100).clamp(18, left_max);
    let right_w = w.saturating_sub(left_w + 1);
    let preview = app.preview_lines(st.sel, &st.items);

    for row in 0..body_h.saturating_sub(2) {
        let idx = st.scroll + row;
        let left = match st.items.get(idx) {
            Some(item) => {
                let line = format!(" {}  {}", if idx == st.sel { ">" } else { " " }, item.path);
                if idx == st.sel {
                    format!("{}{}{}", REV, pad(&line, left_w), RESET)
                } else {
                    pad(&line, left_w)
                }
            }
            None => pad("", left_w),
        };
        let right = preview.get(row).map(|s| s.as_str()).unwrap_or("");
        out.push(format!("{}|{}", left, pad(&fit(right, right_w), right_w)));
    }
}

fn text(v: &crate::app::TextView, w: usize, body_h: usize, out: &mut Vec<String>) {
    out.push(format!("{}{}{}", BOLD, pad(&format!(" {}", v.title), w), RESET));
    out.push(pad(&rule(w), w));
    let shown = v.lines.iter().skip(v.scroll).take(body_h.saturating_sub(2));
    for line in shown {
        out.push(pad(line, w));
    }
}

fn input(i: &crate::app::InputState, w: usize, _body_h: usize, out: &mut Vec<String>) {
    out.push(String::new());
    out.push(pad(&format!(" {}:", i.prompt), w));
    let mut line = pad(&format!(" > {}", i.buf), w.saturating_sub(1));
    line.push_str("\x1b[7m \x1b[0m");
    out.push(line);
    out.push(String::new());
    out.push(pad(&format!("{}Enter 确认 / Esc 取消{}", DIM, RESET), w));
}

fn confirm(c: &crate::app::ConfirmState, w: usize, _body_h: usize, out: &mut Vec<String>) {
    out.push(String::new());
    out.push(pad(&format!(" {}", c.prompt), w));
    out.push(pad(&format!("{}y 确认 / n 或 Esc 取消{}", DIM, RESET), w));
}


fn install(st: &crate::app::InstallState, w: usize, body_h: usize, out: &mut Vec<String>) {
    let spin = ["|", "/", "-", "\\"][st.spinner % 4];
    if st.brew {
        out.push(pad(" 安装 — brew（← 切回 nix）", w));
        out.push(pad(&format!(" 名字: {}_", st.brew_name), w));
        out.push(pad(&rule(w), w));
        out.push(pad(" Enter: brew install + 自动写入 homebrew.nix 声明", w));
        out.push(pad(" cask / formula 自动识别", w));
        return;
    }

    out.push(pad(
        &format!(" 安装 — nix 搜索（→ 切到 brew）  {}", if st.pending { spin } else { "" }),
        w,
    ));
    out.push(pad(&format!(" 查询: {}_", st.query), w));
    out.push(pad(&format!(" {}{}{}", DIM, st.status, RESET), w));
    out.push(pad(&rule(w), w));

    // 已选列表固定篮位：标题 + 最多 5 行
    let cart_rows = st.cart.len().min(5);
    let cart_block = if st.cart.is_empty() { 1 } else { cart_rows + 1 };
    let rows = body_h.saturating_sub(4 + cart_block);

    for row in 0..rows {
        let idx = st.scroll + row;
        let Some(hit) = st.results.get(idx) else {
            out.push(String::new());
            continue;
        };
        let mark = if st.cart.iter().any(|c| c == &hit.attr) { "[x]" } else { "[ ]" };
        let line = format!(
            " {} {} {:<30} {:<10} {}",
            if idx == st.sel && st.focus == crate::app::Focus::Results { ">" } else { " " },
            mark,
            trunc(&hit.attr, 30),
            trunc(&hit.version, 10),
            trunc(&hit.programs, 40)
        );
        out.push(if idx == st.sel && st.focus == crate::app::Focus::Results {
            format!("{}{}{}", REV, pad(&line, w), RESET)
        } else {
            pad(&line, w)
        });
    }

    // 已选列表
    let focus_cart = st.focus == crate::app::Focus::Cart;
    let cart_head = if st.cart.is_empty() {
        String::from(" 已选 0  （空 — 结果列表里按 Tab 选中）")
    } else {
        format!(
            " 已选 {}  （{}）",
            st.cart.len(),
            if focus_cart { "↑/↓ 选择, Tab 移除, ↑ 回结果" } else { "↓ 进入 / Ctrl-O(字母O)" }
        )
    };
    out.push(if focus_cart {
        format!("{}{}{}", REV, pad(&cart_head, w), RESET)
    } else {
        pad(&cart_head, w)
    });
    let offset = if st.cart_sel >= cart_rows { st.cart_sel + 1 - cart_rows } else { 0 };
    for row in 0..cart_rows {
        let idx = offset + row;
        let Some(attr) = st.cart.get(idx) else {
            out.push(String::new());
            continue;
        };
        let line = format!(" {} - {}", if focus_cart && idx == st.cart_sel { ">" } else { " " }, attr);
        out.push(if focus_cart && idx == st.cart_sel {
            format!("{}{}{}", REV, pad(&line, w), RESET)
        } else {
            pad(&line, w)
        });
    }
}

fn trunc(s: &str, w: usize) -> String {
    fit(s, w)
}

fn footer(app: &App, w: usize, h: usize, out: &mut Vec<String>) {
    let hint = match &app.screen {
        Screen::Menu { .. } => "up/down 选择   Enter 执行   q 退出",
        Screen::Browse { .. } => "up/down 选择   Enter 进入   Esc 返回",
        Screen::Files(_) => "up/down 选择   输入 过滤   Enter 编辑   Esc 返回",
        Screen::Text(_) | Screen::Log(_) => "up/down 滚动   PgUp/PgDn 翻页   q 返回",
        Screen::Input(_) => "Enter 确认   Esc 取消",
        Screen::Confirm(_) => "y 确认   n/Esc 取消",
        Screen::Install(st) if st.brew => "输入名字   Enter 安装   ← 切到 nix   Esc 返回",
        Screen::Install(st) if st.focus == crate::app::Focus::Cart => {
            "↑/↓ 选择   Tab/Backspace 移除   ↑ 回结果   Enter 写入   Esc 返回"
        }
        Screen::Install(_) => "输入搜索   Tab 选中   ↓ 进已选   Enter 写入   → 切 brew",
    };
    let toast = if app.toast.is_empty() {
        String::new()
    } else {
        format!("  |  {}", app.toast)
    };
    let plain = fit(&format!(" {}{}", hint, toast), w);
    let fill = w.saturating_sub(width(&plain));
    out.truncate(h.saturating_sub(1));
    out.push(format!("{}{}{}{}", DIM, plain, RESET, " ".repeat(fill)));
}

/// 去掉 ANSI 转义，供 `--dump` 自检。
pub fn strip_ansi(s: &str) -> String {
    let mut out = String::new();
    let mut in_esc = false;
    for c in s.chars() {
        if in_esc {
            if c == 'm' {
                in_esc = false;
            }
        } else if c == '\x1b' {
            in_esc = true;
        } else {
            out.push(c);
        }
    }
    out
}
