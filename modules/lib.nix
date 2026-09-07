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
  # Single source of truth. nix.envVars (daemon) and environment.variables
  # (shell/GUI) both reference these, so the two never drift apart.
  proxyEnv = {
    http_proxy = "http://127.0.0.1:7890";
    https_proxy = "http://127.0.0.1:7890";
    HTTP_PROXY = "http://127.0.0.1:7890";
    HTTPS_PROXY = "http://127.0.0.1:7890";
    no_proxy = "localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com";
    NO_PROXY = "localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com";
  };

  # SOCKS variants are only relevant for user shells / GUI apps, not the
  # nix-daemon (which only needs HTTP(S)_PROXY).
  # SOCKS variants: 2026-09-06 注释掉 — all_proxy=socks5 污染 GUI app (nvim) git,
  # git 优先用 env all_proxy(socks5) → github 443 SSL_ERROR_SYSCALL (Lazy update 失败)。
  # ClashBar TUN/系统代理模式下不需要 socks5 env。
  shellProxyExtra = {
    # all_proxy = "socks5://127.0.0.1:7890";
    # ALL_PROXY = "socks5://127.0.0.1:7890";
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
