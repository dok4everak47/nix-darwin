{ config, lib, pkgs, ... }:

{
  # ── tmux ─────────────────────────────────────────────────────────────
  # 用 nix-darwin 内置的 programs.tmux 模块管理（源码见
  # nix-darwin-26.05 modules/programs/tmux.nix），不经过 Home Manager：
  #   * /etc/tmux.conf 由本模块声明式生成（environment.etc）
  #   * PATH 上的 tmux 是 wrapper，启动时强制 -f /etc/tmux.conf，
  #     因此 ~/.tmux.conf 不再被读取——所有配置必须写在这里
  #   * 配置末尾会 source-file -q /etc/tmux.conf.local：临时实验、
  #     本机特例可放该文件（不存在也不报错），无需改 Nix 重新构建
  #
  # 二进制说明: enable 后模块自动提供 wrapped tmux 并加入系统 profile，
  # 故 system-packages.nix 里的裸 pkgs.tmux 已移除，避免 profile 冲突。
  #
  # 生效方式:   darwin-rebuild switch --flake .#dok4ever-mac
  # 会话内热载: prefix r（下方 bind r），或 :source-file /etc/tmux.conf
  programs.tmux = {
    enable = true;

    # base-index 1 / renumber-windows / escape-time 0 / aggressive-resize /
    # status-keys emacs / 新窗口继承当前路径；默认终端用 screen-256color
    # （macOS 自带 terminfo 里最稳的 256 色条目，兼容 Terminal.app/iTerm/Ghostty）
    enableSensible = true;

    enableMouse = true;

    # copy-mode vi 键位 + hjkl 切 pane；y 复制走 pbcopy（macOS 剪贴板直通）
    enableVim = true;

    # M-p: fzf 选文本粘贴到当前 pane; M-s: fzf 选会话切换。
    # fzf 由 modules/shell.nix 安装在系统 profile。
    enableFzf = true;

    # 显式关闭分屏键反转：stateVersion=6 且 enableSensible 时模块默认会把
    # % 和 " 的横竖语义对调；这里保持 tmux 原生习惯（% 左右 / " 上下）。
    # 更顺手的形状键位 | 和 - 见 extraConfig。
    reverseSplitBindings = false;

    extraConfig = ''
      # ── 会话/窗口行为 ──────────────────────────────────────────────
      set -g history-limit 50000
      set -g automatic-rename on       # 窗口标题跟随前台命令
      set -g focus-events on           # nvim 在 tmux 内能收到 FocusGained/Lost

      # ── 分屏快捷键（继承当前路径；保留原生 % 和 " 不动）────────
      # 形状助记: | 竖线 → 左右分屏, - 横线 → 上下分屏
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # ── 状态栏 ────────────────────────────────────────────────────
      set -g status-interval 5

      # ── 重载配置 ──────────────────────────────────────────────────
      # wrapper 固定读 /etc/tmux.conf，热载同一个文件即拿到最新内容
      bind r source-file /etc/tmux.conf \; display-message "tmux.conf reloaded"
    '';
  };
}
