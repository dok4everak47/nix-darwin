{
  description = "Node.js project (pnpm)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = {self, nixpkgs}: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forEach = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forEach (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [nodejs_22 pnpm];
        shellHook = ''
          echo "🟢 Node $(node --version) | pnpm $(pnpm --version)"
        '';
      };
    });
  };
}
