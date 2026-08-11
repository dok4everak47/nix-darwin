{
  description = "dok4ever-mac nix-darwin configuration";

  inputs = {
    # Pin to stable release branches (2026-08, per nixos-and-flakes.thiscute.world
    # best practices: avoid floating master/unstable inputs).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # atuin needs >= 18.16 (2026-07-09 "shell" migration); stable 26.05 only has 18.15.2.
    unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, unstable }:
  {
    # Build darwin flake using:
    # $ darwin-rebuild switch --flake .#dok4ever-mac
    darwinConfigurations."dok4ever-mac" = nix-darwin.lib.darwinSystem {
      # Pass `inputs` to all modules so they can access overlay/input attrs.
      specialArgs = { inherit inputs; };

      modules = [
        ./modules/direnv.nix
        ./modules/users.nix
        ./modules/darwin-store.nix
        ./modules/system-packages.nix
        ./modules/nix-settings.nix
        ./modules/activation.nix

        # Set Git commit hash for darwin-version (needs `self`, so lives here).
        { system.configurationRevision = self.rev or self.dirtyRev or null; }

        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          # Pass `inputs` to home-manager modules too.
          home-manager.extraSpecialArgs = { inherit inputs unstable; };
          home-manager.users.dok4ever = import ./home.nix;
        }
      ];
    };
  };
}