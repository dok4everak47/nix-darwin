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
    (pkgs.emacs.override { withXwidgets = true; withXinput2 = true; }) # Emacs 30 + xwidget-webkit (内嵌浏览器, 跑 CSS/JS)
    pkgs.fd
    pkgs.imagemagick
    pkgs.nmap
  ];
}
