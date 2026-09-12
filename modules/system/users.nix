{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── 用户声明(nix-darwin 接管)─────────────────────────────────────
  # 将 dok4ever(uid 501, 现有 macOS admin 用户)纳入 knownUsers,使登录
  # shell 由 nix-darwin 声明式管理:每次 `darwin-rebuild switch` 都会通过
  # dscl 把 UserShell 同步为 /run/current-system/sw/bin/swsh —— 即 shell
  # 切换器调度器(modules/shell/login-shell.nix),取代手动 chsh。
  #
  # 安全边界(见 nix-darwin modules/users/default.nix 激活脚本):
  #   - uid 501 不在删除范围(仅 uid > 501 会被 deletedUsers 处理),且是
  #     system.primaryUser(homebrew.nix),双重保护不会误删;
  #   - uid 匹配现有用户 → 激活只执行 dscl 同步 gid/shell,不动家目录;
  #   - home 必须与现状一致(/Users/dok4ever),否则激活校验中止。
  users.users.${shared.username} = {
    uid = 501;
    home = shared.home;
    # shell 指向调度器;候选 shell(nu/zsh)、/etc/shells 白名单与
    # ignoreShellProgramCheck 一并声明在 modules/shell/login-shell.nix。
  };

  # 纳入 nix-darwin 用户管理(激活时同步 UserShell 等属性)。
  users.knownUsers = [ shared.username ];
}
