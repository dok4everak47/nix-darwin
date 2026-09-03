# Aggregated nix-darwin modules. Ordered: overlays first (so downstream
# package references see the overridden attrs), then system config, shell,
# programs, and fixups. Order within each group is irrelevant — nix-darwin
# merges all module outputs.
{
  imports = [
    # ── Overlays (must precede package references that use overrides) ──
    ./overlays

    # ── System ─────────────────────────────────────────────────────────
    ./system/nix.nix
    ./system/homebrew.nix
    ./system/packages.nix
    ./system/activation.nix
    ./system/pam.nix
    ./system/nitter.nix # self-hosted Nitter (x-tweet-fetcher timeline backend)

    # ── Shell ──────────────────────────────────────────────────────────
    ./shell/default.nix
    ./shell/aliases.nix
    ./shell/env.nix
    ./shell/plugins.nix
    ./shell/functions.nix

    # ── Programs ───────────────────────────────────────────────────────
    ./programs/direnv.nix
    ./programs/elm.nix
    ./programs/rust.nix
    ./programs/tmux.nix
    ./programs/fetch.nix

    # ── Fixes / workarounds ────────────────────────────────────────────
    ./fixes/ssh-config.nix
    ./fixes/dasd-freeze.nix
  ];
}
