{
  config, pkgs, inputs, unstable, ...  # via extraSpecialArgs
}:

{
  home.username = "dok4ever";
  home.homeDirectory = "/Users/dok4ever";
  home.stateVersion = "26.05";  # Matches HM release-26.05 branch

  programs.home-manager.enable = true;

  # ── User-level packages ─────────────────────────────────────────────
  # CLI tools moved here from systemPackages (2026-08).
  home.packages = [
    pkgs.fzf
    # atuin from unstable: stable 26.05 (18.15.2) predates the 2026-07-09
    # "shell" migration in the existing history.db.
    (unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin)
  ];

  # ── Zsh (HM overwrites ~/.zshrc; old content migrated here) ─────────
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Aliases migrated from .zshrc
    shellAliases = {
      ls = "eza";
      ll = "eza -lah";
      la = "eza -a";
      tree = "eza --tree";
      "-" = "cd -";
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

    # Environment variables (proxy, PATH, etc.)
    envExtra = ''
      # ── Proxy (ClashX 7890) ─────────────────────────────────────────
      export http_proxy=http://127.0.0.1:7890
      export https_proxy=http://127.0.0.1:7890
      export HTTP_PROXY=http://127.0.0.1:7890
      export HTTPS_PROXY=http://127.0.0.1:7890
      export all_proxy=socks5://127.0.0.1:7890
      export ALL_PROXY=socks5://127.0.0.1:7890
      export no_proxy=localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com
      export NO_PROXY=localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com
      export LARK_CLI_NO_PROXY=1

      # PATH additions
      export PATH="/Library/TeX/texbin:/usr/local/texlive/2026basic/bin/universal-darwin:$HOME/.local/bin:$HOME/bin:$PATH"

    '';

    # Everything that doesn't map to a structured HM option lives here.
    initContent = ''
      # iterm2 shell integration
      test -e "''${HOME}/.iterm2_shell_integration.zsh" && source "''${HOME}/.iterm2_shell_integration.zsh"

      # Nix profile env
      [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

      # NVM
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

      # yazi wrapper: cd to last dir on exit
      function y() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
        command yazi "$@" --cwd-file="$tmp"
        IFS= read -r -d ''' cwd < "$tmp"
        [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
        command rm -f -- "$tmp"
      }

      # ── antidote (zsh plugin manager) ──────────────────────────────
      # Cache moved out of ~/Library/Caches to survive cleanup tools
      zstyle ':antidote:home' dir "$HOME/.local/share/antidote"
      # source $(brew --prefix) 在 nix 环境 PATH 无 brew 会报错, 写死绝对路径
      source /opt/homebrew/opt/antidote/share/antidote/antidote.zsh

      # Rebuild if bundle is stale OR cache directory was cleaned
      if [[ ! ~/.zsh_plugins.zsh -nt ~/.zsh_plugins.txt ]] || [[ ! -d "$HOME/.local/share/antidote" ]]; then
        antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
      fi

      # ── Completion: case-insensitive (fzf-tab) ───────────────────
      # zsh 默认补全大小写敏感；这里让小写也能匹配大写(cd doc → Documents)
      # 只加大小写部分, fuzzy 交给 fzf 本身(fzf-tab 下加 r:/l: matcher 会撑爆候选列表)
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

      source ~/.zsh_plugins.zsh

      # bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    '';
  };

  # ── starship (replaces `eval "$(starship init zsh)"`) ───────────────
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── zoxide (replaces `eval "$(zoxide init zsh)"`) ───────────────────
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── atuin (replaces `eval "$(atuin init zsh)"`) ─────────────────────
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    package = unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin;
  };

  # ── direnv (darwin-level already enables programs.direnv; this adds
  # the zsh hook via HM instead of manually `eval "$(direnv hook zsh)"`).
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # ── fzf ─────────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}