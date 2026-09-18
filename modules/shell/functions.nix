
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
    # dsh update
    dsh-update() {
      (
        cd ${home}/Project/deepseek-harness || exit 1
        https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890 \
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
      https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890 \
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
          https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890 \
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
        https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890 \
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

    # nxd-install: 安装软件子菜单 (nxd 调用, 也可独立运行)。
    #   🔍 nix: nix-search 搜索(频道=26.05, 与 flake.lock 的 nixos-26.05 匹配,
    #      flake 升级大版本时同步改这里) → 选中 → 自动追加进 packages.nix
    #      systemPackages 列表首行 → 询问是否立即 rebuild。
    #   🍺 brew: 输 formula/cask 名 → brew info 自动识别类型 → brew install
    #      → 自动追加声明进 homebrew.nix 对应列表。自定义 tap 未声明时只装
    #      不声明(缺 tap 声明会让下次 brew bundle 报错), 由用户先声明 tap。
    #   📝 直接编辑 packages.nix / homebrew.nix。
    # 写文件用 awk 在列表头插入一行; 目标行格式变化时放弃并提示手动添加。
    nxd-install() {
      local repo="/etc/nix-darwin"
      local sub pkg name kind tap declare_ok yn k2 tmpf install_rc added
      while true; do
        sub=$(printf '%s\n' \
          "🔍 nix 安装 (搜索 + 自动声明 packages.nix)" \
          "🍺 brew 安装 (安装 + 自动声明 homebrew.nix)" \
          "📝 编辑 packages.nix" \
          "📝 编辑 homebrew.nix" \
          "⬅ 返回" \
          | fzf --prompt="安装软件> " --reverse --height=50%) || return 0
        case "$sub" in
          *nix*安装*)
            rm -f /tmp/nxd-install-cart /tmp/nxd-install-cart.t
            touch /tmp/nxd-install-cart
            fzf --phony --query="" \
              --prompt="nix 搜索> " \
              --header="输入即实时搜索 · 空格 选择/取消 · Enter 安装已选 · Esc 取消" \
              --multi --reverse --height=90% --delimiter='\t' \
              --bind="space:toggle+execute-silent(sh -c 'if grep -qxF -e {1} /tmp/nxd-install-cart 2>/dev/null; then grep -vxF -e {1} /tmp/nxd-install-cart > /tmp/nxd-install-cart.t && mv /tmp/nxd-install-cart.t /tmp/nxd-install-cart; else printf \"%s\\n\" {1} >> /tmp/nxd-install-cart; fi')+refresh-preview" \
              --bind="change:reload-sync([ -n \"\$FZF_QUERY\" ] && nix-search --channel=26.05 -m 50 --json \"\$FZF_QUERY\" 2>/dev/null | jq -r '\"\(.package_attr_name // \"\")\t\(.package_pversion // \"\")\t\(.package_description // \"\")\t\((.package_programs // []) | join(\" \"))\"' | sort -u || true)" \
              --preview="printf '▸ {1} @ {2}\n\n'; printf '%s\n' '{3}'; printf '\n命令: %s\n' '{4}'; cat /tmp/nxd-install-cart 2>/dev/null | sed 's/^/  ✓ /'; [ -s /tmp/nxd-install-cart ] || echo '  (空)'" \
              --preview-window=right:45%:wrap >/dev/null </dev/null
            install_rc=$?
            if [[ "$install_rc" -ne 0 ]]; then
              rm -f /tmp/nxd-install-cart /tmp/nxd-install-cart.t
              continue
            fi
            added=0
            while IFS= read -r pkg; do
              [ -z "$pkg" ] && continue
              if ! [[ "$pkg" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
                echo "✖ 包名含特殊字符, 跳过: $pkg" >&2
                continue
              fi
              if grep -qE "^[[:space:]]*$pkg[[:space:]]*\$" "$repo/modules/system/packages.nix"; then
                echo "⚠ packages.nix 已有 $pkg, 跳过"
                continue
              fi
              tmpf="$repo/modules/system/packages.nix.tmp"
              awk -v pkg="      $pkg" '
                !ins && /environment.systemPackages = with pkgs;/ {
                  print
                  if ((getline nxt) <= 0) exit 2
                  print nxt
                  if (nxt !~ /^[[:space:]]*\[[[:space:]]*$/) exit 2
                  print pkg
                  ins = 1
                  next
                }
                { print }
                END { if (!ins) exit 3 }
              ' "$repo/modules/system/packages.nix" > "$tmpf" \
                && mv "$tmpf" "$repo/modules/system/packages.nix" \
                || { rm -f "$tmpf"; echo "✖ packages.nix 列表格式与预期不符, $pkg 未添加 (请手动)" >&2; continue; }
              echo "✓ 已加入 packages.nix: $pkg"
              added=$((added + 1))
            done < /tmp/nxd-install-cart
            rm -f /tmp/nxd-install-cart /tmp/nxd-install-cart.t
            if [[ "$added" -eq 0 ]]; then
              echo "(没有新增声明)"
              continue
            fi
            printf '立即 rebuild 生效? (y/N) '
            read -r yn
            [[ "$yn" == y* ]] && (cd "$repo" && sudo darwin-rebuild switch --flake .#dok4ever-mac)
            ;;
          *brew*安装*)
            printf 'brew 名字 (formula 或 cask, 支持 user/tap/name)> '
            read -r name
            [ -z "$name" ] && continue
            if ! [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.@+-]*$ ]]; then
              echo "✖ 名字含异常字符: $name" >&2
              continue
            fi
            if brew info --formula "$name" >/dev/null 2>&1; then
              kind=formula
              tap=$(brew info --json=v2 --formula "$name" 2>/dev/null | jq -r '.formula[0].tap // ""')
            elif brew info --cask "$name" >/dev/null 2>&1; then
              kind=cask
              tap=$(brew info --json=v2 --cask "$name" 2>/dev/null | jq -r '.casks[0].tap // ""')
            else
              echo "✖ brew 找不到: $name (formula / cask 都没命中)" >&2
              continue
            fi
            if [[ "$kind" == formula ]]; then
              brew install "$name" || continue
            else
              brew install --cask "$name" || continue
            fi
            declare_ok=1
            if [[ -n "$tap" && "$tap" != homebrew/* ]] && ! grep -qF "$tap" "$repo/modules/system/homebrew.nix"; then
              echo "⚠ tap '$tap' 未在 homebrew.nix 声明 — 跳过自动声明; 请先声明 tap 并加条目, 否则下次 rebuild 会把它清掉" >&2
              declare_ok=0
            fi
            if [[ "$declare_ok" == 1 ]]; then
              if grep -qE "^[[:space:]]*\"?$name\"?[[:space:]]*\$|name = \"$name\";" "$repo/modules/system/homebrew.nix"; then
                echo "⚠ homebrew.nix 已有 $name, 跳过声明"
              else
                if [[ "$kind" == cask ]]; then
                  tmpf="$repo/modules/system/homebrew.nix.tmp"
                  awk -v e="      \"$name\"" '
                    !ins && /casks = \[/ { print; print e; ins = 1; next }
                    { print }
                    END { if (!ins) exit 3 }
                  ' "$repo/modules/system/homebrew.nix" > "$tmpf" \
                    && mv "$tmpf" "$repo/modules/system/homebrew.nix" \
                    || { rm -f "$tmpf"; echo "✖ casks 列表格式异常, 请手动声明" >&2; continue; }
                  echo "✓ 已声明进 casks: $name"
                else
                  tmpf="$repo/modules/system/homebrew.nix.tmp"
                  awk -v e="      \"$name\"" '
                    !ins && /brews = \[/ { print; print e; ins = 1; next }
                    { print }
                    END { if (!ins) exit 3 }
                  ' "$repo/modules/system/homebrew.nix" > "$tmpf" \
                    && mv "$tmpf" "$repo/modules/system/homebrew.nix" \
                    || { rm -f "$tmpf"; echo "✖ brews 列表格式异常, 请手动声明" >&2; continue; }
                  echo "✓ 已声明进 brews: $name"
                fi
              fi
            fi
            if [[ "$declare_ok" == 1 ]]; then
              echo "✓ 已安装 $name ($kind); 声明已入 homebrew.nix, 下次 rebuild 自动转正"
            else
              echo "✖ 已安装 $name ($kind) 但未声明 — 下次 rebuild 会被 cleanup 清掉, 请尽快声明 tap + 条目"
            fi
            ;;
          *packages.nix*)
            (cd "$repo" && $EDITOR modules/system/packages.nix) ;;
          *homebrew.nix*)
            (cd "$repo" && $EDITOR modules/system/homebrew.nix) ;;
          *)
            return 0 ;;
        esac
        printf '\n↩ 回车返回安装菜单 / q 回主菜单> '
        read -r k2
        [[ "$k2" == q* ]] && return 0
      done
    }

    # nxd: nix-darwin TUI — fzf 菜单一站式操作 /etc/nix-darwin。
    #   $ nxd   # 菜单: 安装(nix/brew) / 编辑(分类/全局) / rebuild / diff / commit&push / rollback
    # 任何目录可用;编辑走 $EDITOR(fzf 带预览),rebuild 走 sudo(前台输密码)。
    # 注意: 本函数体内严禁 dollar-quote(两个相邻单引号)写法, 会截断 Nix indented 字符串,
    # 换行用 printf, tab 用 awk 双引号转义 / fzf 反斜杠t 正则。
    nxd() {
      local repo="/etc/nix-darwin"
      local menu cat files file yn k
      while true; do
        menu=$(printf '%s\n' \
          "📝 编辑配置 (全局搜索)" \
          "📂 分类浏览编辑 (软件/shell/system/...)" \
          "📦 安装软件 (nix / brew)" \
          "🔨 rebuild (switch)" \
          "👀 查看未提交改动" \
          "✅ commit & push" \
          "↩️  rollback 上一代" \
          "🚪 退出" \
          | fzf --prompt="nix-darwin [$(git -C "$repo" branch --show-current)]> " \
            --header="$(git -C "$repo" status -s | wc -l | tr -d ' ') 个未提交文件" \
            --reverse --height=50%) || return 0
        case "$menu" in
          *全局搜索*)
            file=$(git -C "$repo" ls-files '*.nix' \
              | fzf --prompt="open> " --reverse --height=60% \
                --preview="bat --color=always --style=numbers --line-range=:200 '$repo/{}'" \
                --preview-window=right:60%:wrap) || continue
            (cd "$repo" && $EDITOR "$file") ;;
          *分类浏览*)
            cat=$(printf '%s\n' \
              "📦 安装软件 (packages / homebrew)" \
              "🐚 shell" \
              "⚙️ system" \
              "🧩 programs" \
              "🔧 fixes" \
              "🔗 overlays" \
              "🌳 核心 (flake / lib / AGENTS)" \
              "⬅ 返回" \
              | fzf --prompt="分类> " --reverse --height=50%) || continue
            case "$cat" in
              *安装*)
                files=""
                nxd-install ;;
              *shell*)
                files=$(git -C "$repo" ls-files 'modules/shell') ;;
              *system*)
                files=$(git -C "$repo" ls-files 'modules/system') ;;
              *programs*)
                files=$(git -C "$repo" ls-files 'modules/programs') ;;
              *fixes*)
                files=$(git -C "$repo" ls-files 'modules/fixes') ;;
              *overlays*)
                files=$(git -C "$repo" ls-files 'modules/overlays') ;;
              *核心*)
                files=$(printf '%s\n' "flake.nix" "modules/lib.nix" "modules/default.nix" "AGENTS.md") ;;
              *)
                continue ;;
            esac
            [ -z "$files" ] && continue
            file=$(printf '%s\n' "$files" \
              | awk -F/ '{print $NF "\t" $0}' \
              | fzf --prompt="open> " --reverse --height=60% \
                --with-nth=1 --delimiter='\t' \
                --preview="bat --color=always --style=numbers --line-range=:200 '$repo/{2}'" \
                --preview-window=right:60%:wrap \
              | cut -f2) || continue
            [ -n "$file" ] || continue
            (cd "$repo" && $EDITOR "$file") ;;
          *安装软件*)
            nxd-install ;;
          *rebuild*)
            (cd "$repo" && sudo darwin-rebuild switch --flake .#dok4ever-mac) ;;
          *查看*)
            git -C "$repo" --no-pager -c color.ui=always diff HEAD | less -R ;;
          *commit*)
            (cd "$repo" && git add -A && git commit && { git push; git push gitea HEAD; }) ;;
          *rollback*)
            printf '确认 rollback 到上一代? (y/N) '
            read -r yn
            [[ "$yn" == y* ]] && sudo darwin-rebuild switch --rollback ;;
          *退出*) return 0 ;;
        esac
        printf '\n↩ 回车返回菜单 / q 退出> '
        read -r k
        [[ "$k" == q* ]] && return 0
      done
    }
  '';
}
