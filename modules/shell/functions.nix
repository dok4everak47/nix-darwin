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
      cd ${home}/Project/deepseek-harness || return 1
      git pull &&
      pnpm install &&
      pnpm run build &&
      dsh --version
    }

    # dsh-web-ui update
    # Interactive: lists local branches, select one to update
    dsh-web-ui-update() {
      cd ${home}/Project/dsh-web-ui || return 1

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
      launchctl kickstart -k "gui/$(id -u)/com.dsh.web"
    }
  '';
}
