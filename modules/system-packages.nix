{ config, pkgs, ... }:

{
  # Packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  #
  # 2026-08: starship/fzf/zoxide/atuin 迁至 home.nix (home.packages);
  # direnv 由 programs.direnv.enable 自动提供, 此处冗余已删;
  # taskwarrior3/taskwarrior-tui/vit 已迁移 htask, 遗留已删。
  environment.systemPackages = [
    pkgs.vim
    pkgs.neovim
    pkgs.fastfetch
    pkgs.wget
    pkgs.curl
    pkgs.bat
    pkgs.eza
    pkgs.himalaya
    pkgs.neomutt
    pkgs.isync
    pkgs.yazi
    (pkgs.emacs.override {
      withXwidgets = true;
      withXinput2 = true;
    }) # Emacs 30 + xwidget-webkit (内嵌浏览器, 跑 CSS/JS)
    pkgs.fd
    pkgs.imagemagick
    pkgs.nmap
    pkgs.tmux
    pkgs.nil
    pkgs.alejandra
    pkgs.ghostty-bin
    pkgs.zed-editor
    pkgs.mdcat
    # NOTE: ghostty 在 nixpkgs (26.05 / unstable 6f6fca0) 的 meta.platforms 仅
    # 列 Linux,aarch64-darwin 上求值会直接报 "not available on the requested
    # hostPlatform"。macOS 走 Homebrew Cask 安装官方 .app:
    #   brew install --cask ghostty
  ];

  # ── LANG (2026-08-14) ────────────────────────────────────────────────
  # macOS 系统 locale 是 en_CN (无效); Emacs NS 端口在 LANG 未设置时
  # 从系统读 locale → 启动警告 "LANG=en_CN.UTF-8 cannot be used"。
  # environment.variables 写入 launchd 环境, GUI 应用 (Dock 启动的 Emacs)
  # 都需要这里显式设置; 终端 shell 的 LANG 在 home.nix envExtra 里。
  environment.variables.LANG = "en_US.UTF-8";
}
