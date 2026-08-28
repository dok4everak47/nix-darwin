{
  description = "Elm 0.19 project";

  # The nix-darwin system profile already ships elm-format / elm-test-rs /
  # elm-review / elm-language-server globally (modules/programs/elm.nix) but
  # intentionally NOT the elm compiler, to avoid version clashes. This shell
  # provides the compiler so a project pins its own 0.19 toolchain.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = {self, nixpkgs}: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forEach = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forEach (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          elmPackages.elm
          elmPackages.elm-format
          elmPackages.elm-test-rs
          elmPackages.elm-review
        ];
        shellHook = ''
          echo "🌳 Elm $(elm --version)"
        '';
      };
    });
  };
}
