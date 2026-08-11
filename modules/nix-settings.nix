{ config, pkgs, ... }:

{
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Allow dok4ever to specify trusted-public-keys (needed for USTC cache).
  nix.settings.trusted-users = [ "root" "dok4ever" ];

  # ── Binary cache: USTC mirror (faster in CN than cache.nixos.org) ──
  # Keys from https://mirrors.ustc.edu.cn/nix-channels/store
  nix.settings.substituters = [
    "https://mirrors.ustc.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjU="
  ];

  # ── Auto GC: keep /nix/store bounded (encrypted APFS volume is small) ──
  # Per nixos-and-flakes.thiscute.world "Other useful Tips".
  nix.gc = {
    automatic = true;
    interval = { Weekday = 0; Hour = 3; Minute = 0; };  # Sun 03:00
    options = "--delete-older-than 30d";
  };

  # Auto optimise (dedup hardlinks) after each activation.
  nix.optimise.automatic = true;

  # Enable alternative shell support in nix-darwin.
  # programs.fish.enable = true;

  # Used for backwards compatibility, please read the changelog before reading.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}