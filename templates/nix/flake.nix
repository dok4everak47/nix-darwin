{
  description = "Nix project (modules + devShell)";

  # Nix toolchain per the repo's Nix rule: tooling lives in the project
  # devShell, never installed globally. LSP = nil (config in nvim).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = {self, nixpkgs}: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forEach = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forEach (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [nixpkgs-fmt statix deadnix nil];
        shellHook = ''
          # ClashBar proxy on 127.0.0.1:7890 -- exported only while it is
          # listening, so a dead proxy never breaks the shell's network.
          if (echo > /dev/tcp/127.0.0.1/7890) 2>/dev/null; then
            export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
            export HTTP_PROXY=http://127.0.0.1:7890 HTTPS_PROXY=http://127.0.0.1:7890
            export all_proxy=socks5://127.0.0.1:7890 ALL_PROXY=socks5://127.0.0.1:7890
            export no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1
          fi
          echo "❄️ Nix $(nix --version) | fmt $(nixpkgs-fmt --version) | nil $(nil --version)"
        '';
      };
    });
  };
}
