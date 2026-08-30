# yabai — tiling window manager (community fork asmvik/yabai 7.1.25).
#
# NOTE: yabai is NOT managed by a nix-darwin built-in module (checked 2026-08-30,
# rev c3e90c8 → modules/services/yabai.nix is 404). We ship our own LaunchAgent.
#
# Requirements (user must do once):
#   1. Partial SIP disable (Apple Silicon, recovery mode) for space/display
#      features. See: https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection-for-yabai
#      csrutil enable --without fs --without debug --without nvram
#   2. Grant Accessibility permission to yabai (System Settings → Privacy &
#      Security → Accessibility), then restart yabai.
#
# yabai needs the macOS scripting addition to control spaces/displays. We
# declare the config in ~/.config/yabai/yabairc (written by activation below)
# so the user can edit it without rebuilds.
{
  config,
  lib,
  pkgs,
  ...
}: let
  shared = import ../lib.nix {};

  yabaiCfg = pkgs.writeText "yabairc" ''
    # ── yabai configuration (managed by nix-darwin; edit via yabai -m) ──
    # Layout: bsp (binary space partitioning)
    yabai -m config layout bsp

    # Window placement
    yabai -m config window_placement second_child

    # Gaps (px)
    yabai -m config top_padding 8
    yabai -m config bottom_padding 8
    yabai -m config left_padding 8
    yabai -m config right_padding 8
    yabai -m config window_gap 8

    # Mouse
    yabai -m config mouse_follows_focus off
    yabai -m config focus_follows_mouse off
    yabai -m config mouse_modifier alt
    yabai -m config mouse_action1 move
    yabai -m config mouse_action2 resize

    # Status bar (sketchybar handles this)
    yabai -m config status_bar off

    # Auto balance
    yabai -m config auto_balance off

    # Focus follows window on space change
    yabai -m config focus_follows_window off

    # Rules: float some apps
    yabai -m rule --add app="^System Settings$" manage=off
    yabai -m rule --add app="^Calculator$" manage=off
    yabai -m rule --add app="^Archive Utility$" manage=off
    yabai -m rule --add app="^Software Update$" manage=off
    yabai -m rule --add app="^Finder$" manage=off
    yabai -m rule --add app="^iTerm2$" manage=off
    yabai -m rule --add app="^Ghostty$" manage=off
    yabai -m rule --add app="^OmniWM$" manage=off
    yabai -m rule --add app="^Mos$" manage=off
  '';
in {
  environment.systemPackages = [pkgs.yabai];

  # Write yabairc to ~/.config/yabai/ so the user can tweak without rebuild.
  # nix-darwin only executes PREDEFINED activation script names
  # (extraActivation/postActivation/...); custom names are silently ignored.
  # extraActivation runs as root → use absolute path + chown.
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    install -d -m 0755 -o ${shared.username} -g staff ${shared.home}/.config/yabai
    rm -f ${shared.home}/.config/yabai/yabairc
    install -m 0755 -o ${shared.username} -g staff ${yabaiCfg} ${shared.home}/.config/yabai/yabairc
  '';

  launchd.user.agents.yabai = {
    serviceConfig = {
      ProgramArguments = ["${pkgs.yabai}/bin/yabai"];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/yabai.log";
      StandardErrorPath = "/tmp/yabai.log";
    };
  };
}
