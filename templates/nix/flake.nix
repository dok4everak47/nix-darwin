{
  description = "Nix project (modules + devShell)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = {self, nixpkgs}: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forEach = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forEach (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        # Nix toolchain per the repo's Nix rule: tooling lives in the project
        # devShell, never installed globally. LSP = nil (config in nvim).
        packages = with pkgs; [nixpkgs-fmt statix deadnix nil];
        shellHook = ''
          echo "❄️ Nix $(nix --version) | fmt $(nixpkgs-fmt --version) | nil $(nil --version)"
        '';
      };
    });
  };
}
