{ config, pkgs, ... }:

{
  # Enable direnv + nix-direnv (use flake support)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
