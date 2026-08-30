# sketchybar — highly customizable macOS status bar replacement (2.23.0).
#
# No nix-darwin built-in module exists; we ship our own LaunchAgent + config.
#
# Requirements:
#   1. Screen Recording permission (System Settings → Privacy & Security →
#      Screen Recording) for sketchybar to read window titles / show full bar.
#   2. Restart sketchybar after granting.
#
# Config lives in ~/.config/sketchybar/ (written at activation time from the
# nix store). Edit files there directly for quick tweaks; rebuild to restore.
{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};

  # ── sketchybarrc — main bar config (shell syntax, 2.x compatible) ──
  sketchybarrc = pkgs.writeText "sketchybarrc" ''
    #!/usr/bin/env sh

    # launchd PATH is minimal (/usr/bin:/bin:...); add nix system profile so
    # `sketchybar` invocations resolve.
    export PATH="/run/current-system/sw/bin:$PATH"

    # ── Bar appearance ──────────────────────────────────────────────
    # y_offset=0: system menu bar is hidden (_HIHideMenuBar=true), so the
    # bar sits flush at the very top. Items stay clear of the MacBook
    # Pro notch via notch_width below (main display = external 4K, no
    # notch, so 0 is fine; adjust if bar moves to the built-in display).
    sketchybar --bar height=32 position=top padding_left=8 padding_right=8 color=0xEE1E1E2E margin=0 corner_radius=12 y_offset=0

    # ── Global colors ───────────────────────────────────────────────
    export BAR_COLOR=0xEE1E1E2E
    export ITEM_BG_COLOR=0xFF313244
    export ACCENT_COLOR=0xFF89B4FA
    export TEXT_COLOR=0xFFCDD6F4
    export ICON_COLOR=0xFFA6ADC8

    # ── Default item properties ─────────────────────────────────────
    sketchybar --default \
      icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
      label.font="JetBrainsMono Nerd Font:Medium:12.0" \
      icon.color="$ICON_COLOR" \
      label.color="$TEXT_COLOR" \
      background.color="$ITEM_BG_COLOR" \
      background.height=24 \
      background.corner_radius=8 \
      background.padding_left=4 \
      background.padding_right=4 \
      icon.padding_left=6 \
      icon.padding_right=2 \
      label.padding_left=2 \
      label.padding_right=6

    # ── Items: left = app name + date, right = battery + wifi ───────
    sketchybar --add item app_name left
    sketchybar --add item date right
    sketchybar --add item time right
    sketchybar --add item battery right

    # App name (frontmost app)
    sketchybar --set app_name \
      icon=󰀨 \
      label="" \
      script="$CONFIG_DIR/plugins/app_name.sh" \
      --subscribe app_name front_app_switched

    # Date
    sketchybar --set date \
      icon= \
      label="$(date '+%a %d')" \
      update_freq=60 \
      --add event date_change "0 * * * *" \
      --subscribe date date_change

    # Time
    sketchybar --set time \
      icon=󰥔 \
      label="$(date '+%H:%M')" \
      update_freq=30 \
      --add event time_change "0,30 * * * *" \
      --subscribe time time_change

    # Battery
    sketchybar --set battery \
      icon=󰁹 \
      label="" \
      script="$CONFIG_DIR/plugins/battery.sh" \
      update_freq=120 \
      --subscribe battery system_woke power_source_change
  '';

  # ── Plugins (event scripts) ──────────────────────────────────────
  appNameScript = pkgs.writeShellScript "app_name.sh" ''
    #!/usr/bin/env sh
    export PATH="/run/current-system/sw/bin:$PATH"
    sketchybar --set app_name label="$INFO"
  '';

  batteryScript = pkgs.writeShellScript "battery.sh" ''
    #!/usr/bin/env sh
    export PATH="/run/current-system/sw/bin:$PATH"
    source "$CONFIG_DIR/colors.sh"

    PERCENTAGE=$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
    CHARGING=$(pmset -g batt | grep -c 'AC Power')

    if [ "$CHARGING" -eq 1 ]; then
      ICON="󰂄"
    elif [ "$PERCENTAGE" -ge 80 ]; then
      ICON="󰁹"
    elif [ "$PERCENTAGE" -ge 60 ]; then
      ICON="󰂀"
    elif [ "$PERCENTAGE" -ge 40 ]; then
      ICON="󰁿"
    elif [ "$PERCENTAGE" -ge 20 ]; then
      ICON="󰁾"
    else
      ICON="󰁻"
    fi

    sketchybar --set battery icon="$ICON" label="$PERCENTAGE%"
  '';

  # ── colors.sh — shared color vars for plugins ─────────────────────
  colorsSh = pkgs.writeText "colors.sh" ''
    export BAR_COLOR=0xEE1E1E2E
    export ITEM_BG_COLOR=0xFF313244
    export ACCENT_COLOR=0xFF89B4FA
    export TEXT_COLOR=0xFFCDD6F4
    export ICON_COLOR=0xFFA6ADC8
  '';
in {
  environment.systemPackages = [pkgs.sketchybar];

  # Write config dir at activation so user can edit without rebuild.
  # nix-darwin only executes PREDEFINED activation script names; use
  # extraActivation (runs as root → absolute path + chown).
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    # Hide the macOS system menu bar (SketchyBar replaces it).
    # _HIHideMenuBar requires logout/login (or reboot) to fully take effect.
    defaults write NSGlobalDomain _HIHideMenuBar -bool true || true

    CONFIG_DIR=${shared.home}/.config/sketchybar
    PLUGIN_DIR=$CONFIG_DIR/plugins
    install -d -m 0755 -o ${shared.username} -g staff "$CONFIG_DIR" "$PLUGIN_DIR"
    rm -f "$CONFIG_DIR"/sketchybarrc "$CONFIG_DIR"/colors.sh "$PLUGIN_DIR"/*.sh
    install -m 0755 -o ${shared.username} -g staff ${sketchybarrc} "$CONFIG_DIR/sketchybarrc"
    install -m 0644 -o ${shared.username} -g staff ${colorsSh} "$CONFIG_DIR/colors.sh"
    install -m 0755 -o ${shared.username} -g staff ${appNameScript} "$PLUGIN_DIR/app_name.sh"
    install -m 0755 -o ${shared.username} -g staff ${batteryScript} "$PLUGIN_DIR/battery.sh"
  '';

  launchd.user.agents.sketchybar = {
    serviceConfig = {
      ProgramArguments = ["${pkgs.sketchybar}/bin/sketchybar"];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/sketchybar.log";
      StandardErrorPath = "/tmp/sketchybar.log";
    };
  };
}
