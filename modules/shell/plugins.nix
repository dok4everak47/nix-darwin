{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
in {
  # ── Interactive zsh init ─────────────────────────────────────────────
  # nix-darwin sources this in /etc/zshrc AFTER compinit setup; it runs
  # before the user's ~/.zshrc.
  programs.zsh.interactiveShellInit = ''
    # Aliases starting with `-` can't live in environment.shellAliases
    # (nix-darwin writes those to /etc/zprofile, where zsh errors with
    # "bad option: -="). Define them here with `alias --` in interactive
    # shells only.
    alias -- -= 'cd -'
    alias -- --='cd ..'

    # Re-assert PATH after ~/.zprofile runs `brew shellenv` (see lib.pathInit).
    ${shared.pathInit}

    # Rebuild if bundle is stale OR cache directory was cleaned
    if [[ ! ~/.zsh_plugins.zsh -nt ~/.zsh_plugins.txt ]] || [[ ! -d "$HOME/.local/share/antidote" ]]; then
        antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
    fi

    # ── Completion: case-insensitive (fzf-tab) ───────────────────
    # zsh 默认补全大小写敏感；这里让小写也能匹配大写(cd doc → Documents)
    zstyle ':completion:*' matcher-list 'm:{a-zA-z}={A-Za-z}'

    # Autoload compinit before sourcing plugins (plugins call compdef)
    autoload -U compinit

    source ~/.zsh_plugins.zsh
    # bun completions
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

    # ── fzf key bindings & completion ──────────────────────────────
    # HM's programs.fzf did this automatically; nix-darwin's enableFzf*
    # only covers History/Git/Completion, not Ctrl-T file widget.
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh
    source ${pkgs.fzf}/share/fzf/completion.zsh

    # ── zoxide (replaces HM programs.zoxide.enableZshIntegration) ──
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"

    # ── atuin (replaces HM programs.atuin.enableZshIntegration) ────
    eval "$(${pkgs.atuin}/bin/atuin init zsh)"

    # Now run compinit to process all compdefs registered by plugins/inits
    compinit
  '';
}
