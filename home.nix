{ config, pkgs, ... }:

{
  home.username = "dok4ever";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  # 用户级包（2026-08 从 systemPackages 迁入）。
  # 注意: 不要启用 programs.starship/zoxide/atuin 配置模块 —
  # shell hook 已在 ~/.zshrc 手动 eval, 启用会重复注入。
  home.packages = [
    pkgs.starship
    pkgs.fzf
    pkgs.zoxide
    pkgs.atuin
  ];
}
