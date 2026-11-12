
{
  config,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};
  home = shared.home;
in {
  # ── Project-specific shell functions ─────────────────────────────────
  # These are NOT generic shell config — they update the deepseek-harness
  # / dsh-web-ui projects. Kept in a separate module so the rest of shell/
  # stays reusable and easy to read. If you prefer these to live outside
  # nix (e.g. ~/.zshrc.local or a personal dotfiles repo), delete this
  # file and remove it from shell/default.nix imports.
  # Assembled into /etc/zdotdir/.zshrc by shell/zdotdir.nix (ZDOTDIR 迁移,
  # 见该文件头注释)。
  dok4ever.shell.zshRc = ''
    # 下面各函数的代理只导出 http(s): 不再夹带 all_proxy=socks5 —— git 会
    # 优先用 socks5, 2026-09-06 记录过 github 443 SSL_ERROR_SYSCALL (见 lib.nix)。
    # 地址/端口来自 modules/lib.nix 的 shared.proxyUrl (单一来源)。
    # ── 第三方安装器助手: sh-install ────────────────────────────────────
    # 背景: 大多数 `curl … | bash` 安装器按 $ZDOTDIR/.zshrc 定位配置文件追加
    # PATH, 而本机 ZDOTDIR=/etc/zdotdir 指向 nix store 只读目录 → 追加必失败
    # (bash: /etc/zdotdir/.zshrc: Permission denied, 2026-09-24 kigi 实测)。
    # 本函数把 ZDOTDIR 改成 $HOME 后再跑脚本: 安装器转而写 ~/.zshrc —— 可写、
    # rebuild 不覆盖, 且被 /etc/zdotdir/.zshrc 末行 source → PATH 立即生效。
    # ⚠️ 只覆盖 zsh: nushell 的 env.nu 是硬编码 PATH 列表、不继承父 shell 环境,
    # nu 里也要用的工具仍需加进 modules/lib.nix 的 pathInitNu。
    # 用法: sh-install <安装脚本 URL> [传给脚本的参数…]
    sh-install() {
      if [ $# -lt 1 ]; then
        print -u2 'usage: sh-install <install-script-url> [args…]'
        return 2
      fi
      local url=$1
      shift
      local tmp && tmp=$(mktemp -t sh-install) || return 1
      if ! curl -fsSL "$url" -o "$tmp"; then
        print -u2 "sh-install: 下载失败: $url"
        rm -f "$tmp"
        return 1
      fi
      ZDOTDIR="$HOME" bash "$tmp" "$@"
      local rc=$?
      rm -f "$tmp"
      return $rc
    }

    # dsh update
    dsh-update() {
      (
        cd ${home}/Project/deepseek-harness || exit 1
        https_proxy=${shared.proxyUrl} http_proxy=${shared.proxyUrl} \
          git pull &&
        pnpm install &&
        pnpm run build &&
        dsh --version
      )
    }

    # dsh-web-ui update
    # Interactive: lists local branches, select one to update
    dsh-web-ui-update() {
      (
      cd ${home}/Project/dsh-web-ui || exit 1

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
          exit 1
        fi
        local branch="$branches[$sel]"
        git checkout "$branch" || exit 1
      fi
      https_proxy=${shared.proxyUrl} http_proxy=${shared.proxyUrl} \
        git pull --rebase &&
      pnpm install &&
      pnpm run build
      # Re-link @linxin666 packages to profile node_modules
      local profile_nm="$HOME/.dsh/profiles/web/node_modules/@linxin666"
      [ -d "$profile_nm" ] && {
        rm -f "$profile_nm"/dsh-client-ui-aionui-panel "$profile_nm"/dsh-chat-recovery "$profile_nm"/dsh-client-ui-community-plugins "$profile_nm"/dsh-desktop-launcher "$profile_nm"/dsh-doctor "$profile_nm"/dsh-client-ui-git-graph "$profile_nm"/dsh-liangshen "$profile_nm"/dsh-client-ui-market "$profile_nm"/dsh-pet "$profile_nm"/dsh-client-ui-plugin-manager "$profile_nm"/dsh-remote-web-ui "$profile_nm"/dsh-client-ui-session-id "$profile_nm"/dsh-client-ui-skill-explorer "$profile_nm"/dsh-ssh "$profile_nm"/dsh-client-ui-task-board "$profile_nm"/dsh-tool-describe-image "$profile_nm"/dsh-web-all "$profile_nm"/dsh-client-ui-turn-nav "$profile_nm"/dsh-client-ui-web-ui-settings
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
        ln -sf "$PWD/packages/turn-nav"                     "$profile_nm"/dsh-client-ui-turn-nav
        ln -sf "$PWD/packages/dsh-web-settings"             "$profile_nm"/dsh-client-ui-web-ui-settings
      }
      # Ensure profile package.json references the right name
      sed -i.bak 's/dsh-web-ui-all/dsh-web-all/g' "$HOME/.dsh/profiles/web/package.json"
      rm -f "$HOME/.dsh/profiles/web/package.json.bak"

      # The 3080 service (`dsh web`) runs from deepseek-harness, not dsh-web-ui.
      # If CLI/server code changed, pull + rebuild it too; don't fail the whole
      # update if there's a local conflict (still restart with current build).
      local harness_dir=${home}/Project/deepseek-harness
      if [ -d "$harness_dir/.git" ]; then
        echo "→ Updating deepseek-harness (dsh web backend)..."
        (
          cd "$harness_dir" || exit 0
          https_proxy=${shared.proxyUrl} http_proxy=${shared.proxyUrl} \
            git pull --rebase &&
          pnpm install &&
          pnpm run build &&
          dsh --version
        ) || echo "⚠ deepseek-harness update failed; restarting with current build." >&2
      fi

      launchctl kickstart -k "gui/$(id -u)/com.dsh.web"
      )
    }

    # dsh-web-ui local reload (fast path for local development).
    # Rebuilds the dsh-web-ui packages (which are symlinked into the profile)
    # and restarts the 3080 service. Does NOT touch git, pnpm install, or
    # deepseek-harness. Use after editing local dsh-web-ui code.
    # Supports interactive branch selection just like dsh-web-ui-update.
    dsh-web-reload() {
      (
        cd ${home}/Project/dsh-web-ui || exit 1

        # List all local branches if more than one
        local branches=($(git branch --format="%(refname:short)"))
        if [[ $#branches -gt 1 ]]; then
          echo "Available local branches:"
          for (( i=1; i<=$#branches; i++ )); do
            echo "  $i) $branches[$i]"
          done
          # Ask user selection
          echo -n "Enter number to select branch (enter for current branch '$(git rev-parse --abbrev-ref HEAD)'): "
          read -r sel

          if [ -n "$sel" ]; then
            if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$#branches" ]; then
              echo "Invalid selection, abort" >&2
              exit 1
            fi
            local branch="$branches[$sel]"
            git checkout "$branch" || exit 1
          fi
        fi

        pnpm run build || { echo "✖ build failed" >&2; exit 1; }
        # Re-link @linxin666 packages (just in case any new packages were added)
        local profile_nm="$HOME/.dsh/profiles/web/node_modules/@linxin666"
        [ -d "$profile_nm" ] && {
          rm -f "$profile_nm"/dsh-client-ui-aionui-panel "$profile_nm"/dsh-chat-recovery "$profile_nm"/dsh-client-ui-community-plugins "$profile_nm"/dsh-desktop-launcher "$profile_nm"/dsh-doctor "$profile_nm"/dsh-client-ui-git-graph "$profile_nm"/dsh-liangshen "$profile_nm"/dsh-client-ui-market "$profile_nm"/dsh-pet "$profile_nm"/dsh-client-ui-plugin-manager "$profile_nm"/dsh-remote-web-ui "$profile_nm"/dsh-client-ui-session-id "$profile_nm"/dsh-client-ui-skill-explorer "$profile_nm"/dsh-ssh "$profile_nm"/dsh-client-ui-task-board "$profile_nm"/dsh-tool-describe-image "$profile_nm"/dsh-web-all "$profile_nm"/dsh-client-ui-turn-nav "$profile_nm"/dsh-client-ui-web-ui-settings
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
          ln -sf "$PWD/packages/turn-nav"                     "$profile_nm"/dsh-client-ui-turn-nav
          ln -sf "$PWD/packages/dsh-web-settings"             "$profile_nm"/dsh-client-ui-web-ui-settings
        }

        launchctl kickstart -k "gui/$(id -u)/com.dsh.web"
        echo "✓ rebuilt and restarted com.dsh.web (port 3080) on branch '$(git rev-parse --abbrev-ref HEAD)'"
      )
    }

    # Rime/Squirrel redeploy. Triggers Squirrel to rebuild its build/ cache
    # from ~/Library/Rime/*.yaml (same as clicking 鼠须管 → Deploy).
    rime-reload() {
      local squirrel_bin="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
      if [ ! -x "$squirrel_bin" ]; then
        echo "✖ Squirrel not found at $squirrel_bin" >&2
        return 1
      fi
      "$squirrel_bin" --reload && echo "✓ Rime redeployed" || echo "✖ redeploy failed (check ~/Library/Rime/build/ for errors)" >&2
    }
    alias rime-deploy='rime-reload'

    # Full Rime redeploy: rebuild nix-darwin then reload Squirrel
    rime-redeploy() {
      (
        cd /etc/nix-darwin || exit 1
        https_proxy=${shared.proxyUrl} http_proxy=${shared.proxyUrl} \
          sudo darwin-rebuild switch --flake .#dok4ever-mac && \
          rime-reload
      )
    }

    # tmux-left-2-right-1: Create the standard 3-pane workspace layout
    # Layout:
    # ┌──────────────┬──────────────┐
    # │      1       │              │
    # ├──────────────┤      3       │
    # │      2       │              │
    # └──────────────┴──────────────┘
    # Left: 2 panes stacked vertically; Right: 1 pane full-height
    tmux-workspace() {
      # Only works inside tmux
      if [ -z "$TMUX" ]; then
        echo "✖ Error: must be run inside tmux" >&2
        return 1
      fi

      # Step 1: Split horizontally, create right pane (50% width)
      tmux split-window -h -c "#{pane_current_path}"

      # Step 2: Go back to left pane, split vertically, create bottom pane
      tmux select-pane -L
      tmux split-window -v -c "#{pane_current_path}"

      # Step 3: Select the top-left pane (pane 1) - reasonable default
      tmux select-pane -U

      echo "✓ Created tmux 3-pane workspace layout"
    }
    alias tws='tmux-workspace'

    # nix-template / nt: interactively scaffold a flake devShell + direnv
    # into the current directory. Templates live in /etc/nix-darwin/templates/*
    # and are exposed via the nix-darwin flake `templates` output.
    #   $ cd ~/dev/myapp && nt          # fzf-pick a template
    #   $ nt python                     # skip the picker, use a named one
    # After init, runs `direnv allow` so the env auto-loads on cd.
    # Requires: template files git-tracked in the nix-darwin repo (git flakes
    # only expose tracked files), and direnv + nix-direnv (already enabled).
    nix-template() {
      local tpl_dir="/etc/nix-darwin/templates"
      if [ ! -d "$tpl_dir" ]; then
        echo "✖ templates dir not found: $tpl_dir" >&2
        return 1
      fi
      local name="$1"
      if [ -z "$name" ]; then
        name=$(ls -1 "$tpl_dir" | fzf --prompt="Select template> " --height=40%) || { echo "Aborted"; return 1; }
      fi
      if [ ! -d "$tpl_dir/$name" ]; then
        echo "✖ no such template: $name (available: $(ls -1 "$tpl_dir" | tr '\n' ' '))" >&2
        return 1
      fi
      nix flake init -t "/etc/nix-darwin#$name" || { echo "✖ nix flake init failed" >&2; return 1; }
      if [ -f .envrc ]; then
        direnv allow && echo "✓ scaffolded '$name' + direnv enabled"
      else
        echo "✓ scaffolded '$name' (no .envrc)"
      fi
    }
    alias nt='nix-template'

    # karakuri: run the home-grown AI agent runtime (Project/karakuri) against
    # the CURRENT directory, using a provider profile from
    # ~/.config/karakuri/providers/<name>.env (API keys live there, mode 600,
    # never in the nix store).
    #   $ cd ~/dev/some-project && karakuri        # default provider: ark
    #   $ karakuri openai                          # pick another provider
    #   $ karakuri ssh                             # fzf-pick a remote project under KARAKURI_SSH_BASE (default /home/dok/Project)
    #   $ KARAKURI_SANDBOX_NETWORK=1 karakuri       # env overrides pass through
    # Seatbelt sandbox is on by default (KARAKURI_SANDBOX=1); set
    # KARAKURI_SANDBOX=0 to disable. Toolchain comes from the project flake's
    # nix develop (cargo must be on PATH for the agent's exec tool).
    karakuri() {
      local profile="''${1:-ark}"
      local env_file="$HOME/.config/karakuri/providers/$profile.env"
      if [ ! -f "$env_file" ]; then
        echo "✖ no such provider profile: $profile ($env_file)" >&2
        echo "  available: $(ls -1 "$HOME/.config/karakuri/providers" 2>/dev/null | sed 's/\.env$//' | tr '\n' ' ')" >&2
        return 1
      fi
      local proj="$PWD"
      (
        set -a; source "$env_file"; set +a

        # SSH 模式且未固定 KARAKURI_SSH_ROOT：从远程基目录（默认
        # /home/dok/Project，可用 KARAKURI_SSH_BASE 覆盖）fzf 选一个项目。
        if [ "''${KARAKURI_RUNTIME:-}" = ssh ] && [ -z "''${KARAKURI_SSH_ROOT:-}" ]; then
          base="''${KARAKURI_SSH_BASE:-/home/dok/Project}"
          # 列目录也走 sh -s + stdin（远程登录 shell 可能是 fish，POSIX 循环交给 sh）
          pick=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "''${KARAKURI_SSH_HOST:-}" sh -s 2>/dev/null <<EOF | fzf --prompt="remote project ($base) > "
for d in '$base'/*/; do [ -d "\$d" ] && basename "\$d"; done
EOF
          ) \
            || { echo "✖ 未选择项目，或无法连接 ''${KARAKURI_SSH_HOST:-<host>}" >&2; return 1; }
          [ -z "$pick" ] && { echo "✖ 未选择项目" >&2; return 1; }
          export KARAKURI_SSH_ROOT="$base/$pick"
          echo "→ remote root: $KARAKURI_SSH_ROOT"
        fi

        cd ${home}/Project/karakuri || exit 1
        KARAKURI_SANDBOX="''${KARAKURI_SANDBOX:-1}" \
          nix develop --command bash -c "cd '$proj' && exec ${home}/Project/karakuri/target/debug/karakuri"
      )
    }

    # ── Hermes 会话浏览/续跑: hr ────────────────────────────────────────
    # 交互式会话选择器 (上下键 + 打字过滤 + 回车续跑), 等价 codex resume 的
    # 候选列表。⚠️ 别用 `hermes resume` —— 那个子命令是解除 hermes pause
    # 的 ESTOP, 与续会话无关。参数透传, 如: hr --source cli
    hr() {
      hermes sessions browse "$@"
    }

    # ── 常用 alias（交互 shell 也要能用，非 login shell 只读 .zshrc） ──
    alias ls=eza
    alias ll='eza -lah --classify --sort=type'
    alias la='eza -a'
    alias tree='eza --tree'
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
    alias c=clear
    alias cls=clear
    alias v=nvim
    alias vi=nvim
    alias cat=bat
    alias em='emacs -nw'

    # grep 彩色
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'

    # git 常用
    alias g='git'
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git pull'
    alias gd='git diff'
    alias gco='git checkout'
    alias gb='git branch'

    # 其它常用
    alias h='history'
    alias j='jobs'

    # nix-darwin rebuild
    alias drs='darwin-rebuild switch'
    alias drb='darwin-rebuild build'
  '';
}
