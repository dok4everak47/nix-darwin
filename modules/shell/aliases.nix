{ config, pkgs, ... }:

{
  # ── Shell aliases ────────────────────────────────────────────────────
  # (was programs.zsh.shellAliases in HM)
  environment.shellAliases = {
    ls = "eza";
    ll = "eza -lah --classify --sort=type";
    la = "eza -a";
    tree = "eza --tree";
    # NOTE: "--" is intentionally NOT here — nix-darwin writes shellAliases to
    # /etc/zprofile where zsh errors with "bad option: -=". It's defined via
    # `alias --` in interactiveShellInit (plugins.nix).
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";
    "....." = "cd ../../../..";
    c = "clear";
    v = "nvim";
    vi = "nvim";
    cat = "bat";
    em = "emacs -nw";
  };
}
