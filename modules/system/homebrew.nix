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
  #   - ffmpeg-full / imagemagick-full: Homebrew "full" variants with the
  #     complete codec / delegate matrix (keg-only; their opt/bin is
  #     prepended to PATH in shell/env.nix so the full builds win).
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
    ];

    brews = [
      # Full feature sets — required; do NOT replace with nixpkgs ffmpeg/imagemagick.
      {name = "imagemagick-full";}
    ];

    casks = [
      "basictex"
      "flowvision"
      "font-symbols-only-nerd-font"
      "forel"
      # NOTE: emacs-app intentionally absent — Nix Emacs
      # (/Applications/Nix Apps/Emacs.app) is the canonical install.
    ];

    onActivation = {
      # Uninstall any Homebrew package not declared above, so the brew
      # prefix converges to the config. Use "zap" to also purge cask
      # prefs/caches.
      cleanup = "uninstall";
      # Personal, single-user machine: also refresh formulae metadata and
      # upgrade declared packages during rebuild, so `darwin-rebuild switch`
      # is the one command for both config and brew updates. Trades strict
      # idempotence/reproducibility for convenience (fine on a laptop).
      autoUpdate = true;
      upgrade = true;
    };

    global = {
      # Point manual `brew bundle` at the generated, store-backed Brewfile.
      brewfile = true;
      # Suppress Homebrew's own auto-update when you run brew commands by
      # hand. Note: during `darwin-rebuild`, onActivation.autoUpdate=true
      # still updates/upgrades the declared packages; this only governs
      # ad-hoc `brew install`/`brew upgrade` typed in a terminal.
      autoUpdate = false;
    };
  };
}
