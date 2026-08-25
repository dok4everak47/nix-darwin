{
  config,
  lib,
  pkgs,
  areofyl-fetch,
  ...
}: let
  shared = import ../lib.nix {};

  # Replicate the upstream home-manager module's config generator:
  # https://github.com/areofyl/fetch/blob/5297ad4/nix/home-module.nix
  #
  # info fields, one per line (no key=value prefix), followed by key=value
  # settings for non-null options. `toString 1.0` → "1" (matches HM).
  cfg = {
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
    labelColor = "magenta";
    separator = "-";
    shading = null;
    light = null;
    spin = "xy";
    speed = 1.0;
    size = null;
    height = null;
  };

  settingLines = lib.mapAttrsToList (key: value: "${key}=${value}") (
    lib.filterAttrs (_: value: value != null) {
      label_color = cfg.labelColor;
      separator = cfg.separator;
      shading = cfg.shading;
      light = cfg.light;
      spin = cfg.spin;
      speed =
        if cfg.speed != null
        then toString cfg.speed
        else null;
      size =
        if cfg.size != null
        then toString cfg.size
        else null;
      height =
        if cfg.height != null
        then toString cfg.height
        else null;
    }
  );

  fetchConfig = pkgs.writeText "fetch-config" (
    lib.concatStringsSep "\n" (cfg.info ++ settingLines) + "\n"
  );

  fetchPkg = areofyl-fetch.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  # ── fetch binary (was home.packages via HM module) ──────────────────
  environment.systemPackages = [fetchPkg];

  # ── ~/.config/fetch/config ──────────────────────────────────────────
  # nix-darwin activation runs as root. There is no user-activation
  # surface any more (removed in nix-darwin ≥ 2024), so create the XDG
  # config path as root and chown to the primary user.
  system.activationScripts.fetch = {
    # Run after /etc is materialised but before the final symlink swap.
    deps = ["etc"];
    text = ''
      install -d -m 0755 -o ${shared.username} -g staff ${shared.home}/.config
      install -d -m 0755 -o ${shared.username} -g staff ${shared.home}/.config/fetch
      # `install` follows symlinks (would try to write into the read-only
      # nix-store target of the old HM link). Remove any existing file or
      # symlink first, then install a fresh regular file.
      rm -f ${shared.home}/.config/fetch/config
      install -m 0644 -o ${shared.username} -g staff ${fetchConfig} ${shared.home}/.config/fetch/config
    '';
  };
}
