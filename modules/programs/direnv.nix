{
  # Enable direnv + nix-direnv (use flake support)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # 静音 direnv 自身日志 (loading / using flake / export +ENV ...)
    # ⚠️ log_format = "" 无效: direnv 把空字符串当"未设置", 回落默认
    #    "direnv: %s" (2026-09-17 实测 — 所以之前一直有噪音).
    #    真正静音靠 log_filter = "^$": 没有任何日志能匹配空串 → 全部丢弃
    #    (direnv >= 2.36 支持; 本机 2.37.1).
    settings = {
      global.log_filter = "^$";
    };
  };
}
