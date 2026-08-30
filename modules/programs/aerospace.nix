# AeroSpace — i3-like tiling window manager for macOS (nikitabobko/AeroSpace).
#
# Why AeroSpace over yabai:
#   - NO SIP disable needed (yabai needed partial SIP off)
#   - NO scripting-addition (yabai's sa fails to inject into Dock on macOS 27
#     Tahoe Preview — space --create broken)
#   - Built-in hotkeys (no skhd needed)
#   - Persistent workspaces 1-9 (always exist, like OmniWM's 9 workspaces)
#
# Config lives at ${XDG_CONFIG_HOME}/aerospace/aerospace.toml
# (= ~/.config/aerospace/aerospace.toml), written by activation below.
#
# Requirements (user must do once):
#   1. Grant Accessibility permission to AeroSpace (System Settings → Privacy
#      & Security → Accessibility), then restart AeroSpace.
{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};

  aeroCfg = pkgs.writeText "aerospace.toml" ''
    # ── AeroSpace config (managed by nix-darwin) ──────────────────
    config-version = 2

    # Start AeroSpace at login (handled by our LaunchAgent instead)
    start-at-login = false

    # Normalizations
    enable-normalization-flatten-containers = true
    enable-normalization-opposite-orientation-for-nested-containers = true

    accordion-padding = 30
    # niri-style: accordion layout = focused window expands, others compress
    # into narrow strips (like niri's focused column being centered/large)
    default-root-container-layout = 'accordion'
    default-root-container-orientation = 'horizontal'

    # Keep 9 workspaces alive (like OmniWM's 9 spaces)
    persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    # Don't move mouse on focus change (keep it simple)
    on-focused-monitor-changed = []

    # Gaps (px)
    [gaps]
        inner.horizontal = 8
        inner.vertical =   8
        outer.left =       8
        outer.bottom =     8
        outer.top =        8
        outer.right =      8

    [key-mapping]
        preset = 'qwerty'

    # ── Keybindings (mirror old OmniWM / yabai+skhd layout) ──────
    [mode.main.binding]

        # Workspaces 1-9 (always exist via persistent-workspaces)
        alt-1 = 'workspace 1'
        alt-2 = 'workspace 2'
        alt-3 = 'workspace 3'
        alt-4 = 'workspace 4'
        alt-5 = 'workspace 5'
        alt-6 = 'workspace 6'
        alt-7 = 'workspace 7'
        alt-8 = 'workspace 8'
        alt-9 = 'workspace 9'

        # Move window to workspace
        alt-shift-1 = 'move-node-to-workspace 1'
        alt-shift-2 = 'move-node-to-workspace 2'
        alt-shift-3 = 'move-node-to-workspace 3'
        alt-shift-4 = 'move-node-to-workspace 4'
        alt-shift-5 = 'move-node-to-workspace 5'
        alt-shift-6 = 'move-node-to-workspace 6'
        alt-shift-7 = 'move-node-to-workspace 7'
        alt-shift-8 = 'move-node-to-workspace 8'
        alt-shift-9 = 'move-node-to-workspace 9'

        # Focus (Vim-style + arrows)
        alt-h = 'focus left'
        alt-j = 'focus down'
        alt-k = 'focus up'
        alt-l = 'focus right'
        alt-left  = 'focus left'
        alt-down  = 'focus down'
        alt-up    = 'focus up'
        alt-right = 'focus right'

        # Move window
        alt-shift-h = 'move left'
        alt-shift-j = 'move down'
        alt-shift-k = 'move up'
        alt-shift-l = 'move right'
        alt-shift-left  = 'move left'
        alt-shift-down  = 'move down'
        alt-shift-up    = 'move up'
        alt-shift-right = 'move right'

        # Recent / back-and-forth
        alt-tab = 'workspace-back-and-forth'

        # Fullscreen
        alt-enter = 'fullscreen'

        # Balance / resize
        alt-b = 'balance-sizes'
        alt-minus = 'resize smart -50'
        alt-equal = 'resize smart +50'

        # Float toggle (service mode)
        alt-f = ['mode service']
        alt-g = ['exec-and-forget open -a Ghostty']

        # ── niri-style: column operations ─────────────────────────
        # join focused window with neighbor into one container (niri's
        # consumeWindowIntoColumn equivalent — merge into a stack).
        # NOTE: 'split' is disabled — it conflicts with
        # enable-normalization-flatten-containers (aerospace warns).
        alt-s = ['mode service']

        # Toggle accordion (focused-column-zoom) vs tiles (flat grid)
        alt-comma = 'layout accordion horizontal vertical'
        alt-slash = 'layout tiles horizontal vertical'

    # ── Service mode (temporary, for operations needing one key) ──
    [mode.service.binding]
        esc = ['reload-config', 'mode main']
        f = ['layout floating tiling', 'mode main']   # toggle float/tile
        r = ['flatten-workspace-tree', 'mode main']   # reset layout
        t = ['layout tiles horizontal vertical', 'mode main']  # toggle split dir
        backspace = ['close-all-windows-but-current', 'mode main']
        # niri-style column ops: join window into neighbor container
        # (consumeWindowIntoColumn ≈ join-with; expel ≈ move out)
        s = ['mode main']
        h = ['join-with left', 'mode main']
        j = ['join-with down', 'mode main']
        k = ['join-with up', 'mode main']
        l = ['join-with right', 'mode main']
  '';
in {
  environment.systemPackages = [pkgs.aerospace];

  # Write config to ~/.config/aerospace/aerospace.toml
  # (nix-darwin only runs PREDEFINED activation script names; extraActivation
  #  runs as root → absolute path + chown)
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    install -d -m 0755 -o ${shared.username} -g staff ${shared.home}/.config/aerospace
    rm -f ${shared.home}/.config/aerospace/aerospace.toml
    install -m 0644 -o ${shared.username} -g staff ${aeroCfg} ${shared.home}/.config/aerospace/aerospace.toml
  '';

  launchd.user.agents.aerospace = {
    serviceConfig = {
      ProgramArguments = ["${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/aerospace.log";
      StandardErrorPath = "/tmp/aerospace.log";
    };
  };
}
