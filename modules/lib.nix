# Shared constants used across multiple nix-darwin modules.
# Import in any module with:
#   let shared = import ../lib.nix { inherit pkgs; };
# or from a file directly under modules/:
#   let shared = import ./lib.nix { };
{}: rec {
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
  shellProxyExtra = {
    all_proxy = "socks5://127.0.0.1:7890";
    ALL_PROXY = "socks5://127.0.0.1:7890";
    LARK_CLI_NO_PROXY = "1";
  };

  # ── Canonical PATH ordering ─────────────────────────────────────────
  # Shared by shellInit (all zsh, including non-interactive) and
  # interactiveShellInit (re-asserted after ~/.zprofile runs
  # `brew shellenv` in login shells).
  #   1. keg-only Homebrew full builds beat both nixpkgs and any regular
  #      brew ffmpeg/magick.
  #   2. Nix system profile — migrated CLI tools — beats /opt/homebrew/bin.
  #   3. TeX, user bins, then /opt/homebrew/bin as a fallback.
  #   4. macOS system paths are preserved via $path (never wholesale-replace).
  pathInit = ''
    typeset -U path
    path=(
      /opt/homebrew/opt/ffmpeg-full/bin
      /opt/homebrew/opt/imagemagick-full/bin
      # /run/current-system/sw/bin
      /nix/var/nix/profiles/system/sw/bin
      /nix/var/nix/profiles/default/bin
      $HOME/.nix-profile/bin
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
}
