{
  # Enable direnv + nix-direnv (use flake support)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # 静音 direnv 日常日志 (loading / using flake / export +ENV ...)
    # ⚠️ log_format = "" 无效: direnv 把空字符串当"未设置", 回落默认
    #    "direnv: %s" (2026-09-17 实测 — 所以之前一直有噪音).
    #    真正的开关是 log_filter (direnv >= 2.36; 本机 2.37.1): 只有匹配
    #    正则的消息才打印. 不能用 "^$" 全静音 — 它连错误一起吞:
    #    blocked .envrc / exit 1 / flake 求值失败全部无声失败 (2026-09-17
    #    实测). "error|failed" 实测矩阵: 成功加载(首次+缓存)全静默;
    #    blocked / exit 1 / bash 语法错 / flake 求值失败 /
    #    "devShell failed. Falling back" 全部可见. nix 自身 stderr 不走
    #    过滤器, 永远可见 (flake 报错盯得住).
    settings = {
      global.log_filter = "error|failed";
    };
  };
}
