//! 安装子菜单的纯逻辑：nix-search 结果解析、packages.nix / homebrew.nix 追加。
//! 不依赖 TUI，便于 `--selftest` 直接测。

use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;

#[derive(Clone, Debug)]
pub struct Hit {
    pub attr: String,
    pub version: String,
    pub programs: String,
}

/// `nix-search foo -m 50` 的一行格式:
/// `python3Minimal @ 3.14.7 : python python3 pydoc3 ...`
pub fn parse_search(out: &str) -> Vec<Hit> {
    out.lines()
        .filter(|l| !l.trim().is_empty())
        .map(|line| {
            let line = line.trim_end();
            match line.split_once(" @ ") {
                Some((attr, rest)) => {
                    let (version, programs) = match rest.split_once(" : ") {
                        Some((v, p)) => (v.to_string(), p.to_string()),
                        None => (rest.to_string(), String::new()),
                    };
                    Hit { attr: attr.trim().to_string(), version, programs }
                }
                None => Hit {
                    attr: line.trim().to_string(),
                    version: String::new(),
                    programs: String::new(),
                },
            }
        })
        .filter(|h| !h.attr.is_empty())
        .collect()
}

/// 在后台线程跑 nix-search，结果通过 channel 回传（UI 不卡）。
pub fn search_async(query: String) -> Receiver<Vec<Hit>> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let out = Command::new("nix-search")
            .args(["--channel=26.05", "-m", "50", &format!("--search={query}")])
            .stdin(Stdio::null())
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();
        let _ = tx.send(parse_search(&out));
    });
    rx
}

fn leading_ws(s: &str) -> &str {
    let end = s.len() - s.trim_start().len();
    &s[..end]
}

/// 把 attr 追加进 `environment.systemPackages = with pkgs; [...]` 的首行之后。
/// 已存在（按整行 trim 比较）的跳过；返回 (新内容, 实际插入数)。
pub fn insert_packages(content: &str, attrs: &[String]) -> Result<(String, usize), String> {
    let mut lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
    let anchor = lines
        .iter()
        .position(|l| l.contains("environment.systemPackages = with pkgs;"))
        .ok_or_else(|| String::from("找不到 environment.systemPackages 列表"))?;
    let bracket = if lines[anchor].contains('[') {
        anchor
    } else {
        (anchor..lines.len())
            .find(|&i| lines[i].contains('['))
            .ok_or_else(|| String::from("找不到列表左括号"))?
    };
    let indent = lines
        .get(bracket + 1)
        .map(|l| leading_ws(l))
        .filter(|s| !s.is_empty())
        .unwrap_or("      ")
        .to_string();
    let mut inserted = 0;
    let mut fresh: Vec<String> = Vec::new();
    for a in attrs {
        let a = a.trim();
        if a.is_empty() {
            continue;
        }
        let exists = lines.iter().any(|l| l.trim() == a || l.trim().starts_with(&format!("{a} ")));
        if !exists {
            fresh.push(format!("{}{}", indent, a));
            inserted += 1;
        }
    }
    if inserted == 0 {
        return Ok((content.to_string(), 0));
    }
    lines.splice(bracket + 1..bracket + 1, fresh);
    Ok((lines.join("\n") + "\n", inserted))
}

/// 把 brew 包声明追加进 homebrew.nix 的 `brews = [` 或 `casks = [`。
pub fn insert_brew(content: &str, name: &str, cask: bool) -> Result<(String, bool), String> {
    let mut lines: Vec<String> = content.lines().map(|s| s.to_string()).collect();
    let key = if cask { "casks = [" } else { "brews = [" };
    let pos = lines
        .iter()
        .position(|l| l.contains(key))
        .ok_or_else(|| format!("homebrew.nix 里找不到 `{key}`"))?;
    let quoted = format!("\"{}\"", name);
    let mut dup = false;
    for l in lines.iter().skip(pos + 1) {
        let t = l.trim();
        if t.starts_with(']') {
            break;
        }
        if t.trim_end_matches(';') == quoted || t.contains(&format!("name = \"{name}\"")) {
            dup = true;
            break;
        }
    }
    if dup {
        return Ok((content.to_string(), false));
    }
    let indent = lines
        .get(pos + 1)
        .map(|l| leading_ws(l))
        .filter(|s| !s.is_empty())
        .unwrap_or("      ")
        .to_string();
    lines.insert(pos + 1, format!("{}{}", indent, quoted));
    Ok((lines.join("\n") + "\n", true))
}

/// 判断 brew 包是 formula 还是 cask（向前者优先）。
pub fn brew_is_cask(name: &str) -> bool {
    let cask = Command::new("brew")
        .args(["info", "--cask", name])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    cask
}
