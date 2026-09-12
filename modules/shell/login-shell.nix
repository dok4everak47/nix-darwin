{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};

  # ── 支持的 shell(单一事实来源)─────────────────────────────────────
  # 新增一个 shell 只改这里一行,下面三处会自动跟着走:
  #   /etc/shells 白名单、调度器里的名字→路径映射、`sw` 的输出。
  # 每个包必须带 shellPath(nixpkgs 的 bash/zsh/fish/nushell 都有),nix-darwin
  # 才能把它映射成稳定的 /run/current-system/sw/bin/<name> 路径。
  supportedShells = {
    nu = pkgs.nushell; # 配置见 modules/shell/nushell.nix(env.nu/config.nu)
    zsh = pkgs.zsh; # 配置见 modules/shell/{default,aliases,env,plugins,functions}.nix
  };

  # ── 默认登录 shell ──────────────────────────────────────────────────
  # 只在状态文件缺失/损坏时生效(首次登录、状态文件被删)。日常切换用
  # `sw nu` / `sw zsh` 写状态文件,不需要动这里、不需要 rebuild。
  defaultLoginShell = "nu";

  shellChoices = lib.attrNames supportedShells;

  # nix-darwin 对 shell 包的路径映射约定(见其 modules/system/shells.nix)。
  shellBin = p: "/run/current-system/sw${p.shellPath}";

  # ── 生成调度器 / CLI ────────────────────────────────────────────────
  # modules/shell/shellsw.sh 是纯 bash、零外部依赖;这里注入它需要的三个
  # 变量。脚本按 $0 的名字分角色:swsh = 登录 shell 调度器,sw = 用户命令。
  swHeader = ''
    SW_DEFAULT="${defaultLoginShell}"
    SW_ORDER="${lib.concatStringsSep " " shellChoices}"
    declare -A SW_SHELLS=(${lib.concatStringsSep " " (
      lib.mapAttrsToList (name: pkg: "[${name}]=\"${shellBin pkg}\"") supportedShells
    )})
  '';

  swCore = pkgs.writeShellScriptBin "sw" (swHeader + builtins.readFile ./shellsw.sh);

  # 同一个脚本装两个名字(symlinkJoin 保持 bin/ 布局,不额外套一层 shell):
  #   sw    — 用户命令(查看 / 切换)
  #   swsh  — 登录 shell 调度器(dscl UserShell 指过来)
  swBin = pkgs.symlinkJoin {
    name = "shellsw";
    paths = [swCore];
    postBuild = "ln -s sw $out/bin/swsh";
  };

  # nix-darwin 的 types.shellPackage 要求有 shellPath 属性,才会把 users.shell
  # 映射成 /run/current-system/sw/bin/swsh(恒定路径 → rebuild 后不漂移,
  # 不会像裸 store 路径那样在 GC 后变成死链)。
  swShell = swBin // {shellPath = "/bin/swsh";};
in {
  # ── 登录 shell:交给调度器 ──────────────────────────────────────────
  # dscl UserShell 每次 rebuild 同步为 /run/current-system/sw/bin/swsh;真正的
  # shell 由调度器读状态文件决定。uid 501 的保护与边界见 modules/system/users.nix。
  users.users.${shared.username} = {
    shell = swShell;
    # 调度器不是 nixpkgs 的 bash/zsh/fish,不在 nix-darwin 的
    # programs.<shell>.enable 白名单里,必须跳过检查。
    ignoreShellProgramCheck = true;
  };

  # ── 登录 shell 白名单(/etc/shells)──────────────────────────────────
  # macOS 只接受列在这份清单里的 shell(chsh/ftpd 校验),调度器与两个候选
  # shell 都要在。
  environment.shells = [pkgs.nushell pkgs.zsh swShell];

  # `sw` / `swsh` 落到 /run/current-system/sw/bin(swShell 的 shellPath 映射
  # 依赖这一点)。
  environment.systemPackages = [swBin];

  assertions = [
    {
      assertion = builtins.elem defaultLoginShell shellChoices;
      message = "modules/shell/login-shell.nix: defaultLoginShell=\"${defaultLoginShell}\" 不在 supportedShells 里";
    }
  ];
}
