{
  description = "dok4ever-mac nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  {
    # Build darwin flake using:
    # $ darwin-rebuild switch --flake .#dok4ever-mac
    darwinConfigurations."dok4ever-mac" = nix-darwin.lib.darwinSystem {
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
          home-manager.users.dok4ever = import ./home.nix;
        }
      ];
    };
  };
}
