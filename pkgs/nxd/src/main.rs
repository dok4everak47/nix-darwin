//! nxd — /etc/nix-darwin 的 ASCII TUI 控制台（零依赖纯 Rust）。
//!
//! 用法:
//!   nxd              进入菜单
//!   nxd -q           跳过启动动画
//!   nxd --dump=menu  渲染一帧到 stdout（自检 / 截图用）
//!   nxd --selftest   跑内置断言

mod app;
mod install;
mod term;
mod ui;

use std::env;
use std::io::{Read, Write};
use std::process::ExitCode;

use app::{App, ConfirmState, FilesState, InputState, Screen, TextView};
use term::{Key, Term};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let mut anim = env::var("NXD_NO_ANIM").map(|v| v != "1").unwrap_or(true);
    let mut dump: Option<String> = None;
    let mut selftest = false;

    for a in &args {
        match a.as_str() {
            "-q" | "--no-anim" => anim = false,
            "--selftest" => selftest = true,
            "--keys" => return keys_mode(),
            "-h" | "--help" => {
                print_help();
                return ExitCode::SUCCESS;
            }
            "-V" | "--version" => {
                emit(&format!("nxd {}", env!("CARGO_PKG_VERSION")));
                return ExitCode::SUCCESS;
            }
            s if s.starts_with("--dump=") => dump = Some(s["--dump=".len()..].to_string()),
            s if s.starts_with("--search=") => {
                let q = s["--search=".len()..].to_string();
                let rx = install::search_async(q);
                match rx.recv() {
                    Ok(hits) => {
                        for h in hits.iter().take(20) {
                            emit(&format!("{} @ {} : {}", h.attr, h.version, h.programs));
                        }
                        emit(&format!("({} hits)", hits.len()));
                    }
                    Err(_) => eprintln!("nxd: 搜索线程失败"),
                }
                return ExitCode::SUCCESS;
            }
            other => {
                eprintln!("nxd: 未知参数: {other}（nxd -h 查看用法）");
                return ExitCode::from(2);
            }
        }
    }

    if selftest {
        return selftest_run();
    }
    if let Some(what) = dump {
        return dump_frame(&what);
    }
    run(anim)
}

/// 写 stdout 且忽略错误：管道被 head 之类提前关掉时不要 panic。
fn emit(line: &str) {
    let mut out = std::io::stdout();
    let _ = writeln!(out, "{line}");
}

fn print_help() {
    for line in [
        "nxd — nix-darwin ASCII TUI",
        "",
        "  nxd                菜单: 编辑 / 分类浏览 / rebuild / diff / commit / rollback / 安装",
        "  nxd -q, --no-anim  跳过启动动画（也可 NXD_NO_ANIM=1）",
        "  nxd --dump=<view>  渲染一帧: menu | browse | files | text | input | confirm | install | log",
        "  nxd --selftest     跑内置断言",
        "  nxd --keys         按键诊断：显示每个按键的字节码（查 Ctrl-O 是否被终端吞掉）",
        "  nxd -V, --version  版本",
    ] {
        emit(line);
    }
}

fn run(anim: bool) -> ExitCode {
    let mut term = match Term::new() {
        Ok(t) => t,
        Err(e) => {
            eprintln!("nxd: 无法初始化终端（不是 TTY?）: {e}");
            return ExitCode::FAILURE;
        }
    };
    let mut app = App::new(app::REPO_DEFAULT);
    if anim {
        app.splash(&mut term);
    }
    loop {
        let frame = ui::render(&app, term.w, term.h);
        if term.draw(&frame).is_err() {
            break;
        }
        let key = term.read_key();
        let _ = app.tick();
        if key == Key::None {
            continue;
        }
        if !app.handle(key, &mut term) {
            break;
        }
        term.refresh_size();
    }
    ExitCode::SUCCESS
}

fn keys_mode() -> ExitCode {
    let term = match Term::new() {
        Ok(t) => t,
        Err(e) => {
            eprintln!("nxd: 无法初始化终端（不是 TTY?）: {e}");
            return ExitCode::FAILURE;
        }
    };
    let _ = term.draw(&[
        String::from(" 按键诊断：按下想检查的键（Ctrl-O / Tab / 方向键 …），q 退出"),
        String::new(),
    ]);
    let mut last = Vec::new();
    loop {
        let mut b = [0u8; 1];
        match std::io::stdin().read(&mut b) {
            Ok(1) => {}
            Ok(_) => continue,
            Err(_) => break,
        }
        if b[0] == b'q' || b[0] == 0x03 {
            break;
        }
        last.push(b[0]);
        if last.len() > 12 {
            last.remove(0);
        }
        let hex: Vec<String> = last.iter().map(|x| format!("{:02x}", x)).collect();
        let name = match b[0] {
            0x0f => "Ctrl-O",
            0x02 => "Ctrl-B",
            0x03 => "Ctrl-C",
            0x09 => "Tab",
            0x0d => "Enter",
            0x1b => "Esc（方向键的第一个字节）",
            0x20 => "Space",
            _ => "",
        };
        let _ = term.draw(&[
            String::from(" 按键诊断：按下想检查的键，q 退出"),
            String::new(),
            format!(" 最近字节: {}", hex.join(" ")),
            format!(" 解释:     {}", name),
        ]);
    }
    ExitCode::SUCCESS
}

fn dump_frame(what: &str) -> ExitCode {
    let mut app = App::new(app::REPO_DEFAULT);
    app.screen = match what {
        "menu" => Screen::Menu { sel: 0 },
        "browse" => Screen::Browse { sel: 1 },
        "files" => Screen::Files(app.files_state("@all", "全局搜索 — *.nix", 0)),
        "text" => Screen::Text(TextView {
            title: String::from("查看未提交改动"),
            lines: app
                .git(&["--no-pager", "diff", "--stat", "HEAD"])
                .lines()
                .map(|s| s.to_string())
                .collect(),
            scroll: 0,
        }),
        "input" => Screen::Input(InputState {
            prompt: String::from("commit message"),
            buf: String::from("feat: nxd ascii tui"),
        }),
        "confirm" => Screen::Confirm(ConfirmState {
            prompt: String::from("确认 rollback 到上一代?"),
            kind: app::ConfirmKind::Rollback,
        }),
        "install" => Screen::Install(app::InstallState::new()),
        "install-cart" => {
            let mut st = app::InstallState::new();
            st.query = String::from("ripgrep");
            st.results = vec![
                install::Hit { attr: String::from("ripgrep"), version: String::from("15.1.0"), programs: String::from("rg") },
                install::Hit { attr: String::from("ripgrep-all"), version: String::from("0.10.10"), programs: String::from("rga") },
            ];
            st.cart = vec![String::from("ripgrep"), String::from("bat")];
            st.focus = app::Focus::Cart;
            st.status = String::from("2 个结果（Tab 选中, Enter 写入）");
            app::Screen::Install(st)
        }
        "log" => Screen::Log(TextView {
            title: String::from("commit & push"),
            lines: vec![
                String::from("$ git add -A"),
                String::from("$ git commit -m 'feat: nxd'"),
                String::from("  [main 1a2b3c4] feat: nxd"),
                String::from("$ git push"),
                String::from("  To github.com:dok4ever/nix-darwin.git"),
            ],
            scroll: 0,
        }),
        other => {
            eprintln!("nxd: 未知视图: {other}");
            return ExitCode::from(2);
        }
    };
    for line in ui::render(&app, 100, 28) {
        emit(&ui::strip_ansi(&line));
    }
    ExitCode::SUCCESS
}

fn selftest_run() -> ExitCode {
    let mut fails = 0;
    let check = |name: &str, ok: bool| {
        if ok {
            println!("ok   {}", name);
        } else {
            println!("FAIL {}", name);
        }
        ok
    };

    if !check("ascii logo width", ui::width(" _   _  __  __  ____") == 20) {
        fails += 1;
    }
    if !check("cjk width", ui::width("中文") == 4) {
        fails += 1;
    }
    if !check("pad exact", ui::pad("abc", 6) == "abc   ") {
        fails += 1;
    }
    if !check("fit truncates", ui::width(&ui::fit("abcdef", 3)) == 3) {
        fails += 1;
    }

    let mut st = FilesState {
        title: String::from("t"),
        origin: 0,
        items: vec![],
        all: vec![
            app::FileItem { path: String::from("flake.nix") },
            app::FileItem { path: String::from("modules/lib.nix") },
        ],
        filter: String::new(),
        sel: 0,
        scroll: 0,
    };
    st.apply_filter();
    if !check("filter empty keeps all", st.items.len() == 2) {
        fails += 1;
    }
    st.filter = String::from("lib");
    st.apply_filter();
    if !check("filter narrows", st.items.len() == 1 && st.items[0].path == "modules/lib.nix") {
        fails += 1;
    }

    let hits = install::parse_search("python3Minimal @ 3.14.7 : python python3\nfoo\n");
    if !check(
        "parse nix-search",
        hits.len() == 2 && hits[0].attr == "python3Minimal" && hits[0].version == "3.14.7",
    ) {
        fails += 1;
    }

    let pkgs_sample = "  environment.systemPackages = with pkgs;\n    [\n      visidata\n      yazi\n    ];\n";
    let (_, n1) = install::insert_packages(pkgs_sample, &[String::from("bat")]).unwrap();
    let (_, n2) = install::insert_packages(pkgs_sample, &[String::from("yazi")]).unwrap();
    if !check("insert into packages.nix", n1 == 1 && n2 == 0) {
        fails += 1;
    }
    let (out, _) = install::insert_packages(pkgs_sample, &[String::from("bat")]).unwrap();
    if !check("packages.nix indent", out.contains("      bat\n")) {
        fails += 1;
    }

    let brew_sample = "    brews = [\n      \"mole\"\n    ];\n";
    // 长列表里的重复也要能识别（旧实现只看前 40 行）
    let mut long_brew = String::from("    brews = [\n");
    for i in 0..60 {
        long_brew.push_str(&format!("      \"pkg{}\n", i));
    }
    long_brew.push_str("      \"mole\"\n    ];\n");
    let (_, b3) = install::insert_brew(&long_brew, "mole", false).unwrap();
    if !check("brew dup beyond 40 lines", !b3) {
        fails += 1;
    }
    // `[` 和 anchor 同一行
    let inline = "  environment.systemPackages = with pkgs; [\n      visidata\n    ];\n";
    let (_, n3) = install::insert_packages(inline, &[String::from("bat")]).unwrap();
    if !check("packages.nix inline bracket", n3 == 1) {
        fails += 1;
    }
    let (_, b1) = install::insert_brew(brew_sample, "htop", false).unwrap();
    let (_, b2) = install::insert_brew(brew_sample, "mole", false).unwrap();
    if !check("insert into homebrew.nix", b1 && !b2) {
        fails += 1;
    }

    let app = App::new(app::REPO_DEFAULT);
    let frame = ui::render(&app, 90, 26);
    if !check("frame height", frame.len() == 26) {
        fails += 1;
    }
    if !check(
        "frame width",
        frame.iter().all(|l| ui::width(&ui::strip_ansi(l)) <= 90),
    ) {
        fails += 1;
    }

    // 任何宽度下都不能超出终端列宽（否则终端自动换行会打乱布局）
    let mut narrow_app = App::new(app::REPO_DEFAULT);
    for w in [20usize, 24, 30, 40] {
        let f = ui::render(&narrow_app, w, 12);
        if !check(&format!("width {w} fits"), f.iter().all(|l| ui::width(&ui::strip_ansi(l)) <= w)) {
            fails += 1;
        }
    }
    narrow_app.screen = Screen::Install(app::InstallState::new());
    for w in [20usize, 26, 40] {
        let f = ui::render(&narrow_app, w, 12);
        if !check(&format!("install width {w} fits"), f.iter().all(|l| ui::width(&ui::strip_ansi(l)) <= w)) {
            fails += 1;
        }
    }

    // 窄终端不能 panic（旧版 clamp(min>max) 会崩）
    let narrow = App::new(app::REPO_DEFAULT);
    let nf = ui::render(&narrow, 22, 10);
    if !check("narrow frame no panic", nf.len() == 10) {
        fails += 1;
    }
    let mut inst = App::new(app::REPO_DEFAULT);
    inst.screen = Screen::Install(app::InstallState::new());
    let inf = ui::render(&inst, 24, 12);
    if !check("narrow install no panic", inf.len() == 12) {
        fails += 1;
    }

    // 按键解析：经典编码 + kitty CSI-u + xterm modifyOtherKeys
    if !check(
        "csi classic",
        term::parse_csi(b"[A") == Key::Up
            && term::parse_csi(b"[5~") == Key::PageUp
            && term::parse_csi(b"[3~") == Key::Backspace,
    ) {
        fails += 1;
    }
    if !check(
        "csi F2",
        term::parse_csi(b"[12~") == Key::F2 && term::parse_csi(b"OQ") == Key::F2,
    ) {
        fails += 1;
    }
    if !check(
        "csi ctrl-o (kitty/xterm)",
        term::parse_csi(b"[111;5u") == Key::CtrlO
            && term::parse_csi(b"[27;5;111~") == Key::CtrlO
            && term::parse_csi(b"[111u") == Key::Char('o'),
    ) {
        fails += 1;
    }

    // 已选列表：能显示并聚焦
    let mut cart_app = App::new(app::REPO_DEFAULT);
    let mut cst = app::InstallState::new();
    cst.cart = vec![String::from("ripgrep"), String::from("bat")];
    cst.focus = app::Focus::Cart;
    cst.cart_sel = 1;
    cart_app.screen = Screen::Install(cst);
    let cart_frame: String = ui::render(&cart_app, 100, 28)
        .iter()
        .map(|l| ui::strip_ansi(l))
        .collect::<Vec<_>>()
        .join("\n");
    if !check(
        "cart list rendered",
        cart_frame.contains("已选 2") && cart_frame.contains("- bat") && cart_frame.contains("- ripgrep"),
    ) {
        fails += 1;
    }

    if fails == 0 {
        println!("all checks passed");
        ExitCode::SUCCESS
    } else {
        println!("{fails} check(s) failed");
        ExitCode::FAILURE
    }
}
