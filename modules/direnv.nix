{
  # Enable direnv + nix-direnv (use flake support)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # 静音 direnv 日志 (loading/export 信息) — 写到 direnv.toml (direnv 2.37 实际读取的文件)
    config = {
      global.log_format = "";
    };
  };
}
