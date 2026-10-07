{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # Homebrew activation runs as the primary (non-root) user.
  system.primaryUser = shared.username;

  # ── Homebrew as a nix-darwin-controlled backend ─────────────────────
  # Nix is the control plane; Homebrew only carries things that nixpkgs
  # cannot (or cannot with the required feature set):
  #   - imagemagick-full: migrated to nixpkgs imagemagick 2026-09-03
  #     (packages.nix, ghostscriptSupport=true). ffmpeg-full 不要重新引入
  #     (2026-08 删除, 无项目需要那一堆 codec)。
  #   - ffmpeg / yt-dlp: 2026-10-07 起用 brew 版（用户要求，见 AGENTS.md
  #     规则 4 例外）—— 版本跟进不必 rebuild，PATH 里 /opt/homebrew/bin 在首位。
  #   - Casks: GUI apps, fonts and the BasicTeX pkg installer.
  # Everything else (CLI tools) lives in nixpkgs — see system/packages.nix.
  #
  # Day-to-day usage: run `darwin-rebuild switch`, not `brew install`.
  # Home-manager is intentionally NOT used (user decision, permanent).
  homebrew = {
    enable = true;
    prefix = "/opt/homebrew";

    # forel cask lives in the lab421 tap.
    taps = [
      {
        name = "lab421/tap";
        trusted = true;
      }
      {
        name = "realskyrin/tap";
        trusted = true;
      }
      {
        name = "kamillobinski/thock";
        trusted = true;
      }
      {
        name = "abue-ammar/tinycast";
        trusted = true;
      }
      {
        name = "rana-gmbh/netfluss";
        trusted = true;
      }
      {
        name = "omlahore/tap";
        trusted = true;
      }
    ];

    brews = [
      "mole"
      # Python console lorem ipsum generator (per9000/lorem) — nixpkgs
      # "lorem" is an unrelated GNOME app, so this one lives on Homebrew.
      {name = "lorem";}
      "removemacai"
      # yt-dlp (2026-10-07, 用户要求从 nixpkgs 迁来): brew 版自带 curl-cffi
      # (--impersonate chrome) + yt-dlp-ejs/deno，且 `brew upgrade` 无需
      # rebuild 就能跟进版本。必须声明在这里，否则 cleanup=uninstall 会删掉。
      "yt-dlp"
      # ffmpeg (2026-10-07, 用户要求从 nixpkgs 迁来): brew 版 9.x 自带
      # ffmpeg/ffprobe/ffplay，`brew upgrade` 跟进版本不用 rebuild。
      # 注意：不要换成 ffmpeg-full。同样是 cleanup=uninstall 前必须声明项。
      "ffmpeg"
    ];

    casks = [
      "robbietilton-compositor"
      "snapzy"
      "basictex"
      "flowvision"
      "font-symbols-only-nerd-font"
      "forel"
      "whatcable"
      "input-source-pro"
      # "tinycast"
      # "netfluss"
      # NOTE: emacs-app intentionally absent — Nix Emacs
      # (/Applications/Nix Apps/Emacs.app) is the canonical install.
    ];

    onActivation = {
      # Uninstall any Homebrew package not declared above, so the brew
      # prefix converges to the config. Use "zap" to also purge cask
      # prefs/caches.
      cleanup = "uninstall";
      # Idempotent rebuilds (2026-08-29): autoUpdate/upgrade disabled so
      # `darwin-rebuild switch` never touches brew unless a declared
      # package is missing. Upgrade manually when wanted:
      #   brew update && brew upgrade
      autoUpdate = false;
      upgrade = false;
    };

    global = {
      # Point manual `brew bundle` at the generated, store-backed Brewfile.
      brewfile = true;
      # Suppress Homebrew's own auto-update when you run brew commands by
      # hand. Upgrade explicitly with `brew update && brew upgrade`.
      autoUpdate = false;
    };
  };
}
