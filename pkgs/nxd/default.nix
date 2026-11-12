{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "nxd";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "ASCII TUI control deck for the nix-darwin config at /etc/nix-darwin";
    mainProgram = "nxd";
    platforms = lib.platforms.darwin;
    license = lib.licenses.mit;
  };
}
