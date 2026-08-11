{
  # Enable direnv + nix-direnv (use flake support)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # 静音: 通过 ~/.config/direnv/config.toml 设置 log_format 为空
  };
}
