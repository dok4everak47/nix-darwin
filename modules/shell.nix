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
    # NOTE: "--" is intentionally NOT here — nix-darwin writes shellAliases to
    # /etc/zprofile where zsh errors with "bad option: -=". It's defined via
    # `alias --` in interactiveShellInit below.
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
  # NOTE: cannot use `environment.variables.PATH = [ ... ]` because nix-dar
  #
  #   1. keg-only Homebrew full builds beat both nixpkgs and any regular
  #      brew ffmpeg/magick.
  #   2. Nix system profile — migrated CLI tools — beats /opt/homebrew/bin.
  #   3. TeX, user bins, then /opt/homebrew/bin as a fallback.
  #   4. macOS system paths are preserved via $path (never wholesale-replace).
  programs.zsh.shellInit = pathInit;

  # ── User packages that lived in home.packages under HM ─────────────
  environment.systemPackages = [
    pkgs.zoxide
    atuin  # patched unstable build; needed on PATH (atuin init calls bare `atuin`)
  ];

  # ── Prompt: starship (replaces HM programs.starship.enableZshIntegration) ──
  programs.zsh.promptInit = ''
    eval "$(${pkgs.starship}/bin/starship init zsh)"
  '';

  # ── Interactive zsh init (was programs.zsh.initContent in HM).
  # nix-darwin sources this in /etc/zshrc AFTER compinit setup; it runs
  # before the user's ~/.zshrc.
  programs.zsh.interactiveShellInit = ''
    # Aliases starting with `-` can't live in environment.shellAliases (nix-darwin
    # writes those to /etc/zprofile, where zsh errors with "bad option: -=").
    # Define them here with `alias --` in interactive shells only.
    alias -- -= 'cd -'
    alias -- --='cd ..'

    # Re-assert PATH after ~/.zprofile runs `brew shellenv` (see pathInit).
    ${pathInit}

    # Rebuild if bundle is stale OR cache directory was cleaned
    if [[ ! ~/.zsh_plugins.zsh -nt ~/.zsh_plugins.txt ]] || [[ ! -d "$HOME/.local/share/antidote" ]]; then
        antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
    fi

    # ── Completion: case-insensitive (fzf-tab) ───────────────────
    # zsh 默认补全大小写敏感；这里让小写也能匹配大写(cd doc → Documents)
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

    # compinit MUST run before sourcing plugins: oh-my-zsh plugins (e.g. git)
    # call `compdef` at load time. nix-darwin runs its own compinit at the end
    # of /etc/zshrc (after interactiveShellInit), which is too late.
    autoload -U compinit && compinit

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

    # dsh-web-ui update
    # Interactive: lists local branches, select one to update
    dsh-web-ui-update() {
      cd /Users/dok4ever/Project/dsh-web-ui || return 1

      # List all local branches
      echo "Available local branches:"
      local branches=($(git branch --format="%(refname:short)"))
      for (( i=1; i<=$#branches; i++ )); do
        echo "  $i) $branches[$i]"
      done

      # Ask user selection
      echo -n "Enter number to select branch (enter for current branch '$(git rev-parse --abbrev-ref HEAD)'): "
      read -r sel

      if [ -n "$sel" ]; then
        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$#branches" ]; then
          echo "Invalid selection, abort" >&2
          return 1
        fi
        local branch="$branches[$sel]"
        git checkout "$branch" || return 1
      fi
      GIT_SSL_NO_VERIFY=1 git pull --rebase &&
      pnpm install &&
      pnpm run build
      # Re-link @linxin666 packages to profile node_modules
      local profile_nm="$HOME/.dsh/profiles/web/node_modules/@linxin666"
      [ -d "$profile_nm" ] && {
        rm -f "$profile_nm"/dsh-client-ui-aionui-panel "$profile_nm"/dsh-chat-recovery "$profile_nm"/dsh-client-ui-community-plugins "$profile_nm"/dsh-desktop-launcher "$profile_nm"/dsh-doctor "$profile_nm"/dsh-client-ui-git-graph "$profile_nm"/dsh-liangshen "$profile_nm"/dsh-client-ui-market "$profile_nm"/dsh-pet "$profile_nm"/dsh-client-ui-plugin-manager "$profile_nm"/dsh-remote-web-ui "$profile_nm"/dsh-client-ui-session-id "$profile_nm"/dsh-client-ui-skill-explorer "$profile_nm"/dsh-ssh "$profile_nm"/dsh-client-ui-task-board "$profile_nm"/dsh-tool-describe-image "$profile_nm"/dsh-web-all "$profile_nm"/dsh-client-ui-web-ui-settings
        ln -sf "$PWD/packages/dsh-aionui-panel"             "$profile_nm"/dsh-client-ui-aionui-panel
        ln -sf "$PWD/packages/dsh-chat-recovery"            "$profile_nm"/dsh-chat-recovery
        ln -sf "$PWD/packages/dsh-community-plugins"        "$profile_nm"/dsh-client-ui-community-plugins
        ln -sf "$PWD/packages/dsh-desktop-launcher"         "$profile_nm"/dsh-desktop-launcher
        ln -sf "$PWD/packages/dsh-doctor"                   "$profile_nm"/dsh-doctor
        ln -sf "$PWD/packages/dsh-git-graph"                "$profile_nm"/dsh-client-ui-git-graph
        ln -sf "$PWD/packages/dsh-liangshen"                "$profile_nm"/dsh-liangshen
        ln -sf "$PWD/packages/dsh-market"                   "$profile_nm"/dsh-client-ui-market
        ln -sf "$PWD/packages/dsh-pet"                      "$profile_nm"/dsh-pet
        ln -sf "$PWD/packages/dsh-plugin-manager"           "$profile_nm"/dsh-client-ui-plugin-manager
        ln -sf "$PWD/packages/dsh-remote-web-ui"            "$profile_nm"/dsh-remote-web-ui
        ln -sf "$PWD/packages/dsh-session-id"               "$profile_nm"/dsh-client-ui-session-id
        ln -sf "$PWD/packages/dsh-skill-explorer"           "$profile_nm"/dsh-client-ui-skill-explorer
        ln -sf "$PWD/packages/dsh-ssh"                      "$profile_nm"/dsh-ssh
        ln -sf "$PWD/packages/dsh-task-board"               "$profile_nm"/dsh-client-ui-task-board
        ln -sf "$PWD/packages/dsh-tool-describe-image"      "$profile_nm"/dsh-tool-describe-image
        ln -sf "$PWD/packages/dsh-web-all"                  "$profile_nm"/dsh-web-all
        ln -sf "$PWD/packages/dsh-web-settings"             "$profile_nm"/dsh-client-ui-web-ui-settings
      }
      # Ensure profile package.json references the right name
      sed -i.bak 's/dsh-web-ui-all/dsh-web-all/g' "$HOME/.dsh/profiles/web/package.json"
      rm -f "$HOME/.dsh/profiles/web/package.json.bak"
      launchctl kickstart -k gui/501/com.dsh.web
    }
  '';
}
