# Shared constants used across multiple nix-darwin modules.
# Import in any module with:
#   let shared = import ../lib.nix { inherit pkgs; };
# or from a file directly under modules/:
#   let shared = import ./lib.nix { };
{ }: rec {
  # ── Identity ────────────────────────────────────────────────────────
  username = "dok4ever";
  home = "/Users/${username}";

  # ── Proxy ───────────────────────────────────────────────────────────
  # 单一事实来源 (2026-09-23 收拢)。改代理只动下面 4 个常量:
  #   nix-daemon      → modules/system/nix.nix (nix.envVars)
  #   所有 zsh/nushell → environment.variables → set-environment (modules/shell/{env,nushell}.nix)
  #   GUI app         → launchd.user.agents.proxy-env (modules/shell/env.nix, 每次登录 setenv)
  #   zsh 函数        → modules/shell/functions.nix (插值 shared.proxyUrl)
  #
  # 注意: templates/*/flake.nix 是独立 flake (被 `nix flake init` 原样复制, 不能
  # import 本文件), 每个模板文件内自带一份同名常量; scripts/npm-proxy.py 也镜像
  # 端口。改端口时这两处必须一起改。
  proxyHost = "127.0.0.1";
  proxyPort = 7890;
  proxyUrl = "http://${proxyHost}:${toString proxyPort}";
  proxySocksUrl = "socks5://${proxyHost}:${toString proxyPort}";

  # 直连名单 (2026-09-23 与手写的 ~/Library/LaunchAgents/com.dok4ever.proxy-env.plist
  # 对齐, 那份已冗余可删): feishu/larksuite = 飞书 CLI; volces/moonshot = ARK 与
  # Kimi 的国内 API。shell 与 GUI 现在共用这一份, 不再出现 "终端走代理 / GUI 直连"。
  proxyNoProxy = "localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com,ark.cn-beijing.volces.com,.volces.com,.moonshot.cn";

  proxyEnv = {
    http_proxy = proxyUrl;
    https_proxy = proxyUrl;
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    no_proxy = proxyNoProxy;
    NO_PROXY = proxyNoProxy;
  };

  # SOCKS 变体只对用户 shell / GUI app 有意义, nix-daemon 只需要 HTTP(S)_PROXY。
  # 2026-09-06 注释掉 all_proxy=socks5 — git 会优先用 env all_proxy(socks5),
  # 导致 GUI app (nvim) 里 git 拉 github 443 报 SSL_ERROR_SYSCALL (Lazy update 失败)。
  # 2026-09-23 起 shell 函数与 devShell 模板也统一只导出 http(s), 不再夹带 socks5。
  shellProxyExtra = {
    # all_proxy = proxySocksUrl;
    # ALL_PROXY = proxySocksUrl;
    LARK_CLI_NO_PROXY = "1";
  };

  # ── Canonical PATH ordering ─────────────────────────────────────────
  # Shared by shellInit (all zsh, including non-interactive) and
  # interactiveShellInit (re-asserted after ~/.zprofile runs
  # `brew shellenv` in login shells).
  #   1. user nix profile (devShell 装的工具, e.g. rust-analyzer) — devShell 优先
  #      (imagemagick-full keg removed 2026-09-03, now nixpkgs system profile).
  #   2. Nix system profile — migrated CLI tools — beats /opt/homebrew/bin.
  #   3. TeX, user bins, then /opt/homebrew/bin as a fallback.
  #   4. macOS system paths are preserved via $path (never wholesale-replace).
  pathInit = ''
    typeset -U path
    path=(
      # user nix profile (devShell 装的 rust-analyzer 1.98.0 走这里) 优先
      $HOME/.nix-profile/bin
      /nix/var/nix/profiles/default/bin
      # /run/current-system/sw/bin  # (fallback, system rust-analyzer 老版)
      /nix/var/nix/profiles/system/sw/bin
      /Library/TeX/texbin
      /usr/local/texlive/2026basic/bin/universal-darwin
      $HOME/.local/bin
      $HOME/bin
      /opt/homebrew/bin
      /opt/homebrew/sbin
      /usr/local/bin
      $path
    )
    export PATH
  '';

  # ── nushell PATH (与 pathInit 严格同序) ─────────────────────────────
  # nushell 是登录 shell 时不读 /etc/zshenv / path_helper,`$env.PATH` 为
  # nothing,须在 env.nu 里完整重建。顺序与上面 pathInit 保持一致,
  # 末尾附 macOS 系统路径兜底(不依赖 launchd 已注入)。
  pathInitNu = ''
    $env.PATH = ([
      ($env.HOME | path join ".nix-profile/bin")
      "/nix/var/nix/profiles/default/bin"
      # "/run/current-system/sw/bin"  # (fallback, 与 pathInit 注释对应)
      "/nix/var/nix/profiles/system/sw/bin"
      "/Library/TeX/texbin"
      "/usr/local/texlive/2026basic/bin/universal-darwin"
      ($env.HOME | path join ".local/bin")
      ($env.HOME | path join "bin")
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
      "/usr/local/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ] | uniq)
  '';
}
