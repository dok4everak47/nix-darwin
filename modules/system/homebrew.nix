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
  #   - imagemagick-full: Homebrew "full" variant with the complete
  #     delegate matrix (keg-only; opt/bin is prepended to PATH in
  #     shell/env.nix so the full build wins). ffmpeg-full was removed
  #     2026-08 (unused) — do not re-add unless a project needs full
  #     codec support not in nixpkgs ffmpeg.
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
      # Full feature set — required; do NOT replace with nixpkgs imagemagick.
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
