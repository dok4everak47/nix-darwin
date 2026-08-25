{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── Global environment ───────────────────────────────────────────────
  # (HM used programs.zsh.envExtra, per-shell). environment.variables writes
  # launchd env, so both terminal zsh and GUI apps launched from Dock
  # (e.g. Emacs) see these.
  #
  # LANG is declared in system/packages.nix (separate concern kept
  # adjacent to its explanatory comment). Proxy vars come from shared
  # constants so nix-daemon and shell never drift.
  environment.variables =
    {
      EDITOR = "nvim";
      VISUAL = "nvim";
      GIT_EDITOR = "nvim";
    }
    // shared.proxyEnv // shared.shellProxyExtra;
}
