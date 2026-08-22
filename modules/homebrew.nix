{ config, pkgs, ... }:

{
  # Homebrew activation runs as the primary (non-root) user.
  system.primaryUser = "dok4ever";

  # ── Homebrew as a nix-darwin-controlled backend ─────────────────────
  # Nix is the control plane; Homebrew only carries things that nixpkgs
  # cannot (or cannot with the required feature set):
  #   - ffmpeg-full / imagemagick-full: Homebrew "full" variants with the
  #     complete codec / delegate matrix (keg-only; their opt/bin is
  #     prepended to PATH in shell.nix so the full builds win).
  #   - Casks: GUI apps, fonts and the BasicTeX pkg installer.
  # Everything else (CLI tools) lives in nixpkgs — see system-packages.nix.
  #
  # Day-to-day usage: run `darwin-rebuild switch`, not `brew install`.
  # Home-manager is intentionally NOT used (user decision, permanent).
  homebrew = {
    enable = true;
    prefix = "/opt/homebrew";

    # forel cask lives in the lab421 tap.
    taps = [
      { name = "lab421/tap"; trusted = true; }
    ];

    brews = [
      # Full feature sets — required; do NOT replace with nixpkgs ffmpeg/imagemagick.
      { name = "ffmpeg-full"; }
      { name = "imagemagick-full"; }
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
      # Phase 2: uninstall any Homebrew package (formula/cask/tap) not
      # declared above, so the brew prefix converges to the config.
      # Use "zap" instead if you also want cask prefs/caches removed.
      cleanup = "uninstall";
      autoUpdate = false;
      upgrade = false;
    };

    global = {
      # Point manual `brew bundle` at the generated, store-backed Brewfile.
      brewfile = true;
      # Suppress Homebrew's own auto-update on manual brew commands;
      # upgrades are an explicit, deliberate action.
      autoUpdate = false;
    };
  };
}
