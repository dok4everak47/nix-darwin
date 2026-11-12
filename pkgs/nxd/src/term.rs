//! 终端底座：raw 模式、尺寸、按键、整帧绘制。
//! 零依赖 —— 通过 `stty` 改行规程，用 ANSI 转义序列绘制，全部字符为 ASCII 或
//! 调用方提供的 UTF-8 文案（边框/标记一律 ASCII）。

use std::io::{self, IsTerminal, Read, Write};
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Enter,
    Esc,
    Tab,
    Backspace,
    Up,
    Down,
    Left,
    Right,
    PageUp,
    PageDown,
    Home,
    End,
    CtrlC,
    CtrlB,
    CtrlO,
    F2,
    None,
}

pub struct Term {
    saved: String,
    pub w: usize,
    pub h: usize,
}

impl Term {
    /// 进入 TUI：保存终端状态 → raw 模式 → 备用屏 → 隐藏光标。
    pub fn new() -> io::Result<Self> {
        if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
            return Err(io::Error::new(
                io::ErrorKind::NotConnected,
                "stdin/stdout is not a terminal",
            ));
        }
        let saved = stty(&["-g"])?;
        if saved.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::NotConnected,
                "stdin is not a terminal",
            ));
        }
        raw_on()?;
        let mut t = Term { saved, w: 80, h: 24 };
        t.refresh_size();
        let mut out = io::stdout();
        out.write_all(b"\x1b[?1049h\x1b[?25l\x1b[2J")?;
        out.flush()?;
        Ok(t)
    }

    /// 临时让出终端（跑 sudo / $EDITOR / less 前后各调一次）。
    pub fn suspend(&self) -> io::Result<()> {
        let mut out = io::stdout();
        out.write_all(b"\x1b[?25h\x1b[?1049l")?;
        out.flush()?;
        restore(&self.saved)
    }

    pub fn resume(&mut self) -> io::Result<()> {
        self.saved = stty(&["-g"])?;
        raw_on()?;
        let mut out = io::stdout();
        out.write_all(b"\x1b[?1049h\x1b[?25l\x1b[2J")?;
        out.flush()?;
        self.refresh_size();
        Ok(())
    }

    pub fn refresh_size(&mut self) {
        if let Ok(s) = stty(&["size"]) {
            let mut it = s.split_whitespace();
            if let (Some(r), Some(c)) = (it.next(), it.next()) {
                if let (Ok(r), Ok(c)) = (r.parse::<usize>(), c.parse::<usize>()) {
                    if r > 4 && c > 20 {
                        self.h = r;
                        self.w = c;
                    }
                }
            }
        }
    }

    /// 整帧输出：回到左上角 → 逐行写 → 清掉剩余区域。
    pub fn draw(&self, lines: &[String]) -> io::Result<()> {
        let mut out = String::with_capacity(self.w * self.h + 64);
        out.push_str("\x1b[H");
        for line in lines.iter().take(self.h) {
            out.push_str(line);
            out.push_str("\x1b[K\r\n");
        }
        out.push_str("\x1b[J");
        let mut stdout = io::stdout();
        stdout.write_all(out.as_bytes())?;
        stdout.flush()
    }

    /// 读一个按键；`min 0 time 1` 下无输入时约 100ms 返回 `None`。
    pub fn read_key(&self) -> Key {
        let mut stdin = io::stdin();
        loop {
            let mut b = [0u8; 1];
            match stdin.read(&mut b) {
                Ok(0) => return Key::None,
                Ok(_) => {}
                Err(_) => return Key::None,
            }
            match b[0] {
                0x03 => return Key::CtrlC,
                0x02 => return Key::CtrlB,
                0x0f => return Key::CtrlO,
                0x1b => return self.read_escape(&mut stdin),
                b'\r' | b'\n' => return Key::Enter,
                b'\t' => return Key::Tab,
                0x7f | 0x08 => return Key::Backspace,
                0x20..=0x7e => return Key::Char(b[0] as char),
                lead if lead >= 0x80 => return read_utf8(&mut stdin, lead),
                _ => return Key::None,
            }
        }
    }

    fn read_escape(&self, stdin: &mut io::Stdin) -> Key {
        // 收集 CSI 序列（ESC [ ... final）。超时/EOF 时按 Esc 处理。
        let mut seq: Vec<u8> = Vec::new();
        loop {
            let mut b = [0u8; 1];
            match stdin.read(&mut b) {
                Ok(1) => {}
                _ => return Key::Esc,
            }
            seq.push(b[0]);
            if seq.len() == 1 {
                if b[0] != b'[' && b[0] != b'O' {
                    // Alt+O / Alt+B：给不习惯 Ctrl+字母的终端用户一个别名
                    return match b[0] {
                        b'o' => Key::CtrlO,
                        b'b' => Key::CtrlB,
                        _ => Key::Esc,
                    };
                }
                continue;
            }
            if (0x40..=0x7e).contains(&b[0]) {
                break;
            }
            if seq.len() > 16 {
                return Key::None;
            }
        }
        parse_csi(&seq)
    }
}

impl Drop for Term {
    fn drop(&mut self) {
        let mut out = io::stdout();
        let _ = out.write_all(b"\x1b[?25h\x1b[?1049l");
        let _ = out.flush();
        let _ = restore(&self.saved);
    }
}

/// 读一个 UTF-8 字符（中文 commit message / 过滤词要用）。
fn read_utf8(stdin: &mut io::Stdin, lead: u8) -> Key {
    let need = match lead {
        0xc0..=0xdf => 1,
        0xe0..=0xef => 2,
        0xf0..=0xf7 => 3,
        _ => return Key::None,
    };
    let mut buf = vec![lead];
    for _ in 0..need {
        let mut x = [0u8; 1];
        match stdin.read(&mut x) {
            Ok(1) => buf.push(x[0]),
            _ => return Key::None,
        }
    }
    match std::str::from_utf8(&buf).ok().and_then(|s| s.chars().next()) {
        Some(c) => Key::Char(c),
        None => Key::None,
    }
}

/// 解析 CSI（`ESC [` 之后的部分，含首字节 `[`/`O`）。
/// 同时兼容经典 xterm 编码和 kitty/xterm 的 `CSI u` / `CSI 27;mod;code~` 扩展编码，
/// 后者在启用了 modifyOtherKeys 的终端里会把 Ctrl-O 送成 `ESC [ 111 ; 5 u`。
pub fn parse_csi(seq: &[u8]) -> Key {
    let Some((&first, rest)) = seq.split_first() else {
        return Key::Esc;
    };
    if first != b'[' && first != b'O' {
        return Key::Esc;
    }
    let Some(&last) = rest.last() else {
        return Key::Esc;
    };
    let body = &rest[..rest.len() - 1];
    let text = String::from_utf8_lossy(body);
    let params: Vec<u32> = text
        .split(';')
        .filter_map(|p| p.parse::<u32>().ok())
        .collect();

    match last {
        b'A' => Key::Up,
        b'B' => Key::Down,
        b'C' => Key::Right,
        b'D' => Key::Left,
        b'H' => Key::Home,
        b'F' => Key::End,
        b'Q' => Key::F2,
        b'~' => match params.first().copied().unwrap_or(0) {
            12 => Key::F2,
            1 | 7 => Key::Home,
            2 => Key::None,
            3 => Key::Backspace,
            4 | 8 => Key::End,
            5 => Key::PageUp,
            6 => Key::PageDown,
            // xterm modifyOtherKeys 形式: CSI 27 ; mods ; code ~
            27 => {
                let mods = params.get(1).copied().unwrap_or(1);
                let code = params.get(2).copied().unwrap_or(0);
                ctrl_char(mods, code)
            }
            _ => Key::None,
        },
        // kitty / xterm CSI-u: CSI code ; mods u
        b'u' => {
            let code = params.first().copied().unwrap_or(0);
            let mods = params.get(1).copied().unwrap_or(1);
            ctrl_char(mods, code)
        }
        _ => Key::None,
    }
}

/// mods: 1 + 位掩码（1=Shift, 2=Alt, 4=Ctrl）。
fn ctrl_char(mods: u32, code: u32) -> Key {
    let ctrl = mods > 1 && (mods - 1) & 4 != 0;
    if ctrl {
        match code {
            2 | 98 => Key::CtrlB,
            3 | 99 => Key::CtrlC,
            15 | 111 => Key::CtrlO,
            9 | 105 => Key::Tab,
            13 | 109 => Key::Enter,
            _ => Key::None,
        }
    } else {
        match code {
            9 => Key::Tab,
            13 | 10 => Key::Enter,
            27 => Key::Esc,
            127 => Key::Backspace,
            _ => char::from_u32(code).map(Key::Char).unwrap_or(Key::None),
        }
    }
}

fn stty(args: &[&str]) -> io::Result<String> {
    let out = Command::new("stty")
        .args(args)
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn raw_on() -> io::Result<()> {
    Command::new("stty")
        .args(["-icanon", "-echo", "-isig", "min", "0", "time", "1"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    Ok(())
}

fn restore(saved: &str) -> io::Result<()> {
    let mut cmd = Command::new("stty");
    for part in saved.split_whitespace() {
        cmd.arg(part);
    }
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    Ok(())
}
