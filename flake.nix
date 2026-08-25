{
  description = "dok4ever-mac nix-darwin configuration";

  inputs = {
    # Pin to stable release branches (2026-08, per nixos-and-flakes.thiscute.world
    # best practices: avoid floating master/unstable inputs).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    # atuin needs >= 18.16 (2026-07-09 "shell" migration); stable 26.05 only has 18.15.2.
    # Pin to rev 6f6fca05 = atuin 18.17.1 (last version before 18.18's
    # "duplicate column: shell" migration bug on an already-migrated db).
    # 18.17.1 is patched for search bug #3908 in modules/overlays/default.nix.
    unstable.url = "github:NixOS/nixpkgs/6f6fca055bb8d39ccd3e3be1e27d8b58b9a442d1";

    # fetch (animated 3D fetch tool) -- https://github.com/areofyl/fetch
    # Pinned to rev 5297ad4 (HEAD as of 2026-08-21). Upstream flake uses
    # nixos-unstable; follow our nixpkgs to avoid pulling a second copy.
    areofyl-fetch.url = "github:areofyl/fetch/5297ad46acf2afb676ddc56aa8f278bd591fb9e6";
    areofyl-fetch.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    unstable,
    areofyl-fetch,
  }: {
    # Build darwin flake using:
    # $ darwin-rebuild switch --flake .#dok4ever-mac
    darwinConfigurations."dok4ever-mac" = nix-darwin.lib.darwinSystem {
      # Pass `inputs` to all modules so they can access overlay/input attrs.
      specialArgs = {
        # Only expose what modules actually consume, not the whole input set:
        #   - unstable  → overlays (atuin 18.17.1)
        #   - areofyl-fetch → programs/fetch.nix
        inherit unstable;
        areofyl-fetch = inputs.areofyl-fetch;
      };

      modules = [
        # All sub-modules are aggregated in modules/default.nix
        # (overlays → system → shell → programs → fixes). The custom-icons
        # module lives at modules/system/custom-icons.nix (vendored from
        # ryanccn/nix-darwin-custom-icons, rev ad3e8cf).
        ./modules

        # Set Git commit hash for darwin-version (needs `self`, so lives here).
        {system.configurationRevision = self.rev or self.dirtyRev or null;}
      ];
    };
  };
}
