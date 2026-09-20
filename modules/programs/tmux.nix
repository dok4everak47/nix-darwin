{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};

  # gpakosz/.tmux — 强大的 tmux 配置框架 (状态栏/主题/快捷键)
  # 固定 commit (2026-08-24 HEAD), sha256 由 nix-prefetch-url 计算。
  gpakoszTmux = pkgs.fetchFromGitHub {
    owner = "gpakosz";
    repo = ".tmux";
    rev = "58a3dcc0d718ec0fa1c0d5a2fddd640a1ad7a5b7";
    sha256 = "0zky4qkndrs645xnxh6498zc8yj7y581sg72hh0h7b31a5jxng30";
  };
  # ── tmux 里点 OSC 8 文件链接 → 新 pane 打开 ──────────────────────────
  # 光标下有 file:// hyperlink(如 rustlings 输出的练习路径)时, 用 nvim 在
  # 右侧新 pane 打开; 由 extraConfig 第 9 节的两个鼠标绑定调用。
  openLink = pkgs.writeShellScript "tmux-open-os8-link" ''
    uri="$1"
    pane="$2"

    case "$uri" in
      file://*) ;;
      *) exit 0 ;;
    esac

    raw=$(printf '%s' "$uri" | sed 's|^file://||')

    if command -v python3 >/dev/null 2>&1; then
      path=$(python3 -c 'import sys, urllib.parse; sys.stdout.write(urllib.parse.unquote(sys.argv[1]))' "$raw")
      quoted=$(python3 -c 'import sys, shlex; sys.stdout.write(shlex.quote(sys.argv[1]))' "$path")
    else
      path="$raw"
      quoted="'$raw'"
    fi

    [ -f "$path" ] || exit 0

    tmux_bin="$TMUX_PROGRAM"
    [ -n "$tmux_bin" ] || tmux_bin=tmux
    sock="$TMUX_SOCKET"
    editor="$EDITOR"
    [ -n "$editor" ] || editor=nvim
    case "$(basename "$editor")" in
      nvim|vim|vi|hx|helix) ;;
      *) editor=nvim ;;
    esac

    if [ -n "$sock" ]; then
      cwd=$("$tmux_bin" -S "$sock" display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)
      [ -n "$cwd" ] || cwd="$HOME"
      exec "$tmux_bin" -S "$sock" split-window -h -l 50% -c "$cwd" -t "$pane" "$editor $quoted"
    else
      cwd=$("$tmux_bin" display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)
      [ -n "$cwd" ] || cwd="$HOME"
      exec "$tmux_bin" split-window -h -l 50% -c "$cwd" -t "$pane" "$editor $quoted"
    fi
  '';

in {
  # ── tmux (gpakosz 集成版) ─────────────────────────────────────────────
  # 本机 tmux 由 nix-darwin 的 wrapped 二进制提供（强制 -f /etc/tmux.conf）。
  # 配置来源：
  #   1. nix-darwin 内置模块选项（mouse / vim 键位 / fzf 绑定）
  #   2. gpakosz/.tmux — 从 store 引用，提供状态栏/主题/插件/快捷键
  #   3. extraConfig — 我们的自定义覆盖（前缀 C-a、分屏键 | 和 -）
  #   4. /etc/tmux.conf.local — 手动覆写，免重建
  #
  # 生效方式:   darwin-rebuild switch --flake .#dok4ever-mac
  # 会话内热载: prefix r（source-file /etc/tmux.conf）
  programs.tmux = {
    enable = true;

    # gpakosz 自己管理 base-index / renumber-windows / escape-time 等,
    # 关闭 nix 内置的 sensible 避免重复/冲突。
    enableSensible = false;

    # gpakosz 不默认开启鼠标, 我们用 nix 模块开启。
    enableMouse = true;

    # gpakosz 不设 mode-keys, 我们开启 vi 键位。
    enableVim = true;

    # gpakosz 无 fzf 绑定, 保留 nix 模块的 fzf 增强（M-p 选文本 / M-s 切会话）。
    enableFzf = true;

    reverseSplitBindings = false;

    extraConfig = ''
      # ── 1. 设置 TMUX_CONF 环境变量 ──────────────────────────────────
      # TMUX_CONF 指向 gpakosz 源文件, 供 _apply_configuration 生成
      # 状态栏/主题；TMUX_CONF_LOCAL 指向本地覆写, 可手动创建。
      # /etc/tmux.conf.local 做免重建的临时修改。
      set-environment -g TMUX_CONF ${gpakoszTmux}/.tmux.conf
      set-environment -g TMUX_CONF_LOCAL /etc/tmux.conf.local
      # 插件管理器路径: 指向可写位置, 避免 gpakosz 试图写入只读的 store。
      set-environment -g TMUX_PLUGIN_MANAGER_PATH ${shared.home}/.tmux/plugins

      # ── 2. 加载 gpakosz ──────────────────────────────────────
      # 直接从 nix store 引用, 只读, 免安装。
      source-file ${gpakoszTmux}/.tmux.conf

      # ── 3. extended-keys ────────────────────────────────────────────
      # gpakosz 根据终端类型自动开关; 在 Terminal.app 等终端上会关掉,
      # 导致 "Modified Enter keys may not work" 警告, 强制打开即可。
      set -g extended-keys on

      # ── 4. 前缀键: C-a (主前缀) ────────────────────────────────────
      # gpakosz 默认保留 C-b 作为主前缀, C-a 作为第二前缀 (prefix2)。
      # 我们偏好 C-a 为主, 双击穿透（C-a C-a 发送字面 C-a 给 zsh/nvim）。
      set -g prefix C-a
      unbind C-b
      # gpakosz 已设 bind C-a send-prefix -2, 我们覆盖成主前缀穿透
      bind C-a send-prefix

      # ── 5. 分屏快捷键（继承当前路径）──────────────────────────────
      # 形状助记: | 竖线 → 左右分屏, - 横线 → 上下分屏
      # gpakosz 用 bind - split-window -v (上下) 和 bind _ (左右),
      # 我们保留 - 的原意, 新增 | 作为左右分屏。
      bind | split-window -h -c "#{pane_current_path}"

      # ── 6. 状态栏刷新 ──────────────────────────────────────────────
      set -g status-interval 5

      # ── 7. 热重载（覆盖 gpakosz 的 bind r, 走 /etc/tmux.conf）────
      bind r source-file /etc/tmux.conf \; display-message "tmux.conf reloaded"

      # ── 8. OSC 8 超链接转发 ─────────────────────────────
      # xterm-ghostty 的 terminfo 不含 Hls, tmux 内置终端特性表也没有
      # xterm-ghostty 条目 → tmux 认为外层终端不支持 OSC 8 hyperlink,
      # 把程序(Claude Code / crush 等)发出的文件链接静默丢弃, 任何修饰键
      # 都点不开(实测: 声明前客户端输出 0 次 OSC 8, 声明后正常转发)。
      # 匹配的是 client termname, 见 tmux list-clients -F '#{client_termname}'。
      # 提示: tmux 里点链接需 Cmd+Shift+click(mouse on 时 Ghostty 要求
      # 用 Shift 逃逸鼠标捕获), 光按 Cmd 不生效。
      set -ag terminal-features 'xterm-ghostty:hyperlinks'

      # ── 9. 鼠标点 OSC 8 文件链接 = 在 tmux 新 pane 里用 nvim 打开 ────────
      # Alt/Option+左键(M-MouseDown1Pane 在 tmux 里无默认绑定) 与 右键
      # (MouseDown3Pane) 均可触发; 只有在光标下确实有 file:// 链接时才接管,
      # 否则 send-keys -M 把鼠标事件原样转发给 pane 内程序(不破坏 nvim/
      # 滚轮/pane 选择)。点击 rustlings 输出的练习路径即可在右侧新 pane
      # 用 nvim 打开该文件(不再弹 Zed)。
      bind -n M-MouseDown1Pane if-shell -F '#{m:file://*,#{mouse_hyperlink}}' \
        'run-shell -b "${openLink} #{q:mouse_hyperlink} #{q:pane_id}"' \
        'send-keys -M'
      bind -n MouseDown3Pane if-shell -F '#{m:file://*,#{mouse_hyperlink}}' \
        'run-shell -b "${openLink} #{q:mouse_hyperlink} #{q:pane_id}"' \
        'send-keys -M'

      # ── 10. C-a m = 切换 tmux 自己的 mouse ─────────────────────────────
      # off 时 tmux 会向终端下发 DECRST(?1000l/?1002l/?1003l/?1006l), Ghostty
      # 的 terminal flag mouse_event 随之归 none → 悬停链接立刻高亮+预览、
      # Cmd+click 走系统打开; on 时恢复滚轮与上面的鼠标绑定。
      # 这是 tmux 里「hover 高亮」唯一的实现方式: Ghostty 只在没有程序捕获
      # 鼠标时才做链接悬停检测(Surface.zig: mouse_event == .none or
      # (mods.shift and !mouseShiftCapture)); 而 Ghostty 的
      # toggle_mouse_reporting 只改 config.mouse_reporting, 不动 terminal
      # flags, 所以那个键对 hover 完全无效(已实测)。
      bind -T prefix m set -g mouse \; display-message "tmux mouse: #{?mouse,on — 滚轮/鼠标绑定可用,off — 鼠标归 Ghostty(悬停高亮 + Cmd+click)}"
    '';
  };
}
