{ config, pkgs, ... }:

{
  # Unlock encrypted Nix Store APFS volume at boot (darwin-store).
  # NOTE: must NOT use `command` — nix-darwin wraps `command` with
  # "/bin/wait4path /nix/store && exec", which deadlocks here (the volume
  # must be unlocked BEFORE /nix/store exists). Use ProgramArguments
  # directly so the unlock runs immediately at boot.
  launchd.daemons.darwin-store = {
    serviceConfig.RunAtLoad = true;
    serviceConfig.Label = "org.nixos.darwin-store";
    serviceConfig.ProgramArguments = [
      "/bin/sh"
      "-c"
      "security find-generic-password -s '59D4BE45-2C6C-45E8-BD4F-FD963AFE97D9' -w | diskutil apfs unlockVolume '59D4BE45-2C6C-45E8-BD4F-FD963AFE97D9' -mountpoint '/nix' -stdinpassphrase"
    ];
  };
}
