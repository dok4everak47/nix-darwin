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
    '';
  };
}
