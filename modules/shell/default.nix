{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── Zsh (nix-darwin writes /etc/{zshenv,zprofile,zshrc}) ────────────
  # Autosuggestions + syntax-highlighting + fzf-tab come from antidote
  # (~/.zsh_plugins.txt), so we don't enable nix-darwin's built-in copies
  # (they'd double-source and conflict).
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # ── PATH additions ───────────────────────────────────────────────────
  # NOTE: cannot use `environment.variables.PATH = [ ... ]` because nix-darwin
  # writes that to /etc/launchd-environment (space-separated, no shell
  # expansion); $HOME/$path must be evaluated at shell startup, so we use
  # programs.zsh.shellInit (runs for every zsh, including non-interactive).
  # Re-asserted in plugins.nix interactiveShellInit after `brew shellenv`.
  programs.zsh.shellInit = shared.pathInit;

  # ── Prompt: starship ─────────────────────────────────────────────────
  # (replaces HM programs.starship.enableZshIntegration)
  programs.zsh.promptInit = ''
    eval "$(${pkgs.starship}/bin/starship init zsh)"
  '';

  # ── User packages that lived in home.packages under HM ─────────────
  # atuin is provided by the overlay in modules/overlays/ (patched unstable);
  # it must be on PATH because `atuin init` emits a bare `atuin` call.
  # fzf MUST be on PATH too: plugins.nix sources fzf's key-bindings by absolute
  # path, but fzf-tab and zoxide's interactive `zi`/space-Tab invoke the bare
  # `fzf` binary at runtime. Without this it silently does nothing on Tab.
  environment.systemPackages = [
    pkgs.zoxide
    pkgs.atuin
    pkgs.fzf

    # Batch `exec zsh` for herdr shell panes after a rebuild (skips nvim /
    # agent panes via foreground-process check). Source: herdr-reload-shells.sh
    # next to this file; writeShellScriptBin gives it nixpkgs bash (mapfile OK).
    (pkgs.writeShellScriptBin "herdr-reload-shells" (builtins.readFile ./herdr-reload-shells.sh))
  ];
}
