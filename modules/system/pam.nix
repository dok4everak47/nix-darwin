{
  config,
  pkgs,
  ...
}: {
  # ── PAM / sudo 认证 (2026-08-29) ────────────────────────────────────
  # Touch ID for sudo（macOS 13+ 原生支持，nix-darwin 26.05 新选项）。
  #
  # 注意：旧选项 security.pam.enableSudoTouchIdAuth 已在 26.05 重命名为
  # security.pam.services.sudo_local.touchIdAuth（与 NixOS 一致），用旧的
  # 会直接 build 报错（mkRemovedOptionModule）。
  #
  # reattach: 修复 tmux/screen 等 bootstrap session 场景下 Touch ID 失效
  # （pam_reattach.so 把认证请求转发回登录会话）。用户重度使用 tmux，
  # 不开这个 tmux 里的 sudo 只能用密码。
  security.pam.services.sudo_local = {
    enable = true;
    touchIdAuth = true;
    reattach = true;
    # watchIdAuth = false;  # Apple Watch 认证，不需要
  };
}
