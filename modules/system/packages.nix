{
  config,
  pkgs,
  ...
}: {
  # Packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  #
  # 2026-08: starship init 通过 programs.zsh.promptInit 接入；fzf/atuin
  # 安装在 modules/shell/；direnv 由 programs.direnv.enable 自动提供;
  # taskwarrior3/taskwarrior-tui/vit 已迁移 htask, 遗留已删。
  #
  # tmux (2026-08): moved to modules/programs/tmux.nix — programs.tmux.enable
  # ships a wrapped tmux (-f /etc/tmux.conf); a bare pkgs.tmux here would collide.
  # Homebrew takeover (2026-08): CLI tools migrated here from brew.
  # ffmpeg-full / imagemagick-full stay on Homebrew (full feature set),
  # managed in modules/system/homebrew.nix and prioritized in shell PATH.
  #
  # Overlays (openmp empty-patch filter, opencode codesign fix, atuin from
  # unstable with search patch) live in modules/overlays/.
  environment.systemPackages = with pkgs; [
    vim
    neovim
    fastfetch
    wget
    curl
    bat
    eza
    himalaya
    neomutt
    isync
    yazi
    (emacs.override {
      withXwidgets = true;
      withXinput2 = true;
    }) # Emacs 30 + xwidget-webkit (内嵌浏览器, 跑 CSS/JS); GUI at /Applications/Nix Apps/Emacs.app
    fd
    nmap
    nil
    alejandra
    ghostty-bin
    zed-editor
    mdcat
    opencode

    # ── Migrated from Homebrew ────────────────────────────────────────
    antidote # zsh plugin manager (replaces /opt/homebrew/opt/antidote)
    cmake
    delta # git-delta
    jq
    lazygit
    nb
    ntfy
    poppler-utils # pdftotext, pdfinfo, ... (poppler is the GLib lib)
    resvg
    ripgrep
    _7zz # 7-Zip CLI (binary is `7zz`; replaces brew sevenzip)
    socat
    zellij
  ];

  # ── LANG (2026-08-14) ────────────────────────────────────────────────
  # macOS 系统 locale 是 en_CN (无效); Emacs NS 端口在 LANG 未设置时
  # 从系统读 locale → 启动警告 "LANG=en_CN.UTF-8 cannot be used"。
  # environment.variables 写入 launchd 环境, GUI 应用 (Dock 启动的 Emacs)
  # 都需要这里显式设置; 终端 shell 的 LANG 在 shell/env.nix 里。
  environment.variables.LANG = "en_US.UTF-8";
}
