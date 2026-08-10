{ config, pkgs, ... }:

{
  # Declare the macOS user so home-manager's common.nix can resolve
  # home.homeDirectory / uid from users.users instead of getting null.
  users.users.dok4ever = {
    name = "dok4ever";
    home = "/Users/dok4ever";
  };
}
