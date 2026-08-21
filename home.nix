{
  config, pkgs, inputs, unstable, ...  # via extraSpecialArgs
}:

let
  # atuin 18.17+ search bug (#3908): `allow_hyphen_values` on the variadic
  # query swallows flags written AFTER the query (e.g. `atuin search git
  # --cmd-only` treats `--cmd-only` as a search term). Patch removes it;
  # hyphen-prefixed queries now need an explicit `--` separator.
  atuin = (unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin).overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./atuin-fix-search-hyphen.patch ];
  });
in
{

  # ── fetch home-manager module (from areofyl-fetch flake input) ─────────
  # https://github.com/areofyl/fetch/tree/main/nix
  imports = [ inputs.areofyl-fetch.homeManagerModules.default ];

  home.username = "dok4ever";
  home.homeDirectory = "/Users/dok4ever";
  home.stateVersion = "26.05";  # Matches HM release-26.05 branch

  programs.home-manager.enable = true;

  # ── User-level packages ─────────────────────────────────────────────
  # CLI tools moved here from systemPackages (2026-08).
  home.packages = [
    pkgs.fzf
    # atuin from unstable: stable 26.05 (18.15.2) predates the 2026-07-09
    # "shell" migration in the existing history.db. Patched for #3908.
    atuin
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
      # ll = "eza -lah";
      ll = "eza -lah --classify --sort=type";
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
      # ── LANG (2026-08-14) ──────────────────────────────────────────
      # macOS 系统 locale 是 en_CN (无效); Emacs NS 端口在 LANG 未设置时
      # 从系统读 locale → 启动警告 "LANG=en_CN.UTF-8 cannot be used"。
      # 终端里启动的 emacs 需要这里显式设置。
      export LANG=en_US.UTF-8

      # ── Default editor ─────────────────────────────────────────────
      export EDITOR="nvim"
      export VISUAL="nvim"
      export GIT_EDITOR="nvim"

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

      # dsh update
      dsh-update() {
      cd /Users/dok4ever/Project/deepseek-harness || return 1
      git pull &&
      pnpm install &&
      pnpm run build &&
      dsh --version
}
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
    package = atuin;
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

  # ── fetch (animated 3D fetch tool) ─────────────────────────────────
  # Replaces `eval "$(fetch init)"`-style manual config; the HM module
  # builds fetch from source and writes ~/.config/fetch/config.
  # Options: https://github.com/areofyl/fetch/blob/main/nix/README.md
  #
  # info 字段取舍 (2026-08-21, 实测 aarch64-darwin):
  #   有数据: os host kernel uptime packages shell wm theme icons
  #          terminal cpu memory disk ip battery colors
  #   macOS 上取不到 (gather_* 返回空, 不列入):
  #          display font cursor gpu swap locale
  #        - gpu 空: package.nix 只给 Linux 加 pciutils(lspci), mac 无
  #        - swap/locale 等: gather_* 在 darwin 上无对应实现
  programs.fetch = {
    enable = true;
    labelColor = "magenta";
    info = [
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "wm"
      "theme"
      "icons"
      "terminal"
      "cpu"
      "memory"
      "disk"
      "ip"
      "battery"
      "colors"
    ];
    spin = "xy";
    speed = 1.0;
  };
}
