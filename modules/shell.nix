{ config, pkgs, inputs, unstable, ... }:

let
  # atuin 18.17+ search bug (#3908): `allow_hyphen_values` on the variadic
  # query swallows flags written AFTER the query (e.g. `atuin search git
  # --cmd-only` treats `--cmd-only` as a search term). Patch removes it;
  # hyphen-prefixed queries now need an explicit `--` separator.
  #
  # atuin from unstable: stable 26.05 (18.15.2) predates the 2026-07-09
  # "shell" migration in the existing history.db.
  atuin = (unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin).overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ../atuin-fix-search-hyphen.patch ];
  });

  # Canonical PATH ordering, shared by shellInit (all zsh, including
  # non-interactive) and interactiveShellInit (re-asserted after
  # ~/.zprofile runs `brew shellenv` in login shells).
  #   1. keg-only Homebrew full builds beat both nixpkgs and any regular
  #      brew ffmpeg/magick.
  #   2. Nix system profile — migrated CLI tools — beats /opt/homebrew/bin.
  #   3. TeX, user bins, then /opt/homebrew/bin as a fallback.
  #   4. macOS system paths are preserved via $path (never wholesale-replace).
  pathInit = ''
    typeset -U path
    path=(
      /opt/homebrew/opt/ffmpeg-full/bin
      /opt/homebrew/opt/imagemagick-full/bin
      # /run/current-system/sw/bin
      /nix/var/nix/profiles/system/sw/bin
      /nix/var/nix/profiles/default/bin
      $HOME/.nix-profile/bin
      /Library/TeX/texbin
      /usr/local/texlive/2026basic/bin/universal-darwin
      $HOME/.local/bin
      $HOME/bin
      /opt/homebrew/bin
      /opt/homebrew/sbin
      /usr/local/bin
      $path
    )
    export PATH
  '';
in
{
  # ── Zsh (nix-darwin writes /etc/{zshenv,zprofile,zshrc}) ────────────
  # Autosuggestions + syntax-highlighting + fzf-tab come from antidote
  # (~/.zsh_plugins.txt), so we don't enable nix-darwin's built-in copies
  # (they'd double-source and conflict).
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # ── Shell aliases (was programs.zsh.shellAliases in HM) ─────────────
  environment.shellAliases = {
    ls = "eza";
    ll = "eza -lah --classify --sort=type";
    la = "eza -a";
    tree = "eza --tree";
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

  # ── Global environment (HM used programs.zsh.envExtra, per-shell).
  # environment.variables writes launchd env, so both terminal zsh and
  # GUI apps launched from Dock (e.g. Emacs) see these.
  environment.variables = {
    # macOS 系统 locale 是 en_CN (无效); Emacs NS 端口在 LANG 未设置时
    # 从系统读 locale → 启动警告。LANG 已在 system-packages.nix 声明,
    # 此处不重复。
    EDITOR = "nvim";
    VISUAL = "nvim";
    GIT_EDITOR = "nvim";

    # ── Proxy (ClashX 7890) ───────────────────────────────────────────
    http_proxy = "http://127.0.0.1:7890";
    https_proxy = "http://127.0.0.1:7890";
    HTTP_PROXY = "http://127.0.0.1:7890";
    HTTPS_PROXY = "http://127.0.0.1:7890";
    all_proxy = "socks5://127.0.0.1:7890";
    ALL_PROXY = "socks5://127.0.0.1:7890";
    no_proxy = "localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com";
    NO_PROXY = "localhost,127.0.0.1,::1,feishu.cn,.feishu.cn,larksuite.com,.larksuite.com";
    LARK_CLI_NO_PROXY = "1";
  };

  # ── PATH additions ───────────────────────────────────────────────────
  # NOTE: cannot use `environment.variables.PATH = [ ... ]` because nix-darwin
  # REPLACES PATH wholesale, dropping /usr/bin:/bin:/usr/sbin:/sbin (this
  # broke `tr`, `mv`, `uname`, `mkdir`, ... on 2026-08-22).
  #
  # pathInit is set here (→ /etc/zshenv, read by EVERY zsh including
  # non-interactive scripts/cron) AND re-asserted in interactiveShellInit
  # (→ /etc/zshrc), because ~/.zprofile runs `brew shellenv` which
  # prepends /opt/homebrew/bin after /etc/zshenv. The interactive re-run
  # re-establishes the intended order for login/interactive shells.
  programs.zsh.shellInit = pathInit;

  # ── User packages that lived in home.packages under HM ──────────────
  environment.systemPackages = [
    pkgs.fzf
    pkgs.starship
    pkgs.zoxide
    atuin
  ];

  # ── Prompt: starship (replaces HM programs.starship.enableZshIntegration) ──
  programs.zsh.promptInit = ''
    eval "$(${pkgs.starship}/bin/starship init zsh)"
  '';

  # ── Interactive zsh init (was programs.zsh.initContent in HM).
  # nix-darwin sources this in /etc/zshrc AFTER compinit setup; it runs
  # before the user's ~/.zshrc.
  programs.zsh.interactiveShellInit = ''
    # Re-assert PATH after ~/.zprofile runs `brew shellenv` (see pathInit).
    ${pathInit}

    # `alias -=cd -` can't live in environment.shellAliases: nix-darwin
    # writes those to /etc/zprofile where zsh parses `-=` as an option.
    # Define it here with `alias --` in interactive shells only.
    alias -- -='cd -'

    # iterm2 shell integration
    test -e "''${HOME}/.iterm2_shell_integration.zsh" && source "''${HOME}/.iterm2_shell_integration.zsh"

    # Nix profile env (DeterminateSystems / standalone installer)
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
    # Cache moved out of ~/Library/Caches to survive cleanup tools.
    # antidote itself is the nixpkgs package (migrated from Homebrew).
    zstyle ':antidote:home' dir "$HOME/.local/share/antidote"
    source ${pkgs.antidote}/share/antidote/antidote.zsh

    # Rebuild if bundle is stale OR cache directory was cleaned
    if [[ ! ~/.zsh_plugins.zsh -nt ~/.zsh_plugins.txt ]] || [[ ! -d "$HOME/.local/share/antidote" ]]; then
      antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
    fi

    # ── Completion: case-insensitive (fzf-tab) ───────────────────
    # zsh 默认补全大小写敏感；这里让小写也能匹配大写(cd doc → Documents)
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

    source ~/.zsh_plugins.zsh

    # bun completions
    [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

    # ── fzf key bindings & completion (HM's programs.fzf did this
    # automatically; nix-darwin's enableFzf* only covers History/Git/
    # Completion, not Ctrl-T file widget).
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh
    source ${pkgs.fzf}/share/fzf/completion.zsh

    # ── zoxide (replaces HM programs.zoxide.enableZshIntegration) ──
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"

    # ── atuin (replaces HM programs.atuin.enableZshIntegration) ────
    eval "$(${atuin}/bin/atuin init zsh)"

    # dsh update
    dsh-update() {
      cd /Users/dok4ever/Project/deepseek-harness || return 1
      git pull &&
      pnpm install &&
      pnpm run build &&
      dsh --version
    }
  '';
}
