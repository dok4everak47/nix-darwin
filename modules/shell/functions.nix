
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
  programs.zsh.interactiveShellInit = ''
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
  '';
}
